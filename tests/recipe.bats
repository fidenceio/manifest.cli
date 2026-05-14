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
    [[ "$output" == *"confirm-repo-target -> manifest.repo.confirm_target {effect: read} [apply]"* ]]
    [[ "$output" == *"archive-docs -> manifest.docs.archive_sweep {effect: local-write}"* ]]
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

@test "built-in repo recipes describe repo target confirmation before writes" {
    local file offenders
    offenders=""

    for file in \
        "$TEST_REPO_ROOT/recipes/builtin/manifest.builtin.prep.repo.yaml" \
        "$TEST_REPO_ROOT/recipes/builtin/manifest.builtin.refresh.repo.yaml" \
        "$TEST_REPO_ROOT"/recipes/builtin/manifest.builtin.ship.repo.*.yaml; do
        if [ "$(yq e '[.steps[] | select(.id == "confirm-repo-target" and .uses == "manifest.repo.confirm_target" and .effect == "read" and .when == "apply")] | length' "$file")" != "1" ]; then
            offenders="$offenders $file"
        fi
    done

    [ -z "$offenders" ]
}

@test "built-in fleet ship recipes describe scope and releaseable-service plan" {
    local file offenders
    offenders=""

    while IFS= read -r file; do
        if [ "$(yq e '[.steps[] | select(.id == "render-fleet-scope" and .uses == "manifest.fleet.scope_block" and .effect == "read")] | length' "$file")" != "1" ]; then
            offenders="$offenders $file:scope"
        fi
        if [ "$(yq e '[.steps[] | select(.id == "build-release-plan" and .uses == "manifest.fleet.release_plan" and .effect == "read")] | length' "$file")" != "1" ]; then
            offenders="$offenders $file:plan"
        fi
        if grep -q 'prep-fleet\|manifest.fleet.ship_services' "$file"; then
            offenders="$offenders $file:stale"
        fi
    done < <(find "$TEST_REPO_ROOT/recipes/builtin" -type f -name 'manifest.builtin.ship.fleet.*.yaml' | sort)

    [ -z "$offenders" ]
}

@test "non-patch repo ship recipes include guarded follow-up patch" {
    local file offenders
    offenders=""

    for file in \
        "$TEST_REPO_ROOT/recipes/builtin/manifest.builtin.ship.repo.minor.yaml" \
        "$TEST_REPO_ROOT/recipes/builtin/manifest.builtin.ship.repo.major.yaml" \
        "$TEST_REPO_ROOT/recipes/builtin/manifest.builtin.ship.repo.revision.yaml"; do
        if [ "$(yq e '[.steps[] | select(.id == "follow-up-patch" and .uses == "manifest.ship.followup_patch" and .effect == "remote-write" and .when == "publish_release && canonical_cli")] | length' "$file")" != "1" ]; then
            offenders="$offenders $file"
        fi
    done

    if grep -q 'follow-up-patch' "$TEST_REPO_ROOT/recipes/builtin/manifest.builtin.ship.repo.patch.yaml"; then
        offenders="$offenders patch-should-not-follow-up"
    fi

    [ -z "$offenders" ]
}

@test "local apply validation allows every mapped ship recipe" {
    load_modules "recipe/manifest-recipe.sh"

    local scope release_type
    for scope in repo fleet; do
        for release_type in patch minor major revision; do
            run manifest_recipe_validate_command_effects ship "$scope" "$release_type" apply true false
            [ "$status" -eq 0 ]
        done
    done
}

@test "local apply validation rejects active remote-write steps" {
    load_modules "recipe/manifest-recipe.sh"
    local recipe="$SCRATCH/work/unsafe.yaml"

    cat > "$recipe" <<'YAML'
id: manifest.test.unsafe
steps:
  - id: push-release
    uses: manifest.git.push_release
    effect: remote-write
    when: apply
YAML

    run manifest_recipe_validate_local_apply_file "$recipe" "manifest test unsafe" apply true false
    [ "$status" -ne 0 ]
    [[ "$output" == *"Refusing local apply"* ]]
    [[ "$output" == *"push-release"* ]]
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
