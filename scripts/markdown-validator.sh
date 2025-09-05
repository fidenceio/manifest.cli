#!/bin/bash

# Simple Markdown Validator
# No complex functions, just straightforward processing

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Simple logging
log_error() { echo -e "${RED}❌ $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }

# Check if file has issues
check_file() {
    local file="$1"
    local errors=0
    
    echo "Checking: $file"
    
    # Check trailing whitespace
    if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
        log_error "Trailing whitespace found"
        errors=$((errors + 1))
    fi
    
    # Check multiple blank lines (3 or more)
    local blank_count
    blank_count=$(awk '/^[[:space:]]*$/{blank++; if(blank>2) {found=1; exit 1}} {blank=0} END{if(found) exit 1; exit 0}' "$file" 2>/dev/null; echo $?)
    if [[ $blank_count -eq 1 ]]; then
        log_error "Multiple consecutive blank lines found"
        errors=$((errors + 1))
    fi
    
    # Check unclosed code blocks
    local code_count
    code_count=$(grep -c '^```' "$file" 2>/dev/null || echo "0")
    code_count=$(echo "$code_count" | head -1)  # Take only first line
    if [[ "$code_count" -gt 0 ]] && [[ $((code_count % 2)) -ne 0 ]]; then
        log_error "Unclosed code block found"
        errors=$((errors + 1))
    fi
    
    # Check file ends with newline
    if [[ -s "$file" ]] && [[ "$(tail -c1 "$file")" != "" ]]; then
        log_warning "File should end with newline"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_success "Valid"
        return 0
    else
        log_error "$errors error(s)"
        return 1
    fi
}

# Main processing
main() {
    local files=()
    
    # Get files from arguments or find all .md files
    if [[ $# -eq 0 ]]; then
        while IFS= read -r file; do
            files+=("$file")
        done < <(find . -name "*.md" -type f | grep -v "docs/zArchive" | sort)
    else
        files=("$@")
    fi
    
    if [[ ${#files[@]} -eq 0 ]]; then
        log_warning "No markdown files found"
        exit 0
    fi
    
    local total_errors=0
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            if ! check_file "$file"; then
                total_errors=$((total_errors + 1))
            fi
            echo ""
        fi
    done
    
    if [[ $total_errors -eq 0 ]]; then
        log_success "All files are valid!"
        exit 0
    else
        log_error "Found $total_errors files with issues"
        exit 1
    fi
}

main "$@"