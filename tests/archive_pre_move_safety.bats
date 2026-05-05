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
    echo "46.12.2" > VERSION
    git add VERSION && git commit -q -m "init repo"
    PROJECT_ROOT="$SCRATCH"
    export PROJECT_ROOT
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

seed_release_file() {
    local version="$1"
    local content="${2:-Initial}"
    local file="docs/RELEASE_v${version}.md"
    echo "# Release v${version}" > "$file"
    echo "$content" >> "$file"
}

@test "archive sweep moves clean (committed) files" {
    seed_release_file "46.0.0" "real content"
    git add docs/RELEASE_v46.0.0.md && git commit -q -m "seed"

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

@test "archive sweep aborts on uncommitted edit to a release file" {
    seed_release_file "46.0.0" "original"
    git add docs/RELEASE_v46.0.0.md && git commit -q -m "seed"
    echo "hand edit" >> docs/RELEASE_v46.0.0.md

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Refusing to archive RELEASE_v46.0.0.md"
    echo "$output" | grep -q "uncommitted changes"
    echo "$output" | grep -q "MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1"
    [ -f "docs/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

@test "archive sweep aborts on untracked release file" {
    seed_release_file "46.0.0"

    run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "Refusing to archive RELEASE_v46.0.0.md"
    [ -f "docs/RELEASE_v46.0.0.md" ]
}

@test "MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 bypasses dirty-file abort" {
    seed_release_file "46.0.0" "original"
    git add docs/RELEASE_v46.0.0.md && git commit -q -m "seed"
    echo "hand edit" >> docs/RELEASE_v46.0.0.md

    MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 run main_cleanup "46.12.2" "2026-05-05 22:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}
