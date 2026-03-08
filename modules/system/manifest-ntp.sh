#!/bin/bash

# Manifest NTP Module v2.0
# Simple, highly accurate timestamp service for manifest operations

# Note: OS detection is now handled by manifest-os.sh module
# This module will use the MANIFEST_OS, MANIFEST_OS_FAMILY, and other variables
# that are set by the OS detection module.

# Configuration with sensible defaults
MANIFEST_CLI_NTP_TIMEOUT=${MANIFEST_CLI_NTP_TIMEOUT:-3}
MANIFEST_CLI_NTP_RETRIES=${MANIFEST_CLI_NTP_RETRIES:-2}

# Global timestamp variables
MANIFEST_CLI_NTP_TIMESTAMP=""
MANIFEST_CLI_NTP_OFFSET=""
MANIFEST_CLI_NTP_UNCERTAINTY=""
MANIFEST_CLI_NTP_SERVER=""
MANIFEST_CLI_NTP_SERVER_IP=""
MANIFEST_CLI_NTP_METHOD=""

# Use the centralized timeout function from manifest-os.sh
# The run_with_timeout function is now provided by the OS module

# Build effective NTP server list from canonical variables (SERVER1..SERVER4),
# with fallback support for legacy MANIFEST_CLI_NTP_SERVERS.
_manifest_ntp_effective_servers() {
    local servers=()

    for i in 1 2 3 4; do
        local server_var="MANIFEST_CLI_NTP_SERVER$i"
        local server_value="${!server_var:-}"
        if [ -n "$server_value" ]; then
            servers+=("$server_value")
        fi
    done

    if [ ${#servers[@]} -eq 0 ] && [ -n "${MANIFEST_CLI_NTP_SERVERS:-}" ]; then
        local legacy_servers=()
        IFS=',' read -r -a legacy_servers <<< "${MANIFEST_CLI_NTP_SERVERS}"
        local server=""
        for server in "${legacy_servers[@]}"; do
            # Trim leading/trailing spaces around comma-separated values.
            server="$(echo "$server" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if [ -n "$server" ]; then
                servers+=("$server")
            fi
        done
    fi

    if [ ${#servers[@]} -eq 0 ]; then
        servers=("time.apple.com" "time.google.com" "pool.ntp.org" "time.nist.gov")
    fi

    local idx=0
    while [ $idx -lt ${#servers[@]} ]; do
        echo "${servers[$idx]}"
        idx=$((idx + 1))
    done
}

# OS-dependent NTP parsing function
parse_ntp_output() {
    local sntp_output="$1"
    local os="$2"
    
    # Debug: Show what we're parsing
    if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
        echo "   🔍 Debug: Parsing for OS='$os'" >&2
    fi
    
    case "$os" in
        "macOS")
            # macOS sntp output format: +0.047157 +/- 0.021125 time.apple.com 17.253.6.45
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: macOS parsing - raw output: '$sntp_output'" >&2
            fi
            local ntp_line
            ntp_line=$(echo "$sntp_output" | grep -E "^[+-][0-9]" | tail -1 || true)
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: macOS parsing - ntp_line: '$ntp_line'" >&2
            fi
            if [ -n "$ntp_line" ]; then
                local offset=$(echo "$ntp_line" | awk '{print $1}')
                local uncertainty=$(echo "$ntp_line" | awk '{print $3}')
                local server_ip=$(echo "$ntp_line" | awk '{print $5}')
                if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                    echo "   🔍 Debug: macOS parsing - offset='$offset', uncertainty='$uncertainty', server_ip='$server_ip'" >&2
                fi
                echo "$offset|$uncertainty|$server_ip"
                return 0
            fi
            ;;
        "Linux")
            # Linux sntp output format: +0.047157 +/- 0.021125 time.apple.com 17.253.6.45
            # or sometimes: 2025-09-22 00:47:43.438049 (+0000) +0.047157 +/- 0.021125 time.apple.com 17.253.6.45
            local ntp_line
            ntp_line=$(echo "$sntp_output" | grep -E "^[+-][0-9]" | tail -1 || true)
            if [ -n "$ntp_line" ]; then
                local offset=$(echo "$ntp_line" | awk '{print $1}')
                local uncertainty=$(echo "$ntp_line" | awk '{print $3}')
                local server_ip=$(echo "$ntp_line" | awk '{print $5}')
                echo "$offset|$uncertainty|$server_ip"
                return 0
            fi
            ;;
        "FreeBSD"|"OpenBSD"|"NetBSD")
            # BSD sntp output format: +0.047157 +/- 0.021125 time.apple.com 17.253.6.45
            local ntp_line
            ntp_line=$(echo "$sntp_output" | grep -E "^[+-][0-9]" | tail -1 || true)
            if [ -n "$ntp_line" ]; then
                local offset=$(echo "$ntp_line" | awk '{print $1}')
                local uncertainty=$(echo "$ntp_line" | awk '{print $3}')
                local server_ip=$(echo "$ntp_line" | awk '{print $5}')
                echo "$offset|$uncertainty|$server_ip"
                return 0
            fi
            ;;
        *)
            # Generic fallback - try multiple parsing strategies
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: Using generic parsing for unknown OS: $os" >&2
            fi
            
            # Strategy 1: Standard format
            local ntp_line
            ntp_line=$(echo "$sntp_output" | grep -E "^[+-][0-9]" | tail -1 || true)
            if [ -n "$ntp_line" ]; then
                local offset=$(echo "$ntp_line" | awk '{print $1}')
                local uncertainty=$(echo "$ntp_line" | awk '{print $3}')
                local server_ip=$(echo "$ntp_line" | awk '{print $5}')
                echo "$offset|$uncertainty|$server_ip"
                return 0
            fi
            
            # Strategy 2: Alternative format with date prefix
            ntp_line=$(echo "$sntp_output" | grep -E "[+-][0-9]" | tail -1 || true)
            if [ -n "$ntp_line" ]; then
                local offset
                offset=$(echo "$ntp_line" | grep -oE '[+-][0-9]+\.[0-9]+' | head -1 || true)
                local uncertainty
                uncertainty=$(echo "$ntp_line" | grep -oE '[0-9]+\.[0-9]+' | tail -1 || true)
                local server_ip
                server_ip=$(echo "$ntp_line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tail -1 || true)
                echo "$offset|$uncertainty|$server_ip"
                return 0
            fi
            ;;
    esac
    
    return 1
}

# Simple NTP query function with OS-dependent parsing and timeout strategy
query_ntp_server() {
    local server="$1"
    local timeout="$2"
    
    # Execute sntp with explicit timeout to avoid hanging on unreachable servers.
    local sntp_output=""
    local exit_code=0

    # Capture non-zero exit safely under set -e.
    if sntp_output=$(sntp -t "$timeout" "$server" 2>&1); then
        exit_code=0
    else
        exit_code=$?
    fi
    
    # Debug: Show what we got
    if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
        echo "   🔍 Debug: OS='$MANIFEST_CLI_OS_OS', sntp_timeout='$timeout', exit_code=$exit_code" >&2
        echo "   🔍 Debug: sntp_output='$sntp_output'" >&2
    fi
    
    # Parse the output using OS-dependent strategy
    local parsed_result=""
    local parse_exit_code=0
    if parsed_result=$(parse_ntp_output "$sntp_output" "$MANIFEST_CLI_OS_OS"); then
        parse_exit_code=0
    else
        parse_exit_code=$?
    fi
    
    if [ $parse_exit_code -eq 0 ] && [ -n "$parsed_result" ]; then
        # Validate the parsed values
        IFS='|' read -r offset uncertainty server_ip <<< "$parsed_result"
        
        if [[ "$offset" =~ ^[+-]?[0-9]+\.[0-9]+$ ]] && [[ "$uncertainty" =~ ^[0-9]+\.[0-9]+$ ]]; then
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: Successfully parsed - offset='$offset' uncertainty='$uncertainty' ip='$server_ip'" >&2
            fi
            echo "$parsed_result"
            return 0
        else
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Invalid format - offset='$offset' uncertainty='$uncertainty'" >&2
            fi
            return 1
        fi
    else
        # No valid NTP response found
        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   ⚠️  Debug: No valid NTP response found for OS='$MANIFEST_CLI_OS_OS'" >&2
        fi
        return 1
    fi
}

# Calculate accurate timestamp from NTP offset
calculate_ntp_timestamp() {
    local offset="$1"
    local uncertainty="$2"
    
    # Get current system time in seconds since epoch
    local system_time=$(date -u +%s)
    
    # Parse offset (remove + sign, handle negative)
    local offset_abs=$(echo "$offset" | sed 's/^+//' | sed 's/^-//')
    local offset_sign=${offset:0:1}
    
    # Calculate NTP-corrected timestamp using bc for floating-point arithmetic
    local ntp_timestamp
    
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
                # Negative offset means system is behind NTP time, so add the offset
                ntp_timestamp=$(echo "$system_time + $offset_abs" | bc -l 2>/dev/null)
            else
                # Positive offset means system is ahead of NTP time, so subtract the offset
                ntp_timestamp=$(echo "$system_time - $offset_abs" | bc -l 2>/dev/null)
            fi
            
            # Handle bc errors by falling back to system time
            if [ $? -ne 0 ] || [ -z "$ntp_timestamp" ]; then
                if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                    echo "   ⚠️  Debug: bc calculation failed (exit code: $?), using system time" >&2
                fi
                ntp_timestamp="$system_time"
            else
                if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                    echo "   🔍 Debug: bc calculation successful: $ntp_timestamp" >&2
                fi
            fi
        else
            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Invalid offset_abs format: '$offset_abs', using system time" >&2
            fi
            ntp_timestamp="$system_time"
        fi
    else
        # bc not available, use simple integer arithmetic
        if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
            echo "   ⚠️  Debug: bc not available, using system time" >&2
        fi
        ntp_timestamp="$system_time"
    fi
    
    # Convert to integer for timestamp
    ntp_timestamp=$(echo "$ntp_timestamp" | cut -d. -f1)
    
    echo "$ntp_timestamp|$offset|$uncertainty"
}

# Get trusted NTP timestamp with fallback strategy
get_ntp_timestamp() {
    echo "🕐 Getting trusted timestamp..."
    
    local timestamp=""
    local offset=""
    local uncertainty=""
    local server=""
    local server_ip=""
    local method=""
    
    # Build array of effective NTP servers.
    local ntp_servers=()
    while IFS= read -r server_line; do
        [ -n "$server_line" ] && ntp_servers+=("$server_line")
    done < <(_manifest_ntp_effective_servers)

    local retries="${MANIFEST_CLI_NTP_RETRIES:-1}"
    if ! [[ "$retries" =~ ^[0-9]+$ ]] || [ "$retries" -lt 1 ]; then
        retries=1
    fi
    
    # Try external NTP servers first
    for ntp_server in "${ntp_servers[@]}"; do
        local attempt=1
        while [ "$attempt" -le "$retries" ]; do
            if [ "$retries" -gt 1 ]; then
                echo "   🔍 Querying $ntp_server (attempt $attempt/$retries)..."
            else
                echo "   🔍 Querying $ntp_server..."
            fi

            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: Calling query_ntp_server with server='$ntp_server', timeout='$MANIFEST_CLI_NTP_TIMEOUT'" >&2
            fi

            local result=""
            local query_exit_code=0
            if result=$(query_ntp_server "$ntp_server" "$MANIFEST_CLI_NTP_TIMEOUT"); then
                query_exit_code=0
            else
                query_exit_code=$?
            fi

            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   🔍 Debug: query_ntp_server returned exit_code=$query_exit_code, result='$result'" >&2
            fi

            if [ $query_exit_code -eq 0 ] && [ -n "$result" ]; then
                # Parse result: offset|uncertainty|server_ip
                IFS='|' read -r calculated_offset calculated_uncertainty server_ip <<< "$result"

                # Calculate the NTP-corrected timestamp
                local timestamp_result
                timestamp_result=$(calculate_ntp_timestamp "$calculated_offset" "$calculated_uncertainty")
                IFS='|' read -r calculated_timestamp offset uncertainty <<< "$timestamp_result"

                timestamp="$calculated_timestamp"
                server="$ntp_server"
                method="external"

                echo "   ✅ NTP timestamp from $ntp_server"
                echo "   📊 Offset: $offset seconds (±$uncertainty)"
                break 2
            fi

            if [ "${MANIFEST_DEBUG:-0}" = "1" ]; then
                echo "   ⚠️  Debug: Query failed with exit code $query_exit_code, result='$result'" >&2
            fi
            if [ "$attempt" -lt "$retries" ]; then
                echo "   ⚠️  Failed to query $ntp_server; retrying..."
            else
                echo "   ⚠️  Failed to query $ntp_server (network timeout or parsing error)"
            fi

            attempt=$((attempt + 1))
        done
    done
    
    # Fallback to system time if no NTP servers responded
    if [ -z "$timestamp" ]; then
        echo "   🔄 No NTP servers responded, using system time"
        timestamp=$(date -u +%s)
        offset="0.000000"
        uncertainty="0.000000"
        server="system"
        server_ip="127.0.0.1"
        method="system"
    fi
    
    # Export variables for use in other functions
    export MANIFEST_CLI_NTP_TIMESTAMP="$timestamp"
    export MANIFEST_CLI_NTP_OFFSET="$offset"
    export MANIFEST_CLI_NTP_UNCERTAINTY="$uncertainty"
    export MANIFEST_CLI_NTP_SERVER="$server"
    export MANIFEST_CLI_NTP_SERVER_IP="$server_ip"
    export MANIFEST_CLI_NTP_METHOD="$method"
    
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
display_ntp_info() {
    echo "🕐 Manifest Timestamp Service"
    echo "============================="
    
    # Get fresh timestamp
    get_ntp_timestamp
    
    echo "📊 Timestamp Details:"
    local tz_display=$(get_timezone_display "$MANIFEST_CLI_NTP_TIMESTAMP")
    echo "   🕐 Time: $(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S') $tz_display"
    echo "   📊 Offset: $MANIFEST_CLI_NTP_OFFSET seconds"
    echo "   🎯 Uncertainty: ±$MANIFEST_CLI_NTP_UNCERTAINTY seconds"
    echo "   🌐 Source: $MANIFEST_CLI_NTP_SERVER ($MANIFEST_CLI_NTP_SERVER_IP)"
    echo "   🔧 Method: $MANIFEST_CLI_NTP_METHOD"
    echo ""
    echo "💡 This timestamp is ready for manifest operations"
}

# Display timestamp configuration
display_ntp_config() {
    echo "⚙️  Manifest Timestamp Configuration"
    echo "===================================="
    echo "   🖥️  OS: $MANIFEST_CLI_OS_OS"
    echo "   ⏱️  Timeout: ${MANIFEST_CLI_NTP_TIMEOUT}s"
    echo "   🔄 Retries: ${MANIFEST_CLI_NTP_RETRIES}"
    echo "   🌐 Servers:"

    local ntp_servers=()
    while IFS= read -r server_line; do
        [ -n "$server_line" ] && ntp_servers+=("$server_line")
    done < <(_manifest_ntp_effective_servers)

    local server=""
    for server in "${ntp_servers[@]}"; do
        case "$server" in
            "time.apple.com")
                echo "   • $server (Apple)"
                ;;
            "time.google.com")
                echo "   • $server (Google)"
                ;;
            "pool.ntp.org")
                echo "   • $server (NTP Pool)"
                ;;
            "time.nist.gov")
                echo "   • $server (NIST)"
                ;;
            *)
                echo "   • $server"
                ;;
        esac
    done
    
    echo ""
    echo "💡 Customize with environment variables:"
    echo "   export MANIFEST_CLI_NTP_SERVER1='time.apple.com'"
    echo "   export MANIFEST_CLI_NTP_SERVER2='time.google.com'"
    echo "   export MANIFEST_CLI_NTP_SERVER3='pool.ntp.org'"
    echo "   export MANIFEST_CLI_NTP_SERVER4='time.nist.gov'"
    echo "   # Legacy fallback also supported:"
    echo "   export MANIFEST_CLI_NTP_SERVERS='time.apple.com,time.google.com'"
    echo "   export MANIFEST_CLI_NTP_TIMEOUT=5"
    echo "   export MANIFEST_CLI_NTP_RETRIES=3"
}

