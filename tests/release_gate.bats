#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the release gate (MANIFEST_CLI_RELEASE_GATE / release.gate):
# the single self-describing policy that blocks a release until verification
# passes. Exercises policy normalization, the pre-bump local-tests phase, the
# post-push remote-ci phase, the loud+audited `none` bypass, and that an
# injection-shaped value is rejected rather than executed.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/proj"
    export HOME
    export PROJECT_ROOT="$SCRATCH/proj"

    # Minimal module stack for the gate functions.
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"

    # Keep the actions waiter fast and offline by default; individual remote-ci
    # tests install the gh stub and set their own contract.
    export MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS=1
    export MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS=1
    unset MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_RELEASE_GATE_COMMAND
    unset MANIFEST_CLI_SHIP_STATUS_FILE
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- policy normalization ---------------------------------------------------

@test "release_gate: default policy is local-tests" {
    run manifest_release_gate_policy
    [ "$status" -eq 0 ]
    [ "$output" = "local-tests" ]
}

@test "release_gate: policy tolerates whitespace and case" {
    MANIFEST_CLI_RELEASE_GATE=" Remote-CI " run manifest_release_gate_policy
    [ "$status" -eq 0 ]
    [ "$output" = "remote-ci" ]
}

@test "release_gate: unknown policy is rejected, never silently disabled" {
    MANIFEST_CLI_RELEASE_GATE="garbage" run manifest_release_gate_policy
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "Invalid release_gate"
}

@test "release_gate: injection-shaped value is rejected and not executed" {
    MANIFEST_CLI_RELEASE_GATE='none; touch pwned' run manifest_release_gate_run "pre-bump"
    [ "$status" -ne 0 ]
    [ ! -e "$PROJECT_ROOT/pwned" ]
    [ ! -e "pwned" ]
}

# --- pre-bump: local-tests --------------------------------------------------

@test "release_gate: local-tests passes when the test command succeeds" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="exit 0"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "tests passed"
}

@test "release_gate: local-tests fails fast when the test command fails" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="exit 1"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Release gate failed"
    echo "$output" | grep -q "No version changes were made"
}

@test "release_gate: local-tests runs the command in PROJECT_ROOT" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="touch ran.marker"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ -e "$PROJECT_ROOT/ran.marker" ]
}

@test "release_gate: local-tests auto-detects ./scripts/run-tests.sh" {
    mkdir -p "$PROJECT_ROOT/scripts"
    cat > "$PROJECT_ROOT/scripts/run-tests.sh" <<'EOF'
#!/usr/bin/env bash
touch "$PWD/autodetect.marker"
exit 0
EOF
    chmod +x "$PROJECT_ROOT/scripts/run-tests.sh"
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ -e "$PROJECT_ROOT/autodetect.marker" ]
}

@test "release_gate: local-tests with no resolvable command warns and proceeds" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    # No gate_command, no scripts/run-tests.sh in PROJECT_ROOT.
    manifest_release_gate_run "pre-bump" >"$SCRATCH/out" 2>&1
    [ "$?" -eq 0 ]
    grep -q "no test command found" "$SCRATCH/out"
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS" = "unverified" ]
}

# --- pre-bump: gate tier (release.gate_tier) --------------------------------

@test "release_gate: default tier is full" {
    run manifest_release_gate_tier
    [ "$status" -eq 0 ]
    [ "$output" = "full" ]
}

@test "release_gate: tier tolerates whitespace and case" {
    MANIFEST_CLI_RELEASE_GATE_TIER=" Smoke " run manifest_release_gate_tier
    [ "$status" -eq 0 ]
    [ "$output" = "smoke" ]
}

@test "release_gate: unknown tier is rejected, never silently shrunk" {
    MANIFEST_CLI_RELEASE_GATE_TIER="quick" run manifest_release_gate_tier
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "Invalid release_gate_tier"
}

@test "release_gate: an invalid tier hard-stops the gate (no run, no release)" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="touch should-not-run.marker"
    export MANIFEST_CLI_RELEASE_GATE_TIER="quick"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    [ ! -e "$PROJECT_ROOT/should-not-run.marker" ]
}

# A stub run-tests.sh records the args it was invoked with so we can assert the
# tier was threaded through to the auto-detected entrypoint.
_install_recording_runtests() {
    mkdir -p "$PROJECT_ROOT/scripts"
    cat > "$PROJECT_ROOT/scripts/run-tests.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$PWD/runtests.args"
exit 0
EOF
    chmod +x "$PROJECT_ROOT/scripts/run-tests.sh"
}

