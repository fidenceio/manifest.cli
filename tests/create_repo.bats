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
    # re-ordered. MANIFEST_CLI_GH_STUB_* belong to the gh_stub harness and would
    # similarly leak across tests if any test forgot to clean up.
    unset _MANIFEST_GH_VALIDATED_AT MANIFEST_CLI_GH_VALIDATION_TTL
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT MANIFEST_CLI_GH_STUB_AUTH_EXIT MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR
    unset MANIFEST_CLI_GH_STUB_ADD_REMOTE MANIFEST_CLI_GITHUB_OWNER
}

# -----------------------------------------------------------------------------
# Mutual exclusion (no gh involvement — pure arg parsing)
# -----------------------------------------------------------------------------

@test "init repo: --create-repo-private and --create-repo-public are mutually exclusive" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_repo --create-repo-private --create-repo-public --dry-run
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mutually exclusive"
}

@test "prep repo: --create-repo-private and --create-repo-public are mutually exclusive" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --create-repo-private --create-repo-public --dry-run
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mutually exclusive"
}

# -----------------------------------------------------------------------------
# init repo --dry-run with create flag
# -----------------------------------------------------------------------------

@test "init repo --dry-run --create-repo-private: shows planned gh repo create (private)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --create-repo-private
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*private"
    echo "$output" | grep -q "No changes written"
    # Hard guarantee: nothing actually changed.
    [ ! -d "$SCRATCH/.git" ]
}

@test "init repo --dry-run --create-repo-public: shows planned gh repo create (public)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --create-repo-public
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*public"
}

@test "init repo --dry-run --create-repo-private: marks origin as exists when already set" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    cd "$SCRATCH"
    git init -q
    git remote add origin https://example.invalid/example.git

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_repo --dry-run --create-repo-private
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

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --dry-run --create-repo-private < /dev/null
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would gh repo create:.*private"
    ! echo "$output" | grep -q "would prompt for an origin URL"
}

@test "prep repo --dry-run --create-repo-public: visibility flows through" {
    source "$TEST_REPO_ROOT/modules/core/manifest-prep.sh"
    cd "$SCRATCH"
    git init -q

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_prep_repo --dry-run --create-repo-public < /dev/null
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

@test "_manifest_dir_is_own_git_repository: rejects an ordinary directory nested in a parent repo" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
    git init -q "$SCRATCH"
    mkdir -p "$SCRATCH/child"

    run _manifest_dir_is_own_git_repository "$SCRATCH/child"
    [ "$status" -ne 0 ]

    git init -q "$SCRATCH/child"
    run _manifest_dir_is_own_git_repository "$SCRATCH/child"
    [ "$status" -eq 0 ]
}

@test "manifest_init_repo: creates an own repo when the target is nested in a parent repo" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    git init -q "$SCRATCH"
    mkdir -p "$SCRATCH/child"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH/child" run manifest_init_repo -y
    [ "$status" -eq 0 ]
    [ -d "$SCRATCH/child/.git" ]
    run git -C "$SCRATCH/child" rev-parse --show-toplevel
    # git canonicalizes the toplevel; on macOS $TMPDIR resolves through
    # /var -> /private/var, so compare "same directory" (device+inode) rather
    # than the raw string (mirrors release_gate.bats). mk_scratch intentionally
    # keeps the unresolved path for the sandbox-predicate prefix contract.
    [ "$output" -ef "$SCRATCH/child" ]
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
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tghost\t./ghost\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet -n test-fleet -y
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

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private -y
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
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tsvc_a\t./svc_a\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    # Stub the leaf: capture exactly what arrived.
    _fleet_init_directory() {
        echo "stub:$1:$2:$3" >> "$SCRATCH/calls.log"
        return 0
    }
    # Don't actually contact gh.
    _manifest_require_gh() { return 0; }

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private -n test-fleet -y
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
    MANIFEST_CLI_GH_VALIDATION_TTL=300

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
    MANIFEST_CLI_GH_VALIDATION_TTL=300

    # Even with no `gh` on PATH, the memo should short-circuit and return 0.
    PATH="/usr/bin:/bin" run _manifest_require_gh
    [ "$status" -eq 0 ]
}

@test "_manifest_require_gh: re-checks after TTL expiry" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=1

    # Stale timestamp + tiny TTL forces a re-check.
    _MANIFEST_GH_VALIDATED_AT=1
    MANIFEST_CLI_GH_VALIDATION_TTL=1

    run _manifest_require_gh
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "not authenticated"
    grep -q $'\tauth\tstatus' "$MANIFEST_CLI_GH_STUB_LOG"
}

# -----------------------------------------------------------------------------
# Strict exit code: _fleet_init bubbles a non-zero status on partial failure
# so CI can act on success/failure without parsing English.
# -----------------------------------------------------------------------------

@test "_fleet_init: exits 2 when TSV row points at a missing directory" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"

    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tghost\t./ghost\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet -n test-fleet -y
    [ "$status" -eq 2 ]
}

