#!/bin/bash

# Manifest Cleanup Docs Module
# Handles moving old documentation to zArchive and general repository cleanup

# Cleanup-docs module - uses MANIFEST_CLI_PROJECT_ROOT from core module

# Get configurable documentation paths
get_zarchive_dir() {
    get_docs_archive_folder "$MANIFEST_CLI_PROJECT_ROOT"
}

# Ensure zArchive directory exists
ensure_zarchive_dir() {
    local zarchive_dir=$(get_zarchive_dir)
    if [[ ! -d "$zarchive_dir" ]]; then
        log_info "Creating zArchive directory: $zarchive_dir"
        mkdir -p "$zarchive_dir"
        log_success "zArchive directory created"
    fi
}


# Clean up temporary files (enhanced version)
cleanup_temp_files() {
    log_info "Cleaning up temporary files..."
    
    local cleaned_count=0
    
    # Remove common temporary files
    local temp_patterns=(
        "*.tmp"
        "*.temp"
        "*.bak"
        "*.backup"
        "*~"
        ".DS_Store"
        "Thumbs.db"
    )
    
    for pattern in "${temp_patterns[@]}"; do
        while IFS= read -r file; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                cleaned_count=$((cleaned_count + 1))
            fi
        done < <(find "$MANIFEST_CLI_PROJECT_ROOT" -name "$pattern" -type f 2>/dev/null || true)
    done
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_success "Cleaned up $cleaned_count temporary files"
    else
        log_info "No temporary files found"
    fi
}

# Clean up empty directories
cleanup_empty_dirs() {
    log_info "Cleaning up empty directories..."
    
    local cleaned_count=0
    
    # Find and remove empty directories (except important ones)
    while IFS= read -r dir; do
        if [[ -d "$dir" && "$dir" != "$MANIFEST_CLI_PROJECT_ROOT" && "$dir" != "$MANIFEST_CLI_PROJECT_ROOT/.git" ]]; then
            if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                rmdir "$dir" 2>/dev/null && cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done < <(find "$MANIFEST_CLI_PROJECT_ROOT" -type d -empty 2>/dev/null || true)
    
    if [[ $cleaned_count -gt 0 ]]; then
        log_success "Removed $cleaned_count empty directories"
    else
        log_info "No empty directories found"
    fi
}

# Validate repository state
validate_repository() {
    log_info "Validating repository state..."
    
    local issues=0
    
    # Check for uncommitted changes
    if ! git diff --quiet 2>/dev/null; then
        log_warning "Repository has uncommitted changes"
        issues=$((issues + 1))
    fi
    
    # Check for untracked files
    if [[ -n "$(git ls-files --others --exclude-standard 2>/dev/null)" ]]; then
        log_warning "Repository has untracked files"
        issues=$((issues + 1))
    fi
    
    # Check zArchive directory
    local zarchive_dir=$(get_zarchive_dir)
    if [[ ! -d "$zarchive_dir" ]]; then
        log_warning "zArchive directory does not exist: $zarchive_dir"
        issues=$((issues + 1))
    fi
    
    if [[ $issues -eq 0 ]]; then
        log_success "Repository state is valid"
        return 0
    else
        log_warning "Repository has $issues issues"
        return 1
    fi
}

# Strict regex for archivable filenames. Anchored to start and end of the
# basename so similar-prefixed hand-authored docs are not swept up.
# Per-version RELEASE/CHANGELOG files are no longer generated — root
# CHANGELOG.md is the single archival surface — so only point-in-time
# audit artifacts (SECURITY_ANALYSIS_REPORT_v*) are archived now.
_MANIFEST_ARCHIVABLE_REGEX='^SECURITY_ANALYSIS_REPORT_v[0-9]+\.[0-9]+\.[0-9]+(_[0-9]+T[0-9]+Z)?\.md$'

# Note: docs/zArchive/ is a read-only "memory" — files enter by move only,
# and nothing is ever created or modified inside it. There is deliberately no
# INDEX.md regeneration and no per-major v<major>/ routing here: a sweep moves
# a file flat into docs/zArchive/ and stops. Legacy v<major>/ folders from
# before this rule stay where they are; new moves go flat.