@test "release_gate: auto-detected run-tests.sh runs the full tier, serial by default" {
    _install_recording_runtests
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    # --jobs 1: the gate runs on an uncontrolled shipping host, so it must not
    # depend on GNU parallel being installed there (parallel is provisioned only
    # in the container and CI). See _manifest_release_gate_test_command.
    # --no-cache: the gate never honors the §5.10 green-run cache — a release
    # must observe the suite passing here, not trust a prior cached run.
    [ "$(cat "$PROJECT_ROOT/runtests.args")" = "--tier full --jobs 1 --no-cache" ]
}

@test "release_gate: gate_tier=smoke threads --tier smoke to run-tests.sh (still serial)" {
    _install_recording_runtests
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_TIER="smoke"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ "$(cat "$PROJECT_ROOT/runtests.args")" = "--tier smoke --jobs 1 --no-cache" ]
}

@test "release_gate: a configured gate_command owns its tiering (no --tier appended)" {
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="my-runner --everything"
    run _manifest_release_gate_test_command "smoke"
    [ "$status" -eq 0 ]
    [ "$output" = "my-runner --everything" ]
}

# --- pre-bump: none (loud + audited) ----------------------------------------

# The durable apply-events log; the gate disposition rides the completion event
# (§8.3b). Emitted by manifest_ship_repo after the workflow; here we drive the
# same emit the ship path does so the test asserts the disposition actually
# reaches the DURABLE record, not only the ephemeral var. Resolved at call time
# (a function, not a top-level var) so it tracks the per-test HOME set in setup.
_audit_file() { echo "$HOME/.manifest-cli/audit/apply-events.ndjson"; }

@test "release_gate: none warns loudly and records an audited bypass IN THE DURABLE LOG (§8.3b)" {
    export MANIFEST_CLI_RELEASE_GATE="none"
    # Call directly (not via `run`) so the disposition var is observable.
    manifest_release_gate_run "pre-bump" >"$SCRATCH/out" 2>&1
    [ "$?" -eq 0 ]
    grep -q "Release gate disabled" "$SCRATCH/out"
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS" = "bypassed" ]
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_POLICY" = "none" ]

    # The completion event (what manifest_ship_repo emits) must carry the
    # bypass so an auditor can see a force-bypassed release after the fact —
    # the in-memory var alone was NOT audited.
    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "$PROJECT_ROOT" \
        "h" "0" "completed" "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS"
    local audit; audit="$(_audit_file)"
    [ -f "$audit" ]
    [[ "$(cat "$audit")" == *'"gate_status":"bypassed"'* ]]
    [[ "$(cat "$audit")" == *'"event":"completed"'* ]]
}

@test "release_gate: an unverified (no test command) ship appends gate_status=unverified to the durable log (§8.3b)" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    # No gate_command and no scripts/run-tests.sh -> the gate fails open with the
    # 'unverified' disposition. The whole point of §8.3b is that this fail-open
    # is observable in the durable record.
    manifest_release_gate_run "pre-bump" >"$SCRATCH/out" 2>&1
    [ "$?" -eq 0 ]
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS" = "unverified" ]

    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "$PROJECT_ROOT" \
        "h" "0" "completed" "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS"
    [[ "$(cat "$(_audit_file)")" == *'"gate_status":"unverified"'* ]]
}

@test "release_gate: a passing local-tests run records verified-local" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="exit 0"
    manifest_release_gate_run "pre-bump" >"$SCRATCH/out" 2>&1
    [ "$?" -eq 0 ]
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS" = "verified-local" ]
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_POLICY" = "local-tests" ]
}

@test "release_gate: none does not run any test command" {
    export MANIFEST_CLI_RELEASE_GATE="none"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="touch should-not-run.marker"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ ! -e "$PROJECT_ROOT/should-not-run.marker" ]
}

# --- remote-ci phase boundaries ---------------------------------------------

@test "release_gate: remote-ci is a no-op in the pre-bump phase" {
    export MANIFEST_CLI_RELEASE_GATE="remote-ci"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="exit 1"  # must NOT run pre-bump
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
}

@test "release_gate: local-tests is a no-op in the post-push phase" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    run manifest_release_gate_run "post-push"
    [ "$status" -eq 0 ]
}

@test "release_gate: post-push remote-ci passes when CI run is green" {
    gh_stub_install
    git -C "$PROJECT_ROOT" init -q
    git -C "$PROJECT_ROOT" config user.email t@e.co
    git -C "$PROJECT_ROOT" config user.name t
    ( cd "$PROJECT_ROOT" && echo x > f && git add f && git commit -q -m c )
    export MANIFEST_CLI_GH_STUB_STDOUT="99999"   # gh run list returns a run id
    export MANIFEST_CLI_GH_STUB_EXIT=0           # gh run watch exits green
    export MANIFEST_CLI_RELEASE_GATE="remote-ci"
    run manifest_release_gate_run "post-push"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "remote CI is green"
}

