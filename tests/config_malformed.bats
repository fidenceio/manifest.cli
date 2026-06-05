#!/usr/bin/env bats
#
# §8.4a: a config file that is PRESENT but unparseable must FAIL LOUD, not
# silently fall back to built-in defaults.
#
# Root cause this pins: parse_yaml_with_yq returned 1 on ANY nonzero yq rc
# (stderr swallowed); get_yaml_value treats that identically to "key not
# found" and returns the default; load_yaml_to_env loops keys swallowing
# errors. So ONE syntax error (unterminated quote, tab indent) in a present
# config made yq fail on every key -> the ENTIRE config silently reverted to
# defaults and a ship proceeded with the wrong branch/gate/policy.
#
# Fix: load_yaml_to_env validates the whole document ONCE before the per-key
# loop (yq e '.' file) and returns a distinct code (2) with a clear error +
# yq's own diagnostic on failure; load_configuration treats a nonzero return
# from a PRESENT file as fatal. An ABSENT file stays non-fatal.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed on host"
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/project"
    load_modules
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- load_yaml_to_env: direct contract ---------------------------------------

@test "malformed: unterminated quote makes load_yaml_to_env fail loud (rc 2)" {
    local cfg="$SCRATCH/bad.yaml"
    printf 'git:\n  tag_prefix: "unterminated\n' > "$cfg"

    run load_yaml_to_env "$cfg"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "not valid YAML"
    echo "$output" | grep -q "$cfg"
}

@test "malformed: tab-indented invalid file makes load_yaml_to_env fail loud (rc 2)" {
    local cfg="$SCRATCH/tab.yaml"
    printf 'git:\n\ttag_prefix: v\n' > "$cfg"

    run load_yaml_to_env "$cfg"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "not valid YAML"
}

@test "malformed: a malformed file does NOT silently apply built-in defaults" {
    # The whole point of §8.4a: a broken file must NOT leave the env at defaults
    # as if nothing happened. Set a sentinel that differs from the default, run
    # the loader on a broken file, and assert (a) it failed and (b) it did not
    # overwrite/clear the pre-existing value with a default.
    local cfg="$SCRATCH/bad.yaml"
    printf 'git:\n  tag_prefix: "oops\n' > "$cfg"
    export MANIFEST_CLI_GIT_TAG_PREFIX="sentinel-"

    run load_yaml_to_env "$cfg"
    [ "$status" -eq 2 ]
    # The loader aborted before the per-key loop, so the env var is untouched —
    # crucially it was NOT reset to the built-in default "v".
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "sentinel-" ]
}

@test "valid: a well-formed config still loads correctly (no regression)" {
    local cfg="$SCRATCH/good.yaml"
    cat > "$cfg" <<'YAML'
git:
  tag_prefix: "rel-"
YAML
    unset MANIFEST_CLI_GIT_TAG_PREFIX

    run load_yaml_to_env "$cfg"
    [ "$status" -eq 0 ]

    load_yaml_to_env "$cfg"
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "rel-" ]
}

@test "absent: a missing file is non-fatal at the loader's file-existence guard" {
    # load_yaml_to_env returns 1 (not 2) for a missing file; load_configuration
    # only ever calls it under a `[ -f ]` guard, so the missing-file path is
    # never the parse-failure path. Pin the distinction.
    run load_yaml_to_env "$SCRATCH/does-not-exist.yaml"
    [ "$status" -eq 1 ]
}

# --- load_configuration: end-to-end fail-loud vs. non-regression -------------

@test "malformed: load_configuration aborts on a present-but-broken global config" {
    # The config module derives MANIFEST_CLI_GLOBAL_CONFIG from $HOME at source
    # time, so the global config must live at its canonical path under $HOME.
    mkdir -p "$SCRATCH/home/.manifest-cli"
    printf 'git:\n  tag_prefix: "unterminated\n' > "$SCRATCH/home/.manifest-cli/manifest.config.global.yaml"

    run env \
        HOME="$SCRATCH/home" \
        PROJECT_ROOT="$SCRATCH/project" \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh"; load_configuration "$PROJECT_ROOT" "false"' _ "$TEST_REPO_ROOT"

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "could not be parsed"
}

@test "malformed: load_configuration aborts on a present-but-broken project config" {
    printf 'git:\n\ttag_prefix: v\n' > "$SCRATCH/project/manifest.config.yaml"

    run env \
        HOME="$SCRATCH/home" \
        MANIFEST_CLI_GLOBAL_CONFIG="$SCRATCH/home/cfg.yaml" \
        PROJECT_ROOT="$SCRATCH/project" \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh"; load_configuration "$PROJECT_ROOT" "false"' _ "$TEST_REPO_ROOT"

    [ "$status" -ne 0 ]
    echo "$output" | grep -q "could not be parsed"
}

@test "absent: load_configuration succeeds with NO config files (defaults, no regression)" {
    # No global config, no project config: defaults must load and the command
    # must succeed exactly as before §8.4a. (HOME has no .manifest-cli config.)
    run env \
        HOME="$SCRATCH/home" \
        PROJECT_ROOT="$SCRATCH/project" \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh"; load_configuration "$PROJECT_ROOT" "false" >/dev/null 2>&1; printf "%s" "$MANIFEST_CLI_GIT_TAG_PREFIX"' _ "$TEST_REPO_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = "v" ]
}

@test "valid: load_configuration applies a well-formed global config (no regression)" {
    mkdir -p "$SCRATCH/home/.manifest-cli"
    cat > "$SCRATCH/home/.manifest-cli/manifest.config.global.yaml" <<'YAML'
git:
  tag_prefix: "release-"
YAML

    # load_configuration logs (and may emit migration-drift warnings) on stderr;
    # `run` merges stderr+stdout, so suppress stderr to assert the loaded VALUE.
    run env \
        HOME="$SCRATCH/home" \
        PROJECT_ROOT="$SCRATCH/project" \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh"; load_configuration "$PROJECT_ROOT" "false" >/dev/null 2>&1; printf "%s" "$MANIFEST_CLI_GIT_TAG_PREFIX"' _ "$TEST_REPO_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = "release-" ]
}
