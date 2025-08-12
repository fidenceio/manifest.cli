#!/bin/bash

# Manifest NTP Module
# Handles NTP timestamp functionality for trusted manifest operations

# NTP Configuration
MANIFEST_NTP_SERVERS=${MANIFEST_NTP_SERVERS:-"time.apple.com,time.google.com,pool.ntp.org,time.nist.gov,time.cloudflare.com,time.windows.com"}
MANIFEST_NTP_TIMEOUT=${MANIFEST_NTP_TIMEOUT:-5}
MANIFEST_NTP_PRIORITY=${MANIFEST_NTP_PRIORITY:-"external,localhost,system"}

get_ntp_timestamp() {
    # Use configured NTP servers or fall back to defaults
    local ntp_servers=($(echo "$MANIFEST_NTP_SERVERS" | tr ',' ' '))
    local timeout="$MANIFEST_NTP_TIMEOUT"
    local priority="$MANIFEST_NTP_PRIORITY"
    
    # Prioritize external NTP servers, fall back to localhost only as last resort
    local timestamp=""
    local offset=""
    local ntp_success=false
    
    echo "🕐 Getting trusted NTP timestamp..."
    echo "   🎯 Priority: External NTP servers → Localhost fallback"
    
    # First, try external NTP servers
    for server in "${ntp_servers[@]}"; do
        echo "   🔍 Querying external server: $server ()..."
        local ntp_result=$(sntp "$server" 2>/dev/null | tail -1)
        
        if [ $? -eq 0 ] && [ -n "$ntp_result" ]; then
            # Simple parsing: extract offset from sntp output
            # Format: -0.006208 +/- 0.017504 time.apple.com 17.253.6.45
            local offset=$(echo "$ntp_result" | awk '{print $1}')
            
            if [[ "$offset" =~ ^[+-][0-9]+\.[0-9]+$ ]]; then
                # Calculate trusted timestamp
                local current_time=$(date -u +%s)
                local ntp_offset_seconds=$(echo "$offset" | sed 's/+//' | sed 's/-//')
                local ntp_offset_sign=$(echo "$offset" | cut -c1)
                
                if [ "$ntp_offset_sign" = "+" ]; then
                    timestamp=$((current_time + ntp_offset_seconds))
                else
                    timestamp=$((current_time - ntp_offset_seconds))
                fi
                
                echo "   ✅ External NTP timestamp obtained from $server"
                echo "   📊 Offset: $offset seconds"
                # Use date command compatible with both Linux and macOS
                if date -d "@$timestamp" >/dev/null 2>&1; then
                    # Linux date command
                    echo "   🕐 Trusted timestamp: $(date -u -d "@$timestamp" '+%Y-%m-%d %H:%M:%S UTC')"
                else
                    # macOS date command
                    echo "   🕐 Trusted timestamp: $(date -u -r "$timestamp" '+%Y-%m-%d %H:%M:%S UTC')"
                fi
                ntp_success=true
                break
            fi
        else
            echo "   ⚠️  Failed to query external server: $server"
        fi
    done
    
    # If external NTP servers failed, try localhost as fallback
    if [ "$ntp_success" = false ]; then
        echo "   🔄 External NTP servers unavailable, trying localhost fallback..."
        echo "   🔍 Querying localhost..."
        
        local localhost_result=$(sntp "127.0.0.1" 2>/dev/null | tail -1)
        if [ $? -eq 0 ] && [ -n "$localhost_result" ]; then
            local offset=$(echo "$localhost_result" | awk '{print $1}')
            
            if [[ "$offset" =~ ^[+-][0-9]+\.[0-9]+$ ]]; then
                local current_time=$(date -u +%s)
                local ntp_offset_seconds=$(echo "$offset" | sed 's/+//' | sed 's/-//')
                local ntp_offset_sign=$(echo "$offset" | cut -c1)
                
                if [ "$ntp_offset_sign" = "+" ]; then
                    timestamp=$((current_time + ntp_offset_seconds))
                else
                    timestamp=$((current_time - ntp_offset_seconds))
                fi
                
                echo "   ✅ Localhost NTP timestamp obtained"
                echo "   📊 Offset: $offset seconds"
                if date -d "@$timestamp" >/dev/null 2>&1; then
                    echo "   🕐 Trusted timestamp: $(date -u -d "@$timestamp" '+%Y-%m-%d %H:%M:%S UTC')"
                else
                    echo "   🕐 Trusted timestamp: $(date -u -r "$timestamp" '+%Y-%m-%d %H:%M:%S UTC')"
                fi
                ntp_success=true
            fi
        else
            echo "   ⚠️  Localhost NTP also failed"
        fi
    fi
    
    # Final fallback to system time if all NTP methods fail
    if [ "$ntp_success" = false ]; then
        echo "   ❌ All NTP methods failed, using system time as last resort"
        timestamp=$(date -u +%s)
        offset="0.000000"
        uncertainty="0.000000"
        server_name="system"
        server_ip="127.0.0.1"
        echo "   ⚠️  System time used - not NTP verified"
    fi
    
    # Export timestamp variables for use in other functions
    export MANIFEST_NTP_TIMESTAMP="$timestamp"
    export MANIFEST_NTP_OFFSET="$offset"
    export MANIFEST_NTP_UNCERTAINTY="$uncertainty"
    export MANIFEST_NTP_SERVER="$server_name"
    export MANIFEST_NTP_SERVER_IP="$server_ip"
    
    echo "   🎯 NTP timestamp ready for manifest operations"
    echo ""
}

