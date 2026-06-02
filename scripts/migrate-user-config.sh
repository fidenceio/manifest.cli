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
        set_yaml_value "$config_file" ".time.server1" "https://www.cloudflare.com/cdn-cgi/trace"
        migrated=$((migrated + 1))
    fi
    if [ "$time2" = "time.google.com" ] || [ "$time2" = "216.239.35.4" ]; then
        set_yaml_value "$config_file" ".time.server2" "https://www.google.com/generate_204"
        migrated=$((migrated + 1))
    fi
    if [ "$time3" = "pool.ntp.org" ]; then
        set_yaml_value "$config_file" ".time.server3" "https://www.apple.com"
        migrated=$((migrated + 1))
    fi
    if [ "$time4" = "time.nist.gov" ]; then
        set_yaml_value "$config_file" ".time.server4" ""
        migrated=$((migrated + 1))
    fi
    if [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ]; then
        set_yaml_value "$config_file" ".brew.tap_repo" "https://github.com/fidenceio/homebrew-tap.git"
        migrated=$((migrated + 1))
    fi

    # Ensure new cache controls exist.
    local cache_ttl cache_cleanup cache_stale
    cache_ttl=$(get_yaml_value "$config_file" ".time.cache_ttl" "")
    if [ -z "$cache_ttl" ]; then
        set_yaml_value "$config_file" ".time.cache_ttl" "120"
        migrated=$((migrated + 1))
    fi
    cache_cleanup=$(get_yaml_value "$config_file" ".time.cache_cleanup_period" "")
    if [ -z "$cache_cleanup" ]; then
        set_yaml_value "$config_file" ".time.cache_cleanup_period" "3600"
        migrated=$((migrated + 1))
    fi
    cache_stale=$(get_yaml_value "$config_file" ".time.cache_stale_max_age" "")
    if [ -z "$cache_stale" ]; then
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
