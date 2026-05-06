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
    echo "46.13.0" > VERSION
    git add VERSION && git commit -q -m "init repo"
    PROJECT_ROOT="$SCRATCH"
    export PROJECT_ROOT
    # Force per-test retention to "1 version" so seeded files predictably archive.
    export MANIFEST_CLI_DOCS_RETAIN="1 version"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

seed_committed_release() {
    local version="$1"
    local file="docs/RELEASE_v${version}.md"
    echo "# Release v${version}" > "$file"
    git add "$file" && git commit -q -m "seed v${version}"
}

@test "first sweep with moves creates the archive log" {
    seed_committed_release "46.0.0"

    [ ! -f "docs/zArchive/.archive-log.md" ]
    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/.archive-log.md" ]

    grep -q "Manifest CLI Archive Move Log" docs/zArchive/.archive-log.md
    grep -q "## 2026-05-05 — v46.13.0 sweep" docs/zArchive/.archive-log.md
    grep -q "Timestamp: 2026-05-05 23:00:00 UTC" docs/zArchive/.archive-log.md
    grep -q "Moved 1 file:" docs/zArchive/.archive-log.md
    grep -q "docs/RELEASE_v46.0.0.md → docs/zArchive/v46/RELEASE_v46.0.0.md" docs/zArchive/.archive-log.md
}

@test "subsequent sweep appends without losing prior entries" {
    seed_committed_release "46.0.0"
    main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC" >/dev/null
    [ -f "docs/zArchive/.archive-log.md" ]
    local before_lines
    before_lines=$(wc -l < docs/zArchive/.archive-log.md)

    seed_committed_release "46.1.0"
    run main_cleanup "46.14.0" "2026-05-06 00:00:00 UTC"
    [ "$status" -eq 0 ]

    # Both sections still present, second appended below first.
    grep -q "v46.13.0 sweep" docs/zArchive/.archive-log.md
    grep -q "v46.14.0 sweep" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v46.0.0.md" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v46.1.0.md" docs/zArchive/.archive-log.md

    local after_lines
    after_lines=$(wc -l < docs/zArchive/.archive-log.md)
    [ "$after_lines" -gt "$before_lines" ]

    # Newest section ordering: v46.14.0 must appear after v46.13.0.
    local first_pos second_pos
    first_pos=$(grep -n "v46.13.0 sweep" docs/zArchive/.archive-log.md | cut -d: -f1)
    second_pos=$(grep -n "v46.14.0 sweep" docs/zArchive/.archive-log.md | cut -d: -f1)
    [ "$second_pos" -gt "$first_pos" ]
}

@test "no log written when no files move" {
    # No release files staged at all; the sweep finds nothing matching.
    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/zArchive/.archive-log.md" ]
}

@test "multi-file sweep records each src→dest pair" {
    seed_committed_release "46.0.0"
    seed_committed_release "46.1.0"
    seed_committed_release "46.2.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    grep -q "Moved 3 files:" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v46.0.0.md →" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v46.1.0.md →" docs/zArchive/.archive-log.md
    grep -q "RELEASE_v46.2.0.md →" docs/zArchive/.archive-log.md
}
