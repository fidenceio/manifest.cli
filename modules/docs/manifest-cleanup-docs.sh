#!/bin/bash

# Manifest Cleanup Docs Module
# Handles moving old documentation to zArchive and general repository cleanup

# Cleanup-docs module - uses PROJECT_ROOT from core module

# Get configurable documentation paths
get_zarchive_dir() {
    get_docs_archive_folder "$PROJECT_ROOT"
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
        done < <(find "$PROJECT_ROOT" -name "$pattern" -type f 2>/dev/null || true)
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
        if [[ -d "$dir" && "$dir" != "$PROJECT_ROOT" && "$dir" != "$PROJECT_ROOT/.git" ]]; then
            if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                rmdir "$dir" 2>/dev/null && cleaned_count=$((cleaned_count + 1))
            fi
        fi
    done < <(find "$PROJECT_ROOT" -type d -empty 2>/dev/null || true)
    
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
# basename so similar-prefixed hand-authored docs (e.g.,
# RELEASE_RUN_HANDOFF_v46.7.0.md) are not swept up.
_MANIFEST_ARCHIVABLE_REGEX='^(RELEASE|CHANGELOG|SECURITY_ANALYSIS_REPORT)_v[0-9]+\.[0-9]+\.[0-9]+(_[0-9]+T[0-9]+Z)?\.md$'

# --- Archive index helpers -------------------------------------------------
#
# These regenerate docs/zArchive/INDEX.md (top-level) and
# docs/zArchive/v<major>/INDEX.md (per-major) after every archive sweep,
# so the indexes never drift from the file layout.

_manifest_archive_extract_date() {
    awk '
      /^\*\*Release Date:\*\* / { sub(/^\*\*Release Date:\*\* /, ""); print substr($0, 1, 10); exit }
      /^Release date: / { sub(/^Release date: */, ""); print substr($0, 1, 10); exit }
      /^\*\*Date:\*\* / { sub(/^\*\*Date:\*\* /, ""); print substr($0, 1, 10); exit }
    ' "$1"
}

_manifest_archive_extract_version_from_filename() {
    basename "$1" | sed -E 's/^[A-Z_]+_v([0-9]+\.[0-9]+\.[0-9]+).*\.md$/\1/'
}

_manifest_archive_extract_type() {
    case "$1" in
        RELEASE_v*) printf '%s\n' "Release Notes" ;;
        CHANGELOG_v*) printf '%s\n' "Changelog" ;;
        SECURITY_ANALYSIS_REPORT*) printf '%s\n' "Security Audit" ;;
        *) printf '%s\n' "Document" ;;
    esac
}

_manifest_archive_sort_key() {
    local f="$1"
    local v t tnum maj min pat
    v="$(_manifest_archive_extract_version_from_filename "$f")"
    t="$(_manifest_archive_extract_type "$(basename "$f")")"
    case "$t" in
        "Release Notes") tnum=1 ;;
        "Changelog") tnum=2 ;;
        "Security Audit") tnum=3 ;;
        *) tnum=4 ;;
    esac
    IFS='.' read -r maj min pat <<<"$v"
    printf '%05d.%05d.%05d.%d\n' "${maj:-0}" "${min:-0}" "${pat:-0}" "$tnum"
}

