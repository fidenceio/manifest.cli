#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest_from_plain_dir() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

@test "discover fleet is the action-first discovery syntax" {
    run_manifest_from_plain_dir discover fleet --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"total"'* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}

@test "update fleet is the action-first update syntax" {
    run_manifest_from_plain_dir update fleet --json
    [ "$status" -eq 0 ]
    [[ "$output" == *'"total"'* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}

@test "other fleet commands expose action-first help" {
    run_manifest_from_plain_dir add fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest add fleet"* ]]

    run_manifest_from_plain_dir validate fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest validate fleet"* ]]

    run_manifest_from_plain_dir docs fleet help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest docs fleet"* ]]

    run_manifest_from_plain_dir pr fleet help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest pr fleet"* ]]

    run_manifest_from_plain_dir quickstart fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest quickstart fleet"* ]]
}

@test "old object-first fleet routes no longer execute" {
    run_manifest_from_plain_dir fleet discover --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest discover fleet"* ]]
    [[ "$output" != *'"total"'* ]]

    run_manifest_from_plain_dir fleet update --json
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest update fleet"* ]]
    [[ "$output" != *'"total"'* ]]
}
