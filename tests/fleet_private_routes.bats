#!/usr/bin/env bats

# Fleet setup helpers retained after removal of the legacy dispatcher.
# (Absence locks for deleted public names / auto-discovery flags were removed
# after the retirement landed; keep the live private API and hint UX.)

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
}

@test "fleet: private _fleet_start/_fleet_init/_fleet_sync ARE defined" {
    declare -F _fleet_start >/dev/null
    declare -F _fleet_init  >/dev/null
    declare -F _fleet_sync  >/dev/null
}
