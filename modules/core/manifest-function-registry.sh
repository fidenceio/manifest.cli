#!/bin/bash

# Manifest Function Registry Module
# Centralized registry for tracking function availability and dependencies

# Check if associative arrays are supported
if [[ "${BASH_VERSION%%.*}" -lt 4 ]]; then
    log_warning "Function registry requires Bash 4.0 or higher, using simplified mode"
    # Fallback to simple arrays for older bash versions
    FUNCTION_REGISTRY_LIST=()
    FUNCTION_DEPENDENCIES_LIST=()
    MODULE_FUNCTIONS_LIST=()
else
    # Function registry data structure
    declare -A FUNCTION_REGISTRY=()
    # Function dependency tracking
    declare -A FUNCTION_DEPENDENCIES=()
    # Module function mappings
    declare -A MODULE_FUNCTIONS=()
fi

# =============================================================================
# REGISTRY MANAGEMENT FUNCTIONS
# =============================================================================

# Register a function and its metadata
register_function() {
    local function_name="$1"
    local module_name="$2"
    local description="$3"
    local dependencies="${4:-}"
    
    # Store function metadata
    FUNCTION_REGISTRY["$function_name"]="$module_name|$description"
    
    # Store dependencies
    if [ -n "$dependencies" ]; then
        FUNCTION_DEPENDENCIES["$function_name"]="$dependencies"
    fi
    
    # Add to module function list
    if [ -z "${MODULE_FUNCTIONS[$module_name]}" ]; then
        MODULE_FUNCTIONS["$module_name"]="$function_name"
    else
        MODULE_FUNCTIONS["$module_name"]="${MODULE_FUNCTIONS[$module_name]} $function_name"
    fi
    
    log_debug "Registered function: $function_name from module: $module_name"
}

# Check if function is available
is_function_available() {
    local function_name="$1"
    [ -n "${FUNCTION_REGISTRY[$function_name]}" ]
}

# Get function metadata
get_function_info() {
    local function_name="$1"
    if [ -n "${FUNCTION_REGISTRY[$function_name]}" ]; then
        echo "${FUNCTION_REGISTRY[$function_name]}"
    else
        echo ""
    fi
}

# Get function dependencies
get_function_dependencies() {
    local function_name="$1"
    if [ -n "${FUNCTION_DEPENDENCIES[$function_name]}" ]; then
        echo "${FUNCTION_DEPENDENCIES[$function_name]}"
    else
        echo ""
    fi
}

# List functions by module
list_module_functions() {
    local module_name="$1"
    if [ -n "${MODULE_FUNCTIONS[$module_name]}" ]; then
        echo "${MODULE_FUNCTIONS[$module_name]}"
    else
        echo ""
    fi
}

# =============================================================================
# FUNCTION REGISTRATION
# =============================================================================

# Register core utilities functions
register_function "log_debug" "manifest-shared-utils" "Debug logging function"
register_function "log_info" "manifest-shared-utils" "Info logging function"
register_function "log_success" "manifest-shared-utils" "Success logging function"
register_function "log_warning" "manifest-shared-utils" "Warning logging function"
register_function "log_error" "manifest-shared-utils" "Error logging function"
register_function "log_trace" "manifest-shared-utils" "Trace logging function"

# Register path resolution functions
register_function "get_script_dir" "manifest-shared-utils" "Get script directory"
register_function "get_script_parent_dir" "manifest-shared-utils" "Get script parent directory"
register_function "get_project_root" "manifest-shared-utils" "Get project root directory"
register_function "get_modules_dir" "manifest-shared-utils" "Get modules directory"

# Register validation functions
register_function "validate_required_args" "manifest-shared-utils" "Validate required arguments"
register_function "validate_version_format" "manifest-shared-utils" "Validate version format"
register_function "validate_git_repo" "manifest-shared-utils" "Validate Git repository"
register_function "validate_file_exists" "manifest-shared-utils" "Validate file exists"
register_function "validate_directory_exists" "manifest-shared-utils" "Validate directory exists"
register_function "validate_repository_root" "manifest-shared-utils" "Validate running from repository root"
register_function "ensure_repository_root" "manifest-shared-utils" "Ensure running from repository root"

