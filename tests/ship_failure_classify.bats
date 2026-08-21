#!/usr/bin/env bats
#
# RED-001 / §9.10 / §8.1a: the shared ship-failure classifier
# (core/manifest-ship-classify.sh). Unit coverage for the classification
# functions, plus the meta-check that the post-push step set has exactly one
# definition site so a divergent copy cannot quietly return.

load 'helpers/setup'

setup() {
    load_modules "core/manifest-ship-classify.sh"
}

@test "classifier: post-push step set covers homebrew_*, github_release, completion_clean" {
    manifest_ship_step_is_post_push "homebrew_update"
    manifest_ship_step_is_post_push "homebrew_commit"
    manifest_ship_step_is_post_push "github_release"
    manifest_ship_step_is_post_push "completion_clean"
}

@test "classifier: pre-push steps are not post-push" {
    refute manifest_ship_step_is_post_push "push_changes"
    refute manifest_ship_step_is_post_push "version_commit"
    refute manifest_ship_step_is_post_push "create_tag"
    refute manifest_ship_step_is_post_push "release_gate"
    # Anchored matches: only the exact step names qualify, not extensions.
    refute manifest_ship_step_is_post_push "github_release_notes"
    refute manifest_ship_step_is_post_push "completion_cleanup"
    refute manifest_ship_step_is_post_push ""
}

@test "classifier: commits-created classes" {
    [ "$(manifest_ship_commits_created_class 3)" = "positive" ]
    [ "$(manifest_ship_commits_created_class 1)" = "positive" ]
    [ "$(manifest_ship_commits_created_class 0)" = "zero" ]
    [ "$(manifest_ship_commits_created_class unknown)" = "unknown" ]
    [ "$(manifest_ship_commits_created_class "")" = "unknown" ]
    [ "$(manifest_ship_commits_created_class " 2")" = "unknown" ]
    [ "$(manifest_ship_commits_created_class -1)" = "unknown" ]
}

@test "classifier: recovery modes" {
    # Public release, post-push failure: rollback forbidden regardless of count.
    [ "$(manifest_ship_recovery_mode success completion_clean 3)" = "post-push" ]
    [ "$(manifest_ship_recovery_mode success homebrew_update 0)" = "post-push" ]
    [ "$(manifest_ship_recovery_mode success github_release unknown)" = "post-push" ]
    # Divergent multi-remote outcomes: rollback forbidden regardless of step.
    [ "$(manifest_ship_recovery_mode partial push_changes 1)" = "partial-push" ]
    [ "$(manifest_ship_recovery_mode partial resume_push 0)" = "partial-push" ]
    # Nothing public: the verified commit count decides.
    [ "$(manifest_ship_recovery_mode failed push_changes 2)" = "rollback" ]
    [ "$(manifest_ship_recovery_mode not_attempted version_commit 0)" = "checkout-files" ]
    [ "$(manifest_ship_recovery_mode not_attempted version_commit unknown)" = "no-destructive" ]
    [ "$(manifest_ship_recovery_mode not_attempted version_commit "")" = "no-destructive" ]
    # Pin of current behavior: a successful push with a NON-post-push step
    # (post-push release gate) still falls through to the commit-count rules.
    [ "$(manifest_ship_recovery_mode success release_gate 2)" = "rollback" ]
}

@test "meta: the post-push step set is defined only in manifest-ship-classify.sh" {
    # RED-001 anti-regression: the classifier exists because two divergent
    # copies of this pattern disagreed about completion_clean. Exactly one
    # definition site may exist; a second copy is the defect returning.
    run grep -rFl 'homebrew_|github_release' "$TEST_REPO_ROOT/modules"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO_ROOT/modules/core/manifest-ship-classify.sh" ]
}
