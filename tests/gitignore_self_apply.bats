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
#
# ADDED 2026-08-25 — TRACKER §1(c), the second instance of the same class.
# `create_default_gitignore` also advises `.env.*` (manifest-init.sh:1126),
# `*.local.{yaml,yml,json,toml}` (:1127-1130) and `*.secret.*` (:1131-1134).
# This repo enumerated ten `.env` literals and one `*.local.*` path, so `.env.dev`,
# `.env.ci`, `creds.secret.json` and `manifest.fleet.config.local.yaml` — a file
# shape this CLI itself defines (manifest-config.sh:888) — were unignored HERE.
# The temp/merge artifacts (`*.tmp *.temp *.bak *.orig *.rej`, `tmp/`, `temp/`)
# were the sharper half: §3 correctly narrowed the ship-time cleanup sweep to the
# docs tree, so a stray one outside docs/ was neither ignored NOR swept, and §4's
# bare `git add .` would publish it. Fixed in 1905755, which shipped with no test
# — the verification lived only in the commit message. These are that test.
#
# The re-inclusions are the fragile part and get both a behavioural and a
# structural assertion: .gitignore is last-match-wins, so `!.env.example` above
# `.env.*` is dead text that reads exactly like live text. Nothing about the file
# announces that its line order is load-bearing, so an alphabetize or a re-sort
# would silently start ignoring the two template files.

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

# ---------------------------------------------------------------------------
# TRACKER §1(c) — the secret-, override- and temp-shaped rules (1905755).
#
# TWO MEASUREMENT CHOICES BELOW, both measured rather than assumed, because each
# has a failure mode that reads as a pass.
#
# 1. `--no-index` on every check, and it is load-bearing, not defensive.
#    `git check-ignore` WITHOUT it never reports a path that is in the index,
#    whatever .gitignore says. §1(d) says this repo should grow the `.env.example`
#    it currently lacks — and the day someone creates and tracks it, a plain
#    `check-ignore -q .env.example` starts answering "not ignored" for the wrong
#    reason and the negation-ordering guard passes vacuously forever. Measured
#    2026-08-25 in a scratch repo with `!.env.example` deliberately moved ABOVE
#    `.env.*`: for a TRACKED .env.example, plain `-q` still said 1 ("not
#    ignored") while `--no-index -q` said 0 ("ignored") and caught the break.
#    --no-index makes the verdict a property of the file under test.
#
# 2. No `-v`, ever. `-v` changes the exit-status contract from "is ignored" to
#    "matched some pattern", and a NEGATED pattern matches. Adding it for a
#    nicer failure message would invert every negation assertion here. Asserted
#    below rather than merely written down.
# ---------------------------------------------------------------------------

# 1-based line number of the first line in this repo's .gitignore equal to $1,
# or empty. awk compares whole strings, so gitignore patterns are not re-read as
# regexes (`.env.*` cannot be answered by `.env.*.local`, `*.secret.*` needs no
# escaping) and no pipeline is involved. Always exits 0, so an absent pattern
# arrives as an empty string to assert on rather than as an errexit abort.
gitignore_line_of() {
    awk -v pat="$1" '$0 == pat { print NR; exit }' "$TEST_REPO_ROOT/.gitignore"
}

@test "gitignore: the template's secret- and override-shaped rules are applied here" {
    local path not_ignored=""
    # One path per rule the fix added; the first four are the shapes TRACKER
    # §1(c) names, `manifest.fleet.config.local.yaml` being the one this CLI
    # itself writes and never ignored here.
    #
    # `creds.secret.txt` rather than `creds.secret.env` on purpose: the latter
    # was already caught by the pre-existing `*.env` (.gitignore:52), so it would
    # sit here passing under both the fixed and the unfixed file — a decorative
    # member. Measured during the A/B, not reasoned about.
    for path in .env.dev \
                .env.ci \
                manifest.fleet.config.local.yaml \
                app.local.yaml \
                app.local.yml \
                app.local.json \
                x.local.toml \
                creds.secret.yaml \
                creds.secret.yml \
                creds.secret.json \
                creds.secret.txt; do
        git -C "$TEST_REPO_ROOT" check-ignore -q --no-index "$path" \
            || not_ignored+="  $path"$'\n'
    done

    if [ -n "$not_ignored" ]; then
        printf 'expected .gitignore to ignore these, and it does not:\n%s' "$not_ignored" >&2
    fi
    [ -z "$not_ignored" ]
}

@test "gitignore: temp and merge artifacts are ignored outside the docs tree too" {
    # The half neither mechanism covered: the ship-time sweep is scoped to docs/
    # (TRACKER §3, tests/cleanup_sweep_scope.bats), so ignoring is the ONLY thing
    # standing between a stray artifact at the repo root and §4's `git add .`.
    # Hence the deliberately non-docs paths.
    local path not_ignored=""
    for path in scratch.tmp \
                build.temp \
                notes.bak \
                merge.orig \
                merge.rej \
                modules/core/scratch.tmp \
                tmp/x \
                temp/x; do
        git -C "$TEST_REPO_ROOT" check-ignore -q --no-index "$path" \
            || not_ignored+="  $path"$'\n'
    done

    if [ -n "$not_ignored" ]; then
        printf 'expected .gitignore to ignore these, and it does not:\n%s' "$not_ignored" >&2
    fi
    [ -z "$not_ignored" ]
}

