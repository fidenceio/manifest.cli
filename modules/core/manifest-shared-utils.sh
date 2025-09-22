#!/bin/bash

# Manifest Shared Utilities Module
# Provides common functions, colors, and patterns used across all modules

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging configuration
MANIFEST_LOG_LEVEL="${MANIFEST_LOG_LEVEL:-INFO}"

# Logging levels (numeric for comparison)
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Get current log level
get_log_level() {
    local level="$(echo "${MANIFEST_LOG_LEVEL}" | tr '[:lower:]' '[:upper:]')"
    case "$level" in
        DEBUG) echo $LOG_LEVEL_DEBUG ;;
        INFO)  echo $LOG_LEVEL_INFO ;;
        WARN)  echo $LOG_LEVEL_WARN ;;
        ERROR) echo $LOG_LEVEL_ERROR ;;
        *)     echo $LOG_LEVEL_INFO ;;
    esac
}

# Enhanced logging functions with levels
log_debug() {
    if [[ $(get_log_level) -le $LOG_LEVEL_DEBUG ]]; then
        echo -e "${PURPLE}🐛 DEBUG: $1${NC}" >&2
    fi
}

log_info() {
    if [[ $(get_log_level) -le $LOG_LEVEL_INFO ]]; then
        echo -e "${BLUE}ℹ️  INFO: $1${NC}" >&2
    fi
}

log_success() {
    if [[ $(get_log_level) -le $LOG_LEVEL_INFO ]]; then
        echo -e "${GREEN}✅ SUCCESS: $1${NC}" >&2
    fi
}

log_warning() {
    if [[ $(get_log_level) -le $LOG_LEVEL_WARN ]]; then
        echo -e "${YELLOW}⚠️  WARN: $1${NC}" >&2
    fi
}

log_error() {
    if [[ $(get_log_level) -le $LOG_LEVEL_ERROR ]]; then
        echo -e "${RED}❌ ERROR: $1${NC}" >&2
    fi
}

