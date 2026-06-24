#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-documentation.sh" "docs/manifest-cleanup-docs.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    mkdir -p docs/zArchive
    echo "46.12.2" > VERSION
    git add VERSION && git commit -q -m "init repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Phase A only archives point-in-time audit artifacts now —
# SECURITY_ANALYSIS_REPORT_v* — since per-version RELEASE/CHANGELOG files
# are no longer generated. The safety check still applies to anything
# the sweep does pick up.
seed_audit_file() {
    local version="$1"
    local content="${2:-Initial}"
    local file="docs/SECURITY_ANALYSIS_REPORT_v${version}.md"
    echo "# Security audit v${version}" > "$file"
    echo "$content" >> "$file"
}

@test "archive sweep moves clean (committed) audit files" {
    seed_audit_file "46.0.0" "real content"
    git add docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md && git commit -q -m "seed"

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
    [ -f "docs/zArchive/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
}

@test "archive sweep aborts on uncommitted edit to a sweepable file" {
    seed_audit_file "46.0.0" "original"
    git add docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md && git commit -q -m "seed"
    echo "hand edit" >> docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Refusing to archive SECURITY_ANALYSIS_REPORT_v46.0.0.md"
    echo "$output" | grep -q "uncommitted changes"
    echo "$output" | grep -q "MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1"
    [ -f "docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
    [ ! -f "docs/zArchive/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
}

@test "archive sweep aborts on untracked sweepable file" {
    seed_audit_file "46.0.0"

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Refusing to archive SECURITY_ANALYSIS_REPORT_v46.0.0.md"
    [ -f "docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
}

@test "MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 bypasses dirty-file abort" {
    seed_audit_file "46.0.0" "original"
    git add docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md && git commit -q -m "seed"
    echo "hand edit" >> docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md

    MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
    [ -f "docs/zArchive/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
}

@test "non-sweepable filenames in active docs are left alone" {
    # RELEASE/CHANGELOG per-version files are no longer generated; if a
    # straggler exists, the sweep should NOT pick it up.
    echo "stray" > docs/RELEASE_v46.0.0.md
    git add docs/RELEASE_v46.0.0.md && git commit -q -m "seed stray"

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/zArchive/RELEASE_v46.0.0.md" ]
}
