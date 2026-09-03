#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    # The fleet-init wrapper lives here; pull it in so we can call the
    # internal helper directly.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet-detect.sh"

    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH-home"
    mkdir -p "$HOME"
    export HOME SCRATCH
    cd "$SCRATCH"
}

teardown() {
    rm -rf "$SCRATCH"
    rm -rf "$SCRATCH-home"
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
cred_url()   { printf 'https://%s:%s@example.com/org/%s.git' "ci-bot" "$(cred_token)" "${1:-repo}"; }

# Build a TSV in fleet_start's exact format. Caller passes pairs of
# "select<TAB>name" rows; the SELECT column is whatever the caller wrote.
make_tsv() {
    local hash="$1"
    shift
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: /tmp/example"
        echo "# Depth: 2"
        echo "# Last scanned: 2026-04-25T00:00:00Z"
        echo "# Canonical config: manifest.fleet.config.yaml"
        echo "# Toggle the SELECT column (true/false) — update/ship/status honor it directly. (manifest init fleet is the first-time scaffold step only.)"
        echo "# DEFAULT-SELECT-HASH: $hash"
        # Deliberately the PRE-§45 header, with an empty REMOTE_URL cell. These
        # stale-detection tests are the standing proof that a roster written by
        # an older CLI still parses — readers take column positions from the
        # file's own header. Do not "modernise" this fixture; that coverage goes
        # with it. Rosters this suite asserts NEW writes against use the current
        # header (see the schema tests below).
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        local row
        for row in "$@"; do
            local sel="${row%%|*}"
            local name="${row#*|}"
            printf "%s\t%s\t/tmp/%s\ttrue\t\tmain\n" "$sel" "$name" "$name"
        done
    }
}

