#!/usr/bin/env bats
# manifest_unstage_accidental_gitlinks — the post-`git add .` guard that keeps
# nested repos (own .git, no .gitmodules entry) out of the index as bare
# mode-160000 gitlinks. Origin: fidence.workspace accidentally captured two
# member repos nested under a tracked parent path (scripts/precommit,
# scripts/security) via ship's bulk add.

load 'helpers/setup'

setup() {
    load_modules 'git/manifest-git.sh'
    SCRATCH="$(mk_scratch)"
    export GIT_AUTHOR_NAME="bats" GIT_AUTHOR_EMAIL="bats@example"
    export GIT_COMMITTER_NAME="bats" GIT_COMMITTER_EMAIL="bats@example"
    unset MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS MANIFEST_CLI_GITLINKS_SKIPPED_COUNT
    unset MANIFEST_CLI_PROJECT_ROOT MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY
}

mk_outer() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "bats@example"
    git -C "$dir" config user.name "bats"
    echo "seed" > "$dir/seed.md"
    git -C "$dir" add seed.md
    git -C "$dir" commit -q -m "seed"
}

mk_inner() {
    local dir="$1"
    mkdir -p "$dir"
    git -C "$dir" init -q -b main
    git -C "$dir" config user.email "bats@example"
    git -C "$dir" config user.name "bats"
    echo "inner" > "$dir/file.txt"
    git -C "$dir" add file.txt
    git -C "$dir" commit -q -m "inner"
}

staged_gitlinks() {
    git -C "${1:-.}" ls-files --stage | awk '$1 == "160000" {print $NF}'
}

@test "bulk add: newly captured bare gitlink is unstaged with notice" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/nested"
    cd "$SCRATCH/outer"
    git add .
    [ "$(staged_gitlinks)" = "nested" ]

    run manifest_unstage_accidental_gitlinks
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped nested git repo: nested"* ]]
    [[ "$output" == *"git.allow_new_gitlinks=true"* ]]
    [ -z "$(staged_gitlinks)" ]
    # The nested repo itself is untouched.
    git -C nested rev-parse -q --verify HEAD >/dev/null
}

@test "declared submodule gitlink is left staged, silently" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/sub"
    cd "$SCRATCH/outer"
    printf '[submodule "sub"]\n\tpath = sub\n\turl = ../sub\n' > .gitmodules
    git add .

    run manifest_unstage_accidental_gitlinks
    [ "$status" -eq 0 ]
    [[ "$output" != *"Skipped nested git repo"* ]]
    [[ "$output" != *"Bare gitlink"* ]]
    [ "$(staged_gitlinks)" = "sub" ]
}

@test "gitlink already tracked in HEAD: pointer bump stays staged with notice" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/nested"
    cd "$SCRATCH/outer"
    git add .
    git commit -q -m "capture gitlink"
    echo "more" >> nested/file.txt
    git -C nested commit -q -am "advance inner"
    git add .

    run manifest_unstage_accidental_gitlinks
    [ "$status" -eq 0 ]
    [[ "$output" == *"Bare gitlink already tracked: nested"* ]]
    [ "$(staged_gitlinks)" = "nested" ]
    # The staged pointer is the inner repo's new HEAD (bump preserved).
    staged_sha="$(git ls-files --stage -- nested | awk '{print $2}')"
    [ "$staged_sha" = "$(git -C nested rev-parse HEAD)" ]
}

@test "gitlink already tracked in HEAD: unchanged pointer is silent" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/nested"
    cd "$SCRATCH/outer"
    git add .
    git commit -q -m "capture gitlink"
    echo "change" >> seed.md
    git add .

    run manifest_unstage_accidental_gitlinks
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(staged_gitlinks)" = "nested" ]
}

@test "git.allow_new_gitlinks=true records the capture" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/nested"
    cd "$SCRATCH/outer"
    git add .
    export MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS=true

    run manifest_unstage_accidental_gitlinks
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ "$(staged_gitlinks)" = "nested" ]
}

@test "unborn HEAD: capture removed, real files stay staged" {
    mkdir -p "$SCRATCH/fresh"
    git -C "$SCRATCH/fresh" init -q -b main
    git -C "$SCRATCH/fresh" config user.email "bats@example"
    git -C "$SCRATCH/fresh" config user.name "bats"
    echo "a" > "$SCRATCH/fresh/a.txt"
    mk_inner "$SCRATCH/fresh/nested"
    cd "$SCRATCH/fresh"
    git add .

    run manifest_unstage_accidental_gitlinks
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped nested git repo: nested"* ]]
    [ -z "$(staged_gitlinks)" ]
    git ls-files --stage | grep -q "a.txt"
}

@test "commit_changes: gitlink-only dirt commits nothing and succeeds" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/nested"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/outer"
    manifest_smart_documentation_review() { return 0; }
    export -f manifest_smart_documentation_review
    cd "$SCRATCH/outer"
    before="$(git rev-parse HEAD)"

    run commit_changes "test commit" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Nothing to commit (only skipped nested git repos)"* ]]
    [ "$(git rev-parse HEAD)" = "$before" ]
    [ -z "$(staged_gitlinks)" ]
}

@test "commit_changes: real changes commit while nested repo is skipped" {
    mk_outer "$SCRATCH/outer"
    mk_inner "$SCRATCH/outer/nested"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/outer"
    manifest_smart_documentation_review() { return 0; }
    export -f manifest_smart_documentation_review
    cd "$SCRATCH/outer"
    echo "change" >> seed.md
    before="$(git rev-parse HEAD)"

    run commit_changes "test commit" ""
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipped nested git repo: nested"* ]]
    [ "$(git rev-parse HEAD)" != "$before" ]
    # The commit carries the file change and no gitlink.
    git show --stat HEAD | grep -q "seed.md"
    [ -z "$(git ls-tree HEAD | awk '$1 == "160000"')" ]
}
