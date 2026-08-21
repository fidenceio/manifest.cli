#!/bin/bash

# Manifest Time Module
# HTTPS-based trusted timestamp service. Queries Cloudflare /cdn-cgi/trace
# (sub-second precision via ts= body field) plus HTTP Date header fallbacks
# on Google and Apple — all over port 443, so corporate firewalls don't bite.

MANIFEST_CLI_TIME_TIMEOUT=${MANIFEST_CLI_TIME_TIMEOUT:-5}
MANIFEST_CLI_TIME_RETRIES=${MANIFEST_CLI_TIME_RETRIES:-2}
MANIFEST_CLI_TIME_CACHE_TTL=${MANIFEST_CLI_TIME_CACHE_TTL:-120}
MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD=${MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD:-3600}
MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE=${MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE:-21600}

MANIFEST_CLI_TIME_TIMESTAMP=""
MANIFEST_CLI_TIME_OFFSET=""
MANIFEST_CLI_TIME_UNCERTAINTY=""
MANIFEST_CLI_TIME_SERVER=""
MANIFEST_CLI_TIME_SERVER_IP=""
MANIFEST_CLI_TIME_METHOD=""

_manifest_time_debug() {
    [ "${MANIFEST_CLI_DEBUG:-0}" = "1" ] && echo "   🔍 Debug: $*" >&2
    return 0
}

_manifest_time_cache_dir() {
    local root="${MANIFEST_CLI_CACHE_DIR:-${TMPDIR:-/tmp}/manifest-cli}"
    echo "${root}/time"
}

_manifest_time_cache_file() { echo "$(_manifest_time_cache_dir)/timestamp.cache"; }
_manifest_time_cleanup_marker() { echo "$(_manifest_time_cache_dir)/cleanup.last"; }

_manifest_time_maybe_cleanup_cache() {
    local cache_dir cleanup_marker period now last
    cache_dir=$(_manifest_time_cache_dir)
    cleanup_marker=$(_manifest_time_cleanup_marker)
    period="${MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD:-3600}"
    [[ "$period" =~ ^[0-9]+$ ]] && [ "$period" -ge 60 ] || period=3600

    now=$(date -u +%s)
    last=0
    if [ -f "$cleanup_marker" ]; then
        last=$(tr -d '[:space:]' < "$cleanup_marker" 2>/dev/null || echo 0)
        [[ "$last" =~ ^[0-9]+$ ]] || last=0
    fi
    [ $((now - last)) -lt "$period" ] && return 0

    mkdir -p "$cache_dir" 2>/dev/null || return 0
    find "$cache_dir" -type f -name "*.cache*" -mmin +"$((period / 60))" -delete 2>/dev/null || true
    printf '%s\n' "$now" > "$cleanup_marker" 2>/dev/null || true
}

# Report a refused (malformed) cache. Absence of a cache is an ordinary miss and
# stays at debug level; a cache that exists but cannot be trusted is a PROBLEM,
# and §9.15 forbids letting absent-or-malformed input read as a value — so it is
# announced at warning level instead of being silently coerced into "no cache".
_manifest_time_cache_refuse() {
    local reason="$1" cache_file="$2"
    if declare -F log_warning >/dev/null 2>&1; then
        log_warning "Ignoring malformed trusted-time cache (${reason}): ${cache_file} — re-querying instead."
    else
        echo "   ⚠️  Ignoring malformed trusted-time cache (${reason}): ${cache_file} — re-querying instead." >&2
    fi
    return 1
}

