#!/bin/bash

# Manifest Git Changes Module
# Handles git change analysis and categorization

# Git changes module - uses PROJECT_ROOT from core module
MANIFEST_CLI_GIT_CHANGES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MANIFEST_CLI_GIT_CHANGES_SCRIPT_DIR/manifest-doc-review.sh"

# Commits Manifest CLI writes during its own pipeline. Filter pure bookkeeping
# from generated changelogs so Manifest's release mechanics never pollute user
# docs. Auto-commit subjects are handled separately because those commits often
# contain the user's real work under a generic Manifest-generated subject.
MANIFEST_CLI_COMMIT_NOISE_SUBJECT_REGEX='^(Bump version to |Update Homebrew formula to |Update formula to |Update main CHANGELOG\.md to |Update CHANGELOG\.md to |Refresh docs and metadata for )'

_manifest_git_changes_file_list_for_commit() {
    local commit="$1"
    git show --format= --name-only "$commit" 2>/dev/null | sed '/^[[:space:]]*$/d'
}

_manifest_git_changes_files_match() {
    local files="$1"
    local pattern="$2"
    printf '%s\n' "$files" | grep -Eq "$pattern"
}

_manifest_git_changes_emit_once() {
    local bullet="$1"
    local seen_var="$2"
    local seen="${!seen_var:-}"

    case "
$seen
" in
        *"
$bullet
"*) return 0 ;;
    esac

    printf -- '- %s\n' "$bullet"
    printf -v "$seen_var" '%s%s\n' "$seen" "$bullet"
}

# Compact dirty-tree summary for the fleet ship plan column. Echoes an
# empty string when the work tree is clean (or only formula/manifest.rb is
# dirty — that file is touched intentionally by ship and is filtered the
# same way auto-commit detection does in manifest-orchestrator.sh). When
# dirty, echoes "Nm+Nu" where N counts modified/staged vs untracked
# entries. Always returns 0; missing or non-git paths produce empty output.
manifest_git_changes_dirty_summary() {
    local path="$1"
    [ -n "$path" ] || return 0
    [ -d "$path/.git" ] || [ -f "$path/.git" ] || return 0

    local porcelain modified untracked
    porcelain=$(git -C "$path" status --porcelain 2>/dev/null \
        | awk '$2 != "formula/manifest.rb" && NF > 0 { print }')
    [ -n "$porcelain" ] || return 0

    # grep -c exits 1 on zero matches, which would propagate through $().
    # Pipe through `|| true` so the substitution always gets a clean count.
    modified=$({ printf '%s\n' "$porcelain" | grep -cv '^??'; } 2>/dev/null || true)
    untracked=$({ printf '%s\n' "$porcelain" | grep -c '^??'; } 2>/dev/null || true)
    : "${modified:=0}" "${untracked:=0}"
    printf '%dm+%du' "$modified" "$untracked"
}

manifest_git_changes_bullets_for_files() {
    local files="$1"
    local emitted=""
    local github_release_changed=false
    [[ -n "$files" ]] || return 0

    if _manifest_git_changes_files_match "$files" '(^|/)modules/workflow/manifest-orchestrator\.sh$|(^|/)modules/core/manifest-yaml\.sh$|(^|/)modules/core/manifest-config\.sh$'; then
        github_release_changed=true
        _manifest_git_changes_emit_once "Add GitHub Release publishing support" emitted
    fi
    if _manifest_git_changes_files_match "$files" '(^|/)modules/core/manifest-ship\.sh$'; then
        _manifest_git_changes_emit_once "Add smart ship preview summaries" emitted
    fi
    if _manifest_git_changes_files_match "$files" '(^|/)docs/|(^|/)README\.md$|(^|/)examples/'; then
        _manifest_git_changes_emit_once "Update release copy and configuration examples" emitted
    fi
    if [[ "$github_release_changed" != "true" ]] && _manifest_git_changes_files_match "$files" '(^|/)modules/recipe/|(^|/)recipes/builtin/|(^|/)docs/contracts/recipe\.schema\.json$'; then
        _manifest_git_changes_emit_once "Add recipe-backed workflow definitions and recipe introspection support" emitted
    fi
    if _manifest_git_changes_files_match "$files" '(^|/)modules/core/manifest-core\.sh$'; then
        _manifest_git_changes_emit_once "Wire first-class CLI commands to inspectable built-in recipe definitions" emitted
    fi
    if _manifest_git_changes_files_match "$files" '(^|/)completions/'; then
        _manifest_git_changes_emit_once "Update shell completions for new command options" emitted
    fi
    if _manifest_git_changes_files_match "$files" '(^|/)scripts/run-tests-container\.sh$'; then
        _manifest_git_changes_emit_once "Add a containerized test runner for Manifest CLI" emitted
    fi
    if _manifest_git_changes_files_match "$files" '(^|/)tests/'; then
        _manifest_git_changes_emit_once "Add regression coverage for the changed CLI workflow" emitted
    fi
    if _manifest_git_changes_files_match "$files" '^CHANGELOG\.md$'; then
        _manifest_git_changes_emit_once "Backfill and clarify release history in the root changelog" emitted
    fi
    if [[ -z "$emitted" ]]; then
        local count noun
        count="$(printf '%s\n' "$files" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
        if [[ "$count" == "1" ]]; then
            noun="file"
        else
            noun="files"
        fi
        _manifest_git_changes_emit_once "Update ${count:-multiple} $noun before release" emitted
    fi
}

