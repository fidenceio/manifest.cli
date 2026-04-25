#!/usr/bin/env bash
# Manifest CLI test runner.
# Requires bats-core: brew install bats-core (or https://github.com/bats-core/bats-core)

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

if ! command -v bats >/dev/null 2>&1; then
    echo "bats is not installed."
    echo "Install: brew install bats-core"
    echo "         or: https://github.com/bats-core/bats-core#installation"
    exit 2
fi

if [ ! -d "$TESTS_DIR" ]; then
    echo "tests/ directory not found at $TESTS_DIR"
    exit 2
fi

# Filter to specific files if any args were given; otherwise run everything.
if [ "$#" -gt 0 ]; then
    bats "$@"
else
    bats "$TESTS_DIR"
fi
