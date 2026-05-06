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
    unset MANIFEST_CLI_DOCS_RETAIN
}

# Seed an archived RELEASE+CHANGELOG pair under zArchive/v<major>/, committed.
seed_archived_pair() {
    local version="$1"
    local major="${version%%.*}"
    local dir="docs/zArchive/v${major}"
    mkdir -p "$dir"
    echo "# Release v${version}" > "${dir}/RELEASE_v${version}.md"
    echo "# Changelog v${version}" > "${dir}/CHANGELOG_v${version}.md"
    git add "${dir}" && git commit -q -m "seed archive v${version}"
}

# -----------------------------------------------------------------------------
# parse helper (white-box)
# -----------------------------------------------------------------------------

@test "parse retention: '10 versions' → versions / 10" {
    local k v
    _manifest_parse_retention "10 versions" k v
    [ "$k" = "versions" ]
    [ "$v" = "10" ]
}

@test "parse retention: '30 days' → days / 30" {
    local k v
    _manifest_parse_retention "30 days" k v
    [ "$k" = "days" ]
    [ "$v" = "30" ]
}

@test "parse retention: 'off' / empty → off" {
    local k v
    _manifest_parse_retention "off" k v
    [ "$k" = "off" ]
    _manifest_parse_retention "" k v
    [ "$k" = "off" ]
}

@test "parse retention: malformed input returns 1" {
    local k v
    run _manifest_parse_retention "ten versions" k v
    [ "$status" -ne 0 ]
    run _manifest_parse_retention "5 weeks" k v
    [ "$status" -ne 0 ]
}

# -----------------------------------------------------------------------------
# Phase A: active-docs sweep is unconditional
# -----------------------------------------------------------------------------

@test "active sweep moves previous version's docs regardless of retain setting" {
    export MANIFEST_CLI_DOCS_RETAIN="off"   # retention off, but Phase A still runs
    echo "v46.10.0 release" > docs/RELEASE_v46.10.0.md
    git add docs/RELEASE_v46.10.0.md && git commit -q -m "seed active v46.10.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.10.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.10.0.md" ]
}

# -----------------------------------------------------------------------------
# Phase B: versions-mode prune
# -----------------------------------------------------------------------------

@test "retain='3 versions': keeps top 3 archived versions; older are pruned" {
    export MANIFEST_CLI_DOCS_RETAIN="3 versions"
    seed_archived_pair "46.10.0"
    seed_archived_pair "46.11.0"
    seed_archived_pair "46.12.0"
    seed_archived_pair "46.13.0"
    seed_archived_pair "46.14.0"

    run main_cleanup "46.15.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    # Top 3 of {14, 13, 12, 11, 10} = 14, 13, 12.
    [ -f "docs/zArchive/v46/RELEASE_v46.14.0.md" ]
    [ -f "docs/zArchive/v46/CHANGELOG_v46.14.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.13.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.12.0.md" ]
    [ ! -f "docs/zArchive/v46/RELEASE_v46.11.0.md" ]
    [ ! -f "docs/zArchive/v46/CHANGELOG_v46.11.0.md" ]
    [ ! -f "docs/zArchive/v46/RELEASE_v46.10.0.md" ]
}

@test "retain='10 versions' (default): nothing pruned when archive has fewer than 10" {
    seed_archived_pair "46.10.0"
    seed_archived_pair "46.11.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/v46/RELEASE_v46.10.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.11.0.md" ]
}

# -----------------------------------------------------------------------------
# Phase B: off mode
# -----------------------------------------------------------------------------

@test "retain='off': archive grows unbounded; nothing pruned" {
    export MANIFEST_CLI_DOCS_RETAIN="off"
    seed_archived_pair "20.0.0"
    seed_archived_pair "30.0.0"
    seed_archived_pair "40.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/v20/RELEASE_v20.0.0.md" ]
    [ -f "docs/zArchive/v30/RELEASE_v30.0.0.md" ]
    [ -f "docs/zArchive/v40/RELEASE_v40.0.0.md" ]
}

