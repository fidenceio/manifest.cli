#!/usr/bin/env bats

# TRACKER §9.23 — the temporary-file sweep must not run wider than the caller
# asked for. It executes as the `archive_sweep` ship step, so anything it
# deletes is deleted on every release; before 2026-08-23 it walked the whole
# project root and removed every pattern hit, which took out git-tracked user
# files and files inside `.git/`.
#
# These assert file state (created / provably not created), not log lines, per
# the §9.27(d) test-policy ratchet.

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-documentation.sh" "docs/manifest-cleanup-docs.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    mkdir -p docs src
    echo "1.0.0" > VERSION
    git add VERSION && git commit -q -m "init repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# POSITIVE CONTROL. Every "survived" assertion below is only meaningful if the
# sweep provably runs and deletes something in this fixture. Without this, a
# sweep that silently did nothing at all would pass the whole file.
@test "POSITIVE CONTROL: an untracked temp file inside docs/ is swept" {
    echo throwaway > docs/generated.tmp

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ ! -f "docs/generated.tmp" ]
}

@test "an untracked .DS_Store is swept anywhere in the tree" {
    # OS droppings are never user content, so these stay tree-wide.
    echo junk > .DS_Store
    echo junk > src/.DS_Store

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ ! -f ".DS_Store" ]
    [ ! -f "src/.DS_Store" ]
}

@test "a git-tracked file matching a sweep pattern is never deleted" {
    echo "hand-written notes" > notes.bak
    echo "kept backup" > src/keep.bak
    git add notes.bak src/keep.bak && git commit -q -m "tracked user backups"

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f "notes.bak" ]
    [ -f "src/keep.bak" ]
    # Nothing was destroyed, so git sees no deletion to commit.
    run git status --porcelain
    [ -z "$output" ]
}

@test "a tracked file is spared even inside the in-scope docs tree" {
    # Tracked beats scope: docs/ is swept, but committed content is not a temp.
    echo "committed on purpose" > docs/committed.bak
    git add docs/committed.bak && git commit -q -m "tracked backup in docs"

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f "docs/committed.bak" ]
}

@test "a staged-but-uncommitted file counts as tracked" {
    # The guard reads the index, so content the user has staged — and is about
    # to commit — is protected too.
    echo "about to commit this" > docs/staged.bak
    git add docs/staged.bak

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f "docs/staged.bak" ]
}

@test "editor-backup patterns are not swept outside the generated docs tree" {
    # *.tmp/*.bak/*~ are plausibly hand-authored, so they are scoped to where
    # this module's own generators write.
    echo scratch > stray.tmp
    echo scratch > src/work.bak
    echo scratch > src/draft.txt~

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f "stray.tmp" ]
    [ -f "src/work.bak" ]
    [ -f "src/draft.txt~" ]
}

@test "nothing inside .git is swept" {
    echo internal > .git/objects/decoy.tmp
    mkdir -p .git/manifest-probe
    echo internal > .git/manifest-probe/thing.bak

    run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f ".git/objects/decoy.tmp" ]
    [ -f ".git/manifest-probe/thing.bak" ]
}

@test "the empty-directory sweep leaves git's own store alone" {
    # The old guard was an exact match on \$root/.git, so `.git/refs/tags` and
    # its empty siblings were removed while `.git` itself was skipped.
    local -a git_empty_dirs=()
    local d
    while IFS= read -r d; do
        git_empty_dirs+=("$d")
    done < <(find .git -type d -empty | sort)
    # Positive control for this test's own fixture: a fresh repo has some.
    [ "${#git_empty_dirs[@]}" -gt 0 ]

    run cleanup_empty_dirs
    [ "$status" -eq 0 ]
    for d in "${git_empty_dirs[@]}"; do
        [ -d "$d" ]
    done
}

@test "preview mode names what it would remove and deletes nothing" {
    echo throwaway > docs/generated.tmp
    echo junk > .DS_Store

    run cleanup_temp_files preview
    [ "$status" -eq 0 ]
    # The contract of a preview is that it names the files.
    [[ "$output" == *"docs/generated.tmp"* ]]
    [[ "$output" == *".DS_Store"* ]]
    # And changes nothing.
    [ -f "docs/generated.tmp" ]
    [ -f ".DS_Store" ]
}

@test "the sweep refuses entirely when git cannot answer what is tracked" {
    # An unreadable index must mean "refuse to delete", not "nothing is
    # tracked" — the absent-input-read-as-a-value shape of §9.15.
    local nogit
    nogit="$(mk_scratch)"
    mkdir -p "$nogit/docs"
    echo throwaway > "$nogit/docs/generated.tmp"

    MANIFEST_CLI_PROJECT_ROOT="$nogit" run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f "$nogit/docs/generated.tmp" ]
    rm -rf "$nogit"
}

@test "a docs.folder pointing outside the repo is not swept" {
    # docs.folder is user-settable and gets no path validation at load, so it
    # can resolve outside the project root. Scoping the sweep to the docs tree
    # must not turn that config value into a steering wheel for rm -f.
    local outside="${SCRATCH}-outside"
    mkdir -p "$outside"
    echo "a file that is none of Manifest's business" > "$outside/precious.tmp"

    MANIFEST_CLI_DOCS_FOLDER="../$(basename "$outside")" run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ -f "$outside/precious.tmp" ]
    rm -rf "$outside"
}

@test "an escaping docs.folder does not disable the tree-wide sweep" {
    # Refusing the docs tree must not silently take the rest of the sweep with
    # it — otherwise the refusal is indistinguishable from a no-op.
    local outside="${SCRATCH}-outside2"
    mkdir -p "$outside"
    echo junk > .DS_Store

    MANIFEST_CLI_DOCS_FOLDER="../$(basename "$outside")" run cleanup_temp_files
    [ "$status" -eq 0 ]
    [ ! -f ".DS_Store" ]
    rm -rf "$outside"
}

@test "main_cleanup runs the sweep with the same guards" {
    # The ship step calls main_cleanup, not cleanup_temp_files directly, so the
    # guards must hold through that path too.
    mkdir -p docs/zArchive
    echo "notes" > notes.bak
    git add notes.bak && git commit -q -m "tracked backup"
    echo throwaway > docs/generated.tmp
    echo internal > .git/objects/decoy.tmp

    run main_cleanup "1.0.0" "2026-08-23 12:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/generated.tmp" ]      # positive control: the sweep ran
    [ -f "notes.bak" ]
    [ -f ".git/objects/decoy.tmp" ]
}
