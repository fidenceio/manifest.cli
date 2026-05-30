#!/bin/bash

# =============================================================================
# MANIFEST FLEET DOCS MODULE
# =============================================================================
#
# PURPOSE:
#   Orchestrates documentation generation across a fleet of repositories.
#   Supports configurable placement strategies: fleet-root, per-service, or both.
#
# CONFIGURATION:
#   Reads from the "docs" section of manifest.fleet.config.yaml via get_fleet_config_value().
#   See examples/manifest.fleet.config.yaml.example for the full schema.
#
# KEY FUNCTIONS:
#   - fleet_docs_dispatch()           : Route fleet docs subcommands
#   - fleet_docs_run()                : Resolve docs targets and delegate
#   - fleet_docs_run_per_service()    : Iterate services and delegate
#   - fleet_docs_status()             : Show current docs config
#
# DEPENDENCIES:
#   - manifest-fleet-config.sh (get_fleet_config_value, get_fleet_service_property)
#   - manifest-documentation.sh (manifest_docs_generate, release notes, etc.)
#   - manifest-shared-utils.sh (logging)
#
# =============================================================================

# Prevent multiple sourcing
if [[ -n "${_MANIFEST_CLI_FLEET_DOCS_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_CLI_FLEET_DOCS_LOADED=1

# Module metadata
readonly MANIFEST_CLI_FLEET_DOCS_MODULE_VERSION="1.0.0"
readonly MANIFEST_CLI_FLEET_DOCS_MODULE_NAME="manifest-fleet-docs"

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: _compute_relpath (internal)
# -----------------------------------------------------------------------------
# Computes a relative path from one directory to another in pure Bash.
# Both arguments must be absolute paths.
#
# ARGUMENTS:
#   $1 - Target path (where we want to point)
#   $2 - Base path (where we're coming from)
#
# RETURNS:
#   Echoes the relative path from $2 to $1.
# -----------------------------------------------------------------------------
_compute_relpath() {
    local target="$1"
    local base="$2"

    # Ensure trailing slashes are stripped
    target="${target%/}"
    base="${base%/}"

    # Split into arrays
    local IFS='/'
    read -ra target_parts <<< "$target"
    read -ra base_parts <<< "$base"

    # Find common prefix length
    local common=0
    while [[ $common -lt ${#target_parts[@]} ]] && [[ $common -lt ${#base_parts[@]} ]] \
          && [[ "${target_parts[$common]}" == "${base_parts[$common]}" ]]; do
        ((common++))
    done

    # Build relative path: go up from base, then down to target
    local rel=""
    local i
    for (( i=common; i<${#base_parts[@]}; i++ )); do
        rel="${rel}../"
    done
    for (( i=common; i<${#target_parts[@]}; i++ )); do
        rel="${rel}${target_parts[$i]}/"
    done

    # Strip trailing slash (but return "." for empty result)
    rel="${rel%/}"
    printf '%s' "${rel:-.}"
}

# =============================================================================
# STRATEGY RESOLUTION
# =============================================================================

# -----------------------------------------------------------------------------
# Function: get_fleet_docs_strategy
# -----------------------------------------------------------------------------
# Resolves the effective docs placement strategy from configuration.
#
# RETURNS:
#   Echoes one of: "fleet-root" | "per-service" | "both"
# -----------------------------------------------------------------------------
get_fleet_docs_strategy() {
    local strategy
    strategy=$(get_fleet_config_value "docs_strategy" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_STRATEGY")
    echo "$strategy"
}

fleet_docs_export_generation_config() {
    export MANIFEST_CLI_DOCS_GENERATE_ENABLED
    MANIFEST_CLI_DOCS_GENERATE_ENABLED=$(get_fleet_config_value "docs_gen_enabled" "${MANIFEST_CLI_DOCS_GENERATE_ENABLED:-true}")
    export MANIFEST_CLI_DOCS_GENERATE_CHANGELOG
    MANIFEST_CLI_DOCS_GENERATE_CHANGELOG=$(get_fleet_config_value "docs_gen_changelog" "${MANIFEST_CLI_DOCS_GENERATE_CHANGELOG:-true}")
    export MANIFEST_CLI_DOCS_GENERATE_README_VERSION
    MANIFEST_CLI_DOCS_GENERATE_README_VERSION=$(get_fleet_config_value "docs_gen_readme_version" "${MANIFEST_CLI_DOCS_GENERATE_README_VERSION:-true}")
    export MANIFEST_CLI_DOCS_GENERATE_INDEX
    MANIFEST_CLI_DOCS_GENERATE_INDEX=$(get_fleet_config_value "docs_gen_index" "${MANIFEST_CLI_DOCS_GENERATE_INDEX:-true}")
    export MANIFEST_CLI_DOCS_GENERATE_ARCHIVE_CLEANUP
    MANIFEST_CLI_DOCS_GENERATE_ARCHIVE_CLEANUP=$(get_fleet_config_value "docs_gen_archive_cleanup" "${MANIFEST_CLI_DOCS_GENERATE_ARCHIVE_CLEANUP:-true}")
    export MANIFEST_CLI_DOCS_GENERATE_SITE
    MANIFEST_CLI_DOCS_GENERATE_SITE=$(get_fleet_config_value "docs_gen_site" "${MANIFEST_CLI_DOCS_GENERATE_SITE:-true}")
    export MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW
    MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW=$(get_fleet_config_value "docs_gen_site_workflow" "${MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW:-true}")
    export MANIFEST_CLI_DOCS_SITE_ENABLED
    MANIFEST_CLI_DOCS_SITE_ENABLED=$(get_fleet_config_value "docs_site_enabled" "${MANIFEST_CLI_DOCS_SITE_ENABLED:-false}")
    export MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES
    MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES=$(get_fleet_config_value "docs_site_enable_pages" "${MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES:-true}")
    export MANIFEST_CLI_DOCS_SITE_SOURCE_DIR
    MANIFEST_CLI_DOCS_SITE_SOURCE_DIR=$(get_fleet_config_value "docs_site_source_dir" "${MANIFEST_CLI_DOCS_SITE_SOURCE_DIR:-docs-site}")
    export MANIFEST_CLI_DOCS_SITE_PUBLISH_MODE
    MANIFEST_CLI_DOCS_SITE_PUBLISH_MODE=$(get_fleet_config_value "docs_site_publish_mode" "${MANIFEST_CLI_DOCS_SITE_PUBLISH_MODE:-actions}")
    export MANIFEST_CLI_DOCS_SITE_BRANDING
    MANIFEST_CLI_DOCS_SITE_BRANDING=$(get_fleet_config_value "docs_site_branding" "${MANIFEST_CLI_DOCS_SITE_BRANDING:-auto}")
    export MANIFEST_CLI_DOCS_SITE_THEME
    MANIFEST_CLI_DOCS_SITE_THEME=$(get_fleet_config_value "docs_site_theme" "${MANIFEST_CLI_DOCS_SITE_THEME:-manifest}")
    export MANIFEST_CLI_DOCS_SITE_TITLE
    MANIFEST_CLI_DOCS_SITE_TITLE=$(get_fleet_config_value "docs_site_title" "${MANIFEST_CLI_DOCS_SITE_TITLE:-}")
    export MANIFEST_CLI_DOCS_SITE_DESCRIPTION
    MANIFEST_CLI_DOCS_SITE_DESCRIPTION=$(get_fleet_config_value "docs_site_description" "${MANIFEST_CLI_DOCS_SITE_DESCRIPTION:-}")
    export MANIFEST_CLI_DOCS_SITE_CUSTOM_CSS
    MANIFEST_CLI_DOCS_SITE_CUSTOM_CSS=$(get_fleet_config_value "docs_site_custom_css" "${MANIFEST_CLI_DOCS_SITE_CUSTOM_CSS:-}")
    export MANIFEST_CLI_DOCS_SITE_PALETTE_PRIMARY
    MANIFEST_CLI_DOCS_SITE_PALETTE_PRIMARY=$(get_fleet_config_value "docs_site_palette_primary" "${MANIFEST_CLI_DOCS_SITE_PALETTE_PRIMARY:-#2563eb}")
    export MANIFEST_CLI_DOCS_SITE_PALETTE_ACCENT
    MANIFEST_CLI_DOCS_SITE_PALETTE_ACCENT=$(get_fleet_config_value "docs_site_palette_accent" "${MANIFEST_CLI_DOCS_SITE_PALETTE_ACCENT:-#14b8a6}")
    export MANIFEST_CLI_DOCS_SITE_PALETTE_BACKGROUND
    MANIFEST_CLI_DOCS_SITE_PALETTE_BACKGROUND=$(get_fleet_config_value "docs_site_palette_background" "${MANIFEST_CLI_DOCS_SITE_PALETTE_BACKGROUND:-#ffffff}")
    export MANIFEST_CLI_DOCS_SITE_PALETTE_SURFACE
    MANIFEST_CLI_DOCS_SITE_PALETTE_SURFACE=$(get_fleet_config_value "docs_site_palette_surface" "${MANIFEST_CLI_DOCS_SITE_PALETTE_SURFACE:-#f8fafc}")
    export MANIFEST_CLI_DOCS_SITE_PALETTE_TEXT
    MANIFEST_CLI_DOCS_SITE_PALETTE_TEXT=$(get_fleet_config_value "docs_site_palette_text" "${MANIFEST_CLI_DOCS_SITE_PALETTE_TEXT:-#111827}")
    export MANIFEST_CLI_DOCS_SITE_PALETTE_MUTED
    MANIFEST_CLI_DOCS_SITE_PALETTE_MUTED=$(get_fleet_config_value "docs_site_palette_muted" "${MANIFEST_CLI_DOCS_SITE_PALETTE_MUTED:-#64748b}")
}

# -----------------------------------------------------------------------------
# Function: should_generate_fleet_root_docs
# -----------------------------------------------------------------------------
# Returns 0 (true) if fleet-root docs should be generated.
# Determined by the strategy value.
# -----------------------------------------------------------------------------
should_generate_fleet_root_docs() {
    local strategy
    strategy=$(get_fleet_docs_strategy)
    [[ "$strategy" == "fleet-root" || "$strategy" == "both" ]]
}

# -----------------------------------------------------------------------------
# Function: should_generate_per_service_docs
# -----------------------------------------------------------------------------
# Returns 0 (true) if per-service docs should be generated.
# Determined by the strategy value.
# -----------------------------------------------------------------------------
should_generate_per_service_docs() {
    local strategy
    strategy=$(get_fleet_docs_strategy)
    [[ "$strategy" == "per-service" || "$strategy" == "both" ]]
}

# =============================================================================
# FLEET DOCUMENTATION ORCHESTRATION
# =============================================================================

fleet_docs_run_fleet_root() {
    local fleet_version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"
    fleet_docs_export_generation_config
    manifest_docs_generate "$fleet_version" "$timestamp" "$release_type" "fleet-root"
}

fleet_docs_run_per_service() {
    local release_type="${1:-patch}"

    local per_service_folder
    per_service_folder=$(get_fleet_config_value "docs_per_service_folder" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER")

    log_info "Generating per-service docs (folder: $per_service_folder)..."

    local any_failures=0

    for service in $MANIFEST_CLI_FLEET_SERVICES; do
        local path
        path=$(get_fleet_service_property "$service" "path")
        local excluded
        excluded=$(get_fleet_service_property "$service" "excluded" "false")

        if [[ "$excluded" == "true" ]]; then
            echo "  - $service: skipped (excluded)"
            continue
        fi

        if [[ ! -d "$path" ]]; then
            echo "  - $service: skipped (path not found)"
            continue
        fi

        # Read service version
        local version="unknown"
        if declare -F _get_repo_version >/dev/null 2>&1; then
            version=$(_get_repo_version "$path" 2>/dev/null || echo "unknown")
        elif [[ -f "$path/VERSION" ]]; then
            version=$(cat "$path/VERSION" 2>/dev/null || echo "unknown")
        fi

        if [[ "$version" == "unknown" ]]; then
            echo "  - $service: skipped (no version found)"
            continue
        fi

        # Generate docs in a subshell to isolate PROJECT_ROOT changes
        (
            cd "$path" || exit 1
            export PROJECT_ROOT="$path"
            export MANIFEST_CLI_DOCS_FOLDER="$per_service_folder"
            fleet_docs_export_generation_config

            # Get timestamp
            local timestamp
            if declare -F get_time_timestamp >/dev/null 2>&1; then
                get_time_timestamp >/dev/null 2>&1
                timestamp=$(format_timestamp "${MANIFEST_CLI_TIME_TIMESTAMP:-$(date +%s)}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
            else
                timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
            fi

            if declare -F manifest_docs_generate >/dev/null 2>&1; then
                manifest_docs_generate "$version" "$timestamp" "$release_type" "repo"
            else
                log_warning "$service: manifest_docs_generate() not available"
                exit 1
            fi
        ) && {
            echo "  - $service: docs generated (v$version)"
        } || {
            echo "  - $service: docs generation failed"
            any_failures=1
        }
    done

    if [[ "$any_failures" -eq 1 ]]; then
        log_warning "Some per-service docs failed to generate"
        return 1
    fi

    log_success "Per-service documentation generated"
    return 0
}

fleet_docs_run() {
    local strategy_override=""
    local fleet_only=false
    local services_only=false
    local release_type="patch"
    local dry_run=false
    local replay_command="manifest docs fleet"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                dry_run=true
                shift
                ;;
            --strategy)
                if [[ -z "${2:-}" ]] || [[ "${2:-}" == --* ]]; then
                    log_error "--strategy requires a value: fleet-root|per-service|both"
                    return 1
                fi
                strategy_override="$2"
                shift 2
                ;;
            --fleet-only)
                fleet_only=true
                shift
                ;;
            --services-only)
                services_only=true
                shift
                ;;
            patch|minor|major|revision)
                release_type="$1"
                shift
                ;;
            *)
                log_error "Unknown option for fleet docs: $1"
                return 1
                ;;
        esac
    done

    # Resolve effective strategy
    local strategy
    if [[ -n "$strategy_override" ]]; then
        strategy="$strategy_override"
    else
        strategy=$(get_fleet_docs_strategy)
    fi

    # Override with --fleet-only / --services-only flags
    local do_fleet_root=false
    local do_per_service=false

    if [[ "$fleet_only" == "true" ]]; then
        do_fleet_root=true
        do_per_service=false
    elif [[ "$services_only" == "true" ]]; then
        do_fleet_root=false
        do_per_service=true
    else
        case "$strategy" in
            "fleet-root")
                do_fleet_root=true
                do_per_service=false
                ;;
            "per-service")
                do_fleet_root=false
                do_per_service=true
                ;;
            "both")
                do_fleet_root=true
                do_per_service=true
                ;;
            *)
                log_warning "Unknown docs strategy: $strategy, defaulting to per-service"
                do_fleet_root=false
                do_per_service=true
                ;;
        esac
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo ""
        echo "Dry run - manifest docs fleet"
        echo ""
        echo "Strategy:     $strategy"
        echo "Release type: $release_type"
        if [[ "$do_fleet_root" == "true" ]]; then
            local fleet_root_folder
            fleet_root_folder=$(get_fleet_config_value "docs_fleet_root_folder" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_FLEET_ROOT_FOLDER")
            echo "Would write:   fleet-root docs in $MANIFEST_CLI_FLEET_ROOT/$fleet_root_folder/"
        else
            echo "Would skip:    fleet-root docs"
        fi
        if [[ "$do_per_service" == "true" ]]; then
            local per_service_folder
            per_service_folder=$(get_fleet_config_value "docs_per_service_folder" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER")
            local service_count=0
            local missing_count=0
            local excluded_count=0
            local service path excluded
            for service in $MANIFEST_CLI_FLEET_SERVICES; do
                excluded=$(get_fleet_service_property "$service" "excluded" "false")
                if [[ "$excluded" == "true" ]]; then
                    ((excluded_count += 1))
                    continue
                fi
                path=$(get_fleet_service_property "$service" "path")
                if [[ -d "$path" ]]; then
                    ((service_count += 1))
                else
                    ((missing_count += 1))
                fi
            done
            echo "Would write:   per-service docs folder '$per_service_folder/' for $service_count service(s)"
            [[ "$excluded_count" -gt 0 ]] && echo "Would skip:    $excluded_count excluded service(s)"
            [[ "$missing_count" -gt 0 ]] && echo "Would warn:    $missing_count service path(s) not found"
        else
            echo "Would skip:    per-service docs"
        fi
        echo ""
        if [[ "$release_type" != "patch" ]]; then
            replay_command="$replay_command $release_type"
        fi
        if [[ "$fleet_only" == "true" ]]; then
            replay_command="$replay_command --fleet-only"
        elif [[ "$services_only" == "true" ]]; then
            replay_command="$replay_command --services-only"
        elif [[ -n "$strategy_override" ]]; then
            replay_command="$replay_command --strategy $strategy_override"
        fi
        manifest_execution_footer "$replay_command -y"
        return 0
    fi

    # Get fleet version and timestamp
    local fleet_version="${MANIFEST_CLI_FLEET_VERSION:-unknown}"
    local timestamp
    if declare -F get_time_timestamp >/dev/null 2>&1; then
        get_time_timestamp >/dev/null 2>&1
        timestamp=$(format_timestamp "${MANIFEST_CLI_TIME_TIMESTAMP:-$(date +%s)}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
    else
        timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    fi

    local any_failures=0
    fleet_docs_export_generation_config

    # Generate fleet-root docs
    if [[ "$do_fleet_root" == "true" ]]; then
        echo "📄 Generating fleet-root documentation..."
        fleet_docs_run_fleet_root "$fleet_version" "$timestamp" "$release_type" || {
            log_warning "Fleet-root docs generation had issues"
            any_failures=1
        }
    fi

    # Generate per-service docs
    if [[ "$do_per_service" == "true" ]]; then
        echo "📄 Generating per-service documentation..."
        fleet_docs_run_per_service "$release_type" || {
            log_warning "Per-service docs generation had issues"
            any_failures=1
        }
    fi

    if [[ "$any_failures" -eq 1 ]]; then
        return 1
    fi

    return 0
}

# -----------------------------------------------------------------------------
# Function: fleet_docs_status
# -----------------------------------------------------------------------------
# Displays current docs configuration and what would be generated.
# -----------------------------------------------------------------------------
fleet_docs_status() {
    local strategy
    strategy=$(get_fleet_docs_strategy)

    local fleet_root_folder
    fleet_root_folder=$(get_fleet_config_value "docs_fleet_root_folder" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_FLEET_ROOT_FOLDER")

    local fleet_root_detail
    fleet_root_detail=$(get_fleet_config_value "docs_fleet_root_detail_level" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_FLEET_ROOT_DETAIL_LEVEL")

    local per_service_folder
    per_service_folder=$(get_fleet_config_value "docs_per_service_folder" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER")

    echo ""
    echo "Fleet Docs Configuration"
    echo "========================"
    echo ""
    echo "Strategy: $strategy"
    echo ""

    if should_generate_fleet_root_docs; then
        echo "Fleet-Root Docs:  ENABLED"
        echo "  Folder:         $MANIFEST_CLI_FLEET_ROOT/$fleet_root_folder/"
        echo "  Detail Level:   $fleet_root_detail"
    else
        echo "Fleet-Root Docs:  disabled"
    fi

    echo ""

    if should_generate_per_service_docs; then
        echo "Per-Service Docs: ENABLED"
        echo "  Folder Name:    $per_service_folder/"
        echo ""
        echo "  Services:"
        for service in $MANIFEST_CLI_FLEET_SERVICES; do
            local path
            path=$(get_fleet_service_property "$service" "path")
            local excluded
            excluded=$(get_fleet_service_property "$service" "excluded" "false")

            if [[ "$excluded" == "true" ]]; then
                echo "    - $service: excluded"
            elif [[ -d "$path" ]]; then
                local version="unknown"
                if declare -F _get_repo_version >/dev/null 2>&1; then
                    version=$(_get_repo_version "$path" 2>/dev/null || echo "unknown")
                fi
                echo "    - $service (v$version): $path/$per_service_folder/"
            else
                echo "    - $service: path not found ($path)"
            fi
        done
    else
        echo "Per-Service Docs: disabled"
    fi

    # Show generation settings
    echo ""
    echo "Document Types:"
    echo "  Enabled:        $(get_fleet_config_value "docs_gen_enabled" "${MANIFEST_CLI_DOCS_GENERATE_ENABLED:-true}")"
    echo "  Changelog:      $(get_fleet_config_value "docs_gen_changelog" "${MANIFEST_CLI_DOCS_GENERATE_CHANGELOG:-true}")"
    echo "  Index:          $(get_fleet_config_value "docs_gen_index" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_GEN_INDEX")"
    echo "  README Version: $(get_fleet_config_value "docs_gen_readme_version" "$MANIFEST_CLI_FLEET_DEFAULT_DOCS_GEN_README_VERSION")"
    echo "  Site:           $(get_fleet_config_value "docs_gen_site" "${MANIFEST_CLI_DOCS_GENERATE_SITE:-true}")"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: fleet_docs_help
# -----------------------------------------------------------------------------
# Displays help for the fleet docs subcommand.
# -----------------------------------------------------------------------------
fleet_docs_help() {
    cat << 'EOF'
Usage: manifest docs fleet [subcommand] [-y|--yes] [--dry-run] [options]

Subcommands:
  generate          Generate fleet documentation (default)
  status            Show current docs configuration
  help              Show this help

Generate Options:
  --strategy <s>    Override docs strategy for this run
                    Values: fleet-root | per-service | both
  --fleet-only      Only generate fleet-root docs
  --services-only   Only generate per-service docs
  --dry-run         Preview planned docs writes without changing files
  -y, --yes         Apply planned docs writes
  patch|minor|major Release type (default: patch)

Configuration:
  Set the "docs" section in manifest.fleet.config.yaml to control placement:

    docs:
      strategy: "per-service"    # fleet-root | per-service | both
      fleet_root:
        folder: "docs"
        detail_level: "summary"  # summary | index
      per_service:
        folder: "docs"
      generate:
        enabled: true
        changelog: true
        readme_version: true
        index: true
        archive_cleanup: true
        site: false
        site_workflow: true
      site:
        enabled: false
        source_dir: "docs-site"
        enable_pages: false

Examples:
  manifest docs fleet                     # Generate per configured strategy
  manifest docs fleet generate            # Same as above
  manifest docs fleet generate -y         # Apply configured generation
  manifest docs fleet status              # Show docs configuration
  manifest docs fleet generate --fleet-only   # Only fleet-root docs
  manifest docs fleet generate --strategy both  # Override strategy
  manifest docs fleet --dry-run             # Preview configured generation
EOF
}

# -----------------------------------------------------------------------------
# Function: fleet_docs_dispatch
# -----------------------------------------------------------------------------
# Routes fleet docs subcommands to their handlers.
#
# ARGUMENTS:
#   $@ - Subcommand and flags
# -----------------------------------------------------------------------------
fleet_docs_dispatch() {
    local subcmd="${1:-generate}"
    shift 2>/dev/null || true
    local execution_mode="preview"
    local _local_only=false
    local remaining_args=()

    case "$subcmd" in
        generate)
            _fleet_ensure_initialized || return 1
            if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
                return 1
            fi
            if [[ "$execution_mode" == "preview" ]]; then
                fleet_docs_run --dry-run "${remaining_args[@]}"
            else
                manifest_execution_apply_header
                fleet_docs_run "${remaining_args[@]}"
            fi
            ;;
        status)
            _fleet_ensure_initialized || return 1
            fleet_docs_status
            ;;
        help|--help|-h)
            fleet_docs_help
            ;;
        # Allow passing flags directly to generate (e.g., manifest docs fleet --fleet-only)
        --fleet-only|--services-only|--strategy|--dry-run|-y|--yes)
            _fleet_ensure_initialized || return 1
            if ! manifest_execution_parse execution_mode _local_only remaining_args "$subcmd" "$@"; then
                return 1
            fi
            if [[ "$execution_mode" == "preview" ]]; then
                fleet_docs_run --dry-run "${remaining_args[@]}"
            else
                manifest_execution_apply_header
                fleet_docs_run "${remaining_args[@]}"
            fi
            ;;
        patch|minor|major|revision)
            _fleet_ensure_initialized || return 1
            if ! manifest_execution_parse execution_mode _local_only remaining_args "$@"; then
                return 1
            fi
            if [[ "$execution_mode" == "preview" ]]; then
                fleet_docs_run "$subcmd" --dry-run "${remaining_args[@]}"
            else
                manifest_execution_apply_header
                fleet_docs_run "$subcmd" "${remaining_args[@]}"
            fi
            ;;
        *)
            log_error "Unknown docs subcommand: $subcmd"
            fleet_docs_help
            return 1
            ;;
    esac
}
