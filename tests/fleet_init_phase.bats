#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    # The fleet-init wrapper lives here; pull it in so we can call the
    # internal helper directly.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"

    SCRATCH="$(mk_scratch)"
    cd "$SCRATCH"
}

teardown() {
    rm -rf "$SCRATCH"
}

# Build a TSV in fleet_start's exact format. Caller passes pairs of
# "select<TAB>name" rows; the SELECT column is whatever the caller wrote.
make_tsv() {
    local hash="$1"
    shift
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: /tmp/example | Depth: 2 | Date: 2026-04-25T00:00:00Z"
        echo "# Toggle the SELECT column (true/false), then run: manifest fleet init"
        echo "# DEFAULT-SELECT-HASH: $hash"
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        local row
        for row in "$@"; do
            local sel="${row%%|*}"
            local name="${row#*|}"
            printf "%s\t%s\t/tmp/%s\trepo\ttrue\t\tmain\t0.0.0\n" "$sel" "$name" "$name"
        done
    }
}

@test "stale-detection: unedited TSV (hash matches) is flagged stale" {
    # Compute the hash that fleet_start would have written for the default
    # selection pattern below (true / false).
    local default_hash
    default_hash="$(printf 'true\nfalse\n' | _manifest_hash_short)"

    make_tsv "$default_hash" "true|alpha" "false|beta" > "$SCRATCH/manifest.fleet.tsv"

    run _fleet_init_tsv_is_stale "$SCRATCH/manifest.fleet.tsv" "$SCRATCH/manifest.fleet.config.yaml"
    [ "$status" -eq 0 ]   # 0 = stale (unedited)
}

@test "stale-detection: edited TSV (one row flipped) is NOT flagged stale" {
    local default_hash
    default_hash="$(printf 'true\nfalse\n' | _manifest_hash_short)"

    # Same default hash, but the data rows have been flipped — user edited.
    make_tsv "$default_hash" "false|alpha" "true|beta" > "$SCRATCH/manifest.fleet.tsv"

    run _fleet_init_tsv_is_stale "$SCRATCH/manifest.fleet.tsv" "$SCRATCH/manifest.fleet.config.yaml"
    [ "$status" -eq 1 ]   # 1 = edited
}

@test "stale-detection: TSV without DEFAULT-SELECT-HASH header is NOT flagged stale" {
    # Old-format TSV (no fingerprint header).
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: /tmp | Depth: 2 | Date: 2026-04-25T00:00:00Z"
        printf "# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH\tVERSION\n"
        printf "true\talpha\t/tmp/alpha\trepo\ttrue\t\tmain\t0.0.0\n"
    } > "$SCRATCH/manifest.fleet.tsv"

    run _fleet_init_tsv_is_stale "$SCRATCH/manifest.fleet.tsv" "$SCRATCH/manifest.fleet.config.yaml"
    [ "$status" -eq 1 ]   # not flagged — back-compat with pre-#15 TSVs
}

@test "stale-detection: existing fleet config short-circuits to 'not stale'" {
    local default_hash
    default_hash="$(printf 'true\n' | _manifest_hash_short)"

    make_tsv "$default_hash" "true|alpha" > "$SCRATCH/manifest.fleet.tsv"
    : > "$SCRATCH/manifest.fleet.config.yaml"

    run _fleet_init_tsv_is_stale "$SCRATCH/manifest.fleet.tsv" "$SCRATCH/manifest.fleet.config.yaml"
    [ "$status" -eq 1 ]
}

@test "stale-detection: missing TSV returns not-stale" {
    run _fleet_init_tsv_is_stale "$SCRATCH/does-not-exist.tsv" "$SCRATCH/manifest.fleet.config.yaml"
    [ "$status" -eq 1 ]
}

@test "_manifest_hash_short produces stable output" {
    local h1 h2
    h1="$(printf 'hello\n' | _manifest_hash_short)"
    h2="$(printf 'hello\n' | _manifest_hash_short)"
    [ -n "$h1" ]
    [ "$h1" = "$h2" ]

    # Different input -> different hash.
    local h3
    h3="$(printf 'world\n' | _manifest_hash_short)"
    [ "$h1" != "$h3" ]
}
