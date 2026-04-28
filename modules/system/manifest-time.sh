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
    [ "${MANIFEST_DEBUG:-0}" = "1" ] && echo "   🔍 Debug: $*" >&2
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

# Read cache. Mode "fresh" honors TTL; "stale" honors STALE_MAX_AGE.
# Echoes: timestamp|offset|uncertainty|server|server_ip|method
_manifest_time_read_cache_data() {
    local mode="${1:-fresh}"
    local cache_file
    cache_file=$(_manifest_time_cache_file)
    [ -f "$cache_file" ] || return 1

    # shellcheck disable=SC1090
    . "$cache_file" 2>/dev/null || return 1

    local now saved ts
    now=$(date -u +%s)
    saved="${MANIFEST_CLI_TIME_CACHE_SAVED_AT:-0}"
    ts="${MANIFEST_CLI_TIME_CACHE_TIMESTAMP:-0}"
    [[ "$saved" =~ ^[0-9]+$ ]] && [[ "$ts" =~ ^[0-9]+$ ]] || return 1

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

    echo "$((ts + age))|${MANIFEST_CLI_TIME_CACHE_OFFSET:-0.000000}|${MANIFEST_CLI_TIME_CACHE_UNCERTAINTY:-0.000000}|${MANIFEST_CLI_TIME_CACHE_SERVER:-cache}|${MANIFEST_CLI_TIME_CACHE_SERVER_IP:-127.0.0.1}|${method}"
}

_manifest_time_write_cache_data() {
    local timestamp="$1" offset="$2" uncertainty="$3" server="$4" server_ip="$5"
    [ -n "$timestamp" ] || return 1
    local cache_dir cache_file now
    cache_dir=$(_manifest_time_cache_dir)
    cache_file=$(_manifest_time_cache_file)
    mkdir -p "$cache_dir" 2>/dev/null || return 1
    now=$(date -u +%s)
    umask 077
    {
        echo "MANIFEST_CLI_TIME_CACHE_SAVED_AT=${now}"
        echo "MANIFEST_CLI_TIME_CACHE_TIMESTAMP=${timestamp}"
        echo "MANIFEST_CLI_TIME_CACHE_OFFSET=${offset}"
        echo "MANIFEST_CLI_TIME_CACHE_UNCERTAINTY=${uncertainty}"
        echo "MANIFEST_CLI_TIME_CACHE_SERVER=${server}"
        echo "MANIFEST_CLI_TIME_CACHE_SERVER_IP=${server_ip}"
    } > "$cache_file" 2>/dev/null || return 1
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

# Parse RFC 7231 HTTP Date header into Unix epoch. Tries GNU date, BSD date, python3.
_parse_http_date() {
    local s="$1" epoch
    epoch=$(date -u -d "$s" +%s 2>/dev/null) && { echo "$epoch"; return 0; }
    epoch=$(date -u -jf "%a, %d %b %Y %H:%M:%S GMT" "$s" +%s 2>/dev/null) && { echo "$epoch"; return 0; }
    if command -v python3 >/dev/null 2>&1; then
        epoch=$(python3 -c "import email.utils,calendar,sys
t=email.utils.parsedate_tz('$s')
print(calendar.timegm(t[:9])) if t else sys.exit(1)" 2>/dev/null) && { echo "$epoch"; return 0; }
    fi
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
