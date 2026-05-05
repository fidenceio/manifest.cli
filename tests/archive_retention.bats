#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-cleanup-docs.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    mkdir -p docs/zArchive
    PROJECT_ROOT="$SCRATCH"
    export PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT
}

seed_committed_release() {
    local version="$1"
    local file="docs/RELEASE_v${version}.md"
    echo "# Release v${version}" > "$file"
    git add "$file" && git commit -q -m "seed v${version}"
}

# -----------------------------------------------------------------------------
# Trigger gating
# -----------------------------------------------------------------------------

@test "trigger=every_ship: sweep runs on patch bump" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.2" "2026-05-05 23:00:00 UTC" "patch"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

@test "trigger=minor_or_major: sweep skips on patch bump" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=minor_or_major
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.2" "2026-05-05 23:00:00 UTC" "patch"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Archive sweep skipped"
    # File stays put.
    [ -f "docs/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

@test "trigger=minor_or_major: sweep runs on minor bump" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=minor_or_major
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

@test "trigger=major_only: skips on minor, runs on major" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=major_only
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "45.6.0"

    run main_cleanup "46.0.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v45.6.0.md" ]

    run main_cleanup "47.0.0" "2026-05-05 23:00:00 UTC" "major"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v45.6.0.md" ]
    [ -f "docs/zArchive/v45/RELEASE_v45.6.0.md" ]
}

@test "trigger=manual: skips when called with bump_type" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=manual
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.0.0.md" ]
}

@test "trigger=manual: runs when invoked without bump_type" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=manual
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

# -----------------------------------------------------------------------------
# Retention math (minor granularity)
# -----------------------------------------------------------------------------

@test "keep_recent=0 (minor bump): only current minor stays" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "46.11.0"
    seed_committed_release "46.12.0"
    seed_committed_release "46.13.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.13.0.md" ]
    [ ! -f "docs/RELEASE_v46.12.0.md" ]
    [ ! -f "docs/RELEASE_v46.11.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.12.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.11.0.md" ]
}

@test "keep_recent=1 (minor bump): current + previous minor stay" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=1
    seed_committed_release "46.11.0"
    seed_committed_release "46.12.0"
    seed_committed_release "46.13.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.13.0.md" ]
    [ -f "docs/RELEASE_v46.12.0.md" ]
    [ ! -f "docs/RELEASE_v46.11.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.11.0.md" ]
}

@test "keep_recent=2 (minor bump): current + 2 previous minors stay" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=2
    seed_committed_release "46.10.0"
    seed_committed_release "46.11.0"
    seed_committed_release "46.12.0"
    seed_committed_release "46.13.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.13.0.md" ]
    [ -f "docs/RELEASE_v46.12.0.md" ]
    [ -f "docs/RELEASE_v46.11.0.md" ]
    [ ! -f "docs/RELEASE_v46.10.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.10.0.md" ]
}

@test "minor bump always archives a different-major file regardless of keep_recent" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=99
    seed_committed_release "45.6.0"
    seed_committed_release "46.13.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.13.0.md" ]
    [ ! -f "docs/RELEASE_v45.6.0.md" ]
    [ -f "docs/zArchive/v45/RELEASE_v45.6.0.md" ]
}

# -----------------------------------------------------------------------------
# Retention math (major granularity)
# -----------------------------------------------------------------------------

@test "keep_recent=0 (major bump): only current major stays" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "45.6.0"
    seed_committed_release "46.0.0"

    run main_cleanup "46.0.0" "2026-05-05 23:00:00 UTC" "major"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/RELEASE_v45.6.0.md" ]
    [ -f "docs/zArchive/v45/RELEASE_v45.6.0.md" ]
}

@test "keep_recent=1 (major bump): current + previous major stay" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=1
    seed_committed_release "44.10.1"
    seed_committed_release "45.6.0"
    seed_committed_release "46.0.0"

    run main_cleanup "46.0.0" "2026-05-05 23:00:00 UTC" "major"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/RELEASE_v45.6.0.md" ]
    [ ! -f "docs/RELEASE_v44.10.1.md" ]
    [ -f "docs/zArchive/v44/RELEASE_v44.10.1.md" ]
}

# -----------------------------------------------------------------------------
# Move log header carries trigger/bump/keep_recent
# -----------------------------------------------------------------------------

@test "move log records trigger, bump, and keep_recent" {
    MANIFEST_CLI_DOCS_ARCHIVE_TRIGGER=every_ship
    MANIFEST_CLI_DOCS_ARCHIVE_KEEP_RECENT=0
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" "minor"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/.archive-log.md" ]
    grep -q "Sweep: trigger=every_ship; bump=minor; keep_recent=0" docs/zArchive/.archive-log.md
}
