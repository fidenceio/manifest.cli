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
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/proj"

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
    [ ! -e "$MANIFEST_CLI_PROJECT_ROOT/pwned" ]
    [ ! -e "pwned" ]
}

# --- pre-bump: local-tests --------------------------------------------------

@test "release_gate: local-tests passes when the test command succeeds" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="true"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "tests passed"
}

@test "release_gate: local-tests fails fast when the test command fails" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="false"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Release gate failed"
    echo "$output" | grep -q "No version changes were made"
}

@test "release_gate: local-tests runs the command in MANIFEST_CLI_PROJECT_ROOT" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="touch ran.marker"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ -e "$MANIFEST_CLI_PROJECT_ROOT/ran.marker" ]
}

# --- clean-room PATH floor: never strand the gate without core tools ---------
# The gate runs in an `env -i` clean room. If manifest is invoked from a shell
# whose PATH was clobbered (e.g. an IDE/agent terminal that reset its env after
# an interrupt), the gate must NOT inherit a broken PATH and fail with "tr/date
# don't resolve". The floor guarantees system + Homebrew dirs are always present.

@test "release_gate: PATH floor restores system dirs when the caller PATH is empty" {
    run _manifest_gate_path_floor ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"/usr/bin"* ]]
    [[ "$output" == *":/bin:"* ]]
    [[ "$output" == *"/opt/homebrew/bin"* ]]
}

@test "release_gate: PATH floor keeps inherited entries first, appends the floor" {
    run _manifest_gate_path_floor "/caller/only"
    [ "$status" -eq 0 ]
    [[ "$output" == "/caller/only:"* ]]
    [[ "$output" == *"/usr/bin"* ]]
    [[ "$output" == *":/bin:"* ]]
}

@test "release_gate: clean room resolves core tools (tr/date/git) via the floor" {
    run _manifest_release_gate_exec "$MANIFEST_CLI_PROJECT_ROOT" bash -c 'command -v tr && command -v date && command -v git'
    [ "$status" -eq 0 ]
    [[ "$output" == *"tr"* ]]
    [[ "$output" == *"date"* ]]
    [[ "$output" == *"git"* ]]
}

@test "release_gate: local-tests auto-detects ./scripts/run-tests.sh" {
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT/scripts"
    cat > "$MANIFEST_CLI_PROJECT_ROOT/scripts/run-tests.sh" <<'EOF'
#!/usr/bin/env bash
touch "$PWD/autodetect.marker"
exit 0
EOF
    chmod +x "$MANIFEST_CLI_PROJECT_ROOT/scripts/run-tests.sh"
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ -e "$MANIFEST_CLI_PROJECT_ROOT/autodetect.marker" ]
}

@test "release_gate: local-tests with no resolvable command FAILS CLOSED (no silent bypass)" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    # No gate_command, no scripts/run-tests.sh in MANIFEST_CLI_PROJECT_ROOT. A gate that
    # silently proceeds on "no tests" is a bypass; the gate must block instead.
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "no test command found"
    echo "$output" | grep -q "refusing to release unverified"
}

@test "release_gate: 'all' with no resolvable command also fails closed" {
    export MANIFEST_CLI_RELEASE_GATE="all"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "refusing to release unverified"
}

@test "release_gate: the only sanctioned no-verify path is the audited none bypass" {
    # With no test command, local-tests blocks (above) but none still proceeds —
    # proving the bypass is deliberate and loud, not a default fall-through.
    export MANIFEST_CLI_RELEASE_GATE="none"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Release gate disabled"
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
    [ ! -e "$MANIFEST_CLI_PROJECT_ROOT/should-not-run.marker" ]
}

# A stub run-tests.sh records the args it was invoked with so we can assert the
# tier was threaded through to the auto-detected entrypoint.
_install_recording_runtests() {
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT/scripts"
    cat > "$MANIFEST_CLI_PROJECT_ROOT/scripts/run-tests.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$PWD/runtests.args"
exit 0
EOF
    chmod +x "$MANIFEST_CLI_PROJECT_ROOT/scripts/run-tests.sh"
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
    [ "$(cat "$MANIFEST_CLI_PROJECT_ROOT/runtests.args")" = "--tier full --jobs 1 --no-cache" ]
}

@test "release_gate: gate_tier=smoke threads --tier smoke to run-tests.sh (still serial)" {
    _install_recording_runtests
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_TIER="smoke"
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ "$(cat "$MANIFEST_CLI_PROJECT_ROOT/runtests.args")" = "--tier smoke --jobs 1 --no-cache" ]
}

