#!/usr/bin/env bats

# Tests for #9: collapse dual fleet paths.
#
# After v44.9.0 the legacy 'manifest fleet <verb>' subcommands no
# longer exist as dispatcher routes — the underlying functions are private
# (_fleet_start / _fleet_init / _fleet_sync) and reachable only via the v42
# entry points. fleet_main prints a one-line migration hint when the removed
# verbs are invoked.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
}

# -----------------------------------------------------------------------------
# Function visibility: legacy public names are gone, private names exist.
# -----------------------------------------------------------------------------

@test "fleet: legacy public fleet_start/fleet_init/fleet_sync are NOT defined" {
    ! declare -F fleet_start >/dev/null
    ! declare -F fleet_init  >/dev/null
    ! declare -F fleet_sync  >/dev/null
}

@test "fleet: private _fleet_start/_fleet_init/_fleet_sync ARE defined" {
    declare -F _fleet_start >/dev/null
    declare -F _fleet_init  >/dev/null
    declare -F _fleet_sync  >/dev/null
}

# -----------------------------------------------------------------------------
# fleet_main: removed verbs return non-zero with a replacement hint.
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# fleet_main: surviving routes still respond. The simplest non-side-effecting
# probe is the help text — fleet_help is still wired and includes the v42
# pointers.
# -----------------------------------------------------------------------------

@test "fleet_main help: documents action-first routes only" {
    run fleet_main help
    [ "$status" -eq 0 ]
    [[ "$output" == *"action-first commands"* ]]
    [[ "$output" != *"quickstart"* ]]
    [[ "$output" == *"manifest status"* ]]
    [[ "$output" == *"manifest update fleet"* ]]
    [[ "$output" == *"manifest docs fleet"* ]]
    [[ "$output" != *"manifest fleet start ["* ]]
    [[ "$output" != *"manifest fleet init ["* ]]
    [[ "$output" != *"manifest fleet sync ["* ]]
    [[ "$output" != *"manifest fleet update"* ]]
    [[ "$output" != *"manifest fleet discover"* ]]
}

# -----------------------------------------------------------------------------
# `manifest first` (fleet) drives auto-discovery via `_fleet_init --_autodiscover`
# — the private flag that replaced the retired `--_quickstart`. Confirm _fleet_init
# still recognizes the new name (and no longer the old one), so first's fleet
# engine keeps working after the quickstart removal.
# -----------------------------------------------------------------------------

@test "_fleet_init: parses the --_autodiscover private flag (first's fleet engine)" {
    local body
    body="$(declare -f _fleet_init)"
    [[ "$body" == *"--_autodiscover"* ]]
    [[ "$body" != *"--_quickstart"* ]]
}
