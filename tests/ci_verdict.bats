#!/usr/bin/env bats
# CI verdict binds the ship (tracker §9.27(a)).
#
# The local release gate proves the suite on the shipping host's OS only; the
# two-OS `tests` workflow on origin bound nothing, and the ubuntu leg was red
# across two releases unnoticed. Contract under test:
#
#   - pre-flight: latest COMPLETED `tests` run on origin/<default branch> —
#     failure REFUSES (naming run id + URL), success proceeds (naming the run),
#     and EVERY degradation (no gh, unauthenticated, gh error, no completed
#     run, neutral conclusion) is an announced "unverified" skip that proceeds.
#     Announced skip is not a pass (§6: absence is not a verdict).
#   - override: release.require_ci_green=false keeps the query and the printed
#     finding but never refuses.
#   - completion report: after a push, a bounded poll names the run the push
#     triggered, or prints the exact command to find it. Never fails the ship.
#   - wiring: a publishing `ship repo -y` refuses at the ci_verdict step before
#     any mutation; `ship fleet` PREVIEW announces the gate and makes ZERO gh
#     calls.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME

    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
}

teardown() {
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT MANIFEST_CLI_GH_STUB_AUTH_EXIT \
        MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR \
        MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT MANIFEST_CLI_GH_STUB_RUN_LIST_EXIT
    unset MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN MANIFEST_CLI_GIT_DEFAULT_BRANCH
    unset MANIFEST_CLI_SHIP_CI_REPORT_ATTEMPTS MANIFEST_CLI_SHIP_CI_REPORT_DELAY_SECONDS
    unset MANIFEST_CLI_AUTO_CONFIRM
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    cd /tmp
    rm -rf "$SCRATCH"
}

# Keep the trusted-time step offline and fast for full-CLI runs: one
# unreachable server, 1s timeout, no retries (pattern: fleet_docs_apply.bats).
neutralize_trusted_time() {
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

RED_ROW=$'424242\tfailure\thttps://github.com/acme/svc/actions/runs/424242'
GREEN_ROW=$'171717\tsuccess\thttps://github.com/acme/svc/actions/runs/171717'

# --- pre-flight verdicts -------------------------------------------------------

@test "ci verdict: a red completed run REFUSES, naming the run id and URL" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$RED_ROW"

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 1 ]
    [[ "$output" == *"CI is red on origin/main: run 424242 concluded failure — fix or override."* ]]
    [[ "$output" == *"https://github.com/acme/svc/actions/runs/424242"* ]]
    [[ "$output" == *"release.require_ci_green=false"* ]]
}

@test "ci verdict: a green completed run proceeds, naming the run" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$GREEN_ROW"

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI green on origin/main (run 171717)."* ]]
}

@test "ci verdict: the query names the tests workflow, the configured default branch, completed only" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$GREEN_ROW"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="trunk"

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"origin/trunk"* ]]
    local calls
    calls="$(cat "$MANIFEST_CLI_GH_STUB_LOG")"
    grep -q -e $'--workflow\ttests' <<<"$calls"
    grep -q -e $'--branch\ttrunk' <<<"$calls"
    grep -q -e $'--status\tcompleted' <<<"$calls"
}

# --- announced degradations (absence is not a verdict, §6) -------------------

@test "ci verdict: no gh on PATH announces the skip as unverified and proceeds" {
    mkdir -p "$SCRATCH/no-gh"

    PATH="$SCRATCH/no-gh" run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI verdict: unverified — gh (GitHub CLI) is not installed"* ]]
    [[ "$output" != *"green"* ]]
}

@test "ci verdict: unauthenticated gh announces the skip and proceeds" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=1

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI verdict: unverified — gh is not authenticated"* ]]
}

@test "ci verdict: a gh listing error (no network / workflow never ran) announces the skip" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT=""
    export MANIFEST_CLI_GH_STUB_RUN_LIST_EXIT=1

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI verdict: unverified — could not list 'tests' workflow runs on origin/main"* ]]
}

@test "ci verdict: no completed run yet announces the skip, worded unverified not green" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT=""

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI verdict: unverified — no completed 'tests' workflow run on origin/main yet"* ]]
    [[ "$output" != *"green"* ]]
}

@test "ci verdict: a neutral conclusion (cancelled) is unverified, neither refused nor green" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT=$'313131\tcancelled\thttps://github.com/acme/svc/actions/runs/313131'

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"concluded 'cancelled' (run 313131), neither green nor red"* ]]
    [[ "$output" != *"CI green"* ]]
}

# --- override: release.require_ci_green=false -----------------------------------

@test "ci verdict: require_ci_green=false reports the red finding but proceeds" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$RED_ROW"
    export MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN=false

    run manifest_ship_ci_verdict_preflight
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI is red on origin/main: run 424242 concluded failure."* ]]
    [[ "$output" == *"release.require_ci_green=false — proceeding despite the red run"* ]]
}

