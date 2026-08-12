#!/usr/bin/env bats

# Coverage for the inherited FLEET config layer on the `manifest config` read
# surface. load_configuration has always inherited <fleet-root>/manifest.config
# {,.local}.yaml into every member, but the CRUD commands only knew about
# local/project/global — so an inherited value was reported as coming "(from
# defaults)" by describe and was omitted from list entirely.
#
# The fleet layer is READ-ONLY here: its files live in a different repository,
# so set/unset must refuse rather than silently write across the boundary.
#
# Lives in its own file because config_crud.bats deliberately runs with no fleet
# sentinel anywhere above its scratch dir, and that must stay true.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    # HOME must be isolated before sourcing: manifest-config.sh resolves
    # MANIFEST_CLI_GLOBAL_CONFIG from $HOME at source time.
    unset MANIFEST_CLI_GITHUB_OWNER
    load_modules "core/manifest-config.sh" "core/manifest-config-crud.sh"
    # The suite-wide hermetic gate export is captured as a process-start
    # override; drop it so merged listings carry only what these fixtures set.
    clear_release_gate_env_override
    MEMBER="$SCRATCH/services/member"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_PROJECT_ROOT MANIFEST_CLI_FLEET_ROOT MANIFEST_CLI_GITHUB_OWNER
}

# A fleet root whose org identity lives in the fleet-root LOCAL config, with a
# nested member underneath — the layout load_configuration inherits from.
setup_fleet() {
    printf 'fleet:\n  name: "demo"\n' > "$SCRATCH/manifest.fleet.config.yaml"
    printf 'github:\n  owner: "fidenceio"\n' > "$SCRATCH/manifest.config.local.yaml"
    mkdir -p "$MEMBER"
    export MANIFEST_CLI_PROJECT_ROOT="$MEMBER"
}

# -----------------------------------------------------------------------------
# reading an inherited value
# -----------------------------------------------------------------------------

@test "config get: an inherited-only fleet key resolves to the fleet value" {
    setup_fleet
    run manifest_config_get github.owner
    [ "$status" -eq 0 ]
    [ "$output" = "fidenceio" ]
}

@test "config describe: an inherited value is attributed to the fleet, not to defaults" {
    setup_fleet
    run manifest_config_describe github.owner
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Effective: fidenceio"
    echo "$output" | grep -q "(from fleet)"
    # The regression this whole change exists to remove.
    ! echo "$output" | grep -q "(from defaults)"
    echo "$output" | grep -q "Layers (highest precedence first):"
    echo "$output" | grep -q "fleet    fidenceio"
    # The member's own layers are still reported, and still empty.
    echo "$output" | grep -q "local    ·"
    echo "$output" | grep -q "project  ·"
}

@test "config describe: names the fleet file that supplied the value" {
    setup_fleet
    printf 'github:\n  owner: "shared-org"\n' > "$SCRATCH/manifest.config.yaml"
    run manifest_config_describe github.owner
    [ "$status" -eq 0 ]
    # The fleet root's local file shadows its shared file, matching the order
    # load_configuration loads them in.
    echo "$output" | grep -q "Effective: fidenceio"
    echo "$output" | grep -qE "fleet +fidenceio +\(.*manifest\.config\.local\.yaml\)"
    echo "$output" | grep -qE "fleet +shared-org +\(.*/manifest\.config\.yaml\)"
}

@test "config describe: reports the fleet root it is inheriting from" {
    setup_fleet
    run manifest_config_describe github.owner
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "^Fleet:     "
}

@test "config list: an inherited-only key is listed, not silently omitted" {
    setup_fleet
    run manifest_config_list
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^ +github\.owner +fleet +fidenceio'
}

@test "config list --json: an inherited-only key carries layer=fleet and its file" {
    setup_fleet
    run manifest_config_list --json
    [ "$status" -eq 0 ]
    echo "$output" | grep -q '"key":"github.owner"'
    echo "$output" | grep -q '"layer":"fleet"'
    echo "$output" | grep -q '"value":"fidenceio"'
    echo "$output" | grep -q '"file":"'
    [ "$(echo "$output" | wc -l | tr -d ' ')" = "1" ]
    echo "$output" | yq e '.' - >/dev/null
}

@test "config list --layer fleet: lists keys set at the fleet root" {
    setup_fleet
    run manifest_config_list --layer fleet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "github.owner"
    echo "$output" | grep -q "fidenceio"
}

