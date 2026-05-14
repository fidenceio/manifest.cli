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
    SCRATCH="$(mk_scratch)"
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # Stub log_error/log_warning so we can capture without coloring noise.
    export MANIFEST_FLEET_SERVICES="alpha bravo charlie"
}

teardown() {
    rm -rf "$SCRATCH"
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

@test "fleet config loads per-service release policy from root config" {
    cat > "$SCRATCH/manifest.fleet.tsv" <<'TSV'
true	alpha	./alpha	service	true	git@example.com:org/alpha.git	main
true	bravo	./bravo	service	true	git@example.com:org/bravo.git	main
TSV
    cat > "$SCRATCH/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: test-fleet
  versioning: none
services:
  alpha:
    release:
      enabled: true
      strategy: direct
  bravo:
    release:
      enabled: false
      strategy: none
YAML
    mkdir -p "$SCRATCH/alpha" "$SCRATCH/bravo"
    export MANIFEST_FLEET_ROOT="$SCRATCH"
    export MANIFEST_FLEET_CONFIG_FILE="$SCRATCH/manifest.fleet.config.yaml"
    export MANIFEST_FLEET_SERVICES="alpha bravo"

    _load_all_service_configs "$SCRATCH"

    [ "$(get_fleet_service_property alpha release_enabled)" = "true" ]
    [ "$(get_fleet_service_property alpha release_strategy)" = "direct" ]
    [ "$(get_fleet_service_property bravo release_enabled)" = "false" ]
    [ "$(get_fleet_service_property bravo release_strategy)" = "none" ]
}

@test "fleet_ship: apply ships releaseable services directly and never calls PR dispatch" {
    mkdir -p "$SCRATCH/alpha/.git" "$SCRATCH/bravo/.git" "$SCRATCH/tap/.git"
    echo "1.0.0" > "$SCRATCH/alpha/VERSION"
    echo "1.0.0" > "$SCRATCH/bravo/VERSION"
    echo "1.0.0" > "$SCRATCH/tap/VERSION"
    export MANIFEST_FLEET_ROOT="$SCRATCH"
    export MANIFEST_FLEET_SERVICES="alpha bravo tap"
    export SHIPPED_SERVICES_FILE="$SCRATCH/shipped.log"
    : > "$SHIPPED_SERVICES_FILE"

    _fleet_require_initialized() { return 0; }
    get_fleet_service_property() {
        case "$1:$2" in
            alpha:path) echo "$SCRATCH/alpha" ;;
            bravo:path) echo "$SCRATCH/bravo" ;;
            tap:path) echo "$SCRATCH/tap" ;;
            tap:release_enabled) echo "false" ;;
            *) echo "" ;;
        esac
    }
    manifest_ship_repo() {
        printf '%s %s\n' "$(basename "$PWD")" "$*" >> "$SHIPPED_SERVICES_FILE"
    }
    manifest_fleet_pr_dispatch() {
        echo "PR dispatch should not run: $*"
        return 99
    }

    run fleet_ship patch -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Starting fleet ship workflow (patch)"* ]]
    [[ "$output" == *"Fleet scope"* ]]
    [[ "$output" == *"Selected:"*"3 services"* ]]
    [[ "$output" == *"Included repositories"* ]]
    [[ "$output" == *"alpha"*"release"*"would ship"*"$SCRATCH/alpha"* ]]
    [[ "$output" == *"tap"*"read"*"skip"*"$SCRATCH/tap (release disabled)"* ]]
    [[ "$output" == *"alpha: shipping patch"* ]]
    [[ "$output" == *"bravo: shipping patch"* ]]
    [[ "$output" == *"tap: skipped (release disabled)"* ]]
    [[ "$output" != *"PR dispatch should not run"* ]]
    grep -q '^alpha patch -y$' "$SHIPPED_SERVICES_FILE"
    grep -q '^bravo patch -y$' "$SHIPPED_SERVICES_FILE"
    ! grep -q '^tap ' "$SHIPPED_SERVICES_FILE"
}
