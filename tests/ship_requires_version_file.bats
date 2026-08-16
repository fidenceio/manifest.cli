#!/usr/bin/env bats

# Coverage for manifest_ship_require_version_file.
#
# `ship repo` reads "$repo_root/VERSION" and every read falls back to the literal
# string "unknown" when the file is absent. Before this guard, running `ship repo`
# somewhere without a VERSION — most easily a fleet root, which is versioned by
# fleet.version_file (e.g. FLEET_VERSION), never VERSION — printed three raw
# "No such file or directory" errors and then proceeded:
#
#     Current version:  unknown
#     Next version:     unknown
#     Release tag:      unknown
#     - VERSION: update unknown -> unknown
#
# Answering -y would have cut a real release keyed on the string "unknown".
# A missing input must be a stop condition, not an empty value.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
    load_modules "core/manifest-ship.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- the stop condition ------------------------------------------------------

@test "version guard: refuses a repo with no VERSION file" {
    mkdir -p "$SCRATCH/plain"
    run manifest_ship_require_version_file "$SCRATCH/plain"
    [ "$status" -eq 1 ]
    [[ "$output" == *"no VERSION file"* ]]
}

@test "version guard: refuses an empty VERSION rather than releasing an empty string" {
    mkdir -p "$SCRATCH/empty"
    printf '   \n' > "$SCRATCH/empty/VERSION"
    run manifest_ship_require_version_file "$SCRATCH/empty"
    [ "$status" -eq 1 ]
    [[ "$output" == *"is empty"* ]]
}

@test "version guard: passes a valid VERSION silently" {
    mkdir -p "$SCRATCH/ok"
    echo "1.2.3" > "$SCRATCH/ok/VERSION"
    run manifest_ship_require_version_file "$SCRATCH/ok"
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# --- the fleet-root case, which is how this is actually hit ------------------

@test "version guard: at a fleet root, refuses and names ship fleet" {
    mkdir -p "$SCRATCH/fleetroot"
    printf 'fleet:\n  versioning: "date"\n  version_file: "FLEET_VERSION"\n' \
        > "$SCRATCH/fleetroot/manifest.fleet.config.yaml"

    run manifest_ship_require_version_file "$SCRATCH/fleetroot"
    [ "$status" -eq 1 ]
    [[ "$output" == *"fleet root"* ]]
    # Must name the command that can act, not just complain.
    [[ "$output" == *"manifest ship fleet"* ]]
}

@test "version guard: reports the fleet's DECLARED version file, not a hardcoded name" {
    mkdir -p "$SCRATCH/custom"
    printf 'fleet:\n  versioning: "semver"\n  version_file: "RELEASE_STAMP"\n' \
        > "$SCRATCH/custom/manifest.fleet.config.yaml"

    run manifest_ship_require_version_file "$SCRATCH/custom"
    [ "$status" -eq 1 ]
    [[ "$output" == *"RELEASE_STAMP"* ]]
    [[ "$output" == *"semver"* ]]
}

@test "version guard: a fleet root WITH a VERSION file is still shippable as a repo" {
    # Being a fleet root is not itself disqualifying — having no version is.
    mkdir -p "$SCRATCH/both"
    printf 'fleet:\n  versioning: "date"\n  version_file: "FLEET_VERSION"\n' \
        > "$SCRATCH/both/manifest.fleet.config.yaml"
    echo "2.0.0" > "$SCRATCH/both/VERSION"

    run manifest_ship_require_version_file "$SCRATCH/both"
    [ "$status" -eq 0 ]
}

# --- no "unknown" may escape -------------------------------------------------

@test "version guard: never emits the literal 'unknown' as a version" {
    mkdir -p "$SCRATCH/plain2"
    run manifest_ship_require_version_file "$SCRATCH/plain2"
    [ "$status" -eq 1 ]
    refute grep -qi "current version:  *unknown" <<< "$output"
    refute grep -qi "update unknown" <<< "$output"
}

# --- the leaked shell error --------------------------------------------------

@test "version reads: a missing VERSION leaks no raw 'No such file' to the caller" {
    # 2>/dev/null on the bare command silences tr's stderr, NOT the shell's
    # redirection failure. The reads must brace-group the redirection.
    refute grep -qE 'tr -d .\[:space:\]. < "\$_?repo_root/VERSION" 2>/dev/null' \
        "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
    grep -qE '\{ tr -d .\[:space:\]. < "\$_?repo_root/VERSION"; \} 2>/dev/null' \
        "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
}

# --- wiring ------------------------------------------------------------------

@test "ship repo calls the guard before building a plan" {
    # If the guard is dropped or moved after the version read, the "unknown"
    # cascade returns. Pin that ship repo invokes it.
    grep -qF 'manifest_ship_require_version_file "$MANIFEST_CLI_PROJECT_ROOT"' \
        "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"
}
