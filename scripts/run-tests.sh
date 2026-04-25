#!/usr/bin/env bash
# Manifest CLI test runner.
# Requires bats-core: brew install bats-core (or https://github.com/bats-core/bats-core)
# Requires Bash 5+ (the CLI itself requires it; tests use associative arrays).

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"

# Bash 3.2 (Apple's default /bin/bash) silently mangles 'declare -A' and array
# subscripts, producing cryptic "syntax error" lines. Surface the real cause
# upfront so contributors don't waste time chasing parser ghosts.
if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    echo "Bash ${BASH_VERSION} is too old. Manifest CLI and its tests require Bash 4+ (5+ recommended)."
    echo "On macOS: brew install bash, then ensure /opt/homebrew/bin is first in PATH."
    exit 2
fi

# bats's '#!/usr/bin/env bash' shebang resolves to whatever bash is first on
# PATH. If we're on macOS with Homebrew's bash present but not first, fix that
# transparently so 'bats' itself runs under bash 5+ — same as the CI workflow.
if [[ -x /opt/homebrew/bin/bash ]] && [[ ":$PATH:" != *":/opt/homebrew/bin:"* ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
fi

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
