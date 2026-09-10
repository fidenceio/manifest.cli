#!/usr/bin/env bats
# §78 — the documentation handoff, end to end through scripts/manifest-cli.sh.
#
# The unit-level rules live in doc_handoff.bats. This file proves the parts
# only a real ship can prove: that the pause commits nothing, that the exit
# code is 4 and not 1, that the re-run KEEPS the driver's edits rather than
# regenerating over them, and that a genuine failure is still reported as a
# failure.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    # Offline and deterministic: no trusted-time network, no release gate.
    export MANIFEST_CLI_TIME_SERVER1="https://127.0.0.1:9/"
    export MANIFEST_CLI_TIME_TIMEOUT=1
    export MANIFEST_CLI_TIME_RETRIES=1
    export MANIFEST_CLI_RELEASE_GATE=none
    # Detection is doc_handoff.bats's and driver_detection.bats's concern; here
    # the policy is set explicitly so these tests assert the SHIP, not the
    # machine that runs them.
    export MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0
    export MANIFEST_CLI_DRIVER=none
}

teardown() {
    unset MANIFEST_CLI_DOCS_HANDOFF MANIFEST_CLI_DRIVER MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_TIMEOUT MANIFEST_CLI_TIME_RETRIES
    unset MANIFEST_CLI_RELEASE_GATE
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# A repo at 1.2.3, tagged, with two commits to release and a bare origin.
# The origin exists because the apply gate refuses an ambiguous target
# (no origin remote) before any step this file cares about.
write_repo() {
    local w="$SCRATCH/work"
    git init -q --bare "$SCRATCH/origin.git"
    git -C "$w" init -q -b main
    git -C "$w" config user.email t@example.com
    git -C "$w" config user.name T
    git -C "$w" remote add origin "$SCRATCH/origin.git"
    echo "1.2.3" > "$w/VERSION"
    printf '# App\n\nSee docs.\n' > "$w/README.md"
    mkdir -p "$w/docs"
    printf '# Guide\n\nBuilt against 1.2.3.\nComing in vNEXT: nothing yet.\n' > "$w/docs/GUIDE.md"
    git -C "$w" add -A
    git -C "$w" commit -qm "init"
    git -C "$w" tag v1.2.3
    git -C "$w" push -q -u origin main --tags
    echo "one" > "$w/src.txt"
    git -C "$w" add src.txt
    git -C "$w" commit -qm "feat: add the src thing"
}

brief_path() { printf '%s' "$SCRATCH/work/.git/manifest-ship/handoff/BRIEF.md"; }

# Replace the skeleton bullets with text only a person would write.
write_driver_changelog() {
    local w="$SCRATCH/work"
    {
        printf '# Changelog\n\n## [1.2.4] - %s\n\n' "$(_handoff_state_date)"
        printf '**Release Type:** Patch\n\n'
        printf -- '- Added the src thing, described by the driver rather than by a path table\n'
    } > "$w/CHANGELOG.md"
}

_handoff_state_date() {
    # grep -m1, never a pipeline into head (tests/suite_shell_options.bats).
    local line
    line="$(grep -m1 '^date=' "$SCRATCH/work/.git/manifest-ship/handoff/state")"
    printf '%s' "${line#date=}"
}

# --- the pause -------------------------------------------------------------

@test "always: the ship pauses with exit 4, makes no release commit, and leaves no tag" {
    write_repo
    local before; before="$(git -C "$SCRATCH/work" rev-parse HEAD)"

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y

    [ "$status" -eq 4 ]
    [[ "$output" == *"Documentation handoff — release paused at 1.2.4"* ]]
    # The version is written and dirty; HEAD does not carry it.
    [ "$(cat "$SCRATCH/work/VERSION")" = "1.2.4" ]
    [ "$(git -C "$SCRATCH/work" show HEAD:VERSION)" = "1.2.3" ]
    [ "$(git -C "$SCRATCH/work" tag)" = "v1.2.3" ]
    [ -f "$(brief_path)" ]
    # A pause is not a failure: none of the failure-report vocabulary appears.
    [[ "$output" != *"Ship Failure Report"* ]]
    [[ "$output" != *"reset --hard"* ]]
    [[ "$output" != *"Roll back"* ]]
    refute git -C "$SCRATCH/work" rev-parse v1.2.4
}

@test "CONTROL: with the handoff off the same repo ships to completion" {
    write_repo

    MANIFEST_CLI_DOCS_HANDOFF=off run_manifest ship repo patch --local -y

    [ "$status" -eq 0 ]
    [ "$(git -C "$SCRATCH/work" show HEAD:VERSION)" = "1.2.4" ]
    [[ "$(git -C "$SCRATCH/work" log -1 --format=%s)" == "Bump version to 1.2.4"* ]]
    [ ! -f "$(brief_path)" ]
}

@test "the pause report states what it DID commit rather than claiming nothing happened" {
    # A first ship into a repo missing scaffolding runs the pre-release
    # auto-commit before the pause. Claiming "nothing was committed" would be
    # false, and a report that lies about the tree is the defect this feature
    # exists to remove.
    write_repo
    local before; before="$(git -C "$SCRATCH/work" rev-parse HEAD)"

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y

    [ "$status" -eq 4 ]
    [[ "$output" == *"No release commit, tag or push was made"* ]]
    local after; after="$(git -C "$SCRATCH/work" rev-parse HEAD)"
    if [ "$before" != "$after" ]; then
        [[ "$output" == *"pre-release auto-commit"* ]]
    fi
}

@test "the brief names the release facts, the fixed heading and the stale lines" {
    write_repo

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y
    [ "$status" -eq 4 ]

    local brief; brief="$(brief_path)"
    grep -q "Version: \*\*1.2.4\*\*" "$brief"
    grep -q "## \[1.2.4\] - " "$brief"
    # The stale scan found the old version and the placeholder.
    grep -q "docs/GUIDE.md:3:" "$brief"
    grep -q "docs/GUIDE.md:4:" "$brief"
    # It states the boundary and the recovery.
    grep -q "will not run any program on your behalf" "$brief"
    grep -q "not\*\* regenerate" "$brief"
    grep -q "manifest ship repo patch --local -y" "$brief"
}

@test "the brief lives under .git and never enters the working tree" {
    write_repo

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y
    [ "$status" -eq 4 ]

    # Only VERSION and CHANGELOG.md (Manifest's own writes) are dirty; the
    # brief is not among them, so the release commit cannot sweep it in.
    local porcelain; porcelain="$(git -C "$SCRATCH/work" status --porcelain)"
    [[ "$porcelain" != *"manifest-ship"* ]]
    [[ "$porcelain" != *"BRIEF"* ]]
}

# --- the re-run ------------------------------------------------------------

@test "re-running without editing pauses again and names the failing rules" {
    write_repo
    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y
    [ "$status" -eq 4 ]

    # The skeleton has bullets, so R1/R2/R4 pass; the placeholder in GUIDE.md
    # is what is still wrong.
    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y

    [ "$status" -eq 4 ]
    [[ "$output" == *"R3 docs/GUIDE.md"* ]]
    [[ "$output" == *"not complete for 1.2.4"* ]]
    [ "$(git -C "$SCRATCH/work" show HEAD:VERSION)" = "1.2.3" ]
}

@test "THE GUARD: the re-run keeps the driver's CHANGELOG instead of regenerating it" {
    write_repo
    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y
    [ "$status" -eq 4 ]

    write_driver_changelog
    sed -i.bak 's/Coming in vNEXT: nothing yet./Coming next: nothing yet./' "$SCRATCH/work/docs/GUIDE.md"
    rm -f "$SCRATCH/work/docs/GUIDE.md.bak"

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y

    [ "$status" -eq 0 ]
    # prepend_root_changelog_entry deletes and re-inserts the section for this
    # version, so an unguarded doc_generation on the re-run would silently
    # replace exactly what the driver wrote. Captured and matched, never piped
    # into a refute: `refute cmd | grep` pipes the refute's own output.
    local committed
    committed="$(git -C "$SCRATCH/work" show HEAD:CHANGELOG.md)"
    [[ "$committed" == *"described by the driver rather than by a path table"* ]]
    [[ "$committed" != *"before release"* ]]
    [ "$(git -C "$SCRATCH/work" show HEAD:VERSION)" = "1.2.4" ]
    [ -z "$(git -C "$SCRATCH/work" status --porcelain)" ]
    [ ! -d "$SCRATCH/work/.git/manifest-ship/handoff" ]
}

@test "a pending handoff refuses a re-run with a different increment" {
    write_repo
    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y
    [ "$status" -eq 4 ]
    local head_before; head_before="$(git -C "$SCRATCH/work" rev-parse HEAD)"

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo minor --local -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"handoff for 1.2.4 is pending"* ]]
    [[ "$output" == *"Re-run exactly: manifest ship repo patch --local -y"* ]]
    # Nothing moved: no sweep of the bumped VERSION into a generic commit.
    [ "$(git -C "$SCRATCH/work" rev-parse HEAD)" = "$head_before" ]
    [ "$(cat "$SCRATCH/work/VERSION")" = "1.2.4" ]
}

