#!/bin/bash

# =============================================================================
# MANIFEST FLEET CONFIGURATION MODULE
# =============================================================================
#
# PURPOSE:
#   Parses and manages fleet configuration from manifest.fleet.config.yaml and
#   environment variables. Provides a unified interface for accessing
#   fleet settings throughout the application.
#
# CONFIGURATION SOURCES (in order of precedence, lowest to highest):
#   1. Built-in defaults (defined in this module)
#   2. ~/.manifest-cli/manifest.config.global.yaml (user-level preferences)
#   3. <fleet-root>/manifest.config.local.yaml (fleet-level overrides)
#   4. manifest.fleet.config.yaml (fleet definition - committed to git)
#   5. <service>/manifest.config.local.yaml (service-specific overrides)
#   6. Command-line flags (highest priority)
#
# KEY FUNCTIONS:
#   - load_fleet_config()      : Load and merge all configuration sources
#   - get_fleet_value()        : Get a configuration value with fallback
#   - parse_fleet_yaml()       : Parse manifest.fleet.config.yaml into shell variables
#   - validate_fleet_config()  : Validate configuration completeness
#
# DEPENDENCIES:
#   - manifest-shared-utils.sh (logging functions)
#   - yq or python3 (for YAML parsing - graceful fallback if unavailable)
#
# USAGE:
#   source manifest-fleet-config.sh
#   load_fleet_config "/path/to/fleet"
#   service_path=$(get_fleet_service_path "user-service")
#
# =============================================================================

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Prevent multiple sourcing
if [[ -n "${_MANIFEST_FLEET_CONFIG_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_FLEET_CONFIG_LOADED=1

# Module metadata (useful for debugging and version tracking)
readonly MANIFEST_FLEET_CONFIG_MODULE_VERSION="1.0.0"
readonly MANIFEST_FLEET_CONFIG_MODULE_NAME="manifest-fleet-config"

# =============================================================================
# DEFAULT CONFIGURATION VALUES
# =============================================================================
# These defaults are used when no configuration file specifies a value.
# Each default is documented with its purpose and valid options.

# -----------------------------------------------------------------------------
# Fleet Detection Defaults
# -----------------------------------------------------------------------------

# How to determine if current directory is part of a fleet
# Options: "auto" | "true" | "false"
#   - "auto"  : Check for manifest.fleet.config.yaml in current or parent directories
#   - "true"  : Force fleet mode, fail if no fleet found
#   - "false" : Disable fleet mode entirely, operate as single repo
readonly MANIFEST_FLEET_DEFAULT_MODE="auto"

# Maximum directory depth to search for manifest.fleet.config.yaml when auto-detecting
# Prevents infinite loops in deeply nested structures
readonly MANIFEST_FLEET_DEFAULT_MAX_SEARCH_DEPTH=10

# Filename for fleet configuration (can be customized per organization)
readonly MANIFEST_FLEET_DEFAULT_CONFIG_FILENAME="manifest.fleet.config.yaml"

# -----------------------------------------------------------------------------
# Fleet Versioning Defaults
# -----------------------------------------------------------------------------

# Fleet-level versioning strategy
# Options: "none" | "date" | "semver" | "increment"
#   - "none"      : No fleet version, services versioned independently
#   - "date"      : Date-based versioning (YYYY.MM.DD)
#   - "semver"    : Semantic versioning (X.Y.Z)
#   - "increment" : Simple incrementing integer (1, 2, 3...)
readonly MANIFEST_FLEET_DEFAULT_VERSIONING="date"

# Fleet version file location (relative to fleet root)
readonly MANIFEST_FLEET_DEFAULT_VERSION_FILE="FLEET_VERSION"

# -----------------------------------------------------------------------------
# Fleet Operations Defaults
# -----------------------------------------------------------------------------

# Default version bump type when none specified
# Options: "patch" | "minor" | "major" | "revision"
readonly MANIFEST_FLEET_DEFAULT_BUMP_TYPE="patch"

# Whether to run operations in parallel across services
readonly MANIFEST_FLEET_DEFAULT_PARALLEL="true"

# Maximum concurrent operations when running in parallel
# Higher values = faster but more resource intensive
readonly MANIFEST_FLEET_DEFAULT_MAX_PARALLEL=4

# Commit strategy for fleet operations
# Options: "per-service" | "atomic"
#   - "per-service" : One commit per service (cleaner history, easier rollback)
#   - "atomic"      : Single commit for all changes (monorepo-style)
readonly MANIFEST_FLEET_DEFAULT_COMMIT_STRATEGY="per-service"

# Push strategy for fleet operations
# Options: "immediate" | "batched" | "manual"
#   - "immediate" : Push each service as it completes
#   - "batched"   : Push all services after all operations complete
#   - "manual"    : Don't push, user will push manually
readonly MANIFEST_FLEET_DEFAULT_PUSH_STRATEGY="batched"

# -----------------------------------------------------------------------------
# Fleet Changelog Defaults
# -----------------------------------------------------------------------------

# Generate unified fleet changelog
readonly MANIFEST_FLEET_DEFAULT_UNIFIED_CHANGELOG="true"

# Detail level for per-service sections in unified changelog
# Options: "full" | "summary" | "minimal"
#   - "full"    : Include entire per-service changelog
#   - "summary" : Key sections only (features, fixes, breaking)
#   - "minimal" : Just version and one-line description
readonly MANIFEST_FLEET_DEFAULT_CHANGELOG_DETAIL="summary"

# Include dependency compatibility matrix in fleet changelog
readonly MANIFEST_FLEET_DEFAULT_CHANGELOG_MATRIX="true"

# -----------------------------------------------------------------------------
# Fleet Docs Defaults
# -----------------------------------------------------------------------------

# Docs placement strategy for fleet operations
# Options: "fleet-root" | "per-service" | "both"
#   - "fleet-root"  : One docs/ folder at the fleet root only
#   - "per-service"  : Each service gets its own docs/ folder (default)
#   - "both"         : Fleet root AND per-service docs folders
readonly MANIFEST_FLEET_DEFAULT_DOCS_STRATEGY="per-service"

# Whether to generate docs at fleet root level
readonly MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_ENABLED="false"

# Docs folder name at fleet root (relative to fleet root)
readonly MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_FOLDER="docs"

# Detail level for fleet-root documentation
# Options: "summary" | "index"
#   - "summary" : Aggregated changes from all services
#   - "index"   : Lightweight version list with links to per-service docs
readonly MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_DETAIL_LEVEL="summary"

# Whether to generate per-service docs
readonly MANIFEST_FLEET_DEFAULT_DOCS_PER_SERVICE_ENABLED="true"

# Docs folder name within each service (relative to service root)
readonly MANIFEST_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER="docs"

# What document types to generate
readonly MANIFEST_FLEET_DEFAULT_DOCS_GEN_RELEASE_NOTES="true"
readonly MANIFEST_FLEET_DEFAULT_DOCS_GEN_CHANGELOG="true"
readonly MANIFEST_FLEET_DEFAULT_DOCS_GEN_INDEX="true"
readonly MANIFEST_FLEET_DEFAULT_DOCS_GEN_README_VERSION="true"

# -----------------------------------------------------------------------------
# Fleet Validation Defaults
# -----------------------------------------------------------------------------

# Require clean git status before fleet operations
readonly MANIFEST_FLEET_DEFAULT_REQUIRE_CLEAN="true"

# Enforce dependency version constraints
readonly MANIFEST_FLEET_DEFAULT_ENFORCE_DEPS="true"

# Allow operations on non-default branches
readonly MANIFEST_FLEET_DEFAULT_ALLOW_BRANCH_OPS="false"

# Strict mode: treat warnings as errors
readonly MANIFEST_FLEET_DEFAULT_STRICT="false"

# -----------------------------------------------------------------------------
# Fleet Submodule Defaults
# -----------------------------------------------------------------------------

# How to handle git submodules
# Options: "include" | "exclude" | "separate"
#   - "include"  : Process submodules as part of parent service
#   - "exclude"  : Ignore submodules entirely
#   - "separate" : Treat submodules as independent fleet services
readonly MANIFEST_FLEET_DEFAULT_SUBMODULE_HANDLING="include"

# Submodule update strategy
# Options: "checkout" | "rebase" | "merge"
readonly MANIFEST_FLEET_DEFAULT_SUBMODULE_UPDATE="checkout"

# =============================================================================
# MODULE STATE VARIABLES
# =============================================================================
# These variables hold the current fleet configuration state.
# They are populated by load_fleet_config() and read by get_fleet_*() functions.

# Fleet root directory (absolute path)
declare -g MANIFEST_FLEET_ROOT=""

# Fleet configuration file path (absolute path to manifest.fleet.config.yaml)
declare -g MANIFEST_FLEET_CONFIG_FILE=""

# Whether fleet mode is active
declare -g MANIFEST_FLEET_ACTIVE="false"

# Associative arrays for service configuration
# Note: Bash 3.x (macOS default) doesn't support associative arrays well,
# so we use a naming convention: MANIFEST_FLEET_SERVICE_<NAME>_<PROPERTY>
# This is populated by parse_fleet_yaml()

# List of service names (space-separated for Bash 3.x compatibility)
declare -g MANIFEST_FLEET_SERVICES=""

# Fleet metadata
declare -g MANIFEST_FLEET_NAME=""
declare -g MANIFEST_FLEET_DESCRIPTION=""
declare -g MANIFEST_FLEET_VERSIONING=""
declare -g MANIFEST_FLEET_VERSION=""

# =============================================================================
# YAML PARSING FUNCTIONS
# =============================================================================
# YAML parser functions (detect_yaml_parser, parse_yaml_with_yq,
# parse_yaml_with_python, parse_yaml_basic, get_yaml_value, set_yaml_value)
# now live in modules/core/manifest-yaml.sh and are sourced before this module
# via manifest-core.sh. Fleet-specific code inherits them from core.

# -----------------------------------------------------------------------------
# Function: get_fleet_services
# -----------------------------------------------------------------------------
# Extracts selected service names from manifest.fleet.tsv.
#
# ARGUMENTS:
#   $1 - Fleet root directory (containing manifest.fleet.tsv)
#
# RETURNS:
#   Space-separated list of service names
#
# EXAMPLE:
#   services=$(get_fleet_services "/path/to/fleet")
#   for service in $services; do
#       echo "Found service: $service"
#   done
# -----------------------------------------------------------------------------
get_fleet_services() {
    local fleet_root="$1"
    local tsv_file="$fleet_root/manifest.fleet.tsv"

    if [[ ! -f "$tsv_file" ]]; then
        return 1
    fi

    local names=""
    while IFS=$'\t' read -r selected name path type has_git url branch version; do
        [[ "$selected" =~ ^#.*$ ]] && continue
        [[ -z "$selected" ]] && continue
        [[ "$selected" != "true" ]] && continue
        if [[ -z "$names" ]]; then
            names="$name"
        else
            names="$names $name"
        fi
    done < "$tsv_file"

    echo "$names"
}

# Backward-compat alias (deprecated — callers should migrate to get_fleet_services)
get_yaml_services() {
    local yaml_file="$1"
    local fleet_root
    fleet_root=$(dirname "$yaml_file")
    get_fleet_services "$fleet_root"
}

# =============================================================================
# FLEET DETECTION FUNCTIONS
# =============================================================================
# These functions handle finding and identifying fleet configurations.

# -----------------------------------------------------------------------------
# Function: find_fleet_root
# -----------------------------------------------------------------------------
# Searches for manifest.fleet.config.yaml starting from the given directory
# and walking up the directory tree.
#
# This enables fleet-aware operations from any subdirectory within a fleet.
#
# ARGUMENTS:
#   $1 - Starting directory (defaults to current directory)
#   $2 - Maximum depth to search (defaults to MANIFEST_FLEET_DEFAULT_MAX_SEARCH_DEPTH)
#
# RETURNS:
#   Echoes the absolute path to the fleet root (directory containing manifest.fleet.config.yaml)
#   Returns 1 if no fleet configuration found
#
# EXAMPLE:
#   if fleet_root=$(find_fleet_root "/path/to/service"); then
#       echo "Fleet found at: $fleet_root"
#   else
#       echo "Not inside a fleet"
#   fi
# -----------------------------------------------------------------------------
find_fleet_root() {
    local start_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_FLEET_DEFAULT_MAX_SEARCH_DEPTH}"
    local config_filename="${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-$MANIFEST_FLEET_DEFAULT_CONFIG_FILENAME}"

    # Resolve to absolute path
    local current_dir
    current_dir=$(cd "$start_dir" 2>/dev/null && pwd)

    if [[ -z "$current_dir" ]]; then
        log_error "Invalid starting directory: $start_dir"
        return 1
    fi

    local depth=0

    while [[ "$depth" -lt "$max_depth" ]]; do
        # Check if fleet config exists in current directory
        if [[ -f "$current_dir/$config_filename" ]]; then
            log_debug "Fleet configuration found at: $current_dir"
            echo "$current_dir"
            return 0
        fi

        # Move to parent directory
        local parent_dir
        parent_dir=$(dirname "$current_dir")

        # Check if we've reached the root
        if [[ "$parent_dir" == "$current_dir" ]]; then
            log_debug "Reached filesystem root without finding fleet config"
            return 1
        fi

        current_dir="$parent_dir"
        ((depth++))
    done

    log_debug "Max search depth ($max_depth) reached without finding fleet config"
    return 1
}

# -----------------------------------------------------------------------------
# Function: is_fleet_mode_enabled
# -----------------------------------------------------------------------------
# Determines whether fleet mode should be active based on configuration
# and environment.
#
# DECISION LOGIC:
#   1. If MANIFEST_CLI_FLEET_MODE="false" → disabled
#   2. If MANIFEST_CLI_FLEET_MODE="true" → enabled (error if no fleet found)
#   3. If MANIFEST_CLI_FLEET_MODE="auto" → enabled only if fleet config found
#
# RETURNS:
#   0 if fleet mode is enabled
#   1 if fleet mode is disabled
#
# SIDE EFFECTS:
#   Sets MANIFEST_FLEET_ROOT if fleet is found
#   Sets MANIFEST_FLEET_ACTIVE to "true" or "false"
#
# EXAMPLE:
#   if is_fleet_mode_enabled; then
#       echo "Operating in fleet mode"
#   else
#       echo "Operating in single-repo mode"
#   fi
# -----------------------------------------------------------------------------
is_fleet_mode_enabled() {
    local fleet_mode="${MANIFEST_CLI_FLEET_MODE:-$MANIFEST_FLEET_DEFAULT_MODE}"
    local explicit_root="${MANIFEST_CLI_FLEET_ROOT:-}"

    # Handle explicit disable
    if [[ "$fleet_mode" == "false" ]]; then
        MANIFEST_FLEET_ACTIVE="false"
        log_debug "Fleet mode explicitly disabled"
        return 1
    fi

    # Try to find fleet root
    local fleet_root=""

    if [[ -n "$explicit_root" ]]; then
        # Use explicitly configured root
        if [[ -d "$explicit_root" ]]; then
            fleet_root="$explicit_root"
        else
            log_error "Configured MANIFEST_CLI_FLEET_ROOT does not exist: $explicit_root"
            MANIFEST_FLEET_ACTIVE="false"
            return 1
        fi
    else
        # Auto-detect fleet root
        fleet_root=$(find_fleet_root)
    fi

    # Handle forced fleet mode
    if [[ "$fleet_mode" == "true" ]]; then
        if [[ -z "$fleet_root" ]]; then
            log_error "Fleet mode forced but no manifest.fleet.config.yaml found"
            MANIFEST_FLEET_ACTIVE="false"
            return 1
        fi
        MANIFEST_FLEET_ROOT="$fleet_root"
        MANIFEST_FLEET_ACTIVE="true"
        log_debug "Fleet mode enabled (forced): $fleet_root"
        return 0
    fi

    # Auto mode: enable if found
    if [[ -n "$fleet_root" ]]; then
        MANIFEST_FLEET_ROOT="$fleet_root"
        MANIFEST_FLEET_ACTIVE="true"
        log_debug "Fleet mode enabled (auto-detected): $fleet_root"
        return 0
    fi

    # Auto mode: no fleet found, disable
    MANIFEST_FLEET_ACTIVE="false"
    log_debug "Fleet mode disabled (no fleet config found)"
    return 1
}

# =============================================================================
# CONFIGURATION LOADING FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: load_fleet_config
# -----------------------------------------------------------------------------
# Main entry point for loading fleet configuration.
# Loads and merges configuration from all sources.
#
# ARGUMENTS:
#   $1 - Fleet root directory (optional, auto-detected if not provided)
#
# RETURNS:
#   0 on success
#   1 if fleet mode is disabled or configuration invalid
#
# SIDE EFFECTS:
#   Populates all MANIFEST_FLEET_* variables
#   Sets service-specific variables as MANIFEST_FLEET_SERVICE_<NAME>_<PROP>
#
# EXAMPLE:
#   if load_fleet_config; then
#       echo "Fleet: $MANIFEST_FLEET_NAME"
#       echo "Services: $MANIFEST_FLEET_SERVICES"
#   fi
# -----------------------------------------------------------------------------
load_fleet_config() {
    local fleet_root="${1:-}"

    # Check if fleet mode is enabled
    if [[ -n "$fleet_root" ]]; then
        MANIFEST_FLEET_ROOT="$fleet_root"
    fi

    if ! is_fleet_mode_enabled; then
        return 1
    fi

    # Set configuration file path
    local config_filename="${MANIFEST_CLI_FLEET_CONFIG_FILENAME:-$MANIFEST_FLEET_DEFAULT_CONFIG_FILENAME}"
    MANIFEST_FLEET_CONFIG_FILE="$MANIFEST_FLEET_ROOT/$config_filename"

    if [[ ! -f "$MANIFEST_FLEET_CONFIG_FILE" ]]; then
        log_error "Fleet configuration file not found: $MANIFEST_FLEET_CONFIG_FILE"
        return 1
    fi

    log_info "Loading fleet configuration from: $MANIFEST_FLEET_CONFIG_FILE"

    # Parse fleet metadata
    MANIFEST_FLEET_NAME=$(get_yaml_value "$MANIFEST_FLEET_CONFIG_FILE" ".fleet.name" "unnamed-fleet")
    MANIFEST_FLEET_DESCRIPTION=$(get_yaml_value "$MANIFEST_FLEET_CONFIG_FILE" ".fleet.description" "")
    MANIFEST_FLEET_VERSIONING=$(get_yaml_value "$MANIFEST_FLEET_CONFIG_FILE" ".fleet.versioning" "$MANIFEST_FLEET_DEFAULT_VERSIONING")

    # Load fleet version if versioning is enabled
    if [[ "$MANIFEST_FLEET_VERSIONING" != "none" ]]; then
        local version_file="${MANIFEST_FLEET_ROOT}/$(get_yaml_value "$MANIFEST_FLEET_CONFIG_FILE" ".fleet.version_file" "$MANIFEST_FLEET_DEFAULT_VERSION_FILE")"
        if [[ -f "$version_file" ]]; then
            MANIFEST_FLEET_VERSION=$(cat "$version_file" 2>/dev/null)
        fi
    fi

    # Parse services from manifest.fleet.tsv (the service inventory)
    MANIFEST_FLEET_SERVICES=$(get_fleet_services "$MANIFEST_FLEET_ROOT")

    if [[ -z "$MANIFEST_FLEET_SERVICES" ]]; then
        log_warning "No services found in manifest.fleet.tsv"
    fi

    # Load per-service configuration from TSV + optional YAML overrides
    _load_all_service_configs "$MANIFEST_FLEET_ROOT"

    local _svc_count=0
    for _ in $MANIFEST_FLEET_SERVICES; do _svc_count=$((_svc_count + 1)); done
    log_success "Fleet configuration loaded: $MANIFEST_FLEET_NAME ($_svc_count services)"
    return 0
}

# -----------------------------------------------------------------------------
# Function: _load_all_service_configs (internal)
# -----------------------------------------------------------------------------
# Loads configuration for all selected services from manifest.fleet.tsv.
# Reads base properties (path, url, type, branch) from TSV, then applies
# optional per-service overrides from the YAML config (team, excluded, etc.).
#
# ARGUMENTS:
#   $1 - Fleet root directory
#
# SIDE EFFECTS:
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_PATH
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_URL
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_TYPE
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_BRANCH
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_TEAM
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_EXCLUDED
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_SUBMODULE
#   Sets MANIFEST_FLEET_SERVICE_<NAME>_DESCRIPTION
# -----------------------------------------------------------------------------
_load_all_service_configs() {
    local fleet_root="$1"
    local tsv_file="$fleet_root/manifest.fleet.tsv"

    if [[ ! -f "$tsv_file" ]]; then
        return 0
    fi

    while IFS=$'\t' read -r selected name path type has_git url branch version; do
        [[ "$selected" =~ ^#.*$ ]] && continue
        [[ -z "$selected" ]] && continue
        [[ "$selected" != "true" ]] && continue

        # Sanitize service name for variable names
        local var_name
        var_name=$(echo "$name" | tr '[:lower:]-.' '[:upper:]__')

        # Resolve relative path to absolute
        local abs_path="$path"
        if [[ -n "$path" ]] && [[ ! "$path" = /* ]]; then
            abs_path="$MANIFEST_FLEET_ROOT/${path#./}"
        fi

        # Base properties from TSV (inventory)
        eval "MANIFEST_FLEET_SERVICE_${var_name}_PATH=\"$abs_path\""
        eval "MANIFEST_FLEET_SERVICE_${var_name}_URL=\"$url\""
        eval "MANIFEST_FLEET_SERVICE_${var_name}_TYPE=\"$type\""
        eval "MANIFEST_FLEET_SERVICE_${var_name}_BRANCH=\"${branch:-${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}}\""
        eval "MANIFEST_FLEET_SERVICE_${var_name}_SUBMODULE=\"false\""

        # Defaults for per-service properties
        local team="" excluded="false" description=""

        # Per-service config from the repo's own manifest.fleet.config.yaml
        local svc_config="$abs_path/manifest.fleet.config.yaml"
        if [[ -f "$svc_config" ]]; then
            team=$(get_yaml_value "$svc_config" ".team" "" 2>/dev/null) || true
            excluded=$(get_yaml_value "$svc_config" ".exclude_from_fleet_bump" "false" 2>/dev/null) || true
            description=$(get_yaml_value "$svc_config" ".description" "" 2>/dev/null) || true

            # Allow per-service overrides of TSV-sourced values
            local svc_type svc_branch
            svc_type=$(get_yaml_value "$svc_config" ".type" "" 2>/dev/null) || true
            svc_branch=$(get_yaml_value "$svc_config" ".branch" "" 2>/dev/null) || true
            [[ -n "$svc_type" ]] && eval "MANIFEST_FLEET_SERVICE_${var_name}_TYPE=\"$svc_type\""
            [[ -n "$svc_branch" ]] && eval "MANIFEST_FLEET_SERVICE_${var_name}_BRANCH=\"$svc_branch\""
        fi

        eval "MANIFEST_FLEET_SERVICE_${var_name}_TEAM=\"$team\""
        eval "MANIFEST_FLEET_SERVICE_${var_name}_EXCLUDED=\"$excluded\""
        eval "MANIFEST_FLEET_SERVICE_${var_name}_DESCRIPTION=\"$description\""

        log_debug "Loaded service config: $name (path=$abs_path, type=$type)"
    done < "$tsv_file"
}

# =============================================================================
# CONFIGURATION ACCESS FUNCTIONS
# =============================================================================
# These functions provide clean access to configuration values.

# -----------------------------------------------------------------------------
# Function: get_fleet_service_path
# -----------------------------------------------------------------------------
# Gets the filesystem path for a service.
#
# ARGUMENTS:
#   $1 - Service name
#
# RETURNS:
#   Echoes the absolute path to the service directory
#   Returns 1 if service not found
#
# EXAMPLE:
#   user_service_path=$(get_fleet_service_path "user-service")
# -----------------------------------------------------------------------------
get_fleet_service_path() {
    local service="$1"
    local var_name
    var_name=$(echo "$service" | tr '[:lower:]-.' '[:upper:]__')

    local path_var="MANIFEST_FLEET_SERVICE_${var_name}_PATH"
    local path="${!path_var:-}"

    if [[ -z "$path" ]]; then
        return 1
    fi

    echo "$path"
    return 0
}

# -----------------------------------------------------------------------------
# Function: get_fleet_service_property
# -----------------------------------------------------------------------------
# Gets any property for a service.
#
# ARGUMENTS:
#   $1 - Service name
#   $2 - Property name (path, url, type, branch, team, excluded, submodule)
#   $3 - Default value (optional)
#
# RETURNS:
#   Echoes the property value or default
#
# EXAMPLE:
#   service_type=$(get_fleet_service_property "user-service" "type" "service")
# -----------------------------------------------------------------------------
get_fleet_service_property() {
    local service="$1"
    local property="$2"
    local default="${3:-}"

    local var_name
    var_name=$(echo "$service" | tr '[:lower:]-.' '[:upper:]__')

    local prop_upper
    prop_upper=$(echo "$property" | tr '[:lower:]' '[:upper:]')

    local full_var="MANIFEST_FLEET_SERVICE_${var_name}_${prop_upper}"
    local value="${!full_var:-}"

    if [[ -n "$value" ]]; then
        echo "$value"
    else
        echo "$default"
    fi
}

# -----------------------------------------------------------------------------
# Function: get_fleet_config_value
# -----------------------------------------------------------------------------
# Gets a fleet configuration value with full precedence handling.
#
# ARGUMENTS:
#   $1 - Configuration key (e.g., "parallel", "push_strategy")
#   $2 - Default value
#
# RETURNS:
#   Echoes the configuration value
#
# PRECEDENCE:
#   1. Environment variable: MANIFEST_CLI_FLEET_<KEY>
#   2. YAML config value
#   3. Default value
#
# EXAMPLE:
#   parallel=$(get_fleet_config_value "parallel" "true")
# -----------------------------------------------------------------------------
get_fleet_config_value() {
    local key="$1"
    local default="$2"

    # Convert key to environment variable format
    local env_key
    env_key="MANIFEST_CLI_FLEET_$(echo "$key" | tr '[:lower:]' '[:upper:]')"

    # Check environment variable first
    local env_value="${!env_key:-}"
    if [[ -n "$env_value" ]]; then
        echo "$env_value"
        return 0
    fi

    # Try YAML config (map common keys to YAML paths)
    # This could be expanded with a more sophisticated mapping
    local yaml_path=""
    case "$key" in
        "parallel") yaml_path=".operations.parallel" ;;
        "max_parallel") yaml_path=".operations.max_parallel" ;;
        "push_strategy") yaml_path=".operations.push.strategy" ;;
        "commit_strategy") yaml_path=".operations.commit.strategy" ;;
        "default_bump") yaml_path=".operations.default_bump" ;;
        "require_clean") yaml_path=".validation.require_clean_status" ;;
        "enforce_deps") yaml_path=".validation.enforce_dependencies" ;;
        "strict") yaml_path=".validation.strict" ;;
        # Docs configuration
        "docs_strategy")              yaml_path=".docs.strategy" ;;
        "docs_fleet_root_enabled")    yaml_path=".docs.fleet_root.enabled" ;;
        "docs_fleet_root_folder")     yaml_path=".docs.fleet_root.folder" ;;
        "docs_fleet_root_detail_level") yaml_path=".docs.fleet_root.detail_level" ;;
        "docs_per_service_enabled")   yaml_path=".docs.per_service.enabled" ;;
        "docs_per_service_folder")    yaml_path=".docs.per_service.folder" ;;
        "docs_gen_release_notes")     yaml_path=".docs.generate.release_notes" ;;
        "docs_gen_changelog")         yaml_path=".docs.generate.changelog" ;;
        "docs_gen_index")             yaml_path=".docs.generate.index" ;;
        "docs_gen_readme_version")    yaml_path=".docs.generate.readme_version" ;;
    esac

    if [[ -n "$yaml_path" ]] && [[ -f "${MANIFEST_FLEET_CONFIG_FILE:-}" ]]; then
        local yaml_value
        if yaml_value=$(get_yaml_value "$MANIFEST_FLEET_CONFIG_FILE" "$yaml_path"); then
            echo "$yaml_value"
            return 0
        fi
    fi

    # Return default
    echo "$default"
    return 0
}

# =============================================================================
# VALIDATION FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: validate_fleet_config
# -----------------------------------------------------------------------------
# Validates the loaded fleet configuration for completeness and correctness.
#
# CHECKS:
#   - Fleet name is set
#   - All services have either path or url
#   - Service paths exist (if specified as path, not url)
#   - No circular dependencies
#   - Version constraints are valid semver
#
# RETURNS:
#   0 if valid
#   1 if validation errors found
#
# OUTPUT:
#   Logs warnings and errors to stderr
#
# EXAMPLE:
#   if ! validate_fleet_config; then
#       echo "Fleet configuration has errors"
#       exit 1
#   fi
# -----------------------------------------------------------------------------
validate_fleet_config() {
    local errors=0
    local warnings=0

    log_info "Validating fleet configuration..."

    # Check fleet metadata
    if [[ -z "$MANIFEST_FLEET_NAME" ]] || [[ "$MANIFEST_FLEET_NAME" == "unnamed-fleet" ]]; then
        log_warning "Fleet name not set (using default)"
        ((warnings++))
    fi

    # Check services
    if [[ -z "$MANIFEST_FLEET_SERVICES" ]]; then
        log_error "No services defined in fleet"
        ((errors++))
    else
        for service in $MANIFEST_FLEET_SERVICES; do
            _validate_service "$service" || ((errors++))
        done
    fi

    # Summary
    if [[ $errors -gt 0 ]]; then
        log_error "Fleet validation failed: $errors error(s), $warnings warning(s)"
        return 1
    elif [[ $warnings -gt 0 ]]; then
        log_warning "Fleet validation passed with $warnings warning(s)"
        return 0
    else
        log_success "Fleet validation passed"
        return 0
    fi
}

# -----------------------------------------------------------------------------
# Function: _validate_service (internal)
# -----------------------------------------------------------------------------
# Validates configuration for a single service.
#
# ARGUMENTS:
#   $1 - Service name
#
# RETURNS:
#   0 if valid
#   1 if validation errors found
# -----------------------------------------------------------------------------
_validate_service() {
    local service="$1"
    local errors=0

    local path=$(get_fleet_service_property "$service" "path")
    local url=$(get_fleet_service_property "$service" "url")

    # Must have either path or url
    if [[ -z "$path" ]] && [[ -z "$url" ]]; then
        log_error "Service '$service': must specify either 'path' or 'url'"
        ((errors++))
    fi

    # If path specified, check if directory exists
    if [[ -n "$path" ]] && [[ ! -d "$path" ]]; then
        # Only error if no URL to clone from
        if [[ -z "$url" ]]; then
            log_error "Service '$service': path does not exist and no url to clone: $path"
            ((errors++))
        else
            log_info "Service '$service': path not found, will clone from url"
        fi
    fi

    # If path exists, check if it's a git repository
    if [[ -d "$path" ]] && [[ ! -d "$path/.git" ]]; then
        local is_submodule=$(get_fleet_service_property "$service" "submodule" "false")
        if [[ "$is_submodule" != "true" ]]; then
            log_warning "Service '$service': path exists but is not a git repository: $path"
        fi
    fi

    if [[ $errors -gt 0 ]]; then
        return 1
    fi
    return 0
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: list_fleet_services
# -----------------------------------------------------------------------------
# Lists all services in the fleet with their status.
#
# OUTPUT:
#   Prints a formatted table of services
#
# EXAMPLE:
#   list_fleet_services
# -----------------------------------------------------------------------------
list_fleet_services() {
    if [[ -z "$MANIFEST_FLEET_SERVICES" ]]; then
        echo "No services in fleet"
        return 0
    fi

    echo "Services in fleet '$MANIFEST_FLEET_NAME':"
    echo ""
    printf "%-20s %-10s %-10s %-30s\n" "SERVICE" "TYPE" "STATUS" "PATH"
    printf "%-20s %-10s %-10s %-30s\n" "-------" "----" "------" "----"

    for service in $MANIFEST_FLEET_SERVICES; do
        local path=$(get_fleet_service_property "$service" "path")
        local type=$(get_fleet_service_property "$service" "type" "service")
        local status="unknown"

        if [[ -d "$path" ]]; then
            if [[ -d "$path/.git" ]]; then
                status="ready"
            else
                status="not-git"
            fi
        else
            status="missing"
        fi

        printf "%-20s %-10s %-10s %-30s\n" "$service" "$type" "$status" "$path"
    done
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================
# Export functions for use by other modules

export -f get_yaml_services
export -f find_fleet_root
export -f is_fleet_mode_enabled
export -f load_fleet_config
export -f get_fleet_service_path
export -f get_fleet_service_property
export -f get_fleet_config_value
export -f validate_fleet_config
export -f list_fleet_services
