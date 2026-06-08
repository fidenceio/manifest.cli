#!/bin/bash

# =============================================================================
# MANIFEST DISCOVERY MODULE
# =============================================================================
#
# Shared filesystem exploration helpers. Fleet, version-surface detection, and
# future repo scanners should put common downward traversal here, then layer
# domain-specific classification on top.
# =============================================================================

if [[ -n "${_MANIFEST_CLI_DISCOVERY_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_DISCOVERY_LOADED=1

readonly MANIFEST_CLI_DISCOVERY_MODULE_VERSION="1.0.0"
readonly MANIFEST_CLI_DISCOVERY_MODULE_NAME="manifest-discovery"

readonly MANIFEST_CLI_DISCOVERY_DEFAULT_MAX_DEPTH=5
readonly MANIFEST_CLI_DISCOVERY_MAX_DEPTH_CAP=10

readonly MANIFEST_CLI_DISCOVERY_IGNORE_DEPS=(
    "node_modules"
    "vendor"
    "bower_components"
    ".bundle"
    "Pods"
    ".gradle"
    ".m2"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_BUILD=(
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

readonly MANIFEST_CLI_DISCOVERY_IGNORE_IDE=(
    ".idea"
    ".vscode"
    ".vs"
    ".atom"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_VCS=(
    ".git"
    ".svn"
    ".hg"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_ARCHIVE=(
    "zArchive"
    "archive"
    ".archive"
    "backup"
    ".backup"
    "old"
    ".old"
    "deprecated"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_FIXTURES=(
    "__fixtures__"
    "__mocks__"
    "fixtures"
    "testdata"
    "test-fixtures"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_TEMP=(
    "tmp"
    "temp"
    ".tmp"
    ".temp"
    ".cache"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_DOCS=(
    "examples"
    "docs"
    "documentation"
)

readonly MANIFEST_CLI_DISCOVERY_IGNORE_FLEET_EXTRA=(
    "packages"
)

_manifest_discovery_log_debug() {
    if declare -F log_debug >/dev/null 2>&1; then
        log_debug "$@"
    fi
}

_manifest_discovery_log_error() {
    if declare -F log_error >/dev/null 2>&1; then
        log_error "$@"
    else
        echo "❌ $*" >&2
    fi
}

_manifest_discovery_clamp_depth() {
    local depth="${1:-$MANIFEST_CLI_DISCOVERY_DEFAULT_MAX_DEPTH}"
    local cap="${2:-$MANIFEST_CLI_DISCOVERY_MAX_DEPTH_CAP}"

    if ! [[ "$depth" =~ ^[0-9]+$ ]]; then
        echo "$MANIFEST_CLI_DISCOVERY_DEFAULT_MAX_DEPTH"
        return 0
    fi
    if (( depth > cap )); then
        echo "$cap"
    else
        echo "$depth"
    fi
}

manifest_discovery_should_ignore_directory() {
    local dirname="$1"
    local profile="${2:-default}"
    local all_ignore=(
        "${MANIFEST_CLI_DISCOVERY_IGNORE_DEPS[@]}"
        "${MANIFEST_CLI_DISCOVERY_IGNORE_BUILD[@]}"
        "${MANIFEST_CLI_DISCOVERY_IGNORE_IDE[@]}"
        "${MANIFEST_CLI_DISCOVERY_IGNORE_VCS[@]}"
        "${MANIFEST_CLI_DISCOVERY_IGNORE_ARCHIVE[@]}"
        "${MANIFEST_CLI_DISCOVERY_IGNORE_FIXTURES[@]}"
        "${MANIFEST_CLI_DISCOVERY_IGNORE_TEMP[@]}"
    )

    case "$profile" in
        fleet)
            all_ignore+=(
                "${MANIFEST_CLI_DISCOVERY_IGNORE_DOCS[@]}"
                "${MANIFEST_CLI_DISCOVERY_IGNORE_FLEET_EXTRA[@]}"
            )
            ;;
        version)
            all_ignore+=("${MANIFEST_CLI_DISCOVERY_IGNORE_DOCS[@]}")
            ;;
    esac

    local pattern
    for pattern in "${all_ignore[@]}"; do
        if [[ "$dirname" == "$pattern" ]]; then
            return 0
        fi
    done

    if [[ "$dirname" == .* ]] && [[ "$dirname" != ".git" ]]; then
        return 0
    fi

    return 1
}

manifest_discovery_is_git_repository() {
    local dir="$1"

    if [[ -d "$dir/.git" ]]; then
        return 0
    fi

    if [[ -f "$dir/.git" ]]; then
        return 0
    fi

    if [[ -f "$dir/HEAD" ]] && [[ -d "$dir/objects" ]] && [[ -d "$dir/refs" ]]; then
        return 0
    fi

    return 1
}

manifest_discovery_is_git_submodule() {
    local dir="$1"
    local parent="${2:-}"

    if [[ -f "$dir/.git" ]]; then
        return 0
    fi

    if [[ -n "$parent" ]] && [[ -f "$parent/.gitmodules" ]]; then
        local rel_path="${dir#"$parent"/}"
        if grep -qF "path = $rel_path" "$parent/.gitmodules" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

manifest_discovery_walk_directories() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_CLI_DISCOVERY_DEFAULT_MAX_DEPTH}"
    local min_depth="${3:-0}"
    local profile="${4:-default}"

    if [[ ! -d "$root_dir" ]]; then
        _manifest_discovery_log_error "Discovery root directory does not exist: $root_dir"
        return 1
    fi

    root_dir=$(cd "$root_dir" && pwd)
    max_depth="$(_manifest_discovery_clamp_depth "$max_depth")"
    [[ "$min_depth" =~ ^[0-9]+$ ]] || min_depth=0

    local discovered_paths=()
    _manifest_discovery_walk_recursive "$root_dir" "$root_dir" 0 "$max_depth" "$min_depth" "$profile" discovered_paths
}

_manifest_discovery_walk_recursive() {
    local current_dir="$1"
    local root_dir="$2"
    local current_depth="$3"
    local max_depth="$4"
    local min_depth="$5"
    local profile="$6"
    local _arr_name="$7"
    local -n _discovered_ref="$_arr_name"

    if (( current_depth > max_depth )); then
        return 0
    fi

    local dirname
    dirname=$(basename "$current_dir")
    if (( current_depth > 0 )) && manifest_discovery_should_ignore_directory "$dirname" "$profile"; then
        _manifest_discovery_log_debug "Skipping ignored directory: $current_dir"
        return 0
    fi

    if (( current_depth >= min_depth )); then
        local rel_path
        if [[ "$current_dir" == "$root_dir" ]]; then
            rel_path="."
        else
            rel_path="${current_dir#"$root_dir"/}"
        fi

        local already_found=false
        local found_path
        for found_path in "${_discovered_ref[@]}"; do
            if [[ "$found_path" == "$rel_path" ]]; then
                already_found=true
                break
            fi
        done

        if [[ "$already_found" == "false" ]]; then
            local has_git="false"
            local is_submodule="false"
            if manifest_discovery_is_git_repository "$current_dir"; then
                has_git="true"
                if manifest_discovery_is_git_submodule "$current_dir" "$root_dir"; then
                    is_submodule="true"
                fi
            fi
            printf "%s\t%s\t%s\t%s\t%s\t%s\n" \
                "$current_depth" "$rel_path" "$current_dir" "$dirname" "$has_git" "$is_submodule"
            _discovered_ref+=("$rel_path")
        fi
    fi

    if (( current_depth >= max_depth )); then
        return 0
    fi

    local subdir
    while IFS= read -r -d '' subdir; do
        if [[ -d "$subdir" ]] && [[ ! -L "$subdir" ]]; then
            _manifest_discovery_walk_recursive "$subdir" "$root_dir" "$((current_depth + 1))" "$max_depth" "$min_depth" "$profile" "$_arr_name"
        fi
    done < <(find "$current_dir" -maxdepth 1 -mindepth 1 -type d -print0 2>/dev/null)
    return 0
}

manifest_discovery_find_git_repos() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_CLI_DISCOVERY_DEFAULT_MAX_DEPTH}"
    local include_submodules="${3:-true}"
    local min_depth="${4:-1}"
    local profile="${5:-default}"

    local depth rel_path abs_path dirname has_git is_submodule
    while IFS=$'\t' read -r depth rel_path abs_path dirname has_git is_submodule; do
        [[ -n "$rel_path" ]] || continue
        [[ "$has_git" == "true" ]] || continue
        if [[ "$include_submodules" != "true" && "$is_submodule" == "true" ]]; then
            continue
        fi
        printf "%s\t%s\t%s\t%s\n" "$rel_path" "$abs_path" "$depth" "$is_submodule"
    done < <(manifest_discovery_walk_directories "$root_dir" "$max_depth" "$min_depth" "$profile")
}

manifest_discovery_find_files() {
    local root_dir="${1:-$(pwd)}"
    local max_depth="${2:-$MANIFEST_CLI_DISCOVERY_DEFAULT_MAX_DEPTH}"
    local min_depth="${3:-0}"
    local profile="${4:-default}"
    shift 4 || true
    local file_names=("$@")

    [[ ${#file_names[@]} -gt 0 ]] || return 0

    local depth rel_dir abs_dir dirname has_git is_submodule file_name rel_file abs_file
    while IFS=$'\t' read -r depth rel_dir abs_dir dirname has_git is_submodule; do
        [[ -n "$rel_dir" ]] || continue
        for file_name in "${file_names[@]}"; do
            [[ -n "$file_name" ]] || continue
            abs_file="$abs_dir/$file_name"
            [[ -f "$abs_file" ]] || continue
            if [[ "$rel_dir" == "." ]]; then
                rel_file="$file_name"
            else
                rel_file="$rel_dir/$file_name"
            fi
            printf "%s\t%s\t%s\t%s\t%s\n" "$rel_file" "$abs_file" "$depth" "$rel_dir" "$file_name"
        done
    done < <(manifest_discovery_walk_directories "$root_dir" "$max_depth" "$min_depth" "$profile")
}

export -f _manifest_discovery_log_debug
export -f _manifest_discovery_log_error
export -f _manifest_discovery_clamp_depth
export -f _manifest_discovery_walk_recursive
export -f manifest_discovery_should_ignore_directory
export -f manifest_discovery_is_git_repository
export -f manifest_discovery_is_git_submodule
export -f manifest_discovery_walk_directories
export -f manifest_discovery_find_git_repos
export -f manifest_discovery_find_files
