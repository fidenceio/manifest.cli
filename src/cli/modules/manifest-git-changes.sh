#!/bin/bash

# Manifest Git Changes Module
# Handles git change analysis and categorization

# Git changes module - uses PROJECT_ROOT from core module

# Get git changes since last tag
get_git_changes() {
    local version="$1"
    local last_tag=""
    
    # Get the last tag
    last_tag=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    
    if [[ -n "$last_tag" ]]; then
        log_info "Getting changes since $last_tag"
        git log --oneline --pretty=format:"- %s" "$last_tag..HEAD" 2>/dev/null || true
    else
        log_info "No previous tags found, getting all changes"
        git log --oneline --pretty=format:"- %s" 2>/dev/null || true
    fi
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
    
    # Analyze git changes
    while IFS= read -r line; do
        local change="${line#- }"
        
        # Categorize changes based on keywords
        case "$change" in
            *"feat"*|*"feature"*|*"add"*|*"new"*)
                new_features+=("$change")
                ;;
            *"fix"*|*"bug"*|*"issue"*)
                bug_fixes+=("$change")
                ;;
            *"break"*|*"BREAKING"*)
                breaking_changes+=("$change")
                ;;
            *"docs"*|*"documentation"*|*"readme"*)
                documentation+=("$change")
                ;;
            *"refactor"*|*"improve"*|*"optimize"*|*"enhance"*)
                improvements+=("$change")
                ;;
            *)
                improvements+=("$change")
                ;;
        esac
    done < "$changes_file"
    
    # Write analysis to file
    cat > "$changes_file" << EOF
# Change Analysis for v$version

## New Features
$(printf '%s\n' "${new_features[@]:-}")

## Improvements
$(printf '%s\n' "${improvements[@]:-}")

## Bug Fixes
$(printf '%s\n' "${bug_fixes[@]:-}")

## Breaking Changes
$(printf '%s\n' "${breaking_changes[@]:-}")

## Documentation
$(printf '%s\n' "${documentation[@]:-}")
EOF
    
    log_success "Change analysis completed"
    log_info "New features: ${#new_features[@]:-0}"
    log_info "Improvements: ${#improvements[@]:-0}"
    log_info "Bug fixes: ${#bug_fixes[@]:-0}"
    log_info "Breaking changes: ${#breaking_changes[@]:-0}"
    log_info "Documentation: ${#documentation[@]:-0}"
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