@test "_fleet_init: exits 1 when a row's gh repo create fails" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"
    mkdir -p svc_x

    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tsvc_x\t./svc_x\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    _manifest_require_gh() { return 0; }
    _manifest_gh_repo_create() { return 1; }

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private -n test-fleet -y
    [ "$status" -eq 1 ]
}

@test "_fleet_init: exits 0 when all selected rows initialize cleanly" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"
    mkdir -p svc_clean

    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tsvc_clean\t./svc_clean\tfalse\t\t\t0.0.0\n"
    } > manifest.fleet.tsv

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet -n test-fleet -y
    [ "$status" -eq 0 ]
    # §9.5: a cleanly-initialized member is also made Manifest-trackable.
    # VERSION is the load-bearing file (created first, no external deps); the
    # full set (README/CHANGELOG/docs) is asserted end-to-end in first.bats.
    [ -f "$SCRATCH/svc_clean/VERSION" ]
}

@test "_fleet_init: repairs stale HAS_GIT inside a parent repo and creates the configured-owner remote" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"

    git init -q .
    git remote add origin git@github.com:example/fleet-root.git
    mkdir -p service.greenlane
    printf 'existing content\n' > service.greenlane/app.txt

    {
        printf 'fleet:\n  name: "test-fleet"\n  versioning: "none"\n'
        printf 'services:\n  servicegreenlane:\n    path: "./service.greenlane"\n    type: "service"\n    branch: "main"\n'
    } > manifest.fleet.config.yaml
    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\tservicegreenlane\t./service.greenlane\ttrue\tgit@github.com:example/service.greenlane.git\t\n"
    } > manifest.fleet.tsv

    export MANIFEST_CLI_GITHUB_OWNER=fidenceio
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private -n test-fleet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would git init:  1 selected directory without git"* ]]
    [[ "$output" == *"would gh repo create: fidenceio/service.greenlane (private)"* ]]

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet --create-repo-private -n test-fleet -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Stale fleet inventory says HAS_GIT=true"* ]]
    [[ "$output" == *"GitHub (private): 1 ready, 0 failed"* ]]
    [ -d "$SCRATCH/service.greenlane/.git" ]
    run git -C "$SCRATCH/service.greenlane" remote get-url origin
    [ "$output" = "git@github.com:fidenceio/service.greenlane.git" ]
    grep -q $'repo\tcreate\tfidenceio/service.greenlane\t--private' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "_fleet_init: re-run on an initialized fleet preserves config and backfills members (no-clobber, no bail)" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"

    # Two existing git members: one bare (needs backfill), one already carrying
    # curated Manifest files (must survive byte-for-byte).
    git init -q "$SCRATCH/svc_bare"
    git init -q "$SCRATCH/svc_seeded"
    printf '2.5.0\n' > "$SCRATCH/svc_seeded/VERSION"
    printf '# Hand-written readme — do not touch\n' > "$SCRATCH/svc_seeded/README.md"
    local seeded_version seeded_readme
    seeded_version="$(cat "$SCRATCH/svc_seeded/VERSION")"
    seeded_readme="$(cat "$SCRATCH/svc_seeded/README.md")"

    # A curated DEPTH-2 member: an adaptive (`auto`) rescan settles at the
    # shallowest level with a repo (depth 1, svc_bare/svc_seeded) and would NOT
    # re-find this one — the exact row the v55.0.1 refresh silently dropped.
    mkdir -p "$SCRATCH/group"
    git init -q "$SCRATCH/group/svc_deep"

    # A curated, already-present fleet config (with a sentinel we can diff on).
    {
        printf 'fleet:\n'
        printf '  name: "curated-fleet"   # SENTINEL-DO-NOT-REGEN\n'
        printf '  versioning: "none"\n'
        printf 'services:\n'
        printf '  svc_bare:\n    path: "./svc_bare"\n    type: "service"\n    branch: "main"\n'
        printf '  svc_seeded:\n    path: "./svc_seeded"\n    type: "service"\n    branch: "main"\n'
    } > manifest.fleet.config.yaml
    local config_before
    config_before="$(cat manifest.fleet.config.yaml)"

    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tsvc_bare\t./svc_bare\ttrue\t\t\t\n"
        printf "true\tsvc_seeded\t./svc_seeded\ttrue\t\t\t2.5.0\n"
        printf "true\tsvc_deep\t./group/svc_deep\ttrue\t\t\t\n"
    } > manifest.fleet.tsv
    local tsv_before
    tsv_before="$(cat manifest.fleet.tsv)"

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet -n test-fleet -y

    # Expected scenario: succeeds, does NOT take the old "already initialized" bail.
    [ "$status" -eq 0 ]
    [[ "$output" != *"To reinitialize from scratch"* ]]
    [[ "$output" == *"Preserved:"*"manifest.fleet.config.yaml"* ]]

    # Curated config preserved byte-for-byte (no regeneration without --force).
    [ "$(cat manifest.fleet.config.yaml)" = "$config_before" ]

    # v55.0.1 regression guard: the curated TSV — including the depth-2 row a
    # shallow auto-rescan would drop — is preserved byte-for-byte. Backfill mode
    # never rescans the membership list (use `manifest update fleet` for that).
    [ "$(cat manifest.fleet.tsv)" = "$tsv_before" ]
    [[ "$(cat manifest.fleet.tsv)" == *"group/svc_deep"* ]]
    [[ "$output" == *"Preserved:"*"manifest.fleet.tsv"* ]]

    # Bare member backfilled. VERSION/README/CHANGELOG have no external deps;
    # the docs/ folder depends on MANIFEST_CLI_DOCS_FOLDER (set by full config
    # init, not by direct module sourcing) so the docs/ backfill is asserted
    # end-to-end in first.bats rather than here.
    [ -f "$SCRATCH/svc_bare/VERSION" ]
    [ -f "$SCRATCH/svc_bare/README.md" ]
    [ -f "$SCRATCH/svc_bare/CHANGELOG.md" ]

    # Seeded member untouched (no-clobber).
    [ "$(cat "$SCRATCH/svc_seeded/VERSION")" = "$seeded_version" ]
    [ "$(cat "$SCRATCH/svc_seeded/README.md")" = "$seeded_readme" ]

    # Backfill writes files but never commits — they land uncommitted.
    run git -C "$SCRATCH/svc_bare" status --porcelain
    [[ "$output" == *"VERSION"* ]]
}