# Append a sweep entry to docs/zArchive/.archive-log.md so each archive
# action is auditable. Args:
#   $1 = version that triggered the sweep
#   $2 = full UTC timestamp string ("YYYY-MM-DD HH:MM:SS UTC")
#   $@ = "src|dest" move pairs (project-root-relative)
_manifest_archive_append_log_entry() {
    local version="$1"
    local timestamp="$2"
    shift 2
    local -a moves=("$@")

    [[ ${#moves[@]} -gt 0 ]] || return 0

    local archive_dir log_file
    archive_dir="$(get_zarchive_dir)"
    [[ -d "$archive_dir" ]] || return 0
    log_file="${archive_dir}/.archive-log.md"

    if [[ ! -f "$log_file" ]]; then
        cat > "$log_file" <<'EOF'
# Manifest CLI Archive Move Log

Append-only record of archive activity by `manifest ship` and
`manifest docs cleanup`. Each section below records one sweep, newest
at the bottom.

EOF
    fi

    {
        printf '## %s — v%s sweep\n\n' "${timestamp%% *}" "$version"
        printf 'Timestamp: %s\n' "$timestamp"

        local plural=""
        [[ ${#moves[@]} -ne 1 ]] && plural="s"
        printf 'Moved %d file%s:\n' "${#moves[@]}" "$plural"
        local pair src dest
        for pair in "${moves[@]}"; do
            src="${pair%%|*}"
            dest="${pair##*|}"
            printf -- '- %s → %s\n' "$src" "$dest"
        done

        printf '\n'
    } >> "$log_file"
}

# Main cleanup. Sweeps point-in-time audit artifacts (currently
# SECURITY_ANALYSIS_REPORT_v*) out of active docs/ into
# zArchive/v<major>/. Per-version RELEASE/CHANGELOG files are no longer
# generated, so the sweep is usually a no-op for the CLI repo itself.
# Honors MANIFEST_CLI_DOCS_ARCHIVE_FORCE to bypass the uncommitted-edit
# safety check (CI use).
main_cleanup() {
    local version="${1:-}"
    local timestamp="${2:-}"

    if [ -z "$timestamp" ]; then
        get_time_timestamp >/dev/null
        timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    fi

    log_info "Starting repository cleanup..."
    log_info "Version: $version"
    log_info "Timestamp: $timestamp"

    cd "$MANIFEST_CLI_PROJECT_ROOT"

    local zarchive_dir
    zarchive_dir="$(get_zarchive_dir)"

    local moved_count=0 skipped_count=0
    local -a move_entries=()
    if [[ -n "$version" ]]; then
        log_info "Archiving previous version documentation..."
        ensure_zarchive_dir

        local f filename
        while IFS= read -r f; do
            [[ -f "$f" ]] || continue
            filename="$(basename "$f")"
            [[ "$filename" =~ $_MANIFEST_ARCHIVABLE_REGEX ]] || continue

            # Skip the current version's own files.
            if [[ "$filename" == *"v$version"* ]]; then
                skipped_count=$((skipped_count + 1))
                continue
            fi

            # Files land flat in docs/zArchive/ — no per-major v<major>/
            # routing — so the sweep only ever moves, never creates.
            local dest="${zarchive_dir}/${filename}"

            if ! is_truthy "${MANIFEST_CLI_DOCS_ARCHIVE_FORCE:-}"; then
                local porcelain
                porcelain="$(git status --porcelain -- "$f" 2>/dev/null || true)"
                if [[ -n "$porcelain" ]]; then
                    log_error "Refusing to archive ${filename} — file has uncommitted changes:"
                    log_error "  ${porcelain}"
                    log_error "Commit, stash, or set MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 to bypass."
                    return 1
                fi
            fi

            if mv "$f" "$dest" 2>/dev/null; then
                log_success "Moved: ${filename} → zArchive/"
                moved_count=$((moved_count + 1))
                move_entries+=("${f#"$MANIFEST_CLI_PROJECT_ROOT"/}|${dest#"$MANIFEST_CLI_PROJECT_ROOT"/}")
            else
                log_warning "Failed to move: $filename"
            fi
        done < <(find "$(get_docs_folder "$MANIFEST_CLI_PROJECT_ROOT")" -maxdepth 1 -type f -name "*.md")

        log_success "Archived $moved_count files, skipped $skipped_count files"
    fi

    if [[ "$moved_count" -gt 0 ]]; then
        _manifest_archive_append_log_entry "$version" "$timestamp" "${move_entries[@]}"
    fi

    cleanup_temp_files
    cleanup_empty_dirs

    log_success "Repository cleanup completed"
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "archive")
            main_cleanup "${2:-}" "${3:-}"
            ;;
        "clean")
            # For clean command, archive all old documentation files
            local latest_version=""
            if [ -f "$MANIFEST_CLI_PROJECT_ROOT/VERSION" ]; then
                latest_version=$(cat "$MANIFEST_CLI_PROJECT_ROOT/VERSION" 2>/dev/null || echo "")
            fi
            # Get trusted timestamp for cleanup
            get_time_timestamp >/dev/null
            local timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
            main_cleanup "$latest_version" "$timestamp"
            ;;
        "validate")
            validate_repository
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Cleanup Docs Module"
            echo "======================"
            echo ""
            echo "Usage: $0 [command] [version] [timestamp]"
            echo ""
            echo "Commands:"
            echo "  archive [version] [timestamp]  - Archive old documentation and cleanup"
            echo "  clean                          - General cleanup (no archiving)"
            echo "  validate                       - Validate repository state"
            echo "  help                           - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 archive 15.28.0             # Archive docs for version 15.28.0"
            echo "  $0 clean                       # General cleanup"
            echo "  $0 validate                    # Check repository state"
            ;;
        *)
            show_usage_error "$1"
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
