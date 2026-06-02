#!/usr/bin/env bats
# §2.3 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Execution-policy edge audit (TRACKER §2.3).
#
# The canonical command surface (ship/refresh/prep/pr/docs subcommands) is
# covered by preview_no_write.bats. This file guards the *deprecated alias*
# surface: a hidden legacy alias that mutates must still route through the
# safe-by-default contract — preview on default invocation, mutate only on -y.
#
# Regression anchor: `manifest cleanup` (deprecated plumbing for the archive
# move) previously called main_cleanup() unconditionally, mutating the doc
# tree with no preview and no consent. Each test below would have caught that.

load 'helpers/setup'
load 'helpers/preview_no_write'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_AUTO_CONFIRM
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# A committed repo carrying an archivable historical doc, so that an
# unguarded cleanup has something concrete it could move/prune.
setup_repo_with_archivable_docs() {
    git -C "$SCRATCH/work" init -q
    git -C "$SCRATCH/work" config user.email "t@t.co"
    git -C "$SCRATCH/work" config user.name "t"
    echo "1.2.3" > "$SCRATCH/work/VERSION"
    mkdir -p "$SCRATCH/work/docs"
    printf '# old\n' > "$SCRATCH/work/docs/RELEASE_NOTES_v1.0.0.md"
    git -C "$SCRATCH/work" add -A
    git -C "$SCRATCH/work" commit -qm init
}

setup_repo_with_remote() {
    git -C "$SCRATCH/work" init -q
    echo "1.2.3" > "$SCRATCH/work/VERSION"
    git -C "$SCRATCH/work" remote add origin https://example.invalid/example.git
}

# Snapshot-and-diff wrapper: assert the invocation left the sandbox identical.
assert_preview_clean() {
    local before after
    before="$(preview_snapshot)"
    run_manifest "$@"
    after="$(preview_snapshot)"
    assert_no_writes "$before" "$after"
    [ "$status" -eq 0 ]
}

# -----------------------------------------------------------------------------
# Deprecated alias: manifest cleanup (-> manifest refresh repo)
#
# This is the §2.3 regression: cleanup must not mutate the doc tree without
# consent, and must still apply when -y is given.
# -----------------------------------------------------------------------------

@test "cleanup alias: default invocation previews and makes no writes" {
    setup_repo_with_archivable_docs
    assert_preview_clean cleanup
    [ ! -e "$SCRATCH/work/docs/zArchive" ]
}

@test "cleanup alias: --dry-run previews and makes no writes" {
    setup_repo_with_archivable_docs
    assert_preview_clean cleanup --dry-run
    [ ! -e "$SCRATCH/work/docs/zArchive" ]
}

@test "cleanup alias: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_archivable_docs
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean cleanup
    [ ! -e "$SCRATCH/work/docs/zArchive" ]
}

@test "cleanup alias: default invocation emits the deprecation warning" {
    setup_repo_with_archivable_docs
    run_manifest cleanup
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "deprecated"
    echo "$output" | grep -q "manifest refresh repo"
}

@test "cleanup alias: -y applies (cleanup actually runs)" {
    setup_repo_with_archivable_docs
    run_manifest cleanup -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    echo "$output" | grep -qi "Repository cleanup completed"
}

# -----------------------------------------------------------------------------
# Deprecated alias: manifest sync (-> manifest prep repo)
#
# sync delegates straight to manifest_prep_repo, which parses execution policy.
# Guard that the alias keeps previewing by default (no fetch, no commit).
# -----------------------------------------------------------------------------

@test "sync alias: default invocation previews and makes no writes" {
    setup_repo_with_remote
    assert_preview_clean sync
}

@test "sync alias: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_remote
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean sync
}

@test "sync alias: default invocation routes through prep repo's replay hint" {
    setup_repo_with_remote
    run_manifest sync
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest prep repo -y"
}

# -----------------------------------------------------------------------------
# Deprecated alias: manifest prep <type> (-> manifest ship repo <type> --local)
#
# The old "prep-as-local-release" syntax must reach ship's preview, not apply.
# -----------------------------------------------------------------------------

@test "prep <type> alias: default invocation previews and makes no writes" {
    setup_repo_with_remote
    assert_preview_clean prep patch
}

@test "prep <type> alias: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_remote
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean prep patch
}

# -----------------------------------------------------------------------------
# Deprecated alias: manifest recipe run <id> (-> the mapped first-class command)
#
# recipe run forwards "$@" to the first-class function, which parses execution
# policy. A mutating recipe must still preview by default.
# -----------------------------------------------------------------------------

@test "recipe run alias: ship recipe previews and makes no writes by default" {
    setup_repo_with_remote
    assert_preview_clean recipe run manifest.builtin.ship.repo.patch
    echo "$output" | grep -q "manifest ship repo patch -y"
}

@test "recipe run alias: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_remote
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean recipe run manifest.builtin.ship.repo.patch
}