# Quick timestamp function for simple operations
get_timestamp() {
    get_ntp_timestamp >/dev/null
    echo "$MANIFEST_CLI_NTP_TIMESTAMP"
}

# Get formatted timestamp string with timezone
get_formatted_timestamp() {
    get_ntp_timestamp >/dev/null
    local tz_display=$(get_timezone_display "$MANIFEST_CLI_NTP_TIMESTAMP")
    echo "$(format_timestamp "$MANIFEST_CLI_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S') $tz_display"
}

# Display NTP/OS compatibility information.
# Keep this namespaced to avoid overriding system/manifest-os.sh display_os_info().
display_ntp_os_info() {
    echo "🖥️  Manifest OS Compatibility"
    echo "============================="
    echo "   🖥️  Detected OS: $MANIFEST_OS"
    echo "   📱  OSTYPE: $OSTYPE"
    
    echo ""
    echo "🔧 Command Availability:"
    
    # Check timeout command
    if command -v timeout >/dev/null 2>&1; then
        echo "   ✅ timeout: $(which timeout)"
    elif command -v gtimeout >/dev/null 2>&1; then
        echo "   ✅ gtimeout: $(which gtimeout)"
    else
        echo "   ⚠️  timeout: Not available (will run without timeout)"
    fi
    
    # Check sntp command
    if command -v sntp >/dev/null 2>&1; then
        echo "   ✅ sntp: $(which sntp)"
    else
        echo "   ❌ sntp: Not available (NTP functionality limited)"
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
    
    echo ""
    echo "💡 OS-specific optimizations applied automatically"
}
