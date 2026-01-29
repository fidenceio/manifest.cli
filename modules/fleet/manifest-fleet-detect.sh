#!/bin/bash

# =============================================================================
# MANIFEST FLEET AUTO-DETECTION MODULE
# =============================================================================
#
# PURPOSE:
#   Automatically discovers and catalogs git repositories within a fleet
#   workspace. This enables zero-configuration fleet setup where Manifest
#   can detect new services without manual manifest.fleet.yaml updates.
#
# KEY FEATURES:
#   - Recursive git repository discovery
#   - Submodule detection and handling
#   - Repository classification (service, library, infrastructure)
#   - Smart filtering (ignore node_modules, vendor, etc.)
#   - Diff detection against existing manifest.fleet.yaml
#
# AUTO-DETECTION MODES:
#   1. DISCOVERY    : Find all git repos in workspace (for fleet init)
#   2. DIFF         : Compare discovered repos against manifest.fleet.yaml
#   3. SUGGEST      : Generate additions for manifest.fleet.yaml
#   4. SYNC         : Auto-update manifest.fleet.yaml with new repos
#
# USAGE:
#   source manifest-fleet-detect.sh
#   discovered=$(discover_fleet_repos "/path/to/workspace")
#   new_repos=$(diff_discovered_repos "$discovered")
#
# DEPENDENCIES:
#   - manifest-fleet-config.sh
#   - git command available
#
# =============================================================================

# =============================================================================
# MODULE INITIALIZATION
# =============================================================================

