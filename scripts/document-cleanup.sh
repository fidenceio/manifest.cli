#!/bin/bash

# Document Cleanup Wrapper
# This script provides a simple interface for the document cleanup tool

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Check if Python 3 is available
if ! command -v python3 >/dev/null 2>&1; then
    echo "❌ Python 3 is required but not installed."
    echo "Please install Python 3 to use the document cleanup tool."
    exit 1
fi

# Run the Python document cleanup tool with all arguments
exec python3 "$SCRIPT_DIR/document-cleanup.py" "$@"
