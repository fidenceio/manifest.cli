#!/usr/bin/env bash
# Manifest CLI test runner.
# Requires bats-core: brew install bats-core (or https://github.com/bats-core/bats-core)
# Requires the same Bash major version as the CLI.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TESTS_DIR="$REPO_ROOT/tests"
# shellcheck disable=SC1091
source "$REPO_ROOT/modules/core/manifest-requirements.sh"

# Bash 3.2 (Apple's default /bin/bash) silently mangles 'declare -A' and array
# subscripts, producing cryptic "syntax error" lines. Surface the real cause
# upfront so contributors don't waste time chasing parser ghosts.
if ! manifest_requirement_current_bash_is_supported; then
    echo "Bash ${BASH_VERSION} is too old. Manifest CLI and its tests require Bash ${MANIFEST_CLI_REQUIRED_BASH_VERSION}+."
    echo "On macOS: brew install bash, then ensure /opt/homebrew/bin is first in PATH."
    exit 2
fi

# bats's '#!/usr/bin/env bash' shebang resolves to whatever bash is first on
# PATH. If macOS has Homebrew's bash but command lookup still lands on
# /bin/bash 3.2, prepend the Homebrew bin so bats itself runs under the required Bash.
if [[ -x /opt/homebrew/bin/bash ]] && [[ "$(command -v bash 2>/dev/null || true)" != "/opt/homebrew/bin/bash" ]]; then
    export PATH="/opt/homebrew/bin:$PATH"
elif [[ -x /usr/local/bin/bash ]] && [[ "$(command -v bash 2>/dev/null || true)" != "/usr/local/bin/bash" ]] && manifest_requirement_bash_is_supported_major "$(manifest_requirement_bash_major_from_command /usr/local/bin/bash)"; then
    export PATH="/usr/local/bin:$PATH"
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
