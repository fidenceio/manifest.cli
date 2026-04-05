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
#   - fleet_docs_generate()           : Main entry point for doc generation
#   - generate_fleet_root_docs()      : Generate unified docs at fleet root
#   - generate_fleet_per_service_docs() : Generate docs in each service
#   - fleet_docs_status()             : Show current docs config
#
# DEPENDENCIES:
#   - manifest-fleet-config.sh (get_fleet_config_value, get_fleet_service_property)
#   - manifest-documentation.sh (generate_documents, generate_release_notes, etc.)
#   - manifest-shared-utils.sh (logging)
#
# =============================================================================

# Prevent multiple sourcing
if [[ -n "${_MANIFEST_FLEET_DOCS_LOADED:-}" ]]; then
    return 0
fi
_MANIFEST_FLEET_DOCS_LOADED=1

# Module metadata
readonly MANIFEST_FLEET_DOCS_MODULE_VERSION="1.0.0"
readonly MANIFEST_FLEET_DOCS_MODULE_NAME="manifest-fleet-docs"

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
    strategy=$(get_fleet_config_value "docs_strategy" "$MANIFEST_FLEET_DEFAULT_DOCS_STRATEGY")
    echo "$strategy"
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
# FLEET-ROOT DOCUMENTATION GENERATION
# =============================================================================

