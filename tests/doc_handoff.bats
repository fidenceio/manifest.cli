#!/usr/bin/env bats
# §78 — the documentation handoff: policy, brief, stale scan, verification.
#
# Unit level. The end-to-end pause/edit/resume flow through the real CLI is
# tests/ship_doc_handoff.bats.

load 'helpers/setup'

setup() {
    load_modules "core/manifest-config.sh" "docs/manifest-handoff.sh"
    set_default_configuration
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH"
    cd "$SCRATCH"
    git init -q .
    git config user.email t@example.com
    git config user.name T
    # Detection is a separate concern; these tests fix the driver explicitly so
    # they assert the POLICY, not the machine they happen to run on.
    export MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0
    unset MANIFEST_CLI_DOCS_HANDOFF
}

teardown() {
    unset MANIFEST_CLI_DOCS_HANDOFF MANIFEST_CLI_DRIVER MANIFEST_CLI_DRIVER_DETECTED
    unset MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS _MANIFEST_CLI_DELEGATED_APPLY_CONSENT
    cd /tmp
    rm -rf "$SCRATCH"
}

# Resolve should_pause with a fixed driver, in a child so the detector's
# idempotence guard cannot leak between cases.
pause_verdict() { # $1 policy, $2 driver
    env MANIFEST_CLI_DOCS_HANDOFF="$1" MANIFEST_CLI_DRIVER="$2" \
        MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 \
        _MANIFEST_CLI_DELEGATED_APPLY_CONSENT="${3:-}" \
        MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" \
        bash -c '
            source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
            source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
            log_error() { :; }
            manifest_handoff_should_pause && echo pause || echo run
        '
}

# --- policy ----------------------------------------------------------------

@test "the policy normalizes off/auto/always and defaults to off" {
    unset MANIFEST_CLI_DOCS_HANDOFF
    [ "$(manifest_handoff_policy)" = "off" ]
    [ "$(MANIFEST_CLI_DOCS_HANDOFF=AUTO manifest_handoff_policy)" = "auto" ]
    [ "$(MANIFEST_CLI_DOCS_HANDOFF=always manifest_handoff_policy)" = "always" ]
}

@test "an unknown policy is rejected, never silently treated as off" {
    run env MANIFEST_CLI_DOCS_HANDOFF=sometimes bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
        log_error() { echo "ERR: $*"; }
        manifest_handoff_policy'
    [ "$status" -eq 2 ]
    [[ "$output" == *"Expected: off, auto, always"* ]]
}

@test "the pause matrix: policy x driver" {
    [ "$(pause_verdict off claude-code)" = "run" ]
    [ "$(pause_verdict auto claude-code)" = "pause" ]
    [ "$(pause_verdict auto other-agent)" = "pause" ]
    [ "$(pause_verdict auto ci)" = "run" ]
    [ "$(pause_verdict auto none)" = "run" ]
    [ "$(pause_verdict always none)" = "pause" ]
    [ "$(pause_verdict always ci)" = "pause" ]
}

@test "a fleet member never pauses, whatever the policy says" {
    # A member runs in a subshell whose non-zero status breaks the fleet loop
    # into its recovery report, so a paused member would read as a failed one.
    [ "$(pause_verdict always claude-code 1)" = "run" ]
    [ "$(pause_verdict auto claude-code 1)" = "run" ]
    # CONTROL: the same policy and driver outside a fleet child does pause.
    [ "$(pause_verdict always claude-code)" = "pause" ]
}

@test "auto never pauses a CI pipeline even when an agent is driving it" {
    run env MANIFEST_CLI_DOCS_HANDOFF=auto CI=true CLAUDECODE=1 \
        MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 bash -c '
            source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
            source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
            manifest_handoff_should_pause && echo pause || echo run'
    [ "$output" = "run" ]
}

# --- state lives outside the working tree ----------------------------------

@test "the state directory is under .git and writing it leaves the tree clean" {
    echo "x" > tracked.txt
    git add tracked.txt
    git commit -qm init
    local dir; dir="$(manifest_handoff_state_dir "$SCRATCH")"
    [[ "$dir" == *"/.git/manifest-ship/handoff" ]]
    mkdir -p "$dir"
    echo "brief" > "$dir/BRIEF.md"
    # The release commit ends in a bare `git add .`; a brief in the tree would
    # be committed into the release it describes.
    [ -z "$(git status --porcelain)" ]
}

@test "pending is empty with no state, and reports the version once written" {
    [ -z "$(manifest_handoff_pending "$SCRATCH")" ]
    local dir; dir="$(manifest_handoff_state_dir "$SCRATCH")"
    mkdir -p "$dir"
    printf 'version=2.0.0\nincrement_type=minor\ndate=2026-09-10\nbrief=%s/BRIEF.md\n' "$dir" > "$dir/state"
    local pending; pending="$(manifest_handoff_pending "$SCRATCH")"
    [ "$(printf '%s' "$pending" | cut -f1)" = "2.0.0" ]
    [ "$(printf '%s' "$pending" | cut -f2)" = "minor" ]
    manifest_handoff_clear "$SCRATCH"
    [ -z "$(manifest_handoff_pending "$SCRATCH")" ]
}

