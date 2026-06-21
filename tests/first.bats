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

@test "first: fleet candidate previews the two-step plan and writes nothing" {
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    PROJECT_ROOT="$SCRATCH/ws" run manifest_first
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

@test "first: fleet-pending reports the handoff to init fleet and writes no config" {
    # A TSV already exists (Phase 1 ran, or the user re-runs first). `first`
    # does not run Phase 2 itself — it points at the curated apply.
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\talpha\t./alpha\ttrue\t\t\t0.0.0\n"
    } > "$SCRATCH/ws/manifest.fleet.tsv"

    # Preview names the next command.
    PROJECT_ROOT="$SCRATCH/ws" run manifest_first
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest init fleet -y"

    # Apply does NOT proceed to Phase 2 — no config, no member scaffolding.
    PROJECT_ROOT="$SCRATCH/ws" run manifest_first -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "ready for review"
    echo "$output" | grep -q "manifest init fleet -y"
    [ ! -f "$SCRATCH/ws/manifest.fleet.config.yaml" ]
    [ ! -f "$SCRATCH/ws/alpha/VERSION" ]
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
    echo "$output" | grep -q "Set up a fleet across 2 discovered repo"
    echo "$output" | grep -q "manifest first -y"
    echo "$output" | grep -q "manifest init fleet -y"
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

@test "first (cli): -y on a fleet candidate runs Phase 1 only — writes TSV, stops, audited" {
    # Aligned behavior: `first -y` on a fleet writes the reviewable membership
    # list and STOPS (no config, no member scaffolding). The curated apply is a
    # separate verb, `manifest init fleet -y`.
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" first -y
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

@test "first (cli): two-phase fleet — first -y writes TSV, init fleet -y scaffolds selected members" {
    # The headline §9.5 flow end-to-end under real module loading + set -e:
    # first -y (Phase 1) → review/edit SELECT → manifest init fleet -y (Phase 2)
    # leaves every SELECTED member Manifest-trackable (VERSION/README/CHANGELOG/docs).
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" first -y
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

@test "first (cli): init fleet -y preserves existing member files (no-clobber)" {
    # Pre-seeded member content must survive Phase 2 scaffolding; only absent
    # files are backfilled.
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    printf '2.5.0\n' > "$SCRATCH/ws/alpha/VERSION"
    printf '# Custom alpha readme\n' > "$SCRATCH/ws/alpha/README.md"
    cd "$SCRATCH/ws"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" first -y
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

@test "first (cli): re-running init fleet -y on an initialized fleet preserves config and backfills a member (no bail)" {
    # The §9.5 follow-up, end-to-end: a SECOND `init fleet -y` on an
    # already-initialized fleet must not bail at the "already initialized"
    # guard — it preserves the curated config verbatim and backfills any
    # selected member still missing its Manifest files (no-clobber).
    mkdir -p "$SCRATCH/ws"
    mkrepo "$SCRATCH/ws/alpha"
    mkrepo "$SCRATCH/ws/beta"
    cd "$SCRATCH/ws"

    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" first -y
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
