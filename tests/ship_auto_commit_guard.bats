#!/usr/bin/env bats
# §82 — the pre-bump auto-commit sweep is a checked ship step.
#
# It used to run bare with its return value ignored, so a hook that refused the
# sweep let the ship carry on to the VERSION bump and fail there — on the same
# hook, with the tree already dirty with Manifest's own writes. Now it is
# wrapped, checked, and a failure there stops the ship before anything is
# written; the report says so and never advises discarding the operator's files.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    unset MANIFEST_CLI_AUTO_CONFIRM MANIFEST_CLI_RELEASE_GATE MANIFEST_CLI_GIT_DEFAULT_BRANCH
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    cd /tmp
    rm -rf "$SCRATCH"
}

# Trusted time offline and fast (pattern: ci_verdict.bats).
neutralize_trusted_time() {
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
}

# A repo at 1.2.3 with ONE pending file the sweep must pick up. Prints its path.
_mk_dirty_repo() {
    local repo="$SCRATCH/work/repo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" symbolic-ref HEAD refs/heads/main
    git -C "$repo" config user.email test@example.com
    git -C "$repo" config user.name test
    echo "1.2.3" > "$repo/VERSION"
    git -C "$repo" add VERSION
    git -C "$repo" commit -qm "init 1.2.3"
    printf 'operator work in progress\n' > "$repo/notes.md"
    echo "$repo"
}

# A pre-commit hook (through core.hooksPath, outside the tree) that prints to
# STDOUT and refuses.
_install_refusing_hook() {
    local repo="$1" hooks="$SCRATCH/hooks"
    mkdir -p "$hooks"
    printf '#!/bin/sh\necho "HOOK-FIXTURE: refusing this commit"\nexit 1\n' > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"
    git -C "$repo" config core.hooksPath "$hooks"
}

_ship_local() {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH=main
    # The gate runs before the sweep; this test is about the sweep.
    export MANIFEST_CLI_RELEASE_GATE=none
    neutralize_trusted_time
    cd "$1"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" ship repo patch --local -y
}

@test "CONTROL: without a hook the sweep commits the pending file and the local ship completes" {
    local repo; repo="$(_mk_dirty_repo)"
    _ship_local "$repo"
    [ "$status" -eq 0 ]
    # The ship scaffolds its own files before the sweep, so the count is more
    # than the operator's one file; what matters is that the sweep ran …
    [[ "$output" =~ Auto-committing\ [0-9]+\ pending\ file ]]
    # … swept the operator's file into its own commit, and the bump then landed.
    local subjects
    subjects="$(git -C "$repo" log --format=%s)"
    grep -q "^Auto-commit before Manifest process" <<<"$subjects"
    git -C "$repo" ls-files --error-unmatch notes.md >/dev/null
    [ "$(cat "$repo/VERSION")" = "1.2.4" ]
    [ -z "$(git -C "$repo" status --porcelain)" ]
}

@test "a hook that refuses the auto-commit stops the ship BEFORE the bump; its STDOUT is shown; the operator's file is untouched" {
    local repo before
    repo="$(_mk_dirty_repo)"
    before="$(git -C "$repo" rev-parse HEAD)"
    _install_refusing_hook "$repo"

    _ship_local "$repo"

    [ "$status" -ne 0 ]
    [[ "$output" == *"HOOK-FIXTURE: refusing this commit"* ]]
    [[ "$output" == *"hook active at"* ]]
    [[ "$output" == *"failed step:        auto_commit"* ]]
    [[ "$output" == *"your pending files are untouched"* ]]
    # The recovery advice must never point at the operator's own work.
    [[ "$output" != *"git checkout HEAD --"* ]]
    [[ "$output" != *"reset --hard"* ]]
    # Nothing was written: no bump, no commit, no tag, and the pending file is
    # still pending with its content intact.
    [ "$(cat "$repo/VERSION")" = "1.2.3" ]
    [ "$(git -C "$repo" rev-parse HEAD)" = "$before" ]
    [ -z "$(git -C "$repo" tag)" ]
    [ -n "$(git -C "$repo" status --porcelain -- notes.md)" ]
    [ "$(cat "$repo/notes.md")" = "operator work in progress" ]
}
