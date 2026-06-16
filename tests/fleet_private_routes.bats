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
# Auto-discovery retirement. `_fleet_init` once had an auto-discovery branch
# driven by an internal flag (`--_quickstart`, later `--_autodiscover`) that
# `manifest first` (fleet) used to write the TSV in one pass. Since the
# first/fleet alignment, `manifest first` routes through manifest_init_fleet's
# two-phase rails and the auto-discovery branch + flag were removed. Confirm
# neither private flag survives in _fleet_init — Phase 2 is start-file only.
# -----------------------------------------------------------------------------

@test "_fleet_init: auto-discovery flag is fully retired (no --_autodiscover/--_quickstart)" {
    local body
    body="$(declare -f _fleet_init)"
    [[ "$body" != *"--_autodiscover"* ]]
    [[ "$body" != *"--_quickstart"* ]]
}