# -----------------------------------------------------------------------------
# Function: generate_fleet_root_docs
# -----------------------------------------------------------------------------
# Generates unified documentation at the fleet root level.
#
# Behavior depends on detail_level config:
#   "summary" - Aggregated RELEASE/CHANGELOG with changes from all services
#   "index"   - Lightweight index listing service versions with links
#
# ARGUMENTS:
#   $1 - Fleet version (e.g., "2026.04.03" or "1.2.0")
#   $2 - Timestamp
#   $3 - Release type (patch|minor|major)
# -----------------------------------------------------------------------------
generate_fleet_root_docs() {
    local fleet_version="$1"
    local timestamp="$2"
    local release_type="${3:-patch}"

    local docs_folder
    docs_folder=$(get_fleet_config_value "docs_fleet_root_folder" "$MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_FOLDER")

    local detail_level
    detail_level=$(get_fleet_config_value "docs_fleet_root_detail_level" "$MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_DETAIL_LEVEL")

    local fleet_docs_dir="$MANIFEST_FLEET_ROOT/$docs_folder"
    mkdir -p "$fleet_docs_dir"

    log_info "Generating fleet-root docs in $fleet_docs_dir (detail_level: $detail_level)..."

    # Check which document types to generate
    local gen_release_notes gen_changelog gen_index gen_readme_version
    gen_release_notes=$(get_fleet_config_value "docs_gen_release_notes" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_RELEASE_NOTES")
    gen_changelog=$(get_fleet_config_value "docs_gen_changelog" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_CHANGELOG")
    gen_index=$(get_fleet_config_value "docs_gen_index" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_INDEX")
    gen_readme_version=$(get_fleet_config_value "docs_gen_readme_version" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_README_VERSION")

    if [[ "$detail_level" == "summary" ]]; then
        _generate_fleet_root_summary "$fleet_version" "$timestamp" "$release_type" \
            "$fleet_docs_dir" "$gen_release_notes" "$gen_changelog" "$gen_index" "$gen_readme_version"
    elif [[ "$detail_level" == "index" ]]; then
        _generate_fleet_root_index "$fleet_version" "$timestamp" \
            "$fleet_docs_dir" "$gen_index"
    else
        log_warning "Unknown fleet docs detail_level: $detail_level, falling back to summary"
        _generate_fleet_root_summary "$fleet_version" "$timestamp" "$release_type" \
            "$fleet_docs_dir" "$gen_release_notes" "$gen_changelog" "$gen_index" "$gen_readme_version"
    fi

    log_success "Fleet-root documentation generated in $fleet_docs_dir"
}

# -----------------------------------------------------------------------------
# Function: _generate_fleet_root_summary (internal)
# -----------------------------------------------------------------------------
# Generates aggregated fleet-root docs with changes from all services.
# -----------------------------------------------------------------------------
_generate_fleet_root_summary() {
    local fleet_version="$1"
    local timestamp="$2"
    local release_type="$3"
    local fleet_docs_dir="$4"
    local gen_release_notes="$5"
    local gen_changelog="$6"
    local gen_index="$7"
    local gen_readme_version="$8"

    # Collect service versions and changes
    local service_summary=""
    local service_changes=""

    for service in $MANIFEST_FLEET_SERVICES; do
        local path
        path=$(get_fleet_service_property "$service" "path")
        local excluded
        excluded=$(get_fleet_service_property "$service" "excluded" "false")

        if [[ "$excluded" == "true" ]]; then
            continue
        fi

        local version="unknown"
        if [[ -d "$path" ]] && declare -F _get_repo_version >/dev/null 2>&1; then
            version=$(_get_repo_version "$path" 2>/dev/null || echo "unknown")
        elif [[ -f "$path/VERSION" ]]; then
            version=$(cat "$path/VERSION" 2>/dev/null || echo "unknown")
        fi

        service_summary="${service_summary}| ${service} | v${version} | ${release_type} |\n"

        # Collect recent git changes for this service
        if [[ -d "$path/.git" ]]; then
            local changes
            changes=$(git -C "$path" log --oneline -10 --no-merges 2>/dev/null || echo "  No recent changes")
            service_changes="${service_changes}
### ${service} (v${version})

\`\`\`
${changes}
\`\`\`
"
        fi
    done

    # Generate fleet-level release notes
    if [[ "$gen_release_notes" == "true" ]]; then
        local release_file="$fleet_docs_dir/RELEASE_v${fleet_version}.md"
        cat > "$release_file" << EOF
# Release Notes - Fleet v${fleet_version}

**Fleet:** ${MANIFEST_FLEET_NAME}
**Version:** ${fleet_version}
**Release Type:** ${release_type}
**Date:** ${timestamp}

## Service Versions

| Service | Version | Bump Type |
|---------|---------|-----------|
$(echo -e "$service_summary")

## Changes by Service
${service_changes}

---
*Generated by Manifest CLI - Fleet Docs*
EOF
        log_success "Fleet release notes generated: $release_file"
    fi

    # Generate fleet-level changelog
    if [[ "$gen_changelog" == "true" ]]; then
        local changelog_file="$fleet_docs_dir/CHANGELOG_v${fleet_version}.md"
        cat > "$changelog_file" << EOF
# Changelog - Fleet v${fleet_version}

**Fleet:** ${MANIFEST_FLEET_NAME}
**Version:** ${fleet_version}
**Date:** ${timestamp}

## Service Summary

| Service | Version | Bump Type |
|---------|---------|-----------|
$(echo -e "$service_summary")

## Detailed Changes
${service_changes}

---
*Generated by Manifest CLI - Fleet Docs*
EOF
        log_success "Fleet changelog generated: $changelog_file"
    fi

    # Generate fleet-level index
    if [[ "$gen_index" == "true" ]]; then
        _generate_fleet_docs_index "$fleet_version" "$timestamp" "$fleet_docs_dir"
    fi

    # Update fleet-root README if present
    if [[ "$gen_readme_version" == "true" ]] && [[ -f "$MANIFEST_FLEET_ROOT/README.md" ]]; then
        (
            PROJECT_ROOT="$MANIFEST_FLEET_ROOT"
            update_readme_version "$fleet_version" "$timestamp" 2>/dev/null || true
        )
    fi
}

# -----------------------------------------------------------------------------
# Function: _generate_fleet_root_index (internal)
# -----------------------------------------------------------------------------
# Generates a lightweight index at fleet root with links to per-service docs.
# -----------------------------------------------------------------------------
_generate_fleet_root_index() {
    local fleet_version="$1"
    local timestamp="$2"
    local fleet_docs_dir="$3"
    local gen_index="$4"

    if [[ "$gen_index" != "true" ]]; then
        return 0
    fi

    _generate_fleet_docs_index "$fleet_version" "$timestamp" "$fleet_docs_dir"
}

# -----------------------------------------------------------------------------
# Function: _generate_fleet_docs_index (internal)
# -----------------------------------------------------------------------------
# Generates INDEX.md for fleet-root docs.
# Lists all services with versions and paths to their individual docs.
# -----------------------------------------------------------------------------
_generate_fleet_docs_index() {
    local fleet_version="$1"
    local timestamp="$2"
    local fleet_docs_dir="$3"

    local per_service_folder
    per_service_folder=$(get_fleet_config_value "docs_per_service_folder" "$MANIFEST_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER")

    local index_file="$fleet_docs_dir/INDEX.md"
    cat > "$index_file" << EOF
# Fleet Documentation Index

**Fleet:** ${MANIFEST_FLEET_NAME}
**Version:** ${fleet_version}
**Last Updated:** ${timestamp}

## Services

| Service | Version | Type | Docs |
|---------|---------|------|------|
EOF

    for service in $MANIFEST_FLEET_SERVICES; do
        local path
        path=$(get_fleet_service_property "$service" "path")
        local type
        type=$(get_fleet_service_property "$service" "type" "service")
        local excluded
        excluded=$(get_fleet_service_property "$service" "excluded" "false")

        if [[ "$excluded" == "true" ]]; then
            continue
        fi

        local version="unknown"
        if [[ -d "$path" ]] && declare -F _get_repo_version >/dev/null 2>&1; then
            version=$(_get_repo_version "$path" 2>/dev/null || echo "unknown")
        elif [[ -f "$path/VERSION" ]]; then
            version=$(cat "$path/VERSION" 2>/dev/null || echo "unknown")
        fi

        # Compute relative path from fleet docs dir to service docs
        local rel_path
        rel_path=$(python3 -c "import os.path; print(os.path.relpath('$path/$per_service_folder', '$fleet_docs_dir'))" 2>/dev/null || echo "$path/$per_service_folder")

        echo "| ${service} | v${version} | ${type} | [docs](${rel_path}/) |" >> "$index_file"
    done

    cat >> "$index_file" << EOF

---
*Generated by Manifest CLI - Fleet Docs*
EOF

    log_success "Fleet docs index generated: $index_file"
}

# =============================================================================
# PER-SERVICE DOCUMENTATION GENERATION
# =============================================================================

# -----------------------------------------------------------------------------
# Function: generate_fleet_per_service_docs
# -----------------------------------------------------------------------------
# Iterates over fleet services and generates docs in each.
# Respects exclude_from_fleet_bump and per-service folder config.
#
# ARGUMENTS:
#   $1 - Release type (patch|minor|major)
# -----------------------------------------------------------------------------
generate_fleet_per_service_docs() {
    local release_type="${1:-patch}"

    local per_service_folder
    per_service_folder=$(get_fleet_config_value "docs_per_service_folder" "$MANIFEST_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER")

    log_info "Generating per-service docs (folder: $per_service_folder)..."

    local any_failures=0

    for service in $MANIFEST_FLEET_SERVICES; do
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

            # Get timestamp
            local timestamp
            if declare -F get_time_timestamp >/dev/null 2>&1; then
                get_time_timestamp >/dev/null 2>&1
                timestamp=$(format_timestamp "${MANIFEST_CLI_TIME_TIMESTAMP:-$(date +%s)}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
            else
                timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
            fi

            if declare -F generate_documents >/dev/null 2>&1; then
                generate_documents "$version" "$timestamp" "$release_type"
            else
                log_warning "$service: generate_documents() not available"
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

# =============================================================================
# MAIN ENTRY POINTS
# =============================================================================

# -----------------------------------------------------------------------------
# Function: fleet_docs_generate
# -----------------------------------------------------------------------------
# Main entry point for fleet docs generation.
# Reads strategy config and dispatches to fleet-root and/or per-service.
#
# ARGUMENTS:
#   $@ - Optional flags: --fleet-only, --services-only, --strategy <s>
# -----------------------------------------------------------------------------
fleet_docs_generate() {
    local strategy_override=""
    local fleet_only=false
    local services_only=false
    local release_type="patch"

    while [[ $# -gt 0 ]]; do
        case "$1" in
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
                log_error "Unknown option for fleet docs generate: $1"
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

    # Get fleet version and timestamp
    local fleet_version="${MANIFEST_FLEET_VERSION:-unknown}"
    local timestamp
    if declare -F get_time_timestamp >/dev/null 2>&1; then
        get_time_timestamp >/dev/null 2>&1
        timestamp=$(format_timestamp "${MANIFEST_CLI_TIME_TIMESTAMP:-$(date +%s)}" '+%Y-%m-%d %H:%M:%S UTC' 2>/dev/null || date -u '+%Y-%m-%d %H:%M:%S UTC')
    else
        timestamp=$(date -u '+%Y-%m-%d %H:%M:%S UTC')
    fi

    local any_failures=0

    # Generate fleet-root docs
    if [[ "$do_fleet_root" == "true" ]]; then
        echo "📄 Generating fleet-root documentation..."
        generate_fleet_root_docs "$fleet_version" "$timestamp" "$release_type" || {
            log_warning "Fleet-root docs generation had issues"
            any_failures=1
        }
    fi

    # Generate per-service docs
    if [[ "$do_per_service" == "true" ]]; then
        echo "📄 Generating per-service documentation..."
        generate_fleet_per_service_docs "$release_type" || {
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
    fleet_root_folder=$(get_fleet_config_value "docs_fleet_root_folder" "$MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_FOLDER")

    local fleet_root_detail
    fleet_root_detail=$(get_fleet_config_value "docs_fleet_root_detail_level" "$MANIFEST_FLEET_DEFAULT_DOCS_FLEET_ROOT_DETAIL_LEVEL")

    local per_service_folder
    per_service_folder=$(get_fleet_config_value "docs_per_service_folder" "$MANIFEST_FLEET_DEFAULT_DOCS_PER_SERVICE_FOLDER")

    echo ""
    echo "Fleet Docs Configuration"
    echo "========================"
    echo ""
    echo "Strategy: $strategy"
    echo ""

    if should_generate_fleet_root_docs; then
        echo "Fleet-Root Docs:  ENABLED"
        echo "  Folder:         $MANIFEST_FLEET_ROOT/$fleet_root_folder/"
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
        for service in $MANIFEST_FLEET_SERVICES; do
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
    echo "  Release Notes:  $(get_fleet_config_value "docs_gen_release_notes" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_RELEASE_NOTES")"
    echo "  Changelog:      $(get_fleet_config_value "docs_gen_changelog" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_CHANGELOG")"
    echo "  Index:          $(get_fleet_config_value "docs_gen_index" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_INDEX")"
    echo "  README Version: $(get_fleet_config_value "docs_gen_readme_version" "$MANIFEST_FLEET_DEFAULT_DOCS_GEN_README_VERSION")"
    echo ""
}

# -----------------------------------------------------------------------------
# Function: fleet_docs_help
# -----------------------------------------------------------------------------
# Displays help for the fleet docs subcommand.
# -----------------------------------------------------------------------------
fleet_docs_help() {
    cat << 'EOF'
Usage: manifest fleet docs [subcommand] [options]

Subcommands:
  generate          Generate fleet documentation (default)
  status            Show current docs configuration
  help              Show this help

Generate Options:
  --strategy <s>    Override docs strategy for this run
                    Values: fleet-root | per-service | both
  --fleet-only      Only generate fleet-root docs
  --services-only   Only generate per-service docs
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

Examples:
  manifest fleet docs                     # Generate per configured strategy
  manifest fleet docs generate            # Same as above
  manifest fleet docs status              # Show docs configuration
  manifest fleet docs generate --fleet-only   # Only fleet-root docs
  manifest fleet docs generate --strategy both  # Override strategy
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

    case "$subcmd" in
        generate)
            fleet_docs_generate "$@"
            ;;
        status)
            fleet_docs_status
            ;;
        help|--help|-h)
            fleet_docs_help
            ;;
        # Allow passing flags directly to generate (e.g., manifest fleet docs --fleet-only)
        --fleet-only|--services-only|--strategy)
            fleet_docs_generate "$subcmd" "$@"
            ;;
        patch|minor|major|revision)
            fleet_docs_generate "$subcmd" "$@"
            ;;
        *)
            log_error "Unknown docs subcommand: $subcmd"
            fleet_docs_help
            return 1
            ;;
    esac
}
