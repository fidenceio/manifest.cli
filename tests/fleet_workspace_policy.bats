#!/usr/bin/env bats
# Workspace policy gate (scripts/manifest-fleet-preflight.sh) coverage.
#
# The apply path has refused on this gate since it existed, but nothing tested
# it, and the preview neither ran nor mentioned it — so a preview could close
# with "Re-run with -y to apply this plan" for an apply that was guaranteed to
# refuse (found live 2026-08-21: a 19-releaseable plan over a hard-failing
# gate). These tests pin the preview surface, the apply refusal, and — since
# the default was inverted on 2026-08-21 before either behavior shipped — that
# preview ANNOUNCES the gate rather than executing it, with
# MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=run as the opt-in for callers who want
# the real verdict. Executing a workspace-supplied script is opt-in because the
# CLI does not own that script; see _fleet_preview_workspace_policy.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

write_ship_fixture() {
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
    cat > "$SCRATCH/work/manifest.fleet.tsv" <<'TSV'
true	svc	./svc	false
TSV
}

write_gate() { # $1 = body; creates an executable gate script
    mkdir -p "$SCRATCH/work/scripts"
    printf '#!/usr/bin/env bash\n%s\n' "$1" > "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"
    chmod +x "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"
}

@test "ship fleet preview runs a passing policy gate and keeps the apply recommendation" {
    write_ship_fixture
    write_gate 'echo gate-ran-ok; exit 0'
    export MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=run

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Workspace policy gate: running scripts/manifest-fleet-preflight.sh"* ]]
    [[ "$output" == *"Workspace policy gate: OK"* ]]
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
    [[ "$output" == *"manifest ship fleet patch -y"* ]]
}

@test "ship fleet preview surfaces a failing policy gate and withdraws the bare recommendation" {
    write_ship_fixture
    write_gate 'echo probing; echo "BLOCKING-FINDING-XYZ" >&2; exit 3'
    export MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=run

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Workspace policy gate: FAILED (exit 3)"* ]]
    [[ "$output" == *"apply would REFUSE before any mutation"* ]]
    [[ "$output" == *"| BLOCKING-FINDING-XYZ"* ]]
    [[ "$output" == *"would refuse before any mutation."* ]]
    [[ "$output" == *"Fix the gate findings, then re-run:"* ]]
    [[ "$output" == *"manifest ship fleet patch -y"* ]]
    [[ "$output" != *"No changes written. Re-run with -y to apply this plan:"* ]]
    [ "$(cat "$SCRATCH/work/svc/VERSION")" = "1.2.3" ]
}

@test "ship fleet preview without a policy gate is unchanged" {
    write_ship_fixture

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" != *"Workspace policy gate"* ]]
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
}

# The default is the security-relevant case: preview must not execute a script
# the CLI does not own. A marker file proves non-execution rather than trusting
# the absence of a log line, and no env var is set — that is the whole point.
@test "ship fleet preview does NOT execute the policy gate by default" {
    write_ship_fixture
    write_gate "touch '$SCRATCH/work/gate-executed'; exit 0"

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [ ! -e "$SCRATCH/work/gate-executed" ]
    [[ "$output" == *"Workspace policy gate: scripts/manifest-fleet-preflight.sh (not run in preview; apply refuses if it fails)"* ]]
    # An un-run gate is not a failing gate: the recommendation still stands.
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
}

# An unrecognized value must announce, not execute — fail safe toward the
# non-executing branch rather than treating "anything not announce" as run.
@test "ship fleet preview announces on an unrecognized policy-gate mode" {
    write_ship_fixture
    write_gate "touch '$SCRATCH/work/gate-executed'; exit 0"
    export MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=yes-please

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [ ! -e "$SCRATCH/work/gate-executed" ]
    [[ "$output" == *"(not run in preview; apply refuses if it fails)"* ]]
}

@test "MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=announce names the gate without executing it" {
    write_ship_fixture
    write_gate "touch '$SCRATCH/work/gate-executed'; exit 0"
    export MANIFEST_CLI_FLEET_PREVIEW_POLICY_GATE=announce

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Workspace policy gate: scripts/manifest-fleet-preflight.sh (not run in preview; apply refuses if it fails)"* ]]
    [ ! -e "$SCRATCH/work/gate-executed" ]
    [[ "$output" == *"No changes written. Re-run with -y to apply this plan:"* ]]
}

@test "ship fleet preview forecasts refusal for a non-executable policy gate" {
    write_ship_fixture
    mkdir -p "$SCRATCH/work/scripts"
    printf '#!/usr/bin/env bash\nexit 0\n' > "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"
    chmod -x "$SCRATCH/work/scripts/manifest-fleet-preflight.sh"

    run_manifest ship fleet patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"is not executable — apply would REFUSE."* ]]
    [[ "$output" == *"would refuse before any mutation."* ]]
    [[ "$output" != *"No changes written. Re-run with -y to apply this plan:"* ]]
}

@test "ship fleet apply refuses on a failing policy gate before any mutation" {
    write_ship_fixture
    write_gate 'echo "BLOCKING-FINDING-XYZ"; exit 1'

    run_manifest ship fleet patch -y

    [ "$status" -ne 0 ]
    [[ "$output" == *"workspace policy gate failed"* ]]
    [[ "$output" == *"Pre-flight refused before any mutation; no fleet member was shipped."* ]]
    [ "$(cat "$SCRATCH/work/svc/VERSION")" = "1.2.3" ]
}
