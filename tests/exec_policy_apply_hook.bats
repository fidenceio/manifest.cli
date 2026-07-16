#!/usr/bin/env bats

# Coverage for the lazy apply hook in manifest-execution-policy.sh:
# manifest_execution_apply_header dispatches _manifest_execution_apply_hook
# when (and only when) a hook is registered and the apply boundary is reached.
# Preview paths never reach the boundary, and the real registered hook
# (manifest-config.sh) advances the warning cooldown marker at apply time.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset _MANIFEST_CLI_DEPRECATION_WARNED _MANIFEST_CLI_MIGRATION_NOTIFIED
}

@test "apply header fires a registered _manifest_execution_apply_hook" {
    _manifest_execution_apply_hook() {
        echo "hook-fired"
        touch "$SCRATCH/hook.marker"
    }

    run manifest_execution_apply_header
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    echo "$output" | grep -q "hook-fired"
    [ -f "$SCRATCH/hook.marker" ]
}

@test "apply header with no hook registered prints only the apply line" {
    ! declare -F _manifest_execution_apply_hook

    run manifest_execution_apply_header
    [ "$status" -eq 0 ]
    [ "$output" = "Applying because -y/--yes was provided." ]
}

@test "preview never reaches the apply boundary: registered hook stays silent" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    _manifest_execution_apply_hook() {
        echo "hook-fired"
        touch "$SCRATCH/hook.marker"
    }
    mkdir -p "$SCRATCH/work"
    cd "$SCRATCH/work"
    git init -q -b main
    git remote add origin git@github.com:example/x.git

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/work" run manifest_prep_repo --dry-run
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Dry run"
    ! echo "$output" | grep -q "hook-fired"
    [ ! -f "$SCRATCH/hook.marker" ]
}

@test "config module's real hook advances the warning cooldown at apply time" {
    # manifest-config.sh registers _manifest_execution_apply_hook; a pending
    # deprecation-warning marker must be flushed to the throttle file exactly
    # at the apply boundary.
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    export _MANIFEST_CLI_DEPRECATION_WARNED=1
    [ ! -f "$HOME/.manifest-cli/config-warning.last" ]

    run manifest_execution_apply_header
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    [ -f "$HOME/.manifest-cli/config-warning.last" ]
    grep -qE '^[0-9]+$' "$HOME/.manifest-cli/config-warning.last"
}

@test "config module's real hook honors the read-only guard (SKIP_WRITES)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    export _MANIFEST_CLI_DEPRECATION_WARNED=1
    export MANIFEST_CLI_CONFIG_SKIP_WRITES=1

    run manifest_execution_apply_header
    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.manifest-cli/config-warning.last" ]

    unset MANIFEST_CLI_CONFIG_SKIP_WRITES
}