# --- the stale scan --------------------------------------------------------

@test "the stale scan finds old versions and placeholders, and skips CHANGELOG and the archive" {
    mkdir -p docs docs/zArchive
    printf '# Guide\n\nBuilt against 1.2.3.\n' > docs/GUIDE.md
    printf '# Readme\n\nComing in vNEXT.\n' > README.md
    printf '# Changelog\n\n## [1.2.3] - old\n' > CHANGELOG.md
    printf 'Historic note about 1.2.3 and vNEXT.\n' > docs/zArchive/OLD.md
    git add -A && git commit -qm docs

    local out; out="$(manifest_handoff_stale_scan "$SCRATCH" "1.2.3")"
    [[ "$out" == *"docs/GUIDE.md:3:"* ]]
    [[ "$out" == *"README.md:3:"* ]]
    # CHANGELOG names old versions for a living; the archive is a deliberate
    # record of superseded documents.
    [[ "$out" != *"CHANGELOG.md"* ]]
    [[ "$out" != *"zArchive"* ]]
}

@test "CONTROL: a clean tree scans clean" {
    mkdir -p docs
    printf '# Guide\n\nNothing stale here.\n' > docs/GUIDE.md
    git add -A && git commit -qm docs
    [ -z "$(manifest_handoff_stale_scan "$SCRATCH" "1.2.3")" ]
}

@test "the scan only reads tracked files" {
    printf 'Untracked mentions 1.2.3\n' > UNTRACKED.md
    [ -z "$(manifest_handoff_stale_scan "$SCRATCH" "1.2.3")" ]
}

# --- verification ----------------------------------------------------------

# Put a pause state and a CHANGELOG section in place for the verifier.
seed_verify() { # $1 = changelog body after the heading
    local dir; dir="$(manifest_handoff_state_dir "$SCRATCH")"
    mkdir -p "$dir"
    printf 'version=1.2.4\ndate=2026-09-10\nincrement_type=patch\nbrief=%s/BRIEF.md\n' "$dir" > "$dir/state"
    { printf '# Changelog\n\n## [1.2.4] - 2026-09-10\n\n'; printf '%s\n' "$1"; } > CHANGELOG.md
    git add -A 2>/dev/null || true
    git commit -qm changelog 2>/dev/null || true
}

@test "verification passes on a well-formed section" {
    seed_verify "- Something a person wrote"
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 0 ]
    [[ "$output" == *"verified"* ]]
}

@test "R1 fails when the heading is missing" {
    seed_verify "- Something"
    printf '# Changelog\n\n## [9.9.9] - 2026-09-10\n\n- Wrong version\n' > CHANGELOG.md
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R1 CHANGELOG.md"* ]]
    [[ "$output" == *"found 0"* ]]
}

@test "R1 fails when the date was changed to today's instead of the release date" {
    seed_verify "- Something"
    printf '# Changelog\n\n## [1.2.4] - 2026-12-25\n\n- Something\n' > CHANGELOG.md
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R1 CHANGELOG.md"* ]]
    [[ "$output" == *"recorded when the handoff was written"* ]]
}

@test "R2 fails when the section has no bullets" {
    seed_verify "Some prose but no list."
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R2 CHANGELOG.md"* ]]
    [[ "$output" == *"no bullets"* ]]
}

@test "R3 fails on a leftover placeholder; CONTROL: fixing it passes" {
    seed_verify "- Real content"
    printf '# Readme\n\nComing in vNEXT.\n' > README.md
    git add -A && git commit -qm readme
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R3 README.md"* ]]
    [[ "$output" == *"placeholder"* ]]

    printf '# Readme\n\nComing soon.\n' > README.md
    git add -A && git commit -qm readme2
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 0 ]
}

@test "R3 does not fire on documentation that DISCUSSES a placeholder" {
    # The first cut matched `X.Y.Z` and any backticked mention, so this repo's
    # own USER_GUIDE tripped it and `docs.handoff: always` produced a release
    # that could never complete. Found by the pre-commit steward review.
    seed_verify "- Real content"
    mkdir -p docs
    {
        printf '# Releasing\n\n'
        printf 'Tag the release as `vX.Y.Z` where X.Y.Z is the semantic version.\n'
        printf 'Write `vNEXT` in the heading and Manifest replaces it.\n'
        printf 'The `{{ next_version }}` token works too.\n'
        printf '\n```\n## vNEXT\n```\n'
    } > docs/RELEASING.md
    git add -A && git commit -qm docs
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 0 ]
}

@test "CONTROL: R3 still catches a real placeholder outside code" {
    seed_verify "- Real content"
    printf '# Notes\n\n## vNEXT\n\n- pending\n' > NOTES.md
    git add -A && git commit -qm notes
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R3 NOTES.md"* ]]

    printf '# Notes\n\nversion: {{ next_version }}\n' > NOTES.md
    git add -A && git commit -qm notes2
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R3 NOTES.md"* ]]
}

