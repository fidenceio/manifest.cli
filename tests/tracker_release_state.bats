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
    # The probe must be a WHOLE command line that only ever appears inside the
    # fence. A bare `git rev-parse` is not fence-unique — the prose above the
    # recipe quotes it while explaining the broken upstream line, which turned
    # this control red the moment that explanation was written.
    local fenced_only='git ls-tree -r --name-only HEAD | grep -c CODEX_AUDIT'
    local prose
    prose="$(release_state_prose)"
    refute grep -qF -- "$fenced_only" <<<"$prose"
    # ...and the fence really is present in the unstripped section.
    run awk '/^### Release state/ {f=1; next} f && /^#{2,3} / {exit} f' "$(TRACKER)"
    [ "$status" -eq 0 ]
    grep -qF -- "$fenced_only" <<<"$output"
}

# --- the recipe must RUN, not merely read well -------------------------------
#
# Replacing recorded facts with commands only pays off if the commands work. The
# upstream line shipped as `git rev-parse --short HEAD @{upstream}` and was
# broken from the day it was written — `--short` accepts a single revision, so
# the two-argument form fails with "Needed a single revision" in every shell. It
# survived because nothing ever executed it; it was found by running the recipe
# by hand after a release (see TRACKER §69's release note for which one — naming
# it here would restate the current version, which version_single_source.bats
# forbids in any tracked file outside the release record, and which this file
# tripped on its first run). Prose is reviewed, commands are run, and
# this block had been getting the former treatment while claiming the latter.
#
# Only the `git` lines are executed here. `manifest --version` depends on what is
# INSTALLED rather than on this tree, and every `gh` line needs the network and a
# credential — running those would make the suite depend on both.

# The git command lines from the release-state recipe, comments stripped.
release_state_git_commands() {
    awk '/^### Release state/ {f=1; next}
         f && /^#{2,3} / {exit}
         f' "$(TRACKER)" \
    | awk '/^```/ {fence = !fence; next} fence' \
    | sed 's/[[:space:]]*#[^"'"'"']*$//' \
    | grep -E '^git ' \
    | sed 's/[[:space:]]*$//'
}

@test "release state: every git command in the recipe actually runs" {
    local cmds
    cmds="$(release_state_git_commands)"

    # Control: the extractor found commands at all. Without this the loop below
    # iterates zero times and reports a pass — the absent-input-reads-as-green
    # shape the control at the top of this file exists for.
    [ -n "$cmds" ]
    [ "$(printf '%s\n' "$cmds" | grep -c .)" -ge 3 ]

    # NOT an exit-code check, deliberately. `git ls-tree … | grep -c CODEX_AUDIT`
    # exits 1 when the count is zero, and zero is the answer the recipe WANTS —
    # so a non-zero status is a legitimate result here, not a broken command.
    # What this guards against is a command git itself refuses to parse, which is
    # what the upstream line did for its whole life. git announces that on stderr
    # with a `fatal:`/`usage:`/`error:` prefix.
    local cmd out failed=""
    while IFS= read -r cmd; do
        [ -n "$cmd" ] || continue
        # `|| true` is load-bearing: a command substitution carries its exit
        # status to the ASSIGNMENT, and bats fails a test on any non-zero
        # command. Without it, the `grep -c` line whose correct answer is a
        # non-zero exit would kill this test at the assignment — the same
        # confusion between "exited non-zero" and "is broken" that this test was
        # rewritten to avoid, reappearing one line lower.
        out="$( ( cd "$TEST_REPO_ROOT" && eval "$cmd" ) 2>&1 >/dev/null || true )"
        if grep -qE '^(fatal|usage|error):' <<<"$out"; then
            failed+="  $cmd"$'\n'"      -> $(grep -m1 -E '^(fatal|usage|error):' <<<"$out")"$'\n'
        fi
    done <<<"$cmds"

    if [ -n "$failed" ]; then
        printf 'release-state recipe commands git refuses to run:\n%s' "$failed" >&2
        return 1
    fi
}

@test "positive control: the recipe runner fails on a command that cannot run" {
    # Proves the loop above can go red, using the exact historical defect as the
    # probe — so this also documents what broke: --short takes one revision.
    run bash -c "cd '$TEST_REPO_ROOT' && git rev-parse --short HEAD '@{upstream}'"
    [ "$status" -ne 0 ]
    grep -qF 'Needed a single revision' <<<"$output"
    # ...and it is caught by the detector the loop above uses, not merely by
    # being non-zero. Without this the control would pass against a runner that
    # had stopped looking at stderr entirely.
    grep -qE '^(fatal|usage|error):' <<<"$output"
}

@test "positive control: a non-zero exit that is a real ANSWER is not flagged" {
    # The counterpart, and the reason this guard reads stderr instead of $?.
    # `grep -c` exits 1 on a count of zero, and zero is what the recipe requires.
    # A runner keyed on exit status would call the correct answer a broken
    # command and go permanently red.
    run bash -c "cd '$TEST_REPO_ROOT' && git ls-tree -r --name-only HEAD | grep -c CODEX_AUDIT"
    [ "$status" -ne 0 ]
    [ "$output" = "0" ]
    refute grep -qE '^(fatal|usage|error):' <<<"$output"
}

@test "positive control: the replacement upstream command does run" {
    # The other direction: the form now in the recipe must succeed and answer the
    # question, so the fix is not merely 'a command that exits 0'.
    run bash -c "cd '$TEST_REPO_ROOT' && git rev-list --left-right --count 'HEAD...@{upstream}'"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+[[:space:]]+[0-9]+$ ]]
}
