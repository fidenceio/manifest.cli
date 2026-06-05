#!/usr/bin/env bats
#
# §8.4b: config migration must back up before any in-place rewrite.
#
# Root cause this pins: _manifest_config_apply_migrations does sequential
# `yq -i` in-place writes against the live global config with NO backup. An
# interrupt (Ctrl-C/crash/disk-full) mid-rewrite, or a yq bug, destroys the
# user's only copy of their hand-tuned config.
#
# Fix: snapshot the config once (cp -p ... .bak.<timestamp>) immediately
# before the FIRST mutating write. Guarded by MANIFEST_CLI_CONFIG_SKIP_WRITES
# (no backup AND no mutation when set). Only back up when a migration will
# actually mutate (no spurious backups for no-op / dry-run). A failed backup
# aborts the migration (we will not rewrite with no safety net).

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not installed on host"
    SCRATCH="$(mk_scratch)"
    load_modules core/manifest-config.sh
    CFG="$SCRATCH/cfg.yaml"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "backup: a mutating migration snapshots the pre-migration file to .bak.*" {
    # Legacy default triggers a real mutation.
    printf 'time:\n  server1: time.apple.com\n' > "$CFG"
    local pre
    pre="$(cat "$CFG")"

    run _manifest_config_apply_migrations "$CFG" "false"
    [ "$status" -eq 0 ]

    # Exactly one backup created, and its contents equal the pre-migration file.
    local bak
    bak="$(ls "$CFG".bak.* 2>/dev/null | head -1)"
    [ -n "$bak" ]
    [ "$(cat "$bak")" = "$pre" ]

    # And the migration actually mutated the live file (sanity: backup wasn't a
    # copy of an already-migrated file).
    [ "$(get_yaml_value "$CFG" ".time.server1" "")" = "https://www.cloudflare.com/cdn-cgi/trace" ]
}

@test "backup: SKIP_WRITES creates no backup and performs no mutation" {
    printf 'time:\n  server1: time.apple.com\n' > "$CFG"
    local pre
    pre="$(cat "$CFG")"

    run env MANIFEST_CLI_CONFIG_SKIP_WRITES=1 \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh"; _manifest_config_apply_migrations "$2" "false"' \
        _ "$TEST_REPO_ROOT" "$CFG"
    [ "$status" -eq 0 ]

    # No backup file.
    ! ls "$CFG".bak.* >/dev/null 2>&1
    # No mutation: file byte-identical to the pre-migration content.
    [ "$(cat "$CFG")" = "$pre" ]
}

@test "backup: dry-run creates no backup and performs no mutation" {
    printf 'time:\n  server1: time.apple.com\n' > "$CFG"
    local pre
    pre="$(cat "$CFG")"

    run _manifest_config_apply_migrations "$CFG" "true"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "would-update"

    ! ls "$CFG".bak.* >/dev/null 2>&1
    [ "$(cat "$CFG")" = "$pre" ]
}

@test "backup: a no-op migration (nothing to mutate) creates no backup" {
    # Already-migrated, fully-populated config -> no actionable issues.
    cat > "$CFG" <<YAML
time:
  server1: https://www.cloudflare.com/cdn-cgi/trace
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600
config:
  schema_version: "${MANIFEST_CLI_CONFIG_SCHEMA_VERSION_CURRENT}"
YAML

    run _manifest_config_apply_migrations "$CFG" "false"
    [ "$status" -eq 0 ]
    ! ls "$CFG".bak.* >/dev/null 2>&1
}
