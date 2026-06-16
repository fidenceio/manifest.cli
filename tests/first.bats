#!/usr/bin/env bats
#
# §7.4: `manifest first` — guided onboarding front door.
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
    # mkrepo gives a named branch (fresh `git init`) but no origin. The
    # repo-uninitialized apply now routes through the shared gate with
    # origin_required=false, so this unambiguous target auto-confirms on -y
    # alone in this non-interactive context (consent model C).
    mkrepo "$SCRATCH/repo"
    cd "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Auto-confirmed unambiguous target (non-interactive apply via -y)"
    [ -f "$SCRATCH/repo/VERSION" ]
    [ -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

@test "first: -y emits exactly one cli apply-event audit record" {
    # Uninitialized repo so the init delegate actually applies (the apply
    # boundary that records the audit event). The gate runs first; with a
    # named branch + origin_required=false it auto-confirms and the single
    # apply-event is still recorded exactly once.
    mkrepo "$SCRATCH/repo"
    cd "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first -y
    [ "$status" -eq 0 ]
    local audit="$HOME/.manifest-cli/audit/apply-events.ndjson"
    [ -f "$audit" ]
    [ "$(grep -c '"source":"cli"' "$audit")" -eq 1 ]
}

@test "first: -y on a detached-HEAD uninitialized repo refuses and writes nothing" {
    # Detached HEAD is ambiguous even with origin_required=false, so the gate
    # refuses; the init delegate must not run and no files are scaffolded.
    mkrepo "$SCRATCH/repo"
    cd "$SCRATCH/repo"
    git -C "$SCRATCH/repo" config user.email t@example.com
    git -C "$SCRATCH/repo" config user.name "Test User"
    : > "$SCRATCH/repo/seed"
    git -C "$SCRATCH/repo" add seed
    git -C "$SCRATCH/repo" commit -q -m seed
    git -C "$SCRATCH/repo" checkout -q --detach HEAD
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Ambiguous apply target in a non-interactive context"
    [ ! -f "$SCRATCH/repo/VERSION" ]
    [ ! -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

# --- flag completeness (T3) --------------------------------------------------

@test "first: unknown flag errors non-zero with a usage line" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first --bogus
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown option: --bogus"
    echo "$output" | grep -q "Usage: manifest first"
}

@test "first: --name with a missing value errors" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first --name
    [ "$status" -ne 0 ]
    echo "$output" | grep -q -- "--name requires a value"
}

@test "first: --name followed by a flag errors (consumes no flag)" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first --name -f
    [ "$status" -ne 0 ]
    echo "$output" | grep -q -- "--name requires a value"
}

@test "first: --depth with a missing value errors" {
    mkrepo "$SCRATCH/repo"
    PROJECT_ROOT="$SCRATCH/repo" run manifest_first --depth
    [ "$status" -ne 0 ]
    echo "$output" | grep -q -- "--depth requires a value"
}

@test "first: --help usage line lists -f|--force" {
    mkdir -p "$SCRATCH/plain"
    PROJECT_ROOT="$SCRATCH/plain" run manifest_first --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "-f|--force"
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

@test "first (cli): quickstart is fully retired — no longer a recognized command" {
    # quickstart (command + alias) was removed 2026-06-15; `first` is the only
    # onboarding front door. The token must now fall through to the unknown-
    # command handler rather than forward anywhere.
    mkrepo "$SCRATCH/repo"
    cd "$SCRATCH/repo"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" quickstart
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown command: quickstart"
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