@test "_fleet_init: first-time Phase 2 refresh honors the TSV's recorded depth, not auto" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"
    cd "$SCRATCH"

    # A repo at depth 1 makes `auto` settle at depth 1; a second repo at depth 2
    # is only seen by a depth>=2 scan. A first-time Phase 2 (no config yet) DOES
    # refresh the TSV — and must rescan at the depth that PRODUCED it (recorded
    # in the "# Depth:" header), not re-resolve `auto` and collapse to depth 1.
    git init -q "$SCRATCH/svc_top"
    mkdir -p "$SCRATCH/group"
    git init -q "$SCRATCH/group/svc_deep"

    {
        printf "# MANIFEST FLEET — Directory Inventory\n"
        printf "# Root: %s\n" "$SCRATCH"
        printf "# Depth: 2\n"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\tsvc_top\t./svc_top\ttrue\t\t\t\n"
        printf "true\tsvc_deep\t./group/svc_deep\ttrue\t\t\t\n"
    } > manifest.fleet.tsv

    # No preexisting config -> first-time Phase 2 -> refresh path runs.
    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" run manifest_init_fleet -n test-fleet -y
    [ "$status" -eq 0 ]

    # The depth-2 member survived the refresh, and the rewritten header still
    # records depth 2. A regressed `auto` rescan would write "# Depth: 1" and
    # drop the deeper row.
    [[ "$(cat manifest.fleet.tsv)" == *"group/svc_deep"* ]]
    grep -q '^# Depth: 2' manifest.fleet.tsv
}

@test "manifest init fleet --help: lists exit codes" {
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    run manifest_init_fleet --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Exit codes"
    echo "$output" | grep -q "TSV references"
}

# -----------------------------------------------------------------------------
# Live `gh` path coverage via PATH-prepended stub
# (tests/helpers/gh_stub.sh records calls; behaviour is env-driven).
# -----------------------------------------------------------------------------

@test "_manifest_gh_repo_create (live): invokes gh with --private --source --remote" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    git init -q "$SCRATCH/myrepo"
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true

    run _manifest_gh_repo_create "$SCRATCH/myrepo" "private"
    [ "$status" -eq 0 ]
    grep -q $'repo\tcreate\tmyrepo\t--private' "$MANIFEST_CLI_GH_STUB_LOG"
    grep -q -- "--remote=origin" "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "_manifest_gh_repo_create (live): uses github.owner and rejects inherited parent origins" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    git init -q "$SCRATCH"
    git -C "$SCRATCH" remote add origin git@github.com:example/parent.git
    mkdir -p "$SCRATCH/childrepo"
    export MANIFEST_CLI_GITHUB_OWNER=fidenceio
    gh_stub_install

    run _manifest_gh_repo_create "$SCRATCH/childrepo" "private"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not its own Git repository"* ]]
    ! grep -q $'repo\tcreate' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "_manifest_github_repo_target: rejects an invalid configured owner" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
    export MANIFEST_CLI_GITHUB_OWNER='bad/owner'

    run _manifest_github_repo_target "$SCRATCH/myrepo"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid github.owner"* ]]
}

@test "_manifest_gh_repo_create (live): returns 1 when gh repo create fails" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    git init -q "$SCRATCH/badrepo"
    gh_stub_install
    # Stub `gh auth status` succeeds (default 0); only `gh repo create` fails.
    export MANIFEST_CLI_GH_STUB_EXIT=1
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=0

    run _manifest_gh_repo_create "$SCRATCH/badrepo" "public"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "gh repo create failed"
    # Stub WAS invoked — proves we tried the live call rather than
    # short-circuiting on a guard.
    grep -q $'repo\tcreate\tbadrepo\t--public' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "_manifest_require_gh (live): returns 1 when gh auth status exits non-zero" {
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    gh_stub_install
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=1
    # Force re-check (don't use a memoized success from a prior session).
    unset _MANIFEST_GH_VALIDATED_AT

    run _manifest_require_gh
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "not authenticated"
}