# Parse the time cache.
#   $1 = cache file
#   $2 = name of the caller variable to receive "saved|ts|offset|uncertainty|server|server_ip"
#   $3 = name of the caller variable to receive a short refusal reason
# Returns 0 when the whole file parsed, 1 otherwise. Results travel by nameref
# rather than stdout precisely so the caller does NOT need a command
# substitution — a $(...) subshell would discard the refusal reason.
#
# The cache is PARSED, never sourced. `. "$cache_file"` (the previous
# implementation) meant anything able to write that file — a squatted cache dir,
# a MANIFEST_CLI_CACHE_DIR pointed somewhere hostile — ran arbitrary code inside
# the CLI's own process (§9.22). Parsing is strictly weaker: only the six keys
# the writer emits are accepted, each value must match its declared shape, and
# ANY other line refuses the whole file. Refusing whole-file rather than
# per-line is deliberate: a cache with an unexplained line is a cache of unknown
# provenance, and a partially-trusted timestamp is worse than a fresh fetch.
_manifest_time_cache_parse() {
    local cache_file="$1"
    local -n _out_ref="$2"
    local -n _reason_ref="$3"
    local line key value
    local saved="" ts="" offset="" uncertainty="" server="" server_ip=""
    _out_ref=""
    _reason_ref=""

    while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        if [[ "$line" != *=* ]]; then
            _reason_ref="line is not KEY=value"
            return 1
        fi
        key="${line%%=*}"
        value="${line#*=}"
        # `|` is the field separator of this module's own wire format, so a
        # value carrying one would silently shift every downstream field.
        if [[ "$value" == *"|"* ]]; then
            _reason_ref="value for ${key} contains a field separator"
            return 1
        fi
        case "$key" in
            MANIFEST_CLI_TIME_CACHE_SAVED_AT)
                [[ "$value" =~ ^[0-9]{1,19}$ ]] || { _reason_ref="bad saved_at"; return 1; }
                saved="$value" ;;
            MANIFEST_CLI_TIME_CACHE_TIMESTAMP)
                [[ "$value" =~ ^[0-9]{1,19}$ ]] || { _reason_ref="bad timestamp"; return 1; }
                ts="$value" ;;
            MANIFEST_CLI_TIME_CACHE_OFFSET)
                [[ "$value" =~ ^[+-]?[0-9]{1,19}(\.[0-9]{1,9})?$ ]] \
                    || { _reason_ref="bad offset"; return 1; }
                offset="$value" ;;
            MANIFEST_CLI_TIME_CACHE_UNCERTAINTY)
                [[ "$value" =~ ^[+-]?[0-9]{1,19}(\.[0-9]{1,9})?$ ]] \
                    || { _reason_ref="bad uncertainty"; return 1; }
                uncertainty="$value" ;;
            MANIFEST_CLI_TIME_CACHE_SERVER)
                # A URL or a short token. Empty is tolerated (the reader
                # substitutes a default), anything with whitespace or a control
                # character is not. The length bound is a separate test, NOT a
                # regex interval: bash's ERE caps a repetition at 255, so
                # `{1,512}` is a hard regex ERROR (not a non-match) and refused
                # every cache it was asked about — caught by the release gate.
                [ -z "$value" ] || { [ "${#value}" -le 512 ] && [[ "$value" =~ ^[[:graph:]]+$ ]]; } \
                    || { _reason_ref="bad server"; return 1; }
                server="$value" ;;
            MANIFEST_CLI_TIME_CACHE_SERVER_IP)
                [ -z "$value" ] || [[ "$value" =~ ^[0-9a-fA-F.:]{1,45}$ ]] \
                    || { _reason_ref="bad server_ip"; return 1; }
                server_ip="$value" ;;
            *)
                _reason_ref="unexpected key ${key}"
                return 1 ;;
        esac
    done < "$cache_file"

    # A cache without both epochs cannot be aged, so it is not a cache. This
    # also catches the truncated-write case (an empty or half-written file),
    # which the sourcing version turned into saved_at=0 and a silent TTL miss.
    [ -n "$saved" ] || { _reason_ref="missing saved_at"; return 1; }
    [ -n "$ts" ]    || { _reason_ref="missing timestamp"; return 1; }

    printf -v _out_ref '%s|%s|%s|%s|%s|%s' \
        "$saved" "$ts" "$offset" "$uncertainty" "$server" "$server_ip"
}

# Read cache. Mode "fresh" honors TTL; "stale" honors STALE_MAX_AGE.
# Echoes: timestamp|offset|uncertainty|server|server_ip|method
_manifest_time_read_cache_data() {
    local mode="${1:-fresh}"
    local cache_file
    cache_file=$(_manifest_time_cache_file)
    [ -f "$cache_file" ] || return 1

    local parsed="" reason=""
    if ! _manifest_time_cache_parse "$cache_file" parsed reason; then
        _manifest_time_cache_refuse "${reason:-unparseable}" "$cache_file"
        return 1
    fi

    local now saved ts offset uncertainty server server_ip
    IFS='|' read -r saved ts offset uncertainty server server_ip <<< "$parsed"
    now=$(date -u +%s)

    local age=$((now - saved))
    [ "$age" -lt 0 ] && return 1

    local max_age method
    case "$mode" in
        fresh) max_age="${MANIFEST_CLI_TIME_CACHE_TTL:-120}";       method="cache" ;;
        stale) max_age="${MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE:-21600}"; method="cache-stale" ;;
        *)     return 1 ;;
    esac
    [[ "$max_age" =~ ^[0-9]+$ ]] && [ "$max_age" -ge 1 ] || return 1
    [ "$age" -gt "$max_age" ] && return 1

    echo "$((ts + age))|${offset:-0.000000}|${uncertainty:-0.000000}|${server:-cache}|${server_ip:-127.0.0.1}|${method}"
}

