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

# A curated TSV in the canonical format, with a deliberately hand-edited
# REMOTE_URL on the first row (mirrors the real marketing.fidence case where
# the on-disk slug was renamed but the GitHub remote intentionally kept).
write_curated_tsv() {
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: $WS"
        echo "# Depth: 2"
        echo "# Last scanned: 2026-01-01T00:00:00Z"
        echo "# Canonical config: manifest.fleet.config.yaml"
        echo "# Toggle the SELECT column (true/false), then run: manifest init fleet"
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\talpha\tapps/alpha\tservice\ttrue\tgit@github.com:org/keep-this-url.git\tmain\n"
        printf "true\tbeta\tdb/beta\tservice\ttrue\t\tmain\n"
    } > "$WS/manifest.fleet.tsv"
}

# Discovered-inventory rows in the 9-field layout produced by
# discover_all_directories | filter_start_inventory_git_repos:
#   name  path  type  branch  version  url  is_submodule  has_git  has_remote
disc_row() {
    printf "%s\t%s\tservice\tmain\t\t%s\tfalse\ttrue\ttrue\n" "$1" "$2" "${3:-}"
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

    # The hand-edited URL on alpha survives — scan metadata must NOT clobber it.
    grep -q $'\talpha\tapps/alpha\tservice\ttrue\tgit@github.com:org/keep-this-url.git\tmain' "$WS/out.tsv"
    ! grep -q "SCANNED-OTHER" "$WS/out.tsv"

    # beta was NOT in the discovered set but must be preserved (not dropped).
    grep -q $'\tbeta\tdb/beta\t' "$WS/out.tsv"

    # gamma is appended as a new row.
    grep -q $'\tgamma\tdb/gamma\tservice\ttrue\tgit@github.com:org/gamma.git\tmain' "$WS/out.tsv"

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
    ! grep -q "2026-01-01T00:00:00Z" "$WS/out.tsv"     # stale timestamp replaced
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