# Register shared functions
register_function "get_current_version" "manifest-shared-functions" "Get current version from VERSION file"
register_function "get_next_version" "manifest-shared-functions" "Get next version based on increment type"
register_function "get_latest_version" "manifest-shared-functions" "Get latest version from GitHub API"
register_function "check_network_connectivity" "manifest-shared-functions" "Check network connectivity"
register_function "check_required_tools" "manifest-shared-functions" "Check required tools availability"
register_function "generate_agent_id" "manifest-shared-functions" "Generate unique agent ID"
register_function "generate_session_id" "manifest-shared-functions" "Generate unique session ID"
register_function "log_operation" "manifest-shared-functions" "Log operation with timestamp"
register_function "get_git_info" "manifest-shared-functions" "Get Git repository information"
register_function "is_git_repository" "manifest-shared-functions" "Check if in Git repository"
register_function "safe_read_file" "manifest-shared-functions" "Safe file read with error handling"
register_function "safe_write_file" "manifest-shared-functions" "Safe file write with backup"
register_function "create_managed_temp_file" "manifest-shared-functions" "Create managed temporary file"
register_function "cleanup_managed_temp_files" "manifest-shared-functions" "Clean up managed temporary files"
register_function "get_config_value" "manifest-shared-functions" "Get configuration value with fallback"
register_function "set_config_value" "manifest-shared-functions" "Set configuration value"
register_function "safe_json_read" "manifest-shared-functions" "Safe JSON read with error handling"
register_function "safe_json_write" "manifest-shared-functions" "Safe JSON write with validation"
register_function "ensure_required_files" "manifest-shared-functions" "Check for required files and create them if missing"
register_function "create_default_readme" "manifest-shared-functions" "Create default README.md content"
register_function "create_default_changelog" "manifest-shared-functions" "Create default CHANGELOG.md content"
register_function "create_default_gitignore" "manifest-shared-functions" "Create default .gitignore content"

# =============================================================================
# REGISTRY QUERY FUNCTIONS
# =============================================================================

# Show function registry status
show_function_registry() {
    echo "Manifest Function Registry"
    echo "========================="
    echo ""
    
    local total_functions=0
    local module_count=0
    
    # Count total functions
    for func in "${!FUNCTION_REGISTRY[@]}"; do
        total_functions=$((total_functions + 1))
    done
    
    # Count modules
    for module in "${!MODULE_FUNCTIONS[@]}"; do
        module_count=$((module_count + 1))
    done
    
    echo "📊 Registry Statistics:"
    echo "  Total Functions: $total_functions"
    echo "  Total Modules: $module_count"
    echo ""
    
    # Show functions by module
    echo "📋 Functions by Module:"
    for module in "${!MODULE_FUNCTIONS[@]}"; do
        local functions="${MODULE_FUNCTIONS[$module]}"
        local func_count=$(echo "$functions" | wc -w)
        echo "  $module: $func_count functions"
        
        # Show individual functions
        for func in $functions; do
            local info="${FUNCTION_REGISTRY[$func]}"
            local description=$(echo "$info" | cut -d'|' -f2)
            echo "    - $func: $description"
        done
        echo ""
    done
}

# Find function by name pattern
find_functions() {
    local pattern="$1"
    echo "Functions matching pattern: $pattern"
    echo "====================================="
    echo ""
    
    for func in "${!FUNCTION_REGISTRY[@]}"; do
        if [[ "$func" == *"$pattern"* ]]; then
            local info="${FUNCTION_REGISTRY[$func]}"
            local module=$(echo "$info" | cut -d'|' -f1)
            local description=$(echo "$info" | cut -d'|' -f2)
            echo "  $func (from $module): $description"
        fi
    done
}

# Check function dependencies
check_function_dependencies() {
    local function_name="$1"
    
    if ! is_function_available "$function_name"; then
        echo "Function '$function_name' is not registered"
        return 1
    fi
    
    local dependencies=$(get_function_dependencies "$function_name")
    if [ -n "$dependencies" ]; then
        echo "Function '$function_name' dependencies: $dependencies"
    else
        echo "Function '$function_name' has no dependencies"
    fi
}

# Validate function availability
validate_function_availability() {
    local function_name="$1"
    
    if is_function_available "$function_name"; then
        log_debug "Function '$function_name' is available"
        return 0
    else
        log_error "Function '$function_name' is not available"
        return 1
    fi
}

# =============================================================================
# REGISTRY MAINTENANCE FUNCTIONS
# =============================================================================

# Clean up registry
cleanup_registry() {
    FUNCTION_REGISTRY=()
    FUNCTION_DEPENDENCIES=()
    MODULE_FUNCTIONS=()
    log_debug "Function registry cleaned up"
}

# Export registry functions
export -f register_function is_function_available get_function_info
export -f get_function_dependencies list_module_functions show_function_registry
export -f find_functions check_function_dependencies validate_function_availability
export -f cleanup_registry
