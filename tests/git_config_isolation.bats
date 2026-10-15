#!/usr/bin/env bats
# bats file_tags=smoke

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    mkdir "$SCRATCH/a" "$SCRATCH/b"
}

teardown() { rm -rf "$SCRATCH"; }

@test "parallel test workers get separate writable Git global configs despite inherited gather state" {
    local parent_config="$GIT_CONFIG_GLOBAL"
    local parent_name="$(git config --global user.name)"
    run bash -c '
        worker() {
            export BATS_TEST_TMPDIR="$SCRATCH/$1"
            source "$2"
            for i in 1 2 3 4; do git config --global user.name "$1" || return 1; done
            [[ "$GIT_CONFIG_GLOBAL" == "$SCRATCH/$1/manifest-test-gitconfig" ]] || return 1
            [[ "$(git config --global user.name)" == "$1" ]]
        }
        worker a "$1" & first=$!
        worker b "$1" & second=$!
        wait "$first"; first_status=$?
        wait "$second"; second_status=$?
        [[ "$first_status" == 0 && "$second_status" == 0 ]]
    ' _ "$TEST_REPO_ROOT/tests/helpers/setup.bash"
    [ "$status" -eq 0 ]
    [ "$GIT_CONFIG_GLOBAL" = "$parent_config" ]
    [ "$(git config --global user.name)" = "$parent_name" ]
}

@test "reloading the shared helper keeps a test's private Git configuration" {
    run bash -c '
        export BATS_TEST_TMPDIR="$SCRATCH/a"
        source "$1"
        git config --global user.name custom
        source "$1"
        [[ "$(git config --global user.name)" == custom ]]
    ' _ "$TEST_REPO_ROOT/tests/helpers/setup.bash"
    [ "$status" -eq 0 ]
}
