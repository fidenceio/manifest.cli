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

# Analyze code changes and categorize them
analyze_changes() {
    local version="$1"
    local changes_file="$2"
    
    log_info "Analyzing code changes for version $version..."
    
    local new_features=()
    local improvements=()
    local bug_fixes=()
    local breaking_changes=()
    local documentation=()
    local total_changes=0

    _manifest_add_change_item() {
        local _array_name="$1"
        local _item="$2"
        local -n _array_ref="$_array_name"
        _array_ref+=("- $_item")
    }
    
    # Analyze git changes
    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        [[ "$line" == "#"* ]] && continue
        [[ "$line" == "## "* ]] && continue
        local change="${line#- }"
        change="${change#"${change%%[![:space:]]*}"}"
        change="${change%"${change##*[![:space:]]}"}"
        [[ -n "$change" ]] || continue

        total_changes=$((total_changes + 1))
        local change_lc
        change_lc="$(printf '%s' "$change" | tr '[:upper:]' '[:lower:]')"
        
        # Categorize changes based on keywords
        case "$change_lc" in
            *"breaking"*|*"break:"*|*"!:"*)
                _manifest_add_change_item breaking_changes "$change"
                ;;
            *"fix"*|*"bug"*|*"issue"*|*"repair"*|*"correct"*)
                _manifest_add_change_item bug_fixes "$change"
                ;;
            *"doc"*|*"documentation"*|*"readme"*|*"changelog"*|*"release note"*)
                _manifest_add_change_item documentation "$change"
                ;;
            *"feat"*|*"feature"*|*"add"*|*"new"*|*"introduce"*|*"support"*)
                _manifest_add_change_item new_features "$change"
                ;;
            *"refactor"*|*"improve"*|*"optimize"*|*"enhance"*|*"update"*|*"cleanup"*|*"harden"*)
                _manifest_add_change_item improvements "$change"
                ;;
            *)
                _manifest_add_change_item improvements "$change"
                ;;
        esac
    done < "$changes_file"
    
    # Write analysis to file
    {
        cat << EOF
## Highlights for v$version

### Summary
EOF

        if [[ "$total_changes" -eq 0 ]]; then
            cat << EOF
No notable user-facing changes were detected since the previous release tag. Only release automation or filtered bookkeeping commits were present.
EOF
        else
            cat << EOF
- Notable changes: $total_changes
- New features: ${#new_features[@]}
- Improvements: ${#improvements[@]}
- Bug fixes: ${#bug_fixes[@]}
- Breaking changes: ${#breaking_changes[@]}
- Documentation updates: ${#documentation[@]}
EOF
        fi

        if [[ "${#breaking_changes[@]}" -gt 0 ]]; then
            printf '\n### Breaking Changes\n'
            printf '%s\n' "${breaking_changes[@]}"
        fi
        if [[ "${#new_features[@]}" -gt 0 ]]; then
            printf '\n### New Features\n'
            printf '%s\n' "${new_features[@]}"
        fi
        if [[ "${#improvements[@]}" -gt 0 ]]; then
            printf '\n### Improvements\n'
            printf '%s\n' "${improvements[@]}"
        fi
        if [[ "${#bug_fixes[@]}" -gt 0 ]]; then
            printf '\n### Bug Fixes\n'
            printf '%s\n' "${bug_fixes[@]}"
        fi
        if [[ "${#documentation[@]}" -gt 0 ]]; then
            printf '\n### Documentation\n'
            printf '%s\n' "${documentation[@]}"
        fi
    } > "$changes_file"

    if [[ "$total_changes" -eq 0 ]]; then
        log_success "Change analysis completed"
        log_info "No notable changes found"
        return 0
    fi

    log_success "Change analysis completed"
    log_info "New features: ${#new_features[@]}"
    log_info "Improvements: ${#improvements[@]}"
    log_info "Bug fixes: ${#bug_fixes[@]}"
    log_info "Breaking changes: ${#breaking_changes[@]}"
    log_info "Documentation: ${#documentation[@]}"
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
