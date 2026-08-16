#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Crawl-privacy scaffold (robots.txt + ai.txt): private/safe by default.
# Uses the shared no-clobber helper — real file when missing, .manifest
# sidecar when present, no-op when both exist.

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

@test "crawl privacy: creates robots.txt and ai.txt when missing" {
    run ensure_crawl_privacy_files "$PROJ"
    [ "$status" -eq 0 ]
    [ -f "$PROJ/robots.txt" ]
    [ -f "$PROJ/ai.txt" ]
    [ ! -e "$PROJ/robots.txt.manifest" ]
    [ ! -e "$PROJ/ai.txt.manifest" ]
    grep -q 'User-agent: \*' "$PROJ/robots.txt"
    grep -q 'Disallow: /' "$PROJ/robots.txt"
    grep -q 'GPTBot' "$PROJ/robots.txt"
    grep -q 'ClaudeBot' "$PROJ/robots.txt"
    grep -q 'Allow: none' "$PROJ/ai.txt"
    grep -q 'Train: no' "$PROJ/ai.txt"
}

@test "crawl privacy: an existing robots.txt is preserved with no sidecar" {
    printf 'User-agent: *\nAllow: /\n' > "$PROJ/robots.txt"
    run ensure_crawl_privacy_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -q 'Allow: /' "$PROJ/robots.txt"
    refute grep -q 'GPTBot' "$PROJ/robots.txt"
    [ ! -e "$PROJ/robots.txt.manifest" ]
    # The missing companion is still created.
    [ -f "$PROJ/ai.txt" ]
    [ ! -e "$PROJ/ai.txt.manifest" ]
}

@test "crawl privacy: an existing pair is left completely alone" {
    printf 'CUSTOM_ROBOTS\n' > "$PROJ/robots.txt"
    printf 'CUSTOM_AI\n' > "$PROJ/ai.txt"

    run ensure_crawl_privacy_files "$PROJ"
    [ "$status" -eq 0 ]
    grep -qx 'CUSTOM_ROBOTS' "$PROJ/robots.txt"
    grep -qx 'CUSTOM_AI' "$PROJ/ai.txt"
    [ ! -e "$PROJ/robots.txt.manifest" ]
    [ ! -e "$PROJ/ai.txt.manifest" ]
}

@test "crawl privacy: ensure_required_files installs both by default" {
    run ensure_required_files "$PROJ"
    [ "$status" -eq 0 ]
    [ -f "$PROJ/robots.txt" ]
    [ -f "$PROJ/ai.txt" ]
    [ -f "$PROJ/VERSION" ]
}
