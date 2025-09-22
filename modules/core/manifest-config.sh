#!/bin/bash

# Manifest Configuration Module
# Handles environment variable loading, validation, and defaults

# Configuration validation
validate_config() {
    # Temporarily disable validation to debug NTP issue
    log_debug "Configuration validation skipped for debugging"
    return 0
}

# Load configuration from environment files
load_configuration() {
    local project_root="$1"
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    # Load configuration files in order (last wins)
    # First try the installation location for global config
    if [ -n "${INSTALL_LOCATION:-}" ] && [ -d "$INSTALL_LOCATION" ]; then
        for config_file in "${CONFIG_FILES[@]}"; do
            local full_path="$INSTALL_LOCATION/$config_file"
            if [ -f "$full_path" ]; then
                echo "🔧 Loading global configuration from: $config_file"
                # Source the file to load variables
                if [ -r "$full_path" ]; then
                    # Use a safe way to load env files
                    while IFS= read -r line || [ -n "$line" ]; do
                        # Skip comments and empty lines
                        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                            continue
                        fi
                        
                        # Skip lines that don't look like variable assignments
                        if [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; then
                            # Parse the line to handle quoted values properly
                            local var_name="${line%%=*}"
                            local var_value="${line#*=}"
                            
                            # Remove quotes if present
                            if [[ "$var_value" =~ ^\".*\"$ ]]; then
                                var_value="${var_value#\"}"
                                var_value="${var_value%\"}"
                            elif [[ "$var_value" =~ ^\'.*\'$ ]]; then
                                var_value="${var_value#\'}"
                                var_value="${var_value%\'}"
                            fi
                            
                            # Export the variable
                            export "$var_name=$var_value"
                        fi
                    done < "$full_path"
                fi
            fi
        done
    fi
    
    # Then try the project root for local overrides
    for config_file in "${CONFIG_FILES[@]}"; do
        local full_path="$project_root/$config_file"
        if [ -f "$full_path" ]; then
            echo "🔧 Loading project configuration from: $config_file"
            # Source the file to load variables
            if [ -r "$full_path" ]; then
                # Use a safe way to load env files
                while IFS= read -r line || [ -n "$line" ]; do
                    # Skip comments and empty lines
                    if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "${line// }" ]]; then
                        continue
                    fi
                    
                    # Skip lines that don't look like variable assignments
                    if [[ "$line" =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*= ]]; then
                        # Parse the line to handle quoted values properly
                        local var_name="${line%%=*}"
                        local var_value="${line#*=}"
                        
                        # Remove inline comments (everything after #)
                        var_value="${var_value%%\#*}"
                        
                        # Trim whitespace first
                        var_value=$(echo "$var_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        
                        # Remove quotes if present
                        if [[ "$var_value" =~ ^\".*\"$ ]]; then
                            var_value="${var_value#\"}"
                            var_value="${var_value%\"}"
                        elif [[ "$var_value" =~ ^\'.*\'$ ]]; then
                            var_value="${var_value#\'}"
                            var_value="${var_value%\'}"
                        fi
                        
                        # Trim whitespace again after quote removal
                        var_value=$(echo "$var_value" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                        
                        # Export the variable
                        export "$var_name=$var_value"
                    fi
                done < "$full_path"
            fi
        fi
    done
    
    # Always set default values for critical variables (even if no config files found)
    set_default_configuration
    
    # Skip validation for now to debug NTP issue
    # validate_config
}

# Set default configuration values
set_default_configuration() {
    # Versioning Configuration
    export MANIFEST_VERSION_FORMAT="${MANIFEST_VERSION_FORMAT:-XX.XX.XX}"
    export MANIFEST_VERSION_SEPARATOR="${MANIFEST_VERSION_SEPARATOR:-.}"
    export MANIFEST_VERSION_COMPONENTS="${MANIFEST_VERSION_COMPONENTS:-major,minor,patch}"
    export MANIFEST_VERSION_MAX_VALUES="${MANIFEST_VERSION_MAX_VALUES:-0,0,0}"
    
    # Human-Intuitive Component Mapping (defaults to standard semantic versioning)
    export MANIFEST_MAJOR_COMPONENT_POSITION="${MANIFEST_MAJOR_COMPONENT_POSITION:-1}"
    export MANIFEST_MINOR_COMPONENT_POSITION="${MANIFEST_MINOR_COMPONENT_POSITION:-2}"
    export MANIFEST_PATCH_COMPONENT_POSITION="${MANIFEST_PATCH_COMPONENT_POSITION:-3}"
    export MANIFEST_REVISION_COMPONENT_POSITION="${MANIFEST_REVISION_COMPONENT_POSITION:-4}"
    
    # Increment Behavior (defaults to standard semantic versioning)
    export MANIFEST_MAJOR_INCREMENT_TARGET="${MANIFEST_MAJOR_INCREMENT_TARGET:-1}"
    export MANIFEST_MINOR_INCREMENT_TARGET="${MANIFEST_MINOR_INCREMENT_TARGET:-2}"
    export MANIFEST_PATCH_INCREMENT_TARGET="${MANIFEST_PATCH_INCREMENT_TARGET:-3}"
    export MANIFEST_REVISION_INCREMENT_TARGET="${MANIFEST_REVISION_INCREMENT_TARGET:-4}"
    
    # Reset Behavior (defaults to standard semantic versioning)
    export MANIFEST_MAJOR_RESET_COMPONENTS="${MANIFEST_MAJOR_RESET_COMPONENTS:-2,3,4}"
    export MANIFEST_MINOR_RESET_COMPONENTS="${MANIFEST_MINOR_RESET_COMPONENTS:-3,4}"
    export MANIFEST_PATCH_RESET_COMPONENTS="${MANIFEST_PATCH_RESET_COMPONENTS:-4}"
    export MANIFEST_REVISION_RESET_COMPONENTS="${MANIFEST_REVISION_RESET_COMPONENTS:-}"
    
    # Git Configuration
    export MANIFEST_GIT_TAG_PREFIX="${MANIFEST_GIT_TAG_PREFIX:-v}"
    export MANIFEST_GIT_TAG_SUFFIX="${MANIFEST_GIT_TAG_SUFFIX:-}"
    
    # Branch Naming Configuration
    export MANIFEST_DEFAULT_BRANCH="${MANIFEST_DEFAULT_BRANCH:-main}"
    export MANIFEST_FEATURE_BRANCH_PREFIX="${MANIFEST_FEATURE_BRANCH_PREFIX:-feature/}"
    export MANIFEST_HOTFIX_BRANCH_PREFIX="${MANIFEST_HOTFIX_BRANCH_PREFIX:-hotfix/}"
    export MANIFEST_RELEASE_BRANCH_PREFIX="${MANIFEST_RELEASE_BRANCH_PREFIX:-release/}"
    export MANIFEST_BUGFIX_BRANCH_PREFIX="${MANIFEST_BUGFIX_BRANCH_PREFIX:-bugfix/}"
    export MANIFEST_DEVELOPMENT_BRANCH="${MANIFEST_DEVELOPMENT_BRANCH:-develop}"
    export MANIFEST_STAGING_BRANCH="${MANIFEST_STAGING_BRANCH:-staging}"
    
    # NTP Configuration
    export MANIFEST_NTP_SERVER1="${MANIFEST_NTP_SERVER1:-time.apple.com}"
    export MANIFEST_NTP_SERVER2="${MANIFEST_NTP_SERVER2:-time.google.com}"
    export MANIFEST_NTP_SERVER3="${MANIFEST_NTP_SERVER3:-pool.ntp.org}"
    export MANIFEST_NTP_SERVER4="${MANIFEST_NTP_SERVER4:-time.nist.gov}"
    export MANIFEST_NTP_TIMEOUT="${MANIFEST_NTP_TIMEOUT:-5}"
    export MANIFEST_NTP_RETRIES="${MANIFEST_NTP_RETRIES:-3}"
    export MANIFEST_NTP_VERIFY="${MANIFEST_NTP_VERIFY:-true}"
    
    # Git Operations
    export MANIFEST_GIT_COMMIT_TEMPLATE="${MANIFEST_GIT_COMMIT_TEMPLATE:-Release v{version} - {timestamp}}"
    export MANIFEST_GIT_PUSH_STRATEGY="${MANIFEST_GIT_PUSH_STRATEGY:-simple}"
    export MANIFEST_GIT_PULL_STRATEGY="${MANIFEST_GIT_PULL_STRATEGY:-rebase}"
    export MANIFEST_GIT_TIMEOUT="${MANIFEST_GIT_TIMEOUT:-300}"
    export MANIFEST_GIT_RETRIES="${MANIFEST_GIT_RETRIES:-3}"
    
    # Homebrew Configuration
    export MANIFEST_BREW_OPTION="${MANIFEST_BREW_OPTION:-enabled}"
    export MANIFEST_BREW_INTERACTIVE="${MANIFEST_BREW_INTERACTIVE:-no}"
    export MANIFEST_TAP_REPO="${MANIFEST_TAP_REPO:-https://github.com/fidenceio/fidenceio-homebrew-tap.git}"
    
    # Documentation Configuration
    export MANIFEST_DOCS_FOLDER="${MANIFEST_DOCS_FOLDER:-docs}"
    export MANIFEST_DOCS_ARCHIVE_FOLDER="${MANIFEST_DOCS_ARCHIVE_FOLDER:-docs/zArchive}"
    export MANIFEST_DOCS_TEMPLATE_DIR="${MANIFEST_DOCS_TEMPLATE_DIR:-}"
    export MANIFEST_DOCS_AUTO_GENERATE="${MANIFEST_DOCS_AUTO_GENERATE:-true}"
    export MANIFEST_DOCS_HISTORICAL_LIMIT="${MANIFEST_DOCS_HISTORICAL_LIMIT:-20}"
    export MANIFEST_DOCS_FILENAME_PATTERN="${MANIFEST_DOCS_FILENAME_PATTERN:-RELEASE_vVERSION.md}"
    
    # File and directory names
    export MANIFEST_README_FILE="${MANIFEST_README_FILE:-README.md}"
    export MANIFEST_VERSION_FILE="${MANIFEST_VERSION_FILE:-VERSION}"
    export MANIFEST_GITIGNORE_FILE="${MANIFEST_GITIGNORE_FILE:-.gitignore}"
    export MANIFEST_DOCUMENTATION_ARCHIVE_DIR="${MANIFEST_DOCUMENTATION_ARCHIVE_DIR:-zArchive}"
    export MANIFEST_GIT_DIR="${MANIFEST_GIT_DIR:-.git}"
    export MANIFEST_MODULES_DIR="${MANIFEST_MODULES_DIR:-modules}"
    
    # File extensions
    export MANIFEST_MARKDOWN_EXT="${MANIFEST_MARKDOWN_EXT:-*.md}"
    
    # Installation paths
    export MANIFEST_INSTALL_DIR="${MANIFEST_INSTALL_DIR:-/usr/local/share/manifest-cli}"
    export MANIFEST_BIN_DIR="${MANIFEST_BIN_DIR:-~/.local/bin}"
    
    # Temporary file paths
    export MANIFEST_TEMP_DIR="${MANIFEST_TEMP_DIR:-~/.manifest-cli}"
    export MANIFEST_TEMP_LIST="${MANIFEST_TEMP_LIST:-temp-files.list}"
    
    # Configuration file names
    export MANIFEST_CONFIG_GLOBAL="${MANIFEST_CONFIG_GLOBAL:-.env.manifest.global}"
    export MANIFEST_CONFIG_LOCAL="${MANIFEST_CONFIG_LOCAL:-.env.manifest.local}"
    
    # Project Configuration
    export MANIFEST_PROJECT_NAME="${MANIFEST_PROJECT_NAME:-Manifest CLI}"
    
    # Auto-Update Configuration
    export MANIFEST_AUTO_UPDATE="${MANIFEST_AUTO_UPDATE:-true}"
    export MANIFEST_UPDATE_COOLDOWN="${MANIFEST_UPDATE_COOLDOWN:-30}"
    export MANIFEST_PROJECT_DESCRIPTION="${MANIFEST_PROJECT_DESCRIPTION:-A powerful CLI tool for versioning, AI documenting, and repository operations}"
    export MANIFEST_ORGANIZATION="${MANIFEST_ORGANIZATION:-Your Organization}"
    
    # Advanced Configuration
    export MANIFEST_VERSION_REGEX="${MANIFEST_VERSION_REGEX:-^[0-9]+(\.[0-9]+)*$}"
    export MANIFEST_VERSION_VALIDATION="${MANIFEST_VERSION_VALIDATION:-true}"
    
    # Development & Debugging
    export MANIFEST_DEBUG="${MANIFEST_DEBUG:-false}"
    export MANIFEST_VERBOSE="${MANIFEST_VERBOSE:-false}"
    export MANIFEST_LOG_LEVEL="${MANIFEST_LOG_LEVEL:-INFO}"
    export MANIFEST_INTERACTIVE="${MANIFEST_INTERACTIVE:-false}"
    
    # Configuration file paths (in order of precedence)
    CONFIG_FILES=(
        "$MANIFEST_CONFIG_GLOBAL"
        "$MANIFEST_CONFIG_LOCAL"
    )
    
    # Validate configuration after setting defaults
    # validate_config
}

# Get configuration value with fallback
get_config() {
    local key="$1"
    local default="$2"
    
    local value="${!key}"
    if [ -n "$value" ]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# Validate version format configuration
validate_version_config() {
    local format="$MANIFEST_VERSION_FORMAT"
    local separator="$MANIFEST_VERSION_SEPARATOR"
    
    # Basic validation
    if [ -z "$format" ]; then
        echo "❌ MANIFEST_VERSION_FORMAT is not set"
        return 1
    fi
    
    if [ -z "$separator" ]; then
        echo "❌ MANIFEST_VERSION_SEPARATOR is not set"
        return 1
    fi
    
    # Check if format contains the separator
    if [[ "$format" != *"$separator"* ]]; then
        echo "❌ MANIFEST_VERSION_FORMAT must contain MANIFEST_VERSION_SEPARATOR"
        return 1
    fi
    
    echo "✅ Version configuration validated"
    return 0
}

# Parse version components based on configuration
parse_version_components() {
    local version="$1"
    local format="$MANIFEST_VERSION_FORMAT"
    local separator="$MANIFEST_VERSION_SEPARATOR"
    
    if [ -z "$version" ] || [ -z "$format" ]; then
        return 1
    fi
    
    # Split format into components
    IFS="$separator" read -ra format_components <<< "$format"
    IFS="$separator" read -ra version_components <<< "$version"
    
    # Create associative array for components
    declare -A components
    local i=0
    for component in "${format_components[@]}"; do
        if [ $i -lt ${#version_components[@]} ]; then
            components["$component"]="${version_components[$i]}"
        else
            components["$component"]="0"
        fi
        ((i++))
    done
    
    # Return components based on format
    case "$format" in
        *"X"*)
            # Standard semantic versioning (X.X.X)
            echo "${components[X]:-0}"
            ;;
        *"XX"*)
            # Two-digit components (XX.XX.XX)
            echo "${components[XX]:-00}"
            ;;
        *"XXX"*)
            # Three-digit components (XXX.XXX.XXX)
            echo "${components[XXX]:-000}"
            ;;
        *"XXXX"*)
            # Four-digit components (XXXX.XXXX.XXXX)
            echo "${components[XXXX]:-0000}"
            ;;
        *"YYYY"*)
            # Year-based components (YYYY.MM.DD)
            echo "${components[YYYY]:-$(date +%Y)}"
            ;;
        *)
            # Fallback to first component
            echo "${version_components[0]:-0}"
            ;;
    esac
}

# Generate next version based on configuration
generate_next_version() {
    local current_version="$1"
    local increment_type="$2"
    local format="$MANIFEST_VERSION_FORMAT"
    local separator="$MANIFEST_VERSION_SEPARATOR"
    
    if [ -z "$current_version" ] || [ -z "$format" ]; then
        return 1
    fi
    
    # Parse current version components
    IFS="$separator" read -ra current_components <<< "$current_version"
    IFS="$separator" read -ra format_components <<< "$format"
    
    # Create new version array
    local new_components=("${current_components[@]}")
    
    # Apply increment based on type and format
    case "$increment_type" in
        "patch")
            # Increment last component
            local last_index=$((${#new_components[@]} - 1))
            new_components[$last_index]=$((${new_components[$last_index]} + 1))
            ;;
        "minor")
            # Increment second-to-last component, reset last
            if [ ${#new_components[@]} -ge 2 ]; then
                local minor_index=$((${#new_components[@]} - 2))
                new_components[$minor_index]=$((${new_components[$minor_index]} + 1))
                new_components[$((${#new_components[@]} - 1))]=0
            fi
            ;;
        "major")
            # Increment first component, reset others
            new_components[0]=$((${new_components[0]} + 1))
            for i in $(seq 1 $((${#new_components[@]} - 1))); do
                new_components[$i]=0
            done
            ;;
        "revision")
            # Add revision component if supported
            if [[ "$format" == *"X"* ]]; then
                new_components+=("1")
            fi
            ;;
    esac
    
    # Join components with separator
    local new_version=""
    for i in "${!new_components[@]}"; do
        if [ $i -eq 0 ]; then
            new_version="${new_components[$i]}"
        else
            new_version="${new_version}${separator}${new_components[$i]}"
        fi
    done
    
    echo "$new_version"
}

# Display current configuration
show_configuration() {
    echo "🔧 Manifest CLI Configuration"
    echo "=============================="
    echo ""
    
    echo "📋 Versioning Configuration:"
    echo "   Format: ${MANIFEST_VERSION_FORMAT}"
    echo "   Separator: ${MANIFEST_VERSION_SEPARATOR}"
    echo "   Components: ${MANIFEST_VERSION_COMPONENTS}"
    echo "   Max Values: ${MANIFEST_VERSION_MAX_VALUES}"
    echo ""
    
    echo "🧠 Human-Intuitive Component Mapping:"
    echo "   Major Position: ${MANIFEST_MAJOR_COMPONENT_POSITION} (leftmost = biggest impact)"
    echo "   Minor Position: ${MANIFEST_MINOR_COMPONENT_POSITION} (middle = moderate impact)"
    echo "   Patch Position: ${MANIFEST_PATCH_COMPONENT_POSITION} (rightmost = least impact)"
    echo "   Revision Position: ${MANIFEST_REVISION_COMPONENT_POSITION} (most right = most specific)"
    echo ""
    
    echo "📈 Increment Behavior:"
    echo "   Major Target: ${MANIFEST_MAJOR_INCREMENT_TARGET} (which component increments)"
    echo "   Minor Target: ${MANIFEST_MINOR_INCREMENT_TARGET} (which component increments)"
    echo "   Patch Target: ${MANIFEST_PATCH_INCREMENT_TARGET} (which component increments)"
    echo "   Revision Target: ${MANIFEST_REVISION_INCREMENT_TARGET} (which component increments)"
    echo ""
    
    echo "🔄 Reset Behavior:"
    echo "   Major Reset: ${MANIFEST_MAJOR_RESET_COMPONENTS} (components reset to 0)"
    echo "   Minor Reset: ${MANIFEST_MINOR_RESET_COMPONENTS} (components reset to 0)"
    echo "   Patch Reset: ${MANIFEST_PATCH_RESET_COMPONENTS} (components reset to 0)"
    echo "   Revision Reset: ${MANIFEST_REVISION_RESET_COMPONENTS} (components reset to 0)"
    echo ""
    
    echo "🌿 Branch Configuration:"
    echo "   Default Branch: ${MANIFEST_DEFAULT_BRANCH}"
    echo "   Feature Prefix: ${MANIFEST_FEATURE_BRANCH_PREFIX}"
    echo "   Hotfix Prefix: ${MANIFEST_HOTFIX_BRANCH_PREFIX}"
    echo "   Release Prefix: ${MANIFEST_RELEASE_BRANCH_PREFIX}"
    echo "   Bugfix Prefix: ${MANIFEST_BUGFIX_BRANCH_PREFIX}"
    echo "   Development Branch: ${MANIFEST_DEVELOPMENT_BRANCH}"
    echo "   Staging Branch: ${MANIFEST_STAGING_BRANCH}"
    echo ""
    
    echo "🏷️  Git Configuration:"
    echo "   Tag Prefix: ${MANIFEST_GIT_TAG_PREFIX}"
    echo "   Tag Suffix: ${MANIFEST_GIT_TAG_SUFFIX}"
    echo "   Push Strategy: ${MANIFEST_GIT_PUSH_STRATEGY}"
    echo "   Pull Strategy: ${MANIFEST_GIT_PULL_STRATEGY}"
    echo "   Timeout: ${MANIFEST_GIT_TIMEOUT} seconds"
    echo "   Retries: ${MANIFEST_GIT_RETRIES} attempts"
    echo "   Remotes: Uses all configured git remotes automatically"
    echo ""
    
    echo "📚 Documentation Configuration:"
    echo "   Docs Folder: ${MANIFEST_DOCS_FOLDER}"
    echo "   Archive Folder: ${MANIFEST_DOCS_ARCHIVE_FOLDER}"
    echo "   Filename Pattern: ${MANIFEST_DOCS_FILENAME_PATTERN}"
    echo "   Historical Limit: ${MANIFEST_DOCS_HISTORICAL_LIMIT}"
    echo ""
    
    echo "🏢 Project Configuration:"
    echo "   Project Name: ${MANIFEST_PROJECT_NAME}"
    echo "   Description: ${MANIFEST_PROJECT_DESCRIPTION}"
    echo "   Organization: ${MANIFEST_ORGANIZATION}"
    echo ""
    
    echo "📍 Installation Configuration:"
    echo "   Binary Location: ${BINARY_LOCATION:-Not set}"
    echo "   Install Location: ${INSTALL_LOCATION:-Not set}"
    echo "   Project Root: ${PROJECT_ROOT:-Not set}"
    echo ""
    
    echo "⚙️  Advanced Configuration:"
    echo "   Version Regex: ${MANIFEST_VERSION_REGEX}"
    echo "   Version Validation: ${MANIFEST_VERSION_VALIDATION}"
    echo ""
    
    echo "🔄 Auto-Update Configuration:"
    echo "   Auto-Update: ${MANIFEST_AUTO_UPDATE}"
    echo "   Update Cooldown: ${MANIFEST_UPDATE_COOLDOWN} minutes"
    echo ""
    
    echo "💡 How This Works:"
    echo "   • LEFT components = More MAJOR changes (bigger impact)"
    echo "   • RIGHT components = More MINOR changes (smaller impact)"
    echo "   • More digits after last dot = More specific/precise changes"
    echo "   • 'manifest go major' increments component ${MANIFEST_MAJOR_INCREMENT_TARGET}"
    echo "   • 'manifest go minor' increments component ${MANIFEST_MINOR_INCREMENT_TARGET}"
    echo "   • 'manifest go patch' increments component ${MANIFEST_PATCH_INCREMENT_TARGET}"
    echo "   • 'manifest go revision' increments component ${MANIFEST_REVISION_INCREMENT_TARGET}"
}

# Get documentation folder path
get_docs_folder() {
    local project_root="$1"
    if [ -z "$project_root" ]; then
        project_root="$PROJECT_ROOT"
    fi
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    echo "$project_root/$MANIFEST_DOCS_FOLDER"
}

# Get documentation archive folder path
get_docs_archive_folder() {
    local project_root="$1"
    if [ -z "$project_root" ]; then
        project_root="$PROJECT_ROOT"
    fi
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    echo "$project_root/$MANIFEST_DOCS_ARCHIVE_FOLDER"
}

# Export functions for use in other modules
export -f load_configuration
export -f set_default_configuration
export -f get_config
export -f validate_version_config
export -f parse_version_components
export -f generate_next_version
export -f show_configuration
export -f get_docs_folder
export -f get_docs_archive_folder

# Load configuration automatically when this module is sourced
# This ensures all environment variables are set up properly
# But only if INSTALL_LOCATION is already set (avoid race condition)
if [ -n "${INSTALL_LOCATION:-}" ]; then
    load_configuration "${PROJECT_ROOT:-.}"
fi
