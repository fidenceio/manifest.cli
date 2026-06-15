#!/usr/bin/env bats
#
# §8.1b-1: the post-push transaction must create the GitHub Release BEFORE
# publishing the Homebrew tap formula, keep the local brew upgrade gated on Homebrew
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

@test "post-push creates the GitHub Release before publishing the Homebrew tap formula" {
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

@test "post-push refuses source formula dirt instead of committing past the tag" {
    update_homebrew_formula() {
        echo "homebrew_formula" >> "$ORDER_LOG"
        echo "generated formula" > formula/manifest.rb
        return 0
    }
    local pre_head
    pre_head="$(git rev-parse HEAD)"

    run manifest_ship_post_push_steps "1.2.3" "$pre_head" "v1.2.3" "success"
    [ "$status" -eq 1 ]

    [ "$(git rev-parse HEAD)" = "$pre_head" ]
    [[ "$output" == *"modified formula/manifest.rb in the CLI repo"* ]]
    [[ "$output" == *"Refusing to create a post-tag CLI commit"* ]]
    ! git log --format=%s | grep -q "Update Homebrew formula to v1.2.3"
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

@test "completion invariant accepts clean repo when published HEAD is unchanged" {
    local pushed_head
    pushed_head="$(git rev-parse HEAD)"

    run manifest_ship_assert_completion_clean "true" "$pushed_head"
    [ "$status" -eq 0 ]
}

@test "completion invariant rejects dirty working tree before success" {
    echo "pending" > pending.txt

    run manifest_ship_assert_completion_clean "false" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"working tree is not clean"* ]]
    [[ "$output" == *"?? pending.txt"* ]]
}

@test "completion invariant rejects post-push source commits" {
    local pushed_head
    pushed_head="$(git rev-parse HEAD)"
    git commit --allow-empty -qm "Post-push source drift"

    run manifest_ship_assert_completion_clean "true" "$pushed_head"
    [ "$status" -eq 1 ]
    [[ "$output" == *"HEAD changed after branch/tag push"* ]]
    [[ "$output" == *"Manifest refuses to report success after creating post-push source commits"* ]]
}

@test "completion invariant does not compare HEAD for local-only ships" {
    local pushed_head
    pushed_head="$(git rev-parse HEAD)"
    git commit --allow-empty -qm "Local-only follow-up commit"

    run manifest_ship_assert_completion_clean "false" "$pushed_head"
    [ "$status" -eq 0 ]
}

@test "completion-clean failure report avoids reset advice for already-pushed releases" {
    run emit_ship_failure_report "completion_clean" "$(git rev-parse HEAD)" "1.2.3" "v1.2.3" "success" "success"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Release artifacts are already pushed"* ]]
    [[ "$output" == *"Inspect status:  git status --short"* ]]
    [[ "$output" == *"Inspect commits: git log --oneline v1.2.3..HEAD"* ]]
    [[ "$output" != *"Roll back:"* ]]
}

@test "real view-guard skips 'release create' when the release already exists (resume idempotency)" {
    # Exercise the ACTUAL manifest_create_github_release_for_tag (not a stub)
    # through the gh stub. With MANIFEST_CLI_GH_STUB_EXIT=0, `gh release view` succeeds, so
    # the view-guard reports "exists" and returns 0 BEFORE reaching
    # `gh release create`. The recorded call log proves create was never issued.
    # Re-source the orchestrator so the real function replaces the setup() stub.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    git remote add origin "git@github.com:fidenceio/manifest.cli.git"
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_EXIT=0

    run manifest_create_github_release_for_tag "1.2.3" "v1.2.3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub Release: exists (v1.2.3)"* ]]

    # The view-guard ran...
    grep -q $'\trelease\tview' "$MANIFEST_CLI_GH_STUB_LOG"
    # ...and create was never reached.
    ! grep -q $'\trelease\tcreate' "$MANIFEST_CLI_GH_STUB_LOG"
}

# --- Hook 1: tap reconciliation after the bottle-wait upgrade -----------------
# The post-push tap refresh runs right after the formula push (commit C1), but
# tap CI appends the :all bottle-SHA writeback (commit C2) AFTERwards. On a
# toolchain-gated host, ship waits for that bottle to pour; by the time it does,
# origin/main is at C2 and the local workspace checkout is one commit behind.
# Hook 1 re-runs the idempotent refresh at the wait-success point to close it.

