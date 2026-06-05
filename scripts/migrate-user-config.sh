#!/bin/bash
# Manifest CLI — user global-config migration.
#
# Extracted from install-cli.sh (§5.1): applies safe, key-level migrations to
# the user's global YAML config on every install/upgrade run. Pure-data
# migration — only known legacy defaults are rewritten; user-customized values
# are preserved. install-cli.sh sources this file and calls
# migrate_user_global_configuration during setup_global_configuration.
#
# Dependencies provided by the sourcing installer context:
#   - print_subheader / print_success / print_status / print_warning  (install-cli.sh)
#   - manifest_install_paths_user_global_config                       (manifest-install-paths.sh)
#   - MANIFEST_CLI_INSTALL_LOCATION                                   (install-cli.sh global)
# get_yaml_value / set_yaml_value are sourced on demand from the YAML module.

migrate_user_global_configuration() {
    local config_file
    config_file="$(manifest_install_paths_user_global_config)"
    [ -f "$config_file" ] || return 0

    # §8.4b: MANIFEST_CLI_CONFIG_SKIP_WRITES is the global "do not touch the
    # config" contract. Honor it before any backup or rewrite — no snapshot and
    # no in-place mutation when writes are suppressed.
    case "${MANIFEST_CLI_CONFIG_SKIP_WRITES:-0}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
    esac

    # Source the YAML module for get_yaml_value / set_yaml_value.
    # This file lives in scripts/, so the source-tree modules root is its parent
    # directory — keep resolving to the repo root the same way install-cli.sh did.
    local yaml_module
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    yaml_module="$script_dir/modules/core/manifest-yaml.sh"
    if [[ -f "$yaml_module" ]]; then
        source "$yaml_module"
    elif [[ -f "$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh" ]]; then
        source "$MANIFEST_CLI_INSTALL_LOCATION/modules/core/manifest-yaml.sh"
    else
        print_warning "⚠️  YAML module not found, skipping configuration migration"
        return 0
    fi

    print_subheader "🧭 Migrating User Configuration (Safe Merge)"

    local migrated=0
    # §8.4b: snapshot the live config once, lazily, immediately before the FIRST
    # in-place (`yq -i`) write. Up to 8 sequential set_yaml_value rewrites run
    # against the user's only copy of their hand-tuned global config; an
    # interrupt/crash/disk-full mid-rewrite (or a yq bug) would destroy it. We
    # back up only when a migration will actually mutate (no spurious backups),
    # honor MANIFEST_CLI_CONFIG_SKIP_WRITES (no backup when writes are skipped),
    # and treat a failed backup as FATAL — the point is not to lose the file.
    local backed_up=0

    # Lazily snapshot the config before the first mutating write. Returns 0 if a
    # backup exists/was made; 1 if it could not be made and the caller must
    # abort. (SKIP_WRITES is handled by the early return above, so by the time
    # we get here a rewrite is genuinely about to happen.)
    _migrate_backup_before_first_write() {
        [ "$backed_up" -eq 1 ] && return 0
        local stamp backup_file
        stamp="$(date +%Y%m%d_%H%M%S)"
        backup_file="${config_file}.bak.${stamp}"
        if cp -p "$config_file" "$backup_file" 2>/dev/null; then
            print_warning "🛟  Backed up config before migration: $backup_file"
            backed_up=1
            return 0
        fi
        print_warning "⚠️  Could not back up config before migration: $config_file — aborting to avoid data loss."
        return 1
    }

    # get_yaml_value with explicit "" default keeps the migration safe under
    # `set -e`: a missing key returns "" rc=0 rather than rc=1, which would
    # otherwise abort the installer on a fresh config file that doesn't yet
    # carry the legacy keys this function is checking for.
    local time1 time2 time3 time4 tap_repo
    time1=$(get_yaml_value "$config_file" ".time.server1" "")
    time2=$(get_yaml_value "$config_file" ".time.server2" "")
    time3=$(get_yaml_value "$config_file" ".time.server3" "")
    time4=$(get_yaml_value "$config_file" ".time.server4" "")
    tap_repo=$(get_yaml_value "$config_file" ".brew.tap_repo" "")

    # Migrate only known legacy defaults; preserve user custom values.
    if [ "$time1" = "time.apple.com" ] || [ "$time1" = "216.239.35.0" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.server1" "https://www.cloudflare.com/cdn-cgi/trace"
        migrated=$((migrated + 1))
    fi
    if [ "$time2" = "time.google.com" ] || [ "$time2" = "216.239.35.4" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.server2" "https://www.google.com/generate_204"
        migrated=$((migrated + 1))
    fi
    if [ "$time3" = "pool.ntp.org" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.server3" "https://www.apple.com"
        migrated=$((migrated + 1))
    fi
    if [ "$time4" = "time.nist.gov" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.server4" ""
        migrated=$((migrated + 1))
    fi
    if [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".brew.tap_repo" "https://github.com/fidenceio/homebrew-tap.git"
        migrated=$((migrated + 1))
    fi

    # Ensure new cache controls exist.
    local cache_ttl cache_cleanup cache_stale
    cache_ttl=$(get_yaml_value "$config_file" ".time.cache_ttl" "")
    if [ -z "$cache_ttl" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.cache_ttl" "120"
        migrated=$((migrated + 1))
    fi
    cache_cleanup=$(get_yaml_value "$config_file" ".time.cache_cleanup_period" "")
    if [ -z "$cache_cleanup" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.cache_cleanup_period" "3600"
        migrated=$((migrated + 1))
    fi
    cache_stale=$(get_yaml_value "$config_file" ".time.cache_stale_max_age" "")
    if [ -z "$cache_stale" ]; then
        _migrate_backup_before_first_write || return 1
        set_yaml_value "$config_file" ".time.cache_stale_max_age" "21600"
        migrated=$((migrated + 1))
    fi

    if [ "$migrated" -gt 0 ]; then
        print_success "✅ Migrated $migrated configuration setting(s) in $config_file"
    else
        print_status "ℹ️  No user config migrations needed"
    fi
    echo ""
}
