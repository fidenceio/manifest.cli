#!/bin/bash

# Manifest Auto-Upgrade Module
# Handles CLI upgrades, installation cleanup, and version management

# Auto-upgrade module - uses PROJECT_ROOT from core module

# get_current_version() and get_latest_version() - Now available from manifest-shared-functions.sh

manifest_upgrade_sed_inplace() {
    case "$OSTYPE" in
        darwin*|freebsd*|openbsd*|netbsd*)
            sed -i '' "$@" ;;
        *)
            sed -i "$@" ;;
    esac
}

manifest_upgrade_upsert_env_key() {
    local file="$1"
    local key="$2"
    local value="$3"

    [ -f "$file" ] || return 1

    if grep -Eq "^[[:space:]]*${key}=" "$file"; then
        manifest_upgrade_sed_inplace "s|^[[:space:]]*${key}=.*|${key}=${value}|" "$file"
    else
        printf '%s=%s\n' "$key" "$value" >> "$file"
    fi
}

migrate_user_global_config_internal() {
    local config_file="$HOME/.env.manifest.global"
    [ -f "$config_file" ] || return 0

    local time1 time2 time3 time4 time_servers tap_repo
    time1=$(awk -F= '/^[[:space:]]*MANIFEST_CLI_TIME_SERVER1=/{print $2}' "$config_file" | tail -n1)
    time2=$(awk -F= '/^[[:space:]]*MANIFEST_CLI_TIME_SERVER2=/{print $2}' "$config_file" | tail -n1)
    time3=$(awk -F= '/^[[:space:]]*MANIFEST_CLI_TIME_SERVER3=/{print $2}' "$config_file" | tail -n1)
    time4=$(awk -F= '/^[[:space:]]*MANIFEST_CLI_TIME_SERVER4=/{print $2}' "$config_file" | tail -n1)
    time_servers=$(awk -F= '/^[[:space:]]*MANIFEST_CLI_TIME_SERVERS=/{print $2}' "$config_file" | tail -n1)
    tap_repo=$(awk -F= '/^[[:space:]]*MANIFEST_CLI_TAP_REPO=/{print $2}' "$config_file" | tail -n1)

    # Safe migrations for known legacy defaults only.
    { [ "$time1" = "time.apple.com" ] || [ "$time1" = "216.239.35.0" ]; } && manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_SERVER1" "https://www.cloudflare.com/cdn-cgi/trace"
    { [ "$time2" = "time.google.com" ] || [ "$time2" = "216.239.35.4" ]; } && manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_SERVER2" "https://www.google.com/generate_204"
    [ "$time3" = "pool.ntp.org" ] && manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_SERVER3" "https://www.apple.com"
    [ "$time4" = "time.nist.gov" ] && manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_SERVER4" ""
    [ "$tap_repo" = "https://github.com/fidenceio/fidenceio-homebrew-tap.git" ] && \
        manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TAP_REPO" "https://github.com/fidenceio/homebrew-tap.git"

    # Add new cache keys if missing.
    grep -Eq "^[[:space:]]*MANIFEST_CLI_TIME_CACHE_TTL=" "$config_file" || \
        manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_CACHE_TTL" "120"
    grep -Eq "^[[:space:]]*MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD=" "$config_file" || \
        manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD" "3600"
    grep -Eq "^[[:space:]]*MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE=" "$config_file" || \
        manifest_upgrade_upsert_env_key "$config_file" "MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE" "21600"

    if [ -n "$time_servers" ]; then
        log_warning "Deprecated variable detected in ~/.env.manifest.global: MANIFEST_CLI_TIME_SERVERS"
        log_warning "Use MANIFEST_CLI_TIME_SERVER1..4 instead (legacy value preserved)"
    fi
}

# Check if upgrade is available
check_for_upgrades() {
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    if [ "$current_version" = "unknown" ] || [ "$latest_version" = "unknown" ]; then
        log_warning "Could not determine version information"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        log_info "Upgrade available: $current_version → $latest_version"
        return 0
    else
        log_success "Already up to date: $current_version"
        return 1
    fi
}

