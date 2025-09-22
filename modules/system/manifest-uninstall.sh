#!/bin/bash

# Manifest Uninstall Module
# Handles complete removal of Manifest CLI installation

# Uninstall module - uses PROJECT_ROOT from core module

# Function to find all possible installation locations
find_installation_locations() {
    local locations=()
    
    # Check common installation locations
    local common_locations=(
        "/usr/local/share/manifest-cli"
        "/opt/manifest-cli"
        "$HOME/.local/share/manifest-cli"
        "$HOME/.manifest-cli"
    )
    
    # Add user-specified location if set
    if [ -n "$MANIFEST_INSTALL_LOCATION" ]; then
        common_locations+=("$MANIFEST_INSTALL_LOCATION")
    fi
    
    # Check which locations actually exist
    for location in "${common_locations[@]}"; do
        if [ -d "$location" ]; then
            locations+=("$location")
        fi
    done
    
    # Return found locations
    printf '%s\n' "${locations[@]}"
}

# Function to find CLI binary locations
find_cli_binaries() {
    local binaries=()
    
    # Check common binary locations
    local common_binaries=(
        "$HOME/.local/bin/manifest"
        "/usr/local/bin/manifest"
        "/opt/manifest-cli/bin/manifest"
    )
    
    # Check which binaries actually exist
    for binary in "${common_binaries[@]}"; do
        if [ -f "$binary" ]; then
            binaries+=("$binary")
        fi
    done
    
    # Return found binaries
    printf '%s\n' "${binaries[@]}"
}

# Function to remove installation directory
remove_installation_directory() {
    local install_dir="$1"
    
    if [ -d "$install_dir" ]; then
        echo "Removing installation directory: $install_dir"
        if rm -rf "$install_dir"; then
            echo "✅ Installation directory removed: $install_dir"
            return 0
        else
            echo "❌ Failed to remove installation directory: $install_dir"
            return 1
        fi
    else
        echo "No installation directory found at: $install_dir"
        return 0
    fi
}

# Function to remove CLI binary
remove_cli_binary() {
    local binary_path="$1"
    
    if [ -f "$binary_path" ]; then
        echo "Removing CLI binary: $binary_path"
        if rm -f "$binary_path"; then
            echo "✅ CLI binary removed: $binary_path"
            return 0
        else
            echo "❌ Failed to remove CLI binary: $binary_path"
            return 1
        fi
    else
        echo "No CLI binary found at: $binary_path"
        return 0
    fi
}

# Function to clean up configuration files
cleanup_config_files() {
    local config_files=(
        "$HOME/.manifestrc"
        "$HOME/.manifest-cli.conf"
        "$HOME/.config/manifest-cli"
        "$HOME/.env.manifest.global"
        "$HOME/.env.manifest.local"
    )
    
    local cleaned=0
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ] || [ -d "$config_file" ]; then
            echo "Removing config file: $config_file"
            if rm -rf "$config_file"; then
                echo "✅ Config file removed: $config_file"
                ((cleaned++))
            else
                echo "❌ Failed to remove config file: $config_file"
            fi
        fi
    done
    
    if [ $cleaned -eq 0 ]; then
        echo "No configuration files found to clean up"
    fi
}

# Function to clean up environment variables
cleanup_environment_variables() {
    echo "🧹 Cleaning up environment variables..."
    
    # Source the environment management module if available
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local modules_dir="$(dirname "$script_dir")"
    local env_management_module="$modules_dir/core/manifest-env-management.sh"
    
    if [ -f "$env_management_module" ]; then
        # Source shared utilities first
        if [ -f "$modules_dir/core/manifest-shared-utils.sh" ]; then
            source "$modules_dir/core/manifest-shared-utils.sh"
        fi
        
        # Source the environment management module
        source "$env_management_module"
        
        # Clean up all Manifest-related environment variables
        cleanup_all_manifest_env_vars
        
        # Remove Manifest variables from shell profile files
        remove_manifest_from_shell_profiles
        
        echo "✅ Environment variable cleanup completed"
    else
        echo "⚠️  Environment management module not found, skipping environment cleanup"
        echo "You may need to manually remove MANIFEST_* and MANIFEST_CLI_* variables from your shell profile"
    fi
}

# Main uninstall function
uninstall_manifest() {
    local skip_confirmations="${1:-false}"  # true = skip confirmation prompts
    local non_interactive="${2:-false}"    # true = run without user interaction
    
    echo "Starting Manifest CLI uninstall process..."
    
    # Find all installation locations
    local install_locations=($(find_installation_locations))
    local cli_binaries=($(find_cli_binaries))
    
    # Check if anything is installed
    if [ ${#install_locations[@]} -eq 0 ] && [ ${#cli_binaries[@]} -eq 0 ]; then
        echo "No Manifest CLI installation found"
        return 0
    fi
    
    # Show what will be removed
    echo "Found the following Manifest CLI installations:"
    for location in "${install_locations[@]}"; do
        echo "  📁 $location"
    done
    for binary in "${cli_binaries[@]}"; do
        echo "  🔧 $binary"
    done
    
    # Interactive confirmation unless forced
    if [ "$non_interactive" != "true" ] && [ "$skip_confirmations" != "true" ]; then
        echo ""
        read -p "Are you sure you want to uninstall Manifest CLI? (y/N): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Uninstall cancelled"
            return 0
        fi
    fi
    
    local errors=0
    
    # Remove installation directories
    for location in "${install_locations[@]}"; do
        if ! remove_installation_directory "$location"; then
            ((errors++))
        fi
    done
    
    # Remove CLI binaries
    for binary in "${cli_binaries[@]}"; do
        if ! remove_cli_binary "$binary"; then
            ((errors++))
        fi
    done
    
    # Clean up configuration files
    cleanup_config_files
    
    # Clean up environment variables
    cleanup_environment_variables
    
    # Summary
    if [ $errors -eq 0 ]; then
        echo "✅ Manifest CLI uninstalled successfully"
        echo ""
        echo "💡 Environment variables and shell profile entries have been cleaned up"
        echo "   You may need to restart your terminal or run 'source ~/.zshrc' (or equivalent)"
        return 0
    else
        echo "❌ Uninstall completed with $errors errors"
        return 1
    fi
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "uninstall")
            local skip_confirmations="${2:-false}"
            uninstall_manifest "$skip_confirmations" "false"
            ;;
        "force")
            uninstall_manifest "true" "true"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Uninstall Module"
            echo "========================"
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  uninstall [--force]  - Uninstall Manifest CLI (interactive)"
            echo "  force               - Force uninstall without confirmation"
            echo "  help                - Show this help"
            echo ""
            echo "Options:"
            echo "  --force             - Skip confirmation prompts"
            echo ""
            echo "Examples:"
            echo "  $0 uninstall        # Interactive uninstall"
            echo "  $0 uninstall --force # Force uninstall"
            echo "  $0 force            # Force uninstall (short form)"
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
