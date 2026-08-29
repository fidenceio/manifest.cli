#!/usr/bin/env bats
# bats file_tags=smoke

# The tracker's release-state section must record no release facts.
#
# Every release in this repo's history was followed by a `docs(tracker):` commit,
# and the cause was structural rather than sloppy: the release-state block
# restated tag SHAs, publish timestamps, CI conclusions and `origin/main`, none of
# which exist until after the push. So the block could never be written in the
# release's own commit, and every release falsified the previous release's
# paragraph — which then had to be corrected by yet another commit. The block had
# accreted one such paragraph per release plus a note saying the older one was
# stale.
#
# That is §36's defect — a fact restated where it does not live — sitting inside
# the register whose job is to police §36. The section now carries the COMMANDS
# that derive each fact instead of the facts themselves. A recipe cannot go stale,
# so a ship no longer leaves anything to correct.
#
# This guard exists because the pull toward re-adding "v… IS PUBLISHED AND
# VERIFIED" after a green release is strong, and one paragraph restarts the loop.
#
# Code fences are exempt: the recipe legitimately contains `origin/main`,
# `@{upstream}` and `gh release view`. It is prose assertions that rot.

load 'helpers/setup'

TRACKER() { printf '%s\n' "$TEST_REPO_ROOT/docs/TRACKER.md"; }

# The release-state section, with fenced code blocks removed.
release_state_prose() {
    awk '/^### Release state/ {f=1; next}
         f && /^#{2,3} / {exit}
         f' "$(TRACKER)" \
    | awk '/^```/ {fence = !fence; next} !fence'
}

# The three shapes that rot. Each is a fact the next push invalidates.
banned_iso_timestamp='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z'
banned_published_claim='IS PUBLISHED AND VERIFIED'
banned_ref_equals_sha='=.*`[0-9a-f]{7,40}`'

@test "release state: the section exists and is non-empty (control)" {
    # Without this, a renamed heading would empty every check below and turn this
    # whole file green while guarding nothing — the absent-input-reads-as-pass
    # shape this repo keeps paying for.
    local prose
    prose="$(release_state_prose)"
    [ -n "$prose" ]
    [ "$(printf '%s\n' "$prose" | grep -c .)" -ge 5 ]
}

@test "release state: records no publish timestamp" {
    run grep -nE "$banned_iso_timestamp" <<<"$(release_state_prose)"
    [ "$status" -ne 0 ]
}

@test "release state: makes no 'IS PUBLISHED AND VERIFIED' claim" {
    run grep -niF "$banned_published_claim" <<<"$(release_state_prose)"
    [ "$status" -ne 0 ]
}

@test "release state: asserts no ref equals a commit SHA" {
    # Historical citations like \`2468f3e\` are fine and wanted; what rots is an
    # assertion that a LIVE ref currently equals one.
    run grep -nE "$banned_ref_equals_sha" <<<"$(release_state_prose)"
    [ "$status" -ne 0 ]
}

# --- positive controls: prove each detector can actually fire ------------------
# Three separate controls rather than one, because a single broken regex would
# otherwise hide behind the other two.

@test "positive control: the timestamp detector fires on a planted timestamp" {
    run grep -cE "$banned_iso_timestamp" <<<'published 2026-08-28T21:25:15Z, not a draft'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "positive control: the published-claim detector fires on a planted claim" {
    # v0.0.0 is the repo's sentinel version, not the real one. Using the actual
    # current version here made this file trip version_single_source.bats on its
    # first full run — a guard breaking the rule it enforces, inside its own
    # fixture, which is the third recorded instance of that shape (§56, §57, §20).
    run grep -ciF "$banned_published_claim" <<<'**v0.0.0 IS PUBLISHED AND VERIFIED.**'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "positive control: the ref-equals-SHA detector fires on a planted assertion" {
    run grep -cE "$banned_ref_equals_sha" <<<'`origin/main` = `5be0ff7` = local HEAD'
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]
}

@test "positive control: the ref-equals-SHA detector spares a historical citation" {
    # The narrow half of the same control: banning SHAs outright would forbid the
    # provenance this file is largely made of.
    run grep -cE "$banned_ref_equals_sha" <<<'visible in the history as `2468f3e` and `ef42cc6`'
    [ "$status" -ne 0 ]
}

@test "positive control: fenced code is stripped before scanning" {
    # The recipe block names origin/main and @{upstream} on purpose. If fence
    # stripping broke, the section would still pass the three checks above — so
    # this asserts the stripping happened rather than assuming it.
    local prose
    prose="$(release_state_prose)"
    refute grep -qF 'git rev-parse' <<<"$prose"
    # ...and the fence really is present in the unstripped section.
    run awk '/^### Release state/ {f=1; next} f && /^#{2,3} / {exit} f' "$(TRACKER)"
    [ "$status" -eq 0 ]
    grep -qF 'git rev-parse' <<<"$output"
}
