#!/bin/bash

# Manifest NTP Module v2.0
# Simple, highly accurate timestamp service for manifest operations

# Note: OS detection is now handled by manifest-os.sh module
# This module will use the MANIFEST_OS, MANIFEST_OS_FAMILY, and other variables
# that are set by the OS detection module.

# Configuration with sensible defaults
MANIFEST_NTP_SERVERS=${MANIFEST_NTP_SERVERS:-"time.apple.com,time.google.com,pool.ntp.org"}
MANIFEST_NTP_TIMEOUT=${MANIFEST_NTP_TIMEOUT:-3}
MANIFEST_NTP_RETRIES=${MANIFEST_NTP_RETRIES:-2}

# Global timestamp variables
MANIFEST_NTP_TIMESTAMP=""
MANIFEST_NTP_OFFSET=""
MANIFEST_NTP_UNCERTAINTY=""
MANIFEST_NTP_SERVER=""
MANIFEST_NTP_SERVER_IP=""
MANIFEST_NTP_METHOD=""

# Use the centralized timeout function from manifest-os.sh
# The run_with_timeout function is now provided by the OS module

# Simple NTP query function
query_ntp_server() {
    local server="$1"
    local timeout="$2"
    
    # Use OS-aware timeout with sntp
    local result=$(run_with_timeout "$timeout" sntp "$server" 2>/dev/null | tail -1)
    
    if [ $? -eq 0 ] && [ -n "$result" ]; then
        # Parse sntp output: date time offset +/- uncertainty server ip
        # Example: 2025-08-12 15:52:23.438049 (+0500) +2.012665 +/- 1.341959 time.apple.com 17.253.6.37
        local offset=$(echo "$result" | awk '{print $4}')
        local uncertainty=$(echo "$result" | awk '{print $6}')
        local server_ip=$(echo "$result" | awk '{print $8}')
        
        # Validate offset format and ensure we have valid data
        if [[ "$offset" =~ ^[+-]?[0-9]+\.[0-9]+$ ]] && [[ "$uncertainty" =~ ^[0-9]+\.[0-9]+$ ]]; then
            echo "$offset|$uncertainty|$server_ip"
            return 0
        fi
    fi
    
    return 1
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
    if [ "$offset_sign" = "-" ]; then
        ntp_timestamp=$(echo "$system_time + $offset_abs" | bc)
    else
        ntp_timestamp=$(echo "$system_time - $offset_abs" | bc)
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
    
    # Convert comma-separated servers to array
    local ntp_servers=($(echo "$MANIFEST_NTP_SERVERS" | tr ',' ' '))
    
    # Try external NTP servers first
    for ntp_server in "${ntp_servers[@]}"; do
        echo "   🔍 Querying $ntp_server..."
        
        local result=$(query_ntp_server "$ntp_server" "$MANIFEST_NTP_TIMEOUT")
        if [ $? -eq 0 ]; then
            # Parse result: offset|uncertainty|server_ip
            IFS='|' read -r calculated_offset calculated_uncertainty server_ip <<< "$result"
            
            # Calculate the NTP-corrected timestamp
            local timestamp_result=$(calculate_ntp_timestamp "$calculated_offset" "$calculated_uncertainty")
            IFS='|' read -r calculated_timestamp offset uncertainty <<< "$timestamp_result"
            
            timestamp="$calculated_timestamp"
            server="$ntp_server"
            method="external"
            
            echo "   ✅ NTP timestamp from $ntp_server"
            echo "   📊 Offset: $offset seconds (±$uncertainty)"
            break
        else
            echo "   ⚠️  Failed to query $ntp_server"
        fi
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
    export MANIFEST_NTP_TIMESTAMP="$timestamp"
    export MANIFEST_NTP_OFFSET="$offset"
    export MANIFEST_NTP_UNCERTAINTY="$uncertainty"
    export MANIFEST_NTP_SERVER="$server"
    export MANIFEST_NTP_SERVER_IP="$server_ip"
    export MANIFEST_NTP_METHOD="$method"
    
    # Display timestamp info
    local formatted_time=$(format_timestamp "$timestamp" '+%Y-%m-%d %H:%M:%S UTC')
    echo "   🕐 Timestamp: $formatted_time"
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
    echo "   🕐 Time: $(format_timestamp "$MANIFEST_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')"
    echo "   📊 Offset: $MANIFEST_NTP_OFFSET seconds"
    echo "   🎯 Uncertainty: ±$MANIFEST_NTP_UNCERTAINTY seconds"
    echo "   🌐 Source: $MANIFEST_NTP_SERVER ($MANIFEST_NTP_SERVER_IP)"
    echo "   🔧 Method: $MANIFEST_NTP_METHOD"
    echo ""
    echo "💡 This timestamp is ready for manifest operations"
}

# Display timestamp configuration
display_ntp_config() {
    echo "⚙️  Manifest Timestamp Configuration"
    echo "===================================="
    echo "   🖥️  OS: $MANIFEST_OS"
    echo "   ⏱️  Timeout: ${MANIFEST_NTP_TIMEOUT}s"
    echo "   🔄 Retries: ${MANIFEST_NTP_RETRIES}"
    echo "   🌐 Servers:"
    
    local ntp_servers=($(echo "$MANIFEST_NTP_SERVERS" | tr ',' ' '))
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
    echo "   export MANIFEST_NTP_SERVERS='time.apple.com,time.google.com'"
    echo "   export MANIFEST_NTP_TIMEOUT=5"
    echo "   export MANIFEST_NTP_RETRIES=3"
}

# Quick timestamp function for simple operations
get_timestamp() {
    get_ntp_timestamp >/dev/null
    echo "$MANIFEST_NTP_TIMESTAMP"
}

# Get formatted timestamp string
get_formatted_timestamp() {
    get_ntp_timestamp >/dev/null
    format_timestamp "$MANIFEST_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC'
}

# Display OS compatibility information
display_os_info() {
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
