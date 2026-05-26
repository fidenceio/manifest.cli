#!/bin/bash

# Manifest Uninstall Module
# Handles complete removal of Manifest CLI installation

# Uninstall module - uses PROJECT_ROOT from core module

# Source the install-paths module so this module never hardcodes filesystem
# locations. Required dependency — the module must be present alongside this
# file in any complete checkout.
# shellcheck source=manifest-install-paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/manifest-install-paths.sh"

# Check if manifest was installed via Homebrew
is_homebrew_installed() {
    command -v brew &>/dev/null && \
        (brew list "$(manifest_install_paths_homebrew_formula)" &>/dev/null || brew list manifest &>/dev/null)
}

# Function to find all possible installation locations
find_installation_locations() {
    local locations=() location
    while IFS= read -r location; do
        [ -n "$location" ] || continue
        if [ -d "$location" ]; then
            locations+=("$location")
        fi
    done < <(manifest_install_paths_install_dirs)
    printf '%s\n' "${locations[@]}"
}

# Function to find CLI binary locations
_manifest_uninstall_resolve_path() {
    local path="$1"
    if command -v realpath >/dev/null 2>&1; then
        realpath "$path" 2>/dev/null && return 0
    fi
    echo "$path"
}

_manifest_uninstall_binary_is_owned() {
    local binary_path="$1"
    [ -f "$binary_path" ] || return 1

    # Fast-path: if the candidate matches one of the canonical install paths
    # (or the configured binary location), trust it without marker grep.
    local candidate
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if [ "$binary_path" = "$candidate" ]; then
            return 0
        fi
    done < <(manifest_install_paths_binary_candidates)
    local configured_bin="${MANIFEST_CLI_CORE_BINARY_LOCATION:-}/manifest"
    if [ -n "${MANIFEST_CLI_CORE_BINARY_LOCATION:-}" ] && [ "$binary_path" = "$configured_bin" ]; then
        return 0
    fi

    local resolved_binary
    resolved_binary="$(_manifest_uninstall_resolve_path "$binary_path")"

    local install_location resolved_location
    while IFS= read -r install_location; do
        [ -n "$install_location" ] || continue
        resolved_location="$(_manifest_uninstall_resolve_path "$install_location")"
        case "$resolved_binary" in
            "$resolved_location"/*)
                return 0
                ;;
        esac
    done < <(find_installation_locations)

    # Homebrew/manual wrappers are text scripts with Manifest-specific markers.
    # Avoid deleting unrelated runner/system tools that only share the name.
    grep -a -E 'Manifest CLI|manifest-cli|MANIFEST_CLI' "$binary_path" >/dev/null 2>&1
}

find_cli_binaries() {
    local binaries=() binary
    while IFS= read -r binary; do
        [ -n "$binary" ] || continue
        if _manifest_uninstall_binary_is_owned "$binary"; then
            binaries+=("$binary")
        fi
    done < <(manifest_install_paths_binary_candidates)

    # Include resolved PATH binary when available (e.g., Homebrew /opt/homebrew/bin/manifest)
    local resolved_manifest=""
    resolved_manifest="$(command -v manifest 2>/dev/null || echo "")"
    if [ -n "$resolved_manifest" ] && _manifest_uninstall_binary_is_owned "$resolved_manifest"; then
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

_manifest_uninstall_print_artifact_plan() {
    local indent="${1:-  }"
    local install_locations=($(find_installation_locations))
    local cli_binaries=($(find_cli_binaries))
    local homebrew_installed=false
    if is_homebrew_installed; then
        homebrew_installed=true
    fi

    local profile_regex
    profile_regex="$(manifest_install_paths_profile_line_regex)"

    local found=0
    if [ "$homebrew_installed" = "true" ]; then
        echo "${indent}Would uninstall Homebrew package: $(manifest_install_paths_homebrew_formula)"
        echo "${indent}Would untap Homebrew tap: $(manifest_install_paths_homebrew_tap)"
        found=1
    fi

    local location binary config_file data_dir profile_file
    for location in "${install_locations[@]}"; do
        echo "${indent}Would remove installation directory: $location"
        found=1
    done
    for binary in "${cli_binaries[@]}"; do
        echo "${indent}Would remove CLI binary: $binary"
        found=1
    done
    while IFS= read -r config_file; do
        [ -n "$config_file" ] || continue
        if [ -f "$config_file" ] || [ -d "$config_file" ]; then
            echo "${indent}Would remove config artifact: $config_file"
            found=1
        fi
    done < <(manifest_install_paths_config_files)
    while IFS= read -r data_dir; do
        [ -n "$data_dir" ] || continue
        if [ -d "$data_dir" ]; then
            echo "${indent}Would remove data directory: $data_dir"
            found=1
        fi
    done < <(manifest_install_paths_data_dirs)
    while IFS= read -r profile_file; do
        [ -n "$profile_file" ] || continue
        if [ -f "$profile_file" ] && grep -q -E "$profile_regex" "$profile_file"; then
            echo "${indent}Would remove Manifest entries from shell profile: $profile_file"
            found=1
        fi
    done < <(manifest_install_paths_shell_profiles)

    if [ "$found" -eq 0 ]; then
        echo "${indent}No Manifest CLI installation artifacts detected."
    fi
}

preview_uninstall_manifest() {
    local replay_command="${1:-manifest uninstall -y}"

    if type manifest_execution_preview_header >/dev/null 2>&1; then
        manifest_execution_preview_header "manifest uninstall"
    else
        echo "Preview - no changes written: manifest uninstall"
    fi
    _manifest_uninstall_print_artifact_plan "  "
    if type manifest_execution_footer >/dev/null 2>&1; then
        manifest_execution_footer "$replay_command"
    else
        echo ""
        echo "No changes written. Re-run with -y to apply this plan:"
        echo "  $replay_command"
    fi
}

preview_reinstall_manifest() {
    local replay_command="${1:-manifest reinstall -y}"

    if type manifest_execution_preview_header >/dev/null 2>&1; then
        manifest_execution_preview_header "manifest reinstall"
    else
        echo "Preview - no changes written: manifest reinstall"
    fi
    echo "Would run uninstall cleanup phase:"
    _manifest_uninstall_print_artifact_plan "  "
    echo ""
    if command -v brew >/dev/null 2>&1; then
        echo "Would reinstall through Homebrew:"
        echo "  brew tap $(manifest_install_paths_homebrew_tap)"
        echo "  brew reinstall $(manifest_install_paths_homebrew_formula) || brew reinstall manifest"
    else
        echo "Would reinstall through the manual installer if the Manifest Cloud installer module is available."
    fi
    if type manifest_execution_footer >/dev/null 2>&1; then
        manifest_execution_footer "$replay_command"
    else
        echo ""
        echo "No changes written. Re-run with -y to apply this plan:"
        echo "  $replay_command"
    fi
}

# Function to remove installation directory
remove_installation_directory() {
    local install_dir="$1"

    if [ -d "$install_dir" ]; then
        manifest_install_paths_assert_destructive_target_safe "$install_dir" "rm install-dir" || return 1
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
        manifest_install_paths_assert_destructive_target_safe "$binary_path" "rm cli-binary" || return 1
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
    local skip_confirmations="${1:-false}"
    local global_yaml
    global_yaml="$(manifest_install_paths_user_global_config)"

    # Gate deletion of the global YAML behind explicit double-confirm so the
    # uninstall workflow can't silently destroy user-customized settings.
    local skip_global_yaml=0
    if [ -f "$global_yaml" ] && [ "$skip_confirmations" != "true" ]; then
        if type _confirm_global_config_write &>/dev/null; then
            if ! _confirm_global_config_write "delete" "$global_yaml" "uninstall removing user-customized global config"; then
                echo "ℹ️  Preserving global config: $global_yaml"
                skip_global_yaml=1
            fi
        fi
    fi

    local cleaned=0 config_file data_dir
    while IFS= read -r config_file; do
        [ -n "$config_file" ] || continue
        if [ "$config_file" = "$global_yaml" ] && [ "$skip_global_yaml" -eq 1 ]; then
            continue
        fi
        if [ -f "$config_file" ] || [ -d "$config_file" ]; then
            if ! manifest_install_paths_assert_destructive_target_safe "$config_file" "rm config"; then
                continue
            fi
            echo "Removing config file: $config_file"
            if rm -rf "$config_file"; then
                echo "✅ Config file removed: $config_file"
                ((cleaned+=1))
            else
                echo "❌ Failed to remove config file: $config_file"
            fi
        fi
    done < <(manifest_install_paths_config_files)

    while IFS= read -r data_dir; do
        [ -n "$data_dir" ] || continue
        if [ -d "$data_dir" ]; then
            if ! manifest_install_paths_assert_destructive_target_safe "$data_dir" "rm data-dir"; then
                continue
            fi
            echo "Removing data directory: $data_dir"
            if rm -rf "$data_dir"; then
                echo "✅ Data directory removed: $data_dir"
                ((cleaned+=1))
            else
                echo "❌ Failed to remove data directory: $data_dir"
            fi
        fi
    done < <(manifest_install_paths_data_dirs)

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
    manifest_install_paths_cleanup_profile_entries 1 1
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
        echo "  🍺 Homebrew package: $(manifest_install_paths_homebrew_formula)"
    fi
    local state_dir
    state_dir="$(manifest_install_paths_global_state_dir)"
    for location in "${install_locations[@]}"; do
        if [[ "$location" == "$state_dir" ]]; then
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
        if ! manifest_install_paths_assert_destructive_brew_safe "brew uninstall manifest"; then
            echo "⚠️  brew uninstall skipped by sandbox tripwire"
            ((errors+=1))
        else
            local brew_formula brew_tap
            brew_formula="$(manifest_install_paths_homebrew_formula)"
            brew_tap="$(manifest_install_paths_homebrew_tap)"
            echo "🍺 Homebrew installation detected — uninstalling via Homebrew..."
            if brew uninstall "$brew_formula" 2>/dev/null || brew uninstall manifest 2>/dev/null; then
                echo "✅ Homebrew package removed"
            else
                echo "⚠️  brew uninstall failed"
                ((errors+=1))
            fi
            if brew untap "$brew_tap" 2>/dev/null; then
                echo "✅ Homebrew tap removed"
            else
                echo "⚠️  brew untap failed (may already be untapped)"
            fi
        fi
    fi

    # Remove installation directories
    for location in "${install_locations[@]}"; do
        if ! remove_installation_directory "$location"; then
            ((errors+=1))
        fi
    done
    
    # Remove CLI binaries
    for binary in "${cli_binaries[@]}"; do
        if ! remove_cli_binary "$binary"; then
            ((errors+=1))
        fi
    done
    
    # Clean up configuration files
    cleanup_config_files "$skip_confirmations"
    
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
