#!/bin/bash

# =============================================================================
# MANIFEST FLEET AUTO-DETECTION MODULE
# =============================================================================
#
# PURPOSE:
#   Automatically discovers and catalogs git repositories within a fleet
#   workspace. This enables zero-configuration fleet setup where Manifest
#   can detect new services without manual manifest.fleet.config.yaml updates.
#
# KEY FEATURES:
#   - Recursive git repository discovery
#   - Submodule detection and handling
#   - Smart filtering (ignore node_modules, vendor, etc.)
#   - Diff detection against existing manifest.fleet.config.yaml
#
# AUTO-DETECTION MODES:
#   1. DISCOVERY    : Find all git repos in workspace (for fleet init/update)
#   2. DIFF         : Compare discovered repos against manifest.fleet.config.yaml
#   3. SUGGEST      : Generate additions for manifest.fleet.config.yaml
#
# REQUIREMENTS:
#   Bash 5.0+ (enforced by manifest-cli-wrapper.sh and install-cli.sh).
#   Uses namerefs (local -n) and associative arrays (declare -A).
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
if [[ -n "${_MANIFEST_CLI_FLEET_DETECT_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_FLEET_DETECT_LOADED=1

# Module metadata
readonly MANIFEST_CLI_FLEET_DETECT_MODULE_VERSION="1.0.0"
readonly MANIFEST_CLI_FLEET_DETECT_MODULE_NAME="manifest-fleet-detect"

MANIFEST_CLI_FLEET_DETECT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_CLI_FLEET_DETECT_MODULES_DIR="${MANIFEST_CLI_CORE_MODULES_DIR:-$(dirname "$MANIFEST_CLI_FLEET_DETECT_SCRIPT_DIR")}"
if ! declare -F manifest_discovery_walk_directories >/dev/null 2>&1 || \
   ! declare -F _manifest_discovery_walk_recursive >/dev/null 2>&1 || \
   [[ -z "${MANIFEST_CLI_DISCOVERY_MAX_DEPTH_CAP+x}" ]]; then
    # shellcheck disable=SC1091
    source "$MANIFEST_CLI_FLEET_DETECT_MODULES_DIR/core/manifest-discovery.sh"
fi

_manifest_fleet_tsv_read_line() {
    local line="$1"
    local _arr_name="$2"
    local -n _fields_ref="$_arr_name"
    local separator=$'\x1f'

    line="${line//$'\t'/$separator}"
    IFS="$separator" read -r -a _fields_ref <<< "$line"
}

# =============================================================================
# DETECTION CONFIGURATION
# =============================================================================

# -----------------------------------------------------------------------------
# Ignore Patterns
# -----------------------------------------------------------------------------
# Directories to skip during repository discovery.
# These are common directories that should never be treated as services.

# Dependency directories (package managers)
readonly MANIFEST_CLI_FLEET_IGNORE_DEPS=(
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
readonly MANIFEST_CLI_FLEET_IGNORE_BUILD=(
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
readonly MANIFEST_CLI_FLEET_IGNORE_IDE=(
    ".idea"
    ".vscode"
    ".vs"
    ".atom"
)

# VCS directories (we look FOR .git, but ignore these)
readonly MANIFEST_CLI_FLEET_IGNORE_VCS=(
    ".git"
    ".svn"
    ".hg"
)

# Archive and backup directories
readonly MANIFEST_CLI_FLEET_IGNORE_ARCHIVE=(
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
readonly MANIFEST_CLI_FLEET_IGNORE_FIXTURES=(
    "__fixtures__"
    "__mocks__"
    "fixtures"
    "testdata"
    "test-fixtures"
)

# Documentation and examples
readonly MANIFEST_CLI_FLEET_IGNORE_DOCS=(
    "examples"
    "docs"
    "documentation"
)

# Temporary directories
readonly MANIFEST_CLI_FLEET_IGNORE_TEMP=(
    "tmp"
    "temp"
    ".tmp"
    ".temp"
    ".cache"
)

# -----------------------------------------------------------------------------
# Detection Settings
# -----------------------------------------------------------------------------

# Fallback depth for the raw discover_* functions when a caller invokes them
# without first resolving --depth. Commands route through
# manifest_fleet_resolve_depth instead (§7.3), so this is only the
# direct-call default.
readonly MANIFEST_CLI_FLEET_DEFAULT_DISCOVERY_DEPTH=5

# Minimum depth (don't treat fleet root as a service)
readonly MANIFEST_CLI_FLEET_MIN_DISCOVERY_DEPTH=1

# Single source of truth for the DOWNWARD discovery-depth ceiling (§7.3): every
# --depth value (explicit or resolved from `auto`) is clamped to this. Distinct
# from MANIFEST_CLI_FLEET_DEFAULT_MAX_SEARCH_DEPTH in fleet-config.sh, which
# bounds the UPWARD walk for the fleet config file — a different axis.
readonly MANIFEST_CLI_FLEET_MAX_DISCOVERY_DEPTH=10

# Whether to include submodules in discovery
readonly MANIFEST_CLI_FLEET_DEFAULT_INCLUDE_SUBMODULES="true"

# -----------------------------------------------------------------------------
# Depth resolution (§7.3): one flag, one meaning, one cap.
# -----------------------------------------------------------------------------
# init / update / detect / plan and fleet.mode: auto all resolve
# --depth through here, so "scan depth" means the same thing everywhere: a
# guardrail on how deep DOWNWARD discovery walks, clamped to a single ceiling.
#
# `auto` is per-branch adaptive: a single pruned scan walks each branch to its
# own first git repo (pruning makes that cheap even at the ceiling), and auto
# resolves to the DEEPEST repo found — the tightest depth that still captures
# every branch in a mixed-depth workspace (repos at depth 1 AND deeper are all
# caught in one pass). A workspace of direct-child repos settles at depth 1; one
# with no repos has nothing to adapt to and falls back to the cap. Callers
# report the resolved depth so the choice is never silent.

# The ceiling — the one source of truth for "how deep is too deep" downward.
manifest_fleet_depth_cap() {
    echo "$MANIFEST_CLI_FLEET_MAX_DISCOVERY_DEPTH"
}

# Adaptive depth: the DEEPEST depth (>= MIN) at which a git repo appears,
# clamped to the cap — the tightest single scan depth that still captures every
# branch's repo in a mixed-depth workspace. Returns the cap when no repo is
# found by the ceiling. One pruned scan to the cap suffices: pruning stops each
# branch at its first repo, so this stays cheap even on a large workspace.
_manifest_fleet_adaptive_depth() {
    local root_dir="${1:-$(pwd)}"
    local cap min deepest=0 depth
    cap="$(manifest_fleet_depth_cap)"
    min="$MANIFEST_CLI_FLEET_MIN_DISCOVERY_DEPTH"
    while IFS=$'\t' read -r _ _ depth _; do
        [[ "$depth" =~ ^[0-9]+$ ]] || continue
        (( depth > deepest )) && deepest="$depth"
    done < <(manifest_discovery_find_git_repos "$root_dir" "$cap" "$MANIFEST_CLI_FLEET_DEFAULT_INCLUDE_SUBMODULES" "$min" fleet true 2>/dev/null)
    if (( deepest >= min )); then
        echo "$deepest"
    else
        echo "$cap"
    fi
}

# Resolve a --depth spec ("auto" | "" | non-negative integer) to a concrete
# integer, clamped to [MIN, cap]. The single entry point every discovery command
# uses for depth handling. Echoes the integer; returns 1 on an invalid spec.
manifest_fleet_resolve_depth() {
    local spec="${1:-auto}"
    local root_dir="${2:-$(pwd)}"
    local cap min
    cap="$(manifest_fleet_depth_cap)"
    min="$MANIFEST_CLI_FLEET_MIN_DISCOVERY_DEPTH"
    case "$spec" in
        auto|"")
            _manifest_fleet_adaptive_depth "$root_dir"
            ;;
        *[!0-9]*)
            log_error "Invalid --depth: '$spec' (expected a non-negative integer or 'auto')"
            return 1
            ;;
        *)
            (( spec < min )) && spec="$min"
            (( spec > cap )) && spec="$cap"
            echo "$spec"
            ;;
    esac
}

# Whether to include nested git repos (repos inside repos)
readonly MANIFEST_CLI_FLEET_DEFAULT_INCLUDE_NESTED="false"

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
    manifest_discovery_should_ignore_directory "$dirname" fleet
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
    manifest_discovery_is_git_repository "$dir"
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
    manifest_discovery_is_git_submodule "$dir" "$parent"
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
        pkg_version=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$repo_dir/package.json" | head -1)
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
# Function: _extract_service_name
# -----------------------------------------------------------------------------
# Generates a service name from a repository path.
#
# ARGUMENTS:
#   $1 - Repository directory path
#   $2 - Fleet root path (for relative path calculation)
#
# RETURNS:
#   Echoes a cleaned service name suitable for manifest.fleet.config.yaml
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
    # - Collapse multiple hyphens, strip leading/trailing hyphens
    name=$(echo "$name" | tr '[:upper:]' '[:lower:]' | tr '_ ' '--' | \
           sed 's/[^a-z0-9-]//g; s/--*/-/g; s/^-//; s/-$//')

    # Handle potential naming conflicts by including parent directory
    # if name is too generic
    if [[ "$name" == "src" ]] || [[ "$name" == "app" ]] || [[ "$name" == "api" ]]; then
        if [[ -n "$fleet_root" ]]; then
            local rel_path="${repo_dir#"$fleet_root"/}"
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
#   $2 - Maximum depth to search (defaults to MANIFEST_CLI_FLEET_DEFAULT_DISCOVERY_DEPTH)
#   $3 - Include submodules (defaults to MANIFEST_CLI_FLEET_DEFAULT_INCLUDE_SUBMODULES)
#
# OUTPUT FORMAT:
#   Outputs one line per discovered repository with tab-separated fields:
#   NAME<tab>PATH<tab>BRANCH<tab>VERSION<tab>URL<tab>IS_SUBMODULE
#
# RETURNS:
#   0 on success (even if no repos found)
#   1 on error (invalid root directory, etc.)
#
# EXAMPLE:
#   repos=$(discover_fleet_repos "/path/to/workspace")
#   while IFS=$'\t' read -r name path branch version url is_sub; do
#       echo "Found: $name at $path"
#   done <<< "$repos"
# -----------------------------------------------------------------------------
discover_fleet_repos() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_CLI_FLEET_DEFAULT_DISCOVERY_DEPTH}"
    local include_submodules="${3:-$MANIFEST_CLI_FLEET_DEFAULT_INCLUDE_SUBMODULES}"

    # Validate root directory
    if [[ ! -d "$root_dir" ]]; then
        log_error "Discovery root directory does not exist: $root_dir"
        return 1
    fi

    # Resolve to absolute path
    root_dir=$(cd "$root_dir" && pwd)

    log_info "Discovering repositories in: $root_dir (max depth: $max_depth)"

    local rel_path abs_path depth is_submodule
    while IFS=$'\t' read -r rel_path abs_path depth is_submodule; do
        [[ -n "$rel_path" ]] || continue

        local name
        name=$(_extract_service_name "$abs_path" "$root_dir")

        local branch
        branch=$(_get_repo_default_branch "$abs_path")

        local version
        version=$(_get_repo_version "$abs_path")

        local url
        url=$(_get_repo_remote_url "$abs_path")

        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$name" "$rel_path" "$branch" "$version" "$url" "$is_submodule"

        log_debug "Discovered: $name at $rel_path"
    done < <(manifest_discovery_find_git_repos "$root_dir" "$max_depth" "$include_submodules" "$MANIFEST_CLI_FLEET_MIN_DISCOVERY_DEPTH" fleet)
    return 0
}

