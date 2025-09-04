#!/bin/bash

# Markdown Manager Wrapper
# This script provides backward compatibility for the new Python-based markdown tool

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python 3 is required but not installed."
    echo "Please install Python 3 to use the markdown manager."
    exit 1
fi

# Run the Python markdown manager with all arguments
exec python3 "$SCRIPT_DIR/markdown-manager.py" "$@"