_manifest_archive_generate_per_major_index() {
    local archive_dir="$1"
    local major="$2"
    local dir="$archive_dir/v${major}"
    [[ -d "$dir" ]] || return 0

    local index_file="$dir/INDEX.md"
    local count=0
    local rows=""
    local f

    for f in "$dir"/*.md; do
        [[ -f "$f" ]] || continue
        [[ "$(basename "$f")" == "INDEX.md" ]] && continue
        count=$((count + 1))
        rows="${rows}$(_manifest_archive_sort_key "$f")|${f}"$'\n'
    done

    if [[ "$count" -eq 0 ]]; then
        rm -f "$index_file"
        rmdir "$dir" 2>/dev/null || true
        return 0
    fi

    {
        echo "# Manifest CLI Archive — v${major}"
        echo
        local plural=""
        [[ "$count" -ne 1 ]] && plural="s"
        echo "${count} archived document${plural} from the v${major} series."
        echo
        echo "| Document | Version | Date |"
        echo "| --- | --- | --- |"
        printf '%s' "$rows" | sort | while IFS='|' read -r _key f; do
            [[ -z "$f" ]] && continue
            local base v t d_str
            base="$(basename "$f")"
            v="$(_manifest_archive_extract_version_from_filename "$f")"
            t="$(_manifest_archive_extract_type "$base")"
            d_str="$(_manifest_archive_extract_date "$f")"
            echo "| [${t} v${v}](${base}) | ${v} | ${d_str:-—} |"
        done
        echo
        echo "[Back to archive index](../INDEX.md)"
    } > "$index_file"
}

_manifest_archive_generate_top_level_index() {
    local archive_dir="$1"
    local index_file="$archive_dir/INDEX.md"

    {
        cat <<'INTRO'
# Manifest CLI Archive

Historical release notes, changelogs, and security audits from past versions.

This archive contains documents that were promoted out of the active `docs/`
directory when superseded by a newer release. Files are grouped by major
version. Boilerplate auto-generated stubs (releases with no substantive
content) have been pruned; only documents describing real changes or
representing point-in-time security analyses are retained.

| Major | Documents | Date range | Notes |
| --- | --- | --- | --- |
INTRO

        local total_docs=0
        local total_majors=0
        local d
        for d in "$archive_dir"/v*/; do
            [[ -d "$d" ]] || continue
            local major count min_date max_date types
            major="$(basename "$d" | tr -d v)"
            count=0
            min_date=""
            max_date=""
            types=""

            local f d_str
            for f in "$d"*.md; do
                [[ -f "$f" ]] || continue
                [[ "$(basename "$f")" == "INDEX.md" ]] && continue
                count=$((count + 1))
                total_docs=$((total_docs + 1))
                d_str="$(_manifest_archive_extract_date "$f")"
                if [[ -z "$min_date" || "$d_str" < "$min_date" ]]; then min_date="$d_str"; fi
                if [[ -z "$max_date" || "$d_str" > "$max_date" ]]; then max_date="$d_str"; fi
                case "$(basename "$f")" in
                    RELEASE_v*|CHANGELOG_v*) [[ "$types" == *release* ]] || types="${types}release " ;;
                    SECURITY_ANALYSIS_REPORT*) [[ "$types" == *security* ]] || types="${types}security " ;;
                esac
            done

            [[ "$count" -gt 0 ]] || continue
            total_majors=$((total_majors + 1))

            local range
            if [[ "$min_date" == "$max_date" ]]; then
                range="${min_date:-—}"
            else
                range="${min_date} – ${max_date}"
            fi

            local label=""
            case "$types" in
                *release*\ *security*\ |*release*\ *security*) label="Release docs + security audit" ;;
                *release*\ ) label="Release docs" ;;
                *security*\ ) label="Security audit$([ "$count" = 1 ] || echo "s")" ;;
            esac
            echo "| [v${major}](v${major}/INDEX.md) | ${count} | ${range} | ${label} |"
        done
        echo
        echo "**Total:** ${total_docs} documents across ${total_majors} major versions."
        echo
        echo "[Back to current docs](../INDEX.md)"
    } > "$index_file"
}

_manifest_archive_regenerate_indexes() {
    local archive_dir
    archive_dir="$(get_zarchive_dir)"
    [[ -d "$archive_dir" ]] || return 0

    local d major
    for d in "$archive_dir"/v*/; do
        [[ -d "$d" ]] || continue
        major="$(basename "$d" | tr -d v)"
        _manifest_archive_generate_per_major_index "$archive_dir" "$major"
    done

    _manifest_archive_generate_top_level_index "$archive_dir"
}

