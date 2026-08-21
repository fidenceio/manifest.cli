#!/usr/bin/env bats

# TYPE-001: fleet env-name normalization folds both '-' and '.' to '_'
# (tr '[:lower:]-.' '[:upper:]__'), so distinct member names like `my-service`
# and `my.service` land on the same MANIFEST_CLI_FLEET_SERVICE_MY_SERVICE_*
# config keys and the later TSV row silently overwrites the earlier member's
# path/url/branch. The loader must detect the collision and refuse the whole
# fleet config load, naming both members.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    mkdir -p "$SCRATCH/work"
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "collision-fleet"
  versioning: "none"
YAML
}

teardown() {
    cd /tmp || true
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_FLEET_ROOT MANIFEST_CLI_FLEET_ACTIVE
}

@test "distinct member names normalizing to the same env key refuse the load" {
    {
        printf 'true\tmy-service\t./my-service\ttrue\t\tmain\n'
        printf 'true\tmy.service\t./my.service\ttrue\t\tmain\n'
    } > "$SCRATCH/work/manifest.fleet.tsv"

    run load_fleet_config "$SCRATCH/work"

    [ "$status" -ne 0 ]
    [[ "$output" == *"my-service"* ]]
    [[ "$output" == *"my.service"* ]]
    [[ "$output" == *"MY_SERVICE"* ]]
}

@test "positive control: non-colliding members load cleanly" {
    # Proves the fixture itself can load — so the refusal above is the
    # collision guard, not a broken fixture.
    {
        printf 'true\tmy-service\t./my-service\ttrue\t\tmain\n'
        printf 'true\tother-service\t./other-service\ttrue\t\tmain\n'
    } > "$SCRATCH/work/manifest.fleet.tsv"

    load_fleet_config "$SCRATCH/work" >/dev/null 2>&1

    [ "$(get_fleet_service_path my-service)" = "$SCRATCH/work/my-service" ]
    [ "$(get_fleet_service_path other-service)" = "$SCRATCH/work/other-service" ]
}

@test "the same member listed twice is not reported as a name collision" {
    # The guard is for DISTINCT names merging; an exact duplicate row keeps
    # today's last-row-wins behavior rather than becoming a new failure mode.
    {
        printf 'true\tmy-service\t./my-service\ttrue\t\tmain\n'
        printf 'true\tmy-service\t./my-service\ttrue\t\tmain\n'
    } > "$SCRATCH/work/manifest.fleet.tsv"

    run load_fleet_config "$SCRATCH/work"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Fleet member name collision"* ]]
}
