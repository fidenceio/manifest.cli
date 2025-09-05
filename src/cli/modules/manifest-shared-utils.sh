#!/bin/bash

# Manifest Shared Utilities Module
# Provides common functions, colors, and patterns used across all modules

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Common validation functions
validate_required_args() {
    local args=("$@")
    local missing_args=()
    
    for arg in "${args[@]}"; do
        if [[ -z "${!arg}" ]]; then
            missing_args+=("$arg")
        fi
    done
    
    if [[ ${#missing_args[@]} -gt 0 ]]; then
        log_error "Missing required arguments: ${missing_args[*]}"
        return 1
    fi
    return 0
}

# Common file operations
ensure_directory() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        log_info "Creating directory: $dir"
        mkdir -p "$dir" || {
            log_error "Failed to create directory: $dir"
            return 1
        }
    fi
}

# Common temporary file handling
create_temp_file() {
    mktemp 2>/dev/null || {
        log_error "Failed to create temporary file"
        return 1
    }
}

cleanup_temp_file() {
    local file="$1"
    if [[ -n "$file" && -f "$file" ]]; then
        rm -f "$file"
    fi
}

# Common help function pattern
show_help() {
    local module_name="$1"
    local usage="$2"
    local commands="$3"
    local examples="$4"
    
    echo "$module_name"
    echo "$(printf '=%.0s' {1..${#module_name}})"
    echo ""
    echo "Usage: $0 $usage"
    echo ""
    echo "Commands:"
    echo "$commands"
    echo ""
    if [[ -n "$examples" ]]; then
        echo "Examples:"
        echo "$examples"
        echo ""
    fi
}

# Common error handling functions
show_usage_error() {
    local command="$1"
    log_error "Unknown command: $command"
    echo "Use '$0 help' for usage information"
    exit 1
}

show_required_arg_error() {
    local arg_name="$1"
    local usage="$2"
    log_error "$arg_name is required"
    echo "Usage: $0 $usage"
    exit 1
}

# Common main function pattern
create_main_function() {
    local module_name="$1"
    shift
    local commands=("$@")
    
    cat << 'EOF'
main() {
    case "${1:-help}" in
EOF
    
    for cmd in "${commands[@]}"; do
        echo "        \"$cmd\")"
        echo "            # Command implementation"
        echo "            ;;"
    done
    
    cat << 'EOF'
        "help"|"-h"|"--help")
            show_help "$MODULE_NAME" "$USAGE" "$COMMANDS" "$EXAMPLES"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF
}

# Export functions for use in other modules
export -f log_info log_success log_warning log_error
export -f validate_required_args ensure_directory create_temp_file cleanup_temp_file
export -f show_help show_usage_error show_required_arg_error create_main_function
