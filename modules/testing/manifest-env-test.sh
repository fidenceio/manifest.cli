#!/bin/bash

# Manifest Environment Variables Test Module
# Displays all global environment variables for the user

# Environment test module - uses PROJECT_ROOT from core module

# Display all global environment variables
show_global_env_vars() {
    echo "🌍 Global Environment Variables"
    echo "================================"
    echo ""
    
    # Get all environment variables and sort them
    local env_vars=$(env | sort)
    
    # Count total variables
    local total_count=$(echo "$env_vars" | wc -l)
    echo "📊 Total environment variables: $total_count"
    echo ""
    
    # Show all variables
    echo "$env_vars"
    echo ""
}

# Display only MANIFEST-related environment variables
show_manifest_env_vars() {
    echo "🔧 Manifest CLI Environment Variables"
    echo "====================================="
    echo ""
    
    # Get all MANIFEST-related variables
    local manifest_vars=$(env | grep -i "^MANIFEST" | sort)
    
    if [ -n "$manifest_vars" ]; then
        local count=$(echo "$manifest_vars" | wc -l)
        echo "📊 Found $count Manifest-related environment variables:"
        echo ""
        echo "$manifest_vars"
    else
        echo "❌ No Manifest-related environment variables found"
    fi
    echo ""
}

# Display only MANIFEST_CLI_ prefixed variables
show_manifest_cli_env_vars() {
    echo "🎯 Manifest CLI Namespaced Environment Variables"
    echo "==============================================="
    echo ""
    
    # Get all MANIFEST_CLI_ prefixed variables
    local cli_vars=$(env | grep "^MANIFEST_CLI_" | sort)
    
    if [ -n "$cli_vars" ]; then
        local count=$(echo "$cli_vars" | wc -l)
        echo "📊 Found $count MANIFEST_CLI_ prefixed variables:"
        echo ""
        echo "$cli_vars"
    else
        echo "❌ No MANIFEST_CLI_ prefixed variables found"
    fi
    echo ""
}

# Display system information
show_system_info() {
    echo "🖥️  System Information"
    echo "====================="
    echo ""
    echo "OS: $(uname -s)"
    echo "Architecture: $(uname -m)"
    echo "Shell: $SHELL"
    echo "User: $USER"
    echo "Home: $HOME"
    echo "PWD: $PWD"
    echo ""
}

# Display shell-specific information
show_shell_info() {
    echo "🐚 Shell Information"
    echo "==================="
    echo ""
    echo "Shell: $SHELL"
    echo "Shell Version: $($SHELL --version 2>/dev/null | head -n1 || echo "Unknown")"
    echo "Bash Version: $(bash --version 2>/dev/null | head -n1 || echo "Not available")"
    echo "Zsh Version: $(zsh --version 2>/dev/null | head -n1 || echo "Not available")"
    echo ""
}

# Display PATH information
show_path_info() {
    echo "🛤️  PATH Information"
    echo "==================="
    echo ""
    echo "PATH:"
    echo "$PATH" | tr ':' '\n' | nl
    echo ""
    echo "MANIFEST CLI Location:"
    if command -v manifest >/dev/null 2>&1; then
        echo "✅ manifest command found at: $(which manifest)"
    else
        echo "❌ manifest command not found in PATH"
    fi
    echo ""
}

# Main function for command-line usage
main() {
    case "${1:-all}" in
        "all")
            show_system_info
            show_shell_info
            show_path_info
            show_manifest_cli_env_vars
            show_manifest_env_vars
            ;;
        "global")
            show_global_env_vars
            ;;
        "manifest")
            show_manifest_env_vars
            ;;
        "cli")
            show_manifest_cli_env_vars
            ;;
        "system")
            show_system_info
            show_shell_info
            show_path_info
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Environment Variables Test Module"
            echo "=========================================="
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  all      - Show all information (default)"
            echo "  global   - Show all global environment variables"
            echo "  manifest - Show all MANIFEST* environment variables"
            echo "  cli      - Show only MANIFEST_CLI_* environment variables"
            echo "  system   - Show system and shell information"
            echo "  help     - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 all      # Show comprehensive environment info"
            echo "  $0 cli      # Show only CLI-specific variables"
            echo "  $0 global   # Show all environment variables"
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
