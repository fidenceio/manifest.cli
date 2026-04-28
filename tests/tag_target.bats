#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH"
    cd "$SCRATCH"

    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit -q --allow-empty -m "first"
    FIRST_SHA="$(git rev-parse HEAD)"
    git commit -q --allow-empty -m "second"
    SECOND_SHA="$(git rev-parse HEAD)"
    export FIRST_SHA SECOND_SHA

    unset MANIFEST_CLI_GIT_TAG_PREFIX MANIFEST_CLI_GIT_TAG_SUFFIX
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "create_tag: tags HEAD when no target sha is provided" {
    run create_tag "1.0.0"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse v1.0.0^{commit})" = "$SECOND_SHA" ]
}

@test "create_tag: tags an earlier commit when target sha is provided" {
    run create_tag "1.0.0" "$FIRST_SHA"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse v1.0.0^{commit})" = "$FIRST_SHA" ]
}

@test "create_tag: empty second arg falls through to HEAD tagging" {
    run create_tag "1.0.0" ""
    [ "$status" -eq 0 ]
    [ "$(git rev-parse v1.0.0^{commit})" = "$SECOND_SHA" ]
}

@test "create_tag: honors MANIFEST_CLI_GIT_TAG_PREFIX/SUFFIX with target sha" {
    MANIFEST_CLI_GIT_TAG_PREFIX="release-" \
    MANIFEST_CLI_GIT_TAG_SUFFIX="-rc" \
        run create_tag "1.0.0" "$FIRST_SHA"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse release-1.0.0-rc^{commit})" = "$FIRST_SHA" ]
}

@test "create_tag: fails when target sha does not exist" {
    run create_tag "1.0.0" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    [ "$status" -ne 0 ]
    run git rev-parse v1.0.0
    [ "$status" -ne 0 ]
}

# Validates the orchestrator-level env-var dispatch logic. We extract just the
# case statement so the test stays unit-level and free of full-workflow side
# effects (commits, pushes, brew). Mirrors modules/workflow/manifest-orchestrator.sh.
resolve_tag_target_sha() {
    local version_commit_sha="$1"
    local result=""
    case "${MANIFEST_CLI_RELEASE_TAG_TARGET:-version_commit}" in
        version_commit)        result="$version_commit_sha" ;;
        final_release_commit)  result="" ;;
        *)                     result="$version_commit_sha" ;;
    esac
    echo "$result"
}

@test "tag target dispatch: defaults to version_commit sha" {
    unset MANIFEST_CLI_RELEASE_TAG_TARGET
    run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ "$output" = "abc123" ]
}

@test "tag target dispatch: version_commit returns the version sha" {
    MANIFEST_CLI_RELEASE_TAG_TARGET="version_commit" \
        run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ "$output" = "abc123" ]
}

@test "tag target dispatch: final_release_commit returns empty (use HEAD)" {
    MANIFEST_CLI_RELEASE_TAG_TARGET="final_release_commit" \
        run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tag target dispatch: unknown value falls back to version sha" {
    MANIFEST_CLI_RELEASE_TAG_TARGET="garbage" \
        run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ "$output" = "abc123" ]
}
