#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    # _MANIFEST_GH_VALIDATED_AT is module-scope; clear it so memoization
    # state cannot leak between tests when the suite is filtered or
    # re-ordered.
    unset _MANIFEST_GH_VALIDATED_AT MANIFEST_GH_VALIDATION_TTL
}

# -----------------------------------------------------------------------------
# Mutual exclusion (no gh involvement — pure arg parsing)
# -----------------------------------------------------------------------------

@test "init repo: --create-repo-private and --create-repo-public are mutually exclusive" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --create-repo-private --create-repo-public --dry-run
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mutually exclusive"
}

@test "prep repo: --create-repo-private and --create-repo-public are mutually exclusive" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q

    PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --create-repo-private --create-repo-public --dry-run
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mutually exclusive"
}

# -----------------------------------------------------------------------------
# init repo --dry-run with create flag
# -----------------------------------------------------------------------------

@test "init repo --dry-run --create-repo-private: shows planned gh repo create (private)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --create-repo-private
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*private"
    echo "$output" | grep -q "No changes written"
    # Hard guarantee: nothing actually changed.
    [ ! -d "$SCRATCH/.git" ]
}

@test "init repo --dry-run --create-repo-public: shows planned gh repo create (public)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --create-repo-public
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*public"
}

@test "init repo --dry-run --create-repo-private: marks origin as exists when already set" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"
    git init -q
    git remote add origin https://example.invalid/example.git

    PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --create-repo-private
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "exists:.*origin remote"
    ! echo "$output" | grep -q "would gh repo create"
}

# -----------------------------------------------------------------------------
# prep repo --dry-run with create flag
# -----------------------------------------------------------------------------

@test "prep repo --dry-run --create-repo-private: replaces prompt with planned gh repo create" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q

    PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --dry-run --create-repo-private < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*private"
    ! echo "$output" | grep -q "would prompt for an origin URL"
}

@test "prep repo --dry-run --create-repo-public: visibility flows through" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q

    PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --dry-run --create-repo-public < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*public"
}

# -----------------------------------------------------------------------------
# Help text exposes the flags
# -----------------------------------------------------------------------------

@test "init repo --help: lists --create-repo-private and --create-repo-public" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    run manifest_init_repo --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--create-repo-private"
    echo "$output" | grep -q -- "--create-repo-public"
}

@test "prep repo --help: lists --create-repo-private and --create-repo-public" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    run manifest_prep_repo --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--create-repo-private"
    echo "$output" | grep -q -- "--create-repo-public"
}

# -----------------------------------------------------------------------------
# Fleet wiring (manifest init fleet)
# -----------------------------------------------------------------------------

@test "init fleet: --create-repo-private and --create-repo-public are mutually exclusive" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"

    run manifest_init_fleet --create-repo-private --create-repo-public
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mutually exclusive"
}

@test "init fleet --help: lists --create-repo-private and --create-repo-public" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    run manifest_init_fleet --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q -- "--create-repo-private"
    echo "$output" | grep -q -- "--create-repo-public"
}

@test "_fleet_init_directory: invokes _manifest_gh_repo_create when visibility is set" {
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    mkdir -p "$SCRATCH/repo_a"

    # Stub out the helper so we don't actually call gh.
    _manifest_gh_repo_create() {
        echo "stub:$1:$2" >> "$SCRATCH/calls.log"
        return 0
    }

    run _fleet_init_directory "$SCRATCH/repo_a" "false" "private"
    [ "$status" -eq 0 ]
    grep -q "stub:$SCRATCH/repo_a:private" "$SCRATCH/calls.log"
}

@test "_fleet_init_directory: skips _manifest_gh_repo_create when no visibility" {
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    mkdir -p "$SCRATCH/repo_b"

    _manifest_gh_repo_create() {
        echo "should-not-fire" >> "$SCRATCH/calls.log"
        return 0
    }

    run _fleet_init_directory "$SCRATCH/repo_b" "false"
    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/calls.log" ]
}

@test "_fleet_init_directory: returns 2 when gh repo create fails" {
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    mkdir -p "$SCRATCH/repo_c"

    _manifest_gh_repo_create() { return 1; }

    run _fleet_init_directory "$SCRATCH/repo_c" "false" "private"
    [ "$status" -eq 2 ]
}

@test "_fleet_init_directory: returns 3 when path is missing on disk" {
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"

    run _fleet_init_directory "$SCRATCH/does-not-exist" "false"
    [ "$status" -eq 3 ]
    echo "$output" | grep -q "Directory not found"
}