# =============================================================================
# ALL-DIRECTORY DISCOVERY (git + non-git)
# =============================================================================

# -----------------------------------------------------------------------------
# Function: discover_all_directories
# -----------------------------------------------------------------------------
# Scans ALL subdirectories (not just git repos) for fleet start.
# Produces the same tab-separated format as discover_fleet_repos with two
# extra trailing fields: HAS_GIT and HAS_REMOTE.
#
# ARGUMENTS:
#   $1 - Root directory to scan (default: pwd)
#   $2 - Maximum depth (default: MANIFEST_CLI_FLEET_DEFAULT_DISCOVERY_DEPTH)
#
# OUTPUT FORMAT (per line, tab-separated):
#   NAME  PATH  BRANCH  VERSION  URL  IS_SUBMODULE  HAS_GIT  HAS_REMOTE
# -----------------------------------------------------------------------------
discover_all_directories() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_CLI_FLEET_DEFAULT_DISCOVERY_DEPTH}"

    if [[ ! -d "$root_dir" ]]; then
        log_error "Discovery root directory does not exist: $root_dir"
        return 1
    fi

    root_dir=$(cd "$root_dir" && pwd)

    log_info "Scanning all directories in: $root_dir (max depth: $max_depth)"

    local depth rel_path abs_path dirname has_git is_submodule
    while IFS=$'\t' read -r depth rel_path abs_path dirname has_git is_submodule; do
        [[ -n "$rel_path" ]] || continue

        local name
        name=$(_extract_service_name "$abs_path" "$root_dir")

        local has_remote="false"
        local branch="" version="0.0.0" url=""

        if [[ "$has_git" == "true" ]]; then
            branch=$(_get_repo_default_branch "$abs_path")
            version=$(_get_repo_version "$abs_path")
            url=$(_get_repo_remote_url "$abs_path")
            [[ -n "$url" ]] && has_remote="true"
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$name" "$rel_path" "$branch" "$version" "$url" "$is_submodule" "$has_git" "$has_remote"

        log_debug "Found directory: $name (has_git=$has_git) at $rel_path"
    done < <(manifest_discovery_walk_directories "$root_dir" "$max_depth" "$MANIFEST_CLI_FLEET_MIN_DISCOVERY_DEPTH" fleet)
    return 0
}

