#!/usr/bin/env bats
#
# §7.4: `manifest init` — guided onboarding front door.
# Read-only inspection by default; writes only on -y through the audited apply
# path.

load 'helpers/setup'

setup() {
    export MANIFEST_CLI_RELEASE_GATE=local-tests
    export MANIFEST_CLI_DOCS_FOLDER=docs
    load_modules \
        "fleet/manifest-fleet.sh" \
        "system/manifest-install-paths.sh" \
        "core/manifest-init.sh" \
        "git/manifest-git.sh" \
        "core/manifest-init-connect.sh" \
        "workflow/manifest-orchestrator.sh" \
        "core/manifest-config.sh" \
        "core/manifest-init-guided.sh"
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

mkrepo() { mkdir -p "$1" && git init -q -b main "$1"; }
ready_repo() {
    git init -q --bare "$SCRATCH/origin.git"
    git -C "$SCRATCH/repo" remote add origin "$SCRATCH/origin.git"
    mkdir -p "$SCRATCH/repo/scripts"
    printf '#!/bin/sh\ntest -f VERSION\n' > "$SCRATCH/repo/scripts/run-tests.sh"
    chmod +x "$SCRATCH/repo/scripts/run-tests.sh"
}


# --- context detection + read-only preview -----------------------------------

@test "init guided: empty dir previews repository setup and writes nothing" {
    mkdir -p "$SCRATCH/plain"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/plain" run _manifest_init_guided
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "no git repo or child repos found"
    echo "$output" | grep -q "would create: .git/"
    echo "$output" | grep -q "Re-run with -y"
    [ -z "$(ls -A "$SCRATCH/plain")" ]
}

@test "init guided: uninitialized repo previews the init plan and writes nothing" {
    mkrepo "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "single repo (not yet initialized)"
    echo "$output" | grep -q "Dry run — manifest init repo:"
    echo "$output" | grep -q "would create:.*VERSION"
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest init repo -y"
    [ ! -f "$SCRATCH/repo/VERSION" ]
    [ ! -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

@test "init guided: VERSION alone does not imply complete setup" {
    mkrepo "$SCRATCH/repo"
    echo "1.2.3" > "$SCRATCH/repo/VERSION"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "single repo (not yet initialized)"
    echo "$output" | grep -q "Version:"
    echo "$output" | grep -q "1.2.3"
    echo "$output" | grep -q "would create:.*README.md"
}

@test "init guided: fleet candidate previews the two-step plan and writes nothing" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/ws" run _manifest_init_guided
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "fleet candidate"
    echo "$output" | grep -q "Set up a fleet across 2 discovered repo"
    # The two-step loop must be self-explanatory in the preview.
    echo "$output" | grep -q "Step 1"
    echo "$output" | grep -q "manifest.fleet.tsv"
    echo "$output" | grep -q "Step 2"
    echo "$output" | grep -q "manifest init fleet -y"
    echo "$output" | grep -q "Fleet name:"
    echo "$output" | grep -q "Scan depth:"
    echo "$output" | grep -q "Re-run with -y"
    [ ! -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/ws/manifest.fleet.tsv" ]
}

@test "init guided: fleet-pending reports the handoff to init fleet and writes no config" {
    # A TSV already exists (Phase 1 ran, or the user re-runs first). `first`
    # does not run Phase 2 itself — it points at the curated apply.
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\talpha\t./alpha\ttrue\t\t\t0.0.0\n"
    } > "$SCRATCH/ws/manifest.fleet.tsv"

    # Preview names the next command.
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/ws" run _manifest_init_guided
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest init fleet -y"

    # Apply does NOT proceed to Phase 2 — no config, no member scaffolding.
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/ws" run _manifest_init_guided -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ready for review"
    echo "$output" | grep -q "manifest init fleet -y"
    [ ! -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/ws/alpha/VERSION" ]
}

# --- flags: help, policy -----------------------------------------------------

@test "init guided: -h prints usage and writes nothing" {
    mkdir -p "$SCRATCH/plain"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/plain" run _manifest_init_guided -h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest init"
    echo "$output" | grep -q "Guided onboarding"
    [ -z "$(ls -A "$SCRATCH/plain")" ]
}

@test "init guided: rejects contradictory --dry-run and -y" {
    mkrepo "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided --dry-run -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Cannot combine --dry-run with -y"
    [ ! -f "$SCRATCH/repo/VERSION" ]
}

# --- apply (-y) --------------------------------------------------------------

@test "init guided: -y with VERSION alone backfills and verifies the repo" {
    mkrepo "$SCRATCH/repo"
    ready_repo
    echo "1.0.0" > "$SCRATCH/repo/VERSION"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided -y
    echo "$output"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Repository prepared for ship"
    [ -f "$SCRATCH/repo/manifest.config.local.yaml" ]
    [ -f "$SCRATCH/repo/README.md" ]
}

@test "init guided: -y on uninitialized repo delegates to init and scaffolds" {
    # mkrepo gives a named branch (fresh `git init`) but no origin. The
    # repo-uninitialized apply routes through the shared gate with
    # origin_required=false, so this unambiguous target auto-confirms on -y
    # alone — no confirmation prompt.
    mkrepo "$SCRATCH/repo"
    ready_repo
    cd "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided -y
    echo "$output"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Auto-confirmed unambiguous target (apply via -y)"
    [ -f "$SCRATCH/repo/VERSION" ]
    [ -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

@test "init guided: -y emits exactly one cli apply-event audit record" {
    # Uninitialized repo so the init delegate actually applies (the apply
    # boundary that records the audit event). The gate runs first; with a
    # named branch + origin_required=false it auto-confirms and the single
    # apply-event is still recorded exactly once.
    mkrepo "$SCRATCH/repo"
    ready_repo
    cd "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided -y
    echo "$output"
    [ "$status" -eq 0 ]
    local audit="$HOME/.manifest-cli/audit/apply-events.ndjson"
    [ -f "$audit" ]
    [ "$(grep -c '"source":"cli"' "$audit")" -eq 1 ]
}

@test "init guided: -y on a detached-HEAD uninitialized repo refuses and writes nothing" {
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
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "detached HEAD"
    [ ! -f "$SCRATCH/repo/VERSION" ]
    [ ! -f "$SCRATCH/repo/manifest.config.local.yaml" ]
}

# --- flag completeness (T3) --------------------------------------------------

@test "init guided: unknown flag errors non-zero with a usage line" {
    mkrepo "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided --bogus
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown option: --bogus"
    echo "$output" | grep -q "Usage: manifest init"
}

@test "init guided: --name with a missing value errors" {
    mkrepo "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided --name
    [ "$status" -ne 0 ]
    echo "$output" | grep -q -- "--name requires a value"
}

@test "init guided: --name followed by a flag errors (consumes no flag)" {
    mkrepo "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided --name -f
    [ "$status" -ne 0 ]
    echo "$output" | grep -q -- "--name requires a value"
}

@test "init guided: --depth with a missing value errors" {
    mkrepo "$SCRATCH/repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo" run _manifest_init_guided --depth
    [ "$status" -ne 0 ]
    echo "$output" | grep -q -- "--depth requires a value"
}

@test "init guided: --help usage line lists -f|--force" {
    mkdir -p "$SCRATCH/plain"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/plain" run _manifest_init_guided --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "-f|--force"
}

# --- read-only config guard (the mechanism `manifest init` relies on) --------

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

@test "init guided (cli): fleet-candidate preview exits clean under set -e" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "fleet candidate"
    echo "$output" | grep -q "Set up a fleet across 2 discovered repo"
    echo "$output" | grep -q "manifest init -y"
    echo "$output" | grep -q "manifest init fleet -y"
    # Read-only: nothing written, no state dir created during inspection.
    [ ! -f "$SCRATCH/ws/manifest.fleet.tsv" ]
    [ ! -d "$HOME/.manifest-cli" ]
}

@test "init guided (cli): -y on a fleet candidate runs Phase 1 only — writes TSV, stops, audited" {
    # Aligned behavior: `first -y` on a fleet writes the reviewable membership
    # list and STOPS (no config, no member scaffolding). The curated apply is a
    # separate verb, `manifest init fleet -y`.
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init -y
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/ws/manifest.fleet.tsv" ]
    # Phase 1 stopped: no config and no member files yet.
    [ ! -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/ws/alpha/VERSION" ]
    [ ! -f "$SCRATCH/ws/beta/VERSION" ]
    # Exactly one cli apply-event for the Phase-1 apply.
    local audit="$HOME/.manifest-cli/audit/apply-events.ndjson"
    [ -f "$audit" ]
    [ "$(grep -c '"source":"cli"' "$audit")" -eq 1 ]
}

@test "init guided (cli): two-phase fleet — init -y writes TSV, init fleet -y scaffolds selected members" {
    # The headline §9.5 flow end-to-end under real module loading + set -e:
    # init -y (Phase 1) → review/edit SELECT → manifest init fleet -y (Phase 2)
    # leaves every SELECTED member Manifest-trackable (VERSION/README/CHANGELOG/docs).
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init -y
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/ws/manifest.fleet.tsv" ]

    # Simulate review: deselect beta. This both exercises selective membership
    # and defeats the stale-TSV guard (SELECT now differs from the default).
    awk 'BEGIN{FS=OFS="\t"} $2=="beta"{$1="false"} {print}' \
        "$SCRATCH/ws/manifest.fleet.tsv" > "$SCRATCH/ws/manifest.fleet.tsv.new"
    mv "$SCRATCH/ws/manifest.fleet.tsv.new" "$SCRATCH/ws/manifest.fleet.tsv"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init fleet -y
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]

    # alpha (selected) is now Manifest-trackable.
    [ -f "$SCRATCH/ws/alpha/VERSION" ]
    [ -f "$SCRATCH/ws/alpha/README.md" ]
    [ -f "$SCRATCH/ws/alpha/CHANGELOG.md" ]
    [ -d "$SCRATCH/ws/alpha/docs" ]

    # No commit: scaffolded files land untracked (parity with init repo).
    run git -C "$SCRATCH/ws/alpha" status --porcelain
    echo "$output" | grep -q "VERSION"

    # beta (deselected) was not touched.
    [ ! -f "$SCRATCH/ws/beta/VERSION" ]
}

@test "init guided (cli): init fleet -y preserves existing member files (no-clobber)" {
    # Pre-seeded member content must survive Phase 2 scaffolding; only absent
    # files are backfilled.
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    printf '2.5.0\n' > "$SCRATCH/ws/alpha/VERSION"
    printf '# Custom alpha readme\n' > "$SCRATCH/ws/alpha/README.md"
    cd "$SCRATCH/ws"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init -y
    [ "$status" -eq 0 ]

    # Review: deselect beta (also defeats the stale-TSV guard), then apply.
    awk 'BEGIN{FS=OFS="\t"} $2=="beta"{$1="false"} {print}' \
        "$SCRATCH/ws/manifest.fleet.tsv" > "$SCRATCH/ws/manifest.fleet.tsv.new"
    mv "$SCRATCH/ws/manifest.fleet.tsv.new" "$SCRATCH/ws/manifest.fleet.tsv"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init fleet -y
    [ "$status" -eq 0 ]

    # Existing files preserved byte-for-byte.
    [ "$(cat "$SCRATCH/ws/alpha/VERSION")" = "2.5.0" ]
    grep -q "Custom alpha readme" "$SCRATCH/ws/alpha/README.md"
    # Absent file backfilled.
    [ -f "$SCRATCH/ws/alpha/CHANGELOG.md" ]
}

@test "init guided (cli): re-running init fleet -y on an initialized fleet preserves config and backfills a member (no bail)" {
    # The §9.5 follow-up, end-to-end: a SECOND `init fleet -y` on an
    # already-initialized fleet must not bail at the "already initialized"
    # guard — it preserves the curated config verbatim and backfills any
    # selected member still missing its Manifest files (no-clobber).
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init -y
    [ "$status" -eq 0 ]

    # First apply: select alpha only (deselecting beta also defeats the
    # stale-TSV guard). beta stays a bare git repo.
    awk 'BEGIN{FS=OFS="\t"} $2=="beta"{$1="false"} {print}' \
        "$SCRATCH/ws/manifest.fleet.tsv" > "$SCRATCH/ws/manifest.fleet.tsv.new"
    mv "$SCRATCH/ws/manifest.fleet.tsv.new" "$SCRATCH/ws/manifest.fleet.tsv"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init fleet -y
    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]
    [ -f "$SCRATCH/ws/alpha/VERSION" ]
    [ ! -f "$SCRATCH/ws/beta/VERSION" ]
    local config_before
    config_before="$(cat "$SCRATCH/ws/manifest.fleet.config.yaml")"

    # Review again: now also select beta, then re-run the SAME verb.
    awk 'BEGIN{FS=OFS="\t"} $2=="beta"{$1="true"} {print}' \
        "$SCRATCH/ws/manifest.fleet.tsv" > "$SCRATCH/ws/manifest.fleet.tsv.new"
    mv "$SCRATCH/ws/manifest.fleet.tsv.new" "$SCRATCH/ws/manifest.fleet.tsv"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" init fleet -y
    [ "$status" -eq 0 ]
    # Did NOT take the old "already initialized" bail path.
    [[ "$output" != *"To reinitialize from scratch"* ]]
    [[ "$output" == *"Preserved:"*"manifest.fleet.config.yaml"* ]]

    # Curated config preserved byte-for-byte (no --force → no regeneration).
    [ "$(cat "$SCRATCH/ws/manifest.fleet.config.yaml")" = "$config_before" ]

    # The newly selected member is backfilled with the full required set.
    [ -f "$SCRATCH/ws/beta/VERSION" ]
    [ -f "$SCRATCH/ws/beta/README.md" ]
    [ -f "$SCRATCH/ws/beta/CHANGELOG.md" ]
    [ -d "$SCRATCH/ws/beta/docs" ]

    # Backfill writes but never commits.
    run git -C "$SCRATCH/ws/beta" status --porcelain
    echo "$output" | grep -q "VERSION"
}
