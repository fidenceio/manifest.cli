#!/usr/bin/env bats
# The changelog's commit range: which tag "since the last tag" resolves to.
#
# `get_git_changes` builds `<previous tag>..HEAD` and turns every surviving
# commit subject into a changelog bullet. Picking the wrong tag does not error —
# it silently widens the range, and the release publishes the PREVIOUS release's
# work as its own, exit 0. That is the failure this file exists to prevent.
#
# THE PRECONDITION IS "HEAD IS TAGGED AT CHANGELOG-GENERATION TIME", and it is
# narrower than it looks, which is why these tests drive `get_git_changes`
# against a purpose-built repo rather than driving `ship`:
#
#   * A ship whose tree needs an auto-commit makes that commit FIRST, so by the
#     time the changelog is generated HEAD has moved off the tag. `HEAD~1` and
#     `HEAD` then resolve to the same tag and a broken reader looks correct.
#     An end-to-end ship test on a fresh fixture is therefore BLIND to this —
#     verified: with the defect planted, such a test stayed green.
#   * The exposure is the second of two consecutive ships — `--force-bump` on a
#     tree the previous ship left clean. There HEAD *is* the previous release's
#     tagged commit, and `HEAD~1` steps over that tag to the one before it.
#
# Reproduced end-to-end before this file was written: three real ships against a
# scratch repo with real tags produced a v2.1.0 whose entry was v2.0.0's bullets
# verbatim, while the third (v2.2.0) was correct — because by then HEAD~1 was
# itself a tagged release commit. One of two empty releases wrong is precisely
# the kind of half-firing defect a single end-to-end case misses.

load 'helpers/setup'

REAL_GIT="$(command -v git)"

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME

    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
}

# v1.0.0 → a commit belonging to the v1.2.3 release → v1.2.3 at HEAD, clean.
# The marker commit is reachable from v1.0.0 but NOT from v1.2.3, so it is the
# discriminator between the two readings.
mk_released_repo() {
    local repo="$SCRATCH/repo"
    mkdir -p "$repo"
    "$REAL_GIT" -C "$repo" init -q
    "$REAL_GIT" -C "$repo" symbolic-ref HEAD refs/heads/main
    "$REAL_GIT" -C "$repo" config user.email test@example.com
    "$REAL_GIT" -C "$repo" config user.name test

    echo "1.0.0" > "$repo/VERSION"
    "$REAL_GIT" -C "$repo" add VERSION
    "$REAL_GIT" -C "$repo" commit -qm "init 1.0.0"
    "$REAL_GIT" -C "$repo" tag "v1.0.0"

    echo "feature" > "$repo/feature.txt"
    "$REAL_GIT" -C "$repo" add feature.txt
    "$REAL_GIT" -C "$repo" commit -qm "feat: PRIORRELEASEMARKER shipped in v1.2.3"

    echo "1.2.3" > "$repo/VERSION"
    "$REAL_GIT" -C "$repo" add VERSION
    "$REAL_GIT" -C "$repo" commit -qm "Bump version to 1.2.3"
    "$REAL_GIT" -C "$repo" tag "v1.2.3"

    echo "$repo"
}

@test "changelog range: HEAD already tagged (a force-bump release) resolves to the tag AT HEAD" {
    local repo
    repo="$(mk_released_repo)"
    cd "$repo"

    run get_git_changes "1.2.4"
    [ "$status" -eq 0 ]

    # The range must start at v1.2.3, so the previous release's commit is gone.
    [[ "$output" != *"PRIORRELEASEMARKER"* ]]
}

@test "positive control: the discriminator IS reachable from the wrong tag" {
    local repo
    repo="$(mk_released_repo)"
    cd "$repo"

    # If this assertion ever fails, the fixture stopped discriminating and the
    # test above would pass vacuously — it would be asserting the absence of
    # something no range could contain.
    run "$REAL_GIT" -C "$repo" log --format='%s' "v1.0.0..HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PRIORRELEASEMARKER"* ]]

    # …and correspondingly absent from the correct range.
    run "$REAL_GIT" -C "$repo" log --format='%s' "v1.2.3..HEAD"
    [ "$status" -eq 0 ]
    [[ "$output" != *"PRIORRELEASEMARKER"* ]]
}

@test "control: a normal release (HEAD not tagged) still collects its own commits" {
    local repo
    repo="$(mk_released_repo)"

    echo "new" > "$repo/new.txt"
    "$REAL_GIT" -C "$repo" add new.txt
    "$REAL_GIT" -C "$repo" commit -qm "feat: NEWWORKMARKER not yet released"
    cd "$repo"

    run get_git_changes "1.2.4"
    [ "$status" -eq 0 ]

    # The ordinary path must keep working: unreleased work reaches the changelog,
    # and the range still does not reach back past v1.2.3. Without this, a fix
    # that emptied every range would pass the first test.
    [[ "$output" == *"NEWWORKMARKER"* ]]
    [[ "$output" != *"PRIORRELEASEMARKER"* ]]
}

@test "control: a repo with no tags at all collects everything and does not error" {
    local repo="$SCRATCH/untagged"
    mkdir -p "$repo"
    "$REAL_GIT" -C "$repo" init -q
    "$REAL_GIT" -C "$repo" symbolic-ref HEAD refs/heads/main
    "$REAL_GIT" -C "$repo" config user.email test@example.com
    "$REAL_GIT" -C "$repo" config user.name test
    echo "0.1.0" > "$repo/VERSION"
    "$REAL_GIT" -C "$repo" add VERSION
    "$REAL_GIT" -C "$repo" commit -qm "feat: FIRSTCOMMITMARKER"
    cd "$repo"

    run get_git_changes "0.1.1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"FIRSTCOMMITMARKER"* ]]
}