format_timestamp() {
    local timestamp="$1"
    local format="$2"
    
    # Use date command compatible with both Linux and macOS
    if date -d "@$timestamp" >/dev/null 2>&1; then
        # Linux date command
        date -u -d "@$timestamp" "$format"
    else
        # macOS date command
        date -u -r "$timestamp" "$format"
    fi
}

display_ntp_info() {
    echo "🕐 Manifest NTP Timestamp Service"
    echo "=================================="
    
    # Get NTP timestamp
    get_ntp_timestamp
    
    # Display NTP information
    echo "🕐 **Trusted NTP Timestamp**: $(format_timestamp "$MANIFEST_NTP_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')"
    echo "   📊 **NTP Offset**: $MANIFEST_NTP_OFFSET seconds"
    echo "   🎯 **Uncertainty**: ±$MANIFEST_NTP_UNCERTAINTY seconds"
    echo "   🌐 **NTP Server**: $MANIFEST_NTP_SERVER ($MANIFEST_NTP_SERVER_IP)"
    echo ""
    echo "�� Use this timestamp for trusted manifest operations"
}

display_ntp_config() {
    echo "⚙️  Manifest NTP Configuration"
    echo "================================"
    echo "   🎯 **Priority**: $MANIFEST_NTP_PRIORITY"
    echo "   ⏱️  **Timeout**: ${MANIFEST_NTP_TIMEOUT}s"
    echo "   🌐 **Servers**:"
    
    local ntp_servers=($(echo "$MANIFEST_NTP_SERVERS" | tr ',' ' '))
    for server in "${ntp_servers[@]}"; do
        case "$server" in
            "time.apple.com")
                echo "   • time.apple.com (Apple)"
                ;;
            "time.google.com")
                echo "   • time.google.com (Google)"
                ;;
            "pool.ntp.org")
                echo "   • pool.ntp.org (NTP Pool)"
                ;;
            "time.nist.gov")
                echo "   • time.nist.gov (NIST)"
                ;;
            "time.cloudflare.com")
                echo "   • time.cloudflare.com (Cloudflare)"
                ;;
            "time.windows.com")
                echo "   • time.windows.com (Microsoft)"
                ;;
            *)
                echo "   • $server"
                ;;
        esac
    done
    
    echo ""
    echo "💡 **Configuration**: Set MANIFEST_NTP_* environment variables to customize"
    echo "   Example: export MANIFEST_NTP_SERVERS='time.apple.com,time.google.com'"
}
