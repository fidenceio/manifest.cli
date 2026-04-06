#!/bin/bash

# Manifest YAML Module
# Provides unified YAML parsing, writing, and configuration mapping for all modules.
#
# This module is the foundation for Manifest CLI's migration from .env to YAML
# configuration. It extracts and extends YAML parser functions originally in the
# fleet module, adds YAML writer capabilities, and defines the bidirectional
# mapping between YAML dot-paths and MANIFEST_CLI_* environment variables.
#
# Dependencies:
#   - manifest-shared-utils.sh (for log_debug, log_error, log_warning)
#   - bash 5+ (for associative arrays with declare -gA)
#
# External tool support (in order of preference):
#   - yq (Mike Farah's Go version, v4+)
#   - python3 with PyYAML (yaml.safe_load)
#   - grep/sed fallback (read-only, top-level keys only)

# Guard: provide no-op log functions if shared-utils not yet sourced
if ! command -v log_debug &>/dev/null; then
    log_debug()   { :; }
    log_error()   { echo "ERROR: $*" >&2; }
    log_warning() { echo "WARNING: $*" >&2; }
fi

# =============================================================================
# YAML-to-ENV Mapping Table
# =============================================================================
# Bidirectional map between YAML dot-paths and MANIFEST_CLI_* env var names.
# Sections are grouped for readability.

