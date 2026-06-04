#!/usr/bin/env bats
# §3.1 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Cloud apply-intent contract (workspace §1.1, CLI §3.1): a Cloud-backed
# mutation must carry an explicit execution_mode=apply. Requests that omit the
# field, or declare a non-apply mode, are rejected by the contract guard BEFORE
# any provider or analyzer runs. The guard fails closed.
#
# Cloud is a no-op stub today (modules/stubs/manifest-cloud-stub.sh); this file
# pins the contract on the stub now, so it is already enforced when §3.1 wires
# real Cloud calls. The "provider/analyzer" step is modeled by overriding the
# post-guard path (_manifest_cloud_not_available) with a sentinel, so each test
# can prove whether anything past the guard was reached.

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
    source "$TEST_REPO_ROOT/modules/stubs/manifest-cloud-stub.sh"

    # Provider/analyzer sentinel: the post-guard path writes this marker. If the
    # guard fails closed, the marker must never appear.
    PROVIDER_MARKER="$SCRATCH/provider-ran"
    _manifest_cloud_not_available() {
        : > "$PROVIDER_MARKER"
        return 1
    }

    # The CLI execution mode the request declares; §3.1 will populate this from
    # the parsed CLI execution mode. Start with it unset (missing field).
    unset MANIFEST_CLI_CLOUD_EXECUTION_MODE
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# --- guard in isolation ------------------------------------------------------

@test "cloud contract: missing execution_mode is rejected fail-closed" {
    run manifest_cloud_require_apply_intent
    [ "$status" -ne 0 ]
}

@test "cloud contract: execution_mode=preview is rejected" {
    MANIFEST_CLI_CLOUD_EXECUTION_MODE=preview run manifest_cloud_require_apply_intent
    [ "$status" -ne 0 ]
}

@test "cloud contract: an unrecognized execution_mode is rejected" {
    MANIFEST_CLI_CLOUD_EXECUTION_MODE=apply-soon run manifest_cloud_require_apply_intent
    [ "$status" -ne 0 ]
}

@test "cloud contract: execution_mode=apply passes the guard" {
    MANIFEST_CLI_CLOUD_EXECUTION_MODE=apply run manifest_cloud_require_apply_intent
    [ "$status" -eq 0 ]
}

# --- guard gates the request before the provider/analyzer --------------------

@test "cloud contract: request missing apply intent is rejected" {
    run send_to_manifest_cloud "5.2.0" "$SCRATCH/changes" "patch"
    [ "$status" -ne 0 ]
}

@test "cloud contract: rejection happens before any provider or analyzer runs" {
    run send_to_manifest_cloud "5.2.0" "$SCRATCH/changes" "patch"
    [ "$status" -ne 0 ]
    # The post-guard (provider/analyzer) path must not have been reached.
    [ ! -e "$PROVIDER_MARKER" ]
}

@test "cloud contract: error names the apply-intent requirement, not a generic failure" {
    run send_to_manifest_cloud "5.2.0" "$SCRATCH/changes" "patch"
    [ "$status" -ne 0 ]
    [[ "$output" == *"execution_mode=apply"* ]]
}

@test "cloud contract: with apply intent the request proceeds past the guard" {
    MANIFEST_CLI_CLOUD_EXECUTION_MODE=apply run send_to_manifest_cloud "5.2.0" "$SCRATCH/changes" "patch"
    # Cloud is still a no-op stub, so the call ultimately fails — but only after
    # the guard passed and the post-guard path was reached.
    [ -e "$PROVIDER_MARKER" ]
}
