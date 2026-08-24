#!/usr/bin/env bats
# create_default_gitignore writes ".manifest-cli/" into every repo Manifest
# scaffolds, and _manifest_gate_pass_ledger_file's comment states that the
# release-gate ledger inside it is "never committed — .manifest-cli/ is
# gitignored by the Manifest .gitignore template". Both were true everywhere
# except here: this repo's own .gitignore had no such entry, so the ledger was
# tracked from 5b6b75b (2026-07-01) and committed 31 times. The mechanism was
# the ship itself — the gate writes the ledger mid-run, then the bare `git add .`
# auto-commit sweeps it, so every release carried a commit containing nothing
# but the ship's own artifact.
#
# SCOPE, deliberately narrow. This does NOT assert the repo's .gitignore is a
# superset of the whole template: the template is a kitchen-sink for arbitrary
# project types (Python, Java, Terraform, yarn), and 120 of its 184 advised rules
# are absent here — most of them irrelevant to a bash project. Two divergences
# are deliberate: this repo TRACKS docs/zArchive/ (24 files) where the template
# ignores it, and it omits "!.claude/settings.json" on purpose (see .gitignore
# and the self-application item in docs/TRACKER.md). What must hold is narrower
# and actually principled: the patterns describing MANIFEST'S OWN machine-local
# state apply to Manifest's own repo.
#
# CORRECTION 2026-08-24: this comment previously also claimed the repo tracks
# `coverage/`. It does not — `coverage/` is ignored at .gitignore:180 and
# `git ls-files coverage` is empty. The claim was written to justify this test's
# narrow scope and was never checked, which is the same unverified-restatement
# habit the register exists to catch. Measure before citing a divergence.
#
# The patterns are read out of the template rather than restated here, so adding
# a new Manifest state path to create_default_gitignore extends this guard by
# itself instead of quietly outgrowing it (TRACKER §9.26's lesson: a
# hand-maintained list beside the authority is just another surface to drift).

load 'helpers/setup'

setup() {
    load_modules "core/manifest-init.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Patterns from the template's "# Manifest CLI" section: everything between that
# header (and its ==== divider) and the next comment line.
manifest_section_patterns() {
    local rendered="$SCRATCH/gitignore.rendered"
    create_default_gitignore "$rendered" >/dev/null 2>&1
    awk '/^# Manifest CLI$/ {f=1; next}
         f && /^# =+$/ && started==0 {next}
         f && /^#/ {exit}
         f && NF {started=1; print}' "$rendered"
}

@test "gitignore: the template's Manifest-state patterns are present in this repo" {
    local patterns
    patterns="$(manifest_section_patterns)"

    # Control: the extraction found something. A changed header format would
    # otherwise yield an empty list and pass this test without checking anything
    # — the absent-input-reads-as-pass shape TRACKER §9.15 exists to kill.
    [ -n "$patterns" ]

    local pattern missing=""
    while IFS= read -r pattern; do
        [ -n "$pattern" ] || continue
        grep -qxF "$pattern" "$TEST_REPO_ROOT/.gitignore" || missing+="  $pattern"$'\n'
    done <<< "$patterns"

    if [ -n "$missing" ]; then
        printf 'template Manifest-state patterns missing from .gitignore:\n%s' "$missing" >&2
    fi
    [ -z "$missing" ]
}

@test "gitignore: no Manifest machine-local state is tracked in this repo" {
    # The stronger statement, and the one the incident actually needs: whatever
    # the .gitignore says, nothing under .manifest-cli/ may be in the index.
    run git -C "$TEST_REPO_ROOT" ls-files .manifest-cli/
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "gitignore: the release-gate ledger path is ignored, not merely absent" {
    # check-ignore distinguishes "ignored" from "happens not to exist right now".
    # Without this, deleting the ledger would make the test above pass while the
    # next gate run re-created a trackable file.
    run git -C "$TEST_REPO_ROOT" check-ignore -q .manifest-cli/release-gate-pass.epoch
    [ "$status" -eq 0 ]
}

@test "positive control: check-ignore does not claim a tracked path is ignored" {
    # Proves the mechanism above discriminates rather than reporting success for
    # anything handed to it.
    run git -C "$TEST_REPO_ROOT" check-ignore -q VERSION
    [ "$status" -ne 0 ]
}
