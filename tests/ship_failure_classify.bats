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
    # §82: the pre-bump auto-commit sweep. Its count is a verified zero, but the
    # only files in the tree are the operator's own pending work — "checkout-files"
    # would tell them to discard it. Never destructive, whatever the count says.
    [ "$(manifest_ship_recovery_mode not_attempted auto_commit 0)" = "no-destructive" ]
    [ "$(manifest_ship_recovery_mode not_attempted auto_commit unknown)" = "no-destructive" ]
    # Pin of current behavior: a successful push with a NON-post-push step
    # (post-push release gate) still falls through to the commit-count rules.
    [ "$(manifest_ship_recovery_mode success release_gate 2)" = "rollback" ]
}

@test "§78 a documentation-handoff pause is classified 'paused', never destructively" {
    # A pause has no wreckage: nothing committed, tagged or pushed, and the
    # uncommitted files are the ones the driver was asked to write. Every
    # destructive mode is wrong here — including checkout-files, which names
    # CHANGELOG.md, the very file being written.
    [ "$(manifest_ship_recovery_mode not_attempted doc_handoff 0)" = "paused" ]
    [ "$(manifest_ship_recovery_mode not_attempted handoff_verify 0)" = "paused" ]
    # The verdict holds whatever the commit count says, because the pre-release
    # auto-commit legitimately creates commits before the pause.
    [ "$(manifest_ship_recovery_mode not_attempted doc_handoff 3)" = "paused" ]
    [ "$(manifest_ship_recovery_mode not_attempted handoff_verify unknown)" = "paused" ]

    # CONTROL: the neighbouring steps keep their existing classification, so
    # the new arm cannot be swallowing anything.
    [ "$(manifest_ship_recovery_mode not_attempted version_commit 0)" = "checkout-files" ]
    [ "$(manifest_ship_recovery_mode not_attempted version_commit 2)" = "rollback" ]
    # CONTROL: a step whose name merely contains a pause step's name is not one.
    [ "$(manifest_ship_recovery_mode not_attempted doc_generation 0)" = "checkout-files" ]
}

@test "meta: the pause step set is defined only in manifest-ship-classify.sh" {
    # Same anti-regression as the post-push set below: one definition site, so
    # a second copy cannot drift and start advising a revert on a pause.
    run grep -rFl 'doc_handoff$|handoff_verify$' "$TEST_REPO_ROOT/modules"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO_ROOT/modules/core/manifest-ship-classify.sh" ]
}

@test "meta: the post-push step set is defined only in manifest-ship-classify.sh" {
    # RED-001 anti-regression: the classifier exists because two divergent
    # copies of this pattern disagreed about completion_clean. Exactly one
    # definition site may exist; a second copy is the defect returning.
    run grep -rFl 'homebrew_|github_release' "$TEST_REPO_ROOT/modules"
    [ "$status" -eq 0 ]
    [ "$output" = "$TEST_REPO_ROOT/modules/core/manifest-ship-classify.sh" ]
}
