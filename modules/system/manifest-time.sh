#!/bin/bash

# Manifest Time Module v3.0
# HTTPS-based trusted timestamp service for manifest operations
#
# Queries trusted HTTPS endpoints for their Date header to determine
# accurate time without requiring UDP port 123 (which is commonly
# blocked by corporate networks, VPNs, and firewalls).

# Note: OS detection is now handled by manifest-os.sh module
# This module will use the MANIFEST_OS, MANIFEST_OS_FAMILY, and other variables
# that are set by the OS detection module.

# Configuration with sensible defaults
MANIFEST_CLI_TIME_TIMEOUT=${MANIFEST_CLI_TIME_TIMEOUT:-5}
MANIFEST_CLI_TIME_RETRIES=${MANIFEST_CLI_TIME_RETRIES:-2}
MANIFEST_CLI_TIME_CACHE_TTL=${MANIFEST_CLI_TIME_CACHE_TTL:-120}
MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD=${MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD:-3600}
MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE=${MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE:-21600}

# Global timestamp variables
MANIFEST_CLI_TIME_TIMESTAMP=""
MANIFEST_CLI_TIME_OFFSET=""
MANIFEST_CLI_TIME_UNCERTAINTY=""
MANIFEST_CLI_TIME_SERVER=""
MANIFEST_CLI_TIME_SERVER_IP=""
MANIFEST_CLI_TIME_METHOD=""

# Use the centralized timeout function from manifest-os.sh
# The run_with_timeout function is now provided by the OS module

# Build deterministic cache paths.
_manifest_time_cache_paths() {
    local cache_root="${MANIFEST_CLI_CACHE_DIR:-${TMPDIR:-/tmp}/manifest-cli}"
    local cache_dir="${cache_root}/time"
    local cache_file="${cache_dir}/timestamp.cache"
    local cleanup_marker="${cache_dir}/cleanup.last"
    echo "${cache_dir}|${cache_file}|${cleanup_marker}"
}

# Delete stale cache files on a fixed cadence.
_manifest_time_maybe_cleanup_cache() {
    local path_data=""
    path_data=$(_manifest_time_cache_paths)
    IFS='|' read -r cache_dir _cache_file cleanup_marker <<< "$path_data"

    local cleanup_period="${MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD:-3600}"
    if ! [[ "$cleanup_period" =~ ^[0-9]+$ ]] || [ "$cleanup_period" -lt 60 ]; then
        cleanup_period=3600
    fi

    local now
    now=$(date -u +%s)
    local last_cleanup=0

    if [ -f "$cleanup_marker" ]; then
        last_cleanup=$(tr -d '[:space:]' < "$cleanup_marker" 2>/dev/null || echo "0")
        if ! [[ "$last_cleanup" =~ ^[0-9]+$ ]]; then
            last_cleanup=0
        fi
    fi

    if [ $((now - last_cleanup)) -lt "$cleanup_period" ]; then
        return 0
    fi

    mkdir -p "$cache_dir" 2>/dev/null || return 0
    # Keep cache folder clean by deleting stale cache artifacts older than cleanup period.
    find "$cache_dir" -type f -name "*.cache*" -mmin +"$((cleanup_period / 60))" -delete 2>/dev/null || true
    printf '%s\n' "$now" > "$cleanup_marker" 2>/dev/null || true
}

_manifest_time_read_cache_data() {
    local cache_mode="${1:-fresh}"
    local path_data=""
    path_data=$(_manifest_time_cache_paths)
    IFS='|' read -r _cache_dir cache_file _cleanup_marker <<< "$path_data"

    [ -f "$cache_file" ] || return 1

    # shellcheck disable=SC1090
    . "$cache_file" 2>/dev/null || return 1

    local now
    now=$(date -u +%s)
    local cached_at="${MANIFEST_CLI_TIME_CACHE_SAVED_AT:-0}"
    local cached_timestamp="${MANIFEST_CLI_TIME_CACHE_TIMESTAMP:-0}"
    local cached_offset="${MANIFEST_CLI_TIME_CACHE_OFFSET:-0.000000}"
    local cached_uncertainty="${MANIFEST_CLI_TIME_CACHE_UNCERTAINTY:-0.000000}"
    local cached_server="${MANIFEST_CLI_TIME_CACHE_SERVER:-cache}"
    local cached_server_ip="${MANIFEST_CLI_TIME_CACHE_SERVER_IP:-127.0.0.1}"

    if ! [[ "$cached_at" =~ ^[0-9]+$ ]] || ! [[ "$cached_timestamp" =~ ^[0-9]+$ ]]; then
        return 1
    fi

    local age=$((now - cached_at))
    if [ "$age" -lt 0 ]; then
        return 1
    fi

    local max_age=0
    case "$cache_mode" in
        "fresh")
            max_age="${MANIFEST_CLI_TIME_CACHE_TTL:-120}"
            ;;
        "stale")
            max_age="${MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE:-21600}"
            ;;
        *)
            return 1
            ;;
    esac

    if ! [[ "$max_age" =~ ^[0-9]+$ ]] || [ "$max_age" -lt 1 ]; then
        return 1
    fi

    if [ "$age" -gt "$max_age" ]; then
        return 1
    fi

    local adjusted_timestamp=$((cached_timestamp + age))
    local cache_method="cache"
    if [ "$cache_mode" = "stale" ]; then
        cache_method="cache-stale"
    fi

    echo "${adjusted_timestamp}|${cached_offset}|${cached_uncertainty}|${cached_server}|${cached_server_ip}|${cache_method}"
}

