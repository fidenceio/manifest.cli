#!/usr/bin/env bash
# Shared bats setup. Source this from each .bats file via:
#   load 'helpers/setup'

# Repo root (resolves regardless of where bats is invoked from).
TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TEST_REPO_ROOT

# Hermetic consent: non-interactive ships run with MANIFEST_CLI_AUTO_CONFIRM=1
# exported, and an inherited blanket grant flips every declined-consent
# assertion in the suite. Tests that need a grant export it themselves.
unset MANIFEST_CLI_AUTO_CONFIRM

# Per-test scratch dir under bats's BATS_TMPDIR.
#
# The path is returned VERBATIM (not canonicalized). On macOS $TMPDIR lives under
# /var -> /private/var, so the raw path differs from a pwd -P / realpath result.
# That is deliberate: sandbox-safety predicates (manifest-install-paths.sh) match
# candidate paths against $BATS_TEST_TMPDIR — which bats itself leaves unresolved
# — by string prefix, so the scratch path MUST keep the same unresolved form.
# Tests that compare against canonicalized tool output (git rev-parse
# --show-toplevel, etc.) use `-ef` at the assertion instead (see release_gate.bats).
mk_scratch() {
    local d
    d="$(mktemp -d "${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}/manifest-test.XXXXXX")"
    echo "$d"
}

# Source one or more module files in dependency order.
# Modules expect MANIFEST_CLI_CORE_MODULES_DIR to point at the modules root.
load_modules() {
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # Always-needed minimal stack: shared utils + yaml.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
    local m
    for m in "$@"; do
        # shellcheck disable=SC1091
        source "$TEST_REPO_ROOT/modules/$m"
    done
}

# Install the gh stub from tests/helpers/gh_stub.sh onto a per-test PATH
# directory. Tests should call this from setup() (or inline) when they need
# to exercise live `gh` invocations without touching the network. Each test
# is responsible for clearing MANIFEST_CLI_GH_STUB_* env vars in its own teardown if it
# diverges from the suite default.
gh_stub_install() {
    local stub_dir="${1:-$SCRATCH/.gh-stub}"
    mkdir -p "$stub_dir"
    cp "$TEST_REPO_ROOT/tests/helpers/gh_stub.sh" "$stub_dir/gh"
    chmod +x "$stub_dir/gh"
    export PATH="$stub_dir:$PATH"
    export MANIFEST_CLI_GH_STUB_LOG="$stub_dir/calls.log"
    : > "$MANIFEST_CLI_GH_STUB_LOG"
}

# Run a function with a fully-isolated MANIFEST_CLI_PROJECT_ROOT and HOME so config/git
# writes never touch the developer's real environment.
in_sandbox() {
    local sandbox
    sandbox="$(mk_scratch)"
    HOME="$sandbox/home" MANIFEST_CLI_PROJECT_ROOT="$sandbox/proj" bash -c "
        mkdir -p \"\$HOME\" \"\$MANIFEST_CLI_PROJECT_ROOT\"
        cd \"\$MANIFEST_CLI_PROJECT_ROOT\"
        $*
    "
}
