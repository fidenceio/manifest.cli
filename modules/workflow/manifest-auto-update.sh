#!/bin/bash

# Manifest Auto-Update Module
# Handles CLI updates, installation cleanup, and version management

# Auto-update module - uses PROJECT_ROOT from core module

# get_current_version() and get_latest_version() - Now available from manifest-shared-functions.sh

# Check if update is available
check_for_updates() {
    local current_version=$(get_current_version)
    local latest_version=$(get_latest_version)
    
    if [ "$current_version" = "unknown" ] || [ "$latest_version" = "unknown" ]; then
        log_warning "Could not determine version information"
        return 1
    fi
    
    if [ "$current_version" != "$latest_version" ]; then
        log_info "Update available: $current_version → $latest_version"
        return 0
    else
        log_success "Already up to date: $current_version"
        return 1
    fi
}

# Clean up old installation directories
cleanup_old_installation() {
    local project_dir="$HOME/.manifest-cli"
    local local_bin="$HOME/.local/bin"
    local cli_name="manifest"
    
    log_info "Cleaning up old installation..."
    
    # Clean up the old .manifest-cli directory
    if [ -d "$project_dir" ]; then
        log_info "Removing old installation directory: $project_dir"
        rm -rf "$project_dir"
        log_success "Old installation directory removed"
    else
        log_info "No old installation directory found"
    fi
    
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

# Install/update the CLI
install_cli() {
    local force_update="${1:-false}"
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
    if [ -f "$PROJECT_ROOT/manifest-cli-wrapper.sh" ]; then
        cp "$PROJECT_ROOT/manifest-cli-wrapper.sh" "$local_bin/$cli_name"
        chmod +x "$local_bin/$cli_name"
        log_success "CLI wrapper installed"
    else
        log_error "CLI wrapper not found at $PROJECT_ROOT/manifest-cli-wrapper.sh"
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
    local essential_files=("VERSION" ".gitignore" "README.md")
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
    
    # Create configuration file
    local config_file="$install_dir/.env"
    if [ ! -f "$config_file" ]; then
        cat > "$config_file" << EOF
# Manifest CLI Configuration
# Generated on $(date)

# Update settings
MANIFEST_CLI_AUTO_UPDATE=true
MANIFEST_CLI_UPDATE_COOLDOWN=30

# NTP settings
MANIFEST_CLI_NTP_TIMESTAMP=true
MANIFEST_CLI_NTP_SERVER1="time.apple.com"
MANIFEST_CLI_NTP_SERVER2="time.google.com"
MANIFEST_CLI_NTP_SERVER3="pool.ntp.org"
MANIFEST_CLI_NTP_TIMEOUT=3
MANIFEST_CLI_NTP_RETRIES=2

# Interactive mode
MANIFEST_CLI_INTERACTIVE_MODE=false

# Homebrew settings
MANIFEST_CLI_BREW_OPTION=enabled
MANIFEST_CLI_BREW_INTERACTIVE=no
MANIFEST_CLI_TAP_REPO="fidenceio/fidenceio-homebrew-tap"

# Repository settings
MANIFEST_CLI_REPO_URL="https://api.github.com/repos/fidenceio/fidenceio.manifest.cli"
EOF
        log_success "Configuration file created"
    fi
    
    log_success "CLI installation completed"
    return 0
}

# Auto-update check with cooldown
check_auto_update_internal() {
    # Check if auto-update is disabled
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
    
    # Only check for updates if cooldown period has passed
    if [ "$time_diff" -ge "$cooldown_minutes" ]; then
        log_info "Checking for updates..."
        if check_for_updates; then
            log_info "Update available! Run 'manifest update' to install"
        fi
        
        # Update last check time
        echo "$current_time" > "$last_check_file"
    fi
}

# Update CLI function
update_cli_internal() {
    local force_update="false"
    local check_only="false"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--force)
                force_update="true"
                shift
                ;;
            -c|--check)
                check_only="true"
                shift
                ;;
            -h|--help)
                echo "Manifest CLI Update Command"
                echo ""
                echo "Usage: manifest update [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -f, --force    Force update regardless of current version"
                echo "  -c, --check    Check for updates only (don't update)"
                echo "  -h, --help     Show this help message"
                echo ""
                echo "Examples:"
                echo "  manifest update              # Check and optionally update"
                echo "  manifest update --force      # Force update to latest version"
                echo "  manifest update --check      # Check version only"
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use 'manifest update --help' for usage information"
                return 1
                ;;
        esac
    done
    
    # Check for updates
    if ! check_for_updates && [ "$force_update" = "false" ]; then
        if [ "$check_only" = "true" ]; then
            log_success "No updates available"
        fi
        return 0
    fi
    
    if [ "$check_only" = "true" ]; then
        return 0
    fi
    
    # Perform update
    log_info "Updating Manifest CLI..."
    if install_cli "$force_update"; then
        log_success "Update completed successfully!"
        log_info "You may need to restart your terminal or run 'hash -r' to use the updated CLI"
    else
        log_error "Update failed"
        return 1
    fi
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "install")
            install_cli "${2:-false}" "${3:-$HOME/.manifest-cli}"
            ;;
        "update")
            update_cli_internal "${@:2}"
            ;;
        "check")
            check_for_updates
            ;;
        "cleanup")
            cleanup_old_installation
            ;;
        "version")
            echo "Current version: $(get_current_version)"
            echo "Latest version: $(get_latest_version)"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Auto-Update Module"
            echo "=========================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  install [force] [dir]  - Install or update the CLI"
            echo "  update [options]       - Update the CLI with options"
            echo "  check                  - Check for available updates"
            echo "  cleanup                - Clean up old installation files"
            echo "  version                - Show current and latest versions"
            echo "  help                   - Show this help"
            echo ""
            echo "Update Options:"
            echo "  -f, --force            - Force update regardless of version"
            echo "  -c, --check            - Check for updates only"
            echo "  -h, --help             - Show help"
            echo ""
            echo "Examples:"
            echo "  $0 install                    # Install CLI"
            echo "  $0 update --force             # Force update"
            echo "  $0 check                      # Check for updates"
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