_manifest_time_write_cache_data() {
    local timestamp="$1"
    local offset="$2"
    local uncertainty="$3"
    local server="$4"
    local server_ip="$5"

    [ -n "$timestamp" ] || return 1

    local path_data=""
    path_data=$(_manifest_time_cache_paths)
    IFS='|' read -r cache_dir cache_file _cleanup_marker <<< "$path_data"

    mkdir -p "$cache_dir" 2>/dev/null || return 1

    local now
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

# Build effective HTTPS time server list from canonical variables (SERVER1..SERVER4).
_manifest_time_effective_servers() {
    local servers=()

    for i in 1 2 3 4; do
        local server_var="MANIFEST_CLI_TIME_SERVER$i"
        local server_value="${!server_var:-}"
        if [ -n "$server_value" ]; then
            servers+=("$server_value")
        fi
    done

    if [ ${#servers[@]} -eq 0 ]; then
        # Default HTTPS time endpoints (port 443, not blocked by firewalls).
        # Cloudflare /cdn-cgi/trace is primary — returns epoch with sub-second
        # precision in body (ts=...). Google and Apple use Date header fallback.
        servers=(
            "https://www.cloudflare.com/cdn-cgi/trace"
            "https://www.google.com/generate_204"
            "https://www.apple.com"
        )
    fi

    local idx=0
    while [ $idx -lt ${#servers[@]} ]; do
        echo "${servers[$idx]}"
        idx=$((idx + 1))
    done
}

# =============================================================================
# HTTPS TIME QUERY
# =============================================================================

# Parse an HTTP Date header value into a Unix epoch timestamp.
# Handles the standard RFC 7231 format: "Fri, 04 Apr 2026 15:25:17 GMT"
# Cross-platform: tries GNU date -d, then macOS date -jf, then python3.
_parse_http_date() {
    local date_str="$1"

    # Try GNU date (Linux, Homebrew coreutils)
    if epoch=$(date -u -d "$date_str" +%s 2>/dev/null); then
        echo "$epoch"
        return 0
    fi

    # Try macOS/BSD date -jf
    # RFC 7231 format: "Fri, 04 Apr 2026 15:25:17 GMT"
    if epoch=$(date -u -jf "%a, %d %b %Y %H:%M:%S GMT" "$date_str" +%s 2>/dev/null); then
        echo "$epoch"
        return 0
    fi

    # Fallback to python3
    if command -v python3 >/dev/null 2>&1; then
        if epoch=$(python3 -c "
import email.utils, calendar, sys
t = email.utils.parsedate_tz('$date_str')
if t: print(calendar.timegm(t[:9]))
else: sys.exit(1)
" 2>/dev/null); then
            echo "$epoch"
            return 0
        fi
    fi

    return 1
}

# Query a single HTTPS endpoint for trusted time.
#
# For Cloudflare /cdn-cgi/trace endpoints, parses the ts= field from the
# response body (epoch with sub-second precision). For all other endpoints,
# falls back to the standard HTTP Date header (1-second resolution).
#
# Returns: offset|uncertainty|server_ip
#   offset      - seconds between system clock and server time (+ means system ahead)
#   uncertainty - estimated accuracy (half the round-trip time)
#   server_ip   - resolved IP of the server
query_time_server() {
    local server="$1"
    local timeout="$2"

    # Ensure the server URL has a scheme.
    if [[ "$server" != https://* ]] && [[ "$server" != http://* ]]; then
        server="https://$server"
    fi

    local is_cloudflare_trace=false
    if [[ "$server" == *"/cdn-cgi/trace"* ]]; then
        is_cloudflare_trace=true
    fi

    if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
        echo "   🔍 Debug: HTTPS query to '$server', timeout='$timeout', cloudflare_trace=$is_cloudflare_trace" >&2
    fi

    # Record time before request for round-trip measurement.
    local t_before
    t_before=$(date -u +%s)

    local server_epoch=""
    local server_ip=""
    local fractional="000000"

    if [ "$is_cloudflare_trace" = true ]; then
        # Cloudflare /cdn-cgi/trace returns a text body with key=value pairs
        # including ts=1712345678.123 (epoch with sub-second precision).
        # Fetch body + write-out metadata in one call.
        local response=""
        local exit_code=0
        if response=$(curl -s \
                --connect-timeout "$timeout" \
                --max-time "$timeout" \
                -w $'\n'"__META__|%{http_code}|%{remote_ip}" \
                "$server" 2>&1); then
            exit_code=0
        else
            exit_code=$?
        fi

        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   🔍 Debug: curl exit_code=$exit_code" >&2
            echo "   🔍 Debug: response='$(echo "$response" | head -5)...'" >&2
        fi

        # Extract metadata from the last line.
        local meta_line
        meta_line=$(echo "$response" | grep "^__META__" | tail -1)
        local http_code=""
        IFS='|' read -r _ http_code server_ip <<< "$meta_line"

        if [ "$exit_code" -ne 0 ] || [ -z "$http_code" ] || [ "$http_code" = "000" ]; then
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Cloudflare request failed (exit=$exit_code, http=$http_code)" >&2
            fi
            return 1
        fi

        # Parse ts= from the body (format: ts=1712345678.123)
        local ts_line
        ts_line=$(echo "$response" | grep -E "^ts=" | head -1)
        local ts_value="${ts_line#ts=}"

        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   🔍 Debug: ts_line='$ts_line', ts_value='$ts_value'" >&2
        fi

        if [[ "$ts_value" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
            # Split into integer and fractional parts.
            server_epoch="${ts_value%%.*}"
            if [[ "$ts_value" == *.* ]]; then
                fractional="${ts_value#*.}"
                # Pad or truncate to 6 digits.
                fractional="${fractional}000000"
                fractional="${fractional:0:6}"
            fi
        else
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Invalid ts value: '$ts_value'" >&2
            fi
            return 1
        fi
    else
        # Standard endpoint — fetch headers only and parse the Date header.
        local curl_output=""
        local exit_code=0
        if curl_output=$(curl -sI \
                --connect-timeout "$timeout" \
                --max-time "$timeout" \
                -o /dev/null \
                -w "%{http_code}|%header{date}|%{remote_ip}" \
                "$server" 2>&1); then
            exit_code=0
        else
            exit_code=$?
        fi

        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   🔍 Debug: curl exit_code=$exit_code, output='$curl_output'" >&2
        fi

        local http_code date_header
        IFS='|' read -r http_code date_header server_ip <<< "$curl_output"

        if [ "$exit_code" -ne 0 ] || [ -z "$http_code" ] || [ "$http_code" = "000" ]; then
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: HTTPS request failed (exit=$exit_code, http=$http_code)" >&2
            fi
            return 1
        fi

        if [ -z "$date_header" ]; then
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: No Date header in response" >&2
            fi
            return 1
        fi

        if ! server_epoch=$(_parse_http_date "$date_header"); then
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Failed to parse Date header: '$date_header'" >&2
            fi
            return 1
        fi
    fi

    if ! [[ "$server_epoch" =~ ^[0-9]+$ ]]; then
        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   ⚠️  Debug: Invalid epoch: '$server_epoch'" >&2
        fi
        return 1
    fi

    local t_after
    t_after=$(date -u +%s)

    # Calculate offset: positive means system clock is ahead of server.
    local rtt=$((t_after - t_before))
    local system_midpoint=$(( t_before + rtt / 2 ))
    local offset_int=$(( system_midpoint - server_epoch ))

    # Format as signed decimal for compatibility with downstream code.
    local offset_str
    if [ "$offset_int" -ge 0 ]; then
        offset_str="+${offset_int}.${fractional}"
    else
        offset_str="${offset_int}.${fractional}"
    fi

    # Uncertainty: for Cloudflare trace, sub-second precision reduces uncertainty.
    # For Date header endpoints, 1-second resolution is the floor.
    local uncertainty_secs=$(( rtt / 2 ))
    if [ "$uncertainty_secs" -lt 1 ]; then
        uncertainty_secs=1
    fi
    local uncertainty_str
    if [ "$is_cloudflare_trace" = true ]; then
        # Sub-second precision available; uncertainty is primarily RTT-driven.
        uncertainty_str="0.${fractional:-500000}"
        if [ "$rtt" -ge 2 ]; then
            uncertainty_str="${uncertainty_secs}.000000"
        fi
    else
        uncertainty_str="${uncertainty_secs}.000000"
    fi

    if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
        echo "   🔍 Debug: server_epoch=$server_epoch, system_mid=$system_midpoint, offset=$offset_str, rtt=${rtt}s, uncertainty=$uncertainty_str, ip=$server_ip" >&2
    fi

    echo "${offset_str}|${uncertainty_str}|${server_ip}"
    return 0
}

# Calculate accurate timestamp from offset
calculate_time_timestamp() {
    local offset="$1"
    local uncertainty="$2"

    # Get current system time in seconds since epoch
    local system_time=$(date -u +%s)

    # Parse offset (remove + sign, handle negative)
    local offset_abs=$(echo "$offset" | sed 's/^+//' | sed 's/^-//')
    local offset_sign=${offset:0:1}

    # Calculate corrected timestamp using bc for floating-point arithmetic
    local time_timestamp

    # Debug: Show what we're calculating
    if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
        echo "   🔍 Debug: Calculating timestamp - system_time=$system_time, offset='$offset', offset_sign='$offset_sign', offset_abs='$offset_abs'" >&2
    fi

    # Validate inputs
    if [ -z "$offset" ] || [ -z "$offset_abs" ]; then
        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   ⚠️  Debug: Invalid offset data - offset='$offset', offset_abs='$offset_abs', using system time" >&2
        fi
        echo "$system_time|$offset|$uncertainty"
        return 0
    fi

    # Check if bc is available
    if command -v bc >/dev/null 2>&1; then
        # Validate offset_abs is a valid number
        if [[ "$offset_abs" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            if [ "$offset_sign" = "-" ]; then
                # Negative offset means system is behind server time, so add the offset
                time_timestamp=$(echo "$system_time + $offset_abs" | bc -l 2>/dev/null)
            else
                # Positive offset means system is ahead of server time, so subtract the offset
                time_timestamp=$(echo "$system_time - $offset_abs" | bc -l 2>/dev/null)
            fi

            # Handle bc errors by falling back to system time
            if [ $? -ne 0 ] || [ -z "$time_timestamp" ]; then
                if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                    echo "   ⚠️  Debug: bc calculation failed (exit code: $?), using system time" >&2
                fi
                time_timestamp="$system_time"
            else
                if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                    echo "   🔍 Debug: bc calculation successful: $time_timestamp" >&2
                fi
            fi
        else
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Invalid offset_abs format: '$offset_abs', using system time" >&2
            fi
            time_timestamp="$system_time"
        fi
    else
        # bc not available, use simple integer arithmetic
        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   ⚠️  Debug: bc not available, using system time" >&2
        fi
        time_timestamp="$system_time"
    fi

    # Convert to integer for timestamp
    time_timestamp=$(echo "$time_timestamp" | cut -d. -f1)

    echo "$time_timestamp|$offset|$uncertainty"
}

# Get trusted timestamp with fallback strategy
get_time_timestamp() {
    echo "🕐 Getting trusted timestamp..."

    local timestamp=""
    local offset=""
    local uncertainty=""
    local server=""
    local server_ip=""
    local method=""

    # Keep cache folder tidy and try cache before external lookups.
    _manifest_time_maybe_cleanup_cache

    local cached_result=""
    if cached_result=$(_manifest_time_read_cache_data "fresh"); then
        IFS='|' read -r timestamp offset uncertainty server server_ip method <<< "$cached_result"
        echo "   ⚡ Using cached trusted timestamp"
        echo "   📊 Offset: $offset seconds (±$uncertainty)"

        export MANIFEST_CLI_TIME_TIMESTAMP="$timestamp"
        export MANIFEST_CLI_TIME_OFFSET="$offset"
        export MANIFEST_CLI_TIME_UNCERTAINTY="$uncertainty"
        export MANIFEST_CLI_TIME_SERVER="$server"
        export MANIFEST_CLI_TIME_SERVER_IP="$server_ip"
        export MANIFEST_CLI_TIME_METHOD="$method"

        local tz_display_cached
        tz_display_cached=$(get_timezone_display "$timestamp")
        local formatted_time_cached
        formatted_time_cached=$(format_timestamp "$timestamp" '+%Y-%m-%d %H:%M:%S')
        echo "   🕐 Timestamp: $formatted_time_cached $tz_display_cached"
        echo "   🎯 Method: $method"
        echo ""
        return 0
    fi

    # Build array of effective HTTPS time servers.
    local time_servers=()
    while IFS= read -r server_line; do
        [ -n "$server_line" ] && time_servers+=("$server_line")
    done < <(_manifest_time_effective_servers)

    local retries="${MANIFEST_CLI_TIME_RETRIES:-1}"
    if ! [[ "$retries" =~ ^[0-9]+$ ]] || [ "$retries" -lt 1 ]; then
        retries=1
    fi

    # Try HTTPS time servers
    for time_server in "${time_servers[@]}"; do
        local attempt=1
        while [ "$attempt" -le "$retries" ]; do
            if [ "$retries" -gt 1 ]; then
                echo "   🔍 Querying $time_server (attempt $attempt/$retries)..."
            else
                echo "   🔍 Querying $time_server..."
            fi

            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: Calling query_time_server with server='$time_server', timeout='$MANIFEST_CLI_TIME_TIMEOUT'" >&2
            fi

            local result=""
            local query_exit_code=0
            if result=$(query_time_server "$time_server" "$MANIFEST_CLI_TIME_TIMEOUT"); then
                query_exit_code=0
            else
                query_exit_code=$?
            fi

            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: query_time_server returned exit_code=$query_exit_code, result='$result'" >&2
            fi

            if [ $query_exit_code -eq 0 ] && [ -n "$result" ]; then
                # Parse result: offset|uncertainty|server_ip
                IFS='|' read -r calculated_offset calculated_uncertainty server_ip <<< "$result"

                # Calculate the corrected timestamp
                local timestamp_result
                timestamp_result=$(calculate_time_timestamp "$calculated_offset" "$calculated_uncertainty")
                IFS='|' read -r calculated_timestamp offset uncertainty <<< "$timestamp_result"

                timestamp="$calculated_timestamp"
                server="$time_server"
                method="https"

                _manifest_time_write_cache_data "$timestamp" "$offset" "$uncertainty" "$server" "$server_ip" || true
                echo "   ✅ Trusted timestamp from $time_server"
                echo "   📊 Offset: $offset seconds (±$uncertainty)"
                break 2
            fi

            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Query failed with exit code $query_exit_code, result='$result'" >&2
            fi
            if [ "$attempt" -lt "$retries" ]; then
                echo "   ⚠️  Failed to query $time_server; retrying..."
            else
                echo "   ⚠️  Failed to query $time_server"
            fi

            attempt=$((attempt + 1))
        done
    done

    # Fallback to stale cache first, then system time if needed.
    if [ -z "$timestamp" ]; then
        local stale_cached_result=""
        if stale_cached_result=$(_manifest_time_read_cache_data "stale"); then
            IFS='|' read -r timestamp offset uncertainty server server_ip method <<< "$stale_cached_result"
            echo "   🔄 No live HTTPS response; using stale trusted cache"
            echo "   📊 Offset: $offset seconds (±$uncertainty)"
        else
            echo "   🔄 No time servers responded, using system time"
            timestamp=$(date -u +%s)
            offset="0.000000"
            uncertainty="0.000000"
            server="system"
            server_ip="127.0.0.1"
            method="system"
        fi
    fi

    # Export variables for use in other functions
    export MANIFEST_CLI_TIME_TIMESTAMP="$timestamp"
    export MANIFEST_CLI_TIME_OFFSET="$offset"
    export MANIFEST_CLI_TIME_UNCERTAINTY="$uncertainty"
    export MANIFEST_CLI_TIME_SERVER="$server"
    export MANIFEST_CLI_TIME_SERVER_IP="$server_ip"
    export MANIFEST_CLI_TIME_METHOD="$method"

    # Display timestamp info with timezone
    local tz_display=$(get_timezone_display "$timestamp")
    local formatted_time=$(format_timestamp "$timestamp" '+%Y-%m-%d %H:%M:%S')
    echo "   🕐 Timestamp: $formatted_time $tz_display"
    echo "   🎯 Method: $method"
    echo ""
}

# Format timestamp for display (cross-platform compatible)
# Now uses the centralized format_timestamp_cross_platform function from manifest-os.sh
format_timestamp() {
    local timestamp="$1"
    local format="$2"

    # Use the centralized cross-platform function
    format_timestamp_cross_platform "$timestamp" "$format"
}

# Display current timestamp information
display_time_info() {
    echo "🕐 Manifest Timestamp Service"
    echo "============================="

    # Get fresh timestamp
    get_time_timestamp

    echo "📊 Timestamp Details:"
    local tz_display=$(get_timezone_display "$MANIFEST_CLI_TIME_TIMESTAMP")
    echo "   🕐 Time: $(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S') $tz_display"
    echo "   📊 Offset: $MANIFEST_CLI_TIME_OFFSET seconds"
    echo "   🎯 Uncertainty: ±$MANIFEST_CLI_TIME_UNCERTAINTY seconds"
    echo "   🌐 Source: $MANIFEST_CLI_TIME_SERVER ($MANIFEST_CLI_TIME_SERVER_IP)"
    echo "   🔧 Method: $MANIFEST_CLI_TIME_METHOD"
    echo ""
    echo "💡 This timestamp is ready for manifest operations"
}

# Display timestamp configuration
display_time_config() {
    echo "⚙️  Manifest Timestamp Configuration"
    echo "===================================="
    echo "   🖥️  OS: $MANIFEST_CLI_OS_OS"
    echo "   ⏱️  Timeout: ${MANIFEST_CLI_TIME_TIMEOUT}s"
    echo "   🔄 Retries: ${MANIFEST_CLI_TIME_RETRIES}"
    echo "   🌐 Servers (HTTPS):"

    local time_servers=()
    while IFS= read -r server_line; do
        [ -n "$server_line" ] && time_servers+=("$server_line")
    done < <(_manifest_time_effective_servers)

    local server=""
    for server in "${time_servers[@]}"; do
        case "$server" in
            *"google.com"*)
                echo "   • $server (Google)"
                ;;
            *"cloudflare.com"*)
                echo "   • $server (Cloudflare)"
                ;;
            *"apple.com"*)
                echo "   • $server (Apple)"
                ;;
            *)
                echo "   • $server"
                ;;
        esac
    done

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

# Quick timestamp function for simple operations
get_timestamp() {
    get_time_timestamp >/dev/null
    echo "$MANIFEST_CLI_TIME_TIMESTAMP"
}

# Get formatted timestamp string with timezone
get_formatted_timestamp() {
    get_time_timestamp >/dev/null
    local tz_display=$(get_timezone_display "$MANIFEST_CLI_TIME_TIMESTAMP")
    echo "$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S') $tz_display"
}

# Display OS compatibility information.
# Keep this namespaced to avoid overriding system/manifest-os.sh display_os_info().
display_time_os_info() {
    echo "🖥️  Manifest OS Compatibility"
    echo "============================="
    echo "   🖥️  Detected OS: $MANIFEST_OS"
    echo "   📱  OSTYPE: $OSTYPE"

    echo ""
    echo "🔧 Command Availability:"

    # Check curl command
    if command -v curl >/dev/null 2>&1; then
        echo "   ✅ curl: $(which curl)"
    else
        echo "   ❌ curl: Not available (HTTPS timestamp queries will fail)"
    fi

    # Check timeout command
    if command -v timeout >/dev/null 2>&1; then
        echo "   ✅ timeout: $(which timeout)"
    elif command -v gtimeout >/dev/null 2>&1; then
        echo "   ✅ gtimeout: $(which gtimeout)"
    else
        echo "   ⚠️  timeout: Not available (curl handles its own timeouts)"
    fi

    # Check date command compatibility
    echo "   📅 date command:"
    if date -d "@$(date +%s)" >/dev/null 2>&1; then
        echo "      ✅ Linux format (-d) supported"
    else
        echo "      ❌ Linux format (-d) not supported"
    fi

    if date -r "$(date +%s)" >/dev/null 2>&1; then
        echo "      ✅ macOS format (-r) supported"
    else
        echo "      ❌ macOS format (-r) not supported"
    fi

    # Check python3 (fallback date parser)
    if command -v python3 >/dev/null 2>&1; then
        echo "   ✅ python3: $(which python3) (fallback date parser)"
    else
        echo "   ⚠️  python3: Not available (fewer date parsing options)"
    fi

    echo ""
    echo "💡 Timestamps are fetched via HTTPS (port 443) — no UDP required"
}
