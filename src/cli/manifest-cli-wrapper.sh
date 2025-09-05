#!/bin/bash

# Manifest CLI Wrapper
# Sources the actual CLI from the project directory

set -e

# Source the core module from the project directory
source "$HOME/.manifest-cli/src/cli/modules/manifest-core.sh"

# Call the main function
main "$@"
