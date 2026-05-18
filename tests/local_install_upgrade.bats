#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules \
        "system/manifest-os.sh" \
        "git/manifest-git.sh" \
        "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$PROJECT_ROOT"
    cd "$PROJECT_ROOT"
    git init -q .
    git checkout -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "1.2.3" > VERSION
    git add VERSION
    git commit -qm "Bump version to 1.2.3"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"

    # No formula/manifest.rb in PROJECT_ROOT → first block self-skips.
    # Stub the GitHub Release step so the middle block self-skips with rc=2.
    manifest_create_github_release_for_tag() { return 2; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "local upgrade surfaces install command when brew has no manifest installed" {
    # brew is on PATH (as a function), but `brew list --formula manifest` fails.
    brew() {
        if [[ "$1" == "list" && "$2" == "--formula" && "$3" == "manifest" ]]; then
            return 1
        fi
        return 0
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    echo "$output" | grep -q "brew install fidenceio/tap/manifest"
    # The new probe must replace the legacy generic warning, not run alongside it.
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
    ! echo "$output" | grep -q "Local installation upgraded"
}

@test "local upgrade reports success when brew upgrade manifest succeeds" {
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list --formula manifest") return 0 ;;
            "update "*|"update") return 0 ;;
            "upgrade manifest"*) return 0 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Local installation upgraded to v1.2.3 via Homebrew"
    ! echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
}

@test "local upgrade warns when brew has manifest installed but upgrade fails" {
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list --formula manifest") return 0 ;;
            "update "*|"update") return 0 ;;
            "upgrade manifest"*) return 1 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Homebrew upgrade did not complete"
    echo "$output" | grep -q "brew update && brew upgrade manifest"
    ! echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    ! echo "$output" | grep -q "Local installation upgraded"
}