@test "ci verdict: manifest_ship_require_ci_green defaults on, env var turns it off" {
    run manifest_ship_require_ci_green
    [ "$status" -eq 0 ]
    MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN=false run manifest_ship_require_ci_green
    [ "$status" -ne 0 ]
    # Garbage is not an off-switch: only an explicit falsy value disables it.
    MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN=garbage run manifest_ship_require_ci_green
    [ "$status" -eq 0 ]
}

# --- completion report -----------------------------------------------------------

@test "ci completion: names the run the push triggered, with the Linux-leg warning" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT=$'987654\t\thttps://github.com/acme/svc/actions/runs/987654'

    run manifest_ship_completion_ci_report "abcdef1234567890"
    [ "$status" -eq 0 ]
    [[ "$output" == *"CI run for abcdef1: 987654 — https://github.com/acme/svc/actions/runs/987654"* ]]
    [[ "$output" == *"a green local gate does not cover the Linux leg"* ]]
}

@test "ci completion: run not visible yet prints the exact gh command, after a bounded poll" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT=""
    export MANIFEST_CLI_SHIP_CI_REPORT_DELAY_SECONDS=0

    run manifest_ship_completion_ci_report "abcdef1234567890"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not visible yet. Check: gh run list --commit abcdef1234567890 --limit 1"* ]]
    # Bounded: exactly the default 3 attempts, then stop — never an open poll.
    [ "$(grep -c $'\trun\tlist' "$MANIFEST_CLI_GH_STUB_LOG")" -eq 3 ]
}

@test "ci completion: gh unavailable degrades to the check-later hint, never fails" {
    mkdir -p "$SCRATCH/no-gh"

    PATH="$SCRATCH/no-gh" run manifest_ship_completion_ci_report "abcdef1234567890"
    [ "$status" -eq 0 ]
    [[ "$output" == *"unverified (gh unavailable)"* ]]
    [[ "$output" == *"gh run list --commit abcdef1234567890 --limit 1"* ]]
}

# --- wiring: the pre-flight binds a publishing ship -------------------------------

# A publish-mode repo fixture: main branch, one commit, VERSION, an origin URL
# (never contacted — the refusal fires before any remote operation).
_mk_publish_repo() {
    local repo="$SCRATCH/work/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" symbolic-ref HEAD refs/heads/main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    echo "1.2.3" > "$repo/VERSION"
    git -C "$repo" -c core.safecrlf=false add VERSION
    git -C "$repo" commit -qm "init 1.2.3"
    git -C "$repo" remote add origin "https://example.invalid/repo.git"
    echo "$repo"
}

@test "ship repo -y (publish): red CI refuses at the ci_verdict step BEFORE any mutation" {
    local repo before
    repo="$(_mk_publish_repo)"
    before="$(git -C "$repo" rev-parse HEAD)"

    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$RED_ROW"
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
    neutralize_trusted_time

    cd "$repo"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship repo patch -y

    [ "$status" -ne 0 ]
    [[ "$output" == *"CI is red on origin/main: run 424242 concluded failure — fix or override."* ]]
    [[ "$output" == *"failed step:        ci_verdict"* ]]
    # Nothing mutated: VERSION untouched, no commit, no tag.
    [ "$(cat "$repo/VERSION")" = "1.2.3" ]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]
    [ -z "$(git -C "$repo" tag)" ]
}

@test "ship repo --local -y: the CI verdict pre-flight never runs (nothing to bind)" {
    local repo
    repo="$(_mk_publish_repo)"

    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$RED_ROW"
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
    neutralize_trusted_time

    cd "$repo"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship repo patch --local -y

    # A --local prep pushes nothing, so a red origin cannot refuse it, and the
    # pre-flight query is never even made.
    [[ "$output" != *"CI is red"* ]]
    local calls
    calls="$(cat "$MANIFEST_CLI_GH_STUB_LOG")"
    refute grep -q $'\trun\tlist' <<<"$calls"
}

# --- preview: announce only, zero gh calls ----------------------------------------

_write_fleet_fixture() {
    mkdir -p "$SCRATCH/work/svc"
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work/svc" init -q
    echo "1.2.3" > "$SCRATCH/work/svc/VERSION"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc:
    path: "./svc"
    branch: "main"
YAML
    printf 'true\tsvc\t./svc\tfalse\n' > "$SCRATCH/work/manifest.fleet.tsv"
}

@test "ship fleet preview announces the CI verdict gate and makes ZERO gh calls" {
    _write_fleet_fixture
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_RUN_LIST_STDOUT="$RED_ROW"

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"CI verdict gate: latest completed 'tests' workflow run on each member's origin default branch (not queried in preview; apply will refuse a member if CI is red)"* ]]
    # Preview queried NOTHING: the stub log never gained a line.
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
}

@test "ship fleet preview announces the require_ci_green=false override instead" {
    _write_fleet_fixture
    gh_stub_install
    export MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN=false

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"CI verdict gate: release.require_ci_green=false — apply reports each member's latest completed 'tests' run without refusing (not queried in preview)"* ]]
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
}
