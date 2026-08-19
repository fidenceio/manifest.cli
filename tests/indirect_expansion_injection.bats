#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# SEC-017 (tracker §9.17). Repository data must never reach shell execution.
#
# `${!name}` is not a lookup, it is an evaluation: bash treats a TRAILING
# `[...]` as an array subscript and evaluates subscripts in an arithmetic
# context, where command substitution runs. So `name='x[$(cmd)]'` executes cmd.
#
# cloud.api_key_env is a mapped config key, so a repository's tracked
# manifest.config.yaml chose that name. The trigger was the validator itself:
# it rejected the malformed name but left it exported and reported the
# rejection through log_warning, which runs manifest_redact, which expanded it.
# Detecting the attack was what launched it.
#
# These tests assert on an OBSERVABLE SIDE EFFECT (a file that must not exist),
# not on log text — a redaction bug that stops printing would otherwise look
# like a fix.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    MARKER="$SCRATCH/PWNED"
    export MARKER
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-config.sh"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- the name validator itself -----------------------------------------------

@test "env name validator: accepts ordinary identifiers" {
    manifest_is_valid_env_var_name GITHUB_TOKEN
    manifest_is_valid_env_var_name _leading_underscore
    manifest_is_valid_env_var_name A1
}

@test "env name validator: rejects the subscript-injection shape" {
    refute manifest_is_valid_env_var_name 'x[$(id)]'
    refute manifest_is_valid_env_var_name 'x[0]'
    refute manifest_is_valid_env_var_name '1LEADING_DIGIT'
    refute manifest_is_valid_env_var_name 'has space'
    refute manifest_is_valid_env_var_name 'has-dash'
    refute manifest_is_valid_env_var_name ''
}

@test "env name validator: a rejected name is never expanded" {
    # manifest_env_value_of must fail closed rather than read.
    refute manifest_env_value_of "x[\$(touch '$MARKER')]"
    [ ! -e "$MARKER" ]
}

# --- the redactor: the actual sink -------------------------------------------

@test "SEC-017: a hostile cloud.api_key_env does not execute via manifest_redact" {
    export MANIFEST_CLI_CLOUD_API_KEY_ENV="x[\$(touch '$MARKER')]"
    run manifest_redact "some log line"
    [ ! -e "$MARKER" ]
}

@test "SEC-017: a hostile name is not emitted as a redaction target at all" {
    export MANIFEST_CLI_CLOUD_API_KEY_ENV="x[\$(touch '$MARKER')]"
    run _manifest_redaction_env_var_names
    [ ! -e "$MARKER" ]
    refute grep -q '\[' <<<"$output"
    # The fixed names must survive the filter — fail-closed, not fail-empty.
    echo "$output" | grep -qx 'GITHUB_TOKEN'
}

@test "SEC-017: a VALID indirected name is still redacted (no over-correction)" {
    export MANIFEST_CLI_CLOUD_API_KEY_ENV="MY_CLOUD_KEY"
    export MY_CLOUD_KEY="supersecretvalue123"
    run manifest_redact "token is supersecretvalue123 here"
    [ "$status" -eq 0 ]
    refute grep -q 'supersecretvalue123' <<<"$output"
    echo "$output" | grep -q 'REDACTED'
}

# --- the config validator: reject must mean remove ---------------------------

@test "SEC-017: rejecting cloud.api_key_env unsets it rather than leaving it live" {
    export MANIFEST_CLI_CLOUD_API_KEY_ENV="x[\$(touch '$MARKER')]"
    unset MANIFEST_CLI_CLOUD_API_KEY
    run _manifest_config_apply_secret_env_refs
    [ ! -e "$MARKER" ]
    # The whole point: the value must not survive for the next consumer.
    [ -z "${MANIFEST_CLI_CLOUD_API_KEY_ENV:-}" ] || {
        # `run` executes in a subshell, so re-check in this shell.
        _manifest_config_apply_secret_env_refs >/dev/null 2>&1 || true
        [ -z "${MANIFEST_CLI_CLOUD_API_KEY_ENV:-}" ]
    }
}

# --- fleet name construction: hardening, asserted as such --------------------

@test "fleet config: a hostile service name yields a clean miss, not an evaluation" {
    run get_fleet_service_path "A[\$(touch '$MARKER')]"
    [ "$status" -ne 0 ]
    [ ! -e "$MARKER" ]
}

@test "fleet config: a hostile service name falls back to the default property" {
    run get_fleet_service_property "A[\$(touch '$MARKER')]" "path" "THEDEFAULT"
    [ ! -e "$MARKER" ]
    [ "$output" = "THEDEFAULT" ]
}

@test "fleet config: ordinary service names still resolve after the guard" {
    export MANIFEST_CLI_FLEET_SERVICE_USER_SERVICE_PATH="/tmp/user-service"
    run get_fleet_service_path "user-service"
    [ "$status" -eq 0 ]
    [ "$output" = "/tmp/user-service" ]
}
