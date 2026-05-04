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