@test "release_gate: a configured gate_command owns its tiering (no --tier appended)" {
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="my-runner --everything"
    MANIFEST_CLI_RELEASE_GATE_ARGV=()
    _manifest_release_gate_test_command "smoke"
    [ "${#MANIFEST_CLI_RELEASE_GATE_ARGV[@]}" -eq 2 ]
    [ "${MANIFEST_CLI_RELEASE_GATE_ARGV[0]}" = "my-runner" ]
    [ "${MANIFEST_CLI_RELEASE_GATE_ARGV[1]}" = "--everything" ]
}

@test "release_gate: a configured gate_command is tokenized to argv, NOT shell-evaluated" {
    # The classic config-to-RCE: a committed manifest.config.yaml sets
    # release.gate_command to a value that, under `bash -c`, would run arbitrary
    # commands. Resolved as argv, whitespace-delimited tokens are literal — there
    # is no shell to interpret `;`, `&&`, `$()`, etc. token[0] becomes the program
    # name verbatim (here 'true;' with the semicolon attached), which is not a
    # real executable, so the gate fails closed rather than running two commands.
    export MANIFEST_CLI_RELEASE_GATE_COMMAND='true; touch pwned'
    MANIFEST_CLI_RELEASE_GATE_ARGV=()
    _manifest_release_gate_test_command "full"
    [ "${#MANIFEST_CLI_RELEASE_GATE_ARGV[@]}" -eq 3 ]
    [ "${MANIFEST_CLI_RELEASE_GATE_ARGV[0]}" = "true;" ]
    [ "${MANIFEST_CLI_RELEASE_GATE_ARGV[1]}" = "touch" ]
    [ "${MANIFEST_CLI_RELEASE_GATE_ARGV[2]}" = "pwned" ]
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
    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "$MANIFEST_CLI_PROJECT_ROOT" \
        "h" "0" "completed" "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS"
    local audit; audit="$(_audit_file)"
    [ -f "$audit" ]
    [[ "$(cat "$audit")" == *'"gate_status":"bypassed"'* ]]
    [[ "$(cat "$audit")" == *'"event":"completed"'* ]]
}

@test "release_gate: a blocked (no test command) ship records gate_status=blocked-no-command and does NOT release" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    # No gate_command and no scripts/run-tests.sh -> the gate fails CLOSED. The
    # blocking disposition must be observable in the durable record so a refused
    # release is auditable, not silent.
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    # Re-run directly to capture the disposition var (run executes in a subshell).
    manifest_release_gate_run "pre-bump" >"$SCRATCH/out" 2>&1 || true
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS" = "blocked-no-command" ]

    manifest_audit_apply_event "cli" "manifest ship repo patch -y" "$MANIFEST_CLI_PROJECT_ROOT" \
        "h" "1" "failed" "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS"
    [[ "$(cat "$(_audit_file)")" == *'"gate_status":"blocked-no-command"'* ]]
}

@test "release_gate: a passing local-tests run records verified-local" {
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="true"
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
    [ ! -e "$MANIFEST_CLI_PROJECT_ROOT/should-not-run.marker" ]
}

# --- pre-bump: force-bump version-stamp skip (clean + at-tag, no code delta) -
#
# A --force-bump that re-stamps a byte-identical, already-released tree carries
# no new code, so the pre-bump gate passes it without a test command (audited
# skipped-stamp-only). The skip is tightly bounded — it requires force-bump AND
# a clean tree AND HEAD exactly at the current release tag. The matrix below
# pins the boundary: a no-delta force-bump skips; a force-bump with ANY real
# delta (dirty or ahead-of-tag) and an ORDINARY ship both still fail closed, so
# C3 verification of actual code changes is unchanged.

# Build MANIFEST_CLI_PROJECT_ROOT as a git repo: VERSION $1, one commit, tag v$1 at HEAD,
# clean tree — the exact shape the stamp-only gate path recognizes.
_mk_tagged_clean_repo() {
    local ver="${1:-1.0.0}"
    git -C "$MANIFEST_CLI_PROJECT_ROOT" init -q
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.email t@e.co
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.name t
    printf '%s\n' "$ver" > "$MANIFEST_CLI_PROJECT_ROOT/VERSION"
    ( cd "$MANIFEST_CLI_PROJECT_ROOT" \
        && echo base > f \
        && git add VERSION f \
        && git commit -q -m "release $ver" \
        && git tag "v$ver" )
}

