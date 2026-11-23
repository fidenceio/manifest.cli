#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-discovery.sh" "core/manifest-version-surfaces.sh" "core/manifest-doctor.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

init_repo() {
    git -C "$SCRATCH" init -q
    git -C "$SCRATCH" config user.email t@e.com
    git -C "$SCRATCH" config user.name t
    echo "1.2.3" > "$SCRATCH/VERSION"
}

@test "doctor: warns on noncanonical version surfaces without failing" {
    init_repo
    printf '{"version":"0.1.0"}\n' > "$SCRATCH/package.json"

    cd "$SCRATCH"
    run manifest_doctor
    [ "$status" -eq 0 ]
    grep -q "Version surfaces" <<<"$output"
    grep -q "noncanonical detected" <<<"$output"
    grep -q "version.sync" <<<"$output"
}

@test "doctor: reports disabled version surface policy" {
    init_repo
    printf '{"version":"0.1.0"}\n' > "$SCRATCH/package.json"
    export MANIFEST_CLI_VERSION_SURFACES_ENABLED="false"

    cd "$SCRATCH"
    run manifest_doctor
    [ "$status" -eq 0 ]
    grep -q "Version surfaces.*disabled by policy" <<<"$output"
    refute grep -q "noncanonical detected" <<<"$output"
}

@test "doctor: warns on invalid version surface policy but stays read-only" {
    init_repo
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="$SCRATCH/missing.tsv"
    export MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH="invalid-depth"
    export MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE="chatty"

    cd "$SCRATCH"
    run manifest_doctor
    [ "$status" -eq 0 ]
    grep -q "catalog not found" <<<"$output"
    grep -q "scan_depth 'invalid-depth' is invalid" <<<"$output"
    grep -q "notification_mode 'chatty' is invalid" <<<"$output"
    [ "$(cat "$SCRATCH/VERSION")" = "1.2.3" ]
}
