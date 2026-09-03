#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke

# Pins: ensure_repo_scaffold is the single shared init path for repo + fleet,
# and fleet passes over members that already have the full scaffold set.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

seed_complete_scaffold() {
    local root="$1"
    mkdir -p "$root/scripts" "$root/docs"
    printf '1.0.0\n' > "$root/VERSION"
    printf '# readme\n' > "$root/README.md"
    printf '# changelog\n' > "$root/CHANGELOG.md"
    printf 'node_modules/\n' > "$root/.gitignore"
    printf 'User-agent: *\nDisallow: /\n' > "$root/robots.txt"
    printf 'Allow: none\n' > "$root/ai.txt"
    printf '#!/bin/sh\necho mine\n' > "$root/scripts/run-tests.sh"
    chmod +x "$root/scripts/run-tests.sh"
    printf '# mine env\nCUSTOM=1\n' > "$root/.env.example"
}

@test "shared scaffold: ensure_repo_scaffold creates the full init set" {
    local proj="$SCRATCH/fresh"
    mkdir -p "$proj"
    run ensure_repo_scaffold "$proj"
    [ "$status" -eq 0 ]
    [ -f "$proj/VERSION" ]
    [ -f "$proj/README.md" ]
    [ -f "$proj/CHANGELOG.md" ]
    [ -f "$proj/.gitignore" ]
    [ -f "$proj/robots.txt" ]
    [ -f "$proj/ai.txt" ]
    [ -x "$proj/scripts/run-tests.sh" ]
    [ -f "$proj/.env.example" ]
    manifest_repo_scaffold_is_complete "$proj"
}

@test "shared scaffold: complete set is detected; incomplete is not" {
    local complete="$SCRATCH/complete"
    local partial="$SCRATCH/partial"
    seed_complete_scaffold "$complete"
    mkdir -p "$partial"
    printf '1.0.0\n' > "$partial/VERSION"

    manifest_repo_scaffold_is_complete "$complete"
    refute manifest_repo_scaffold_is_complete "$partial"
}

@test "shared scaffold: re-run never clobbers real files" {
    local proj="$SCRATCH/complete"
    seed_complete_scaffold "$proj"

    run ensure_repo_scaffold "$proj"
    [ "$status" -eq 0 ]
    # Real files stay byte-identical to the seeded content.
    grep -qx '1.0.0' "$proj/VERSION"
    grep -q 'echo mine' "$proj/scripts/run-tests.sh"
    grep -q 'CUSTOM=1' "$proj/.env.example"
    grep -q 'Disallow: /' "$proj/robots.txt"
    # No sidecar may appear beside any preserved file.
    [ ! -e "$proj/scripts/run-tests.sh.manifest" ]
    [ ! -e "$proj/.env.example.manifest" ]
    [ ! -e "$proj/robots.txt.manifest" ]
}

@test "fleet skip: already-initialized members are not re-scaffolded" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"

    local fleet="$SCRATCH/fleet"
    local member="$fleet/apps/demo"
    mkdir -p "$member"
    seed_complete_scaffold "$member"
    # Snapshot: no sidecars yet
    [ ! -e "$member/robots.txt.manifest" ]
    [ ! -e "$member/.env.example.manifest" ]
    [ ! -e "$member/scripts/run-tests.sh.manifest" ]

    # Calling the completeness gate directly is what the fleet loop uses to skip.
    manifest_repo_scaffold_is_complete "$member"

    # Simulate the fleet skip path: when complete, ensure_repo_scaffold is NOT called.
    if manifest_repo_scaffold_is_complete "$member"; then
        : # skip — same as fleet
    else
        ensure_repo_scaffold "$member"
    fi

    [ ! -e "$member/robots.txt.manifest" ]
    [ ! -e "$member/.env.example.manifest" ]
    [ ! -e "$member/scripts/run-tests.sh.manifest" ]
}

@test "fleet backfill: incomplete member gets the shared scaffold including privacy+env" {
    local member="$SCRATCH/fleet/apps/newsvc"
    mkdir -p "$member"
    git -C "$member" init -q

    refute manifest_repo_scaffold_is_complete "$member"
    run ensure_repo_scaffold "$member"
    [ "$status" -eq 0 ]
    manifest_repo_scaffold_is_complete "$member"
    grep -q 'GPTBot' "$member/robots.txt"
    grep -q 'scaffolded by Manifest CLI' "$member/.env.example"
}

# =============================================================================
# §73 — fleet init must not silently rewrite a member's own .gitignore
# =============================================================================
# ensure_repo_scaffold defaults its gitignore mode to `upgrade`, and the fleet
# loop calls it with stdout AND stderr sent to /dev/null. That combination
# appended advised rules to every incomplete member's existing .gitignore with
# the announcement discarded — falsifying the sentence in manifest-init.sh that
# makes appending to a file Manifest does not own defensible ("the count is
# always announced before it is written"), on the one path that touches N repos
# at once.
#
# The mode governs exactly one branch: an existing .gitignore that already has
# real entries. Both tests below are needed — the first proves the mutation
# stops, the second proves the fix did not go too far and leave a member with
# no .gitignore at all.

