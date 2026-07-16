#!/usr/bin/env bats

# Coverage for the layered config CRUD (manifest-config-crud.sh): apply-path
# set/unset actually mutate the layer file, get reads the layered effective
# value (local > project > env-var fallback), describe reports source layers,
# unknown keys are rejected before any write, and the global layer stays
# behind the safety gate (non-TTY refusal without MANIFEST_CLI_AUTO_CONFIRM).

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    # HOME must be isolated before sourcing: manifest-config.sh resolves
    # MANIFEST_CLI_GLOBAL_CONFIG from $HOME at source time.
    load_modules "core/manifest-config.sh" "core/manifest-config-crud.sh"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    export MANIFEST_CLI_PROJECT_ROOT="$PROJ"
    cd "$PROJ"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_PROJECT_ROOT MANIFEST_CLI_AUTO_CONFIRM
    unset MANIFEST_CLI_GIT_TAG_PREFIX MANIFEST_CLI_GIT_TAG_SUFFIX
}

# -----------------------------------------------------------------------------
# set -y (apply)
# -----------------------------------------------------------------------------

@test "config set -y: writes the default (local) layer file" {
    run manifest_config_set git.default_branch trunk -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "✓ set local:git.default_branch = trunk"
    echo "$output" | grep -q "$PROJ/manifest.config.local.yaml"
    [ -f "$PROJ/manifest.config.local.yaml" ]
    [ "$(yq e '.git.default_branch' "$PROJ/manifest.config.local.yaml")" = "trunk" ]
    # Only the targeted layer was written.
    [ ! -f "$PROJ/manifest.config.yaml" ]
}

@test "config set -y --layer project: writes manifest.config.yaml" {
    run manifest_config_set --layer project version.format semver -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "✓ set project:version.format = semver"
    [ "$(yq e '.version.format' "$PROJ/manifest.config.yaml")" = "semver" ]
    [ ! -f "$PROJ/manifest.config.local.yaml" ]
}

@test "config set -y: accepts the env-var spelling and normalizes to the dot-path" {
    run manifest_config_set MANIFEST_CLI_GIT_TAG_PREFIX rel- -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "✓ set local:git.tag_prefix = rel-"
    [ "$(yq e '.git.tag_prefix' "$PROJ/manifest.config.local.yaml")" = "rel-" ]
}

@test "config set -y: unknown key is rejected before any write" {
    run manifest_config_set bogus.key x -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown key: bogus.key"
    [ ! -f "$PROJ/manifest.config.local.yaml" ]
}

# -----------------------------------------------------------------------------
# get / unset round-trip across layers
# -----------------------------------------------------------------------------

@test "config get: local layer wins; unset -y peels it back to project" {
    run manifest_config_set --layer project git.default_branch develop -y
    [ "$status" -eq 0 ]
    run manifest_config_set --layer local git.default_branch trunk -y
    [ "$status" -eq 0 ]

    run manifest_config_get git.default_branch
    [ "$status" -eq 0 ]
    [ "$output" = "trunk" ]

    run manifest_config_unset git.default_branch -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "✓ unset local:git.default_branch"
    [ "$(yq e '.git.default_branch' "$PROJ/manifest.config.local.yaml")" = "null" ]

    run manifest_config_get git.default_branch
    [ "$status" -eq 0 ]
    [ "$output" = "develop" ]
}

@test "config get: falls back to the env var when no layer file sets the key" {
    export MANIFEST_CLI_GIT_TAG_PREFIX="v"
    run manifest_config_get git.tag_prefix
    [ "$status" -eq 0 ]
    [ "$output" = "v" ]
}

@test "config get: returns 1 when the key is set nowhere" {
    unset MANIFEST_CLI_GIT_TAG_SUFFIX
    run manifest_config_get git.tag_suffix
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "config unset -y: missing layer file is a friendly no-op" {
    run manifest_config_unset git.default_branch -y
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "(local file does not exist; nothing to unset)"
    [ ! -f "$PROJ/manifest.config.local.yaml" ]
}

# -----------------------------------------------------------------------------
# describe
# -----------------------------------------------------------------------------

@test "config describe: reports env var, effective value, and per-layer sources" {
    run manifest_config_set git.default_branch trunk -y
    [ "$status" -eq 0 ]

    run manifest_config_describe git.default_branch
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Key:       git.default_branch"
    echo "$output" | grep -q "Env var:   MANIFEST_CLI_GIT_DEFAULT_BRANCH"
    echo "$output" | grep -q "Effective: trunk"
    echo "$output" | grep -q "(from local)"
    echo "$output" | grep -q "Layers (highest precedence first):"
    # The local layer carries the value; project/global are absent.
    echo "$output" | grep -q "local    trunk"
    echo "$output" | grep -q "project  ·"
    echo "$output" | grep -q "global   ·"
}

@test "config describe: unknown key is rejected" {
    run manifest_config_describe not.a.key
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown key: not.a.key"
}

# -----------------------------------------------------------------------------
# global layer safety gate
# -----------------------------------------------------------------------------

@test "config set -y --layer global: refused non-interactively without AUTO_CONFIRM" {
    run manifest_config_set --layer global git.default_branch trunk -y < /dev/null
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Refusing to modify global config without confirmation."
    [ ! -f "$HOME/.manifest-cli/manifest.config.global.yaml" ]
}

@test "config set -y --layer global: AUTO_CONFIRM=1 authorizes and writes" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    run manifest_config_set --layer global brew.tap_repo example/homebrew-tap -y < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Auto-confirming modify"
    echo "$output" | grep -q "✓ set global:brew.tap_repo = example/homebrew-tap"
    [ "$(yq e '.brew.tap_repo' "$HOME/.manifest-cli/manifest.config.global.yaml")" = "example/homebrew-tap" ]
}
