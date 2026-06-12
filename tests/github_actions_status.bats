#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
}

teardown() {
    unset MANIFEST_CLI_GITHUB_ACTIONS_WAIT
    unset MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS
    unset MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS
    unset MANIFEST_CLI_GITHUB_RELEASE_ENABLED
    unset MANIFEST_CLI_GITHUB_RELEASE_REQUIRED
    unset MANIFEST_CLI_GITHUB_RELEASE_DRAFT
    unset MANIFEST_CLI_GITHUB_RELEASE_PRERELEASE
    unset MANIFEST_CLI_GH_TEST_LOG
}

@test "github actions check can be disabled" {
    MANIFEST_CLI_GITHUB_ACTIONS_WAIT=false run manifest_check_github_actions_for_head "abc1234"

    [ "$status" -eq 2 ]
    [[ "$output" == *"skipped (disabled"* ]]
}

@test "github actions check is disabled by default" {
    run manifest_check_github_actions_for_head "abc1234"

    [ "$status" -eq 2 ]
    [[ "$output" == *"skipped (disabled"* ]]
}

@test "github actions check skips when gh is missing and wait is enabled" {
    old_path="$PATH"
    mkdir -p "${BATS_TEST_TMPDIR:-/tmp}/no-gh"

    MANIFEST_CLI_GITHUB_ACTIONS_WAIT=true PATH="${BATS_TEST_TMPDIR:-/tmp}/no-gh" run manifest_check_github_actions_for_head "abc1234"

    PATH="$old_path"
    [ "$status" -eq 2 ]
    [[ "$output" == *"skipped (gh not installed)"* ]]
}

@test "github actions check reports failed watched run" {
    gh() {
        case "$1 $2" in
            "auth status") return 0 ;;
            "run list") echo "123456"; return 0 ;;
            "run watch") return 1 ;;
            *) return 1 ;;
        esac
    }
    MANIFEST_CLI_GITHUB_ACTIONS_WAIT=true
    MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS=1
    MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS=1

    run manifest_check_github_actions_for_head "abcdef123456"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Run: 123456"* ]]
    [[ "$output" == *"GitHub Actions: failed"* ]]
    [[ "$output" == *"gh run view 123456 --log-failed"* ]]
}

@test "github actions check reports passed watched run" {
    gh() {
        case "$1 $2" in
            "auth status") return 0 ;;
            "run list") echo "123456"; return 0 ;;
            "run watch") return 0 ;;
            *) return 1 ;;
        esac
    }
    MANIFEST_CLI_GITHUB_ACTIONS_WAIT=true
    MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS=1
    MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS=1

    run manifest_check_github_actions_for_head "abcdef123456"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Run: 123456"* ]]
    [[ "$output" == *"GitHub Actions: passed"* ]]
}

@test "github release creation skips when disabled" {
    MANIFEST_CLI_GITHUB_RELEASE_ENABLED=false run manifest_create_github_release_for_tag "1.2.3" "v1.2.3"

    [ "$status" -eq 2 ]
    [[ "$output" == *"GitHub Release: skipped (disabled"* ]]
}

@test "github release creation reports existing release without creating" {
    SCRATCH="$(mk_scratch)"
    mkdir -p "$SCRATCH/repo"
    cd "$SCRATCH/repo"
    git init -q
    git remote add origin https://github.com/example/project.git
    PROJECT_ROOT="$SCRATCH/repo"
    export PROJECT_ROOT
    MANIFEST_CLI_GH_TEST_LOG="$SCRATCH/gh-release-existing.log"
    export MANIFEST_CLI_GH_TEST_LOG
    gh() {
        printf '%s\n' "$*" >> "$MANIFEST_CLI_GH_TEST_LOG"
        case "$1 $2" in
            "auth status") return 0 ;;
            "release view") return 0 ;;
            *) return 1 ;;
        esac
    }
    export -f gh

    run manifest_create_github_release_for_tag "1.2.3" "v1.2.3"

    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub Release: exists (v1.2.3)"* ]]
    grep -q "release view v1.2.3" "$MANIFEST_CLI_GH_TEST_LOG"
    ! grep -q "release create" "$MANIFEST_CLI_GH_TEST_LOG"
}

@test "github release creation creates missing release with changelog notes" {
    SCRATCH="$(mk_scratch)"
    mkdir -p "$SCRATCH/repo"
    cd "$SCRATCH/repo"
    git init -q
    git remote add origin git@github.com:example/project.git
    cat > CHANGELOG.md <<'EOF'
# Changelog

## [1.2.3] - 2026-05-08

### Changes

- Add GitHub Release integration.

## [1.2.2] - 2026-05-07
EOF
    PROJECT_ROOT="$SCRATCH/repo"
    export PROJECT_ROOT
    MANIFEST_CLI_GH_TEST_LOG="$SCRATCH/gh-release-create.log"
    export MANIFEST_CLI_GH_TEST_LOG
    gh() {
        printf '%s\n' "$*" >> "$MANIFEST_CLI_GH_TEST_LOG"
        case "$1 $2" in
            "auth status") return 0 ;;
            "release view") return 1 ;;
            "release create") return 0 ;;
            *) return 1 ;;
        esac
    }
    export -f gh

    run manifest_create_github_release_for_tag "1.2.3" "v1.2.3"

    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub Release: created (v1.2.3)"* ]]
    grep -q "release create v1.2.3 --repo example/project" "$MANIFEST_CLI_GH_TEST_LOG"
    grep -q "Add GitHub Release integration" "$MANIFEST_CLI_GH_TEST_LOG"
}