@test "manifest_init_fleet: summary names missing paths and shows how to fix" {
    # End-to-end: a TSV row pointing at a non-existent dir should tally as
    # 'Missing: 1' (not silently skipped) and the fix-it block should name
    # the path and tell the user to edit manifest.fleet.tsv.
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"

    {
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tghost\t./ghost\trepo\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    PROJECT_ROOT="$SCRATCH" run manifest_init_fleet -n test-fleet
    echo "$output" | grep -q "Missing: 1"
    echo "$output" | grep -q "Issues to resolve:"
    echo "$output" | grep -q "Missing paths"
    echo "$output" | grep -q -- "- ./ghost"
    echo "$output" | grep -q "edit manifest.fleet.tsv"
}

@test "manifest_init_fleet --create-repo-private (Phase 1): prints 'applies in Phase 2' notice" {
    # Phase 1 fires when no manifest.fleet.tsv exists yet. The flag is
    # not actionable until Phase 2 (after the user edits the TSV), so the
    # entry point should forward-point with a notice rather than silently
    # accept-and-ignore.
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"

    PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private
    echo "$output" | grep -q "applies in Phase 2"
    echo "$output" | grep -q "after editing manifest.fleet.tsv"
}

@test "manifest_init_fleet --create-repo-private: end-to-end forwards visibility to _fleet_init_directory" {
    # End-to-end: parse at entry point -> rewrite to internal flag in
    # fleet_args -> _fleet_init re-parses -> per-row loop forwards to
    # _fleet_init_directory. Stubs the leaf so we don't touch gh.
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"
    mkdir -p svc_a

    # Old-format TSV (no DEFAULT-SELECT-HASH) — never flagged stale.
    {
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tsvc_a\t./svc_a\trepo\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    # Stub the leaf: capture exactly what arrived.
    _fleet_init_directory() {
        echo "stub:$1:$2:$3" >> "$SCRATCH/calls.log"
        return 0
    }
    # Don't actually contact gh.
    _manifest_require_gh() { return 0; }

    PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private -n test-fleet
    [ -f "$SCRATCH/calls.log" ]
    grep -q "stub:.*svc_a:false:private" "$SCRATCH/calls.log"
}

# -----------------------------------------------------------------------------
# _manifest_gh_repo_create real-path branches
# -----------------------------------------------------------------------------

@test "_manifest_gh_repo_create: origin already exists -> warns and skips gh (no invocation)" {
    # The dry-run path is already covered above. This exercises the live
    # guard at modules/core/manifest-shared-functions.sh: when origin is
    # already configured, the function must warn and short-circuit BEFORE
    # invoking `gh`. The sentinel file proves gh was never called.
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    git init -q "$SCRATCH/repo"
    git -C "$SCRATCH/repo" remote add origin https://example.invalid/example.git

    # Skip the require-gh check by seeding the memo cache.
    _MANIFEST_GH_VALIDATED_AT=$(date +%s)
    MANIFEST_GH_VALIDATION_TTL=300

    # Stub `gh` so we can detect any invocation. Function definitions
    # shadow PATH lookups in bash.
    gh() { echo "gh-was-called" >> "$SCRATCH/gh-sentinel"; return 0; }

    run _manifest_gh_repo_create "$SCRATCH/repo" "private"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "origin already configured"
    [ ! -f "$SCRATCH/gh-sentinel" ]
}

# -----------------------------------------------------------------------------
# _manifest_require_gh memoization (TTL)
# -----------------------------------------------------------------------------

@test "_manifest_require_gh: memoizes success across calls within TTL" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    # Force the cache to be considered fresh by seeding the timestamp.
    _MANIFEST_GH_VALIDATED_AT=$(date +%s)
    MANIFEST_GH_VALIDATION_TTL=300

    # Even with no `gh` on PATH, the memo should short-circuit and return 0.
    PATH="/usr/bin:/bin" run _manifest_require_gh
    [ "$status" -eq 0 ]
}

@test "_manifest_require_gh: re-checks after TTL expiry" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    # Stale timestamp + tiny TTL forces a re-check.
    _MANIFEST_GH_VALIDATED_AT=1
    MANIFEST_GH_VALIDATION_TTL=1

    # No `gh` on PATH should now surface as failure.
    PATH="/usr/bin:/bin" run _manifest_require_gh
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "GitHub CLI"
}