# --- policy through the real CLI -------------------------------------------

@test "auto pauses when an agent is driving" {
    write_repo

    MANIFEST_CLI_DOCS_HANDOFF=auto MANIFEST_CLI_DRIVER=claude-code run_manifest ship repo patch --local -y

    [ "$status" -eq 4 ]
    [ "$(git -C "$SCRATCH/work" show HEAD:VERSION)" = "1.2.3" ]
}

@test "CONTROL: auto with the same agent inside CI ships without pausing" {
    # §71: a prompt or a pause that can stop a pipeline is a defect, so CI
    # outranks the agent even though both signals are present.
    write_repo

    MANIFEST_CLI_DOCS_HANDOFF=auto MANIFEST_CLI_DRIVER=ci CI=true run_manifest ship repo patch --local -y

    [ "$status" -eq 0 ]
    [ "$(git -C "$SCRATCH/work" show HEAD:VERSION)" = "1.2.4" ]
    [ ! -f "$(brief_path)" ]
}

@test "a fleet member never pauses, even on the prep path" {
    # The module guarantees this, but the guarantee was enforced only by
    # _MANIFEST_CLI_DELEGATED_APPLY_CONSENT, and `_fleet_prep_run` was the one
    # delegated call site that never set it. A paused member returns non-zero
    # into the fleet loop, so a deliberate pause read as a failed prep. Found
    # by the pre-commit steward review.
    local w="$SCRATCH/work"
    git init -q --bare "$SCRATCH/origin.git"
    git -C "$w" init -q -b main
    git -C "$w" config user.email t@example.com
    git -C "$w" config user.name T
    printf 'fleet:\n  name: "f"\n  versioning: "none"\nservices:\n  svca:\n    path: "./svca"\n' > "$w/manifest.fleet.config.yaml"
    printf '# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\ntrue\tsvca\t./svca\tfalse\tmain\n' > "$w/manifest.fleet.tsv"
    git -C "$w" add -A && git -C "$w" commit -qm coordination

    mkdir -p "$w/svca"
    git -C "$w/svca" init -q -b main
    git -C "$w/svca" config user.email t@example.com
    git -C "$w/svca" config user.name T
    git -C "$w/svca" remote add origin "$SCRATCH/origin.git"
    echo "1.2.3" > "$w/svca/VERSION"
    git -C "$w/svca" add -A && git -C "$w/svca" commit -qm init
    echo "work" > "$w/svca/src.txt"
    git -C "$w/svca" add -A && git -C "$w/svca" commit -qm "feat: work"

    MANIFEST_CLI_DOCS_HANDOFF=always MANIFEST_CLI_DRIVER=claude-code run_manifest prep fleet -y

    [ "$status" -eq 0 ]
    [[ "$output" != *"prep failed"* ]]
    [ ! -f "$w/svca/.git/manifest-ship/handoff/BRIEF.md" ]
}

