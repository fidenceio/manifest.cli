#!/usr/bin/env bats
#
# `manifest update fleet` default behavior (two guarantees):
#   1. DEPTH    — with no explicit --depth, rescan at the depth that PRODUCED
#                 the existing TSV (its "# Depth:" header) for a reproducible
#                 re-scan; a fresh `auto` resolve is used only when no TSV exists.
#   2. EDIT     — the TSV is edited in place: existing rows are preserved
#                 verbatim (order + content, including hand-edited columns) and
#                 only newly discovered repos are appended. Never overwrite,
#                 reorder, or drop curated rows.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    WS="$SCRATCH/ws"
    mkdir -p "$WS"
    # manifest-fleet.sh self-sources detect (sentinel-guarded).
    load_modules "fleet/manifest-fleet-detect.sh" "fleet/manifest-fleet.sh"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_FLEET_ROOT HOME WS
}

mkrepo() { mkdir -p "$1" && git init -q "$1"; }

# A curated TSV in the canonical format, with a deliberately hand-edited BRANCH
# on the first row: the scan reports `main` for it, so anything that re-derived
# the row from scan metadata would overwrite `release` and fail the assertion.
#
# That column used to be a hand-edited REMOTE_URL. §45 removed the column from
# the schema entirely (the roster is committed and pushed, so a credentialed URL
# in it is published irrecoverably) — the "curated column survives a rescan"
# property is unchanged, it is just demonstrated on a column that still exists.
# The legacy shape is exercised by its own migration test below.
write_curated_tsv() {
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: $WS"
        echo "# Depth: 2"
        echo "# Last scanned: 2026-01-01T00:00:00Z"
        echo "# Canonical config: manifest.fleet.config.yaml"
        echo "# Toggle the SELECT column (true/false) — update/ship/status honor it directly. (manifest init fleet is the first-time scaffold step only.)"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n"
        printf "true\talpha\tapps/alpha\ttrue\trelease\n"
        printf "true\tbeta\tdb/beta\ttrue\t\n"
    } > "$WS/manifest.fleet.tsv"
}

# A credentialed URL and its token, assembled at runtime from harmless parts.
#
# Same convention as credential_url_redaction.bats, and it is not cosmetic: the
# pre-commit hook's §45 backstop refuses to stage ANY file containing the
# `scheme://<user>:<pass>@` shape, and it deliberately has no test-fixture
# exemption. A guard with a carve-out for the files most likely to carry the
# forbidden thing is a hiding place — so the fixtures assemble instead, and the
# guard keeps exactly one rule for every file in the tree.
cred_token() { printf 'tok%s' "1234567890"; }
cred_url()   { printf 'https://%s:%s@github.com/org/alpha.git' "ci-bot" "$(cred_token)"; }

# The same roster as it was written by a CLI older than the §45 fix: one extra
# column, carrying a credential on the first row.
write_legacy_tsv() {
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: $WS"
        echo "# Depth: 2"
        echo "# Last scanned: 2026-01-01T00:00:00Z"
        echo "# Canonical config: manifest.fleet.config.yaml"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\talpha\tapps/alpha\ttrue\t%s\trelease\n" "$(cred_url)"
        printf "false\tbeta\tdb/beta\ttrue\t\tmain\n"
    } > "$WS/manifest.fleet.tsv"
}

# Discovered-inventory rows in the 8-field layout produced by
# discover_all_directories | filter_start_inventory_git_repos:
#   name  path  branch  version  url  is_submodule  has_git  has_remote
disc_row() {
    printf "%s\t%s\tmain\t\t%s\tfalse\ttrue\ttrue\n" "$1" "$2" "${3:-}"
}

# =============================================================================
# (2) EDIT IN PLACE — merge_update_tsv (append mode)
# =============================================================================

@test "append: preserves existing rows verbatim and appends only new repos" {
    write_curated_tsv
    local discovered
    discovered="$(
        disc_row alpha apps/alpha "git@github.com:org/SCANNED-OTHER.git"  # re-found, different url
        disc_row gamma db/gamma   "git@github.com:org/gamma.git"          # genuinely new
    )"

    local err
    err="$(merge_update_tsv "$discovered" "$WS/manifest.fleet.tsv" "$WS" 2 append 2>&1 > "$WS/out.tsv")"

    # The hand-edited branch on alpha survives — the scan says `main` for it, so
    # a row re-derived from scan metadata would read `main` here and fail.
    grep -q $'\talpha\tapps/alpha\ttrue\trelease' "$WS/out.tsv"
    refute grep -q "SCANNED-OTHER" "$WS/out.tsv"

    # beta was NOT in the discovered set but must be preserved (not dropped).
    grep -q $'\tbeta\tdb/beta\t' "$WS/out.tsv"

    # gamma is appended as a new row.
    grep -q $'\tgamma\tdb/gamma\ttrue\tmain' "$WS/out.tsv"

    # alpha appears exactly once (no duplicate from the re-discovery).
    [ "$(grep -c $'\talpha\tapps/alpha\t' "$WS/out.tsv")" -eq 1 ]

    # Exactly one repo appended.
    [[ "$err" == *"NEW:1"* ]]

    # Order preserved: alpha, then beta, then the appended gamma.
    run bash -c "grep -n $'\\\\t\\\\(alpha\\\\|beta\\\\|gamma\\\\)\\\\t' '$WS/out.tsv' | cut -d: -f2 | awk -F'\\t' '{print \$2}'"
    [ "${lines[0]}" = "alpha" ]
    [ "${lines[1]}" = "beta" ]
    [ "${lines[2]}" = "gamma" ]
}