@test "THIS repository's own tracked markdown passes R3" {
    # A positive control against the exact regression above: the feature must
    # not brick the repo that ships it. Runs against the real tree, not a
    # fixture, because a fixture cannot notice new prose someone writes later.
    local offenders=0 f hit
    while IFS= read -r f; do
        [ -f "$TEST_REPO_ROOT/$f" ] || continue
        hit="$(_manifest_handoff_strip_code "$TEST_REPO_ROOT/$f" \
               | grep -nE -m1 -- "$MANIFEST_CLI_VERSION_PLACEHOLDER_REGEX" || true)"
        if [ -n "$hit" ]; then
            echo "placeholder in $f: $hit" >&2
            offenders=$((offenders + 1))
        fi
    done < <(git -C "$TEST_REPO_ROOT" ls-files -- '*.md' | grep -v 'docs/zArchive/')
    [ "$offenders" -eq 0 ]
}


@test "R2 does not accept a bullet that only exists inside a code fence" {
    seed_verify 'Here is the shape to follow:

```
- like this
```'
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R2 CHANGELOG.md"* ]]
}

@test "an unreadable policy REFUSES rather than failing open" {
    # The comment claimed a typo could not silently disable the handoff. It
    # could: the rejection was printed and the ship then committed anyway.
    run env MANIFEST_CLI_DOCS_HANDOFF=alwyas MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
        log_error() { echo "ERR: $*"; }
        manifest_handoff_should_pause; echo "rc=$?"'
    [[ "$output" == *"rc=2"* ]]
    # CONTROL: a valid policy still answers 0 or 1, never 2.
    run env MANIFEST_CLI_DOCS_HANDOFF=off MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
        manifest_handoff_should_pause; echo "rc=$?"'
    [[ "$output" == *"rc=1"* ]]
}

@test "R4 rejects assistant preamble in the section" {
    seed_verify "Sure, here are the release notes:

- Something"
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R4 CHANGELOG.md"* ]]
    [[ "$output" == *"Sure, here"* ]]
}

@test "R4 and the release-notes validator share ONE banned-phrase list" {
    # A phrase rejected in a provider's output must be rejected in a driver's
    # hand-written section too; two lists would drift.
    local phrase
    for phrase in "As an AI" "As a language model" "Sure, here" "Here are the" "I'll generate" "I'd be happy"; do
        [ -n "$(_manifest_handoff_banned_phrase "prefix $phrase suffix")" ] || {
            echo "handoff verifier does not reject: $phrase" >&2
            return 1
        }
    done
    [ -z "$(_manifest_handoff_banned_phrase "- An ordinary bullet")" ]
}

@test "every failing rule is reported in one pass, not one per re-run" {
    seed_verify "Prose only, and Sure, here it is."
    printf '# Readme\n\nvNEXT\n' > README.md
    git add -A && git commit -qm readme
    run manifest_handoff_verify "1.2.4"
    [ "$status" -eq 1 ]
    [[ "$output" == *"R2 "* ]]
    [[ "$output" == *"R3 "* ]]
    [[ "$output" == *"R4 "* ]]
    [[ "$output" == *"3 rule(s) failed"* ]]
}


# --- disclosure ------------------------------------------------------------

@test "the disclosure is silent when the policy is off" {
    run env MANIFEST_CLI_DOCS_HANDOFF=off MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
        manifest_handoff_disclose "manifest ship repo patch -y"'
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "the disclosure names the policy, the driver and the exit code when it will pause" {
    run env MANIFEST_CLI_DOCS_HANDOFF=always MANIFEST_CLI_DRIVER=none \
        MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
        MANIFEST_CLI_SHIP_HANDOFF_PAUSED_EXIT_CODE=4
        manifest_handoff_disclose "manifest ship repo patch -y"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"PAUSES before the release commit"* ]]
    [[ "$output" == *"docs.handoff: always"* ]]
    [[ "$output" == *"exit 4"* ]]
    [[ "$output" == *"manifest ship repo patch -y"* ]]
    # The §44 boundary, stated where the user reads about the feature.
    [[ "$output" == *"No program is chosen or run on your behalf"* ]]
}

@test "with a brief pending the disclosure says it VERIFIES, not that it pauses" {
    local dir; dir="$(manifest_handoff_state_dir "$SCRATCH")"
    mkdir -p "$dir"
    printf 'version=1.2.4\nincrement_type=patch\ndate=2026-09-10\nbrief=%s/BRIEF.md\n' "$dir" > "$dir/state"
    run env MANIFEST_CLI_DOCS_HANDOFF=always MANIFEST_CLI_DRIVER=none \
        MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        source "'"$TEST_REPO_ROOT"'/modules/docs/manifest-handoff.sh"
        manifest_handoff_disclose "manifest ship repo patch -y"'
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERIFIES the edits for 1.2.4"* ]]
    [[ "$output" == *"NOT regenerated"* ]]
    [[ "$output" != *"PAUSES"* ]]
}
