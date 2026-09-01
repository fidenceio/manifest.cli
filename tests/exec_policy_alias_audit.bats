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
# manifest cleanup
#
# This is the §2.3 regression: cleanup must not mutate without consent, and must
# still apply when -y is given.
#
# `cleanup` was a hidden, DEPRECATED alias for the documentation archiving that
# `refresh repo` absorbed. It is now a current command with its own job —
# removing Manifest's own leftovers (retired scaffold sidecars, temp files,
# stale worktree records). The safe-by-default property these tests guard is
# unchanged and is the reason they stay; only the mutation they provoke is
# different, so the apply test now asserts FILE STATE rather than a log line,
# per the §12b ratchet.
# -----------------------------------------------------------------------------

@test "cleanup: default invocation previews and makes no writes" {
    setup_repo_with_archivable_docs
    assert_preview_clean cleanup
    [ ! -e "$SCRATCH/work/docs/zArchive" ]
}

@test "cleanup: --dry-run previews and makes no writes" {
    setup_repo_with_archivable_docs
    assert_preview_clean cleanup --dry-run
    [ ! -e "$SCRATCH/work/docs/zArchive" ]
}

@test "cleanup: AUTO_CONFIRM=1 default still previews and makes no writes" {
    setup_repo_with_archivable_docs
    export MANIFEST_CLI_AUTO_CONFIRM=1
    assert_preview_clean cleanup
    [ ! -e "$SCRATCH/work/docs/zArchive" ]
}

# The inverse of the test this replaces. `cleanup` is no longer deprecated, and
# advertising a replacement for a command that is now the replacement would send
# users to `refresh repo` for a job it does not do.
@test "cleanup: no longer emits a deprecation warning" {
    setup_repo_with_archivable_docs
    run_manifest cleanup
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -qi "deprecated"
}

@test "cleanup: a preview names the leftovers and still writes nothing" {
    setup_repo_with_archivable_docs
    echo stale > "$SCRATCH/work/.gitignore.manifest"

    run_manifest cleanup
    [ "$status" -eq 0 ]
    echo "$output" | grep -q ".gitignore.manifest"
    echo "$output" | grep -q "No changes written"
    # Named, not removed.
    [ -f "$SCRATCH/work/.gitignore.manifest" ]
}

@test "cleanup: -y applies and removes an untracked retired sidecar" {
    setup_repo_with_archivable_docs
    echo stale > "$SCRATCH/work/.gitignore.manifest"

    run_manifest cleanup -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    [ ! -f "$SCRATCH/work/.gitignore.manifest" ]
}

# The `-y` contract is "no prompt, TTY or not". A prompt would block or fail on
# closed stdin, so this is the only assertion that actually proves its absence
# rather than restating the intent.
@test "cleanup: -y completes with stdin closed and no controlling TTY" {
    setup_repo_with_archivable_docs
    echo stale > "$SCRATCH/work/.gitignore.manifest"

    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" cleanup repo -y < /dev/null
    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/work/.gitignore.manifest" ]
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
