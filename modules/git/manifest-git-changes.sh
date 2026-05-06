#!/bin/bash

# Manifest Git Changes Module
# Handles git change analysis and categorization

# Git changes module - uses PROJECT_ROOT from core module
MANIFEST_GIT_CHANGES_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$MANIFEST_GIT_CHANGES_SCRIPT_DIR/manifest-doc-review.sh"

# Commits Manifest CLI writes during its own pipeline. Filter these from
# generated changelogs so Manifest's bookkeeping never pollutes user docs.
MANIFEST_COMMIT_NOISE_REGEX='^- (Auto-commit (before Manifest process|changes)|Bump version to |Update Homebrew formula to |Update formula to |Update main CHANGELOG\.md to |Update CHANGELOG\.md to |Refresh docs and metadata for )'

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

    git log --oneline --pretty=format:"- %s" ${range:+"$range"} 2>/dev/null \
        | grep -E -v "$MANIFEST_COMMIT_NOISE_REGEX" || true
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