_manifest_git_changes_auto_commit_bullets() {
    local commit="$1"
    local files
    files="$(_manifest_git_changes_file_list_for_commit "$commit")"
    manifest_git_changes_bullets_for_files "$files"
}

# Get git changes since last tag
get_git_changes() {
    local version="$1"
    local last_tag=""
    local range=""

    # Get the previous tag (not the current one)
    last_tag=$(git describe --tags --abbrev=0 HEAD~1 2>/dev/null || echo "")

    if [[ -n "$last_tag" ]]; then
        log_info "Getting changes since $last_tag" >&2
        range="$last_tag..HEAD"
    else
        log_info "No previous tags found, getting all changes" >&2
    fi

    local commit subject
    while IFS= read -r commit; do
        [[ -n "$commit" ]] || continue
        subject="$(git log -1 --pretty=%s "$commit" 2>/dev/null || true)"
        [[ -n "$subject" ]] || continue

        case "$subject" in
            Auto-commit\ before\ Manifest\ process*|Auto-commit\ changes*)
                _manifest_git_changes_auto_commit_bullets "$commit"
                ;;
            *)
                if [[ "$subject" =~ $MANIFEST_CLI_COMMIT_NOISE_SUBJECT_REGEX ]]; then
                    continue
                fi
                printf -- '- %s\n' "$subject"
                ;;
        esac
    done < <(git log --reverse --format='%H' ${range:+"$range"} 2>/dev/null || true)
    manifest_doc_review_release_notes_since "$range" || true
    echo  # Add final newline
}

# Analyze raw git changes into a single-section narrative body. The output
# overwrites changes_file with `## Highlights for v<version>` followed by a
# `### Changes` section listing one bullet per surviving commit subject. When
# no bullets survive, only the highlights header is emitted; the empty-body
# fallback in _manifest_build_changelog_entry takes over from there.
analyze_changes() {
    local version="$1"
    local changes_file="$2"

    log_info "Analyzing code changes for version $version..."

    local bullets=()

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" == "#"* ]] && continue
        [[ "$line" == "## "* ]] && continue
        local change="${line#- }"
        change="${change#"${change%%[![:space:]]*}"}"
        change="${change%"${change##*[![:space:]]}"}"
        [[ -n "$change" ]] || continue

        # Strip a single trailing period so bullets read like the
        # hand-curated gold-standard entries (no period on simple imperatives).
        change="${change%.}"

        # Capitalize a lowercase ASCII first letter so subjects coming from
        # `git log` in lowercase still render consistently.
        local first="${change:0:1}"
        case "$first" in
            [a-z])
                change="$(printf '%s' "$first" | tr '[:lower:]' '[:upper:]')${change:1}"
                ;;
        esac

        bullets+=("- $change")
    done < "$changes_file"

    {
        printf '## Highlights for v%s\n' "$version"
        if [[ "${#bullets[@]}" -gt 0 ]]; then
            printf '\n### Changes\n\n'
            printf '%s\n' "${bullets[@]}"
        fi
    } > "$changes_file"

    log_success "Change analysis completed"
    log_info "Bullets: ${#bullets[@]}"
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "get")
            local version="${2:-}"
            if [[ -z "$version" ]]; then
                show_required_arg_error "Version" "get <version>"
            fi
            get_git_changes "$version"
            ;;
        "analyze")
            local version="${2:-}"
            local changes_file="${3:-}"
            if [[ -z "$version" || -z "$changes_file" ]]; then
                show_required_arg_error "Version and changes file" "analyze <version> <changes_file>"
            fi
            analyze_changes "$version" "$changes_file"
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Git Changes Module"
            echo "=========================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  get <version>                    - Get git changes since last tag"
            echo "  analyze <version> <file>         - Analyze and categorize changes"
            echo "  help                             - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 get 15.28.0"
            echo "  $0 analyze 15.28.0 /tmp/changes.md"
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