declare -gA _MANIFEST_YAML_TO_ENV=(
    # -------------------------------------------------------------------------
    # version — versioning scheme configuration
    # -------------------------------------------------------------------------
    ["version.format"]="MANIFEST_CLI_VERSION_FORMAT"
    ["version.separator"]="MANIFEST_CLI_VERSION_SEPARATOR"
    ["version.components"]="MANIFEST_CLI_VERSION_COMPONENTS"
    ["version.max_values"]="MANIFEST_CLI_VERSION_MAX_VALUES"
    ["version.component_position.major"]="MANIFEST_CLI_MAJOR_COMPONENT_POSITION"
    ["version.component_position.minor"]="MANIFEST_CLI_MINOR_COMPONENT_POSITION"
    ["version.component_position.patch"]="MANIFEST_CLI_PATCH_COMPONENT_POSITION"
    ["version.component_position.revision"]="MANIFEST_CLI_REVISION_COMPONENT_POSITION"
    ["version.increment_target.major"]="MANIFEST_CLI_MAJOR_INCREMENT_TARGET"
    ["version.increment_target.minor"]="MANIFEST_CLI_MINOR_INCREMENT_TARGET"
    ["version.increment_target.patch"]="MANIFEST_CLI_PATCH_INCREMENT_TARGET"
    ["version.increment_target.revision"]="MANIFEST_CLI_REVISION_INCREMENT_TARGET"
    ["version.reset_components.major"]="MANIFEST_CLI_MAJOR_RESET_COMPONENTS"
    ["version.reset_components.minor"]="MANIFEST_CLI_MINOR_RESET_COMPONENTS"
    ["version.reset_components.patch"]="MANIFEST_CLI_PATCH_RESET_COMPONENTS"
    ["version.reset_components.revision"]="MANIFEST_CLI_REVISION_RESET_COMPONENTS"
    ["version.regex"]="MANIFEST_CLI_VERSION_REGEX"
    ["version.validation"]="MANIFEST_CLI_VERSION_VALIDATION"

    # -------------------------------------------------------------------------
    # git — git workflow configuration
    # -------------------------------------------------------------------------
    ["git.tag_prefix"]="MANIFEST_CLI_GIT_TAG_PREFIX"
    ["git.tag_suffix"]="MANIFEST_CLI_GIT_TAG_SUFFIX"
    ["git.default_branch"]="MANIFEST_CLI_GIT_DEFAULT_BRANCH"
    ["git.development_branch"]="MANIFEST_CLI_GIT_DEVELOPMENT_BRANCH"
    ["git.staging_branch"]="MANIFEST_CLI_GIT_STAGING_BRANCH"
    ["git.feature_prefix"]="MANIFEST_CLI_GIT_FEATURE_BRANCH_PREFIX"
    ["git.hotfix_prefix"]="MANIFEST_CLI_GIT_HOTFIX_BRANCH_PREFIX"
    ["git.release_prefix"]="MANIFEST_CLI_GIT_RELEASE_BRANCH_PREFIX"
    ["git.bugfix_prefix"]="MANIFEST_CLI_GIT_BUGFIX_BRANCH_PREFIX"
    ["git.commit_template"]="MANIFEST_CLI_GIT_COMMIT_TEMPLATE"
    ["git.push_strategy"]="MANIFEST_CLI_GIT_PUSH_STRATEGY"
    ["git.pull_strategy"]="MANIFEST_CLI_GIT_PULL_STRATEGY"
    ["git.timeout"]="MANIFEST_CLI_GIT_TIMEOUT"
    ["git.retries"]="MANIFEST_CLI_GIT_RETRIES"

    # -------------------------------------------------------------------------
    # time — NTP time verification and caching
    # -------------------------------------------------------------------------
    ["time.server1"]="MANIFEST_CLI_TIME_SERVER1"
    ["time.server2"]="MANIFEST_CLI_TIME_SERVER2"
    ["time.server3"]="MANIFEST_CLI_TIME_SERVER3"
    ["time.server4"]="MANIFEST_CLI_TIME_SERVER4"
    ["time.timeout"]="MANIFEST_CLI_TIME_TIMEOUT"
    ["time.retries"]="MANIFEST_CLI_TIME_RETRIES"
    ["time.verify"]="MANIFEST_CLI_TIME_VERIFY"
    ["time.cache_ttl"]="MANIFEST_CLI_TIME_CACHE_TTL"
    ["time.cache_cleanup_period"]="MANIFEST_CLI_TIME_CACHE_CLEANUP_PERIOD"
    ["time.cache_stale_max_age"]="MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE"
    ["time.timezone"]="MANIFEST_CLI_TIMEZONE"

    # -------------------------------------------------------------------------
    # docs — documentation generation
    # -------------------------------------------------------------------------
    ["docs.folder"]="MANIFEST_CLI_DOCS_FOLDER"
    ["docs.archive_folder"]="MANIFEST_CLI_DOCS_ARCHIVE_FOLDER"
    ["docs.template_dir"]="MANIFEST_CLI_DOCS_TEMPLATE_DIR"
    ["docs.auto_generate"]="MANIFEST_CLI_DOCS_AUTO_GENERATE"
    ["docs.historical_limit"]="MANIFEST_CLI_DOCS_HISTORICAL_LIMIT"
    ["docs.filename_pattern"]="MANIFEST_CLI_DOCS_FILENAME_PATTERN"

    # -------------------------------------------------------------------------
    # files — file and directory paths
    # -------------------------------------------------------------------------
    ["files.readme"]="MANIFEST_CLI_README_FILE"
    ["files.version"]="MANIFEST_CLI_VERSION_FILE"
    ["files.gitignore"]="MANIFEST_CLI_GITIGNORE_FILE"
    ["files.archive_dir"]="MANIFEST_CLI_DOCUMENTATION_ARCHIVE_DIR"
    ["files.git_dir"]="MANIFEST_CLI_GIT_DIR"
    ["files.modules_dir"]="MANIFEST_CLI_MODULES_DIR"
    ["files.markdown_ext"]="MANIFEST_CLI_MARKDOWN_EXT"

    # -------------------------------------------------------------------------
    # install — installation paths
    # -------------------------------------------------------------------------
    ["install.dir"]="MANIFEST_CLI_INSTALL_DIR"
    ["install.bin_dir"]="MANIFEST_CLI_BIN_DIR"
    ["install.temp_dir"]="MANIFEST_CLI_TEMP_DIR"
    ["install.temp_list"]="MANIFEST_CLI_TEMP_LIST"

    # -------------------------------------------------------------------------
    # brew — Homebrew integration
    # -------------------------------------------------------------------------
    ["brew.option"]="MANIFEST_CLI_BREW_OPTION"
    ["brew.interactive"]="MANIFEST_CLI_BREW_INTERACTIVE"
    ["brew.tap_repo"]="MANIFEST_CLI_TAP_REPO"

    # -------------------------------------------------------------------------
    # project — project metadata
    # -------------------------------------------------------------------------
    ["project.name"]="MANIFEST_CLI_PROJECT_NAME"
    ["project.description"]="MANIFEST_CLI_PROJECT_DESCRIPTION"
    ["project.organization"]="MANIFEST_CLI_ORGANIZATION"

    # -------------------------------------------------------------------------
    # auto_update — automatic update settings
    # -------------------------------------------------------------------------
    ["auto_update.enabled"]="MANIFEST_CLI_AUTO_UPDATE"
    ["auto_update.cooldown"]="MANIFEST_CLI_UPDATE_COOLDOWN"

    # -------------------------------------------------------------------------
    # config — schema versioning
    # -------------------------------------------------------------------------
    ["config.schema_version"]="MANIFEST_CLI_CONFIG_SCHEMA_VERSION"

    # -------------------------------------------------------------------------
    # debug — debugging and verbosity
    # -------------------------------------------------------------------------
    ["debug.enabled"]="MANIFEST_CLI_DEBUG"
    ["debug.verbose"]="MANIFEST_CLI_VERBOSE"
    ["debug.log_level"]="MANIFEST_CLI_LOG_LEVEL"
    ["debug.interactive"]="MANIFEST_CLI_INTERACTIVE"

    # -------------------------------------------------------------------------
    # pr — pull request settings
    # -------------------------------------------------------------------------
    ["pr.profile"]="MANIFEST_CLI_PR_PROFILE"
    ["pr.enforce_ready"]="MANIFEST_CLI_PR_ENFORCE_READY"
)

