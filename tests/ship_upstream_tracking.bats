#!/usr/bin/env bats

# Coverage for upstream tracking after a release push.
#
# push_changes() pushes a literal refspec (`git push <remote> <branch> <tag>`),
# which updates refs/remotes/<remote>/<branch> but never writes
# branch.<name>.remote / branch.<name>.merge. Without a compensating step, a repo
# that only Manifest has ever pushed is left with no upstream, and the human has
# to run `git push -u` once by hand before bare git push/pull/status work.
#
# manifest_set_upstream_if_absent() closes that gap as a separate config write
# after the push, so the release refspec itself stays literal and untouched.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh"
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo"

    REMOTE="$SCRATCH/remote.git"
    git init --bare -q "$REMOTE"

    git init -q "$MANIFEST_CLI_PROJECT_ROOT"
    cd "$MANIFEST_CLI_PROJECT_ROOT"
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit -q --allow-empty -m "first"

    BRANCH="$(git branch --show-current)"
    export BRANCH REMOTE
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="$BRANCH"

    unset MANIFEST_CLI_GIT_TAG_PREFIX MANIFEST_CLI_GIT_TAG_SUFFIX
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- the reported defect ------------------------------------------------------

@test "push_changes: a repo only Manifest ever pushed ends up with an upstream" {
    git remote add origin "$REMOTE"

    # Precondition: this is the state the defect describes.
    refute git config --get "branch.$BRANCH.remote"

    run create_tag "1.0.0"
    [ "$status" -eq 0 ]
    run push_changes "1.0.0"
    [ "$status" -eq 0 ]

    [ "$(git config --get "branch.$BRANCH.remote")" = "origin" ]
    [ "$(git config --get "branch.$BRANCH.merge")" = "refs/heads/$BRANCH" ]
    # The user-visible payoff: ahead/behind works without a manual push first.
    # Captured whole and sliced rather than piped into `head -1`, which would
    # close the pipe on git mid-write and surface as pipefail status 141.
    local sb
    sb="$(git status -sb)"
    [[ "${sb%%$'\n'*}" == *"$BRANCH...origin/$BRANCH"* ]]
}

@test "push_changes: announces the config write rather than doing it silently" {
    git remote add origin "$REMOTE"
    run create_tag "1.0.0"
    [ "$status" -eq 0 ]

    run push_changes "1.0.0"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Set upstream"* ]]
}

# --- the release path must stay untouched ------------------------------------

@test "push_changes: still pushes the literal branch+tag refspec (no -u added)" {
    # The guard in ship_release_branch_guard.bats depends on push_changes pushing
    # the literal default-branch ref. Setting upstream must not have relaxed that.
    grep -E 'git push .*\$default_branch .*\$tag_name' \
        "$TEST_REPO_ROOT/modules/git/manifest-git.sh" >/dev/null
    # Upstream is set by a separate `git branch --set-upstream-to` afterwards,
    # never by relaxing the release push itself into `git push -u`.
    refute grep -qE '^[^#]*git push .*(-u |--set-upstream)' \
        "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
}

# --- never override the user's choice ----------------------------------------

@test "set_upstream_if_absent: an existing upstream is left alone" {
    git remote add origin "$REMOTE"
    git remote add mirror "$REMOTE"
    git push -q origin "$BRANCH"
    git push -q mirror "$BRANCH"
    git config "branch.$BRANCH.remote" "mirror"
    git config "branch.$BRANCH.merge" "refs/heads/$BRANCH"

    run manifest_set_upstream_if_absent "$MANIFEST_CLI_PROJECT_ROOT" "$BRANCH"
    [ "$status" -eq 0 ]
    [ "$(git config --get "branch.$BRANCH.remote")" = "mirror" ]
    [[ "$output" != *"Set upstream"* ]]
}

# --- remote selection ---------------------------------------------------------

@test "set_upstream_if_absent: prefers 'origin' when several remotes exist" {
    git remote add mirror "$REMOTE"
    git remote add origin "$REMOTE"
    git push -q origin "$BRANCH"
    git push -q mirror "$BRANCH"

    run manifest_set_upstream_if_absent "$MANIFEST_CLI_PROJECT_ROOT" "$BRANCH"
    [ "$status" -eq 0 ]
    [ "$(git config --get "branch.$BRANCH.remote")" = "origin" ]
}

@test "set_upstream_if_absent: adopts a lone remote that isn't named origin" {
    git remote add upstream "$REMOTE"
    git push -q upstream "$BRANCH"

    run manifest_set_upstream_if_absent "$MANIFEST_CLI_PROJECT_ROOT" "$BRANCH"
    [ "$status" -eq 0 ]
    [ "$(git config --get "branch.$BRANCH.remote")" = "upstream" ]
}

@test "set_upstream_if_absent: refuses to guess among several non-origin remotes" {
    git remote add alpha "$REMOTE"
    git remote add beta "$REMOTE"
    git push -q alpha "$BRANCH"
    git push -q beta "$BRANCH"

    run manifest_set_upstream_if_absent "$MANIFEST_CLI_PROJECT_ROOT" "$BRANCH"
    [ "$status" -eq 0 ]
    refute git config --get "branch.$BRANCH.remote"
    [[ "$output" != *"Set upstream"* ]]
}

# --- never fatal --------------------------------------------------------------

@test "set_upstream_if_absent: no remotes at all is a silent no-op, not an error" {
    run manifest_set_upstream_if_absent "$MANIFEST_CLI_PROJECT_ROOT" "$BRANCH"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "set_upstream_if_absent: missing remote-tracking ref is a no-op, not an error" {
    # Remote configured but never pushed to — refs/remotes/origin/<branch> absent.
    git remote add origin "$REMOTE"

    run manifest_set_upstream_if_absent "$MANIFEST_CLI_PROJECT_ROOT" "$BRANCH"
    [ "$status" -eq 0 ]
    refute git config --get "branch.$BRANCH.remote"
}
