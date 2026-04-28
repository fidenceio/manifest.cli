#!/bin/bash

# Manifest CLI - New Modular Version
# A powerful command-line tool for Git operations and version management

set -eo pipefail

# Require Bash 5+ at runtime. If possible, re-exec into a newer bash.
ensure_bash5_or_reexec() {
    local min_major=5
    local current_major="${BASH_VERSINFO[0]:-0}"

    if [ "$current_major" -ge "$min_major" ]; then
        return 0
    fi

    if [ "${MANIFEST_CLI_BASH_REEXEC:-0}" = "1" ]; then
        echo "❌ Manifest CLI requires Bash 5+." >&2
        echo "   Current shell: bash ${BASH_VERSION:-unknown}" >&2
        echo "   Install Bash 5+ and retry:" >&2
        echo "     macOS: brew install bash" >&2
        echo "     Debian/Ubuntu: sudo apt-get install bash" >&2
        echo "     RHEL/Fedora: sudo dnf install bash" >&2
        return 1
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
        major="$("$candidate" -c 'echo "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || echo "0")"
        if [ "$major" -ge "$min_major" ]; then
            MANIFEST_CLI_BASH_REEXEC=1 exec "$candidate" "$0" "$@"
        fi
    done

    echo "❌ Manifest CLI requires Bash 5+." >&2
    echo "   Current shell: bash ${BASH_VERSION:-unknown}" >&2
    echo "   No compatible bash found in common locations." >&2
    echo "   Install Bash 5+ and retry:" >&2
    echo "     macOS: brew install bash" >&2
    echo "     Debian/Ubuntu: sudo apt-get install bash" >&2
    echo "     RHEL/Fedora: sudo dnf install bash" >&2
    return 1
}

ensure_bash5_or_reexec "$@"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the core module (which sources all other modules)
source "$SCRIPT_DIR/../modules/core/manifest-core.sh"

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # This script is being executed directly
    main "$@"
fi