@test "a pending handoff whose VERSION is no longer dirty gives followable advice" {
    # The driver commits its own doc edits — a normal thing for an agent told
    # to finish the documentation. `resume_in_place` can then never be true
    # again, so "re-run exactly <cmd>" names the command that just refused.
    write_repo
    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y
    [ "$status" -eq 4 ]
    git -C "$SCRATCH/work" add -A
    git -C "$SCRATCH/work" commit -qm "docs: finish the release notes"

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch --local -y

    [ "$status" -eq 1 ]
    [[ "$output" == *"cannot be resumed"* ]]
    [[ "$output" == *"Clear it and ship normally"* ]]
    [[ "$output" != *"Re-run exactly"* ]]
}

@test "the preview discloses the pause and writes nothing" {
    write_repo
    local before; before="$(git -C "$SCRATCH/work" status --porcelain)"

    MANIFEST_CLI_DOCS_HANDOFF=always run_manifest ship repo patch

    [ "$status" -eq 0 ]
    [[ "$output" == *"PAUSES before the release commit"* ]]
    [[ "$output" == *"exit 4"* ]]
    [[ "$output" == *"No program is chosen or run on your behalf"* ]]
    [ "$(git -C "$SCRATCH/work" status --porcelain)" = "$before" ]
    [ "$(cat "$SCRATCH/work/VERSION")" = "1.2.3" ]
}

@test "CONTROL: a real failure is still reported as a failure, not as a pause" {
    write_repo
    # A pre-commit hook that refuses, installed outside the tree.
    local hooks="$SCRATCH/hooks"
    mkdir -p "$hooks"
    printf '#!/bin/sh\necho "HOOK-FIXTURE: refusing"\nexit 1\n' > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"
    git -C "$SCRATCH/work" config core.hooksPath "$hooks"

    MANIFEST_CLI_DOCS_HANDOFF=off run_manifest ship repo patch --local -y

    [ "$status" -ne 0 ]
    [ "$status" -ne 4 ]
    [[ "$output" == *"Ship Failure Report"* ]]
    [[ "$output" != *"Documentation handoff"* ]]
}
