#!/usr/bin/env bats

# Tests for #9: collapse dual fleet paths.
#
# After v44.9.0 the legacy 'manifest fleet start|init|sync' subcommands no
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
# fleet_main: removed verbs return non-zero with a migration hint.
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

# -----------------------------------------------------------------------------
# fleet_main: surviving routes still respond. The simplest non-side-effecting
# probe is the help text — fleet_help is still wired and includes the v42
# pointers.
# -----------------------------------------------------------------------------

@test "fleet_main help: surviving routes documented; legacy start/init/sync no longer in COMMANDS section" {
    run fleet_main help
    [ "$status" -eq 0 ]
    [[ "$output" == *"v42 entry points"* ]]
    [[ "$output" == *"manifest fleet quickstart"* ]]
    [[ "$output" == *"manifest fleet status"* ]]
    [[ "$output" == *"manifest fleet update"* ]]
    # Legacy aliases must NOT appear as command entries — but a few may still
    # be referenced as migration pointers (e.g. inside the v42 mapping list).
    # The COMMANDS section header is "LEGACY-ONLY COMMANDS"; any 'manifest
    # fleet start|init|sync' line there would be a regression.
    [[ "$output" != *"manifest fleet start ["* ]]
    [[ "$output" != *"manifest fleet init ["* ]]
    [[ "$output" != *"manifest fleet sync ["* ]]
}

# -----------------------------------------------------------------------------
# Quickstart still calls _fleet_init internally (renamed callsite).
# We don't fully exercise quickstart here — just confirm the function body
# references the new private name, not the old public one.
# -----------------------------------------------------------------------------

@test "fleet_quickstart: body invokes _fleet_init (not legacy fleet_init)" {
    local body
    body="$(declare -f fleet_quickstart)"
    [[ "$body" == *"_fleet_init"* ]]
    # No bare-word 'fleet_init' that isn't preceded by an underscore.
    ! grep -Eq '(^|[^_])fleet_init\b' <<< "$body"
}