run_manifest() {
    run bash -c '
        export MANIFEST_CLI_CORE_MODULES_DIR="$TEST_REPO_ROOT/modules"
        source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
        source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
        source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"
        cd "$SCRATCH"
        manifest_init_fleet "$@"
    ' bash "$@"
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

@test "init fleet phase 1 defaults to compact repo-depth TSV" {
    mkdir -p "$SCRATCH/apps/web/src" "$SCRATCH/services/api/internal"

    run_manifest -y

    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/manifest.fleet.tsv" ]
    grep -q $'\tapps/web\t' "$SCRATCH/manifest.fleet.tsv"
    grep -q $'\tservices/api\t' "$SCRATCH/manifest.fleet.tsv"
    refute grep -q $'\tapps\t' "$SCRATCH/manifest.fleet.tsv"
    refute grep -q $'\tapps/web/src\t' "$SCRATCH/manifest.fleet.tsv"
    [[ "$output" == *"Inventory mode: repo-depth prompts"* ]]
    [[ "$output" == *"Listed in TSV:"*"2"* ]]
}

@test "init fleet phase 1 TSV uses freshness metadata instead of VERSION column" {
    mkdir -p "$SCRATCH/apps/web"

    run_manifest -y

    [ "$status" -eq 0 ]
    grep -q '^# Last scanned: ' "$SCRATCH/manifest.fleet.tsv"
    refute grep -q '^# Generated by:' "$SCRATCH/manifest.fleet.tsv"
    grep -q '^# Canonical config: manifest.fleet.config.yaml$' "$SCRATCH/manifest.fleet.tsv"
    grep -q $'^# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH$' "$SCRATCH/manifest.fleet.tsv"
    refute grep -q $'^# SELECT\tNAME\tPATH\tTYPE\tHAS_GIT\tREMOTE_URL\tBRANCH$' "$SCRATCH/manifest.fleet.tsv"
}

# §45: the roster must not carry a remote URL at all — it is a committed file,
# and a credentialed URL in it is published irrecoverably. The header assertion
# above states the schema; this one states the consequence, so a writer that
# re-adds the column under a different name still fails.
@test "init fleet phase 1 TSV records no remote URL for any member" {
    mkdir -p "$SCRATCH/apps/web"
    git -C "$SCRATCH/apps/web" init -q
    git -C "$SCRATCH/apps/web" remote add origin "$(cred_url web)"

    run_manifest -y

    [ "$status" -eq 0 ]
    # Positive control: the member IS in the roster, so a null result below
    # would be visible rather than passing vacuously.
    grep -q $'\tapps/web\t' "$SCRATCH/manifest.fleet.tsv"
    refute grep -q "$(cred_token)" "$SCRATCH/manifest.fleet.tsv"
    refute grep -q 'example.com/org/web.git' "$SCRATCH/manifest.fleet.tsv"
}

@test "merge_update_tsv preserves selected root workspace row" {
    cat > "$SCRATCH/manifest.fleet.tsv" <<'TSV'
# SELECT	NAME	PATH	HAS_GIT	BRANCH
true	rootworkspace	.	true	main
TSV
    local discovered
    discovered="$(printf "svc\tservices/api\tmain\t1.0.0\tgit@example.com:org/api.git\tfalse\ttrue\ttrue\n")"

    merge_update_tsv "$discovered" "$SCRATCH/manifest.fleet.tsv" "$SCRATCH" 5 > "$SCRATCH/merged.tsv" 2>/dev/null

    grep -q $'^true\trootworkspace\t.\ttrue\tmain$' "$SCRATCH/merged.tsv"
    grep -q $'^true\tsvc\tservices/api\ttrue\tmain$' "$SCRATCH/merged.tsv"
}

# A roster written before §45 still has REMOTE_URL between HAS_GIT and BRANCH.
# Regenerating must read it by header — not by position — or the stored URL is
# carried into the BRANCH column, which is a wrong value rather than an error.
@test "merge_update_tsv regenerate drops a legacy REMOTE_URL column without shifting BRANCH" {
    {
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"
        printf "true\trootworkspace\t.\ttrue\t%s\trelease\n" "$(cred_url root)"
    } > "$SCRATCH/manifest.fleet.tsv"
    local discovered
    discovered="$(printf "svc\tservices/api\tmain\t1.0.0\t\tfalse\ttrue\ttrue\n")"

    merge_update_tsv "$discovered" "$SCRATCH/manifest.fleet.tsv" "$SCRATCH" 5 > "$SCRATCH/merged.tsv" 2>/dev/null

    grep -q $'^# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH$' "$SCRATCH/merged.tsv"
    # The branch survives as the branch — the control that fails if the reader
    # is positional, because it would have found the URL in that column.
    grep -q $'^true\trootworkspace\t.\ttrue\trelease$' "$SCRATCH/merged.tsv"
    refute grep -q "$(cred_token)" "$SCRATCH/merged.tsv"
}

@test "merge_update_tsv keeps empty TSV fields aligned" {
    : > "$SCRATCH/manifest.fleet.tsv"
    local discovered
    discovered="$(printf "plain\tservices/plain\t\t0.0.0\t\tfalse\tfalse\tfalse\n")"

    merge_update_tsv "$discovered" "$SCRATCH/manifest.fleet.tsv" "$SCRATCH" 5 > "$SCRATCH/merged.tsv" 2>/dev/null

    [ "$(awk -F '\t' '$2 == "plain" {print $4 "|" $5}' "$SCRATCH/merged.tsv")" = "false|" ]
}

@test "init fleet --all-folders writes exhaustive TSV" {
    mkdir -p "$SCRATCH/apps/web/src"

    run_manifest --all-folders --depth 3 -y

    [ "$status" -eq 0 ]
    [ -f "$SCRATCH/manifest.fleet.tsv" ]
    grep -q $'\tapps\t' "$SCRATCH/manifest.fleet.tsv"
    grep -q $'\tapps/web\t' "$SCRATCH/manifest.fleet.tsv"
    grep -q $'\tapps/web/src\t' "$SCRATCH/manifest.fleet.tsv"
    [[ "$output" == *"Inventory mode: all scanned folders"* ]]
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
