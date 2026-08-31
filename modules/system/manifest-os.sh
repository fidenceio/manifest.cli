#!/bin/bash

# Manifest OS Detection Module
# Handles OS detection and platform-specific command setup

# OS Detection Variables
MANIFEST_CLI_OS_OS=""
MANIFEST_CLI_OS_FAMILY=""
MANIFEST_CLI_OS_VERSION=""

# Bash version, recorded for display only.
#
# There are deliberately NO capability flags here. The runtime floor is Bash 5+
# and it is enforced before any module loads: `ensure_bash5_or_reexec` in both
# entry points re-execs into a Bash 5 if the current shell is older and exits
# with "requires Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+" when it cannot
# find one. So `[[ ]]` (2.02+) and associative arrays (4.0+) are guaranteed, not
# contingent, and a flag asking whether they are available can only ever hold
# one value.
#
# This module used to carry `..._SUPPORTS_DOUBLE_BRACKETS` and
# `..._SUPPORTS_ASSOCIATIVE_ARRAYS`, both computed per run and both structurally
# `true`. They are gone rather than pinned to true: a constant dressed as a
# probe invites callers to branch on it, and every such branch is unreachable
# code that tests can only reach by falsifying the variable — which is what
# `tests/os_helpers.bats` was doing.
MANIFEST_CLI_OS_BASH_VERSION=""
MANIFEST_CLI_OS_BASH_MAJOR=""
MANIFEST_CLI_OS_BASH_MINOR=""

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
    else
        MANIFEST_CLI_OS_BASH_VERSION="Unknown"
        MANIFEST_CLI_OS_BASH_MAJOR="0"
        MANIFEST_CLI_OS_BASH_MINOR="0"
    fi
}

# Advisory output from the platform setup below.
#
# Routed through one helper for two reasons. It goes to STDERR, because this
# module runs at source time — `detect_os` is called on load — so anything on
# stdout prepends itself to whatever the invoked command was asked to print,
# including machine-readable output. And it respects the same verbose gate as
# `detect_os`'s own banner, because the module's stated contract is to be
# silent by default; `tests/os_detection_preamble.bats` asserts exactly that.
#
# These advisories used to be unconditional `echo`s. They were invisible on any
# machine that had the tools — a developer host, and CI — and appeared only on
# the machines that did not, which is the population the advice is for and the
# one nobody tests on. `manifest doctor` is the surface that reports a missing
# coreutils; this stays a verbose-mode detail.
_manifest_os_advise() {
    if [ "${MANIFEST_CLI_VERBOSE:-0}" = "1" ] || [ "${MANIFEST_CLI_DEBUG:-0}" = "1" ]; then
        printf '%s\n' "$1" >&2
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
    [ "$verbose" = "1" ] && echo "   🐍 Bash: $MANIFEST_CLI_OS_BASH_VERSION (required: ${MANIFEST_CLI_REQUIRED_BASH_VERSION:-5}+)"

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
        _manifest_os_advise "   ⚠️  gtimeout not found, using fallback timeout method"
        _manifest_os_advise "   ℹ️  Install coreutils for the supported macOS timeout command"
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
        _manifest_os_advise "   ⚠️  timeout not available, using fallback method"
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
    _manifest_os_advise "   ⚠️  Unknown platform, using fallback commands"
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

    # IANA names are Area/Location (letters, digits, _, -, +, /). Reject anything
    # else — especially ".." — before interpolating into zoneinfo paths.
    case "$timezone" in
        *..*|*[!A-Za-z0-9_/+-]*)
            echo "$timezone"
            return 0
            ;;
    esac

    # Without zoneinfo for this IANA name, date often still exits 0 and prints a
    # misleading label (UTC, or a path fragment). Prefer the IANA name over a
    # wrong short abbreviation when the zone database entry is missing.
    if [ ! -e "/usr/share/zoneinfo/$timezone" ] \
        && [ ! -e "/var/db/timezone/zoneinfo/$timezone" ]; then
        echo "$timezone"
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

# Both of these carried a `[[ ]]`-vs-`[ ]` version branch until the Bash 5+ floor
# made it unreachable — see the note on the removed capability flags above. The
# branch was doubly empty: for a single `-z`/`-d` test on a quoted operand the two
# forms are exactly equivalent, so each arm did the same thing. `compare_strings`
# below had already been collapsed for that reason and says so; these two were
# missed, and a test kept the dead arm alive by setting the flag to false by hand.
check_string_empty() {
    local str="$1"
    [[ -z "$str" ]]
}

check_directory_exists() {
    local dir="$1"
    [[ -d "$dir" ]]
}

# Pure classifier: does an Apple build identifier denote a pre-release seed?
# Apple seed builds (developer/public betas, RCs) carry a trailing lowercase
# letter — e.g. 26A5353q — while shipping builds end in a digit — e.g. 23A344.
# Kept separate from the environment lookup so it is trivially unit-testable.
# Returns 0 (pre-release) / 1 (release or unrecognized).
manifest_os_build_id_is_prerelease() {
    local build="$1"
    [ -n "$build" ] || return 1
    case "$build" in
        *[a-z]) return 0 ;;
        *)      return 1 ;;
    esac
}

# Is the host running a macOS pre-release (beta/RC/seed)? Used only to enrich
# advisory messaging — never to gate behavior — so an imperfect read is harmless.
# Two signals: a ProductVersionExtra entry (present on betas/RCs/RSRs), else the
# build-id seed signature above. Returns 0 (pre-release) / 1 (release or non-mac).
manifest_os_macos_is_prerelease() {
    [ "$(uname -s 2>/dev/null)" = "Darwin" ] || return 1
    command -v sw_vers >/dev/null 2>&1 || return 1
    if sw_vers 2>/dev/null | grep -q 'ProductVersionExtra'; then
        return 0
    fi
    manifest_os_build_id_is_prerelease "$(sw_vers -buildVersion 2>/dev/null)"
}

# Display OS information
# Initialize OS detection when module is sourced
detect_os
