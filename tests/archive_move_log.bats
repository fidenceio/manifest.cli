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
    echo "46.13.0" > VERSION
    git add VERSION && git commit -q -m "init repo"
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    export MANIFEST_CLI_PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

seed_committed_audit() {
    local version="$1"
    local file="docs/SECURITY_ANALYSIS_REPORT_v${version}.md"
    echo "# Security audit v${version}" > "$file"
    git add "$file" && git commit -q -m "seed v${version}"
}

@test "first sweep with moves creates the archive log" {
    seed_committed_audit "46.0.0"

    [ ! -f "docs/zArchive/.archive-log.md" ]
    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/.archive-log.md" ]

    grep -q "Manifest CLI Archive Move Log" docs/zArchive/.archive-log.md
    grep -q "## 2026-05-05 — v46.13.0 sweep" docs/zArchive/.archive-log.md
    grep -q "Timestamp: 2026-05-05 23:00:00 UTC" docs/zArchive/.archive-log.md
    grep -q "Moved 1 file:" docs/zArchive/.archive-log.md
    grep -q "docs/SECURITY_ANALYSIS_REPORT_v46.0.0.md → docs/zArchive/SECURITY_ANALYSIS_REPORT_v46.0.0.md" docs/zArchive/.archive-log.md
}

@test "subsequent sweep appends without losing prior entries" {
    seed_committed_audit "46.0.0"
    main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" >/dev/null
    [ -f "docs/zArchive/.archive-log.md" ]
    local before_lines
    before_lines=$(wc -l < docs/zArchive/.archive-log.md)

    seed_committed_audit "46.1.0"
    run main_cleanup "46.14.0" "2026-05-06 00:00:00 UTC"
    [ "$status" -eq 0 ]

    grep -q "v46.13.0 sweep" docs/zArchive/.archive-log.md
    grep -q "v46.14.0 sweep" docs/zArchive/.archive-log.md
    grep -q "SECURITY_ANALYSIS_REPORT_v46.0.0.md" docs/zArchive/.archive-log.md
    grep -q "SECURITY_ANALYSIS_REPORT_v46.1.0.md" docs/zArchive/.archive-log.md

    local after_lines
    after_lines=$(wc -l < docs/zArchive/.archive-log.md)
    [ "$after_lines" -gt "$before_lines" ]

    local first_pos second_pos
    first_pos=$(grep -n "v46.13.0 sweep" docs/zArchive/.archive-log.md | cut -d: -f1)
    second_pos=$(grep -n "v46.14.0 sweep" docs/zArchive/.archive-log.md | cut -d: -f1)
    [ "$second_pos" -gt "$first_pos" ]
}

@test "no log written when no files move" {
    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/zArchive/.archive-log.md" ]
}

@test "multi-file sweep records each src→dest pair" {
    seed_committed_audit "46.0.0"
    seed_committed_audit "46.1.0"
    seed_committed_audit "46.2.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    grep -q "Moved 3 files:" docs/zArchive/.archive-log.md
    grep -q "SECURITY_ANALYSIS_REPORT_v46.0.0.md →" docs/zArchive/.archive-log.md
    grep -q "SECURITY_ANALYSIS_REPORT_v46.1.0.md →" docs/zArchive/.archive-log.md
    grep -q "SECURITY_ANALYSIS_REPORT_v46.2.0.md →" docs/zArchive/.archive-log.md
}

@test "sweep moves files flat and creates no archive-side INDEX.md" {
    # zArchive is read-only "memory": files enter by move only and the sweep
    # must never generate an index inside the archive (top-level or per-major).
    seed_committed_audit "46.0.0"
    seed_committed_audit "46.1.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]

    # Files landed flat — no per-major v<major>/ routing.
    [ -f "docs/zArchive/SECURITY_ANALYSIS_REPORT_v46.0.0.md" ]
    [ -f "docs/zArchive/SECURITY_ANALYSIS_REPORT_v46.1.0.md" ]

    # No generated index anywhere under the archive.
    [ ! -f "docs/zArchive/INDEX.md" ]
    [ -z "$(find docs/zArchive -name INDEX.md 2>/dev/null)" ]
    [ -z "$(find docs/zArchive -type d -name 'v*' 2>/dev/null)" ]
}