# Append a sweep entry to docs/zArchive/.archive-log.md so each archive
# action is auditable. Args:
#   $1 = version that triggered the sweep
#   $2 = full UTC timestamp string ("YYYY-MM-DD HH:MM:SS UTC")
#   $3 = retain spec
#   $4 = number of move entries that follow
#   $@ = first $4 args are "src|dest" move pairs, remaining are pruned-file paths
#        (all project-root-relative)
_manifest_archive_append_log_entry() {
    local version="$1"
    local timestamp="$2"
    local retain="$3"
    local move_count="$4"
    shift 4

    local -a moves=() prunes=()
    local i=0
    while [[ "$i" -lt "$move_count" ]]; do
        moves+=("$1"); shift; i=$((i+1))
    done
    prunes=("$@")

    local total=$(( ${#moves[@]} + ${#prunes[@]} ))
    [[ "$total" -gt 0 ]] || return 0

    local archive_dir log_file
    archive_dir="$(get_zarchive_dir)"
    [[ -d "$archive_dir" ]] || return 0
    log_file="${archive_dir}/.archive-log.md"

    if [[ ! -f "$log_file" ]]; then
        cat > "$log_file" <<'EOF'
# Manifest CLI Archive Move Log

Append-only record of archive activity by `manifest ship` and
`manifest docs cleanup`. Each section below records one sweep, newest
at the bottom. Moves come from the active-docs sweep; prunes come
from the `docs.retain` retention policy.

EOF
    fi

    {
        printf '## %s — v%s sweep\n\n' "${timestamp%% *}" "$version"
        printf 'Timestamp: %s\n' "$timestamp"
        [[ -n "$retain" ]] && printf 'Retain: %s\n' "$retain"

        if [[ ${#moves[@]} -gt 0 ]]; then
            local plural=""
            [[ ${#moves[@]} -ne 1 ]] && plural="s"
            printf 'Moved %d file%s:\n' "${#moves[@]}" "$plural"
            local pair src dest
            for pair in "${moves[@]}"; do
                src="${pair%%|*}"
                dest="${pair##*|}"
                printf -- '- %s → %s\n' "$src" "$dest"
            done
        fi

        if [[ ${#prunes[@]} -gt 0 ]]; then
            local plural=""
            [[ ${#prunes[@]} -ne 1 ]] && plural="s"
            printf 'Pruned %d file%s (over retention cap):\n' "${#prunes[@]}" "$plural"
            local p
            for p in "${prunes[@]}"; do
                printf -- '- %s\n' "$p"
            done
        fi

        printf '\n'
    } >> "$log_file"
}

# Parse a docs.retain spec into kind and value.
#   "N versions" → kind=versions, value=N
#   "N days"     → kind=days, value=N
#   "off" or ""  → kind=off, value=0
# Returns 0 on success, 1 on malformed input. Output written to the named
# variables in $2 (kind) and $3 (value).
_manifest_parse_retention() {
    local raw="$1"
    local _outkind="$2"
    local _outval="$3"

    raw="$(printf '%s' "$raw" | tr -s '[:space:]' ' ')"
    raw="${raw# }"; raw="${raw% }"

    if [[ -z "$raw" || "$raw" == "off" ]]; then
        printf -v "$_outkind" '%s' "off"
        printf -v "$_outval" '%s' "0"
        return 0
    fi

    local num="${raw%% *}"
    local unit="${raw#* }"
    [[ "$num" =~ ^[0-9]+$ ]] || return 1

    case "$unit" in
        version|versions)
            printf -v "$_outkind" '%s' "versions"
            printf -v "$_outval" '%s' "$num"
            ;;
        day|days)
            printf -v "$_outkind" '%s' "days"
            printf -v "$_outval" '%s' "$num"
            ;;
        *)
            return 1
            ;;
    esac
}

# Main cleanup function. Two-phase archive maintenance:
#   Phase A — sweep: move every previous-version file out of active docs/
#             into zArchive/v<major>/. Always runs (no config); active docs/
#             holds at most one version's docs at a time.
#   Phase B — prune: enforce docs.retain on the archive itself by deleting
#             RELEASE/CHANGELOG files whose version is older than the cap.
#             SECURITY_ANALYSIS_REPORT_v* files are excluded — those are
#             point-in-time audit artifacts, not release docs.
# Both phases honor MANIFEST_CLI_DOCS_ARCHIVE_FORCE for the uncommitted-edit
# safety guard.
main_cleanup() {
    local version="${1:-}"
    local timestamp="${2:-}"

    if [ -z "$timestamp" ]; then
        get_time_timestamp >/dev/null
        timestamp=$(format_timestamp "$MANIFEST_CLI_TIME_TIMESTAMP" '+%Y-%m-%d %H:%M:%S UTC')
    fi

    local retain_spec="${MANIFEST_CLI_DOCS_RETAIN:-10 versions}"
    local retain_kind retain_value
    if ! _manifest_parse_retention "$retain_spec" retain_kind retain_value; then
        log_error "Invalid docs.retain spec: '${retain_spec}' (expected 'N versions', 'N days', or 'off')"
        return 1
    fi

    log_info "Starting repository cleanup..."
    log_info "Version: $version"
    log_info "Timestamp: $timestamp"

    cd "$PROJECT_ROOT"

    local zarchive_dir
    zarchive_dir="$(get_zarchive_dir)"

    # ---- Phase A: active-docs sweep ----------------------------------------
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

            local file_major
            file_major="$(printf '%s' "$filename" | sed -E 's/^[A-Z_]+_v([0-9]+)\..*/\1/')"
            local target_dir="${zarchive_dir}/v${file_major}"
            mkdir -p "$target_dir"
            local dest="${target_dir}/${filename}"

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
                log_success "Moved: ${filename} → v${file_major}/"
                moved_count=$((moved_count + 1))
                move_entries+=("${f#"$PROJECT_ROOT"/}|${dest#"$PROJECT_ROOT"/}")
            else
                log_warning "Failed to move: $filename"
            fi
        done < <(find "$(get_docs_folder "$PROJECT_ROOT")" -maxdepth 1 -type f -name "*.md")

        log_success "Archived $moved_count files, skipped $skipped_count files"
    fi

    # ---- Phase B: archive retention prune ----------------------------------
    local pruned_count=0
    local -a prune_entries=()
    if [[ "$retain_kind" != "off" && -d "$zarchive_dir" ]]; then
        log_info "Enforcing archive retention (retain=${retain_spec})..."

        local -a archived_files=() archived_versions=()
        local af bn av
        while IFS= read -r af; do
            [[ -f "$af" ]] || continue
            bn="$(basename "$af")"
            # Only RELEASE_v* and CHANGELOG_v* are subject to retention;
            # SECURITY_ANALYSIS_REPORT_v* files are point-in-time audits
            # and stay in the archive indefinitely.
            [[ "$bn" =~ ^(RELEASE|CHANGELOG)_v[0-9]+\.[0-9]+\.[0-9]+\.md$ ]] || continue
            av="$(printf '%s' "$bn" | sed -nE 's/^[A-Z]+_v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
            [[ -n "$av" ]] || continue
            archived_files+=("$af")
            archived_versions+=("$av")
        done < <(find "$zarchive_dir" -mindepth 2 -maxdepth 2 -type f -name "*.md" 2>/dev/null)

        local -a to_prune=()
        local i
        case "$retain_kind" in
            versions)
                local kept_versions=""
                if [[ ${#archived_versions[@]} -gt 0 ]]; then
                    kept_versions="$(printf '%s\n' "${archived_versions[@]}" | sort -u -V -r | head -n "$retain_value")"
                fi
                local v
                for v in "${archived_versions[@]}"; do
                    if grep -qFx "$v" <<< "$kept_versions"; then
                        to_prune+=(0)
                    else
                        to_prune+=(1)
                    fi
                done
                ;;
            days)
                local c
                for c in "${archived_files[@]}"; do
                    if [[ -n "$(find "$c" -maxdepth 0 -mtime "+${retain_value}" 2>/dev/null)" ]]; then
                        to_prune+=(1)
                    else
                        to_prune+=(0)
                    fi
                done
                ;;
        esac

        for ((i=0; i<${#archived_files[@]}; i++)); do
            [[ "${to_prune[i]}" -eq 1 ]] || continue
            local af="${archived_files[i]}"
            local bn
            bn="$(basename "$af")"

            # Pre-delete safety: refuse to delete a file with uncommitted
            # *edits* (the user's hand-edit they haven't committed yet).
            # Untracked files are excluded — those include the entries
            # Phase A just moved into the archive in this same run, which
            # are transient and safe to prune. Same FORCE bypass as Phase A.
            if ! is_truthy "${MANIFEST_CLI_DOCS_ARCHIVE_FORCE:-}"; then
                local porcelain
                porcelain="$(git status --porcelain -- "$af" 2>/dev/null | grep -vE '^\?\?' || true)"
                if [[ -n "$porcelain" ]]; then
                    log_error "Refusing to prune ${bn} — file has uncommitted changes:"
                    log_error "  ${porcelain}"
                    log_error "Commit, revert, or set MANIFEST_CLI_DOCS_ARCHIVE_FORCE=1 to bypass."
                    return 1
                fi
            fi

            if rm -f "$af"; then
                log_success "Pruned: ${af#"$PROJECT_ROOT"/}"
                pruned_count=$((pruned_count + 1))
                prune_entries+=("${af#"$PROJECT_ROOT"/}")
            else
                log_warning "Failed to prune: $bn"
            fi
        done

        if [[ "$pruned_count" -gt 0 ]]; then
            log_success "Pruned $pruned_count files from archive"
        fi
    fi

    # ---- Append a single log entry covering both phases --------------------
    if [[ "$moved_count" -gt 0 || "$pruned_count" -gt 0 ]]; then
        _manifest_archive_append_log_entry "$version" "$timestamp" "$retain_spec" "$moved_count" "${move_entries[@]}" "${prune_entries[@]}"
    fi

    # Regenerate the archive indexes (idempotent rebuild from file state).
    if [[ "$moved_count" -gt 0 || "$pruned_count" -gt 0 ]] || [[ -d "$zarchive_dir" ]]; then
        _manifest_archive_regenerate_indexes
    fi

    # Clean up temporary files
    cleanup_temp_files

    # Clean up empty directories
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
            if [ -f "$PROJECT_ROOT/VERSION" ]; then
                latest_version=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "")
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
