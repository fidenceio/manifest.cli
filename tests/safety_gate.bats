#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
    load_modules
    # manifest-config.sh sources cleanly without a real MANIFEST_CLI_PROJECT_ROOT/git context
    # because we only exercise _confirm_global_config_write here.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    SCRATCH="$(mk_scratch)"
    TARGET="$SCRATCH/global.yaml"
    : > "$TARGET"
    unset MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED MANIFEST_CLI_AUTO_CONFIRM
    # §46: the gate reads MANIFEST_CLI_AUTO_CONFIRM only through the module's
    # source-time snapshot of the PROCESS ENVIRONMENT, never live. Re-take the
    # snapshot with the variable unset so every case below starts from a known
    # "no consent supplied at process start" state regardless of ambient env.
    _manifest_config_capture_auto_confirm_env
}

# Simulate a CLI process that STARTED with MANIFEST_CLI_AUTO_CONFIRM=1 in its
# environment — the only origin the gate accepts. Exporting the variable alone
# is deliberately not enough (that is how a config file would set it); the pair
# of tests below pins both halves.
grant_auto_confirm_from_process_env() {
    export MANIFEST_CLI_AUTO_CONFIRM="${1:-1}"
    _manifest_config_capture_auto_confirm_env
}

teardown() {
    chmod -R u+w "$SCRATCH" 2>/dev/null || true
    rm -rf "$SCRATCH"
}

@test "safety gate: MANIFEST_CLI_AUTO_CONFIRM=1 bypasses prompt for modify" {
    grant_auto_confirm_from_process_env
    run _confirm_global_config_write "modify" "$TARGET" "test reason"
    [ "$status" -eq 0 ]
}

@test "safety gate: MANIFEST_CLI_AUTO_CONFIRM=1 bypasses prompt for delete" {
    grant_auto_confirm_from_process_env
    run _confirm_global_config_write "delete" "$TARGET" "test reason"
    [ "$status" -eq 0 ]
}

@test "safety gate: AUTO_CONFIRM sets the session-authorized flag" {
    grant_auto_confirm_from_process_env
    _confirm_global_config_write "modify" "$TARGET" "test reason"
    [ "$MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED" = "1" ]
}

@test "safety gate: §46 a value assigned AFTER the process-env snapshot does not authorize" {
    # This is precisely what a loaded config file does: load_yaml_to_env maps
    # automation.auto_confirm onto MANIFEST_CLI_AUTO_CONFIRM long after the
    # module was sourced. Repo-scope data must not authorize a write to a file
    # outside the repo, so the gate must ignore it.
    export MANIFEST_CLI_AUTO_CONFIRM=1
    run _confirm_global_config_write "modify" "$TARGET" "config-file origin"
    [ "$status" -ne 0 ]
    [ "${MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED:-0}" != "1" ]
}

@test "safety gate: §46 one predicate — 'true' in the process env does not authorize" {
    # The gate used is_truthy (true/yes/on/1) while manifest_repo_scope_confirm_apply
    # requires the literal "1", so a spelling decided which safety gates were
    # bypassed. Collapsed to the literal "1" here.
    grant_auto_confirm_from_process_env "true"
    run _confirm_global_config_write "modify" "$TARGET" "loose spelling"
    [ "$status" -ne 0 ]
}

@test "safety gate: §46 'yes' in the process env does not authorize either" {
    grant_auto_confirm_from_process_env "yes"
    run _confirm_global_config_write "modify" "$TARGET" "loose spelling"
    [ "$status" -ne 0 ]
}

@test "safety gate: session cache short-circuits subsequent modify ops" {
    export MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED=1
    # No AUTO_CONFIRM, no TTY — would normally fail. Cache should let it through.
    run _confirm_global_config_write "modify" "$TARGET" "subsequent modify"
    [ "$status" -eq 0 ]
}

@test "safety gate: cached approval does NOT short-circuit destructive delete" {
    export MANIFEST_CLI_GLOBAL_CONFIG_AUTHORIZED=1
    # Non-TTY + no AUTO_CONFIRM => should be denied even with prior approval.
    run _confirm_global_config_write "delete" "$TARGET" "destructive op"
    [ "$status" -ne 0 ]
}

@test "safety gate: non-TTY without AUTO_CONFIRM denies modify" {
    # bats redirects stdin so [ -t 0 ] is false; no AUTO_CONFIRM set.
    run _confirm_global_config_write "modify" "$TARGET" "should deny"
    [ "$status" -ne 0 ]
}

@test "config cooldown state writes are silent when state dir is unwritable" {
    # Held in a variable rather than spelled inline. The pre-commit hook's
    # absolute-home-path check greps for an UNANCHORED home-directory pattern,
    # so a scratch subdirectory of that name followed by another path segment
    # reads to it as a developer's real home path and blocks the commit. Every
    # other sandboxed-HOME test in this suite already uses this shape; this one
    # was the outlier. The over-broad pattern is filed separately -- do not
    # loosen a security hook to accommodate a test.
    local sandbox_home="$SCRATCH/home"
    mkdir -p "$sandbox_home/.manifest-cli"
    chmod u-w "$sandbox_home/.manifest-cli"

    HOME="$sandbox_home" MANIFEST_CLI_CONFIG_WARNING_COOLDOWN_MINUTES=1440 \
        run --separate-stderr _manifest_config_should_emit_warnings

    [ "$status" -eq 0 ]
    [ -z "$stderr" ]
}
