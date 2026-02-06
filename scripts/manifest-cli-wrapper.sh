#!/bin/bash

# Manifest CLI Wrapper
# Sources the actual CLI from the project directory

set -e

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