# Build the reverse map (ENV var -> YAML path) programmatically
declare -gA _MANIFEST_ENV_TO_YAML=()
for _yaml_path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
    _MANIFEST_ENV_TO_YAML["${_MANIFEST_YAML_TO_ENV[$_yaml_path]}"]="$_yaml_path"
done
unset _yaml_path

# =============================================================================
# Mapping Helpers
# =============================================================================

# -----------------------------------------------------------------------------
# Function: yaml_path_to_env_var
# -----------------------------------------------------------------------------
# Looks up the MANIFEST_CLI_* env var name for a given YAML dot-path.
#
# ARGUMENTS:
#   $1 - YAML dot-path (e.g., "git.tag_prefix")
#
# RETURNS:
#   Echoes the env var name, or returns 1 if not found
# -----------------------------------------------------------------------------
yaml_path_to_env_var() {
    local dotpath="$1"

    if [[ -z "$dotpath" ]]; then
        log_error "yaml_path_to_env_var: no dot-path provided"
        return 1
    fi

    local env_var="${_MANIFEST_YAML_TO_ENV[$dotpath]:-}"
    if [[ -z "$env_var" ]]; then
        log_debug "yaml_path_to_env_var: no mapping for dot-path '$dotpath'"
        return 1
    fi

    echo "$env_var"
    return 0
}