@test "fleet scaffold: report mode leaves an existing .gitignore untouched" {
    local member="$SCRATCH/fleet/apps/curated"
    mkdir -p "$member"
    git -C "$member" init -q
    # A hand-maintained .gitignore with real entries — the branch the mode governs.
    printf 'build/\nmy-secret-dir/\n' > "$member/.gitignore"
    local before
    before="$(sha256_of "$member/.gitignore")"

    run ensure_repo_scaffold "$member" report
    [ "$status" -eq 0 ]

    # Byte-for-byte unchanged: no appended rules, no marked header.
    [ "$(sha256_of "$member/.gitignore")" = "$before" ]
    refute grep -q 'Added by Manifest' "$member/.gitignore"
    # Positive control: the scaffold DID run — other files were created, so the
    # assertion above is about the mode and not about ensure_repo_scaffold
    # having quietly done nothing at all.
    [ -f "$member/robots.txt" ]
}

@test "fleet scaffold: report mode still CREATES a .gitignore when there is none" {
    local member="$SCRATCH/fleet/apps/bare"
    mkdir -p "$member"
    git -C "$member" init -q
    [ ! -e "$member/.gitignore" ]

    run ensure_repo_scaffold "$member" report
    [ "$status" -eq 0 ]

    # The other direction: `report` suppresses UPGRADING an existing file, never
    # creation. Without this, "stop mutating member .gitignores" could be
    # satisfied by leaving members with no .gitignore at all.
    [ -f "$member/.gitignore" ]
    grep -q 'KEY MATERIAL' "$member/.gitignore"
}

@test "fleet scaffold: upgrade mode DOES append — the control that dates the fix" {
    # Without this, both tests above would pass against an ensure_repo_scaffold
    # that had lost the ability to upgrade anything, and the §73 fix would be
    # indistinguishable from a regression.
    local member="$SCRATCH/fleet/apps/upgradable"
    mkdir -p "$member"
    git -C "$member" init -q
    printf 'build/\n' > "$member/.gitignore"

    run ensure_repo_scaffold "$member" upgrade
    [ "$status" -eq 0 ]
    grep -q "Added by Manifest" "$member/.gitignore"
}

# The three tests above pin ensure_repo_scaffold's BEHAVIOUR per mode. None of
# them can see the §73 defect, which was in the CALL SITE: they invoke the
# function directly with an explicit mode, so reverting fleet's argument leaves
# them all green. Verified by mutation — that is why this guard exists.
#
# It binds the general rule rather than one line: `upgrade` is the default, and
# it appends to a file Manifest does not own, so any caller outside the module
# that owns the function must SAY which mode it wants. A new caller that omits
# the argument gets the mutating default silently, which is exactly how §73
# happened.
@test "§73: every ensure_repo_scaffold caller outside manifest-init.sh names its mode" {
    local offenders=()
    local file line
    while IFS= read -r file; do
        # The defining module is excluded from its own rule — it is where the
        # default is declared. Asserted below to be exactly one path so the
        # exclusion cannot widen into a hiding place.
        [[ "$file" == *"/core/manifest-init.sh" ]] && continue
        while IFS= read -r line; do
            # grep -n prefixes "NNN:"; strip it before deciding, or every
            # comment MENTIONING the function reads as a bare call — which is
            # how this guard failed on its own explanatory comment first.
            local body="${line#*:}"
            case "$body" in
                [[:space:]]*'#'*|'#'*) continue ;;
            esac
            # A call is `ensure_repo_scaffold <root> <mode>`; anything with only
            # one argument before a redirect/terminator is taking the default.
            case "$body" in
                *'declare -F ensure_repo_scaffold'*) continue ;;
                *'ensure_repo_scaffold '*) ;;
                *) continue ;;
            esac
            if ! grep -qE 'ensure_repo_scaffold[[:space:]]+[^[:space:]]+[[:space:]]+(report|upgrade|"$[a-z_]+")' <<<"$body"; then
                offenders+=("$file: $line")
            fi
        done < <(grep -nF 'ensure_repo_scaffold ' "$file" 2>/dev/null || true)
    done < <(find "$TEST_REPO_ROOT/modules" -name '*.sh' -type f)

    if [ ${#offenders[@]} -gt 0 ]; then
        printf 'ensure_repo_scaffold called without an explicit gitignore mode:\n' >&2
        printf '  %s\n' "${offenders[@]}" >&2
    fi
    [ ${#offenders[@]} -eq 0 ]
}

@test "§73 control: the exclusion is exactly one file, and the guard can fail" {
    # Without this, the exclusion above could quietly grow to cover the very
    # caller it is meant to police, and the guard would still report green.
    local excluded
    excluded="$(find "$TEST_REPO_ROOT/modules" -name 'manifest-init.sh' -type f | wc -l | tr -d ' ')"
    [ "$excluded" -eq 1 ]

    # Positive control: the detector must reject a bare call. Proven on a
    # synthetic line rather than by editing the tree.
    local bare='                        ensure_repo_scaffold "$abs_path" >/dev/null 2>&1'
    refute grep -qE 'ensure_repo_scaffold[[:space:]]+[^[:space:]]+[[:space:]]+(report|upgrade|"\$[a-z_]+")' <<<"$bare"
    # ...and accept the fixed form.
    local fixed='                        ensure_repo_scaffold "$abs_path" report >/dev/null 2>&1'
    grep -qE 'ensure_repo_scaffold[[:space:]]+[^[:space:]]+[[:space:]]+(report|upgrade|"\$[a-z_]+")' <<<"$fixed"
}
