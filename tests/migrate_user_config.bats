#!/usr/bin/env bats
#
# §5.1: migrate_user_global_configuration was extracted out of install-cli.sh
# into scripts/migrate-user-config.sh; install-cli.sh sources/delegates to it.
# This locks in both the delegation wiring (the function is defined only in the
# extracted file and sourced by the installer) and that the extracted function
# still performs the safe key-level migration when sourced standalone.

load 'helpers/setup'

MIGRATE_SCRIPT="$TEST_REPO_ROOT/scripts/migrate-user-config.sh"
INSTALLER="$TEST_REPO_ROOT/install-cli.sh"

setup() {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed on host"
    fi
    load_modules
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME/.manifest-cli"
    CFG="$HOME/.manifest-cli/manifest.config.global.yaml"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- delegation wiring -------------------------------------------------------

@test "migrate: extracted script exists and is the sole definition site" {
    [ -f "$MIGRATE_SCRIPT" ]
    grep -qE '^[[:space:]]*migrate_user_global_configuration[[:space:]]*\(\)[[:space:]]*\{' "$MIGRATE_SCRIPT"
    # install-cli.sh must NOT define the function inline anymore.
    ! grep -qE '^[[:space:]]*migrate_user_global_configuration[[:space:]]*\(\)[[:space:]]*\{' "$INSTALLER"
}

@test "migrate: install-cli.sh sources the extracted script" {
    grep -qF 'scripts/migrate-user-config.sh' "$INSTALLER"
    # And still calls the function (delegation, not removal).
    grep -qE '^[[:space:]]*migrate_user_global_configuration[[:space:]]*$' "$INSTALLER"
}

@test "migrate: extracted script defines the function when sourced" {
    run bash -c "source '$MIGRATE_SCRIPT' && declare -F migrate_user_global_configuration"
    [ "$status" -eq 0 ]
}

# --- behavior (sourced standalone, no full installer) ------------------------

# Minimal sourcing context that the installer normally provides: the
# install-paths getter, the print_* helpers, MANIFEST_CLI_INSTALL_LOCATION,
# plus the YAML module (via load_modules) so get/set_yaml_value resolve.
_run_migration() {
    manifest_install_paths_user_global_config() { echo "$CFG"; }
    print_status()    { echo "[INFO] $1"; }
    print_success()   { echo "[SUCCESS] $1"; }
    print_warning()   { echo "[WARNING] $1"; }
    print_subheader() { echo "$1"; }
    MANIFEST_CLI_INSTALL_LOCATION="$HOME/.manifest-cli"
    # shellcheck disable=SC1090
    source "$MIGRATE_SCRIPT"
    migrate_user_global_configuration
}

@test "migrate: announces the safe-merge step and completes on a legacy config" {
    # A config carrying legacy defaults: the function announces the migration
    # step and runs to completion. (We assert the contract that is identical
    # across the extraction — the function entry/exit behavior — rather than
    # the post-write key values, which depend on the YAML writer and are
    # exercised by the yaml.bats suite.)
    cat > "$CFG" <<'EOF'
time:
  server1: time.apple.com
  server2: time.google.com
brew:
  tap_repo: "https://github.com/fidenceio/fidenceio-homebrew-tap.git"
EOF

    run _run_migration
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Migrating User Configuration"
}

@test "migrate: actually rewrites a legacy default end-to-end (leading-dot write path)" {
    # Regression: the migration reads with a leading-dot path (get_yaml_value,
    # fine) but also WROTE with a leading-dot path (set_yaml_value), which
    # silently no-op'd — yq rejected the ".." expression and 2>/dev/null ate it.
    # So on every upgrade the legacy time servers were never rewritten and the
    # cache controls were never added. The other migrate tests deliberately
    # defer post-write values to yaml.bats, so nothing here caught it. Assert the
    # rewrite happens.
    cat > "$CFG" <<'EOF'
time:
  server1: time.apple.com
EOF

    run _run_migration
    [ "$status" -eq 0 ]

    # Legacy default rewritten to the new endpoint...
    [ "$(get_yaml_value "$CFG" ".time.server1" "")" = "https://www.cloudflare.com/cdn-cgi/trace" ]
    # ...and the new cache controls added (were missing).
    [ "$(get_yaml_value "$CFG" ".time.cache_ttl" "")" = "120" ]
}

@test "migrate: preserves user-customized values" {
    cat > "$CFG" <<'EOF'
time:
  server1: https://my.internal.time/trace
  cache_ttl: 999
EOF

    run _run_migration
    [ "$status" -eq 0 ]

    [ "$(get_yaml_value "$CFG" ".time.server1" "")" = "https://my.internal.time/trace" ]
    [ "$(get_yaml_value "$CFG" ".time.cache_ttl" "")" = "999" ]
}

@test "migrate: no-op on an already-migrated config and a missing file" {
    # Already-migrated config: nothing to rewrite.
    cat > "$CFG" <<'EOF'
time:
  cache_ttl: 120
  cache_cleanup_period: 3600
  cache_stale_max_age: 21600
EOF
    run _run_migration
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "No user config migrations needed"

    # Missing config file: returns 0 without touching anything.
    rm -f "$CFG"
    run _run_migration
    [ "$status" -eq 0 ]
    [ ! -f "$CFG" ]
}