# -----------------------------------------------------------------------------
# Function: generate_start_tsv
# -----------------------------------------------------------------------------
# Generates TSV selection file content from discover_all_directories output.
#
# ARGUMENTS:
#   $1 - Output of discover_all_directories (multi-line, tab-separated)
#   $2 - Root directory path (for header metadata)
#   $3 - Scan depth used (for header metadata)
#   $4 - Selection mode: git-only (default) or listed
#   $5 - Fingerprint mode: fingerprint (default) or trusted
#
# OUTPUT:
#   TSV content written to stdout, ready to redirect to a file.
# -----------------------------------------------------------------------------
_fleet_start_selected_for_row() {
    local has_git="$1"
    local select_mode="${2:-git-only}"

    case "$select_mode" in
        listed) echo "true" ;;
        git-only|*) [[ "$has_git" == "true" ]] && echo "true" || echo "false" ;;
    esac
}

_fleet_normalize_relative_path() {
    local path="$1"
    path="${path#./}"
    path="${path%/}"
    echo "$path"
}

_fleet_repo_depth_for_path() {
    local path
    path=$(_fleet_normalize_relative_path "$1")
    [[ -n "$path" ]] || {
        echo "0"
        return
    }
    if [[ "$path" != */* ]]; then
        echo "0"
        return
    fi

    local rest="${path#*/}"
    local depth=1
    while [[ "$rest" == */* ]]; do
        rest="${rest#*/}"
        ((depth += 1))
    done
    echo "$depth"
}

_fleet_top_level_for_path() {
    local path
    path=$(_fleet_normalize_relative_path "$1")
    echo "${path%%/*}"
}

_fleet_default_repo_depth_rules() {
    local discovered="$1"
    declare -A max_depth_by_top=()
    local tops=()

    while IFS=$'\t' read -r name path _branch _version _url _submodule _has_git _has_remote; do
        [[ -z "$name" ]] && continue
        local top depth
        top=$(_fleet_top_level_for_path "$path")
        [[ -n "$top" ]] || continue
        depth=$(_fleet_repo_depth_for_path "$path")
        if [[ -z "${max_depth_by_top[$top]+_}" ]]; then
            tops+=("$top")
            max_depth_by_top["$top"]="$depth"
        elif (( depth > ${max_depth_by_top[$top]} )); then
            max_depth_by_top["$top"]="$depth"
        fi
    done <<< "$discovered"

    local top
    for top in "${tops[@]}"; do
        if (( ${max_depth_by_top[$top]} > 0 )); then
            echo "$top=1"
        else
            echo "$top=0"
        fi
    done
    return 0
}

_fleet_prompt_repo_depth_rules() {
    local discovered="$1"
    local defaults
    defaults=$(_fleet_default_repo_depth_rules "$discovered")

    [[ -n "$defaults" ]] || return 0

    echo "" > /dev/tty
    echo "Choose repo granularity for each top-level folder:" > /dev/tty
    echo "  0 = the folder itself" > /dev/tty
    echo "  1 = direct children (folder/*)" > /dev/tty
    echo "  2 = grandchildren (folder/*/*)" > /dev/tty
    echo "  all = every nested folder, skip = none" > /dev/tty
    echo "" > /dev/tty

    local line top default_depth answer
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        top="${line%%=*}"
        default_depth="${line#*=}"

        while true; do
            printf "How deep should repos be under %s/? [%s] " "$top" "$default_depth" > /dev/tty
            read -r answer < /dev/tty
            answer="${answer:-$default_depth}"
            case "$answer" in
                skip|none) echo "$top=skip"; break ;;
                all) echo "$top=all"; break ;;
                ''|*[!0-9]*)
                    echo "Enter 0, 1, 2, all, or skip." > /dev/tty
                    ;;
                *) echo "$top=$answer"; break ;;
            esac
        done
    done <<< "$defaults"
    return 0
}