# Clean up old installation artifacts (binaries and legacy system install).
# NOTE: ~/.manifest-cli is the runtime state/data directory (logs, config
# markers, etc.) and is intentionally preserved during upgrades.
cleanup_old_installation() {
    local local_bin="$HOME/.local/bin"
    local cli_name="manifest"

    log_info "Cleaning up old installation..."

    # Clean up any old CLI binary
    if [ -f "$local_bin/$cli_name" ]; then
        log_info "Removing old CLI binary: $local_bin/$cli_name"
        rm -f "$local_bin/$cli_name"
        log_success "Old CLI binary removed"
    fi

    # Clean up any old installation in /usr/local/share
    local old_install_dir="/usr/local/share/manifest-cli"
    if [ -d "$old_install_dir" ]; then
        # Validate path before sudo operations to prevent privilege escalation
        if [[ "$old_install_dir" =~ ^/usr/local/share/manifest-cli ]] && [ -d "$old_install_dir" ]; then
            log_info "Removing old system installation: $old_install_dir"
            sudo rm -rf "$old_install_dir" 2>/dev/null || {
                log_warning "Could not remove system installation (may require sudo)"
            }
        else
            log_error "Invalid installation directory path: $old_install_dir"
            return 1
        fi
    fi
}

# Install/upgrade the CLI
install_cli() {
    local force_upgrade="${1:-false}"
    local install_dir="${2:-$HOME/.manifest-cli}"
    local local_bin="$HOME/.local/bin"
    local cli_name="manifest"
    
    log_info "Installing Manifest CLI..."
    
    # Clean up old installation first
    cleanup_old_installation
    
    # Create installation directory
    mkdir -p "$install_dir"
    mkdir -p "$local_bin"
    
    # Copy CLI wrapper
    if [ -f "$PROJECT_ROOT/scripts/manifest-cli-wrapper.sh" ]; then
        cp "$PROJECT_ROOT/scripts/manifest-cli-wrapper.sh" "$local_bin/$cli_name"
        chmod +x "$local_bin/$cli_name"
        log_success "CLI wrapper installed"
    else
        log_error "CLI wrapper not found at $PROJECT_ROOT/scripts/manifest-cli-wrapper.sh"
        return 1
    fi
    
    # Copy source modules
    if [ -d "$PROJECT_ROOT/modules" ]; then
        cp -r "$PROJECT_ROOT/modules" "$install_dir/"
        log_success "Source modules copied"
    else
        log_error "Modules directory not found at $PROJECT_ROOT/modules"
        return 1
    fi
    
    # Copy essential files
    local essential_files=("VERSION" ".gitignore" "README.md" "CHANGELOG.md")
    for file in "${essential_files[@]}"; do
        if [ -f "$PROJECT_ROOT/$file" ]; then
            cp "$PROJECT_ROOT/$file" "$install_dir/"
            log_success "Copied $file"
        fi
    done

    # Copy documentation
    if [ -d "$PROJECT_ROOT/docs" ]; then
        cp -r "$PROJECT_ROOT/docs" "$install_dir/"
        log_success "Documentation copied"
    fi

    # Copy examples (config templates, fleet examples)
    if [ -d "$PROJECT_ROOT/examples" ]; then
        cp -r "$PROJECT_ROOT/examples" "$install_dir/"
        log_success "Examples copied"
    fi
    
    # Create configuration file
    local config_file="$install_dir/.env"
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
# Manifest CLI Configuration
# Generated on $(date)

# Upgrade settings
MANIFEST_CLI_AUTO_UPDATE=true
MANIFEST_CLI_UPDATE_COOLDOWN=30

# Time server settings
MANIFEST_CLI_TIME_TIMESTAMP=true
MANIFEST_CLI_TIME_SERVER1="https://www.cloudflare.com/cdn-cgi/trace"
MANIFEST_CLI_TIME_SERVER2="https://www.google.com/generate_204"
MANIFEST_CLI_TIME_SERVER3="https://www.apple.com"
MANIFEST_CLI_TIME_TIMEOUT=5
MANIFEST_CLI_TIME_RETRIES=2

# Interactive mode
MANIFEST_CLI_INTERACTIVE_MODE=false

# Homebrew settings
MANIFEST_CLI_BREW_OPTION=enabled
MANIFEST_CLI_BREW_INTERACTIVE=no
MANIFEST_CLI_TAP_REPO="https://github.com/fidenceio/homebrew-tap.git"

# Repository settings
MANIFEST_CLI_REPO_URL="https://api.github.com/repos/fidenceio/fidenceio.manifest.cli"
EOF
        log_success "Configuration file created"
    fi
    
    log_success "CLI installation completed"
    return 0
}

# Auto-upgrade check with cooldown
check_auto_upgrade_internal() {
    # Check if auto-upgrade is disabled
    if [ "${MANIFEST_CLI_AUTO_UPDATE:-true}" = "false" ]; then
        return 0
    fi
    
    local last_check_file="$PROJECT_ROOT/.manifest_last_update"
    local cooldown_minutes="${MANIFEST_CLI_UPDATE_COOLDOWN:-30}"
    local current_time=$(date +%s)
    local last_check_time=0
    
    # Read last check time if file exists
    if [ -f "$last_check_file" ]; then
        last_check_time=$(cat "$last_check_file" 2>/dev/null || echo "0")
    fi
    
    # Calculate time difference in minutes
    local time_diff=$(( (current_time - last_check_time) / 60 ))
    
    # Only check for upgrades if cooldown period has passed
    if [ "$time_diff" -ge "$cooldown_minutes" ]; then
        log_info "Checking for upgrades..."
        if check_for_upgrades; then
            log_info "Upgrade available! Run 'manifest upgrade' to install"
        fi
        
        # Update last check time
        echo "$current_time" > "$last_check_file"
    fi
}

