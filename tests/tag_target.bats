#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

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

@test "tag target dispatch: release_head returns empty (use HEAD)" {
    MANIFEST_CLI_RELEASE_TAG_TARGET="release_head" \
        run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tag target dispatch: final_release_commit is a deprecated alias for release_head" {
    MANIFEST_CLI_RELEASE_TAG_TARGET="final_release_commit" \
        run --separate-stderr resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"deprecated"* ]]
    [[ "$stderr" == *"release_head"* ]]
}

@test "tag target dispatch: unknown value falls back to version sha" {
    MANIFEST_CLI_RELEASE_TAG_TARGET="garbage" \
        run --separate-stderr resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ "$output" = "abc123" ]
}

@test "tag target dispatch: unknown value emits a warning to stderr" {
    # M6: lock the warning behavior so a future refactor that silently drops
    # it cannot pass tests.  The warning must echo back the offending value
    # so the user can debug their YAML.
    MANIFEST_CLI_RELEASE_TAG_TARGET="garbage" \
        run --separate-stderr resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [[ "$stderr" == *"garbage"* ]]
    [[ "$stderr" == *"version_commit or release_head"* ]]
}

@test "tag target dispatch: case-insensitive — Version_Commit accepted" {
    # M5: enumerated values are normalized (trim + lowercase) before dispatch
    # so a YAML user-typed "Version_Commit" matches the same as "version_commit".
    MANIFEST_CLI_RELEASE_TAG_TARGET="Version_Commit" \
        run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ "$output" = "abc123" ]
}

@test "tag target dispatch: whitespace-tolerant — surrounding spaces accepted" {
    # M5: even though load_yaml_to_env trims at load time, the dispatch is
    # also tolerant defensively so direct env-var users (CI scripts) get the
    # same forgiveness.
    MANIFEST_CLI_RELEASE_TAG_TARGET="  release_head  " \
        run resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "tag target dispatch: combined whitespace + case + deprecated alias" {
    # All three forgiveness layers compose: trim, lowercase, and the
    # final_release_commit -> release_head alias.
    MANIFEST_CLI_RELEASE_TAG_TARGET="  Final_Release_Commit  " \
        run --separate-stderr resolve_tag_target_sha "abc123"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [[ "$stderr" == *"deprecated"* ]]
}

# -----------------------------------------------------------------------------
# M7: workflow integration — divergent bump/CHANGELOG history
# -----------------------------------------------------------------------------
# The unit dispatch tests above prove resolve_tag_target_sha returns the right
# SHA (or empty) per setting. The create_tag tests prove the tag lands at an
# explicit SHA. M7 closes the loop: in the *actual* workflow sequence
# (Bump version commit -> CHANGELOG commit -> tag), does the tag land where
# the setting promises? This is the only scenario where version_commit and
# release_head diverge — without it, the feature's central distinction is
# untested at the integration level.
#
# Harness: rather than load the full manifest_ship_workflow (VERSION file,
# docs/, time server, markdown lint, etc.), we replay the orchestrator's
# tag-relevant slice — the bump commit and the CHANGELOG commit — then call
# the same two production functions the orchestrator does. Mirrors
# orchestrator.sh:285 (capture version_commit_sha), :347 (resolve_tag_target_sha),
# :350 (create_tag).

@test "M7 workflow: version_commit tags the bump commit when CHANGELOG follows" {
    # Replay the orchestrator's commit sequence on the scratch repo.
    git commit -q --allow-empty -m "Bump version to 1.0.0"
    local version_commit_sha
    version_commit_sha="$(git rev-parse HEAD)"
    git commit -q --allow-empty -m "Update main CHANGELOG.md to v1.0.0"
    local changelog_sha
    changelog_sha="$(git rev-parse HEAD)"
    # Sanity: the two commits really are different — without this the test
    # would silently pass either way.
    [ "$version_commit_sha" != "$changelog_sha" ]

    local tag_target_sha
    tag_target_sha="$(MANIFEST_CLI_RELEASE_TAG_TARGET=version_commit \
        resolve_tag_target_sha "$version_commit_sha")"
    run create_tag "1.0.0" "$tag_target_sha"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse v1.0.0^{commit})" = "$version_commit_sha" ]
    [ "$(git rev-parse v1.0.0^{commit})" != "$changelog_sha" ]
}

@test "M7 workflow: release_head tags the CHANGELOG commit (current HEAD)" {
    git commit -q --allow-empty -m "Bump version to 1.0.0"
    local version_commit_sha
    version_commit_sha="$(git rev-parse HEAD)"
    git commit -q --allow-empty -m "Update main CHANGELOG.md to v1.0.0"
    local changelog_sha
    changelog_sha="$(git rev-parse HEAD)"
    [ "$version_commit_sha" != "$changelog_sha" ]

    local tag_target_sha
    tag_target_sha="$(MANIFEST_CLI_RELEASE_TAG_TARGET=release_head \
        resolve_tag_target_sha "$version_commit_sha")"
    run create_tag "1.0.0" "$tag_target_sha"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse v1.0.0^{commit})" = "$changelog_sha" ]
    [ "$(git rev-parse v1.0.0^{commit})" != "$version_commit_sha" ]
}

@test "M7 workflow: default (unset) behaves like version_commit on divergent history" {
    # Locks the documented default. If someone flips the default to
    # release_head, this test fails loudly — that's a behavior change worth
    # blocking on.
    git commit -q --allow-empty -m "Bump version to 1.0.0"
    local version_commit_sha
    version_commit_sha="$(git rev-parse HEAD)"
    git commit -q --allow-empty -m "Update main CHANGELOG.md to v1.0.0"
    local changelog_sha
    changelog_sha="$(git rev-parse HEAD)"
    [ "$version_commit_sha" != "$changelog_sha" ]

    unset MANIFEST_CLI_RELEASE_TAG_TARGET
    local tag_target_sha
    tag_target_sha="$(resolve_tag_target_sha "$version_commit_sha")"
    run create_tag "1.0.0" "$tag_target_sha"
    [ "$status" -eq 0 ]
    [ "$(git rev-parse v1.0.0^{commit})" = "$version_commit_sha" ]
}
