#!/bin/bash

# Manifest OS Detection Module
# Handles OS detection and platform-specific command setup

# OS Detection Variables
MANIFEST_OS=""
MANIFEST_OS_FAMILY=""
MANIFEST_OS_VERSION=""

# Platform-specific command variables
DATE_CMD=""
TIMEOUT_CMD=""
GREP_CMD=""
SED_CMD=""

# OS Detection function
detect_os() {
    echo "🔍 Detecting operating system..."
    
    # Get OS name
    local os_name=$(uname -s)
    local os_version=$(uname -r)
    
    case "$os_name" in
        "Darwin")
            MANIFEST_OS="macOS"
            MANIFEST_OS_FAMILY="unix"
            MANIFEST_OS_VERSION="$os_version"
            setup_macos_commands
            ;;
        "Linux")
            MANIFEST_OS="Linux"
            MANIFEST_OS_FAMILY="unix"
            MANIFEST_OS_VERSION="$os_version"
            setup_linux_commands
            ;;
        "FreeBSD")
            MANIFEST_OS="FreeBSD"
            MANIFEST_OS_FAMILY="unix"
            MANIFEST_OS_VERSION="$os_version"
            setup_bsd_commands
            ;;
        "OpenBSD")
            MANIFEST_OS="OpenBSD"
            MANIFEST_OS_FAMILY="unix"
            MANIFEST_OS_VERSION="$os_version"
            setup_bsd_commands
            ;;
        "NetBSD")
            MANIFEST_OS="NetBSD"
            MANIFEST_OS_FAMILY="unix"
            MANIFEST_OS_VERSION="$os_version"
            setup_bsd_commands
            ;;
        "CYGWIN"*|"MSYS"*|"MINGW"*)
            MANIFEST_OS="Windows"
            MANIFEST_OS_FAMILY="windows"
            MANIFEST_OS_VERSION="$os_version"
            setup_windows_commands
            ;;
        *)
            MANIFEST_OS="Unknown"
            MANIFEST_OS_FAMILY="unknown"
            MANIFEST_OS_VERSION="$os_version"
            setup_fallback_commands
            ;;
    esac
    
    echo "   ✅ Detected: $MANIFEST_OS ($MANIFEST_OS_VERSION)"
    echo "   🔧 Platform: $MANIFEST_OS_FAMILY"
}

# macOS-specific command setup
setup_macos_commands() {
    DATE_CMD="date -u -r"
    TIMEOUT_CMD="gtimeout"  # Requires coreutils installation
    GREP_CMD="grep"
    SED_CMD="sed"
    
    # Check if coreutils is installed for timeout
    if ! command -v gtimeout &> /dev/null; then
        echo "   ⚠️  gtimeout not found, installing coreutils..."
        if command -v brew &> /dev/null; then
            brew install coreutils
            TIMEOUT_CMD="gtimeout"
        else
            echo "   ⚠️  Homebrew not found, using fallback timeout method"
            TIMEOUT_CMD="timeout_fallback"
        fi
    fi
}

# Linux-specific command setup
setup_linux_commands() {
    DATE_CMD="date -u -d"
    TIMEOUT_CMD="timeout"
    GREP_CMD="grep"
    SED_CMD="sed"
}

# BSD-specific command setup
setup_bsd_commands() {
    DATE_CMD="date -u -r"
    TIMEOUT_CMD="timeout"  # May not be available on all BSDs
    GREP_CMD="grep"
    SED_CMD="sed"
    
    # Check if timeout is available
    if ! command -v timeout &> /dev/null; then
        echo "   ⚠️  timeout not available, using fallback method"
        TIMEOUT_CMD="timeout_fallback"
    fi
}

# Windows-specific command setup (Cygwin/MSYS)
setup_windows_commands() {
    DATE_CMD="date -u -d"
    TIMEOUT_CMD="timeout"
    GREP_CMD="grep"
    SED_CMD="sed"
}

# Fallback command setup for unknown platforms
setup_fallback_commands() {
    echo "   ⚠️  Unknown platform, using fallback commands"
    DATE_CMD="date -u"
    TIMEOUT_CMD="timeout_fallback"
    GREP_CMD="grep"
    SED_CMD="sed"
}

# Fallback timeout function for platforms without timeout command
timeout_fallback() {
    local timeout_seconds="$1"
    shift
    
    # Start the command in background
    "$@" &
    local cmd_pid=$!
    
    # Wait for specified timeout
    sleep "$timeout_seconds"
    
    # Check if process is still running
    if kill -0 "$cmd_pid" 2>/dev/null; then
        kill "$cmd_pid" 2>/dev/null
        return 124  # Exit code for timeout
    fi
    
    return 0
}

# Cross-platform date formatting function
format_timestamp_cross_platform() {
    local timestamp="$1"
    local format="$2"
    
    case "$MANIFEST_OS" in
        "macOS"|"FreeBSD"|"OpenBSD"|"NetBSD")
            # Unix timestamp format for macOS/BSD
            $DATE_CMD "$timestamp" "$format"
            ;;
        "Linux"|"Windows")
            # Unix timestamp format for Linux/Windows
            $DATE_CMD "@$timestamp" "$format"
            ;;
        *)
            # Fallback for unknown platforms
            if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                # Try Linux format first
                if $DATE_CMD "@$timestamp" "$format" 2>/dev/null; then
                    return 0
                fi
                # Try macOS format
                if $DATE_CMD "$timestamp" "$format" 2>/dev/null; then
                    return 0
                fi
            fi
            # Last resort: use current time
            date "$format"
            ;;
    esac
}

# Cross-platform timeout function
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    
    if [[ "$TIMEOUT_CMD" == "timeout_fallback" ]]; then
        timeout_fallback "$timeout_seconds" "$@"
    else
        $TIMEOUT_CMD "$timeout_seconds" "$@"
    fi
}

# Display OS information
display_os_info() {
    echo "🖥️  Manifest OS Detection Service"
    echo "=================================="
    echo "   🎯 **Operating System**: $MANIFEST_OS"
    echo "   🔧 **Platform Family**: $MANIFEST_OS_FAMILY"
    echo "   📋 **Version**: $MANIFEST_OS_VERSION"
    echo ""
    echo "   🛠️  **Platform Commands**:"
    echo "      • Date: $DATE_CMD"
    echo "      • Timeout: $TIMEOUT_CMD"
    echo "      • Grep: $GREP_CMD"
    echo "      • Sed: $SED_CMD"
    echo ""
    echo "   ✅ OS detection complete"
}

# Initialize OS detection when module is sourced
detect_os
