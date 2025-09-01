#!/bin/bash

# Manifest Configuration Module
# Handles environment variable loading, validation, and defaults

# Configuration file paths (in order of precedence)
CONFIG_FILES=(
    ".env"
    ".env.local"
    ".env.development"
    ".env.staging"
    ".env.production"
)

# Load configuration from environment files
load_configuration() {
    local project_root="$1"
    
    if [ -z "$project_root" ]; then
        project_root="."
    fi
    
    # Load configuration files in order (last wins)
    for config_file in "${CONFIG_FILES[@]}"; do
        local full_path="$project_root/$config_file"
        if [ -f "$full_path" ]; then
            echo "🔧 Loading configuration from: $config_file"
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
                        # Export the variable
                        export "$line"
                    fi
                done < "$full_path"
            fi
        fi
    done
    
    # Set default values for critical variables
    set_default_configuration
}

# Set default configuration values
set_default_configuration() {
    # Versioning Configuration
    export MANIFEST_VERSION_FORMAT="${MANIFEST_VERSION_FORMAT:-XX.XX.XX}"
    export MANIFEST_VERSION_SEPARATOR="${MANIFEST_VERSION_SEPARATOR:-.}"
    export MANIFEST_VERSION_COMPONENTS="${MANIFEST_VERSION_COMPONENTS:-major,minor,patch}"
    export MANIFEST_VERSION_MAX_VALUES="${MANIFEST_VERSION_MAX_VALUES:-0,0,0}"
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
    export MANIFEST_NTP_SERVERS="${MANIFEST_NTP_SERVERS:-time.apple.com,time.google.com,pool.ntp.org,time.nist.gov}"
    export MANIFEST_NTP_TIMEOUT="${MANIFEST_NTP_TIMEOUT:-5}"
    export MANIFEST_NTP_RETRIES="${MANIFEST_NTP_RETRIES:-3}"
    export MANIFEST_NTP_VERIFY="${MANIFEST_NTP_VERIFY:-true}"
    
    # Git Configuration
    export MANIFEST_GIT_COMMIT_TEMPLATE="${MANIFEST_GIT_COMMIT_TEMPLATE:-Release v{version} - {timestamp}}"
    export MANIFEST_GIT_PRIMARY_REMOTE="${MANIFEST_GIT_PRIMARY_REMOTE:-origin}"
    export MANIFEST_GIT_ADDITIONAL_REMOTES="${MANIFEST_GIT_ADDITIONAL_REMOTES:-}"
    export MANIFEST_GIT_PUSH_STRATEGY="${MANIFEST_GIT_PUSH_STRATEGY:-simple}"
    export MANIFEST_GIT_PULL_STRATEGY="${MANIFEST_GIT_PULL_STRATEGY:-rebase}"
    
    # Homebrew Configuration
    export MANIFEST_BREW_OPTION="${MANIFEST_BREW_OPTION:-enabled}"
    export MANIFEST_BREW_INTERACTIVE="${MANIFEST_BREW_INTERACTIVE:-no}"
    export MANIFEST_TAP_REPO="${MANIFEST_TAP_REPO:-https://github.com/fidenceio/fidenceio-homebrew-tap.git}"
    
    # Documentation Configuration
    export MANIFEST_DOCS_TEMPLATE_DIR="${MANIFEST_DOCS_TEMPLATE_DIR:-}"
    export MANIFEST_DOCS_AUTO_GENERATE="${MANIFEST_DOCS_AUTO_GENERATE:-true}"
    export MANIFEST_DOCS_HISTORICAL_LIMIT="${MANIFEST_DOCS_HISTORICAL_LIMIT:-20}"
    export MANIFEST_DOCS_FILENAME_PATTERN="${MANIFEST_DOCS_FILENAME_PATTERN:-RELEASE_vVERSION.md}"
    
    # Development & Debugging
    export MANIFEST_DEBUG="${MANIFEST_DEBUG:-false}"
    export MANIFEST_VERBOSE="${MANIFEST_VERBOSE:-false}"
    export MANIFEST_LOG_LEVEL="${MANIFEST_LOG_LEVEL:-INFO}"
    export MANIFEST_INTERACTIVE="${MANIFEST_INTERACTIVE:-true}"
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
    echo "🔧 Current Manifest CLI Configuration:"
    echo ""
    
    echo "📋 Versioning Configuration:"
    echo "   Format: $MANIFEST_VERSION_FORMAT"
    echo "   Separator: $MANIFEST_VERSION_SEPARATOR"
    echo "   Components: $MANIFEST_VERSION_COMPONENTS"
    echo "   Tag Prefix: $MANIFEST_GIT_TAG_PREFIX"
    echo "   Tag Suffix: $MANIFEST_GIT_TAG_SUFFIX"
    echo ""
    
    echo "🌿 Branch Configuration:"
    echo "   Default Branch: $MANIFEST_DEFAULT_BRANCH"
    echo "   Feature Prefix: $MANIFEST_FEATURE_BRANCH_PREFIX"
    echo "   Hotfix Prefix: $MANIFEST_HOTFIX_BRANCH_PREFIX"
    echo "   Release Prefix: $MANIFEST_RELEASE_BRANCH_PREFIX"
    echo "   Development Branch: $MANIFEST_DEVELOPMENT_BRANCH"
    echo ""
    
    echo "🕐 NTP Configuration:"
    echo "   Servers: $MANIFEST_NTP_SERVERS"
    echo "   Timeout: $MANIFEST_NTP_TIMEOUT seconds"
    echo "   Retries: $MANIFEST_NTP_RETRIES"
    echo "   Verify: $MANIFEST_NTP_VERIFY"
    echo ""
    
    echo "📚 Documentation Configuration:"
    echo "   Auto-generate: $MANIFEST_DOCS_AUTO_GENERATE"
    echo "   Historical Limit: $MANIFEST_DOCS_HISTORICAL_LIMIT"
    echo "   Filename Pattern: $MANIFEST_DOCS_FILENAME_PATTERN"
    echo ""
    
    echo "🍺 Homebrew Configuration:"
    echo "   Option: $MANIFEST_BREW_OPTION"
    echo "   Interactive: $MANIFEST_BREW_INTERACTIVE"
    echo ""
    
    echo "🔍 Development Configuration:"
    echo "   Debug: $MANIFEST_DEBUG"
    echo "   Verbose: $MANIFEST_VERBOSE"
    echo "   Log Level: $MANIFEST_LOG_LEVEL"
    echo "   Interactive: $MANIFEST_INTERACTIVE"
}

# Export functions for use in other modules
export -f load_configuration
export -f set_default_configuration
export -f get_config
export -f validate_version_config
export -f parse_version_components
export -f generate_next_version
export -f show_configuration
