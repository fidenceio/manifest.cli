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

# Hermetic gate: no test may trigger a real release gate — under the default
# local-tests policy a gate reaching a project root that carries
# scripts/run-tests.sh would exec it and re-run the suite inside itself
# (suite-within-a-suite). Tests that assert gate behavior set their own policy;
# release_gate.bats unsets this in its setup() so the default stays covered.
export MANIFEST_CLI_RELEASE_GATE=none

# The hermetic-gate export above is present when a test's setup() sources
# manifest-config.sh, so the module's source-time snapshot records it as a
# process-start env override — the same highest-precedence layer a real
# user-supplied MANIFEST_CLI_RELEASE_GATE occupies — and load_configuration
# re-applies it on top of every YAML layer. Tests that assert per-repo YAML
# gate resolution (e.g. fleet members overriding the fleet baseline) must
# drop the simulated override first or it shadows the very config under test.
# Each such test remains gate-hermetic by its own fixture: stubbed per-repo
# workflows or explicit member gate_command values that never auto-detect
# scripts/run-tests.sh.
clear_release_gate_env_override() {
    unset MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_RELEASE_GATE_COMMAND
    unset '_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[MANIFEST_CLI_RELEASE_GATE]' \
          '_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[MANIFEST_CLI_RELEASE_GATE_COMMAND]' \
          2>/dev/null || true
}

# Hermetic git config: the host's git config must not be able to change a
# verdict, and the suite must not be able to change the host's. A developer's
# ~/.gitconfig core.excludesFile pointing at ~/.gitignore_global once made an
# init-template assertion fail inside the sandbox; separately, tests that run
# `git config --global init.defaultBranch main` were writing into the real
# ~/.gitconfig. Redirecting the global layer to a per-run file fixes both
# directions at once, and — unlike /dev/null — keeps `git config --global`
# writable, so those tests still get the branch default they set up.
#
# Identity goes in that file rather than GIT_AUTHOR_*/GIT_COMMITTER_* so normal
# precedence still holds: a repo-local user.email, or a test exporting the env
# vars, continues to win. Without it, a runner with no global identity fails
# every test that commits.
#
# Scope matters: only GLOBAL is redirected. The system scope (/etc/gitconfig) is
# where run-tests-container.sh records `safe.directory` for the bind-mounted
# /work checkout — root in the container against a host-owned mount is
# "dubious ownership", and system scope is the only layer git reads regardless
# of the per-test $HOME. Redirecting it too makes every repo-scoped test fail
# in the container with "requires running inside a Git repository", which is
# how it broke CI in 58.0.1. The host config this guard exists to neutralize —
# core.excludesFile pointing at ~/.gitignore_global — is global anyway.
if [ -z "${TEST_GIT_CONFIG_GLOBAL:-}" ]; then
    TEST_GIT_CONFIG_GLOBAL="$(mktemp "${BATS_TEST_TMPDIR:-${BATS_TMPDIR:-/tmp}}/manifest-test-gitconfig.XXXXXX")"
    export TEST_GIT_CONFIG_GLOBAL
    git config --file "$TEST_GIT_CONFIG_GLOBAL" user.name "Manifest Test" 2>/dev/null || true
    git config --file "$TEST_GIT_CONFIG_GLOBAL" user.email "test@manifest.invalid" 2>/dev/null || true
    # Fixtures that run a bare `git init` and then assert on branch `main` were
    # passing only because the developer's ~/.gitconfig happened to set this;
    # git's own fallback is `master`. Own the default here so the branch name is
    # a property of the suite rather than of whoever is running it.
    git config --file "$TEST_GIT_CONFIG_GLOBAL" init.defaultBranch main 2>/dev/null || true
fi
export GIT_CONFIG_GLOBAL="$TEST_GIT_CONFIG_GLOBAL"

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
# Assert that a command FAILS.
#
# Bash exempts any command prefixed with `!` from errexit — POSIX: "the -e
# setting shall be ignored when ... the command is prefixed with !". In a bats
# test body that makes a bare `! grep -q ...` inert unless it happens to be the
# test's final command, whose status becomes the test's status. 114 assertions
# in this suite sat mid-test and could never fail; one of them was masking a
# real defect (three-segment-only CHANGELOG section matching).
#
# `refute cmd ...` is an ordinary command, so errexit applies wherever it
# appears, and a violation reports what it expected instead of passing quietly.
#
# Pipelines take a herestring instead of a pipe:
#   ! echo "$output" | grep -q needle   ->   refute grep -q needle <<<"$output"
#
# For a command whose own stdout/status you also need, keep using bats's `run`
# plus [ "$status" -ne 0 ]; `refute` deliberately does not touch $output.
refute() {
    if "$@"; then
        printf 'refute: expected failure, but command succeeded: %s\n' "$*" >&2
        return 1
    fi
    return 0
}

# Print the sha256 of a file, on any platform the suite runs on.
#
# `shasum` is a Perl script: macOS ships it, and the Alpine test container does
# NOT (it has coreutils' sha256sum instead). Tests that called `shasum` bare
# behaved two different wrong ways in CI depending on whether the file had run
# load_modules, which is what sets pipefail:
#
#   with pipefail    `x="$(shasum f | awk '{print $1}')"` -> 127 propagates,
#                    the test FAILS loudly (status.bats did this on every
#                    Linux leg since 62adae6)
#   without pipefail awk exits 0 and swallows the 127, so x is EMPTY and the
#                    later `[ "$after" = "$before" ]` compares "" to "" and
#                    PASSES VACUOUSLY
#
# The second is the dangerous one: the vacuously-passing assertions were the
# uninstall/path-modification tripwires, which exist to prove a decoy file was
# never touched. Verified 2026-08-21 by mutation — corrupting the decoy on
# purpose still passed on Alpine and failed on macOS.
#
# No pipe here on purpose: it also keeps this helper out of the
# producer-into-early-exiting-consumer SIGPIPE class (§9.21).
sha256_of() {
    local out
    if command -v shasum >/dev/null 2>&1; then
        out="$(shasum -a 256 "$1")" || return 1
    elif command -v sha256sum >/dev/null 2>&1; then
        out="$(sha256sum "$1")" || return 1
    else
        printf 'sha256_of: no sha256 tool available (need shasum or sha256sum)\n' >&2
        return 1
    fi
    printf '%s\n' "${out%% *}"
}

# Module functions must execute under the shell options they ship with.
# manifest-core.sh:7 sets `set -eo pipefail` at top level, but that is the
# entrypoint module — sourcing it here would also run its path resolution and
# pull in the whole module tree, so the suite loads the leaf modules directly
# and has to set the options itself.
#
# Measured, not assumed (2026-08-18): bats already runs test bodies under
# errexit, so `-e` was never actually missing. `pipefail` WAS missing, and that
# is the real gap this line closes — a module function whose pipeline fails in
# an early element but succeeds in the last one returned 0 to the assertions
# here while aborting in production. Setting both keeps the pair together and
# matched to manifest-core.sh; suite_shell_options.bats asserts they stay that
# way, and would have caught the drift.
#
# `run` clears errexit for the command it captures and `refute` evaluates its
# command as an `if` condition, so both idioms keep working unchanged.
load_modules() {
    set -eo pipefail
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # Always-needed minimal stack: shared utils + yaml + lock primitives.
    # manifest-lock.sh has no dependencies of its own (it probes for log_warning
    # rather than requiring it) and is consumed by both the config and fleet
    # locks, so it belongs in the base stack alongside shared-utils.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-lock.sh"
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
