#!/bin/bash

# Manifest OS Detection Module
# Handles OS detection and platform-specific command setup

# OS Detection Variables
MANIFEST_CLI_OS_OS=""
MANIFEST_CLI_OS_FAMILY=""
MANIFEST_CLI_OS_VERSION=""

# Bash compatibility variables
MANIFEST_CLI_OS_BASH_VERSION=""
MANIFEST_CLI_OS_BASH_MAJOR=""
MANIFEST_CLI_OS_BASH_MINOR=""
MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS=false
MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS=false

# Platform-specific command variables
MANIFEST_CLI_OS_DATE_CMD=""
MANIFEST_CLI_OS_TIMEOUT_CMD=""
MANIFEST_CLI_OS_GREP_CMD=""
MANIFEST_CLI_OS_SED_CMD=""

# Bash version detection function
detect_bash_version() {
    if command -v bash >/dev/null 2>&1; then
        MANIFEST_CLI_OS_BASH_VERSION=$(bash --version | head -n1 | grep -oE 'version [0-9]+\.[0-9]+' | cut -d' ' -f2)
        if [ -n "$MANIFEST_CLI_OS_BASH_VERSION" ]; then
            MANIFEST_CLI_OS_BASH_MAJOR=$(echo "$MANIFEST_CLI_OS_BASH_VERSION" | cut -d'.' -f1)
            MANIFEST_CLI_OS_BASH_MINOR=$(echo "$MANIFEST_CLI_OS_BASH_VERSION" | cut -d'.' -f2)
            
            # Check for double bracket support (bash 2.02+)
            if [ "$MANIFEST_CLI_OS_BASH_MAJOR" -gt 2 ] || ([ "$MANIFEST_CLI_OS_BASH_MAJOR" -eq 2 ] && [ "$MANIFEST_CLI_OS_BASH_MINOR" -ge 2 ]); then
                MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS=true
            fi
            
            # Check for associative arrays (bash 4.0+)
            if [ "$MANIFEST_CLI_OS_BASH_MAJOR" -ge 4 ]; then
                MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS=true
            fi
        fi
    else
        MANIFEST_CLI_OS_BASH_VERSION="Unknown"
        MANIFEST_CLI_OS_BASH_MAJOR="0"
        MANIFEST_CLI_OS_BASH_MINOR="0"
    fi
}

# OS Detection function
detect_os() {
    echo "🔍 Detecting operating system..."
    
    # Get OS name
    local os_name=$(uname -s)
    local os_version=$(uname -r)
    
    case "$os_name" in
        "Darwin")
            MANIFEST_CLI_OS_OS="macOS"
            MANIFEST_CLI_OS_FAMILY="unix"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_macos_commands
            ;;
        "Linux")
            MANIFEST_CLI_OS_OS="Linux"
            MANIFEST_CLI_OS_FAMILY="unix"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_linux_commands
            ;;
        "FreeBSD")
            MANIFEST_CLI_OS_OS="FreeBSD"
            MANIFEST_CLI_OS_FAMILY="unix"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_bsd_commands
            ;;
        "OpenBSD")
            MANIFEST_CLI_OS_OS="OpenBSD"
            MANIFEST_CLI_OS_FAMILY="unix"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_bsd_commands
            ;;
        "NetBSD")
            MANIFEST_CLI_OS_OS="NetBSD"
            MANIFEST_CLI_OS_FAMILY="unix"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_bsd_commands
            ;;
        "CYGWIN"*|"MSYS"*|"MINGW"*)
            MANIFEST_CLI_OS_OS="Windows"
            MANIFEST_CLI_OS_FAMILY="windows"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_windows_commands
            ;;
        *)
            MANIFEST_CLI_OS_OS="Unknown"
            MANIFEST_CLI_OS_FAMILY="unknown"
            MANIFEST_CLI_OS_VERSION="$os_version"
            setup_fallback_commands
            ;;
    esac
    
    echo "   ✅ Detected: $MANIFEST_CLI_OS_OS ($MANIFEST_CLI_OS_VERSION)"
    echo "   🔧 Platform: $MANIFEST_CLI_OS_FAMILY"
    
    # Detect bash version and capabilities
    detect_bash_version
    echo "   🐍 Bash: $MANIFEST_CLI_OS_BASH_VERSION ([[ ]]: $MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS, Arrays: $MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS)"
}

