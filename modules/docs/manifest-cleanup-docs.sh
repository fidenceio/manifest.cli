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


# ---------------------------------------------------------------------------
# Temporary-file sweep (TRACKER §3)
#
# This runs as the `archive_sweep` ship step, so it deletes files on every
# release, and until 2026-08-23 it walked the whole project root removing every
# hit for `*.tmp *.temp *.bak *.backup *~ .DS_Store Thumbs.db`. That took out a
# user's *tracked* `notes.bak` and anything matching inside `.git/` — from a
# step whose stated job is documentation cleanup, and which no preview
# mentioned. Three rules now bound it:
#
#   1. `.git` is pruned. Nothing in git's own store is a temporary file; a
#      swept `*.tmp` in there is repository damage, not tidiness.
#   2. A git-TRACKED file is never deleted. A tracked `notes.bak` is content
#      somebody committed on purpose, and the release commit's `git add .`
#      would then record the sweep's deletion as an intended change.
#   3. Patterns a person plausibly authored are scoped to where this module's
#      own generators write. Only unambiguous machine droppings sweep tree-wide.
#
# Skips are reported rather than silent: a caller learns nothing from a step
# that quietly decided not to act.
# ---------------------------------------------------------------------------

# Never user content under any name — safe to sweep anywhere in the work tree.
_MANIFEST_CLI_CLEANUP_TREEWIDE_PATTERNS=(".DS_Store" "Thumbs.db")

# Plausibly hand-authored (an editor backup, a deliberately kept `.bak`).
# Swept only under the docs tree, which is what this module generates into.
_MANIFEST_CLI_CLEANUP_SCOPED_PATTERNS=("*.tmp" "*.temp" "*.bak" "*.backup" "*~")

# Every path git tracks, keyed by repo-relative path.
declare -gA _MANIFEST_CLI_CLEANUP_TRACKED=()

# Load the tracked-file set for $1. Returns non-zero when git cannot answer,
# which the caller must treat as "refuse to delete" — reading an unavailable
# index as "nothing is tracked" is exactly the absent-input-as-a-value shape
# that TRACKER §6 exists to remove.
_manifest_cleanup_load_tracked() {
    local root="$1" path
    _MANIFEST_CLI_CLEANUP_TRACKED=()
    git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    while IFS= read -r -d '' path; do
        [[ -n "$path" ]] && _MANIFEST_CLI_CLEANUP_TRACKED["$path"]=1
    done < <(git -C "$root" ls-files -z 2>/dev/null)
    return 0
}

# find(1) with `.git` pruned, NUL-delimited so a newline in a filename cannot
# split one path into two.
_manifest_cleanup_find() {
    local base="$1" pattern="$2"
    [[ -d "$base" ]] || return 0
    find "$base" -name .git -type d -prune -o -type f -name "$pattern" -print0 2>/dev/null
}

# Physical path of an existing directory (symlinks resolved), or non-zero.
# `cd`+`pwd -P` rather than realpath(1), which is absent on older macOS.
_manifest_cleanup_realdir() {
    ( cd "$1" 2>/dev/null && pwd -P ) || return 1
}