@test "append: preserves the # Depth header and refreshes # Last scanned" {
    write_curated_tsv
    local discovered; discovered="$(disc_row gamma db/gamma)"
    merge_update_tsv "$discovered" "$WS/manifest.fleet.tsv" "$WS" 2 append 2>/dev/null > "$WS/out.tsv"

    grep -q "^# Depth: 2$" "$WS/out.tsv"               # depth header untouched
    refute grep -q "2026-01-01T00:00:00Z" "$WS/out.tsv"     # stale timestamp replaced
    grep -q "^# Last scanned: " "$WS/out.tsv"          # ... with a fresh one
}

@test "append: is idempotent when nothing new is discovered (NEW:0)" {
    write_curated_tsv
    local before; before="$(grep -v '^# Last scanned:' "$WS/manifest.fleet.tsv")"
    local discovered; discovered="$(disc_row alpha apps/alpha)"  # already listed

    local err
    err="$(merge_update_tsv "$discovered" "$WS/manifest.fleet.tsv" "$WS" 2 append 2>&1 > "$WS/out.tsv")"

    [[ "$err" == *"NEW:0"* ]]
    # Every line except the refreshed timestamp is unchanged.
    [ "$(grep -v '^# Last scanned:' "$WS/out.tsv")" = "$before" ]
}

# =============================================================================
# (2b) LEGACY MIGRATION — §45
# =============================================================================
# Append mode preserves every existing line byte-for-byte, which is exactly why
# it needed an exception: a credential committed before the fix would otherwise
# be re-emitted, re-staged and re-pushed by every subsequent `manifest update`.
# Verbatim preservation would have preserved the leak.

@test "append: migrates a legacy roster off the REMOTE_URL column" {
    write_legacy_tsv
    local discovered; discovered="$(disc_row gamma db/gamma)"

    local err
    err="$(merge_update_tsv "$discovered" "$WS/manifest.fleet.tsv" "$WS" 2 append 2>&1 > "$WS/out.tsv")"

    # The header is rewritten to the current schema...
    grep -q $'^# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH$' "$WS/out.tsv"
    # ...and the credential is gone from the file entirely.
    refute grep -q "$(cred_token)" "$WS/out.tsv"
    refute grep -q 'REMOTE_URL' "$WS/out.tsv"

    # Everything the migration is NOT allowed to touch. Without these the test
    # would pass against a migration that simply emptied the file.
    grep -q $'^true\talpha\tapps/alpha\ttrue\trelease$' "$WS/out.tsv"
    grep -q $'^false\tbeta\tdb/beta\ttrue\tmain$' "$WS/out.tsv"
    grep -q "^# Depth: 2$" "$WS/out.tsv"
    [[ "$err" == *"NEW:1"* ]]
    [[ "$err" == *"MIGRATED:2"* ]]
}

@test "append: reports no migration for a roster already on the current schema" {
    # The negative control for the test above: MIGRATED must not be emitted for
    # every append, or it says nothing when it IS emitted.
    write_curated_tsv
    local discovered; discovered="$(disc_row gamma db/gamma)"

    local err
    err="$(merge_update_tsv "$discovered" "$WS/manifest.fleet.tsv" "$WS" 2 append 2>&1 > "$WS/out.tsv")"

    [[ "$err" == *"NEW:1"* ]]
    [[ "$err" != *"MIGRATED"* ]]
}

# =============================================================================
# (1) DEPTH — fleet_update reuses the TSV's recorded depth by default
# =============================================================================

@test "depth: default update reuses the TSV's recorded # Depth (finds deep repos)" {
    mkrepo "$WS/alpha"            # repo at depth 1 — `auto` would settle here
    mkrepo "$WS/group/deepsvc"    # repo at depth 2 — only seen with depth >= 2
    write_curated_tsv             # records "# Depth: 2"
    export MANIFEST_CLI_FLEET_ROOT="$WS"

    run fleet_update -q
    [ "$status" -eq 0 ]
    [[ "$output" == *"deepsvc"* ]]
}

@test "depth: without a TSV, default update falls back to auto (reaches deepest)" {
    mkrepo "$WS/alpha"
    mkrepo "$WS/group/deepsvc"
    # No manifest.fleet.tsv — nothing to read a depth from; auto is per-branch
    # adaptive and resolves to the deepest repo (depth 2), so deepsvc is found.
    export MANIFEST_CLI_FLEET_ROOT="$WS"

    run fleet_update -q
    [ "$status" -eq 0 ]
    [[ "$output" == *"alpha"* ]]
    [[ "$output" == *"deepsvc"* ]]
}

@test "depth: an explicit --depth still overrides the recorded header" {
    mkrepo "$WS/alpha"
    mkrepo "$WS/group/deepsvc"
    write_curated_tsv                # records "# Depth: 2"
    export MANIFEST_CLI_FLEET_ROOT="$WS"

    run fleet_update -q --depth 1    # explicit shallow scan wins
    [ "$status" -eq 0 ]
    [[ "$output" != *"deepsvc"* ]]
}
