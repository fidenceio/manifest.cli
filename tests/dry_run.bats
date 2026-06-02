#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

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
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest init repo -y"

    # Hard guarantee: nothing should have been written.
    [ ! -f "$SCRATCH/VERSION" ]
    [ ! -f "$SCRATCH/CHANGELOG.md" ]
    [ ! -f "$SCRATCH/manifest.config.local.yaml" ]
    [ ! -d "$SCRATCH/.git" ]
}

@test "init repo defaults to preview and writes nothing" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest init repo -y"
    [ ! -f "$SCRATCH/VERSION" ]
    [ ! -d "$SCRATCH/.git" ]
}

@test "execution policy rejects contradictory dry-run and yes flags" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Cannot combine --dry-run with -y"
    [ ! -f "$SCRATCH/VERSION" ]
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
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest prep repo -y"
}

@test "prep repo defaults to preview and makes no remote calls" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q
    git remote add origin https://example.invalid/example.git

    PROJECT_ROOT="$SCRATCH" run manifest_prep_repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    echo "$output" | grep -q "Remotes that would be pulled"
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
# ship repo preview
# -----------------------------------------------------------------------------

@test "ship repo preview describes file and documentation effects" {
    source "$TEST_REPO_ROOT/modules/core/manifest-status.sh"
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    source "$TEST_REPO_ROOT/modules/git/manifest-git-changes.sh"
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
    cd "$SCRATCH"
    git init -q
    git remote add origin git@github.com:example/project.git
    echo "1.2.3" > VERSION
    echo "pending docs" > docs-note.md
    mkdir -p modules/core docs tests
    echo "preview work" > modules/core/manifest-ship.sh
    echo "release docs" > docs/COMMAND_REFERENCE.md
    echo "coverage" > tests/dry_run.bats

    PROJECT_ROOT="$SCRATCH" run manifest_ship_repo minor

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Ship repo preview"
    echo "$output" | grep -q "Release type:   minor"
    echo "$output" | grep -q "Current version: 1.2.3"
    echo "$output" | grep -q "Next version:    1.3.0"
    echo "$output" | grep -q "What's new"
    echo "$output" | grep -q "Added smart ship preview summaries"
    echo "$output" | grep -q "Updated release copy and configuration examples"
    echo "$output" | grep -q "Working tree: 5 pending file(s) would be auto-committed"
    echo "$output" | grep -q "VERSION: update 1.2.3 -> 1.3.0"
    echo "$output" | grep -q "CHANGELOG.md: prepend the 1.3.0 release entry"
    echo "$output" | grep -q "docs/: regenerate release documentation"
    echo "$output" | grep -q "Repo identity"
    echo "$output" | grep -q "Current repo:.*example/project"
    echo "$output" | grep -q "Origin:.*example/project"
    echo "$output" | grep -q "Mutation scope:.*this Git repository only"
    ! echo "$output" | grep -q "Git and publish plan"
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest ship repo minor -y"
    echo "$output" | grep -q "DRY RUN COMPLETE: APPLY PREFLIGHT WAS NOT RUN"
    echo "$output" | grep -q "Preview mode did not touch .git or test Git metadata writes."
    echo "$output" | grep -q "When you rerun with -y, Manifest checks Git metadata write access before changing files."
    echo "$output" | grep -q "Depending upon your IDE or agent, you may see a brief failure before an elevated script completes the job."
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
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest refresh repo -y"
}

@test "refresh repo defaults to preview" {
    source "$TEST_REPO_ROOT/modules/core/manifest-refresh.sh"
    cd "$SCRATCH"
    git init -q
    echo "2.5.4" > VERSION

    PROJECT_ROOT="$SCRATCH" run manifest_refresh_repo
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    echo "$output" | grep -q "No changes written. Re-run with -y to apply this plan:"
    echo "$output" | grep -q "manifest refresh repo -y"
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