_manifest_time_write_cache_data() {
    local timestamp="$1" offset="$2" uncertainty="$3" server="$4" server_ip="$5"
    [ -n "$timestamp" ] || return 1
    local cache_dir cache_file now
    cache_dir=$(_manifest_time_cache_dir)
    cache_file=$(_manifest_time_cache_file)
    mkdir -p "$cache_dir" 2>/dev/null || return 1
    now=$(date -u +%s)
    # umask 077 goes INSIDE a subshell so the tight mode applies to this write
    # and nothing else. At function scope (§9.22) it leaked process-wide: every
    # file the same manifest process created afterwards — generated docs, the
    # CHANGELOG, user-facing output — inherited 0600. Same subshell pattern as
    # the audit log in manifest-shared-utils.sh; the cache itself must stay
    # 0600, which is what the umask is here for.
    (
        umask 077
        {
            echo "MANIFEST_CLI_TIME_CACHE_SAVED_AT=${now}"
            echo "MANIFEST_CLI_TIME_CACHE_TIMESTAMP=${timestamp}"
            echo "MANIFEST_CLI_TIME_CACHE_OFFSET=${offset}"
            echo "MANIFEST_CLI_TIME_CACHE_UNCERTAINTY=${uncertainty}"
            echo "MANIFEST_CLI_TIME_CACHE_SERVER=${server}"
            echo "MANIFEST_CLI_TIME_CACHE_SERVER_IP=${server_ip}"
        } > "$cache_file"
    ) 2>/dev/null || return 1
    # A cache file that pre-existed 0644 keeps its old mode through a truncating
    # redirect, so repair it — same reason the audit writer chmods after mkdir.
    chmod 600 "$cache_file" 2>/dev/null || true
}

