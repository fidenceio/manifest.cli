#!/usr/bin/env bats

# §2(b): `check_actual_pii` is a DETECTOR, so its tests are positive controls
# first — a detector that cannot fire passes every negative test, which is
# exactly how it shipped inert. As written before the fix, the three ERE
# patterns were passed to `grep -r` with no -E, so `+` and `{2,}` were
# literals and nothing ever matched. A/B against the unfixed module (QA's
# stash-free form: `git archive HEAD` into scratch, this file overlaid): the
# tests that assert detection or the fixed shape fail, and the scope tests
# (clean repo, documented examples, documentation types) pass either way —
# they state limits, they do not discriminate. The measured sets are in the
# §2(b) bullet of docs/TRACKER.md.

load 'helpers/setup'

setup() {
    load_modules "system/manifest-security.sh"
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$MANIFEST_CLI_PROJECT_ROOT/docs"
    cd "$MANIFEST_CLI_PROJECT_ROOT"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    printf '46.10.0\n' > VERSION
    printf '.env\n.env.*.local\nmanifest.config.local.yaml\n' > .gitignore
    git add VERSION .gitignore
    git commit -q -m "initial"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "positive control: an email address in a shell file is detected" {
    printf '#!/bin/bash\nMAINTAINER="alice.jones@realcorp.io"\n' > contact.sh

    run check_actual_pii "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Potential actual PII pattern found"* ]]
    [[ "$output" == *"@"* ]]   # the email pattern is the one named
}

@test "positive control: a phone number in a shell file is detected" {
    printf '#!/bin/bash\nSUPPORT_LINE="415-555-0199"\n' > contact.sh

    run check_actual_pii "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 1 ]
    [[ "$output" == *"Potential actual PII pattern found"* ]]
}

@test "a clean repo passes, including lines the retired address pattern matched" {
    # `[0-9]+ [A-Za-z ]+ [A-Za-z]+` matched both of these lines. If anyone
    # restores a street-address heuristic, this is the fixture it must not
    # fire on.
    printf '#!/bin/bash\n# 12 ok tests ran\necho "step 3 of 5 done"\n' > run.sh

    run check_actual_pii "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
    [[ "$output" != *"Potential actual PII pattern found"* ]]
}

@test "the documented example addresses are filtered, not reported" {
    printf '#!/bin/bash\n# contact: john.doe@example.com or 555-123-4567\n' > example.sh

    run check_actual_pii "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
}

@test "scope, stated: documentation file types are outside the scan" {
    # The scan excludes *.md and docs/ by design — prose carries contact
    # lines legitimately. This pins that exclusion so a widening is a
    # deliberate change, not drift.
    printf 'Contact alice.jones@realcorp.io for access.\n' > NOTES.md
    printf 'alice.jones@realcorp.io\n' > docs/owners.sh

    run check_actual_pii "$MANIFEST_CLI_PROJECT_ROOT"

    [ "$status" -eq 0 ]
}

@test "guard: the PII scan passes grep no long options, which BusyBox grep rejects" {
    # BusyBox grep (Alpine/musl installs) exits 2 on --exclude-dir and
    # --exclude; the scan once ran them behind 2>/dev/null and read the
    # failure as "0 matches". Candidate files come from find(1) now. The
    # positive controls above prove the scan fires on the containerized
    # leg; this pins the shape so the regression cannot be reintroduced.
    local module hits control
    module="$TEST_REPO_ROOT/modules/system/manifest-security.sh"

    # Positive control: the probe sees the shape it forbids, in the form
    # that actually shipped — the long option on its own continuation line,
    # which a same-line `grep .*--exclude` probe never saw (QA, 2026-11-06).
    control="$(printf 'x=$(grep -rE "$p" "$r" \\\n    --exclude-dir=.git)\n' | grep -cE -- '--(exclude|include)')"
    [ "$control" -eq 1 ]

    hits="$(awk '/^check_actual_pii\(\)/,/^}/' "$module" | grep -nE -- '--(exclude|include)' || true)"
    [ -z "$hits" ]
}

@test "a symlinked project root is scanned, not silently empty" {
    # `cd ~/link-to-repo` makes the root a symlink; find without -H yields
    # zero candidates and the always-green shape this item exists to kill.
    printf '#!/bin/bash\nMAINTAINER="alice.jones@realcorp.io"\n' > contact.sh
    ln -s "$MANIFEST_CLI_PROJECT_ROOT" "$SCRATCH/link"

    run check_actual_pii "$SCRATCH/link"

    [ "$status" -eq 1 ]
}

@test "a grep that rejects the scan's options is reported as CRITICAL, not as clean" {
    # The shape BusyBox grep produced on the old long options: usage text on
    # stderr, exit 2 — which `2>/dev/null | wc -l` once counted as 0 matches.
    local real_grep
    real_grep="$(command -v grep)"
    mkdir -p "$SCRATCH/bin"
    printf '#!/usr/bin/env bash\ncase " $* " in *" -E "*) echo "grep: unrecognized option: -E" >&2; exit 2;; esac\nexec "%s" "$@"\n' "$real_grep" > "$SCRATCH/bin/grep"
    chmod +x "$SCRATCH/bin/grep"
    printf '#!/bin/bash\nMAINTAINER="alice.jones@realcorp.io"\n' > contact.sh

    PATH="$SCRATCH/bin:$PATH" run manifest_security --check

    [ "$status" -eq 1 ]
    [[ "$output" == *"CRITICAL: PII scan could not run"* ]]
    [[ "$output" != *"No actual PII detected"* ]]
}

@test "PII is a WARNING: manifest security reports it and still exits 0" {
    # Promoting this to a critical (exit 1) would change the pre-commit hook
    # and the ship's security step for every installed copy; this test makes
    # that a deliberate decision rather than a side effect.
    printf '#!/bin/bash\nMAINTAINER="alice.jones@realcorp.io"\n' > contact.sh

    run manifest_security --check

    [ "$status" -eq 0 ]
    [[ "$output" == *"WARNING: Actual PII detected in code"* ]]
    [[ "$output" == *"Security audit passed with 1 warning(s)."* ]]
    [[ "$output" != *"No actual PII detected"* ]]
}
