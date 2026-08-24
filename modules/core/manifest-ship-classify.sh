#!/bin/bash
# -----------------------------------------------------------------------------
# Manifest CLI — shared ship-failure classification
# -----------------------------------------------------------------------------
# One implementation of "what recovery advice may a ship failure report give?"
#
# WHY THIS MODULE EXISTS
# The failure-report logic grew two divergent copies of the post-push step
# regex: the orchestrator's suppressed rollback advice for completion_clean,
# the fleet's copy did not — so a fleet member whose push succeeded but which
# failed at completion_clean was offered rollback advice for a release that
# was already public (RED-001). Separately, the rollback guard had no notion
# of whether a commit even existed: with commits_created=0 the report printed
# `git reset --hard <start_sha>`, which would have erased uncommitted work
# unrecoverably (TRACKER §9.10 — nothing committed means no reflog, no stash).
# This is the defect class TRACKER §6 exists to remove: duplicated
# derivations that agree only until they don't. Both call sites now share
# these functions; only their messages differ.
#
# CLASSIFICATION MODEL
#   post-push       push succeeded and the failed step runs after the push —
#                   the release is public; rollback advice is forbidden.
#   partial-push    a multi-remote push succeeded on some remotes and failed
#                   (or was not attempted) on others — public state exists
#                   somewhere; rollback advice is forbidden (TRACKER §8.1a).
#   rollback        nothing public and a verified positive number of commits
#                   was created — `git reset --hard <start_sha>` is safe.
#   checkout-files  nothing public and verifiably ZERO commits were created —
#                   a hard reset would destroy uncommitted work; only the
#                   ship-generated files should be reverted.
#   no-destructive  the commits-created count is unverifiable — fail safe and
#                   advise nothing destructive (§6: absence is not a value,
#                   and an unverifiable count must not authorize destruction).
# -----------------------------------------------------------------------------

# 0 if the step runs after the branch/tag push (so a push that succeeded means
# the release is already public when this step fails). THE post-push step set —
# the only definition site; call sites must not re-derive it.
manifest_ship_step_is_post_push() {
    [[ "${1:-}" =~ ^(homebrew_|github_release$|completion_clean$) ]]
}

# Classify a commits-created count. Echoes one of:
#   positive  a verified integer > 0
#   zero      a verified integer 0
#   unknown   anything else (empty, non-numeric, "unknown") — unverifiable
manifest_ship_commits_created_class() {
    local count="${1:-}"
    if [[ "$count" =~ ^[0-9]+$ ]]; then
        if [ "$count" -gt 0 ]; then
            echo "positive"
        else
            echo "zero"
        fi
    else
        echo "unknown"
    fi
}

# Decide which recovery advice a failure report may print.
#   $1 push_status      not_attempted | attempted | failed | partial | success
#   $2 failure_step     the step the ship stopped at
#   $3 commits_created  integer count, or anything else when unverifiable
# Echoes one mode (see CLASSIFICATION MODEL above):
#   post-push | partial-push | rollback | checkout-files | no-destructive
# Always returns 0 — the mode string is the verdict, not the exit status.
manifest_ship_recovery_mode() {
    local push_status="${1:-}"
    local failure_step="${2:-}"
    local commits_created="${3:-}"

    if [[ "$push_status" == "success" ]] && manifest_ship_step_is_post_push "$failure_step"; then
        echo "post-push"
        return 0
    fi
    if [[ "$push_status" == "partial" ]]; then
        echo "partial-push"
        return 0
    fi
    case "$(manifest_ship_commits_created_class "$commits_created")" in
        positive) echo "rollback" ;;
        zero)     echo "checkout-files" ;;
        *)        echo "no-destructive" ;;
    esac
    return 0
}
