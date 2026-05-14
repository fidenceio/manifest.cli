#!/bin/bash

# Manifest CLI - New Modular Version
# A powerful command-line tool for Git operations and version management

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../modules/core/manifest-requirements.sh"

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

# Source the core module (which sources all other modules)
source "$SCRIPT_DIR/../modules/core/manifest-core.sh"

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # This script is being executed directly
    main "$@"
fi