# True when $2 is $1 itself or lives underneath it. Both must already be
# physical paths, or a symlink makes the string compare lie.
_manifest_cleanup_is_inside() {
    local base="$1" candidate="$2"
    [[ "$candidate" == "$base" || "$candidate" == "$base"/* ]]
}

# Sweep temporary files. $1 = "apply" (default, deletes) or "preview" (lists
# only) — preview is what the mutating verbs' plan output calls.
#
# shellcheck disable=SC2120  # "preview" is passed by callers in other files
# (manifest-core.sh's `cleanup`/`docs cleanup` preview arms and
# manifest-refresh.sh's plan output); shellcheck only sees this file.
cleanup_temp_files() {
    local mode="${1:-apply}"
    local root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    # Resolve the root physically, and use that same value for both the find
    # bases and the "${file#$root/}" strip below, so the two can never disagree
    # about where the project starts.
    root="$(_manifest_cleanup_realdir "$root")" || {
        log_warning "Skipping the temporary-file sweep — project root is not a readable directory."
        return 0
    }

    # `docs.folder` is user-settable and gets no path validation at load, so it
    # can point outside the repo ("../elsewhere"). Scoping the sweep to the docs
    # tree therefore has to prove containment first — otherwise a config value
    # steers `rm -f` at a directory the caller never named. Measured: without
    # this, `docs.folder: ../outside` deleted a file outside the project root.
    local docs_dir docs_real=""
    docs_dir="$(get_docs_folder "$root")"
    if [[ -d "$docs_dir" ]]; then
        docs_real="$(_manifest_cleanup_realdir "$docs_dir")" || docs_real=""
        if [[ -n "$docs_real" ]] && ! _manifest_cleanup_is_inside "$root" "$docs_real"; then
            log_warning "Not sweeping the docs folder — it resolves outside the project root:"
            log_warning "  docs.folder → $docs_real"
            docs_real=""
        fi
    fi

    if ! _manifest_cleanup_load_tracked "$root"; then
        log_warning "Skipping the temporary-file sweep — cannot read the git index."
        log_warning "  Without the tracked-file list this step cannot tell a throwaway from committed content."
        return 0
    fi

    local -a candidates=()
    local pattern file
    for pattern in "${_MANIFEST_CLI_CLEANUP_TREEWIDE_PATTERNS[@]}"; do
        while IFS= read -r -d '' file; do
            candidates+=("$file")
        done < <(_manifest_cleanup_find "$root" "$pattern")
    done
    if [[ -n "$docs_real" ]]; then
        for pattern in "${_MANIFEST_CLI_CLEANUP_SCOPED_PATTERNS[@]}"; do
            while IFS= read -r -d '' file; do
                candidates+=("$file")
            done < <(_manifest_cleanup_find "$docs_real" "$pattern")
        done
    fi

    local swept=0 rel
    local -a kept=()
    for file in "${candidates[@]}"; do
        [[ -f "$file" ]] || continue
        rel="${file#"$root"/}"
        # If the path did not reduce to a repo-relative one, the tracked-file
        # lookup cannot be trusted, so refuse rather than delete on a miss.
        if [[ "$rel" == /* ]]; then
            log_warning "Not sweeping $file — cannot place it inside the project root."
            continue
        fi
        if [[ -n "${_MANIFEST_CLI_CLEANUP_TRACKED[$rel]+set}" ]]; then
            kept+=("$rel")
            continue
        fi
        if [[ "$mode" == "preview" ]]; then
            echo "  • $rel"
            swept=$((swept + 1))
            continue
        fi
        if rm -f "$file"; then
            swept=$((swept + 1))
        else
            log_warning "Could not remove $rel"
        fi
    done

    if [[ "$mode" == "preview" ]]; then
        [[ $swept -eq 0 ]] && echo "  • (none)"
    elif [[ $swept -gt 0 ]]; then
        log_success "Cleaned up $swept temporary files"
    else
        log_info "No temporary files found"
    fi

    if [[ ${#kept[@]} -gt 0 ]]; then
        # Tense-neutral: this line prints in both preview and apply, and "left"
        # would read as past tense in a plan that has not run yet.
        log_info "Keeping ${#kept[@]} tracked file(s) (committed content, not temporary):"
        for rel in "${kept[@]}"; do
            log_info "  $rel"
        done
    fi
}

# Clean up empty directories. `.git` is pruned for the same reason as the file
# sweep above: the old exact-match guard skipped `$root/.git` itself while
# happily removing `.git/refs/tags` and its siblings.
cleanup_empty_dirs() {
    log_info "Cleaning up empty directories..."

    local root="${MANIFEST_CLI_PROJECT_ROOT:-$PWD}"
    local cleaned_count=0 dir

    while IFS= read -r -d '' dir; do
        [[ -d "$dir" ]] || continue
        [[ "$dir" == "$root" ]] && continue
        [[ -z "$(ls -A "$dir" 2>/dev/null)" ]] || continue
        rmdir "$dir" 2>/dev/null && cleaned_count=$((cleaned_count + 1))
    done < <(find "$root" -name .git -type d -prune -o -type d -empty -print0 2>/dev/null)

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
# The version segment comes from _MANIFEST_CLI_VERSION_ERE (manifest-shared-utils.sh,
# always sourced first) so a report stamped with a revision version — the
# generator interpolates the live VERSION verbatim — is still archivable.
_MANIFEST_ARCHIVABLE_REGEX='^SECURITY_ANALYSIS_REPORT_v'"${_MANIFEST_CLI_VERSION_ERE}"'(_[0-9]+T[0-9]+Z)?\.md$'

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