# Bare tap remote with C1 then a CI-style writeback C2, plus a local checkout
# parked at C1 — the exact "1 behind" state Hook 1 must reconcile.
_seed_behind_tap_checkout() {
    local tap="$1"
    local remote="$SCRATCH/homebrew-tap.git"
    local writer="$SCRATCH/writer"

    git init --bare -q "$remote"
    git clone -q "$remote" "$writer"
    git -C "$writer" checkout -q -b main
    git -C "$writer" config user.email "test@example.com"
    git -C "$writer" config user.name "Test"
    mkdir -p "$writer/Formula"
    echo "C1" > "$writer/Formula/manifest.rb"
    git -C "$writer" add Formula/manifest.rb
    git -C "$writer" commit -qm "Update formula to v1.2.3"
    git -C "$writer" push -q -u origin main
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

    # Local checkout at C1 — what the post-push refresh already fast-forwarded to.
    git clone -q "$remote" "$tap"

    # CI lands the :all bottle SHA as a SECOND commit, after the formula push.
    echo "C2-bottle-sha" > "$writer/Formula/manifest.rb"
    git -C "$writer" add Formula/manifest.rb
    git -C "$writer" commit -qm "Add :all bottle for manifest 1.2.3 [skip ci]"
    git -C "$writer" push -q origin main
}

# Force manifest_ship_post_push_steps down the toolchain-gated bottle-wait
# SUCCESS branch, with the REAL tap refresh wired in against $tap.
_arrange_bottle_wait_success() {
    local tap="$1"
    # The real refresh + candidate discovery live in core, which the shared
    # setup() does not load; source it, then re-assert the stubs it overrides.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    should_update_homebrew_for_repo() { return 0; }
    update_homebrew_formula() { return 0; }

    # The fixture remote is a local path, so its origin slug won't match the
    # canonical tap slug — disable the slug guard (as homebrew_tap_refresh does).
    export MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT="$tap"
    export MANIFEST_CLI_HOMEBREW_TAP_SLUG=""

    brew() {
        case "$1" in
            update) return 0 ;;
            upgrade) echo "Error: Your Xcode is too outdated for this macOS"; return 1 ;;
            --prefix) echo "$SCRATCH/no-such-brew-prefix"; return 0 ;;
            *) return 0 ;;
        esac
    }
    manifest_install_paths_is_brew_managed() { return 0; }
    manifest_install_paths_ensure_brew_trust() { return 0; }
    manifest_install_paths_brew_error_is_toolchain_gate() { return 0; }
    manifest_ship_wait_for_bottle_upgrade() { return 0; }
    manifest_ship_restore_tap_ssh_origin() { return 0; }
    manifest_install_paths_auto_upgrade_mark_checked() { return 0; }
}

@test "bottle-wait success fast-forwards the workspace tap checkout to the CI writeback commit" {
    local tap="$SCRATCH/tap"
    _seed_behind_tap_checkout "$tap"
    [ "$(cat "$tap/Formula/manifest.rb")" = "C1" ]   # starts one commit behind
    _arrange_bottle_wait_success "$tap"

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 0 ]

    [[ "$output" == *"upgraded to v1.2.3 via Homebrew bottle"* ]]
    [[ "$output" == *"Refreshed local Homebrew tap checkout: $tap"* ]]
    # The checkout advanced C1 → C2 and now matches origin/main.
    [ "$(cat "$tap/Formula/manifest.rb")" = "C2-bottle-sha" ]
    [ "$(git -C "$tap" rev-parse HEAD)" = "$(git -C "$tap" rev-parse origin/main)" ]
}

@test "bottle-wait success leaves a dirty workspace tap checkout untouched" {
    local tap="$SCRATCH/tap" before
    _seed_behind_tap_checkout "$tap"
    before="$(git -C "$tap" rev-parse HEAD)"
    echo "local edit" >> "$tap/Formula/manifest.rb"   # uncommitted local work
    _arrange_bottle_wait_success "$tap"

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"
    [ "$status" -eq 0 ]

    # Ship still succeeds, but the dirty checkout is skipped, not mutated.
    [[ "$output" == *"Skipped local Homebrew tap checkout: $tap (dirty)"* ]]
    [ "$(git -C "$tap" rev-parse HEAD)" = "$before" ]
}