filter_start_inventory_by_repo_depth() {
    local discovered="$1"
    local rules="$2"
    local all_folders="${3:-false}"

    if [[ "$all_folders" == "true" ]]; then
        printf "%s\n" "$discovered"
        return 0
    fi

    declare -A rule_by_top=()
    local rule top value
    while IFS= read -r rule; do
        [[ -z "$rule" ]] && continue
        top="${rule%%=*}"
        value="${rule#*=}"
        rule_by_top["$top"]="$value"
    done <<< "$rules"

    local line
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        local path="${fields[1]:-}"
        local branch="${fields[2]:-}"
        local version="${fields[3]:-}"
        local url="${fields[4]:-}"
        local submodule="${fields[5]:-}"
        local has_git="${fields[6]:-}"
        local has_remote="${fields[7]:-}"
        [[ -z "$name" ]] && continue

        if [[ "$has_git" == "true" ]]; then
            printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$name" "$path" "$branch" "$version" "$url" "$submodule" "$has_git" "$has_remote"
            continue
        fi

        top=$(_fleet_top_level_for_path "$path")
        value="${rule_by_top[$top]:-1}"
        [[ "$value" == "skip" || "$value" == "none" ]] && continue

        local depth
        depth=$(_fleet_repo_depth_for_path "$path")
        if [[ "$value" == "all" ]]; then
            (( depth >= 1 )) || continue
        elif [[ "$value" =~ ^[0-9]+$ ]]; then
            (( depth == value )) || continue
        else
            continue
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$name" "$path" "$branch" "$version" "$url" "$submodule" "$has_git" "$has_remote"
    done <<< "$discovered"
    return 0
}

