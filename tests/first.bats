#!/usr/bin/env bats
#
# §7.4: `manifest first` — guided onboarding front door (supersedes quickstart).
# Read-only inspection by default; writes only on -y through the audited apply
# path.

load 'helpers/setup'

setup() {
    load_modules \
        "fleet/manifest-fleet.sh" \
        "system/manifest-install-paths.sh" \
        "core/manifest-init.sh" \
        "core/manifest-config.sh" \
        "core/manifest-first.sh"
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

mkrepo() { mkdir -p "$1" && git init -q "$1"; }

# --- context detection + read-only preview -----------------------------------

@test "first: empty dir reports nothing to onboard and writes nothing" {
    mkdir -p "$SCRATCH/plain"
    PROJECT_ROOT="$SCRATCH/plain" run manifest_first
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "no git repo or child repos found"
    echo "$output" | grep -q "No git repository or child repos found here."
    # Empty context offers no apply footer.
    ! echo "$output" | grep -q "Re-run with -y"
    [ -z "$(ls -A "$SCRATCH/plain")" ]
}

@test "first: uninitialized repo previews the init plan and writes nothing" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "single repo (not yet initialized)"
    echo "$output" | grep -q "Initialize this repository:"
    echo "$output" | grep -q "would create:.*VERSION"
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest first -y"
    [ ! -f "$SCRATCH/repo/VERSION" ]
    [ ! -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

@test "first: initialized repo reports already-set-up with version" {
    mkrepo "$SCRATCH/repo"
    echo "1.2.3" > "$SCRATCH/repo/VERSION"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "single repo (initialized)"
    echo "$output" | grep -q "Version:"
    echo "$output" | grep -q "1.2.3"
    echo "$output" | grep -q "already initialized"
}

@test "first: fleet candidate previews fleet plan with discovered repo count" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    PROJECT_ROOT="$SCRATCH/ws" run manifest_first
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "fleet candidate"
    echo "$output" | grep -q "Initialize a fleet across 2 discovered repo"
    echo "$output" | grep -q "Fleet name:"
    echo "$output" | grep -q "Scan depth:"
    echo "$output" | grep -q "Re-run with -y"
    [ ! -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/ws/manifest.fleet.tsv" ]
}

# --- flags: help, policy -----------------------------------------------------

@test "first: -h prints usage and writes nothing" {
    mkdir -p "$SCRATCH/plain"
    PROJECT_ROOT="$SCRATCH/plain" run manifest_first -h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest first"
    echo "$output" | grep -q "Guided onboarding"
    [ -z "$(ls -A "$SCRATCH/plain")" ]
}

@test "first: rejects contradictory --dry-run and -y" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first --dry-run -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Cannot combine --dry-run with -y"
    [ ! -f "$SCRATCH/repo/VERSION" ]
}

# --- apply (-y) --------------------------------------------------------------

@test "first: -y on an already-initialized repo applies nothing and writes no config" {
    mkrepo "$SCRATCH/repo"
    echo "1.0.0" > "$SCRATCH/repo/VERSION"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Already set up"
    [ ! -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

@test "first: -y on uninitialized repo delegates to init and scaffolds" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first -y
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/repo/VERSION" ]
    [ -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

@test "first: -y emits exactly one cli apply-event audit record" {
    # Uninitialized repo so the init delegate actually applies (the apply
    # boundary that records the audit event).
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first -y
    [ "$status" -eq 0 ]
    local audit="$HOME/.manifest-cli/audit/apply-events.ndjson"
    [ -f "$audit" ]
    [ "$(grep -c '"source":"cli"' "$audit")" -eq 1 ]
}

# --- read-only config guard (the mechanism `manifest first` relies on) --------

@test "config: CONFIG_SKIP_WRITES blocks state-dir creation" {
    run env HOME="$SCRATCH/home2" MANIFEST_CLI_CONFIG_SKIP_WRITES=1 bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-shared-utils.sh"
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-config.sh"
        _manifest_config_state_dir_ensure
    '
    [ "$status" -ne 0 ]
    [ ! -d "$SCRATCH/home2/.manifest-cli" ]
}

@test "config: without the guard, state-dir creation succeeds" {
    run env HOME="$SCRATCH/home3" bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-shared-utils.sh"
        source "'"$TEST_REPO_ROOT"'/modules/core/manifest-config.sh"
        _manifest_config_state_dir_ensure
    '
    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/home3/.manifest-cli" ]
}

# --- integration via the real binary (runs under the CLI's set -e) -----------
# Unit tests above don't enable set -e, so they miss errexit landmines (e.g.
# an arithmetic post-increment returning 1). These exercise the real dispatch.

@test "first (cli): fleet-candidate preview exits clean under set -e" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" first
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "fleet candidate"
    echo "$output" | grep -q "Initialize a fleet across 2 discovered repo"
    echo "$output" | grep -q "manifest first -y"
    # Read-only: nothing written, no state dir created during inspection.
    [ ! -f "$SCRATCH/ws/manifest.fleet.tsv" ]
    [ ! -d "$HOME/.manifest-cli" ]
}

@test "first (cli): quickstart is a deprecated alias forwarding to first" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    cd "$SCRATCH/ws"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" quickstart fleet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "deprecated"
    echo "$output" | grep -q "manifest first"
}

@test "first (cli): -y applies a fleet, audited" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" first -y
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/ws/manifest.fleet.tsv" ]
    [ -f "$HOME/.manifest-cli/audit/apply-events.ndjson" ]
}