# -----------------------------------------------------------------------------
# Function: env_var_to_yaml_path
# -----------------------------------------------------------------------------
# Looks up the YAML dot-path for a given MANIFEST_CLI_* env var name.
#
# ARGUMENTS:
#   $1 - Environment variable name (e.g., "MANIFEST_CLI_GIT_TAG_PREFIX")
#
# RETURNS:
#   Echoes the YAML dot-path, or returns 1 if not found
# -----------------------------------------------------------------------------
env_var_to_yaml_path() {
    local envvar="$1"

    if [[ -z "$envvar" ]]; then
        log_error "env_var_to_yaml_path: no env var name provided"
        return 1
    fi

    local yaml_path="${_MANIFEST_ENV_TO_YAML[$envvar]:-}"
    if [[ -z "$yaml_path" ]]; then
        log_debug "env_var_to_yaml_path: no mapping for env var '$envvar'"
        return 1
    fi

    echo "$yaml_path"
    return 0
}

# =============================================================================
# YAML Parser Functions
# =============================================================================

# -----------------------------------------------------------------------------
# Function: detect_yaml_parser
# -----------------------------------------------------------------------------
# Detects the best available YAML parser on the system.
#
# RETURNS:
#   Echoes "yq", "python", or "none"
# -----------------------------------------------------------------------------
detect_yaml_parser() {
    # Check for yq (Mike Farah's version, most common)
    if command -v yq &>/dev/null; then
        # Verify it's the Go version (not the Python wrapper)
        if yq --version 2>&1 | grep -q "mikefarah\|version v4"; then
            echo "yq"
            return 0
        fi
    fi

    # Check for python3 with yaml module
    if command -v python3 &>/dev/null; then
        if python3 -c "import yaml" 2>/dev/null; then
            echo "python"
            return 0
        fi
    fi

    # No parser available
    echo "none"
    return 0
}

# -----------------------------------------------------------------------------
# Function: parse_yaml_with_yq
# -----------------------------------------------------------------------------
# Parses YAML using yq (Mike Farah's Go version).
#
# ARGUMENTS:
#   $1 - Path to YAML file
#   $2 - YAML path expression (e.g., ".fleet.name")
#
# RETURNS:
#   Echoes the value at the specified path
#   Returns 1 if path doesn't exist or file is invalid
#
# EXAMPLE:
#   value=$(parse_yaml_with_yq "config.yaml" ".git.tag_prefix")
# -----------------------------------------------------------------------------
parse_yaml_with_yq() {
    local yaml_file="$1"
    local yaml_path="$2"

    if [[ ! -f "$yaml_file" ]]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    # Use yq to extract value
    # The 'e' command evaluates the expression
    # We use -r for raw output (no quotes around strings)
    local value
    value=$(yq e "$yaml_path // \"\"" "$yaml_file" 2>/dev/null)

    # Check if value is "null" (yq's representation of missing keys)
    if [[ "$value" == "null" ]] || [[ -z "$value" ]]; then
        return 1
    fi

    echo "$value"
    return 0
}

# -----------------------------------------------------------------------------
# Function: parse_yaml_with_python
# -----------------------------------------------------------------------------
# Parses YAML using Python's yaml module.
#
# ARGUMENTS:
#   $1 - Path to YAML file
#   $2 - Dot-notation path (e.g., "fleet.name" — note: no leading dot)
#
# RETURNS:
#   Echoes the value at the specified path
#   Returns 1 if path doesn't exist or file is invalid
#
# EXAMPLE:
#   value=$(parse_yaml_with_python "config.yaml" "git.tag_prefix")
# -----------------------------------------------------------------------------
parse_yaml_with_python() {
    local yaml_file="$1"
    local yaml_path="$2"

    if [[ ! -f "$yaml_file" ]]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    # Remove leading dot if present (for consistency with yq syntax)
    yaml_path="${yaml_path#.}"

    # Python script to navigate the YAML structure
    # Pass file/path via env vars to avoid shell injection through heredoc
    local value
    value=$(_MANIFEST_PY_FILE="$yaml_file" _MANIFEST_PY_PATH="$yaml_path" python3 << 'PYEOF'
import yaml
import sys
import os

try:
    yaml_file = os.environ['_MANIFEST_PY_FILE']
    yaml_path = os.environ['_MANIFEST_PY_PATH']

    with open(yaml_file, 'r') as f:
        data = yaml.safe_load(f)

    path_parts = yaml_path.split('.')
    current = data

    for part in path_parts:
        if current is None:
            sys.exit(1)
        if isinstance(current, dict):
            current = current.get(part)
        else:
            sys.exit(1)

    if current is None:
        sys.exit(1)

    print(current)
except Exception as e:
    sys.exit(1)
PYEOF
    )

    if [[ $? -ne 0 ]] || [[ -z "$value" ]]; then
        return 1
    fi

    echo "$value"
    return 0
}