log_trace() {
    if [[ $(get_log_level) -le $LOG_LEVEL_DEBUG ]]; then
        echo -e "${CYAN}🔍 TRACE: $1${NC}" >&2
    fi
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

# Common path resolution utilities
get_script_dir() {
    echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
}

get_script_parent_dir() {
    echo "$(dirname "$(get_script_dir)")"
}

get_project_root() {
    # Try to find project root by looking for VERSION file
    local current_dir="$(pwd)"
    local search_dir="$current_dir"
    
    # Search up to 5 levels for VERSION file
    for i in {1..5}; do
        if [[ -f "$search_dir/VERSION" ]]; then
            echo "$search_dir"
            return 0
        fi
        search_dir="$(dirname "$search_dir")"
    done
    
    # Fallback to current directory
    echo "$current_dir"
}

# Validate and ensure we're running from repository root
validate_repository_root() {
    local current_dir="$(pwd)"
    local git_root=""
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a Git repository. Please run Manifest from within a Git repository."
        return 1
    fi
    
    # Get the git repository root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [[ -z "$git_root" ]]; then
        log_error "Could not determine Git repository root"
        return 1
    fi
    
    # Check if current directory is the repository root
    if [[ "$current_dir" != "$git_root" ]]; then
        log_error "Manifest must be run from the repository root directory"
        log_error "Current directory: $current_dir"
        log_error "Repository root: $git_root"
        log_error ""
        log_error "Please run: cd \"$git_root\" && manifest $*"
        return 1
    fi
    
    # Additional validation: ensure we have a .git directory
    if [[ ! -d "$MANIFEST_CLI_GIT_DIR" ]]; then
        log_error "No $MANIFEST_CLI_GIT_DIR directory found in current location"
        return 1
    fi
    
    log_debug "Repository root validation passed: $current_dir"
    return 0
}

# Ensure we're in repository root and change directory if needed
ensure_repository_root() {
    local current_dir="$(pwd)"
    local git_root=""
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir >/dev/null 2>&1; then
        log_error "Not in a Git repository. Please run Manifest from within a Git repository."
        return 1
    fi
    
    # Get the git repository root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [[ -z "$git_root" ]]; then
        log_error "Could not determine Git repository root"
        return 1
    fi
    
    # Check if current directory is the repository root
    if [[ "$current_dir" != "$git_root" ]]; then
        log_warning "Not running from repository root. Changing to repository root..."
        log_warning "From: $current_dir"
        log_warning "To: $git_root"
        
        # Change to repository root
        if ! cd "$git_root"; then
            log_error "Failed to change to repository root: $git_root"
            return 1
        fi
        
        log_success "Changed to repository root: $git_root"
    fi
    
    # Additional validation: ensure we have a .git directory
    if [[ ! -d "$MANIFEST_CLI_GIT_DIR" ]]; then
        log_error "No $MANIFEST_CLI_GIT_DIR directory found in current location"
        return 1
    fi
    
    log_debug "Repository root ensured: $(pwd)"
    return 0
}

get_modules_dir() {
    local script_dir="$(get_script_dir)"
    # If we're in a module subdirectory, go up to modules root
    if [[ "$script_dir" == */modules/* ]]; then
        echo "$(dirname "$(dirname "$script_dir")")/modules"
    else
        echo "$script_dir/modules"
    fi
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

# cleanup_temp_file() - Use cleanup_temp_files() from manifest-cleanup-docs.sh for comprehensive cleanup

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

# Standardized error message functions
show_network_error() {
    log_error "Network operation failed: $1"
    return 1
}

show_file_error() {
    log_error "File operation failed: $1"
    return 1
}

show_git_error() {
    log_error "Git operation failed: $1"
    return 1
}

show_config_error() {
    log_error "Configuration error: $1"
    return 1
}

show_validation_error() {
    log_error "Validation failed: $1"
    return 1
}

show_permission_error() {
    log_error "Permission denied: $1"
    return 1
}

show_dependency_error() {
    log_error "Missing dependency: $1"
    echo "Please install $1 and try again"
    return 1
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

# create_main_function() - Removed: unused function that generated boilerplate code

# Input sanitization and validation functions
sanitize_filename() {
    local filename="$1"
    # Remove dangerous characters and limit length
    echo "$filename" | sed 's/[^a-zA-Z0-9._-]//g' | cut -c1-255
}

sanitize_version() {
    local version="$1"
    # Only allow alphanumeric, dots, and hyphens
    echo "${version//[^a-zA-Z0-9.-]/}"
}

sanitize_path() {
    local path="$1"
    # Remove path traversal attempts and normalize
    path="${path//../}"
    path="${path//\/\//\/}"
    path="${path#//}"
    echo "$path"
}

validate_version_format() {
    local version="$1"
    local pattern="${MANIFEST_VERSION_REGEX:-^[0-9]+(\.[0-9]+)*$}"
    
    # Skip validation for template patterns
    if [[ "$version" == *"X"* ]] || [[ "$version" == *"XX"* ]]; then
        log_debug "Skipping validation for template version: $version"
        return 0
    fi
    
    if [[ ! "$version" =~ $pattern ]]; then
        show_validation_error "Invalid version format: $version (expected pattern: $pattern)"
        return 1
    fi
    return 0
}

validate_git_repo() {
    local path="${1:-.}"
    
    if ! git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
        show_validation_error "Not a valid Git repository: $path"
        return 1
    fi
    return 0
}

validate_file_exists() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        show_file_error "File not found: $file"
        return 1
    fi
    return 0
}

validate_directory_exists() {
    local dir="$1"
    
    if [[ ! -d "$dir" ]]; then
        show_file_error "Directory not found: $dir"
        return 1
    fi
    return 0
}

# Export functions for use in other modules
export -f log_debug log_info log_success log_warning log_error log_trace
export -f validate_required_args ensure_directory create_temp_file
export -f show_help show_usage_error show_required_arg_error
export -f get_script_dir get_script_parent_dir get_project_root get_modules_dir
export -f validate_repository_root ensure_repository_root
export -f show_network_error show_file_error show_git_error show_config_error
export -f show_validation_error show_permission_error show_dependency_error
export -f sanitize_filename sanitize_version sanitize_path validate_version_format
export -f validate_git_repo validate_file_exists validate_directory_exists
