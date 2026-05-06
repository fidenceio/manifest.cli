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

@test "recipe list exposes built-in ship recipes outside a git repository" {
    run_manifest_from_plain_dir recipe list
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest.builtin.ship.repo.patch"* ]]
    [[ "$output" == *"manifest ship repo patch"* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}

@test "recipe show prints the built-in recipe yaml" {
    run_manifest_from_plain_dir recipe show manifest.builtin.ship.repo.patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"id: manifest.builtin.ship.repo.patch"* ]]
    [[ "$output" == *"command: manifest ship repo patch"* ]]
}

@test "recipe explain renders command mapping and steps" {
    run_manifest_from_plain_dir recipe explain manifest.builtin.ship.repo.patch
    [ "$status" -eq 0 ]
    [[ "$output" == *"Ship Repo Patch"* ]]
    [[ "$output" == *"Command:    manifest ship repo patch"* ]]
    [[ "$output" == *"bump-version -> manifest.version.bump"* ]]
}

@test "ship repo explain uses the built-in recipe without requiring git" {
    run_manifest_from_plain_dir ship repo patch --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"ID:         manifest.builtin.ship.repo.patch"* ]]
    [[ "$output" == *"Definition:"* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}
