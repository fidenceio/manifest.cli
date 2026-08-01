#!/usr/bin/env bats

# Fleet private helpers + migration hints for retired dispatcher verbs.
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

@test "fleet_main start: emits migration hint pointing at 'manifest init fleet'" {
    run fleet_main start
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest init fleet"* ]]
}

@test "fleet_main init: emits migration hint pointing at 'manifest init fleet'" {
    run fleet_main init
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest init fleet"* ]]
}

@test "fleet_main sync: emits migration hint pointing at 'manifest prep fleet'" {
    run fleet_main sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest prep fleet"* ]]
}

@test "fleet_main discover: emits replacement pointing at 'manifest discover fleet'" {
    run fleet_main discover
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest discover fleet"* ]]
}

@test "fleet_main update: emits replacement pointing at 'manifest update fleet'" {
    run fleet_main update
    [ "$status" -ne 0 ]
    [[ "$output" == *"no longer a dispatcher route"* ]]
    [[ "$output" == *"manifest update fleet"* ]]
}

@test "fleet_main help: documents action-first routes only" {
    run fleet_main help
    [ "$status" -eq 0 ]
    [[ "$output" == *"action-first commands"* ]]
    [[ "$output" == *"manifest status"* ]]
    [[ "$output" == *"manifest update fleet"* ]]
    [[ "$output" == *"manifest docs fleet"* ]]
}