# macOS-specific command setup
setup_macos_commands() {
    MANIFEST_CLI_OS_DATE_CMD="date -u -r"
    MANIFEST_CLI_OS_TIMEOUT_CMD="gtimeout"  # Requires coreutils installation
    MANIFEST_CLI_OS_GREP_CMD="grep"
    MANIFEST_CLI_OS_SED_CMD="sed"
    
    # Check if coreutils is installed for timeout
    if ! command -v gtimeout &> /dev/null; then
        echo "   ⚠️  gtimeout not found, installing coreutils..."
        if command -v brew &> /dev/null; then
            brew install coreutils
            MANIFEST_CLI_OS_TIMEOUT_CMD="gtimeout"
        else
            echo "   ⚠️  Homebrew not found, using fallback timeout method"
            MANIFEST_CLI_OS_TIMEOUT_CMD="timeout_fallback"
        fi
    fi
}

# Linux-specific command setup
setup_linux_commands() {
    MANIFEST_CLI_OS_DATE_CMD="date -u -d"
    MANIFEST_CLI_OS_TIMEOUT_CMD="timeout"
    MANIFEST_CLI_OS_GREP_CMD="grep"
    MANIFEST_CLI_OS_SED_CMD="sed"
}

# BSD-specific command setup
setup_bsd_commands() {
    MANIFEST_CLI_OS_DATE_CMD="date -u -r"
    MANIFEST_CLI_OS_TIMEOUT_CMD="timeout"  # May not be available on all BSDs
    MANIFEST_CLI_OS_GREP_CMD="grep"
    MANIFEST_CLI_OS_SED_CMD="sed"
    
    # Check if timeout is available
    if ! command -v timeout &> /dev/null; then
        echo "   ⚠️  timeout not available, using fallback method"
        MANIFEST_CLI_OS_TIMEOUT_CMD="timeout_fallback"
    fi
}

# Windows-specific command setup (Cygwin/MSYS)
setup_windows_commands() {
    MANIFEST_CLI_OS_DATE_CMD="date -u -d"
    MANIFEST_CLI_OS_TIMEOUT_CMD="timeout"
    MANIFEST_CLI_OS_GREP_CMD="grep"
    MANIFEST_CLI_OS_SED_CMD="sed"
}

# Fallback command setup for unknown platforms
setup_fallback_commands() {
    echo "   ⚠️  Unknown platform, using fallback commands"
    MANIFEST_CLI_OS_DATE_CMD="date -u"
    MANIFEST_CLI_OS_TIMEOUT_CMD="timeout_fallback"
    MANIFEST_CLI_OS_GREP_CMD="grep"
    MANIFEST_CLI_OS_SED_CMD="sed"
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
# Uses MANIFEST_CLI_TIMEZONE for timezone support (defaults to UTC)
format_timestamp_cross_platform() {
    local timestamp="$1"
    local format="$2"
    local timezone="${MANIFEST_CLI_TIMEZONE:-UTC}"

    # For UTC, use the -u flag for simplicity and accuracy
    if [ "$timezone" = "UTC" ]; then
        case "$MANIFEST_CLI_OS_OS" in
            "macOS"|"FreeBSD"|"OpenBSD"|"NetBSD")
                date -u -r "$timestamp" "$format"
                ;;
            "Linux"|"Windows")
                date -u -d "@$timestamp" "$format"
                ;;
            *)
                # Fallback for unknown platforms
                if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                    if date -u -d "@$timestamp" "$format" 2>/dev/null; then
                        return 0
                    fi
                    if date -u -r "$timestamp" "$format" 2>/dev/null; then
                        return 0
                    fi
                fi
                date -u "$format"
                ;;
        esac
    else
        # Use TZ environment variable for non-UTC timezones
        case "$MANIFEST_CLI_OS_OS" in
            "macOS"|"FreeBSD"|"OpenBSD"|"NetBSD")
                TZ="$timezone" date -r "$timestamp" "$format"
                ;;
            "Linux"|"Windows")
                TZ="$timezone" date -d "@$timestamp" "$format"
                ;;
            *)
                # Fallback for unknown platforms
                if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                    if TZ="$timezone" date -d "@$timestamp" "$format" 2>/dev/null; then
                        return 0
                    fi
                    if TZ="$timezone" date -r "$timestamp" "$format" 2>/dev/null; then
                        return 0
                    fi
                fi
                TZ="$timezone" date "$format"
                ;;
        esac
    fi
}

