#!/usr/bin/env bats

# Tests for #24: 'manifest ship fleet --only / --except <service>' filtering.
#
# The filter is implemented inside fleet_ship via a service-list override of
# $MANIFEST_FLEET_SERVICES, plus forwarding of --only/--except to
# manifest_fleet_pr_dispatch (Cloud plugin honors them). These tests exercise:
#   - the _fleet_filter_services helper directly
#   - argument parsing in fleet_ship (mutual exclusion, missing values, help)
# We cannot exercise the full workflow here because PR dispatch requires Cloud.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # Stub log_error/log_warning so we can capture without coloring noise.
    export MANIFEST_FLEET_SERVICES="alpha bravo charlie"
}

# -----------------------------------------------------------------------------
# _fleet_filter_services helper.
# -----------------------------------------------------------------------------

@test "filter: --only single service returns just that service" {
    run _fleet_filter_services "alpha" ""
    [ "$status" -eq 0 ]
    [ "$output" = "alpha" ]
}

@test "filter: --only comma-separated list returns ordered subset" {
    run _fleet_filter_services "alpha,charlie" ""
    [ "$status" -eq 0 ]
    [ "$output" = "alpha charlie" ]
}

@test "filter: --only with unknown service errors out" {
    run _fleet_filter_services "alpha,zeta" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"'zeta'"* ]]
    [[ "$output" == *"not in the fleet"* ]]
}

@test "filter: --except removes named service" {
    run _fleet_filter_services "" "bravo"
    [ "$status" -eq 0 ]
    [ "$output" = "alpha charlie" ]
}

@test "filter: --except comma-separated list removes multiple" {
    run _fleet_filter_services "" "alpha,charlie"
    [ "$status" -eq 0 ]
    [ "$output" = "bravo" ]
}

@test "filter: --except with unknown service errors out" {
    run _fleet_filter_services "" "zeta"
    [ "$status" -ne 0 ]
    [[ "$output" == *"'zeta'"* ]]
    [[ "$output" == *"not in the fleet"* ]]
}

@test "filter: no selectors returns full fleet unchanged" {
    run _fleet_filter_services "" ""
    [ "$status" -eq 0 ]
    [ "$output" = "alpha bravo charlie" ]
}

@test "filter: word-boundary match — 'alpha' does not match 'alpha-svc'" {
    MANIFEST_FLEET_SERVICES="alpha-svc bravo"
    run _fleet_filter_services "alpha" ""
    [ "$status" -ne 0 ]
    [[ "$output" == *"not in the fleet"* ]]
}

# -----------------------------------------------------------------------------
# fleet_ship argument parsing — exercise via --help and validation paths.
# -----------------------------------------------------------------------------

@test "fleet_ship --help: documents --only and --except" {
    _fleet_require_initialized() { return 0; }
    run fleet_ship --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--only"* ]]
    [[ "$output" == *"--except"* ]]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "fleet_ship: --only and --except are mutually exclusive" {
    # Stub _fleet_require_initialized so we get past the gate.
    _fleet_require_initialized() { return 0; }
    run fleet_ship --only alpha --except bravo
    [ "$status" -ne 0 ]
    [[ "$output" == *"mutually exclusive"* ]]
}

@test "fleet_ship: --only without value errors" {
    _fleet_require_initialized() { return 0; }
    run fleet_ship --only
    [ "$status" -ne 0 ]
    [[ "$output" == *"--only requires"* ]]
}

@test "fleet_ship: --except without value errors" {
    _fleet_require_initialized() { return 0; }
    run fleet_ship --except
    [ "$status" -ne 0 ]
    [[ "$output" == *"--except requires"* ]]
}

@test "fleet_ship: --only with unknown service errors before workflow runs" {
    _fleet_require_initialized() { return 0; }
    # If the workflow ran, _fleet_prep_run would attempt git ops — failing in a
    # different way. We assert the *filter* error fires first.
    run fleet_ship --only nonexistent_svc
    [ "$status" -ne 0 ]
    [[ "$output" == *"'nonexistent_svc'"* ]]
    [[ "$output" == *"not in the fleet"* ]]
}