# -----------------------------------------------------------------------------
# Function: parse_yaml_basic
# -----------------------------------------------------------------------------
# Basic YAML parsing using grep/sed for simple key-value pairs.
# This is a fallback when no proper YAML parser is available.
#
# LIMITATIONS:
#   - Only handles simple top-level keys
#   - Does not support nested structures
#   - Does not support arrays
#   - May fail on complex YAML
#
# ARGUMENTS:
#   $1 - Path to YAML file
#   $2 - Key name (simple, e.g., "name" not "fleet.name")
#
# RETURNS:
#   Echoes the value for the key
#   Returns 1 if key not found
#
# EXAMPLE:
#   name=$(parse_yaml_basic "config.yaml" "name")
# -----------------------------------------------------------------------------
parse_yaml_basic() {
    local yaml_file="$1"
    local key="$2"

    if [[ ! -f "$yaml_file" ]]; then
        log_error "YAML file not found: $yaml_file"
        return 1
    fi

    # Extract the last component of dotted path
    local simple_key="${key##*.}"

    # Try to find the key and extract its value
    # This handles: key: value, key: "value", key: 'value'
    local value
    value=$(grep -E "^[[:space:]]*${simple_key}:" "$yaml_file" | head -1 | \
            sed -E 's/^[[:space:]]*[^:]+:[[:space:]]*//' | \
            sed -E 's/^["'\''](.*)[\"'\'']$/\1/' | \
            sed -E 's/[[:space:]]*#.*$//' | \
            sed -E 's/[[:space:]]+$//')

    if [[ -z "$value" ]]; then
        return 1
    fi

    echo "$value"
    return 0
}

# -----------------------------------------------------------------------------
# Function: get_yaml_value
# -----------------------------------------------------------------------------
# Unified YAML parsing function that automatically selects the best parser.
#
# This is the primary function to use for reading YAML values.
# It handles parser detection, caching, and error handling.
#
# ARGUMENTS:
#   $1 - Path to YAML file
#   $2 - YAML path (dot notation, e.g., ".fleet.name" or "fleet.name")
#   $3 - Default value if path not found (optional)
#
# RETURNS:
#   Echoes the value or default
#   Returns 0 on success, 1 if not found and no default provided
#
# EXAMPLE:
#   tag_prefix=$(get_yaml_value "config.yaml" ".git.tag_prefix" "v")
# -----------------------------------------------------------------------------
get_yaml_value() {
    local yaml_file="$1"
    local yaml_path="$2"
    local default_value="${3:-}"

    # Cache the parser detection result
    if [[ -z "${_MANIFEST_YAML_PARSER:-}" ]]; then
        _MANIFEST_YAML_PARSER=$(detect_yaml_parser)
        log_debug "YAML parser detected: $_MANIFEST_YAML_PARSER"
    fi

    local value=""
    local found=false

    case "$_MANIFEST_YAML_PARSER" in
        "yq")
            if value=$(parse_yaml_with_yq "$yaml_file" "$yaml_path" 2>/dev/null); then
                found=true
            fi
            ;;
        "python")
            # Remove leading dot for Python parser
            local python_path="${yaml_path#.}"
            if value=$(parse_yaml_with_python "$yaml_file" "$python_path" 2>/dev/null); then
                found=true
            fi
            ;;
        "none"|*)
            # Fallback to basic parsing
            local simple_key="${yaml_path##*.}"
            if value=$(parse_yaml_basic "$yaml_file" "$simple_key" 2>/dev/null); then
                found=true
            fi
            ;;
    esac

    if [[ "$found" == "true" ]] && [[ -n "$value" ]]; then
        echo "$value"
        return 0
    elif [[ -n "$default_value" ]]; then
        echo "$default_value"
        return 0
    else
        return 1
    fi
}