# Upgrade CLI function
upgrade_cli_internal() {
    local force_upgrade="false"
    local check_only="false"
    local brew_formula_ref="fidenceio/tap/manifest"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_upgrade="true"
                shift
                ;;
            -c|--check)
                check_only="true"
                shift
                ;;
            -h|--help)
                echo "Manifest CLI Upgrade Command"
                echo ""
                echo "Usage: manifest upgrade [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -f, --force    Force upgrade regardless of current version"
                echo "  -c, --check    Check for upgrades only (don't upgrade)"
                echo "  -h, --help     Show this help message"
                echo ""
                echo "Examples:"
                echo "  manifest upgrade             # Check and optionally upgrade"
                echo "  manifest upgrade --force     # Force upgrade to latest version"
                echo "  manifest upgrade --check     # Check version only"
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use 'manifest upgrade --help' for usage information"
                return 1
                ;;
        esac
    done
    
    # Check for upgrades
    if ! check_for_upgrades && [ "$force_upgrade" = "false" ]; then
        if [ "$check_only" = "true" ]; then
            log_success "No upgrades available"
            return 0
        fi

        # Even on a no-op upgrade request, force Homebrew post-install hooks
        # so migrations still run through the canonical upgrade pathway.
        if is_homebrew_installed; then
            if brew postinstall "$brew_formula_ref" || brew postinstall manifest; then
                log_info "Ran Homebrew post-install migrations."
            else
                log_warning "Homebrew post-install hook failed; applying internal safe migrations instead."
                migrate_user_global_config_internal
            fi
        else
            migrate_user_global_config_internal
        fi
        log_success "Already up-to-date. Verified safe configuration migrations."
        return 0
    fi
    
    if [ "$check_only" = "true" ]; then
        return 0
    fi
    
    # Perform upgrade
    log_info "Upgrading Manifest CLI..."

    # Route through Homebrew if that's how it was installed
    if is_homebrew_installed; then
        log_info "🍺 Homebrew installation detected — upgrading via Homebrew..."
        if brew update && (brew upgrade "$brew_formula_ref" || brew upgrade manifest); then
            if brew postinstall "$brew_formula_ref" || brew postinstall manifest; then
                log_info "Ran Homebrew post-install migrations."
            else
                log_warning "Homebrew post-install hook failed; applying internal safe migrations instead."
                migrate_user_global_config_internal
            fi
            log_success "Upgrade completed successfully via Homebrew!"
        else
            log_error "Homebrew upgrade failed"
            return 1
        fi
    elif install_cli "$force_upgrade"; then
        migrate_user_global_config_internal
        log_success "Upgrade completed successfully!"
        log_info "You may need to restart your terminal or run 'hash -r' to use the upgraded CLI"
    else
        log_error "Upgrade failed"
        return 1
    fi
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "install")
            install_cli "${2:-false}" "${3:-$HOME/.manifest-cli}"
            ;;
        "update"|"upgrade")
            upgrade_cli_internal "${@:2}"
            ;;
        "check")
            check_for_upgrades
            ;;
        "cleanup")
            cleanup_old_installation
            ;;
        "version")
            echo "Current version: $(get_current_version)"
            echo "Latest version: $(get_latest_version)"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Auto-Upgrade Module"
            echo "=========================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  install [force] [dir]  - Install or upgrade the CLI"
            echo "  upgrade [options]      - Upgrade the CLI with options"
            echo "  update [options]       - Deprecated alias for upgrade"
            echo "  check                  - Check for available upgrades"
            echo "  cleanup                - Clean up old installation files"
            echo "  version                - Show current and latest versions"
            echo "  help                   - Show this help"
            echo ""
            echo "Upgrade Options:"
            echo "  -f, --force            - Force upgrade regardless of version"
            echo "  -c, --check            - Check for upgrades only"
            echo "  -h, --help             - Show help"
            echo ""
            echo "Examples:"
            echo "  $0 install                    # Install CLI"
            echo "  $0 upgrade --force            # Force upgrade"
            echo "  $0 check                      # Check for upgrades"
            echo "  $0 cleanup                    # Clean old files"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