filter_start_inventory_git_repos() {
    local discovered="$1"

    local line
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        local path="${fields[1]:-}"
        local branch="${fields[2]:-}"
        local version="${fields[3]:-}"
        local url="${fields[4]:-}"
        local submodule="${fields[5]:-}"
        local has_git="${fields[6]:-}"
        local has_remote="${fields[7]:-}"
        [[ -z "$name" ]] && continue
        [[ "$has_git" == "true" ]] || continue
        printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$name" "$path" "$branch" "$version" "$url" "$submodule" "$has_git" "$has_remote"
    done <<< "$discovered"
    return 0
}

generate_start_tsv() {
    local discovered="$1"
    local root_dir="$2"
    local depth="$3"
    local select_mode="${4:-git-only}"
    local fingerprint_mode="${5:-fingerprint}"
    local scan_date
    scan_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # First pass: build the SELECT column for the default pattern so we can
    # fingerprint it. The fingerprint lets `manifest init fleet` detect
    # whether the user has actually edited selections in Phase 2.
    local selects=""
    local observed_depth=0
    local line
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        local path="${fields[1]:-}"
        local has_git="${fields[6]:-}"
        [[ -z "$name" ]] && continue
        local selected
        selected=$(_fleet_start_selected_for_row "$has_git" "$select_mode")
        selects="${selects}${selected}\n"
        if [[ "$has_git" == "true" ]]; then
            local row_depth=$(( $(_fleet_repo_depth_for_path "$path") + 1 ))
            (( row_depth > observed_depth )) && observed_depth="$row_depth"
        fi
    done <<< "$discovered"

    local default_hash
    default_hash=$(printf "%b" "$selects" | _manifest_hash_short)

    # Header. `# Depth:` is the observed deepest repo depth (derived from the
    # rows), not the requested scan depth — a diagnostic of the fleet's actual
    # reach. Falls back to the requested depth when no git repo was found.
    local recorded_depth="$observed_depth"
    (( recorded_depth > 0 )) || recorded_depth="$depth"
    echo "# MANIFEST FLEET — Directory Inventory"
    echo "# Root: $root_dir"
    echo "# Depth: $recorded_depth"
    echo "# Last scanned: $scan_date"
    echo "# Canonical config: manifest.fleet.config.yaml"
    echo "# Toggle the SELECT column (true/false) — update/ship/status honor it directly. (manifest init fleet is the first-time scaffold step only.)"
    if [[ "$fingerprint_mode" != "trusted" ]]; then
        echo "# DEFAULT-SELECT-HASH: ${default_hash}"
    fi
    printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"

    # Data rows
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        local path="${fields[1]:-}"
        local branch="${fields[2]:-}"
        local url="${fields[4]:-}"
        local has_git="${fields[6]:-}"
        [[ -z "$name" ]] && continue

        # Default selection: true for git repos, false for non-git dirs
        local selected
        selected=$(_fleet_start_selected_for_row "$has_git" "$select_mode")

        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$selected" "$name" "$path" "$has_git" "$url" "${branch:-}"
    done <<< "$discovered"
    return 0
}


# -----------------------------------------------------------------------------
# Function: parse_start_tsv
# -----------------------------------------------------------------------------
# Reads a manifest.fleet.tsv file and returns selected entries.
#
# ARGUMENTS:
#   $1 - Path to manifest.fleet.tsv
#
# OUTPUT FORMAT (per line, tab-separated):
#   NAME  PATH  HAS_GIT  REMOTE_URL  BRANCH
# -----------------------------------------------------------------------------
parse_start_tsv() {
    local tsv_file="$1"

    if [[ ! -f "$tsv_file" ]]; then
        log_error "Start file not found: $tsv_file"
        return 1
    fi

    local line
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local selected="${fields[0]:-}"
        local name="${fields[1]:-}"
        local path="${fields[2]:-}"
        local has_git="${fields[3]:-}"
        local url="${fields[4]:-}"
        local branch="${fields[5]:-}"
        # Skip comments and blank lines
        [[ "$selected" =~ ^#.*$ ]] && continue
        [[ -z "$selected" ]] && continue

        # Only return selected entries. Read loops intentionally accept the old
        # trailing VERSION column for backward compatibility, but the TSV no
        # longer treats per-repo versions as inventory truth.
        if [[ "$selected" == "true" ]]; then
            printf "%s\t%s\t%s\t%s\t%s\n" "$name" "$path" "$has_git" "$url" "${branch:-}"
        fi
    done < "$tsv_file"
}

# -----------------------------------------------------------------------------
# Function: _fleet_tsv_header_depth
# -----------------------------------------------------------------------------
# Reads the recorded scan depth from a TSV's "# Depth: N" header line.
# Echoes the integer when present and well-formed; echoes nothing otherwise so
# the caller can fall back to `auto`. A Phase-2 refresh uses this to rescan at
# the depth that PRODUCED the TSV rather than re-resolving `auto` — re-resolving
# would shrink a TSV written at an explicit deeper --depth down to the shallowest
# adaptive level, silently dropping its deeper rows (§7.3).
# -----------------------------------------------------------------------------
_fleet_tsv_header_depth() {
    local tsv="$1"
    [[ -f "$tsv" ]] || return 0
    local line depth
    while IFS= read -r line; do
        case "$line" in
            "# Depth: "*)
                depth="${line#\# Depth: }"
                depth="${depth//[[:space:]]/}"
                [[ "$depth" =~ ^[0-9]+$ ]] && echo "$depth"
                return 0 ;;
            "#"*) ;;          # other header/comment line — keep scanning
            *) return 0 ;;    # reached data rows; no depth header found
        esac
    done < "$tsv"
}