@test "gitignore: .env.example and .env.template survive .env.*" {
    # These are templates, not secrets. `.env.*` swallows both, so they exist as
    # committable paths only because the two `!` lines are re-read AFTER it.
    local path wrongly_ignored=""
    for path in .env.example .env.template; do
        if git -C "$TEST_REPO_ROOT" check-ignore -q --no-index "$path"; then
            wrongly_ignored+="  $path"$'\n'
        fi
    done

    if [ -n "$wrongly_ignored" ]; then
        printf 're-inclusion is dead: .env.* now swallows these:\n%s' "$wrongly_ignored" >&2
        printf 'check the ORDER of `!.env.example` / `!.env.template` vs `.env.*`.\n' >&2
    fi
    [ -z "$wrongly_ignored" ]
}

@test "gitignore: the re-inclusions sit AFTER .env.*, structurally" {
    # The behavioural assertion above is the contract; this one names the cause.
    # A re-sort of .gitignore breaks the ordering without touching any pattern
    # text, so without this the only symptom is a check-ignore verdict flipping
    # for no visible reason. Asserted on line numbers, so it fails at the edit.
    local wildcard example template
    wildcard="$(gitignore_line_of '.env.*')"
    example="$(gitignore_line_of '!.env.example')"
    template="$(gitignore_line_of '!.env.template')"

    # Control: all three lines were actually located. A renamed or reformatted
    # pattern would otherwise leave these empty, and `[ "" -lt "" ]` is an error
    # rather than an assertion — the absent-input-reads-as-a-result shape.
    [ -n "$wildcard" ]
    [ -n "$example" ]
    [ -n "$template" ]

    [ "$wildcard" -lt "$example" ]
    [ "$wildcard" -lt "$template" ]
}

@test "gitignore: the new patterns do not swallow ordinary tracked content" {
    # Negative controls for the rules above. `--no-index` matters here for the
    # opposite reason to the ordering test: it strips the index's protection, so
    # these paths are judged by .gitignore alone and a pattern that grew wide
    # enough to match them shows up as a failure instead of being masked by the
    # fact that they happen to be tracked today.
    local path wrongly_ignored=""
    for path in VERSION README.md docs/TRACKER.md modules/core/manifest-init.sh; do
        if git -C "$TEST_REPO_ROOT" check-ignore -q --no-index "$path"; then
            wrongly_ignored+="  $path"$'\n'
        fi
    done

    if [ -n "$wrongly_ignored" ]; then
        printf 'an ignore rule has grown wide enough to swallow repo content:\n%s' "$wrongly_ignored" >&2
    fi
    [ -z "$wrongly_ignored" ]
}

@test "gitignore: no tracked file is ignored, so nothing was silently un-tracked" {
    # The check 1905755 ran by hand before adding the patterns, kept executable.
    # A pattern that matches something already in the index does not remove it,
    # it makes it invisible to every later `git add` — including §4's bare one —
    # so the file stops receiving updates with no error anywhere.
    local tracked="$SCRATCH/tracked-files"
    git -C "$TEST_REPO_ROOT" ls-files > "$tracked"

    # Control on the INPUT: an empty listing makes check-ignore print nothing,
    # which is byte-identical to a clean result.
    [ -s "$tracked" ]

    run git -C "$TEST_REPO_ROOT" check-ignore --no-index --stdin < "$tracked"
    # 0 = at least one matched, 1 = none did. Anything else is git failing, and
    # a failing git also prints nothing to stdout, so status is checked too.
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]

    if [ -n "$output" ]; then
        printf 'tracked files that .gitignore now ignores:\n%s\n' "$output" >&2
    fi
    [ -z "$output" ]
}

@test "positive control: the tracked-file sweep reports a path that IS ignored" {
    # Same command, same flags, one known-ignored path. Without this, the empty
    # result above is indistinguishable from a broken pipeline reading as clean
    # — the control 1905755's commit message claims, now run every time.
    local probe="$SCRATCH/probe-paths"
    printf '%s\n' '.env.dev' > "$probe"

    run git -C "$TEST_REPO_ROOT" check-ignore --no-index --stdin < "$probe"
    [ "$status" -eq 0 ]
    [ "$output" = ".env.dev" ]
}

@test "positive control: check-ignore means 'is ignored' only without -v" {
    # This one measures the INSTRUMENT, not the repo (TRACKER §5's protocol
    # point 5: the harness's own bugs read as product defects first). With -v the
    # exit status reports "some pattern matched", and a negated pattern matches
    # — so every `.env.example` assertion in this file would read as a pass for
    # the exact state it exists to reject. Recorded so adding -v fails HERE.
    run git -C "$TEST_REPO_ROOT" check-ignore -q --no-index .env.example
    [ "$status" -eq 1 ]

    run git -C "$TEST_REPO_ROOT" check-ignore -v --no-index .env.example
    [ "$status" -eq 0 ]
    [[ "$output" == *'!.env.example'* ]]
}
