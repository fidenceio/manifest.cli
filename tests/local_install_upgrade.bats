#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules \
        "system/manifest-os.sh" \
        "system/manifest-install-paths.sh" \
        "git/manifest-git.sh" \
        "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$PROJECT_ROOT/formula"
    cd "$PROJECT_ROOT"
    git init -q .
    git checkout -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "1.2.3" > VERSION
    echo "stub formula" > formula/manifest.rb
    git add VERSION formula/manifest.rb
    git commit -qm "Bump version to 1.2.3"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"

    # Drive the first block to "success" without touching the tap or network:
    # treat fixture as the canonical CLI repo, and make the formula update
    # return 0 without modifying formula/manifest.rb so the commit branch is skipped.
    should_update_homebrew_for_repo() { return 0; }
    update_homebrew_formula() { return 0; }
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

@test "successful brew upgrade invokes the SSH-restore helper" {
    # Integration check: confirm post-push wires the SSH-restore step in after
    # a successful upgrade. The helper's own behavior is covered exhaustively
    # in homebrew_tap_ssh_restore.bats — this test only proves the call site
    # exists. No tap-dir paths or SSH URLs are hardcoded; we stub the helper
    # to drop a sentinel and assert the sentinel appears.
    local sentinel="$SCRATCH/ssh-restore-fired"
    manifest_ship_restore_tap_ssh_origin() { touch "$sentinel"; }

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
    [ -f "$sentinel" ]
}

@test "failed brew upgrade does NOT invoke the SSH-restore helper" {
    # Drift guard: the restore helper must only fire after a successful
    # upgrade, not unconditionally — otherwise we'd be writing origin URLs
    # against a tap brew may not even have touched.
    local sentinel="$SCRATCH/ssh-restore-fired"
    manifest_ship_restore_tap_ssh_origin() { touch "$sentinel"; }

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
    [ ! -f "$sentinel" ]
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

@test "local upgrade is skipped entirely when tap push did not succeed" {
    # Force the homebrew block to self-skip → workflow_homebrew_status stays "skipped".
    # The local upgrade gate must then prevent any upgrade output, even with a
    # fully functional brew on PATH.
    rm -f "$PROJECT_ROOT/formula/manifest.rb"
    git add -A
    git commit -qm "drop formula"

    brew() { return 0; }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Upgrading local Manifest CLI installation"
    ! echo "$output" | grep -q "Local installation upgraded"
    ! echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
}
