#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for the shared apply-guard helpers and the plan fingerprint
# (CLI tracker 2.1 + 2.2): manifest_execution_require_apply /
# manifest_execution_replay_hint centralize the preview/apply boundary, and
# manifest_plan_fingerprint gives a stable digest of a release plan for
# preview/apply comparison and the future apply-event audit log.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-requirements.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- replay hint ------------------------------------------------------------

@test "replay_hint appends -y to the base command" {
    run manifest_execution_replay_hint "manifest ship repo patch"
    [ "$status" -eq 0 ]
    [ "$output" = "manifest ship repo patch -y" ]
}

# --- require_apply guard ----------------------------------------------------

@test "require_apply: preview mode is a no-op and never confirms" {
    # Override the confirm to detect if it is (wrongly) called.
    manifest_repo_scope_confirm_apply() { echo "CONFIRM-CALLED"; return 0; }
    run manifest_execution_require_apply "preview" "/tmp" "hint -y"
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "CONFIRM-CALLED"
}

@test "require_apply: apply mode confirms and proceeds on accept" {
    manifest_repo_scope_confirm_apply() { return 0; }
    run manifest_execution_require_apply "apply" "/tmp" "hint -y"
    [ "$status" -eq 0 ]
}

@test "require_apply: apply mode propagates a declined confirmation" {
    manifest_repo_scope_confirm_apply() { return 1; }
    run manifest_execution_require_apply "apply" "/tmp" "hint -y"
    [ "$status" -eq 1 ]
}

@test "require_apply: apply mode passes the project root and replay hint through" {
    manifest_repo_scope_confirm_apply() { echo "root=$1 hint=$2"; return 0; }
    run manifest_execution_require_apply "apply" "/srv/repo" "manifest ship repo patch -y"
    [ "$status" -eq 0 ]
    [ "$output" = "root=/srv/repo hint=manifest ship repo patch -y" ]
}

# --- plan fingerprint -------------------------------------------------------

@test "plan fingerprint is a stable 12-char digest for identical inputs" {
    local a b
    a="$(manifest_plan_fingerprint ship-repo patch false 1.0.0 1.0.1 v1.0.1)"
    b="$(manifest_plan_fingerprint ship-repo patch false 1.0.0 1.0.1 v1.0.1)"
    [ "$a" = "$b" ]
    [ "${#a}" -eq 12 ]
}

@test "plan fingerprint changes when any field changes" {
    local base diff_type diff_ver
    base="$(manifest_plan_fingerprint ship-repo patch false 1.0.0 1.0.1 v1.0.1)"
    diff_type="$(manifest_plan_fingerprint ship-repo minor false 1.0.0 1.1.0 v1.1.0)"
    diff_ver="$(manifest_plan_fingerprint ship-repo patch false 2.0.0 2.0.1 v2.0.1)"
    [ "$base" != "$diff_type" ]
    [ "$base" != "$diff_ver" ]
}

@test "plan fingerprint is order-sensitive" {
    local a b
    a="$(manifest_plan_fingerprint patch minor)"
    b="$(manifest_plan_fingerprint minor patch)"
    [ "$a" != "$b" ]
}
