#!/bin/bash

# Manifest CLI - New Modular Version
# A powerful command-line tool for Git operations and version management

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the core module (which sources all other modules)
source "$SCRIPT_DIR/modules/core/manifest-core.sh"

# Main entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # This script is being executed directly
    main "$@"
fi