# =============================================================================
# YAML Writer Functions
# =============================================================================

# -----------------------------------------------------------------------------
# Function: set_yaml_value
# -----------------------------------------------------------------------------
# Updates a single key in a YAML file. Creates the file if it does not exist.
# Requires yq or python3 — the basic grep/sed fallback cannot write YAML.
#
# ARGUMENTS:
#   $1 - Path to YAML file
#   $2 - Dot-path (e.g., "git.tag_prefix")
#   $3 - Value to set
#
# RETURNS:
#   0 on success, 1 on failure
#
# EXAMPLE:
#   set_yaml_value "config.yaml" "git.tag_prefix" "v"
# -----------------------------------------------------------------------------
set_yaml_value() {
    local yaml_file="$1"
    local dotpath="$2"
    local value="$3"

    if [[ -z "$yaml_file" ]] || [[ -z "$dotpath" ]]; then
        log_error "set_yaml_value: file path and dot-path are required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$yaml_file")
    if [[ ! -d "$parent_dir" ]]; then
        log_error "set_yaml_value: parent directory does not exist: $parent_dir"
        return 1
    fi

    # Create the file if it does not exist
    if [[ ! -f "$yaml_file" ]]; then
        touch "$yaml_file" || {
            log_error "set_yaml_value: cannot create file: $yaml_file"
            return 1
        }
    fi

    # Cache parser detection
    if [[ -z "${_MANIFEST_YAML_PARSER:-}" ]]; then
        _MANIFEST_YAML_PARSER=$(detect_yaml_parser)
        log_debug "YAML parser detected: $_MANIFEST_YAML_PARSER"
    fi

    case "$_MANIFEST_YAML_PARSER" in
        "yq")
            # Use yq's env() operator to avoid shell injection through value
            _MANIFEST_YQ_VAL="$value" yq e ".${dotpath} = env(_MANIFEST_YQ_VAL)" -i "$yaml_file" 2>/dev/null
            if [[ $? -ne 0 ]]; then
                log_error "set_yaml_value: yq failed to set '${dotpath}' in $yaml_file"
                return 1
            fi
            ;;
        "python")
            # Pass file/path/value via env vars to avoid shell injection through heredoc
            _MANIFEST_PY_FILE="$yaml_file" _MANIFEST_PY_PATH="$dotpath" _MANIFEST_PY_VAL="$value" python3 << 'PYEOF'
import yaml
import sys
import os

try:
    yaml_file = os.environ['_MANIFEST_PY_FILE']
    dotpath = os.environ['_MANIFEST_PY_PATH']
    value = os.environ['_MANIFEST_PY_VAL']

    # Load existing data or start fresh
    try:
        with open(yaml_file, 'r') as f:
            data = yaml.safe_load(f) or {}
    except Exception:
        data = {}

    # Navigate/create the nested path
    path_parts = dotpath.split('.')
    current = data
    for part in path_parts[:-1]:
        if part not in current or not isinstance(current.get(part), dict):
            current[part] = {}
        current = current[part]

    # Set the value
    current[path_parts[-1]] = value

    # Write back
    with open(yaml_file, 'w') as f:
        yaml.dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
            if [[ $? -ne 0 ]]; then
                log_error "set_yaml_value: python3 failed to set '${dotpath}' in $yaml_file"
                return 1
            fi
            ;;
        "none"|*)
            log_error "set_yaml_value: writing YAML requires yq or python3 (neither available)"
            return 1
            ;;
    esac

    log_debug "set_yaml_value: set '${dotpath}' = '${value}' in $yaml_file"
    return 0
}