# Prevent multiple sourcing
if [[ -n "${_MANIFEST_FLEET_DETECT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_FLEET_DETECT_LOADED=1

# Module metadata
readonly MANIFEST_FLEET_DETECT_MODULE_VERSION="1.0.0"
readonly MANIFEST_FLEET_DETECT_MODULE_NAME="manifest-fleet-detect"

# =============================================================================
# DETECTION CONFIGURATION
# =============================================================================

# -----------------------------------------------------------------------------
# Ignore Patterns
# -----------------------------------------------------------------------------
# Directories to skip during repository discovery.
# These are common directories that should never be treated as services.

# Dependency directories (package managers)
readonly MANIFEST_FLEET_IGNORE_DEPS=(
    "node_modules"
    "vendor"
    "bower_components"
    ".bundle"
    "packages"          # Unless it contains independent services
    "Pods"              # iOS CocoaPods
    ".gradle"
    ".m2"
)

# Build and output directories
readonly MANIFEST_FLEET_IGNORE_BUILD=(
    "dist"
    "build"
    "out"
    "target"
    ".next"
    ".nuxt"
    ".output"
    "coverage"
    ".nyc_output"
)

# IDE and tool directories
readonly MANIFEST_FLEET_IGNORE_IDE=(
    ".idea"
    ".vscode"
    ".vs"
    ".atom"
)

# VCS directories (we look FOR .git, but ignore these)
readonly MANIFEST_FLEET_IGNORE_VCS=(
    ".git"
    ".svn"
    ".hg"
)

# Archive and backup directories
readonly MANIFEST_FLEET_IGNORE_ARCHIVE=(
    "zArchive"
    "archive"
    ".archive"
    "backup"
    ".backup"
    "old"
    ".old"
    "deprecated"
)

# Test fixtures and mocks
readonly MANIFEST_FLEET_IGNORE_FIXTURES=(
    "__fixtures__"
    "__mocks__"
    "fixtures"
    "testdata"
    "test-fixtures"
)

# Documentation and examples
readonly MANIFEST_FLEET_IGNORE_DOCS=(
    "examples"
    "docs"
    "documentation"
)

# Temporary directories
readonly MANIFEST_FLEET_IGNORE_TEMP=(
    "tmp"
    "temp"
    ".tmp"
    ".temp"
    ".cache"
)

# -----------------------------------------------------------------------------
# Detection Settings
# -----------------------------------------------------------------------------

# Maximum depth to search for repositories
readonly MANIFEST_FLEET_DEFAULT_DISCOVERY_DEPTH=5

# Minimum depth (don't treat fleet root as a service)
readonly MANIFEST_FLEET_MIN_DISCOVERY_DEPTH=1

# Whether to include submodules in discovery
readonly MANIFEST_FLEET_DEFAULT_INCLUDE_SUBMODULES="true"

# Whether to include nested git repos (repos inside repos)
readonly MANIFEST_FLEET_DEFAULT_INCLUDE_NESTED="false"

# =============================================================================
# HELPER FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _should_ignore_directory
# -----------------------------------------------------------------------------
# Checks if a directory should be skipped during discovery.
#
# ARGUMENTS:
#   $1 - Directory name (basename only)
#
# RETURNS:
#   0 if directory should be ignored
#   1 if directory should be processed
#
# EXAMPLE:
#   if _should_ignore_directory "node_modules"; then
#       echo "Skipping node_modules"
#   fi
# -----------------------------------------------------------------------------
_should_ignore_directory() {
    local dirname="$1"

    # Check against all ignore lists
    local all_ignore=(
        "${MANIFEST_FLEET_IGNORE_DEPS[@]}"
        "${MANIFEST_FLEET_IGNORE_BUILD[@]}"
        "${MANIFEST_FLEET_IGNORE_IDE[@]}"
        "${MANIFEST_FLEET_IGNORE_VCS[@]}"
        "${MANIFEST_FLEET_IGNORE_ARCHIVE[@]}"
        "${MANIFEST_FLEET_IGNORE_FIXTURES[@]}"
        "${MANIFEST_FLEET_IGNORE_DOCS[@]}"
        "${MANIFEST_FLEET_IGNORE_TEMP[@]}"
    )

    for pattern in "${all_ignore[@]}"; do
        if [[ "$dirname" == "$pattern" ]]; then
            return 0  # Should ignore
        fi
    done

    # Check for hidden directories (except specific ones we want)
    if [[ "$dirname" == .* ]] && [[ "$dirname" != ".git" ]]; then
        return 0  # Should ignore hidden directories
    fi

    return 1  # Should not ignore
}

# -----------------------------------------------------------------------------
# Function: _is_git_repository
# -----------------------------------------------------------------------------
# Checks if a directory is a git repository.
#
# ARGUMENTS:
#   $1 - Directory path
#
# RETURNS:
#   0 if directory is a git repository
#   1 if not
#
# NOTE:
#   This checks for both regular repos (.git directory) and bare repos
# -----------------------------------------------------------------------------
_is_git_repository() {
    local dir="$1"

    # Check for .git directory (normal repo)
    if [[ -d "$dir/.git" ]]; then
        return 0
    fi

    # Check for bare repository markers
    if [[ -f "$dir/HEAD" ]] && [[ -d "$dir/objects" ]] && [[ -d "$dir/refs" ]]; then
        return 0
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Function: _is_git_submodule
# -----------------------------------------------------------------------------
# Checks if a directory is a git submodule.
#
# ARGUMENTS:
#   $1 - Directory path
#   $2 - Parent repository path (optional, for context)
#
# RETURNS:
#   0 if directory is a submodule
#   1 if not
#
# DETECTION METHOD:
#   1. Check if .git is a file (submodules have .git as file pointing to parent)
#   2. Check parent's .gitmodules file
# -----------------------------------------------------------------------------
_is_git_submodule() {
    local dir="$1"
    local parent="${2:-}"

    # Submodules have .git as a file, not a directory
    if [[ -f "$dir/.git" ]]; then
        return 0
    fi

    # Check parent's .gitmodules if provided
    if [[ -n "$parent" ]] && [[ -f "$parent/.gitmodules" ]]; then
        local rel_path="${dir#$parent/}"
        if grep -q "path = $rel_path" "$parent/.gitmodules" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# -----------------------------------------------------------------------------
# Function: _get_repo_remote_url
# -----------------------------------------------------------------------------
# Gets the origin remote URL for a git repository.
#
# ARGUMENTS:
#   $1 - Repository directory path
#
# RETURNS:
#   Echoes the remote URL or empty string if not found
# -----------------------------------------------------------------------------
_get_repo_remote_url() {
    local repo_dir="$1"

    if [[ ! -d "$repo_dir" ]]; then
        return 1
    fi

    git -C "$repo_dir" remote get-url origin 2>/dev/null || echo ""
}

# -----------------------------------------------------------------------------
# Function: _get_repo_default_branch
# -----------------------------------------------------------------------------
# Determines the default branch for a repository.
#
# ARGUMENTS:
#   $1 - Repository directory path
#
# RETURNS:
#   Echoes the default branch name (main, master, develop, etc.)
#
# DETECTION PRIORITY:
#   1. Remote HEAD reference
#   2. Local branch named 'main'
#   3. Local branch named 'master'
#   4. Current branch
#   5. Fallback to 'main'
# -----------------------------------------------------------------------------
_get_repo_default_branch() {
    local repo_dir="$1"

    if [[ ! -d "$repo_dir" ]]; then
        echo "main"
        return
    fi

    # Try to get remote HEAD
    local remote_head
    remote_head=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    if [[ -n "$remote_head" ]]; then
        echo "$remote_head"
        return
    fi

    # Check for common branch names
    if git -C "$repo_dir" show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        echo "main"
        return
    fi

    if git -C "$repo_dir" show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        echo "master"
        return
    fi

    # Fallback to current branch or 'main'
    local current
    current=$(git -C "$repo_dir" branch --show-current 2>/dev/null)
    echo "${current:-main}"
}

# -----------------------------------------------------------------------------
# Function: _get_repo_version
# -----------------------------------------------------------------------------
# Gets the current version from a repository.
#
# ARGUMENTS:
#   $1 - Repository directory path
#
# RETURNS:
#   Echoes the version or "0.0.0" if not found
#
# CHECKS (in order):
#   1. VERSION file
#   2. package.json version field
#   3. Latest git tag matching v* pattern
#   4. Default "0.0.0"
# -----------------------------------------------------------------------------
_get_repo_version() {
    local repo_dir="$1"

    # Check VERSION file
    if [[ -f "$repo_dir/VERSION" ]]; then
        cat "$repo_dir/VERSION" 2>/dev/null
        return
    fi

    # Check package.json
    if [[ -f "$repo_dir/package.json" ]]; then
        local pkg_version
        pkg_version=$(grep -o '"version"[[:space:]]*:[[:space:]]*"[^"]*"' "$repo_dir/package.json" | \
                      head -1 | sed 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
        if [[ -n "$pkg_version" ]]; then
            echo "$pkg_version"
            return
        fi
    fi

    # Check git tags
    if _is_git_repository "$repo_dir"; then
        local latest_tag
        latest_tag=$(git -C "$repo_dir" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
        if [[ -n "$latest_tag" ]]; then
            echo "$latest_tag"
            return
        fi
    fi

    # Default
    echo "0.0.0"
}

# -----------------------------------------------------------------------------
# Function: _classify_repository
# -----------------------------------------------------------------------------
# Attempts to classify a repository by type (service, library, infrastructure).
#
# ARGUMENTS:
#   $1 - Repository directory path
#
# RETURNS:
#   Echoes one of: "service" | "library" | "infrastructure" | "tool" | "unknown"
#
# CLASSIFICATION HEURISTICS:
#   - Has Dockerfile/docker-compose.yaml → service
#   - Directory named "lib*" or contains only index.* → library
#   - Has terraform/*.tf files → infrastructure
#   - Has Makefile + cmd/ directory → tool
#   - Default → service
# -----------------------------------------------------------------------------
_classify_repository() {
    local repo_dir="$1"
    local dirname
    dirname=$(basename "$repo_dir")

    # Infrastructure indicators
    if [[ -d "$repo_dir/terraform" ]] || \
       [[ -f "$repo_dir/main.tf" ]] || \
       [[ -d "$repo_dir/ansible" ]] || \
       [[ -f "$repo_dir/Pulumi.yaml" ]] || \
       [[ -d "$repo_dir/cloudformation" ]]; then
        echo "infrastructure"
        return
    fi

    # Library indicators
    if [[ "$dirname" == lib* ]] || \
       [[ "$dirname" == *-lib ]] || \
       [[ "$dirname" == shared* ]] || \
       [[ "$dirname" == common* ]] || \
       [[ "$dirname" == *-sdk ]] || \
       [[ "$dirname" == *-client ]]; then
        echo "library"
        return
    fi

    # Tool indicators (CLI tools, scripts)
    if [[ -d "$repo_dir/cmd" ]] || \
       [[ "$dirname" == *-cli ]] || \
       [[ "$dirname" == *-tool ]] || \
       [[ "$dirname" == *-script* ]]; then
        echo "tool"
        return
    fi

    # Service indicators (most common for microservices)
    if [[ -f "$repo_dir/Dockerfile" ]] || \
       [[ -f "$repo_dir/docker-compose.yaml" ]] || \
       [[ -f "$repo_dir/docker-compose.yml" ]] || \
       [[ -d "$repo_dir/src" ]] || \
       [[ -d "$repo_dir/api" ]] || \
       [[ "$dirname" == *-service ]] || \
       [[ "$dirname" == *-api ]] || \
       [[ "$dirname" == *-server ]]; then
        echo "service"
        return
    fi

    # Default classification
    echo "service"
}

# -----------------------------------------------------------------------------
# Function: _extract_service_name
# -----------------------------------------------------------------------------
# Generates a service name from a repository path.
#
# ARGUMENTS:
#   $1 - Repository directory path
#   $2 - Fleet root path (for relative path calculation)
#
# RETURNS:
#   Echoes a cleaned service name suitable for manifest.fleet.yaml
#
# TRANSFORMATIONS:
#   - Uses directory basename
#   - Removes common prefixes/suffixes if nested
#   - Converts to lowercase
#   - Replaces invalid characters with hyphens
# -----------------------------------------------------------------------------
_extract_service_name() {
    local repo_dir="$1"
    local fleet_root="${2:-}"

    local name
    name=$(basename "$repo_dir")

    # Clean up the name
    # - Convert to lowercase
    # - Replace underscores and spaces with hyphens
    # - Remove any characters that aren't alphanumeric or hyphens
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | \
           tr '_' '-' | tr ' ' '-' | \
           sed 's/[^a-z0-9-]//g' | \
           sed 's/--*/-/g' | \
           sed 's/^-//' | sed 's/-$//')

    # Handle potential naming conflicts by including parent directory
    # if name is too generic
    if [[ "$name" == "src" ]] || [[ "$name" == "app" ]] || [[ "$name" == "api" ]]; then
        if [[ -n "$fleet_root" ]]; then
            local rel_path="${repo_dir#$fleet_root/}"
            local parent
            parent=$(dirname "$rel_path")
            if [[ "$parent" != "." ]]; then
                local parent_name
                parent_name=$(basename "$parent" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
                name="${parent_name}-${name}"
            fi
        fi
    fi

    echo "$name"
}

# =============================================================================
# DISCOVERY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: discover_fleet_repos
# -----------------------------------------------------------------------------
# Discovers all git repositories within a directory structure.
#
# This is the main entry point for repository discovery. It performs a
# recursive search of the filesystem, identifying git repositories and
# gathering metadata about each one.
#
# ARGUMENTS:
#   $1 - Root directory to search (defaults to current directory)
#   $2 - Maximum depth to search (defaults to MANIFEST_FLEET_DEFAULT_DISCOVERY_DEPTH)
#   $3 - Include submodules (defaults to MANIFEST_FLEET_DEFAULT_INCLUDE_SUBMODULES)
#
# OUTPUT FORMAT:
#   Outputs one line per discovered repository with tab-separated fields:
#   NAME<tab>PATH<tab>TYPE<tab>BRANCH<tab>VERSION<tab>URL<tab>IS_SUBMODULE
#
# RETURNS:
#   0 on success (even if no repos found)
#   1 on error (invalid root directory, etc.)
#
# EXAMPLE:
#   repos=$(discover_fleet_repos "/path/to/workspace")
#   while IFS=$'\t' read -r name path type branch version url is_sub; do
#       echo "Found: $name at $path (type: $type)"
#   done <<< "$repos"
# -----------------------------------------------------------------------------
discover_fleet_repos() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_FLEET_DEFAULT_DISCOVERY_DEPTH}"
    local include_submodules="${3:-$MANIFEST_FLEET_DEFAULT_INCLUDE_SUBMODULES}"

    # Validate root directory
    if [[ ! -d "$root_dir" ]]; then
        log_error "Discovery root directory does not exist: $root_dir"
        return 1
    fi

    # Resolve to absolute path
    root_dir=$(cd "$root_dir" && pwd)

    log_info "Discovering repositories in: $root_dir (max depth: $max_depth)"

    # Track discovered repos to avoid duplicates
    local discovered_paths=()

    # Recursive discovery function
    _discover_repos_recursive "$root_dir" "$root_dir" 0 "$max_depth" "$include_submodules" discovered_paths
}

# -----------------------------------------------------------------------------
# Function: _discover_repos_recursive (internal)
# -----------------------------------------------------------------------------
# Internal recursive function for repository discovery.
#
# ARGUMENTS:
#   $1 - Current directory to scan
#   $2 - Root directory (for relative path calculation)
#   $3 - Current depth
#   $4 - Maximum depth
#   $5 - Include submodules flag
#   $6 - Name of array to store discovered paths (for dedup)
# -----------------------------------------------------------------------------
_discover_repos_recursive() {
    local current_dir="$1"
    local root_dir="$2"
    local current_depth="$3"
    local max_depth="$4"
    local include_submodules="$5"
    local -n _discovered_ref="$6"  # nameref for dedup array

    # Check depth limit
    if [[ $current_depth -gt $max_depth ]]; then
        return 0
    fi

    # Skip if current directory should be ignored
    local dirname
    dirname=$(basename "$current_dir")
    if _should_ignore_directory "$dirname"; then
        log_debug "Skipping ignored directory: $current_dir"
        return 0
    fi

    # Check if current directory is a git repository
    local is_repo=false
    local is_submodule=false

    if _is_git_repository "$current_dir"; then
        is_repo=true

        # Check if it's a submodule
        if _is_git_submodule "$current_dir"; then
            is_submodule=true
            if [[ "$include_submodules" != "true" ]]; then
                log_debug "Skipping submodule (disabled): $current_dir"
                # Still recurse into submodule's contents if nested repos allowed
            fi
        fi
    fi

    # Output repository info if found (and not at root level)
    if [[ "$is_repo" == "true" ]] && [[ $current_depth -ge $MANIFEST_FLEET_MIN_DISCOVERY_DEPTH ]]; then
        # Skip if we've already discovered this path
        local rel_path="${current_dir#$root_dir/}"
        local already_found=false
        for found_path in "${_discovered_ref[@]}"; do
            if [[ "$found_path" == "$rel_path" ]]; then
                already_found=true
                break
            fi
        done

        if [[ "$already_found" == "false" ]]; then
            # Gather repository metadata
            local name
            name=$(_extract_service_name "$current_dir" "$root_dir")

            local type
            type=$(_classify_repository "$current_dir")

            local branch
            branch=$(_get_repo_default_branch "$current_dir")

            local version
            version=$(_get_repo_version "$current_dir")

            local url
            url=$(_get_repo_remote_url "$current_dir")

            local submodule_flag="false"
            if [[ "$is_submodule" == "true" ]]; then
                submodule_flag="true"
            fi

            # Output in tab-separated format
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$name" "$rel_path" "$type" "$branch" "$version" "$url" "$submodule_flag"

            # Track discovered path
            _discovered_ref+=("$rel_path")

            log_debug "Discovered: $name ($type) at $rel_path"
        fi
    fi

    # Recurse into subdirectories
    # Use a while loop with find to handle directories with spaces
    while IFS= read -r -d '' subdir; do
        # Only recurse if it's a directory (not a file or symlink to file)
        if [[ -d "$subdir" ]] && [[ ! -L "$subdir" ]]; then
            _discover_repos_recursive "$subdir" "$root_dir" $((current_depth + 1)) "$max_depth" "$include_submodules" _discovered_ref
        fi
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
}

# =============================================================================
# COMPARISON AND DIFF FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: diff_discovered_repos
# -----------------------------------------------------------------------------
# Compares discovered repositories against existing manifest.fleet.yaml.
#
# ARGUMENTS:
#   $1 - Discovery output (from discover_fleet_repos)
#   $2 - Path to manifest.fleet.yaml (optional, uses loaded config if not provided)
#
# OUTPUT FORMAT:
#   Outputs lines prefixed with status:
#   + NAME<tab>...  - New repository not in manifest
#   - NAME<tab>...  - In manifest but not found on disk
#   ~ NAME<tab>...  - In both but with differences
#   = NAME<tab>...  - In both and matching
#
# EXAMPLE:
#   discovered=$(discover_fleet_repos "/workspace")
#   diff_discovered_repos "$discovered"
# -----------------------------------------------------------------------------
diff_discovered_repos() {
    local discovered="$1"
    local manifest_file="${2:-$MANIFEST_FLEET_CONFIG_FILE}"

    # Get services from manifest
    local manifest_services=""
    if [[ -f "$manifest_file" ]]; then
        manifest_services=$(get_yaml_services "$manifest_file")
    fi

    # Build a lookup of manifest service paths
    declare -A manifest_paths
    for service in $manifest_services; do
        local path
        path=$(get_fleet_service_property "$service" "path")
        if [[ -n "$path" ]]; then
            # Make relative if absolute
            path="${path#$MANIFEST_FLEET_ROOT/}"
            manifest_paths["$path"]="$service"
        fi
    done

    # Process discovered repos
    local discovered_paths=()
    while IFS=$'\t' read -r name path type branch version url is_sub; do
        [[ -z "$name" ]] && continue

        discovered_paths+=("$path")

        if [[ -n "${manifest_paths[$path]:-}" ]]; then
            # Found in manifest - check for differences
            local manifest_name="${manifest_paths[$path]}"
            local manifest_type
            manifest_type=$(get_fleet_service_property "$manifest_name" "type" "service")

            if [[ "$name" != "$manifest_name" ]] || [[ "$type" != "$manifest_type" ]]; then
                echo "~	$name	$path	$type	$branch	$version	$url	$is_sub"
            else
                echo "=	$name	$path	$type	$branch	$version	$url	$is_sub"
            fi
        else
            # New repository not in manifest
            echo "+	$name	$path	$type	$branch	$version	$url	$is_sub"
        fi
    done <<< "$discovered"

    # Check for services in manifest but not discovered
    for path in "${!manifest_paths[@]}"; do
        local found=false
        for discovered_path in "${discovered_paths[@]}"; do
            if [[ "$path" == "$discovered_path" ]]; then
                found=true
                break
            fi
        done

        if [[ "$found" == "false" ]]; then
            local service="${manifest_paths[$path]}"
            echo "-	$service	$path	unknown	unknown	unknown		false"
        fi
    done
}

# -----------------------------------------------------------------------------
# Function: get_new_repos
# -----------------------------------------------------------------------------
# Filters diff output to only show new repositories.
#
# ARGUMENTS:
#   $1 - Diff output (from diff_discovered_repos)
#
# RETURNS:
#   Lines for new repositories only (without the + prefix)
# -----------------------------------------------------------------------------
get_new_repos() {
    local diff_output="$1"
    echo "$diff_output" | grep "^+"  | cut -f2-
}

# -----------------------------------------------------------------------------
# Function: get_missing_repos
# -----------------------------------------------------------------------------
# Filters diff output to show repositories in manifest but not on disk.
#
# ARGUMENTS:
#   $1 - Diff output (from diff_discovered_repos)
#
# RETURNS:
#   Lines for missing repositories (without the - prefix)
# -----------------------------------------------------------------------------
get_missing_repos() {
    local diff_output="$1"
    echo "$diff_output" | grep "^-" | cut -f2-
}

# =============================================================================
# YAML GENERATION FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: generate_service_yaml
# -----------------------------------------------------------------------------
# Generates YAML snippet for a discovered service.
#
# ARGUMENTS:
#   $1 - Service name
#   $2 - Service path (relative to fleet root)
#   $3 - Service type
#   $4 - Default branch
#   $5 - Current version
#   $6 - Remote URL (optional)
#   $7 - Is submodule flag
#
# OUTPUT:
#   YAML snippet suitable for inserting into manifest.fleet.yaml
# -----------------------------------------------------------------------------
generate_service_yaml() {
    local name="$1"
    local path="$2"
    local type="$3"
    local branch="$4"
    local version="$5"
    local url="$6"
    local is_submodule="$7"

    echo "  $name:"
    echo "    path: \"./$path\""

    if [[ -n "$url" ]]; then
        echo "    url: \"$url\""
    fi

    echo "    type: \"$type\""
    echo "    branch: \"$branch\""

    if [[ "$is_submodule" == "true" ]]; then
        echo "    submodule: true"
    fi

    # Add comment with discovered version
    echo "    # Discovered version: $version"
}

# -----------------------------------------------------------------------------
# Function: generate_manifest_additions
# -----------------------------------------------------------------------------
# Generates YAML additions for new repositories.
#
# ARGUMENTS:
#   $1 - New repos output (from get_new_repos)
#
# OUTPUT:
#   Complete YAML snippet to add to manifest.fleet.yaml services section
# -----------------------------------------------------------------------------
generate_manifest_additions() {
    local new_repos="$1"

    if [[ -z "$new_repos" ]]; then
        echo "# No new repositories to add"
        return 0
    fi

    echo ""
    echo "  # ==========================================="
    echo "  # AUTO-DISCOVERED SERVICES"
    echo "  # Generated by: manifest fleet discover"
    echo "  # Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "  # ==========================================="

    while IFS=$'\t' read -r name path type branch version url is_sub; do
        [[ -z "$name" ]] && continue
        echo ""
        generate_service_yaml "$name" "$path" "$type" "$branch" "$version" "$url" "$is_sub"
    done <<< "$new_repos"
}

# =============================================================================
# INTERACTIVE DISCOVERY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: interactive_discover
# -----------------------------------------------------------------------------
# Runs discovery with interactive prompts for handling results.
#
# ARGUMENTS:
#   $1 - Root directory to search
#
# BEHAVIOR:
#   1. Discovers all repositories
#   2. Shows diff against existing manifest
#   3. Prompts user to add new repos, remove missing, or skip
#   4. Optionally updates manifest.fleet.yaml
# -----------------------------------------------------------------------------
interactive_discover() {
    local root_dir="${1:-$(pwd)}"

    echo ""
    echo "============================================="
    echo "  MANIFEST FLEET AUTO-DISCOVERY"
    echo "============================================="
    echo ""
    echo "Scanning: $root_dir"
    echo ""

    # Run discovery
    local discovered
    discovered=$(discover_fleet_repos "$root_dir")

    local repo_count
    repo_count=$(echo "$discovered" | grep -c "^" || echo "0")

    echo "Found $repo_count potential service(s)"
    echo ""

    # If no manifest exists, this is initial setup
    if [[ ! -f "$MANIFEST_FLEET_CONFIG_FILE" ]]; then
        echo "No manifest.fleet.yaml found."
        echo "Run 'manifest fleet init' to create one with these services."
        echo ""
        echo "Discovered services:"
        echo "---"
        while IFS=$'\t' read -r name path type branch version url is_sub; do
            [[ -z "$name" ]] && continue
            printf "  %-25s %-12s %s\n" "$name" "($type)" "$path"
        done <<< "$discovered"
        return 0
    fi

    # Run diff
    local diff_output
    diff_output=$(diff_discovered_repos "$discovered")

    # Count changes
    local new_count removed_count changed_count unchanged_count
    new_count=$(echo "$diff_output" | grep -c "^+" || echo "0")
    removed_count=$(echo "$diff_output" | grep -c "^-" || echo "0")
    changed_count=$(echo "$diff_output" | grep -c "^~" || echo "0")
    unchanged_count=$(echo "$diff_output" | grep -c "^=" || echo "0")

    echo "Comparison with manifest.fleet.yaml:"
    echo "  + New:       $new_count"
    echo "  - Missing:   $removed_count"
    echo "  ~ Changed:   $changed_count"
    echo "  = Unchanged: $unchanged_count"
    echo ""

    # Show details
    if [[ $new_count -gt 0 ]]; then
        echo "NEW REPOSITORIES (not in manifest):"
        echo "---"
        echo "$diff_output" | grep "^+" | while IFS=$'\t' read -r status name path type branch version url is_sub; do
            printf "  + %-25s %-12s %s\n" "$name" "($type)" "$path"
        done
        echo ""
    fi

    if [[ $removed_count -gt 0 ]]; then
        echo "MISSING REPOSITORIES (in manifest but not found):"
        echo "---"
        echo "$diff_output" | grep "^-" | while IFS=$'\t' read -r status name path type rest; do
            printf "  - %-25s %s\n" "$name" "$path"
        done
        echo ""
    fi

    # Output YAML for new repos
    if [[ $new_count -gt 0 ]]; then
        echo ""
        echo "To add new services, append this to manifest.fleet.yaml:"
        echo "============================================="
        local new_repos
        new_repos=$(get_new_repos "$diff_output")
        generate_manifest_additions "$new_repos"
        echo ""
    fi
}

# =============================================================================
# QUICK DISCOVERY FUNCTION
# =============================================================================

# -----------------------------------------------------------------------------
# Function: quick_discover
# -----------------------------------------------------------------------------
# Performs a quick discovery and returns a summary.
# Useful for status checks and CI/CD pipelines.
#
# ARGUMENTS:
#   $1 - Root directory
#
# OUTPUT:
#   JSON-formatted summary (for easy parsing)
# -----------------------------------------------------------------------------
quick_discover() {
    local root_dir="${1:-$(pwd)}"

    local discovered
    discovered=$(discover_fleet_repos "$root_dir" 3)  # Limited depth for speed

    local total=0 services=0 libraries=0 infra=0 tools=0

    while IFS=$'\t' read -r name path type rest; do
        [[ -z "$name" ]] && continue
        ((total++))
        case "$type" in
            "service") ((services++)) ;;
            "library") ((libraries++)) ;;
            "infrastructure") ((infra++)) ;;
            "tool") ((tools++)) ;;
        esac
    done <<< "$discovered"

    cat << EOF
{
  "total": $total,
  "services": $services,
  "libraries": $libraries,
  "infrastructure": $infra,
  "tools": $tools,
  "root": "$root_dir"
}
EOF
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

export -f discover_fleet_repos
export -f diff_discovered_repos
export -f get_new_repos
export -f get_missing_repos
export -f generate_service_yaml
export -f generate_manifest_additions
export -f interactive_discover
export -f quick_discover
