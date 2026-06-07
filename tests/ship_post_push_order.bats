#!/usr/bin/env bats
#
# §8.1b-1: the post-push transaction must create the GitHub Release BEFORE
# updating the Homebrew formula, keep the local brew upgrade gated on Homebrew
# success, and stay idempotent on the resume path (release view-guard).

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

    # Treat the fixture as the canonical repo so the Homebrew block runs.
    should_update_homebrew_for_repo() { return 0; }

    # Order marker: each post-push step appends its name here so a test can
    # assert relative ordering without relying on stdout interleaving.
    ORDER_LOG="$SCRATCH/order.log"
    : > "$ORDER_LOG"

    # Stub the two heavy steps. Default contract: both succeed, formula update
    # leaves the working tree clean (so the commit/push branch is skipped).
    manifest_create_github_release_for_tag() {
        echo "github_release" >> "$ORDER_LOG"
        return 0
    }
    update_homebrew_formula() {
        echo "homebrew_formula" >> "$ORDER_LOG"
        return 0
    }

    # No brew on PATH by default → the (C) upgrade block self-skips to the
    # `manifest upgrade` arm, which we stub to a no-op success.
    manifest() { return 0; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "post-push creates the GitHub Release before updating the Homebrew formula" {
    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 0 ]

    # Both steps ran...
    grep -qx "github_release" "$ORDER_LOG"
    grep -qx "homebrew_formula" "$ORDER_LOG"
    # ...and the release step is recorded strictly before the formula step.
    local gh_line brew_line
    gh_line="$(grep -n '^github_release$' "$ORDER_LOG" | head -1 | cut -d: -f1)"
    brew_line="$(grep -n '^homebrew_formula$' "$ORDER_LOG" | head -1 | cut -d: -f1)"
    [ "$gh_line" -lt "$brew_line" ]
}

@test "GitHub Release failure (required) aborts before Homebrew with homebrew status still skipped" {
    # rc 1 = failed-and-required (fatal). Homebrew must never be attempted, and
    # the failure report must show homebrew status as not-yet-attempted.
    manifest_create_github_release_for_tag() {
        echo "github_release" >> "$ORDER_LOG"
        return 1
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 1 ]

    grep -qx "github_release" "$ORDER_LOG"
    ! grep -qx "homebrew_formula" "$ORDER_LOG"
    [[ "$output" == *"failed step:        github_release"* ]]
    [[ "$output" == *"homebrew status:    skipped"* ]]
}

@test "GitHub Release skip (rc 2) is non-fatal and Homebrew still runs" {
    manifest_create_github_release_for_tag() {
        echo "github_release" >> "$ORDER_LOG"
        return 2
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 0 ]

    grep -qx "github_release" "$ORDER_LOG"
    grep -qx "homebrew_formula" "$ORDER_LOG"
}

@test "local brew upgrade only runs after Homebrew success" {
    # Force Homebrew failure (rc 1 from update_homebrew_formula) → fatal, and the
    # brew upgrade block must never be reached.
    update_homebrew_formula() {
        echo "homebrew_formula" >> "$ORDER_LOG"
        return 1
    }
    brew() { echo "brew_called" >> "$ORDER_LOG"; return 0; }
    manifest() { echo "manifest_upgrade_called" >> "$ORDER_LOG"; return 0; }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 1 ]

    # GitHub release ran first, Homebrew was attempted and failed...
    grep -qx "github_release" "$ORDER_LOG"
    grep -qx "homebrew_formula" "$ORDER_LOG"
    # ...and neither the brew nor the manifest upgrade arm fired.
    ! grep -qx "brew_called" "$ORDER_LOG"
    ! grep -qx "manifest_upgrade_called" "$ORDER_LOG"
    [[ "$output" == *"failed step:        homebrew_update"* ]]
}

@test "resume after release-exists retries only Homebrew (view-guard skips release)" {
    # Simulate the resume contract: the GitHub Release already exists, so the
    # real manifest_create_github_release_for_tag view-guard returns 0 without
    # creating anything. We model that exact rc (0, no creation side effect) and
    # assert the post-push step proceeds straight to Homebrew, which succeeds.
    manifest_create_github_release_for_tag() {
        # rc 0 = release present (view-guard) OR newly created — same return.
        echo "github_release_view_ok" >> "$ORDER_LOG"
        return 0
    }
    update_homebrew_formula() {
        echo "homebrew_formula_retry" >> "$ORDER_LOG"
        return 0
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 0 ]

    grep -qx "github_release_view_ok" "$ORDER_LOG"
    grep -qx "homebrew_formula_retry" "$ORDER_LOG"
    local gh_line brew_line
    gh_line="$(grep -n '^github_release_view_ok$' "$ORDER_LOG" | head -1 | cut -d: -f1)"
    brew_line="$(grep -n '^homebrew_formula_retry$' "$ORDER_LOG" | head -1 | cut -d: -f1)"
    [ "$gh_line" -lt "$brew_line" ]
}

@test "real view-guard skips 'release create' when the release already exists (resume idempotency)" {
    # Exercise the ACTUAL manifest_create_github_release_for_tag (not a stub)
    # through the gh stub. With GH_STUB_EXIT=0, `gh release view` succeeds, so
    # the view-guard reports "exists" and returns 0 BEFORE reaching
    # `gh release create`. The recorded call log proves create was never issued.
    # Re-source the orchestrator so the real function replaces the setup() stub.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    git remote add origin "git@github.com:fidenceio/manifest.cli.git"
    gh_stub_install
    export GH_STUB_EXIT=0

    run manifest_create_github_release_for_tag "1.2.3" "v1.2.3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub Release: exists (v1.2.3)"* ]]

    # The view-guard ran...
    grep -q $'\trelease\tview' "$GH_STUB_LOG"
    # ...and create was never reached.
    ! grep -q $'\trelease\tcreate' "$GH_STUB_LOG"
}
