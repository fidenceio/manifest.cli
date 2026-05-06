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

seed_committed_release() {
    local version="$1"
    local file="docs/RELEASE_v${version}.md"
    echo "# Release v${version}" > "$file"
    git add "$file" && git commit -q -m "seed v${version}"
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
# versions-mode retention
# -----------------------------------------------------------------------------

@test "retain='1 version': only current stays; older archives" {
    export MANIFEST_CLI_DOCS_RETAIN="1 version"
    seed_committed_release "46.0.0"
    seed_committed_release "46.5.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/RELEASE_v46.5.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.5.0.md" ]
}

@test "retain='3 versions': top 3 distinct stay (current included in sort)" {
    export MANIFEST_CLI_DOCS_RETAIN="3 versions"
    seed_committed_release "46.10.0"
    seed_committed_release "46.11.0"
    seed_committed_release "46.12.0"
    seed_committed_release "46.13.0"

    run main_cleanup "46.14.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    # Top 3 of {46.14.0, 46.13.0, 46.12.0, 46.11.0, 46.10.0} = 14, 13, 12.
    [ -f "docs/RELEASE_v46.13.0.md" ]
    [ -f "docs/RELEASE_v46.12.0.md" ]
    [ ! -f "docs/RELEASE_v46.11.0.md" ]
    [ ! -f "docs/RELEASE_v46.10.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.11.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.10.0.md" ]
}

@test "retain='10 versions' (default): nothing archives when fewer than 10 candidates" {
    # set_default_configuration set MANIFEST_CLI_DOCS_RETAIN="10 versions" already.
    seed_committed_release "46.10.0"
    seed_committed_release "46.11.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/RELEASE_v46.10.0.md" ]
    [ -f "docs/RELEASE_v46.11.0.md" ]
}

# -----------------------------------------------------------------------------
# off mode
# -----------------------------------------------------------------------------

@test "retain='off': sweep skipped entirely" {
    export MANIFEST_CLI_DOCS_RETAIN="off"
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Archive sweep skipped (retain=off)"
    [ -f "docs/RELEASE_v46.0.0.md" ]
    [ ! -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
}

# -----------------------------------------------------------------------------
# days-mode retention (uses find -mtime)
# -----------------------------------------------------------------------------

@test "retain='10 days': old files archive, recent stay" {
    export MANIFEST_CLI_DOCS_RETAIN="10 days"
    seed_committed_release "46.0.0"
    seed_committed_release "46.5.0"
    # Set mtime: v46.0.0 to 30 days ago, v46.5.0 to today.
    touch -t 202604010000 docs/RELEASE_v46.0.0.md
    touch docs/RELEASE_v46.5.0.md

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ ! -f "docs/RELEASE_v46.0.0.md" ]
    [ -f "docs/zArchive/v46/RELEASE_v46.0.0.md" ]
    [ -f "docs/RELEASE_v46.5.0.md" ]
}

# -----------------------------------------------------------------------------
# malformed config
# -----------------------------------------------------------------------------

@test "main_cleanup errors out on a malformed retain spec" {
    export MANIFEST_CLI_DOCS_RETAIN="banana"
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Invalid docs.retain spec"
    [ -f "docs/RELEASE_v46.0.0.md" ]
}

# -----------------------------------------------------------------------------
# move log carries the retain spec
# -----------------------------------------------------------------------------

@test "move log records the retain spec used" {
    export MANIFEST_CLI_DOCS_RETAIN="1 version"
    seed_committed_release "46.0.0"

    run main_cleanup "46.13.0" "2026-05-05 23:00:00 UTC"
    [ "$status" -eq 0 ]
    [ -f "docs/zArchive/.archive-log.md" ]
    grep -q "Retain: 1 version" docs/zArchive/.archive-log.md
}
