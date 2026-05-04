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

@test "fleet help works outside a git repository" {
    run_manifest_from_plain_dir fleet help
    [ "$status" -eq 0 ]
    [[ "$output" == *"MANIFEST FLEET"* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}

@test "nested ship help works outside a git repository" {
    run_manifest_from_plain_dir ship fleet --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest ship fleet"* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}

@test "pr subcommand help does not require git or gh" {
    run_manifest_from_plain_dir pr create --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest pr create"* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
    [[ "$output" != *"'gh' (GitHub CLI) is required"* ]]
}

@test "destructive command help prints usage instead of running" {
    run_manifest_from_plain_dir uninstall --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usage: manifest uninstall"* ]]
    [[ "$output" != *"Uninstalling"* ]]
    [[ "$output" != *"Removing"* ]]
}
