#!/usr/bin/env bats

# Guards the 2026-05-26 decision (CLI TRACKER): the fleet config's
# `validation:` block must NOT advertise branch-enforcement knobs the CLI
# never reads. `require_expected_branch` and `allow_branch_operations` had
# zero consumers — no env→yaml mapper entry, no preflight/apply gate — so
# they were removed rather than left as decorative config that promises a
# guarantee the tool doesn't keep. This test fails if either knob is
# reintroduced into the generated default config.

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

@test "generated fleet config omits inert branch-enforcement knobs" {
    local cfg="$SCRATCH/manifest.fleet.config.yaml"
    _generate_full_manifest "$cfg" "testfleet"

    [ -f "$cfg" ]
    # The validation block survives and keeps the live knobs...
    grep -q '^  require_clean_status:' "$cfg"
    grep -q '^  enforce_dependencies:' "$cfg"
    # ...but the two inert branch knobs must be gone.
    ! grep -q 'require_expected_branch' "$cfg"
    ! grep -q 'allow_branch_operations' "$cfg"
}