# -----------------------------------------------------------------------------
# Function: write_full_yaml
# -----------------------------------------------------------------------------
# Dumps ALL current MANIFEST_CLI_* env vars (that have a mapping and a value)
# into a complete YAML config file. Overwrites the target file.
#
# Uses python3 preferably (correct nested structure), falls back to yq,
# errors out if neither is available.
#
# ARGUMENTS:
#   $1 - Path to output YAML file
#
# RETURNS:
#   0 on success, 1 on failure
#
# EXAMPLE:
#   write_full_yaml "manifest.yaml"
# -----------------------------------------------------------------------------
write_full_yaml() {
    local yaml_file="$1"

    if [[ -z "$yaml_file" ]]; then
        log_error "write_full_yaml: output file path is required"
        return 1
    fi

    # Ensure parent directory exists
    local parent_dir
    parent_dir=$(dirname "$yaml_file")
    if [[ ! -d "$parent_dir" ]]; then
        log_error "write_full_yaml: parent directory does not exist: $parent_dir"
        return 1
    fi

    # Cache parser detection
    if [[ -z "${_MANIFEST_YAML_PARSER:-}" ]]; then
        _MANIFEST_YAML_PARSER=$(detect_yaml_parser)
        log_debug "YAML parser detected: $_MANIFEST_YAML_PARSER"
    fi

    # Collect all mappings that have a current env var value
    # Format: dotpath=value pairs, one per line
    local mappings=""
    local yaml_path env_var env_value
    for yaml_path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
        env_var="${_MANIFEST_YAML_TO_ENV[$yaml_path]}"
        env_value="${!env_var:-}"
        if [[ -n "$env_value" ]]; then
            mappings+="${yaml_path}=${env_value}"$'\n'
        fi
    done

    if [[ -z "$mappings" ]]; then
        log_warning "write_full_yaml: no MANIFEST_CLI_* env vars are set; writing empty config"
        echo "# Manifest CLI Configuration" > "$yaml_file"
        echo "# Generated by manifest-yaml.sh" >> "$yaml_file"
        return 0
    fi

    # Prefer python3 for correct nested YAML structure
    # Pass mappings and output file via env vars to avoid heredoc injection
    if command -v python3 &>/dev/null && python3 -c "import yaml" 2>/dev/null; then
        _MANIFEST_PY_FILE="$yaml_file" _MANIFEST_PY_MAPPINGS="$mappings" python3 << 'PYEOF'
import yaml
import sys
import os

SECTION_COMMENTS = {
    'version': 'Version scheme configuration',
    'git': 'Git workflow configuration',
    'time': 'HTTPS time verification and caching',
    'docs': 'Documentation generation',
    'files': 'File and directory paths',
    'install': 'Installation paths',
    'brew': 'Homebrew integration',
    'project': 'Project metadata',
    'auto_update': 'Automatic update settings',
    'config': 'Schema versioning',
    'debug': 'Debugging and verbosity',
    'pr': 'Pull request settings',
}

try:
    yaml_file = os.environ['_MANIFEST_PY_FILE']
    mappings_raw = os.environ['_MANIFEST_PY_MAPPINGS'].strip()

    data = {}
    for line in mappings_raw.split('\n'):
        if not line.strip():
            continue
        dotpath, value = line.split('=', 1)
        parts = dotpath.split('.')
        current = data
        for part in parts[:-1]:
            if part not in current:
                current[part] = {}
            current = current[part]
        current[parts[-1]] = value

    with open(yaml_file, 'w') as f:
        f.write('# Manifest CLI Configuration\n')
        f.write('# Generated by manifest-yaml.sh\n\n')

        for section_key in data:
            comment = SECTION_COMMENTS.get(section_key, section_key)
            f.write(f'# {comment}\n')
            section_data = {section_key: data[section_key]}
            yaml_str = yaml.dump(section_data, default_flow_style=False, sort_keys=False, allow_unicode=True)
            f.write(yaml_str)
            f.write('\n')

except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
        if [[ $? -ne 0 ]]; then
            log_error "write_full_yaml: python3 failed to write $yaml_file"
            return 1
        fi
    elif [[ "$_MANIFEST_YAML_PARSER" == "yq" ]]; then
        # Fallback: use yq by setting each value individually
        echo "# Manifest CLI Configuration" > "$yaml_file"
        echo "# Generated by manifest-yaml.sh" >> "$yaml_file"

        local line dotpath value
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            dotpath="${line%%=*}"
            value="${line#*=}"
            _MANIFEST_YQ_VAL="$value" yq e ".${dotpath} = env(_MANIFEST_YQ_VAL)" -i "$yaml_file" 2>/dev/null
            if [[ $? -ne 0 ]]; then
                log_warning "write_full_yaml: yq failed to set '${dotpath}'"
            fi
        done <<< "$mappings"
    else
        log_error "write_full_yaml: writing YAML requires python3 (with PyYAML) or yq (neither available)"
        return 1
    fi

    log_debug "write_full_yaml: wrote config to $yaml_file"
    return 0
}

