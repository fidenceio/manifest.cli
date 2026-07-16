#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Coverage for manifest_ship_dispatch — scope routing, the legacy bare
# bump-word route, help, and both error branches — plus the manifest_ship_repo
# bump types not exercised elsewhere (major, revision, their short flags, and
# the unknown/missing release-type errors). All ship calls here are previews:
# nothing is written, no gate runs.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Minimal previewable repo: VERSION + git identity + origin.
_mk_ship_fixture() {
    cd "$SCRATCH"
    git init -q
    git remote add origin git@github.com:example/project.git
    echo "1.2.3" > VERSION
}

# --- dispatch: error + help branches -----------------------------------------

@test "ship dispatch: empty scope errors with usage" {
    run manifest_ship_dispatch
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "ship requires a scope"
    echo "$output" | grep -q "manifest ship <repo|fleet>"
}

@test "ship dispatch: unknown scope errors and names the scope" {
    run manifest_ship_dispatch bogus patch
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Unknown scope: bogus"
}

@test "ship dispatch: -h renders help and exits 0" {
    run manifest_ship_dispatch -h
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest ship <repo|fleet> <patch|minor|major|revision>"
    echo "$output" | grep -q "Highest consequence command"
}

@test "ship dispatch: legacy bare bump word routes to ship repo with args intact" {
    manifest_ship_repo() { echo "ROUTED:$*"; }
    run manifest_ship_dispatch patch --dry-run
    [ "$status" -eq 0 ]
    [ "$output" = "ROUTED:patch --dry-run" ]
}

# --- ship repo: bump types beyond patch/minor --------------------------------

@test "ship repo preview: major computes 1.2.3 -> 2.0.0" {
    _mk_ship_fixture
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_ship_repo major
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Release type:     major"
    echo "$output" | grep -q "Next version:     2.0.0"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}

@test "ship repo preview: revision computes 1.2.3 -> 1.2.3.1" {
    _mk_ship_fixture
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_ship_repo revision
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Release type:     revision"
    echo "$output" | grep -q "Next version:     1.2.3.1"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}

@test "ship repo preview: -M and -r short flags resolve to major and revision" {
    _mk_ship_fixture
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_ship_repo -M
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Release type:     major"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_ship_repo -r
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Release type:     revision"
}

@test "ship repo: unknown release type errors with usage" {
    _mk_ship_fixture
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_ship_repo enormous
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Unknown option: enormous"
    echo "$output" | grep -q "manifest ship repo <patch|minor|major|revision>"
}

@test "ship repo: missing release type errors with usage" {
    _mk_ship_fixture
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_ship_repo
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "ship repo requires a release type"
}
