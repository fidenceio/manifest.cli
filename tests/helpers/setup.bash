#!/usr/bin/env bash
# Shared bats setup. Source this from each .bats file via:
#   load 'helpers/setup'

# Repo root (resolves regardless of where bats is invoked from).
TEST_REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export TEST_REPO_ROOT

# Per-test scratch dir under bats's BATS_TMPDIR.
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
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
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
# is responsible for clearing GH_STUB_* env vars in its own teardown if it
# diverges from the suite default.
gh_stub_install() {
    local stub_dir="${1:-$SCRATCH/.gh-stub}"
    mkdir -p "$stub_dir"
    cp "$TEST_REPO_ROOT/tests/helpers/gh_stub.sh" "$stub_dir/gh"
    chmod +x "$stub_dir/gh"
    export PATH="$stub_dir:$PATH"
    export GH_STUB_LOG="$stub_dir/calls.log"
    : > "$GH_STUB_LOG"
}

# Run a function with a fully-isolated PROJECT_ROOT and HOME so config/git
# writes never touch the developer's real environment.
in_sandbox() {
    local sandbox
    sandbox="$(mk_scratch)"
    HOME="$sandbox/home" PROJECT_ROOT="$sandbox/proj" bash -c "
        mkdir -p \"\$HOME\" \"\$PROJECT_ROOT\"
        cd \"\$PROJECT_ROOT\"
        $*
    "
}