# -----------------------------------------------------------------------------
# Phase B: SECURITY_ANALYSIS_REPORT files are excluded from retention
# -----------------------------------------------------------------------------

@test "retain prunes RELEASE/CHANGELOG but never SECURITY_ANALYSIS_REPORT" {
    export MANIFEST_CLI_DOCS_RETAIN="1 version"
    seed_archived_pair "20.0.0"
    seed_archived_pair "46.13.0"
    mkdir -p docs/zArchive/v20
    echo "# Audit v20.0.0" > docs/zArchive/v20/SECURITY_ANALYSIS_REPORT_v20.0.0.md
    git add docs/zArchive/v20/SECURITY_ANALYSIS_REPORT_v20.0.0.md && git commit -q -m "seed audit"

    run main_cleanup "46.14.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    # v20 release docs pruned (not in top 1)…
    [ ! -f "docs/zArchive/v20/RELEASE_v20.0.0.md" ]
    [ ! -f "docs/zArchive/v20/CHANGELOG_v20.0.0.md" ]
    # …but the audit stays.
    [ -f "docs/zArchive/v20/SECURITY_ANALYSIS_REPORT_v20.0.0.md" ]
}

# -----------------------------------------------------------------------------
# Phase B: days-mode (uses find -mtime)
# -----------------------------------------------------------------------------

@test "retain='10 days': archived files older than N days are pruned" {
    export MANIFEST_CLI_DOCS_RETAIN="10 days"
    seed_archived_pair "46.0.0"
    seed_archived_pair "46.5.0"
    # Set mtime: v46.0.0 to 30 days ago; v46.5.0 to today.
    touch -t 202604010000 docs/zArchive/v46/RELEASE_v46.0.0.md
    touch -t 202604010000 docs/zArchive/v46/CHANGELOG_v46.0.0.md
    touch docs/zArchive/v46/RELEASE_v46.5.0.md
    touch docs/zArchive/v46/CHANGELOG_v46.5.0.md

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/zArchive/v46/CHANGELOG_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.5.0.md" ]
    [ -f "docs/zArchive/v46/CHANGELOG_v46.5.0.md" ]
}

# -----------------------------------------------------------------------------
# Phase B: pre-delete safety check honors uncommitted edits
# -----------------------------------------------------------------------------

@test "prune refuses to delete an archived file with uncommitted edits" {
    export MANIFEST_CLI_DOCS_RETAIN="1 version"
    seed_archived_pair "20.0.0"
    seed_archived_pair "46.13.0"
    # Hand-edit the v20 file (security retraction simulation).
    echo "RETRACTED" >> docs/zArchive/v20/RELEASE_v20.0.0.md

    run main_cleanup "46.14.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Refusing to prune"
    echo "$output" | grep -q "uncommitted changes"
    # File still present.
    [ -f "docs/zArchive/v20/RELEASE_v20.0.0.md" ]
}

# -----------------------------------------------------------------------------
# Malformed config
# -----------------------------------------------------------------------------

@test "main_cleanup errors out on a malformed retain spec" {
    export MANIFEST_CLI_DOCS_RETAIN="banana"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Invalid docs.retain spec"
}

# -----------------------------------------------------------------------------
# Move log captures both moves and prunes
# -----------------------------------------------------------------------------

@test "move log records moves and prunes in one entry" {
    export MANIFEST_CLI_DOCS_RETAIN="1 version"
    seed_archived_pair "20.0.0"          # 2 files, will be pruned (Phase B)
    echo "v46.13.4" > docs/RELEASE_v46.13.4.md
    git add docs/RELEASE_v46.13.4.md && git commit -q -m "seed active v46.13.4"

    run main_cleanup "46.14.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/.archive-log.md" ]
    grep -q "Retain: 1 version" docs/zArchive/.archive-log.md
    grep -q "Moved 1 file:" docs/zArchive/.archive-log.md
    grep -q "Pruned 2 files (over retention cap):" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v46.13.4.md" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v20.0.0.md" docs/zArchive/.archive-log.md
}
