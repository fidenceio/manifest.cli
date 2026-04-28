#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# -----------------------------------------------------------------------------
# init repo --dry-run
# -----------------------------------------------------------------------------

@test "init repo --dry-run: prints intent and writes nothing" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    echo "$output" | grep -q "would create:.*VERSION"
    echo "$output" | grep -q "No changes written"

    # Hard guarantee: nothing should have been written.
    [ ! -f "$SCRATCH/VERSION" ]
    [ ! -f "$SCRATCH/CHANGELOG.md" ]
    [ ! -f "$SCRATCH/manifest.config.local.yaml" ]
    [ ! -d "$SCRATCH/.git" ]
}

@test "init repo --dry-run: marks existing files as 'exists', not 'would create'" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"
    git init -q
    echo "1.0.0" > VERSION

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "exists:.*VERSION"
    # And the .git dir is not marked for creation.
    ! echo "$output" | grep -q "would create: .git"
}

@test "init repo --dry-run --force: existing files marked 'would overwrite'" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"
    git init -q
    echo "1.0.0" > VERSION

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --force
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would overwrite:.*VERSION"
    # Nothing actually mutated.
    [ "$(cat "$SCRATCH/VERSION")" = "1.0.0" ]
}

# -----------------------------------------------------------------------------
# prep repo --dry-run
# -----------------------------------------------------------------------------

@test "prep repo --dry-run: lists remotes that would be pulled, no network" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q
    git remote add origin https://example.invalid/example.git

    PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    echo "$output" | grep -q "Remotes that would be pulled"
    echo "$output" | grep -q "origin"
    echo "$output" | grep -q "https://example.invalid/example.git"
    echo "$output" | grep -q "No changes written"
}

@test "prep repo --dry-run: no remote configured -> reports plan, no prompt" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q

    # Run with stdin closed so a real prompt would hang or fail; dry-run must
    # short-circuit before that point.
    PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --dry-run < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "no remotes configured"
}

# -----------------------------------------------------------------------------
# refresh repo --dry-run
# -----------------------------------------------------------------------------

@test "refresh repo --dry-run: prints plan and skips doc regen" {
    source "$TEST_REPO_ROOT/modules/core/manifest-refresh.sh"
    cd "$SCRATCH"
    git init -q
    echo "2.5.4" > VERSION

    PROJECT_ROOT="$SCRATCH" run manifest_refresh_repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    echo "$output" | grep -q "Version: 2.5.4 (unchanged)"
    echo "$output" | grep -q "Would perform"
    echo "$output" | grep -q "Regenerate documentation"
    echo "$output" | grep -q "No changes written"
}

@test "refresh repo --dry-run --commit: surfaces the commit step in the plan" {
    source "$TEST_REPO_ROOT/modules/core/manifest-refresh.sh"
    cd "$SCRATCH"
    git init -q
    echo "0.1.0" > VERSION

    PROJECT_ROOT="$SCRATCH" run manifest_refresh_repo --dry-run --commit
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Commit refreshed files"
}
