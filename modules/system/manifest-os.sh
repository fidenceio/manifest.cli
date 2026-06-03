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
    if [ -n "${BASH_VERSION:-}" ]; then
        MANIFEST_CLI_OS_BASH_VERSION="${BASH_VERSION%%[^0-9.]*}"
        MANIFEST_CLI_OS_BASH_MAJOR="${BASH_VERSINFO[0]:-0}"
        MANIFEST_CLI_OS_BASH_MINOR="${BASH_VERSINFO[1]:-0}"

        # Check for double bracket support (bash 2.02+)
        if [ "$MANIFEST_CLI_OS_BASH_MAJOR" -gt 2 ] || ([ "$MANIFEST_CLI_OS_BASH_MAJOR" -eq 2 ] && [ "$MANIFEST_CLI_OS_BASH_MINOR" -ge 2 ]); then
            MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS=true
        fi

        # Check for associative arrays (bash 4.0+)
        if [ "$MANIFEST_CLI_OS_BASH_MAJOR" -ge 4 ]; then
            MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS=true
        fi
    else
        MANIFEST_CLI_OS_BASH_VERSION="Unknown"
        MANIFEST_CLI_OS_BASH_MAJOR="0"
        MANIFEST_CLI_OS_BASH_MINOR="0"
    fi
}

# OS Detection function. Idempotent: re-sourcing the module or calling
# detect_os a second time is a no-op. Output is gated behind verbose
# mode (`MANIFEST_CLI_VERBOSE=1` or `MANIFEST_CLI_DEBUG=1`); the
# detection itself always runs, only the preamble is suppressed.
detect_os() {
    if [ -n "${MANIFEST_CLI_OS_DETECTED:-}" ]; then
        return 0
    fi

    local verbose=0
    if [ "${MANIFEST_CLI_VERBOSE:-0}" = "1" ] || [ "${MANIFEST_CLI_DEBUG:-0}" = "1" ]; then
        verbose=1
    fi

    [ "$verbose" = "1" ] && echo "🔍 Detecting operating system..."

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

    if [ "$verbose" = "1" ]; then
        echo "   ✅ Detected: $MANIFEST_CLI_OS_OS ($MANIFEST_CLI_OS_VERSION)"
        echo "   🔧 Platform: $MANIFEST_CLI_OS_FAMILY"
    fi

    # Detect bash version and capabilities
    detect_bash_version
    [ "$verbose" = "1" ] && echo "   🐍 Bash: $MANIFEST_CLI_OS_BASH_VERSION ([[ ]]: $MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS, Arrays: $MANIFEST_CLI_OS_BASH_SUPPORTS_ASSOCIATIVE_ARRAYS)"

    MANIFEST_CLI_OS_DETECTED=1
}

# macOS-specific command setup
setup_macos_commands() {
    # GNU userland is forced onto PATH (coreutils + gnu-sed gnubin), so date
    # takes the GNU `-d @<epoch>` form here too — same as Linux.
    MANIFEST_CLI_OS_DATE_CMD="date -u -d"
    MANIFEST_CLI_OS_TIMEOUT_CMD="gtimeout"  # Requires coreutils installation
    MANIFEST_CLI_OS_GREP_CMD="grep"
    MANIFEST_CLI_OS_SED_CMD="sed"

    # Check if coreutils is installed for timeout
    if ! command -v gtimeout &> /dev/null; then
        echo "   ⚠️  gtimeout not found, using fallback timeout method"
        echo "   ℹ️  Install coreutils for the supported macOS timeout command"
        MANIFEST_CLI_OS_TIMEOUT_CMD="timeout_fallback"
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
    # Non-macOS BSDs have no Homebrew gnubin to force onto PATH, so the native
    # BSD date keeps the `-r <epoch>` form. (macOS is handled in setup_macos_commands.)
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
#
# GNU-first: macOS now runs the GNU `-d @<epoch>` form too, because the wrapper
# forces coreutils' gnubin onto PATH. The BSD `-r <epoch>` form is kept ONLY as
# a fallback for native BSDs (FreeBSD/OpenBSD/NetBSD) and unknown platforms with
# no GNU date — it is never tried first, so it cannot mis-fire under GNU.
format_timestamp_cross_platform() {
    local timestamp="$1"
    local format="$2"
    local timezone="${MANIFEST_CLI_TIMEZONE:-UTC}"

    # For UTC, use the -u flag for simplicity and accuracy
    if [ "$timezone" = "UTC" ]; then
        date -u -d "@$timestamp" "$format" 2>/dev/null && return 0
        date -u -r "$timestamp" "$format" 2>/dev/null && return 0  # native-BSD fallback
        date -u "$format"
    else
        # Use TZ environment variable for non-UTC timezones
        TZ="$timezone" date -d "@$timestamp" "$format" 2>/dev/null && return 0
        TZ="$timezone" date -r "$timestamp" "$format" 2>/dev/null && return 0  # native-BSD fallback
        TZ="$timezone" date "$format"
    fi
}

# Get the timezone abbreviation/offset for display
# Returns the timezone abbreviation (e.g., "EST", "PST") or offset (e.g., "+0530")
# GNU-first; native-BSD `-r` only as a fallback (see format_timestamp_cross_platform).
get_timezone_display() {
    local timestamp="${1:-$(date +%s)}"
    local timezone="${MANIFEST_CLI_TIMEZONE:-UTC}"

    if [ "$timezone" = "UTC" ]; then
        echo "UTC"
        return 0
    fi

    # Get the timezone abbreviation at the given timestamp
    TZ="$timezone" date -d "@$timestamp" '+%Z' 2>/dev/null && return 0
    TZ="$timezone" date -r "$timestamp" '+%Z' 2>/dev/null && return 0  # native-BSD fallback
    echo "$timezone"
}

# Cross-platform timeout function
# Bash-compatible comparison functions
# These functions use the appropriate syntax based on bash version
compare_strings() {
    local str1="$1"
    local op="$2"
    local str2="$3"

    # Operators are matched explicitly rather than expanded dynamically inside
    # a test expression. A dynamic operator (`[ "$a" $op "$b" ]`) is fragile —
    # it cannot be statically analyzed and breaks if the operand looks like a
    # flag. `[ ... ]` with literal string operators works identically on Bash
    # 3.2 and 5+, so no version branch is needed for string comparison.
    case "$op" in
        "!=")      [ "$str1" != "$str2" ] ;;
        "=="|"=")  [ "$str1" = "$str2" ] ;;
        *)
            echo "compare_strings: unsupported operator '$op'" >&2
            return 2
            ;;
    esac
}

check_string_empty() {
    local str="$1"
    
    if [ "$MANIFEST_CLI_OS_BASH_SUPPORTS_DOUBLE_BRACKETS" = "true" ]; then
        [[ -z "$str" ]]
    else
        [ -z "$str" ]
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
# Initialize OS detection when module is sourced
detect_os
