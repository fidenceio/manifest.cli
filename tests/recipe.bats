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
    [[ "$output" == *"manifest.builtin.ship.fleet.minor"* ]]
    [[ "$output" == *"manifest ship fleet minor"* ]]
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
    [[ "$output" == *"create-github-release -> github.release.create {effect: remote-write} [publish_release && github.release.enabled]"* ]]
}

@test "recipe help advertises inspection only" {
    run_manifest_from_plain_dir recipe help
    [ "$status" -eq 0 ]
    [[ "$output" == *"manifest recipe <list|show|explain> [id]"* ]]
    [[ "$output" == *"Inspect Manifest workflow recipes behind first-class commands."* ]]
    [[ "$output" != *"run <id>"* ]]
}

@test "built-in recipes declare execution policy and step effects" {
    local file missing
    missing=""

    while IFS= read -r file; do
        if [ "$(yq e 'has("execution")' "$file")" != "true" ]; then
            missing="$missing $file:execution"
        fi
        if [ "$(yq e '.execution.default_mode // ""' "$file")" != "preview" ]; then
            missing="$missing $file:execution.default_mode"
        fi
        if [ "$(yq e '(.execution.requires_yes_for | type) == "!!seq"' "$file")" != "true" ]; then
            missing="$missing $file:execution.requires_yes_for"
        fi
        if [ "$(yq e '[.steps[] | select(has("effect") | not)] | length' "$file")" != "0" ]; then
            missing="$missing $file:steps.effect"
        fi
    done < <(find "$TEST_REPO_ROOT/recipes/builtin" -type f -name '*.yaml' | sort)

    [ -z "$missing" ]
}

@test "built-in ship recipes do not declare PR effects" {
    local file offenders
    offenders=""

    while IFS= read -r file; do
        if [ "$(yq e '[.steps[] | select(.effect == "pr")] | length' "$file")" != "0" ]; then
            offenders="$offenders $file"
        fi
    done < <(find "$TEST_REPO_ROOT/recipes/builtin" -type f -name 'manifest.builtin.ship.*.yaml' | sort)

    [ -z "$offenders" ]
}

@test "ship repo explain uses the built-in recipe without requiring git" {
    run_manifest_from_plain_dir ship repo patch --explain
    [ "$status" -eq 0 ]
    [[ "$output" == *"ID:         manifest.builtin.ship.repo.patch"* ]]
    [[ "$output" == *"Definition:"* ]]
    [[ "$output" != *"Not in a Git repository"* ]]
}

@test "ship fleet explain supports every advertised release type" {
    for release_type in patch minor major revision; do
        run_manifest_from_plain_dir ship fleet "$release_type" --explain
        [ "$status" -eq 0 ]
        [[ "$output" == *"ID:         manifest.builtin.ship.fleet.$release_type"* ]]
        [[ "$output" == *"Command:    manifest ship fleet $release_type"* ]]
        [[ "$output" != *"No built-in recipe is registered"* ]]
        [[ "$output" != *"Not in a Git repository"* ]]
    done
}
