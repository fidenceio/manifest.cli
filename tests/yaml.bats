#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    YAML="$SCRATCH/test.yaml"
}

teardown() {
    rm -rf "$SCRATCH"
}

@test "yaml: require_yaml_parser succeeds when yq is on PATH" {
    run require_yaml_parser
    [ "$status" -eq 0 ]
}

@test "yaml: yaml_path_to_env_var maps known YAML paths to MANIFEST_CLI_* envs" {
    run yaml_path_to_env_var "git.tag_prefix"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_GIT_TAG_PREFIX" ]
}

@test "yaml: env_var_to_yaml_path is the inverse of yaml_path_to_env_var" {
    run env_var_to_yaml_path "MANIFEST_CLI_GIT_TAG_PREFIX"
    [ "$status" -eq 0 ]
    [ "$output" = "git.tag_prefix" ]
}

@test "yaml: maps release tag target policy" {
    run yaml_path_to_env_var "release.tag_target"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_RELEASE_TAG_TARGET" ]

    run env_var_to_yaml_path "MANIFEST_CLI_RELEASE_TAG_TARGET"
    [ "$status" -eq 0 ]
    [ "$output" = "release.tag_target" ]
}

@test "yaml: set_yaml_value creates a file and writes a nested key" {
    set_yaml_value "$YAML" "git.tag_prefix" "v"
    [ -f "$YAML" ]
    run yq e ".git.tag_prefix" "$YAML"
    [ "$output" = "v" ]
}

@test "yaml: get_yaml_value reads a value previously written" {
    set_yaml_value "$YAML" "git.default_branch" "main"
    run get_yaml_value "$YAML" ".git.default_branch"
    [ "$status" -eq 0 ]
    [ "$output" = "main" ]
}

@test "yaml: get_yaml_value returns the supplied default when key is missing" {
    : > "$YAML"
    run get_yaml_value "$YAML" ".does.not.exist" "fallback-val"
    [ "$status" -eq 0 ]
    [ "$output" = "fallback-val" ]
}

@test "yaml: load_yaml_to_env exports mapped keys into MANIFEST_CLI_* envs" {
    set_yaml_value "$YAML" "git.tag_prefix" "release-"
    set_yaml_value "$YAML" "git.default_branch" "trunk"
    set_yaml_value "$YAML" "release.tag_target" "release_head"
    unset MANIFEST_CLI_GIT_TAG_PREFIX MANIFEST_CLI_GIT_DEFAULT_BRANCH MANIFEST_CLI_RELEASE_TAG_TARGET
    load_yaml_to_env "$YAML"
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "release-" ]
    [ "$MANIFEST_CLI_GIT_DEFAULT_BRANCH" = "trunk" ]
    [ "$MANIFEST_CLI_RELEASE_TAG_TARGET" = "release_head" ]
}

@test "yaml: load_yaml_to_env preserves unrelated env values when key absent (layered precedence)" {
    set_yaml_value "$YAML" "git.tag_prefix" "v"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="preserved"
    load_yaml_to_env "$YAML"
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "v" ]
    [ "$MANIFEST_CLI_GIT_DEFAULT_BRANCH" = "preserved" ]
}

@test "yaml: set_yaml_value followed by get_yaml_value round-trips multi-level paths" {
    set_yaml_value "$YAML" "time.cache_ttl" "120"
    set_yaml_value "$YAML" "time.cache_cleanup_period" "3600"
    run get_yaml_value "$YAML" ".time.cache_ttl"
    [ "$output" = "120" ]
    run get_yaml_value "$YAML" ".time.cache_cleanup_period"
    [ "$output" = "3600" ]
}
