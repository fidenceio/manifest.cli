#!/bin/bash

# Manifest OS Detection Module
#
# Records what the host platform is, and provides the cross-platform date and
# timezone helpers. It does NOT select per-platform binaries: see the note below
# on why the command shims were deleted rather than wired up.

# OS Detection Variables
MANIFEST_CLI_OS_NAME=""
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

# There are deliberately NO per-platform command variables here.
#
# This module used to assign MANIFEST_CLI_OS_{DATE,TIMEOUT,GREP,SED}_CMD across
# five platform arms. They were removed 2026-08-31 (TRACKER §65(3)) after
# measuring zero consumers anywhere in the product — every reference was in
# tests/os_helpers.bats, which asserted the assignments the module had just
# made. A test that only checks a value nothing reads keeps dead code alive and
# reports it as covered.
#
# Deleted rather than wired up, for three reasons, in order of weight:
#
#   1. **The production idiom already exists and works.** Where a real BSD/GNU
#      divergence had to be handled, the code does GNU-first with a BSD
#      fallback: `format_timestamp_cross_platform` below tries `date -u -d
#      @<epoch>` then `date -u -r <epoch>`. That needs no platform detection at
#      all, degrades correctly on a platform nobody anticipated, and cannot
#      drift out of agreement with a detection table.
#   2. **Two of the four carried no platform information even in principle.**
#      GREP_CMD and SED_CMD were the bare strings `grep` and `sed` in all five
#      arms. "Wiring them up" would have meant first inventing values that
#      differ per platform.
#   3. **Selecting a binary per platform is the wrong containment for the tool
#      that actually diverges.** The product's least-portable dependency is
#      `awk` (46 raw call sites), and awk differences are extensions —
#      `gensub`, `asort`, `length(array)` — where the fix is to not use them,
#      checkable by a lint, not to pick an implementation at runtime. See §74.
#
# `timeout_fallback` went with them: it existed only as the value TIMEOUT_CMD
# took when `gtimeout` was absent, and had no caller outside its own tests.
# `manifest doctor` is the surface that reports a missing coreutils.

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

# There is no advisory helper here any more either.
#
# A `_manifest_os_advise` was added earlier the same day to route the platform
# setup's warnings to stderr behind the verbose gate, fixing a real defect: they
# were unconditional `echo`s on stdout, emitted at module-source time, and so
# prepended themselves to the output of whatever command the user actually ran.
# Deleting the setup functions removed every caller, and the warnings themselves
# were about which timeout binary had been selected — a selection that no longer
# happens. `manifest doctor` reports a missing coreutils, which is the part the
# user could act on.
#
# Noting it because the helper was correct and still went: the fix that survives
# is the one that deletes the code needing the fix.

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

    # Each arm records WHAT the platform is and nothing more. The arms used to
    # end in a setup_*_commands call that selected per-platform binaries; those
    # are gone (see the note at the top of this file). MANIFEST_CLI_OS_NAME is the
    # one value here with a real consumer, so getting its spelling right matters
    # more than the table's breadth — see tests/os_var_name_agreement.bats.
    MANIFEST_CLI_OS_VERSION="$os_version"
    case "$os_name" in
        "Darwin")
            MANIFEST_CLI_OS_NAME="macOS"
            MANIFEST_CLI_OS_FAMILY="unix"
            ;;
        "Linux")
            MANIFEST_CLI_OS_NAME="Linux"
            MANIFEST_CLI_OS_FAMILY="unix"
            ;;
        "FreeBSD"|"OpenBSD"|"NetBSD")
            MANIFEST_CLI_OS_NAME="$os_name"
            MANIFEST_CLI_OS_FAMILY="unix"
            ;;
        "CYGWIN"*|"MSYS"*|"MINGW"*)
            MANIFEST_CLI_OS_NAME="Windows"
            MANIFEST_CLI_OS_FAMILY="windows"
            ;;
        *)
            MANIFEST_CLI_OS_NAME="Unknown"
            MANIFEST_CLI_OS_FAMILY="unknown"
            ;;
    esac

    if [ "$verbose" = "1" ]; then
        echo "   ✅ Detected: $MANIFEST_CLI_OS_NAME ($MANIFEST_CLI_OS_VERSION)"
        echo "   🔧 Platform: $MANIFEST_CLI_OS_FAMILY"
    fi

    # Detect bash version and capabilities
    detect_bash_version
    [ "$verbose" = "1" ] && echo "   🐍 Bash: $MANIFEST_CLI_OS_BASH_VERSION (required: ${MANIFEST_CLI_REQUIRED_BASH_VERSION:-5}+)"

    MANIFEST_CLI_OS_DETECTED=1
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