@test "release_gate: force-bump on a clean, at-tag tree SKIPS the gate (stamp-only; no test command needed)" {
    _mk_tagged_clean_repo 1.0.0
    export MANIFEST_CLI_RELEASE_GATE="local-tests"   # the strict default policy
    _MANIFEST_CLI_SHIP_FORCE_BUMP=true
    # Call directly (not via `run`) so the disposition var is observable here.
    manifest_release_gate_run "pre-bump" >"$SCRATCH/out" 2>&1
    local rc=$?
    [ "$rc" -eq 0 ]
    grep -q "version stamp on an unchanged" "$SCRATCH/out"
    grep -q "Skipping tests" "$SCRATCH/out"
    [ "$_MANIFEST_CLI_SHIP_LAST_GATE_STATUS" = "skipped-stamp-only" ]
}

@test "release_gate: a no-delta force-bump skips even when a test command EXISTS (and never runs it)" {
    _mk_tagged_clean_repo 1.0.0
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    # Intentional: a clean, at-tag tree is byte-identical to one already gated,
    # so even a present (and here, side-effecting) command is not re-run. The
    # marker proves the command never executed.
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="touch $MANIFEST_CLI_PROJECT_ROOT/should-not-run.marker"
    _MANIFEST_CLI_SHIP_FORCE_BUMP=true
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]
    [ ! -e "$MANIFEST_CLI_PROJECT_ROOT/should-not-run.marker" ]
    echo "$output" | grep -q "no code delta to verify"
}

@test "release_gate: force-bump with a DIRTY tree STILL fails closed (a real delta is not a stamp)" {
    _mk_tagged_clean_repo 1.0.0
    ( cd "$MANIFEST_CLI_PROJECT_ROOT" && echo changed >> f )   # uncommitted change = real delta
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    _MANIFEST_CLI_SHIP_FORCE_BUMP=true
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "no test command found"
    echo "$output" | grep -q "refusing to release unverified"
}

@test "release_gate: force-bump AHEAD of the last tag STILL fails closed (commits since the tag are a real delta)" {
    _mk_tagged_clean_repo 1.0.0
    # New commit after the tag: clean working tree, but HEAD is ahead of v1.0.0.
    ( cd "$MANIFEST_CLI_PROJECT_ROOT" && echo more > g && git add g && git commit -q -m "post-tag commit" )
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    _MANIFEST_CLI_SHIP_FORCE_BUMP=true
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "refusing to release unverified"
}

@test "release_gate: an ORDINARY ship (no force-bump) of a clean, at-tag tree STILL fails closed (C3 intact)" {
    _mk_tagged_clean_repo 1.0.0
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    # _MANIFEST_CLI_SHIP_FORCE_BUMP is "false" (set at module source). The skip
    # is gated on force-bump, so an ordinary ship still demands verification.
    run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "no test command found"
    echo "$output" | grep -q "refusing to release unverified"
}

# --- remote-ci phase boundaries ---------------------------------------------

@test "release_gate: remote-ci is a no-op in the pre-bump phase" {
    export MANIFEST_CLI_RELEASE_GATE="remote-ci"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="false"  # must NOT run pre-bump
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
    git -C "$MANIFEST_CLI_PROJECT_ROOT" init -q
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.email t@e.co
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.name t
    ( cd "$MANIFEST_CLI_PROJECT_ROOT" && echo x > f && git add f && git commit -q -m c )
    export MANIFEST_CLI_GH_STUB_STDOUT="99999"   # gh run list returns a run id
    export MANIFEST_CLI_GH_STUB_EXIT=0           # gh run watch exits green
    export MANIFEST_CLI_RELEASE_GATE="remote-ci"
    run manifest_release_gate_run "post-push"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "remote CI is green"
}

@test "release_gate: post-push remote-ci fails when CI run is red" {
    gh_stub_install
    git -C "$MANIFEST_CLI_PROJECT_ROOT" init -q
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.email t@e.co
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.name t
    ( cd "$MANIFEST_CLI_PROJECT_ROOT" && echo x > f && git add f && git commit -q -m c )
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
    git -C "$MANIFEST_CLI_PROJECT_ROOT" init -q
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.email t@e.co
    git -C "$MANIFEST_CLI_PROJECT_ROOT" config user.name t
    ( cd "$MANIFEST_CLI_PROJECT_ROOT" && echo x > f && git add f && git commit -q -m c )
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
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="false"

    MANIFEST_CLI_RELEASE_GATE="none" run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 0 ]   # member A: bypassed

    MANIFEST_CLI_RELEASE_GATE="local-tests" run manifest_release_gate_run "pre-bump"
    [ "$status" -eq 1 ]   # member B: gated, fails on its own failing tests
}

