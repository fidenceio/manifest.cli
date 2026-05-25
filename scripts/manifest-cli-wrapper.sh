#!/bin/bash

# Manifest CLI Wrapper
# Sources the actual CLI from the project directory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Locate the installed CLI tree. The wrapper lives in a bin directory
# (typically $HOME/.local/bin) while modules live elsewhere (typically
# $HOME/.manifest-cli/modules/), so we cannot assume modules sit at
# $SCRIPT_DIR/../modules/. Must run before any module source.
find_cli_dir() {
    local possible_dirs=(
        "${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"
        "$HOME/.manifest-cli"
    )

    # Dev mode: wrapper lives at <repo>/scripts/manifest-cli-wrapper.sh with
    # modules at <repo>/modules/. realpath resolves symlinks so a symlinked
    # wrapper still finds the real source tree.
    if command -v realpath >/dev/null 2>&1; then
        possible_dirs+=("$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")")
    else
        possible_dirs+=("$(dirname "$SCRIPT_DIR")")
    fi

    for dir in "${possible_dirs[@]}"; do
        if [ -f "$dir/modules/core/manifest-core.sh" ]; then
            echo "$dir"
            return 0
        fi
    done

    echo "ERROR: Could not find Manifest CLI installation directory" >&2
    exit 1
}

CLI_DIR="$(find_cli_dir)"

# shellcheck disable=SC1091
source "$CLI_DIR/modules/core/manifest-requirements.sh"

# Require the centralized Bash runtime version. If possible, re-exec into it.
ensure_bash5_or_reexec() {
    local current_major="${BASH_VERSINFO[0]:-0}"

    if manifest_requirement_bash_is_supported_major "$current_major"; then
        return 0
    fi

    local candidate major
    local candidates=(
        "${MANIFEST_CLI_BASH_PATH:-}"
        "/opt/homebrew/bin/bash"
        "/usr/local/bin/bash"
        "$(command -v bash 2>/dev/null || true)"
        "/bin/bash"
    )

    for candidate in "${candidates[@]}"; do
        if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
            continue
        fi
        major="$(manifest_requirement_bash_major_from_command "$candidate")"
        if manifest_requirement_bash_is_supported_major "$major"; then
            MANIFEST_CLI_BASH_REEXEC=1 exec "$candidate" "$0" "$@"
        fi
    done

    echo "❌ Manifest CLI requires Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+." >&2
    echo "   Current shell: bash ${BASH_VERSION:-unknown}" >&2
    echo "   No compatible bash found in common locations." >&2
    echo "   Install Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+ and retry:" >&2
    echo "     macOS: brew install bash" >&2
    echo "     Debian/Ubuntu: sudo apt-get install bash" >&2
    echo "     RHEL/Fedora: sudo dnf install bash" >&2
    return 1
}

ensure_bash5_or_reexec "$@"

# shellcheck disable=SC1091
source "$CLI_DIR/modules/core/manifest-core.sh"

# Call the main function
main "$@"
