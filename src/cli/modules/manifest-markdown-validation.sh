#!/bin/bash

# Manifest Markdown Validation Module
# Provides comprehensive markdown validation and cleaning

# Get the project root (three levels up from modules)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Markdown validation helper
validate_markdown_syntax() {
    local content="$1"
    local errors=0
    
    # Check for proper heading hierarchy
    local prev_level=0
    while IFS= read -r line; do
        if [[ $line =~ ^(#+)[[:space:]] ]]; then
            local current_level=${#BASH_REMATCH[1]}
            if [ $current_level -gt $((prev_level + 1)) ]; then
                log_error "Heading level skipped: $line"
                errors=$((errors + 1))
            fi
            prev_level=$current_level
        fi
    done <<< "$content"
    
    # Check for multiple consecutive blank lines
    if echo "$content" | awk '/^$/{if(prev_empty){print "found"; exit} prev_empty=1; next} {prev_empty=0} END{exit 0}' | grep -q "found"; then
        log_error "Multiple consecutive blank lines found"
        errors=$((errors + 1))
    fi
    
    # Check for trailing whitespace
    if echo "$content" | grep -q "[[:space:]]$"; then
        log_error "Trailing whitespace found"
        errors=$((errors + 1))
    fi
    
    return $errors
}

# Clean markdown content
clean_markdown() {
    local content="$1"
    
    # Remove trailing whitespace
    content=$(echo "$content" | sed 's/[[:space:]]*$//')
    
    # Remove multiple consecutive blank lines
    content=$(echo "$content" | awk 'BEGIN{blank=0} /^[[:space:]]*$/{blank++; if(blank<=1) print; next} {blank=0; print}')
    
    # Ensure file ends with newline
    if [ -n "$content" ] && [ "${content: -1}" != $'\n' ]; then
        content="${content}"$'\n'
    fi
    
    echo "$content"
}

# Validate a single file
validate_file() {
    local file="$1"
    local clean="${2:-false}"
    
    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi
    
    log_info "Validating: $file"
    
    local content=$(cat "$file")
    local original_content="$content"
    
    # Clean if requested
    if [[ "$clean" == "true" ]]; then
        content=$(clean_markdown "$content")
        if [[ "$content" != "$original_content" ]]; then
            echo "$content" > "$file"
            log_success "Cleaned: $file"
        fi
    fi
    
    # Validate syntax
    if validate_markdown_syntax "$content"; then
        log_success "Valid: $file"
        return 0
    else
        log_error "Invalid: $file"
        return 1
    fi
}

# Validate all markdown files in a directory
validate_directory() {
    local dir="$1"
    local clean="${2:-false}"
    local errors=0
    local total=0
    
    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi
    
    log_info "Validating all markdown files in: $dir"
    
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            total=$((total + 1))
            if ! validate_file "$file" "$clean"; then
                errors=$((errors + 1))
            fi
        fi
    done < <(find "$dir" -name "*.md" -type f)
    
    log_info "Validated $total files with $errors errors"
    return $errors
}

# Validate project documentation
validate_project() {
    local clean="${1:-false}"
    local errors=0
    
    log_info "Validating project documentation..."
    
    # Validate root README
    if [[ -f "$PROJECT_ROOT/README.md" ]]; then
        if ! validate_file "$PROJECT_ROOT/README.md" "$clean"; then
            errors=$((errors + 1))
        fi
    else
        log_warning "README.md not found in project root"
    fi
    
    # Validate docs directory
    if [[ -d "$PROJECT_ROOT/docs" ]]; then
        if ! validate_directory "$PROJECT_ROOT/docs" "$clean"; then
            errors=$((errors + 1))
        fi
    else
        log_warning "docs/ directory not found"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "All markdown files are valid"
        return 0
    else
        log_error "Found $errors validation issues"
        return 1
    fi
}

# Main function for command-line usage
main() {
    case "${1:-help}" in
        "file")
            local file="${2:-}"
            local clean="${3:-false}"
            
            if [[ -z "$file" ]]; then
                log_error "File path is required"
                echo "Usage: $0 file <path> [clean]"
                exit 1
            fi
            
            validate_file "$file" "$clean"
            ;;
        "dir")
            local dir="${2:-}"
            local clean="${3:-false}"
            
            if [[ -z "$dir" ]]; then
                log_error "Directory path is required"
                echo "Usage: $0 dir <path> [clean]"
                exit 1
            fi
            
            validate_directory "$dir" "$clean"
            ;;
        "project")
            local clean="${2:-false}"
            validate_project "$clean"
            ;;
        "clean")
            local file="${2:-}"
            if [[ -n "$file" && -f "$file" ]]; then
                validate_file "$file" "true"
            else
                log_error "File not found: $file"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Markdown Validation Module"
            echo "==================================="
            echo ""
            echo "Usage: $0 [command] [options]"
            echo ""
            echo "Commands:"
            echo "  file <path> [clean]     - Validate a single file"
            echo "  dir <path> [clean]      - Validate all .md files in directory"
            echo "  project [clean]         - Validate project documentation"
            echo "  clean <file>            - Clean a single file"
            echo "  help                    - Show this help"
            echo ""
            echo "Options:"
            echo "  clean                   - Clean files while validating"
            echo ""
            echo "Examples:"
            echo "  $0 file README.md"
            echo "  $0 file README.md clean"
            echo "  $0 dir docs/"
            echo "  $0 project clean"
            echo "  $0 clean README.md"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
