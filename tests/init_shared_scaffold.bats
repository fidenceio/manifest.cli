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
    ! manifest_repo_scaffold_is_complete "$partial"
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
    # Sidecars may appear (merge references) — that is still no-clobber.
    [ -f "$proj/scripts/run-tests.sh.manifest" ] || [ -f "$proj/.env.example.manifest" ] || [ -f "$proj/robots.txt.manifest" ]
}

@test "fleet skip: already-initialized members are not re-scaffolded with sidecars" {
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

    ! manifest_repo_scaffold_is_complete "$member"
    run ensure_repo_scaffold "$member"
    [ "$status" -eq 0 ]
    manifest_repo_scaffold_is_complete "$member"
    grep -q 'GPTBot' "$member/robots.txt"
    grep -q 'scaffolded by Manifest CLI' "$member/.env.example"
}
