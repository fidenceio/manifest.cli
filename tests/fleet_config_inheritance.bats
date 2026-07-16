#!/usr/bin/env bats

# A repo nested inside a fleet inherits the fleet root's configuration as a
# baseline (e.g. github.owner) so a fleet-wide setting applies to every member
# without being copied per repo. Regression: github.owner lived only in the
# fleet-root manifest.config.local.yaml, a nested `manifest init repo` never
# loaded it, and `gh` fell back to the authenticated user.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    # Isolate the user global config so tests never read the developer's real
    # ~/.manifest-cli/manifest.config.global.yaml.
    HOME="$SCRATCH/home"; mkdir -p "$HOME"
    export HOME
    # The release process itself has already resolved and exported global
    # config. Clear the key under test before manifest-config.sh captures real
    # process-start overrides, then source it against the sandboxed HOME.
    unset MANIFEST_CLI_GITHUB_OWNER
    load_modules core/manifest-config.sh
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_GITHUB_OWNER
}

# Make $SCRATCH a fleet root whose org identity lives in the fleet-root LOCAL
# config (the exact reported layout), with a nested member dir underneath.
setup_fleet() {
    printf 'fleet:\n  name: "demo"\n' > "$SCRATCH/manifest.fleet.config.yaml"
    printf 'github:\n  owner: "fidenceio"\n' > "$SCRATCH/manifest.config.local.yaml"
    mkdir -p "$SCRATCH/services/member"
}

@test "nested repo inherits fleet-root github.owner during init (include_project_overrides=false)" {
    setup_fleet
    # "false" mirrors how `manifest init repo` loads config — it must still
    # inherit the fleet org even though it skips the repo's OWN local file.
    load_configuration "$SCRATCH/services/member" "false" >/dev/null 2>&1
    [ "$MANIFEST_CLI_GITHUB_OWNER" = "fidenceio" ]

    run _manifest_github_repo_target "$SCRATCH/services/member"
    [ "$status" -eq 0 ]
    [ "$output" = "fidenceio/member" ]
}

@test "a member's own github.owner overrides the inherited fleet owner" {
    setup_fleet
    printf 'github:\n  owner: "member-org"\n' > "$SCRATCH/services/member/manifest.config.yaml"

    load_configuration "$SCRATCH/services/member" "true" >/dev/null 2>&1
    [ "$MANIFEST_CLI_GITHUB_OWNER" = "member-org" ]
}

@test "a repo not inside any fleet inherits no owner (gh keeps its authed-user default)" {
    mkdir -p "$SCRATCH/standalone"

    load_configuration "$SCRATCH/standalone" "false" >/dev/null 2>&1
    [ -z "${MANIFEST_CLI_GITHUB_OWNER:-}" ]

    run _manifest_github_repo_target "$SCRATCH/standalone"
    [ "$status" -eq 0 ]
    [ "$output" = "standalone" ]
}

@test "the fleet root itself resolves its own owner (no redundant inheritance load)" {
    setup_fleet
    load_configuration "$SCRATCH" "true" >/dev/null 2>&1
    [ "$MANIFEST_CLI_GITHUB_OWNER" = "fidenceio" ]
    # The inheritance layer is skipped when project == fleet root; the value
    # comes from the project's own local config (Layer 3).
    run _manifest_github_repo_target "$SCRATCH"
    [ "$status" -eq 0 ]
    [ "$output" = "fidenceio/$(basename "$SCRATCH")" ]
}
