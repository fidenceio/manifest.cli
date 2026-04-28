#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    # manifest-config.sh sources cleanly without a real PROJECT_ROOT/git context
    # because we only exercise _confirm_global_config_write here.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    SCRATCH="$(mk_scratch)"
    TARGET="$SCRATCH/global.yaml"
    : > "$TARGET"
    unset _MANIFEST_GLOBAL_CONFIG_AUTHORIZED MANIFEST_CLI_AUTO_CONFIRM
}

teardown() {
    rm -rf "$SCRATCH"
}

@test "safety gate: MANIFEST_CLI_AUTO_CONFIRM=1 bypasses prompt for modify" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    run _confirm_global_config_write "modify" "$TARGET" "test reason"
    [ "$status" -eq 0 ]
}

@test "safety gate: MANIFEST_CLI_AUTO_CONFIRM=1 bypasses prompt for delete" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    run _confirm_global_config_write "delete" "$TARGET" "test reason"
    [ "$status" -eq 0 ]
}

@test "safety gate: AUTO_CONFIRM sets the session-authorized flag" {
    export MANIFEST_CLI_AUTO_CONFIRM=1
    _confirm_global_config_write "modify" "$TARGET" "test reason"
    [ "$_MANIFEST_GLOBAL_CONFIG_AUTHORIZED" = "1" ]
}

@test "safety gate: session cache short-circuits subsequent modify ops" {
    export _MANIFEST_GLOBAL_CONFIG_AUTHORIZED=1
    # No AUTO_CONFIRM, no TTY — would normally fail. Cache should let it through.
    run _confirm_global_config_write "modify" "$TARGET" "subsequent modify"
    [ "$status" -eq 0 ]
}

@test "safety gate: cached approval does NOT short-circuit destructive delete" {
    export _MANIFEST_GLOBAL_CONFIG_AUTHORIZED=1
    # Non-TTY + no AUTO_CONFIRM => should be denied even with prior approval.
    run _confirm_global_config_write "delete" "$TARGET" "destructive op"
    [ "$status" -ne 0 ]
}

@test "safety gate: non-TTY without AUTO_CONFIRM denies modify" {
    # bats redirects stdin so [ -t 0 ] is false; no AUTO_CONFIRM set.
    run _confirm_global_config_write "modify" "$TARGET" "should deny"
    [ "$status" -ne 0 ]
}