# --- clean-room isolation of the gate command (_manifest_release_gate_exec) ---
#
# By the time the gate runs, the ship process has exported its config vars,
# ~160 manifest_* functions, MANIFEST_CLI_PROJECT_ROOT, etc. The gate command must run in a
# fresh environment or hermetic tests inherit that state and fail spuriously.
# These guard the env -i clean room. The command is now passed as ARGV — a shell
# snippet is run by spelling out `bash -c` as explicit argv (no implicit shell).

@test "gate exec: command runs in gate_root, exit code propagates" {
    mkdir -p "$SCRATCH/gate"
    run _manifest_release_gate_exec "$SCRATCH/gate" pwd
    [ "$status" -eq 0 ]
    # Compare by inode, not string: a TMPDIR with a trailing slash makes mktemp
    # emit a double slash that `cd`+`pwd` normalizes away, and symlinked temp
    # roots (/var -> /private/var) diverge too. -ef asserts "same directory"
    # regardless of path spelling.
    [ "$output" -ef "$SCRATCH/gate" ]

    run _manifest_release_gate_exec "$SCRATCH/gate" bash -c 'exit 7'
    [ "$status" -eq 7 ]
}

@test "gate exec: a bad gate_root fails closed (does not run the command in the wrong tree)" {
    run _manifest_release_gate_exec "$SCRATCH/does-not-exist" bash -c 'echo SHOULD_NOT_RUN'
    [ "$status" -ne 0 ]
    [[ "$output" != *"SHOULD_NOT_RUN"* ]]
}

@test "gate exec: the command is exec'd as argv, never interpreted by a shell" {
    # The directory token is consumed by the fixed wrapper; the remaining argv is
    # exec'd verbatim. A program name containing shell metacharacters is looked up
    # literally (status 127, command-not-found), proving no shell parses it — so
    # the `;` never separates commands and the side effect never happens.
    # Called directly (not via `run`) so an expected 127 is not surfaced as a
    # bats BW01 advisory.
    local rc=0
    _manifest_release_gate_exec "$SCRATCH" 'true; touch pwned' 2>/dev/null || rc=$?
    [ "$rc" -ne 0 ]
    [ ! -e "$SCRATCH/pwned" ]
    [ ! -e "pwned" ]
}

@test "gate exec: MANIFEST_CLI_* vars do not leak into the command" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_SOME_LEAK="leaked-value"
    run _manifest_release_gate_exec "$SCRATCH" bash -c 'echo "AC=[${MANIFEST_CLI_AUTO_CONFIRM:-unset}] LEAK=[${MANIFEST_CLI_SOME_LEAK:-unset}]"'
    [ "$status" -eq 0 ]
    [ "$output" = "AC=[unset] LEAK=[unset]" ]
}

@test "gate exec: exported manifest functions do not leak into the command" {
    manifest_repo_identity_block() { return 127; }
    export -f manifest_repo_identity_block
    run _manifest_release_gate_exec "$SCRATCH" bash -c 'type -t manifest_repo_identity_block || echo ABSENT'
    [ "$status" -eq 0 ]
    [ "$output" = "ABSENT" ]
}

@test "gate exec: leaked MANIFEST_CLI_PROJECT_ROOT does not reach the command" {
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/proj"
    run _manifest_release_gate_exec "$SCRATCH" bash -c 'echo "PR=[${MANIFEST_CLI_PROJECT_ROOT:-unset}]"'
    [ "$status" -eq 0 ]
    [ "$output" = "PR=[unset]" ]
}

@test "gate exec: PATH and HOME are preserved so tools and sandboxing work" {
    run _manifest_release_gate_exec "$SCRATCH" bash -c 'echo "HOME=[$HOME]"; command -v bash >/dev/null && echo BASH_FOUND'
    [ "$status" -eq 0 ]
    [[ "$output" == *"HOME=[$HOME]"* ]]
    [[ "$output" == *"BASH_FOUND"* ]]
}

@test "gate exec: a configured gate_command runs end-to-end via run as argv (no shell injection)" {
    # End-to-end: gate_command resolved by the run path and exec'd as argv. A
    # value crafted as a shell injection must NOT touch the marker file.
    export MANIFEST_CLI_RELEASE_GATE="local-tests"
    export MANIFEST_CLI_RELEASE_GATE_COMMAND="true; touch injected"
    run manifest_release_gate_run "pre-bump"
    [ ! -e "$MANIFEST_CLI_PROJECT_ROOT/injected" ]
    [ ! -e "injected" ]
}