# =============================================================================
# YAML-to-ENV Loader
# =============================================================================

# -----------------------------------------------------------------------------
# Function: load_yaml_to_env
# -----------------------------------------------------------------------------
# Reads a YAML config file and exports all mapped MANIFEST_CLI_* env vars.
# Only exports values that are non-empty, so layered precedence is preserved
# (a higher-priority config can override a lower one by setting a value;
# omitting a key leaves the existing env var untouched).
#
# ARGUMENTS:
#   $1 - Path to YAML config file
#
# RETURNS:
#   0 on success (even if some keys are missing — that is normal)
#   1 if the file does not exist or cannot be read
#
# EXAMPLE:
#   load_yaml_to_env "$HOME/.manifest-cli/config.yaml"
#   load_yaml_to_env ".manifest.yaml"
# -----------------------------------------------------------------------------
load_yaml_to_env() {
    local yaml_file="$1"

    if [[ -z "$yaml_file" ]]; then
        log_error "load_yaml_to_env: file path is required"
        return 1
    fi

    if [[ ! -f "$yaml_file" ]]; then
        log_error "load_yaml_to_env: file not found: $yaml_file"
        return 1
    fi

    if [[ ! -r "$yaml_file" ]]; then
        log_error "load_yaml_to_env: file not readable: $yaml_file"
        return 1
    fi

    log_debug "load_yaml_to_env: loading config from $yaml_file"

    local yaml_path env_var value
    local loaded_count=0

    for yaml_path in "${!_MANIFEST_YAML_TO_ENV[@]}"; do
        env_var="${_MANIFEST_YAML_TO_ENV[$yaml_path]}"

        # get_yaml_value handles parser detection and caching internally
        if value=$(get_yaml_value "$yaml_file" ".${yaml_path}" "" 2>/dev/null); then
            if [[ -n "$value" ]]; then
                export "$env_var"="$value"
                log_debug "load_yaml_to_env: ${env_var}=${value}"
                loaded_count=$((loaded_count + 1))
            fi
        fi
    done

    log_debug "load_yaml_to_env: loaded $loaded_count values from $yaml_file"
    return 0
}

# =============================================================================
# Export Public Functions
# =============================================================================

export -f detect_yaml_parser
export -f parse_yaml_with_yq
export -f parse_yaml_with_python
export -f parse_yaml_basic
export -f get_yaml_value
export -f set_yaml_value
export -f write_full_yaml
export -f load_yaml_to_env
export -f yaml_path_to_env_var
export -f env_var_to_yaml_path
