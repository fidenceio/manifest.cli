#!/bin/bash

# =============================================================================
# Manifest CLI Environment Variable Management
# =============================================================================
# Handles cleanup and management of environment variables for the Manifest CLI
# =============================================================================

# Function to get all MANIFEST_* environment variables
get_manifest_env_vars() {
    # Get all environment variables that start with MANIFEST_
    env | grep -E '^MANIFEST_[A-Z_]+=' | cut -d'=' -f1 | sort
}

# Function to get all MANIFEST_CLI_* environment variables
get_manifest_cli_env_vars() {
    # Get all environment variables that start with MANIFEST_CLI_
    env | grep -E '^MANIFEST_CLI_[A-Z_]+=' | cut -d'=' -f1 | sort
}

# Function to unset all MANIFEST_* environment variables
unset_manifest_env_vars() {
    local vars_to_unset=($(get_manifest_env_vars))
    local unset_count=0
    
    if [ ${#vars_to_unset[@]} -eq 0 ]; then
        echo "No MANIFEST_* environment variables found to unset"
        return 0
    fi
    
    echo "Found ${#vars_to_unset[@]} MANIFEST_* environment variables to unset:"
    for var in "${vars_to_unset[@]}"; do
        echo "  - $var"
        unset "$var"
        ((unset_count++))
    done
    
    echo "✅ Unset $unset_count MANIFEST_* environment variables"
    return 0
}

# Function to unset all MANIFEST_CLI_* environment variables
unset_manifest_cli_env_vars() {
    local vars_to_unset=($(get_manifest_cli_env_vars))
    local unset_count=0
    
    if [ ${#vars_to_unset[@]} -eq 0 ]; then
        echo "No MANIFEST_CLI_* environment variables found to unset"
        return 0
    fi
    
    echo "Found ${#vars_to_unset[@]} MANIFEST_CLI_* environment variables to unset:"
    for var in "${vars_to_unset[@]}"; do
        echo "  - $var"
        unset "$var"
        ((unset_count++))
    done
    
    echo "✅ Unset $unset_count MANIFEST_CLI_* environment variables"
    return 0
}

# Function to clean up all Manifest CLI-related environment variables
cleanup_all_manifest_env_vars() {
    echo "🧹 Cleaning up all Manifest CLI-related environment variables..."
    
    # Unset old MANIFEST_* variables
    unset_manifest_env_vars
    
    # Unset new MANIFEST_CLI_* variables
    unset_manifest_cli_env_vars
    
    echo "✅ Environment variable cleanup completed"
}

# Function to remove Manifest environment variables from shell profile files
remove_manifest_from_shell_profiles() {
    local shell_files=()
    local removed_count=0
    
    # Detect shell and determine profile files
    if [ -n "$ZSH_VERSION" ]; then
        shell_files=("$HOME/.zshrc" "$HOME/.zprofile" "$HOME/.zsh_profile")
    elif [ -n "$BASH_VERSION" ]; then
        shell_files=("$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile")
    else
        # Try common shell profile files
        shell_files=("$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile")
    fi
    
    echo "🔍 Checking shell profile files for Manifest CLI environment variables..."
    
    for profile_file in "${shell_files[@]}"; do
        if [ -f "$profile_file" ]; then
            echo "Checking $profile_file..."
            
            # Create backup
            local backup_file="${profile_file}.manifest-backup-$(date +%Y%m%d-%H%M%S)"
            cp "$profile_file" "$backup_file"
            echo "Created backup: $backup_file"
            
            # Remove lines containing MANIFEST_* variable exports
            local temp_file=$(mktemp)
            if grep -v -E '^[[:space:]]*export[[:space:]]+MANIFEST_[A-Z_]+=' "$profile_file" > "$temp_file"; then
                if [ -s "$temp_file" ] && ! cmp -s "$profile_file" "$temp_file"; then
                    mv "$temp_file" "$profile_file"
                    echo "✅ Removed Manifest CLI environment variables from $profile_file"
                    ((removed_count++))
                else
                    rm -f "$temp_file"
                    echo "No Manifest CLI environment variables found in $profile_file"
                fi
            else
                rm -f "$temp_file"
                echo "⚠️  Failed to process $profile_file"
            fi
        fi
    done
    
    if [ $removed_count -gt 0 ]; then
        echo "✅ Removed Manifest CLI environment variables from $removed_count shell profile files"
        echo "💡 You may need to restart your terminal or run 'source ~/.zshrc' (or equivalent) to apply changes"
    else
        echo "No Manifest CLI environment variables found in shell profile files"
    fi
}

# Function to display current Manifest environment variables
display_manifest_env_vars() {
    echo "📋 Current Manifest CLI environment variables:"
    
    local manifest_vars=($(get_manifest_env_vars))
    local manifest_cli_vars=($(get_manifest_cli_env_vars))
    
    if [ ${#manifest_vars[@]} -gt 0 ]; then
        echo "  MANIFEST_* variables:"
        for var in "${manifest_vars[@]}"; do
            echo "    $var=${!var}"
        done
    fi
    
    if [ ${#manifest_cli_vars[@]} -gt 0 ]; then
        echo "  MANIFEST_CLI_* variables:"
        for var in "${manifest_cli_vars[@]}"; do
            echo "    $var=${!var}"
        done
    fi
    
    if [ ${#manifest_vars[@]} -eq 0 ] && [ ${#manifest_cli_vars[@]} -eq 0 ]; then
        echo "No Manifest CLI environment variables currently set"
    fi
}

# Function to export environment variables from configuration file
export_env_from_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        echo "Configuration file not found: $config_file"
        return 1
    fi
    
    echo "📥 Loading environment variables from $config_file..."
    
    local exported_count=0
    local line_number=0
    
    while IFS= read -r line; do
        ((line_number++))
        
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        
        # Check if line contains an environment variable assignment
        if [[ "$line" =~ ^[A-Z_][A-Z0-9_]*= ]]; then
            local var_name="${line%%=*}"
            local var_value="${line#*=}"
            
            # Remove quotes if present
            var_value="${var_value%\"}"
            var_value="${var_value#\"}"
            var_value="${var_value%\'}"
            var_value="${var_value#\'}"
            
            # Export the variable
            export "$var_name"="$var_value"
            ((exported_count++))
            echo "Exported $var_name"
        fi
    done < "$config_file"
    
    echo "✅ Exported $exported_count environment variables from $config_file"
    return 0
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "cleanup")
            cleanup_all_manifest_env_vars
            remove_manifest_from_shell_profiles
            ;;
        "unset-old")
            unset_manifest_env_vars
            ;;
        "unset-new")
            unset_manifest_cli_env_vars
            ;;
        "show")
            display_manifest_env_vars
            ;;
        "export")
            local config_file="${2:-}"
            if [ -z "$config_file" ]; then
                log_error "Configuration file path required"
                echo "Usage: $0 export <config_file>"
                return 1
            fi
            export_env_from_config "$config_file"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Environment Variable Management"
            echo "========================================"
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  cleanup              - Clean up all Manifest environment variables"
            echo "  unset-old            - Unset old MANIFEST_* variables only"
            echo "  unset-new            - Unset new MANIFEST_CLI_* variables only"
            echo "  show                 - Display current Manifest environment variables"
            echo "  export <config_file> - Export variables from configuration file"
            echo "  help                 - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 cleanup           # Clean up all Manifest variables"
            echo "  $0 show              # Show current variables"
            echo "  $0 export .env.manifest.global  # Load from config file"
            ;;
        *)
            echo "Unknown command: $1"
            echo "Run '$0 help' for usage information"
            return 1
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
