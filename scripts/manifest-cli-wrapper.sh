#!/bin/bash

# Manifest CLI Wrapper
# Sources the actual CLI from the project directory

set -e

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

# Function to find the CLI installation directory
find_cli_dir() {
    # Try installation locations (primary: ~/.manifest-cli)
    local possible_dirs=(
        "${MANIFEST_CLI_INSTALL_DIR:-$HOME/.manifest-cli}"
        "$HOME/.manifest-cli"
        # Check if we're running from a development directory (scripts/ subdir)
        "$(dirname "$(dirname "$(realpath "${BASH_SOURCE[0]}")")")"
    )
    
    for dir in "${possible_dirs[@]}"; do
        if [ -f "$dir/modules/core/manifest-core.sh" ]; then
            echo "$dir"
            return 0
        fi
    done
    
    # If not found, try to find it relative to this script
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local project_root="$(dirname "$script_dir")"
    
    if [ -f "$project_root/modules/core/manifest-core.sh" ]; then
        echo "$project_root"
        return 0
    fi
    
    echo "ERROR: Could not find Manifest CLI installation directory" >&2
    exit 1
}

# Find and source the core module
CLI_DIR="$(find_cli_dir)"
source "$CLI_DIR/modules/core/manifest-core.sh"

# Call the main function
main "$@"
