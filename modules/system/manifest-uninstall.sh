#!/bin/bash

# Manifest Uninstall Module
# Handles complete removal of Manifest CLI installation

# Uninstall module - uses PROJECT_ROOT from core module

# Check if manifest was installed via Homebrew
is_homebrew_installed() {
    command -v brew &>/dev/null && (brew list fidenceio/tap/manifest &>/dev/null || brew list manifest &>/dev/null)
}

# Function to find all possible installation locations
find_installation_locations() {
    local locations=()
    
    # Check installation locations (primary: ~/.manifest-cli, plus legacy for cleanup)
    local common_locations=(
        "$HOME/.manifest-cli"
        "/usr/local/share/manifest-cli"
    )
    
    # Add user-specified location if set (legacy + current env names)
    if [ -n "$MANIFEST_INSTALL_LOCATION" ]; then
        common_locations+=("$MANIFEST_INSTALL_LOCATION")
    fi
    if [ -n "$MANIFEST_CLI_INSTALL_DIR" ]; then
        common_locations+=("$MANIFEST_CLI_INSTALL_DIR")
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

    # Include resolved PATH binary when available (e.g., Homebrew /opt/homebrew/bin/manifest)
    local resolved_manifest=""
    resolved_manifest="$(command -v manifest 2>/dev/null || echo "")"
    if [ -n "$resolved_manifest" ] && [ -f "$resolved_manifest" ]; then
        local seen=false
        local existing=""
        for existing in "${binaries[@]}"; do
            if [ "$existing" = "$resolved_manifest" ]; then
                seen=true
                break
            fi
        done
        if [ "$seen" = "false" ]; then
            binaries+=("$resolved_manifest")
        fi
    fi
    
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

# Function to clean up configuration files and data directories
cleanup_config_files() {
    local global_yaml="$HOME/.manifest-cli/manifest.config.global.yaml"
    local config_files=(
        "$HOME/.manifestrc"
        "$HOME/.manifest-cli.conf"
        "$HOME/.config/manifest-cli"
        "$global_yaml"
    )

    # Data directories created at runtime by cloud/agent and time modules
    local data_dirs=(
        "$HOME/.manifest-agent"
    )

    # Time cache lives under $TMPDIR (or /tmp) — clean both possible locations
    local tmpdir_cache="${TMPDIR:-/tmp}/manifest-cli"
    local fallback_cache="/tmp/manifest-cli"
    data_dirs+=("$tmpdir_cache")
    if [[ "$fallback_cache" != "$tmpdir_cache" ]]; then
        data_dirs+=("$fallback_cache")
    fi

    # Gate deletion of the global YAML behind explicit double-confirm so the
    # uninstall workflow can't silently destroy user-customized settings.
    local skip_global_yaml=0
    if [ -f "$global_yaml" ]; then
        if type _confirm_global_config_write &>/dev/null; then
            if ! _confirm_global_config_write "delete" "$global_yaml" "uninstall removing user-customized global config"; then
                echo "ℹ️  Preserving global config: $global_yaml"
                skip_global_yaml=1
            fi
        fi
    fi

    local cleaned=0
    for config_file in "${config_files[@]}"; do
        if [ "$config_file" = "$global_yaml" ] && [ "$skip_global_yaml" -eq 1 ]; then
            continue
        fi
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

    for data_dir in "${data_dirs[@]}"; do
        if [ -d "$data_dir" ]; then
            echo "Removing data directory: $data_dir"
            if rm -rf "$data_dir"; then
                echo "✅ Data directory removed: $data_dir"
                ((cleaned++))
            else
                echo "❌ Failed to remove data directory: $data_dir"
            fi
        fi
    done

    if [ $cleaned -eq 0 ]; then
        echo "No configuration files or data directories found to clean up"
    fi
}

# Function to clean up environment variables AND shell-profile entries.
# Uninstall runs in its own process so unsetting in-memory MANIFEST_CLI_*
# vars affects nothing user-visible — but stripping any leftover lines from
# shell profiles is real cleanup the user benefits from.
cleanup_environment_variables() {
    echo "🧹 Cleaning up Manifest CLI shell-profile entries..."

    local shell_files=(
        "$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zsh_profile"
        "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"
    )
    local removed_count=0

    local profile_file backup_file temp_file
    for profile_file in "${shell_files[@]}"; do
        [ -f "$profile_file" ] || continue
        backup_file="${profile_file}.manifest-backup-$(date +%Y%m%d-%H%M%S)"
        cp "$profile_file" "$backup_file"
        temp_file=$(mktemp)
        # Remove any line that:
        #  - exports a MANIFEST_* variable
        #  - prepends .manifest-cli or .local/bin to PATH (installer-style)
        #  - sources a manifest-related rc file
        if grep -v -E '^[[:space:]]*(export[[:space:]]+MANIFEST_[A-Z_]+=|export[[:space:]]+PATH=.*\.manifest-cli|export[[:space:]]+PATH=.*\.local/bin.*PATH|(\.|source)[[:space:]]+.*manifest)' "$profile_file" > "$temp_file"; then
            if [ -s "$temp_file" ] && ! cmp -s "$profile_file" "$temp_file"; then
                mv "$temp_file" "$profile_file"
                echo "  ✅ Cleaned: $profile_file (backup: $backup_file)"
                ((removed_count++))
            else
                rm -f "$temp_file" "$backup_file"
            fi
        else
            rm -f "$temp_file" "$backup_file"
        fi
    done

    if [ $removed_count -eq 0 ]; then
        echo "  No Manifest CLI entries found in shell profiles"
    else
        echo "  ✅ Cleaned $removed_count shell profile(s) — restart your terminal to apply"
    fi

    # Best-effort in-process unset (not user-visible after process exits).
    local var
    for var in $(env | grep -E '^MANIFEST_(CLI_)?[A-Z_]+=' | cut -d'=' -f1); do
        unset "$var"
    done

    return 0
}

# Main uninstall function
uninstall_manifest() {
    local skip_confirmations="${1:-false}"  # true = skip confirmation prompts
    local non_interactive="${2:-false}"    # true = run without user interaction
    
    echo "Starting Manifest CLI uninstall process..."
    
    # Find all installation locations
    local install_locations=($(find_installation_locations))
    local cli_binaries=($(find_cli_binaries))
    local homebrew_installed=false
    if is_homebrew_installed; then
        homebrew_installed=true
    fi
    
    # Check if anything is installed
    if [ ${#install_locations[@]} -eq 0 ] && [ ${#cli_binaries[@]} -eq 0 ] && [ "$homebrew_installed" = "false" ]; then
        echo "No Manifest CLI installation found"
        return 0
    fi
    
    # Show what will be removed
    echo "Found the following Manifest CLI artifacts:"
    if [ "$homebrew_installed" = "true" ]; then
        echo "  🍺 Homebrew package: fidenceio/tap/manifest"
    fi
    for location in "${install_locations[@]}"; do
        if [[ "$location" == "$HOME/.manifest-cli" ]]; then
            echo "  📁 $location (state/data directory: logs, config markers)"
        else
            echo "  📁 $location"
        fi
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

    # Uninstall via Homebrew if that's how it was installed
    if [ "$homebrew_installed" = "true" ]; then
        echo "🍺 Homebrew installation detected — uninstalling via Homebrew..."
        if brew uninstall fidenceio/tap/manifest 2>/dev/null || brew uninstall manifest 2>/dev/null; then
            echo "✅ Homebrew package removed"
        else
            echo "⚠️  brew uninstall failed"
            ((errors++))
        fi
        if brew untap fidenceio/tap 2>/dev/null; then
            echo "✅ Homebrew tap removed"
        else
            echo "⚠️  brew untap failed (may already be untapped)"
        fi
    fi

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
