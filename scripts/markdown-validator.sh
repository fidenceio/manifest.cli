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

# Fix file issues
fix_file() {
    local file="$1"
    local temp_file=$(mktemp)
    local fixed=false
    
    # Fix trailing whitespace
    if grep -q '[[:space:]]$' "$file" 2>/dev/null; then
        sed 's/[[:space:]]*$//' "$file" > "$temp_file" && mv "$temp_file" "$file"
        log_success "Fixed trailing whitespace"
        fixed=true
    fi
    
    # Fix multiple blank lines (reduce to max 2 consecutive)
    # Use awk to process the file line by line and reduce consecutive empty lines
    local temp_file2=$(mktemp)
    local empty_count=0
    local prev_empty=false
    
    while IFS= read -r line; do
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*$ ]]; then
            # This is an empty line
            if [[ "$prev_empty" == true ]]; then
                empty_count=$((empty_count + 1))
            else
                empty_count=1
                prev_empty=true
            fi
            
            # Only keep up to 2 consecutive empty lines
            if [[ $empty_count -le 2 ]]; then
                echo "" >> "$temp_file2"
            fi
        else
            # This is a non-empty line
            echo "$line" >> "$temp_file2"
            empty_count=0
            prev_empty=false
        fi
    done < "$file"
    
    # Check if we made changes
    if ! cmp -s "$file" "$temp_file2"; then
        mv "$temp_file2" "$file"
        log_success "Fixed multiple blank lines"
        fixed=true
    else
        rm "$temp_file2"
    fi
    
    # Fix file ending - ensure single newline at end
    if [[ -s "$file" ]]; then
        # Check if file ends with exactly one newline
        local last_char=$(tail -c1 "$file" 2>/dev/null)
        if [[ "$last_char" != "" ]]; then
            # File doesn't end with newline, add one
            echo "" >> "$file"
            log_success "Fixed file ending"
            fixed=true
        elif [[ $(tail -c2 "$file" 2>/dev/null | wc -c) -eq 2 ]]; then
            # File ends with exactly one newline, this is correct
            :
        else
            # File might have multiple trailing newlines, fix it
            perl -i -pe 'chomp if eof' "$file" 2>/dev/null
            echo "" >> "$file"
            log_success "Fixed file ending"
            fixed=true
        fi
    fi
    
    # Note: Unclosed code blocks require manual intervention
    local code_count
    code_count=$(grep -c '^```' "$file" 2>/dev/null || echo "0")
    code_count=$(echo "$code_count" | head -1)
    if [[ "$code_count" -gt 0 ]] && [[ $((code_count % 2)) -ne 0 ]]; then
        log_warning "Unclosed code block found - requires manual fix"
    fi
    
    if [[ "$fixed" == true ]]; then
        return 0
    else
        return 1
    fi
}

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
    
    local total_fixed=0
    for file in "${files[@]}"; do
        if [[ -f "$file" ]]; then
            echo "Processing: $file"
            if fix_file "$file"; then
                total_fixed=$((total_fixed + 1))
            fi
            echo ""
        fi
    done
    
    if [[ $total_fixed -eq 0 ]]; then
        log_success "All files are already valid!"
        exit 0
    else
        log_success "Fixed $total_fixed files"
        exit 0
    fi
}

main "$@"