# Effective server list from MANIFEST_CLI_TIME_SERVER1..4, or defaults.
_manifest_time_effective_servers() {
    local servers=() i value
    for i in 1 2 3 4; do
        local var="MANIFEST_CLI_TIME_SERVER$i"
        value="${!var:-}"
        [ -n "$value" ] && servers+=("$value")
    done
    if [ ${#servers[@]} -eq 0 ]; then
        servers=(
            "https://www.cloudflare.com/cdn-cgi/trace"
            "https://www.google.com/generate_204"
            "https://www.apple.com"
        )
    fi
    printf '%s\n' "${servers[@]}"
}

# Parse RFC 7231 HTTP Date header into Unix epoch. Tries GNU date, then BSD date.
_parse_http_date() {
    local s="$1" epoch
    epoch=$(date -u -d "$s" +%s 2>/dev/null) && { echo "$epoch"; return 0; }
    epoch=$(date -u -jf "%a, %d %b %Y %H:%M:%S GMT" "$s" +%s 2>/dev/null) && { echo "$epoch"; return 0; }
    return 1
}

# Query a single HTTPS endpoint. Echoes "offset|uncertainty|server_ip" on success.
query_time_server() {
    local server="$1" timeout="$2"
    [[ "$server" == http://* || "$server" == https://* ]] || server="https://$server"

    local is_cf=false
    [[ "$server" == *"/cdn-cgi/trace"* ]] && is_cf=true

    local t_before t_after server_epoch="" server_ip="" fractional="000000"
    t_before=$(date -u +%s)

    if $is_cf; then
        local response meta http_code ts_value ts_line
        response=$(curl -s --connect-timeout "$timeout" --max-time "$timeout" \
            -w $'\n'"__META__|%{http_code}|%{remote_ip}" "$server" 2>&1) || {
            _manifest_time_debug "Cloudflare curl failed: $response"; return 1; }
        meta=$(echo "$response" | grep "^__META__" | tail -1)
        IFS='|' read -r _ http_code server_ip <<< "$meta"
        [ -z "$http_code" ] || [ "$http_code" = "000" ] && return 1

        ts_line=$(echo "$response" | grep -E "^ts=" | head -1)
        ts_value="${ts_line#ts=}"
        [[ "$ts_value" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
        server_epoch="${ts_value%%.*}"
        if [[ "$ts_value" == *.* ]]; then
            fractional="${ts_value#*.}000000"
            fractional="${fractional:0:6}"
        fi
    else
        local out http_code date_header
        out=$(curl -sI --connect-timeout "$timeout" --max-time "$timeout" \
            -o /dev/null -w "%{http_code}|%header{date}|%{remote_ip}" "$server" 2>&1) || {
            _manifest_time_debug "HEAD curl failed: $out"; return 1; }
        IFS='|' read -r http_code date_header server_ip <<< "$out"
        [ -z "$http_code" ] || [ "$http_code" = "000" ] && return 1
        [ -n "$date_header" ] || return 1
        server_epoch=$(_parse_http_date "$date_header") || return 1
    fi

    [[ "$server_epoch" =~ ^[0-9]+$ ]] || return 1

    t_after=$(date -u +%s)
    local rtt=$((t_after - t_before))
    local mid=$((t_before + rtt / 2))
    local offset=$((mid - server_epoch))
    local offset_str
    if [ "$offset" -ge 0 ]; then offset_str="+${offset}.${fractional}"
    else                         offset_str="${offset}.${fractional}"; fi

    local rtt_half=$((rtt / 2))
    [ "$rtt_half" -lt 1 ] && rtt_half=1
    local uncertainty_str="${rtt_half}.000000"
    if $is_cf && [ "$rtt" -lt 2 ]; then
        uncertainty_str="0.${fractional:-500000}"
    fi

    _manifest_time_debug "server_epoch=$server_epoch mid=$mid offset=$offset_str rtt=${rtt}s ip=$server_ip"
    echo "${offset_str}|${uncertainty_str}|${server_ip}"
}

# Compute corrected timestamp = system_time - integer_part_of_offset.
# Offset format from query_time_server is signed decimal (+/-N.frac).
_manifest_time_apply_offset() {
    local offset="$1" system_time
    system_time=$(date -u +%s)
    if [[ "$offset" =~ ^[+-]?([0-9]+)(\.[0-9]+)?$ ]]; then
        local sign="${offset:0:1}" mag="${BASH_REMATCH[1]}"
        if [ "$sign" = "-" ]; then echo $((system_time + mag))
        else                       echo $((system_time - mag)); fi
    else
        echo "$system_time"
    fi
}

_manifest_time_export() {
    export MANIFEST_CLI_TIME_TIMESTAMP="$1"
    export MANIFEST_CLI_TIME_OFFSET="$2"
    export MANIFEST_CLI_TIME_UNCERTAINTY="$3"
    export MANIFEST_CLI_TIME_SERVER="$4"
    export MANIFEST_CLI_TIME_SERVER_IP="$5"
    export MANIFEST_CLI_TIME_METHOD="$6"
}

_manifest_time_print_result() {
    local tz formatted
    tz=$(get_timezone_display "$MANIFEST_CLI_TIME_TIMESTAMP")
    formatted=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S')
    echo "   🕐 Timestamp: $formatted $tz"
    echo "   🎯 Method: $MANIFEST_CLI_TIME_METHOD"
    echo ""
}

# Public: populate MANIFEST_CLI_TIME_* from cache, HTTPS query, stale cache, or system clock.
get_time_timestamp() {
    echo "🕐 Getting trusted timestamp..."
    _manifest_time_maybe_cleanup_cache
    command -v _manifest_runtime_maybe_cleanup_cache >/dev/null 2>&1 \
        && _manifest_runtime_maybe_cleanup_cache

    local cached
    if cached=$(_manifest_time_read_cache_data "fresh"); then
        IFS='|' read -r t off unc srv ip meth <<< "$cached"
        _manifest_time_export "$t" "$off" "$unc" "$srv" "$ip" "$meth"
        echo "   ⚡ Using cached trusted timestamp"
        echo "   📊 Offset: $off seconds (±$unc)"
        _manifest_time_print_result
        return 0
    fi

    local servers=() s
    while IFS= read -r s; do [ -n "$s" ] && servers+=("$s"); done < <(_manifest_time_effective_servers)

    local retries="${MANIFEST_CLI_TIME_RETRIES:-1}"
    [[ "$retries" =~ ^[0-9]+$ ]] && [ "$retries" -ge 1 ] || retries=1

    local server result attempt
    for server in "${servers[@]}"; do
        attempt=1
        while [ "$attempt" -le "$retries" ]; do
            if [ "$retries" -gt 1 ]; then
                echo "   🔍 Querying $server (attempt $attempt/$retries)..."
            else
                echo "   🔍 Querying $server..."
            fi
            if result=$(query_time_server "$server" "$MANIFEST_CLI_TIME_TIMEOUT") && [ -n "$result" ]; then
                local off unc ip ts
                IFS='|' read -r off unc ip <<< "$result"
                ts=$(_manifest_time_apply_offset "$off")
                _manifest_time_write_cache_data "$ts" "$off" "$unc" "$server" "$ip" || true
                _manifest_time_export "$ts" "$off" "$unc" "$server" "$ip" "https"
                echo "   ✅ Trusted timestamp from $server"
                echo "   📊 Offset: $off seconds (±$unc)"
                _manifest_time_print_result
                return 0
            fi
            [ "$attempt" -lt "$retries" ] \
                && echo "   ⚠️  Failed to query $server; retrying..." \
                || echo "   ⚠️  Failed to query $server"
            attempt=$((attempt + 1))
        done
    done

    if cached=$(_manifest_time_read_cache_data "stale"); then
        IFS='|' read -r t off unc srv ip meth <<< "$cached"
        _manifest_time_export "$t" "$off" "$unc" "$srv" "$ip" "$meth"
        echo "   🔄 No live HTTPS response; using stale trusted cache"
        echo "   📊 Offset: $off seconds (±$unc)"
    else
        _manifest_time_export "$(date -u +%s)" "0.000000" "0.000000" "system" "127.0.0.1" "system"
        echo "   🔄 No time servers responded, using system time"
    fi
    _manifest_time_print_result
}

# Public: cross-platform timestamp formatter (delegates to manifest-os.sh).
format_timestamp() {
    format_timestamp_cross_platform "$1" "$2"
}

# Public: human-readable status, used by `manifest doctor` / display flow.
display_time_info() {
    echo "🕐 Manifest Timestamp Service"
    echo "============================="
    get_time_timestamp
    echo "📊 Timestamp Details:"
    local tz
    tz=$(get_timezone_display "$MANIFEST_CLI_TIME_TIMESTAMP")
    echo "   🕐 Time: $(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S') $tz"
    echo "   📊 Offset: $MANIFEST_CLI_TIME_OFFSET seconds"
    echo "   🎯 Uncertainty: ±$MANIFEST_CLI_TIME_UNCERTAINTY seconds"
    echo "   🌐 Source: $MANIFEST_CLI_TIME_SERVER ($MANIFEST_CLI_TIME_SERVER_IP)"
    echo "   🔧 Method: $MANIFEST_CLI_TIME_METHOD"
    echo ""
    echo "💡 This timestamp is ready for manifest operations"
}

# Public: `manifest config time` output.
display_time_config() {
    echo "⚙️  Manifest Timestamp Configuration"
    echo "===================================="
    echo "   🖥️  OS: $MANIFEST_CLI_OS_OS"
    echo "   ⏱️  Timeout: ${MANIFEST_CLI_TIME_TIMEOUT}s"
    echo "   🔄 Retries: ${MANIFEST_CLI_TIME_RETRIES}"
    echo "   🌐 Servers (HTTPS):"

    local s label
    while IFS= read -r s; do
        case "$s" in
            *"google.com"*)     label="(Google)" ;;
            *"cloudflare.com"*) label="(Cloudflare)" ;;
            *"apple.com"*)      label="(Apple)" ;;
            *)                  label="" ;;
        esac
        if [ -n "$label" ]; then echo "   • $s $label"
        else                     echo "   • $s"; fi
    done < <(_manifest_time_effective_servers)

    echo ""
    echo "💡 Customize with environment variables:"
    echo "   export MANIFEST_CLI_TIME_SERVER1='https://www.cloudflare.com/cdn-cgi/trace'"
    echo "   export MANIFEST_CLI_TIME_SERVER2='https://www.google.com/generate_204'"
    echo "   export MANIFEST_CLI_TIME_SERVER3='https://www.apple.com'"
    echo "   export MANIFEST_CLI_TIME_SERVER4=''        # optional"
    echo "   export MANIFEST_CLI_TIME_TIMEOUT=5"
    echo "   export MANIFEST_CLI_TIME_RETRIES=3"
    echo "   export MANIFEST_CLI_TIME_CACHE_TTL=120"
    echo "   export MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD=3600"
    echo "   export MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE=21600"
}
