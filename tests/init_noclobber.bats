#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Pins the shared no-clobber contract for Manifest scaffold writers:
#   missing real file  → create the real file (no .manifest extension)
#   real file exists   → write/refresh <name>.manifest with latest Manifest defaults
#   never touch the real file once it exists
# Sole documented exception: empty .gitignore may be filled once
# (ensure_gitignore_smart) — covered here.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- shared helper -------------------------------------------------------------

_writer_marker() {
    printf 'MARKER_CONTENT\n' > "$1"
}

@test "no-clobber helper: missing dest creates the real file (no .manifest)" {
    run write_scaffold_no_clobber "$PROJ/sample.txt" _writer_marker
    [ "$status" -eq 0 ]
    [ "$output" = "sample.txt" ]
    [ -f "$PROJ/sample.txt" ]
    [ ! -e "$PROJ/sample.txt.manifest" ]
    grep -qx 'MARKER_CONTENT' "$PROJ/sample.txt"
}

@test "no-clobber helper: existing dest writes .manifest sidecar only" {
    printf 'ORIGINAL\n' > "$PROJ/sample.txt"
    run write_scaffold_no_clobber "$PROJ/sample.txt" _writer_marker
    [ "$status" -eq 0 ]
    [ "$output" = "sample.txt.manifest" ]
    grep -qx 'ORIGINAL' "$PROJ/sample.txt"
    grep -qx 'MARKER_CONTENT' "$PROJ/sample.txt.manifest"
}

@test "no-clobber helper: existing dest + sidecar refreshes only the sidecar" {
    printf 'ORIGINAL\n' > "$PROJ/sample.txt"
    printf 'STALE_SIDECAR\n' > "$PROJ/sample.txt.manifest"
    run write_scaffold_no_clobber "$PROJ/sample.txt" _writer_marker
    [ "$status" -eq 0 ]
    [ "$output" = "sample.txt.manifest" ]
    grep -qx 'ORIGINAL' "$PROJ/sample.txt"
    grep -qx 'MARKER_CONTENT' "$PROJ/sample.txt.manifest"
    ! grep -q 'STALE_SIDECAR' "$PROJ/sample.txt.manifest"
}

# --- ensure_required_files identity pins --------------------------------------

@test "no-clobber: VERSION/README/CHANGELOG are never overwritten" {
    printf '9.9.9\n' > "$PROJ/VERSION"
    printf '# mine readme\n' > "$PROJ/README.md"
    printf '# mine changelog\n' > "$PROJ/CHANGELOG.md"
    mkdir -p "$PROJ/docs"

    run ensure_required_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -qx '9.9.9' "$PROJ/VERSION"
    grep -q 'mine readme' "$PROJ/README.md"
    grep -q 'mine changelog' "$PROJ/CHANGELOG.md"
    # These single-source files do not get .manifest sidecars.
    [ ! -e "$PROJ/VERSION.manifest" ]
    [ ! -e "$PROJ/README.md.manifest" ]
    [ ! -e "$PROJ/CHANGELOG.md.manifest" ]
}

@test "no-clobber: non-empty .gitignore is never overwritten (sidecar only)" {
    printf 'node_modules/\n' > "$PROJ/.gitignore"
    run ensure_gitignore_smart "$PROJ"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx '.gitignore.manifest'
    grep -qx 'node_modules/' "$PROJ/.gitignore"
    ! grep -q 'Manifest CLI' "$PROJ/.gitignore"
    [ -f "$PROJ/.gitignore.manifest" ]
    grep -q 'Manifest CLI' "$PROJ/.gitignore.manifest"
}

@test "no-clobber: existing .gitignore + sidecar refreshes only the sidecar" {
    printf 'node_modules/\n' > "$PROJ/.gitignore"
    printf 'STALE\n' > "$PROJ/.gitignore.manifest"
    run ensure_gitignore_smart "$PROJ"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx '.gitignore.manifest'
    grep -qx 'node_modules/' "$PROJ/.gitignore"
    ! grep -q 'STALE' "$PROJ/.gitignore.manifest"
    grep -q 'Manifest CLI' "$PROJ/.gitignore.manifest"
}

@test "no-clobber exception: empty .gitignore may be filled once" {
    printf '# comment only\n\n' > "$PROJ/.gitignore"
    run ensure_gitignore_smart "$PROJ"
    [ "$status" -eq 0 ]
    echo "$output" | grep -qx '.gitignore:empty-overwrite'
    grep -q 'Manifest CLI' "$PROJ/.gitignore"
    [ ! -e "$PROJ/.gitignore.manifest" ]
}

@test "no-clobber: dry-run --force never claims scaffold overwrite" {
    printf '1.0.0\n' > "$PROJ/VERSION"
    printf '# r\n' > "$PROJ/README.md"
    printf '# c\n' > "$PROJ/CHANGELOG.md"
    printf 'x\n' > "$PROJ/.gitignore"
    mkdir -p "$PROJ/docs" "$PROJ/scripts"
    printf '#!/bin/sh\n' > "$PROJ/scripts/run-tests.sh"
    printf 'mine\n' > "$PROJ/.env.example"
    printf 'User-agent: *\nDisallow: /\n' > "$PROJ/robots.txt"
    printf 'Allow: none\n' > "$PROJ/ai.txt"
    touch "$PROJ/manifest.config.local.yaml"

    cd "$PROJ"
    export MANIFEST_CLI_PROJECT_ROOT="$PROJ"
    run manifest_init_repo --dry-run --force
    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q 'would overwrite: VERSION'
    ! echo "$output" | grep -q 'would overwrite: README.md'
    ! echo "$output" | grep -q 'would overwrite: CHANGELOG.md'
    ! echo "$output" | grep -q 'would overwrite: .gitignore'
    ! echo "$output" | grep -q 'would overwrite: robots.txt'
    echo "$output" | grep -q 'would recreate:  manifest.config.local.yaml'
}