@test "config list --layer fleet --json: empty array when not inside a fleet" {
    mkdir -p "$SCRATCH/standalone"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/standalone"
    run manifest_config_list --layer fleet --json
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "config list --layer fleet: human form explains the layer does not apply" {
    mkdir -p "$SCRATCH/standalone"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/standalone"
    run manifest_config_list --layer fleet
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "not inside a fleet"
}

@test "config list --layer bogus: unknown layers are still rejected" {
    setup_fleet
    run manifest_config_list --layer bogus
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown layer: bogus"
}

# -----------------------------------------------------------------------------
# precedence
# -----------------------------------------------------------------------------

@test "a member's own key overrides the inherited fleet value, which stays visible" {
    setup_fleet
    printf 'github:\n  owner: "member-org"\n' > "$MEMBER/manifest.config.yaml"

    run manifest_config_get github.owner
    [ "$status" -eq 0 ]
    [ "$output" = "member-org" ]

    run manifest_config_describe github.owner
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "(from project)"
    echo "$output" | grep -q "project  member-org"
    # The shadowed fleet value is still inspectable — that is the point of describe.
    echo "$output" | grep -q "fleet    fidenceio"
}

@test "the fleet root itself does not double-count its own config as an inherited layer" {
    setup_fleet
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"

    run manifest_config_describe github.owner
    [ "$status" -eq 0 ]
    # At the fleet root those files ARE the project/local layers.
    echo "$output" | grep -q "(from local)"
    ! echo "$output" | grep -qE '^  fleet '
    ! echo "$output" | grep -q "^Fleet:     "

    run manifest_config_list
    [ "$status" -eq 0 ]
    echo "$output" | grep -qE '^ +github\.owner +local +fidenceio'
}

@test "a repo not inside any fleet behaves exactly as before" {
    mkdir -p "$SCRATCH/standalone"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/standalone"
    printf 'git:\n  default_branch: "trunk"\n' > "$SCRATCH/standalone/manifest.config.local.yaml"

    run manifest_config_describe git.default_branch
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "(from local)"
    echo "$output" | grep -q "local    trunk"
    echo "$output" | grep -q "project  ·"
    echo "$output" | grep -q "global   ·"
    ! echo "$output" | grep -qE '^  fleet '
}

@test "the config fleet layer follows the loader's sentinel walk, not MANIFEST_CLI_FLEET_ROOT" {
    setup_fleet
    mkdir -p "$SCRATCH/decoy"
    printf 'github:\n  owner: "decoy-org"\n' > "$SCRATCH/decoy/manifest.config.yaml"
    export MANIFEST_CLI_FLEET_ROOT="$SCRATCH/decoy"

    # load_configuration ignores MANIFEST_CLI_FLEET_ROOT when resolving the
    # inherited layer; the config surface must agree with it or it would report
    # a layer the runtime never loads.
    run manifest_config_get github.owner
    [ "$status" -eq 0 ]
    [ "$output" = "fidenceio" ]
}

# -----------------------------------------------------------------------------
# the fleet layer is read-only
# -----------------------------------------------------------------------------

@test "config set --layer fleet is rejected and writes nothing" {
    setup_fleet
    run manifest_config_set --layer fleet github.owner other -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "read-only"
    echo "$output" | grep -q "different repository"
    # The fleet root is untouched and no member file was created.
    [ "$(yq e '.github.owner' "$SCRATCH/manifest.config.local.yaml")" = "fidenceio" ]
    [ ! -f "$SCRATCH/manifest.config.yaml" ]
    [ ! -f "$MEMBER/manifest.config.yaml" ]
    [ ! -f "$MEMBER/manifest.config.local.yaml" ]
}

@test "config set --layer fleet is rejected in preview mode, before any preview output" {
    setup_fleet
    run manifest_config_set --layer fleet github.owner other
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "read-only"
    # The guard must sit above the preview branch, or the operator is told the
    # write is merely pending rather than impossible.
    ! echo "$output" | grep -q "Would set"
}

@test "config unset --layer fleet is rejected, not treated as a missing-file no-op" {
    setup_fleet
    run manifest_config_unset --layer fleet github.owner -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "read-only"
    ! echo "$output" | grep -q "nothing to unset"
    [ "$(yq e '.github.owner' "$SCRATCH/manifest.config.local.yaml")" = "fidenceio" ]
}

@test "config set --layer fleet outside a fleet is still a read-only error, not 'unknown layer'" {
    mkdir -p "$SCRATCH/standalone"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/standalone"
    run manifest_config_set --layer fleet git.default_branch trunk -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "read-only"
    ! echo "$output" | grep -q "Unknown layer"
}

@test "config set --layer bogus still reports an unknown layer" {
    setup_fleet
    run manifest_config_set --layer bogus git.default_branch trunk -y
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Unknown layer: bogus"
}
