#!/usr/bin/env bats

# Guards the honest-contract decision for the fleet config's `validation:`
# block (CLI TRACKER §2.8, extending the 2026-05-26 §require_expected_branch
# precedent). Every knob that lived under `validation:` advertised a guarantee
# the CLI never wired to a gate:
#   - require_expected_branch / allow_branch_operations — inert, removed 05-26
#   - require_clean_status — declared + mapped, but clean-status enforcement is
#     hardcoded-on in the apply path; flipping the flag changed nothing
#   - enforce_dependencies — declared + mapped, zero consumers
#   - strict — reachable via the short-key mapper, never in the heredoc, no gate
# All of them were removed rather than left as decorative config. Clean-status
# enforcement remains unconditional in the apply path. This test fails if any
# of these knobs is reintroduced into the generated default config or the
# env->yaml short-key mapper.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    SCRATCH="$(mk_scratch)"
    export SCRATCH
}

teardown() {
    rm -rf "$SCRATCH"
}

@test "generated fleet config carries no inert validation knobs" {
    local cfg="$SCRATCH/manifest.fleet.config.yaml"
    _generate_full_manifest "$cfg" "testfleet"

    [ -f "$cfg" ]
    # The whole validation: block and each former knob must be gone — none of
    # them was ever read by a gate, so advertising them was a contract hole.
    ! grep -qE '^validation:' "$cfg"
    ! grep -q 'require_clean_status' "$cfg"
    ! grep -q 'enforce_dependencies' "$cfg"
    ! grep -q 'require_expected_branch' "$cfg"
    ! grep -q 'allow_branch_operations' "$cfg"
}

@test "fleet config mapper exposes no validation short keys" {
    # The env->yaml short-key mapper must not resolve the removed knobs.
    # With no config file present these resolve to the supplied default,
    # proving there is no live .validation.* path behind them.
    [ "$(get_fleet_config_value require_clean SENTINEL)" = "SENTINEL" ]
    [ "$(get_fleet_config_value enforce_deps SENTINEL)" = "SENTINEL" ]
    [ "$(get_fleet_config_value strict SENTINEL)" = "SENTINEL" ]

    # And the source must not map any short key onto a .validation.* path.
    ! grep -qE '\.validation\.' "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-config.sh"
}