# Get the timezone abbreviation/offset for display
# Returns the timezone abbreviation (e.g., "EST", "PST") or offset (e.g., "+0530")
get_timezone_display() {
    local timestamp="${1:-$(date +%s)}"
    local timezone="${MANIFEST_CLI_TIMEZONE:-UTC}"

    if [ "$timezone" = "UTC" ]; then
        echo "UTC"
        return 0
    fi

    # Get the timezone abbreviation at the given timestamp
    case "$MANIFEST_CLI_OS_OS" in
        "macOS"|"FreeBSD"|"OpenBSD"|"NetBSD")
            TZ="$timezone" date -r "$timestamp" '+%Z'
            ;;
        "Linux"|"Windows")
            TZ="$timezone" date -d "@$timestamp" '+%Z'
            ;;
        *)
            if TZ="$timezone" date -d "@$timestamp" '+%Z' 2>/dev/null; then
                return 0
            fi
            if TZ="$timezone" date -r "$timestamp" '+%Z' 2>/dev/null; then
                return 0
            fi
            echo "$timezone"
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

# Bash-compatible comparison functions
# These functions use the appropriate syntax based on bash version
compare_strings() {
    local str1="$1"
    local op="$2"
    local str2="$3"
    
    if [ "$MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS" = "true" ]; then
        case "$op" in
            "!=") [[ "$str1" != "$str2" ]] ;;
            "==") [[ "$str1" == "$str2" ]] ;;
            "=")  [[ "$str1" = "$str2" ]] ;;
            *)    [ "$str1" $op "$str2" ] ;;
        esac
    else
        [ "$str1" $op "$str2" ]
    fi
}

check_string_empty() {
    local str="$1"
    
    if [ "$MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS" = "true" ]; then
        [[ -z "$str" ]]
    else
        [ -z "$str" ]
    fi
}

check_string_not_empty() {
    local str="$1"
    
    if [ "$MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS" = "true" ]; then
        [[ -n "$str" ]]
    else
        [ -n "$str" ]
    fi
}

check_file_exists() {
    local file="$1"
    
    if [ "$MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS" = "true" ]; then
        [[ -f "$file" ]]
    else
        [ -f "$file" ]
    fi
}

check_directory_exists() {
    local dir="$1"
    
    if [ "$MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS" = "true" ]; then
        [[ -d "$dir" ]]
    else
        [ -d "$dir" ]
    fi
}

# Display OS information
display_os_info() {
    echo "🖥️  Manifest OS Detection Service"
    echo "=================================="
    echo "   🎯 **Operating System**: $MANIFEST_CLI_OS_OS"
    echo "   🔧 **Platform Family**: $MANIFEST_CLI_OS_FAMILY"
    echo "   📋 **Version**: $MANIFEST_CLI_OS_VERSION"
    echo ""
    echo "   🐍 **Bash Compatibility**:"
    echo "      • Version: $MANIFEST_CLI_OS_BASH_VERSION"
    echo "      • Double Brackets ([[ ]]): $MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS"
    echo "      • Associative Arrays: $MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS"
    echo ""
    echo "   🛠️  **Platform Commands**:"
    echo "      • Date: $MANIFEST_CLI_OS_DATE_CMD"
    echo "      • Timeout: $MANIFEST_CLI_OS_TIMEOUT_CMD"
    echo "      • Grep: $MANIFEST_CLI_OS_GREP_CMD"
    echo "      • Sed: $MANIFEST_CLI_OS_SED_CMD"
    echo ""
    echo "   ✅ OS detection complete"
}

# Initialize OS detection when module is sourced
detect_os