@test "release_gate: post-push remote-ci fails when CI run is red" {
    gh_stub_install
    git -C "$PROJECT_ROOT" init -q
    git -C "$PROJECT_ROOT" config user.email t@e.co
    git -C "$PROJECT_ROOT" config user.name t
    ( cd "$PROJECT_ROOT" && echo x > f && git add f && git commit -q -m c )
    export MANIFEST_CLI_GH_STUB_STDOUT="99999"   # run id present
    export MANIFEST_CLI_GH_STUB_EXIT=1           # gh run watch exits non-zero (red)
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=0      # but auth is fine
    export MANIFEST_CLI_RELEASE_GATE="remote-ci"
    run manifest_release_gate_run "post-push"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "remote CI did not pass"
}

@test "release_gate: post-push remote-ci hard-stops when CI cannot be confirmed" {
    gh_stub_install
    git -C "$PROJECT_ROOT" init -q
    git -C "$PROJECT_ROOT" config user.email t@e.co
    git -C "$PROJECT_ROOT" config user.name t
    ( cd "$PROJECT_ROOT" && echo x > f && git add f && git commit -q -m c )
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=1      # gh installed but not authenticated -> rc2 path
    export MANIFEST_CLI_RELEASE_GATE="remote-ci"
    run manifest_release_gate_run "post-push"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "could not confirm a green CI run"
}

# --- per-repo independence (fleet version independence) ---------------------

@test "release_gate: policy is read per call so each repo gates independently" {
    # The gate is a pure function of the current env, so a fleet ship that
    # invokes it per member (each with its own config) gates members
    # independently. Prove the same function yields different verdicts when
    # the policy differs between calls.
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="exit 1"

    MANIFEST_CLI_RELEASE_GATE="none" run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]   # member A: bypassed

    MANIFEST_CLI_RELEASE_GATE="local-tests" run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]   # member B: gated, fails on its own failing tests
}

# --- clean-room isolation of the gate command (_manifest_release_gate_exec) ---
#
# By the time the gate runs, the ship process has exported its config vars,
# ~160 manifest_* functions, PROJECT_ROOT, etc. The gate command must run in a
# fresh environment or hermetic tests inherit that state and fail spuriously.
# These guard the env -i clean room.

@test "gate exec: command runs in gate_root, exit code propagates" {
    mkdir -p "$SCRATCH/gate"
    run _manifest_release_gate_exec "$SCRATCH/gate" 'pwd'
    [ "$status" -eq 0 ]
    [ "$output" = "$SCRATCH/gate" ]

    run _manifest_release_gate_exec "$SCRATCH/gate" 'exit 7'
    [ "$status" -eq 7 ]
}

@test "gate exec: MANIFEST_CLI_* vars do not leak into the command" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_SOME_LEAK="leaked-value"
    run _manifest_release_gate_exec "$SCRATCH" 'echo "AC=[${MANIFEST_CLI_AUTO_CONFIRM:-unset}] LEAK=[${MANIFEST_CLI_SOME_LEAK:-unset}]"'
    [ "$status" -eq 0 ]
    [ "$output" = "AC=[unset] LEAK=[unset]" ]
}

@test "gate exec: exported manifest functions do not leak into the command" {
    manifest_repo_identity_block() { return 127; }
    export -f manifest_repo_identity_block
    run _manifest_release_gate_exec "$SCRATCH" 'type -t manifest_repo_identity_block || echo ABSENT'
    [ "$status" -eq 0 ]
    [ "$output" = "ABSENT" ]
}

@test "gate exec: leaked PROJECT_ROOT does not reach the command" {
    export PROJECT_ROOT="$SCRATCH/proj"
    run _manifest_release_gate_exec "$SCRATCH" 'echo "PR=[${PROJECT_ROOT:-unset}]"'
    [ "$status" -eq 0 ]
    [ "$output" = "PR=[unset]" ]
}

@test "gate exec: PATH and HOME are preserved so tools and sandboxing work" {
    run _manifest_release_gate_exec "$SCRATCH" 'echo "HOME=[$HOME]"; command -v bash >/dev/null && echo BASH_FOUND'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HOME=[$HOME]"* ]]
    [[ "$output" == *"BASH_FOUND"* ]]
}