# -----------------------------------------------------------------------------
# Function: merge_update_tsv
# -----------------------------------------------------------------------------
# Reconciles a fresh scan into manifest.fleet.tsv. Two modes:
#
#   regenerate (default) — rebuild the TSV from the scan: write a fresh header,
#     emit one row per discovered path (in scan order), preserve the user's
#     SELECT toggle for paths already listed, default new paths by git status,
#     and re-derive every other column from the scan. Paths absent from the
#     scan are dropped. Used by `init fleet` after it git-inits selected dirs,
#     so the just-created repos pick up fresh git metadata.
#
#   append — edit the existing TSV in place: preserve every line verbatim (all
#     headers and data rows, in original order, byte-for-byte) and only APPEND
#     discovered paths not already listed; the sole in-place edit is the
#     "# Last scanned:" timestamp. Used by `update`/`refresh fleet` so an update
#     never drops a curated row the (shallower or transiently-missing) scan
#     fails to re-find, and never clobbers a manual edit to an existing row
#     (e.g. a deliberately preserved REMOTE_URL). With no existing TSV there is
#     nothing to edit in place, so append falls through to regenerate.
#
# ARGUMENTS:
#   $1 - Output of discover_all_directories (multi-line, tab-separated)
#   $2 - Path to manifest.fleet.tsv
#   $3 - Root directory path (for the regenerate header)
#   $4 - Scan depth (for the regenerate header)
#   $5 - Mode: "regenerate" (default) | "append"
#
# OUTPUT:
#   Updated TSV content written to stdout.
#   Returns count of new/appended entries via stderr as "NEW:<count>"
# -----------------------------------------------------------------------------
merge_update_tsv() {
    local discovered="$1"
    local existing_tsv="$2"
    local root_dir="$3"
    local depth="$4"
    local mode="${5:-regenerate}"
    local scan_date
    scan_date=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # --- append mode: edit the existing TSV in place (preserve + append) ------
    if [[ "$mode" == "append" && -f "$existing_tsv" ]]; then
        # Index paths already present so the append phase skips them.
        declare -A existing_paths
        local line
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in '#'*|'') continue ;; esac
            local fields=()
            _manifest_fleet_tsv_read_line "$line" fields
            local key
            key=$(_fleet_normalize_relative_path "${fields[2]:-}")
            [[ -n "$key" ]] && existing_paths["$key"]="1"
        done < "$existing_tsv"

        # Emit the existing file verbatim, refreshing only the scan timestamp.
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                "# Last scanned: "*) echo "# Last scanned: $scan_date" ;;
                *) printf '%s\n' "$line" ;;
            esac
        done < "$existing_tsv"

        # Append discovered paths not already listed.
        local new_count=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" ]] && continue
            local fields=()
            _manifest_fleet_tsv_read_line "$line" fields
            local name="${fields[0]:-}"
            local path="${fields[1]:-}"
            local branch="${fields[2]:-}"
            local url="${fields[4]:-}"
            local has_git="${fields[6]:-}"
            [[ -z "$name" ]] && continue
            local key
            key=$(_fleet_normalize_relative_path "$path")
            [[ -n "${existing_paths[$key]+_}" ]] && continue
            existing_paths["$key"]="1"
            local selected
            [[ "$has_git" == "true" ]] && selected="true" || selected="false"
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$selected" "$name" "$path" "$has_git" "$url" "${branch:-}"
            ((new_count += 1))
        done <<< "$discovered"

        echo "NEW:$new_count" >&2
        return 0
    fi

    # --- regenerate mode (default): rebuild the TSV from the scan -------------
    # Build lookup of existing selections keyed by path
    declare -A existing_selections
    declare -A existing_names existing_has_git existing_urls existing_branches
    if [[ -f "$existing_tsv" ]]; then
        local line
        while IFS= read -r line; do
            local fields=()
            _manifest_fleet_tsv_read_line "$line" fields
            local selected="${fields[0]:-}"
            local name="${fields[1]:-}"
            local path="${fields[2]:-}"
            local has_git="${fields[3]:-}"
            local url="${fields[4]:-}"
            local branch="${fields[5]:-}"
            [[ "$selected" =~ ^#.*$ ]] && continue
            [[ -z "$selected" ]] && continue
            local key
            key=$(_fleet_normalize_relative_path "$path")
            existing_selections["$key"]="$selected"
            existing_names["$key"]="$name"
            existing_has_git["$key"]="$has_git"
            existing_urls["$key"]="$url"
            existing_branches["$key"]="$branch"
        done < "$existing_tsv"
    fi

    # Write header
    echo "# MANIFEST FLEET — Directory Inventory"
    echo "# Root: $root_dir"
    echo "# Depth: $depth"
    echo "# Last scanned: $scan_date"
    echo "# Canonical config: manifest.fleet.config.yaml"
    echo "# Toggle the SELECT column (true/false) — update/ship/status honor it directly. (manifest init fleet is the first-time scaffold step only.)"
    printf "# SELECT\tNAME\tPATH\tHAS_GIT\tREMOTE_URL\tBRANCH\n"

    # Write data rows, preserving existing selections
    local new_count=0
    declare -A emitted_paths
    if [[ -n "${existing_selections[.]+_}" ]]; then
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "${existing_selections[.]}" \
            "${existing_names[.]}" \
            "." \
            "${existing_has_git[.]:-true}" \
            "${existing_urls[.]}" \
            "${existing_branches[.]:-${MANIFEST_CLI_GIT_DEFAULT_BRANCH:-main}}"
        emitted_paths["."]="true"
    fi

    local line
    while IFS= read -r line; do
        local fields=()
        _manifest_fleet_tsv_read_line "$line" fields
        local name="${fields[0]:-}"
        local path="${fields[1]:-}"
        local branch="${fields[2]:-}"
        local url="${fields[4]:-}"
        local has_git="${fields[6]:-}"
        [[ -z "$name" ]] && continue
        local key
        key=$(_fleet_normalize_relative_path "$path")
        [[ -n "${emitted_paths[$key]+_}" ]] && continue

        local selected
        if [[ -n "${existing_selections[$key]+_}" ]]; then
            # Preserve user's previous selection
            selected="${existing_selections[$key]}"
        else
            # New entry: default based on git status
            [[ "$has_git" == "true" ]] && selected="true" || selected="false"
            ((new_count += 1))
        fi

        printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
            "$selected" "$name" "$path" "$has_git" "$url" "${branch:-}"
        emitted_paths["$key"]="true"
    done <<< "$discovered"

    echo "NEW:$new_count" >&2
}

# =============================================================================
# COMPARISON AND DIFF FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: diff_discovered_repos
# -----------------------------------------------------------------------------
# Compares discovered repositories against existing manifest.fleet.config.yaml.
#
# ARGUMENTS:
#   $1 - Discovery output (from discover_fleet_repos)
#   $2 - Path to manifest.fleet.config.yaml (optional, uses loaded config if not provided)
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
    local manifest_file="${2:-$MANIFEST_CLI_FLEET_CONFIG_FILE}"

    # Get services from manifest
    local manifest_services=""
    if [[ -f "$manifest_file" ]]; then
        manifest_services=$(get_yaml_services "$manifest_file")
    fi

    # Build a lookup of manifest service paths
    # NOTE: We read directly from the YAML file (via get_yaml_value) rather than
    # using get_fleet_service_property, because the latter requires load_fleet_config
    # to have been called first — which isn't guaranteed in all code paths (e.g.
    # update fleet --dry-run, update fleet --quiet).
    declare -A manifest_paths
    for service in $manifest_services; do
        local path
        path=$(get_yaml_value "$manifest_file" ".services.$service.path" "")
        if [[ -n "$path" ]]; then
            # Make relative if absolute
            path="${path#"$MANIFEST_CLI_FLEET_ROOT"/}"
            # Strip leading ./ so paths match discovery output format
            path="${path#./}"
            manifest_paths["$path"]="$service"
        fi
    done

    # Process discovered repos
    local discovered_paths=()
    local root_dir="${MANIFEST_CLI_FLEET_ROOT:-$(dirname "$manifest_file")}"
    if [[ -n "${manifest_paths[.]:-}" ]] && _is_git_repository "$root_dir"; then
        local root_service="${manifest_paths[.]}"
        local root_branch root_version root_url
        root_branch=$(_get_repo_default_branch "$root_dir")
        root_version=$(_get_repo_version "$root_dir")
        root_url=$(_get_repo_remote_url "$root_dir")
        discovered_paths+=(".")
        echo "=	$root_service	.	$root_branch	$root_version	$root_url	false"
    fi
    while IFS=$'\t' read -r name path branch version url is_sub; do
        [[ -z "$name" ]] && continue

        discovered_paths+=("$path")

        if [[ -n "${manifest_paths[$path]:-}" ]]; then
            # Found in manifest - check for differences
            local manifest_name="${manifest_paths[$path]}"

            if [[ "$name" != "$manifest_name" ]]; then
                echo "~	$name	$path	$branch	$version	$url	$is_sub"
            else
                echo "=	$name	$path	$branch	$version	$url	$is_sub"
            fi
        else
            # New repository not in manifest
            echo "+	$name	$path	$branch	$version	$url	$is_sub"
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
            echo "-	$service	$path	unknown	unknown		false"
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
#   $3 - Default branch
#   $4 - Current version
#   $5 - Remote URL (optional)
#   $6 - Is submodule flag
#
# OUTPUT:
#   YAML snippet suitable for inserting into manifest.fleet.config.yaml
# -----------------------------------------------------------------------------
generate_service_yaml() {
    local name="$1"
    local path="$2"
    local branch="$3"
    local version="$4"
    local url="$5"
    local is_submodule="$6"

    echo "  $name:"
    echo "    path: \"./$path\""

    if [[ -n "$url" ]]; then
        echo "    url: \"$url\""
    fi

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
#   Complete YAML snippet to add to manifest.fleet.config.yaml services section
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
    echo "  # Generated by: manifest discover fleet"
    echo "  # Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    echo "  # ==========================================="

    while IFS=$'\t' read -r name path branch version url is_sub; do
        [[ -z "$name" ]] && continue
        echo ""
        generate_service_yaml "$name" "$path" "$branch" "$version" "$url" "$is_sub"
    done <<< "$new_repos"
}

# =============================================================================
# MANIFEST YAML WRITE FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: append_services_to_manifest
# -----------------------------------------------------------------------------
# Appends new service entries to manifest.fleet.config.yaml.
#
# Finds the last line of the services: section (before the next top-level key
# or end of file) and inserts the generated YAML there.
#
# ARGUMENTS:
#   $1 - Config file path (manifest.fleet.config.yaml)
#   $2 - YAML content to append (from generate_manifest_additions)
#
# RETURNS:
#   0 on success, 1 on failure
# -----------------------------------------------------------------------------
append_services_to_manifest() {
    local config_file="$1"
    local yaml_content="$2"

    if [[ ! -f "$config_file" ]]; then
        log_error "Config file not found: $config_file"
        return 1
    fi

    if [[ -z "$yaml_content" ]]; then
        log_info "No content to append"
        return 0
    fi

    # Find the line number of the next top-level key after "services:"
    # Top-level keys start at column 0 with a word followed by ":"
    local services_line
    services_line=$(grep -nm 1 "^services:" "$config_file" | cut -d: -f1)

    if [[ -z "$services_line" ]] || ! [[ "$services_line" =~ ^[0-9]+$ ]]; then
        # TSV-based fleet: the roster lives in manifest.fleet.tsv, not a config
        # services: map. There is nothing to append here — the caller reconciles
        # the roster into the TSV. Skip gracefully rather than failing the update.
        log_info "No services: map in $config_file (TSV-based fleet); skipping config append"
        return 0
    fi

    # Find the next top-level key after services:
    local insert_line
    insert_line=$(tail -n "+$((services_line + 1))" "$config_file" | grep -nm 1 "^[a-zA-Z_]" | cut -d: -f1)

    if [[ -n "$insert_line" ]]; then
        # Insert before the next top-level key
        # insert_line is relative to services_line+1, so absolute line is:
        local abs_line=$((services_line + insert_line))

        # Use a temp file in the same directory for safe writing (avoids /tmp race conditions)
        local tmp_file
        tmp_file=$(mktemp "${config_file}.XXXXXX") || {
            log_error "Failed to create temp file for $config_file"
            return 1
        }
        # Clean up temp file on any failure
        trap "rm -f '$tmp_file'" RETURN

        head -n "$((abs_line - 1))" "$config_file" > "$tmp_file" || { log_error "Failed to write to temp file"; return 1; }
        echo "$yaml_content" >> "$tmp_file"
        echo "" >> "$tmp_file"
        tail -n "+$abs_line" "$config_file" >> "$tmp_file" || { log_error "Failed to write to temp file"; return 1; }

        mv "$tmp_file" "$config_file" || { log_error "Failed to replace $config_file"; return 1; }
        # Successful mv — clear cleanup trap
        trap - RETURN
    else
        # No next section — append to end of file
        echo "" >> "$config_file"
        echo "$yaml_content" >> "$config_file"
    fi

    return 0
}

# =============================================================================
# MODULE EXPORTS
# =============================================================================

export -f discover_fleet_repos
export -f discover_all_directories
export -f filter_start_inventory_by_repo_depth
export -f filter_start_inventory_git_repos
export -f generate_start_tsv
export -f parse_start_tsv
export -f merge_update_tsv
export -f diff_discovered_repos
export -f get_new_repos
export -f get_missing_repos
export -f generate_service_yaml
export -f generate_manifest_additions
export -f append_services_to_manifest
