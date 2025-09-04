#!/bin/bash

# Markdown Validator for Manifest CLI
# This script validates markdown files and can be integrated into the CLI workflow

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Validation rules
validate_markdown() {
    local file="$1"
    local errors=0
    local warnings=0
    
    echo "🔍 Validating: $(basename "$file")"
    
    # Check 1: Multiple consecutive blank lines (more than 2)
    if ! awk '/^[[:space:]]*$/{blank++; if(blank>2) {found=1; exit 1}} {blank=0} END{if(found) exit 1; exit 0}' "$file" 2>/dev/null; then
        echo "  ❌ Multiple consecutive blank lines found"
        errors=$((errors + 1))
    fi
    
    # Check 2: Trailing whitespace
    if grep -q "[[:space:]]$" "$file"; then
        echo "  ❌ Trailing whitespace found"
        errors=$((errors + 1))
    fi
    
    # Check 3: File should start with header
    if ! head -1 "$file" | grep -q "^#"; then
        echo "  ❌ File should start with a header (# Title)"
        errors=$((errors + 1))
    fi
    
    # Check 4: Proper heading hierarchy (no skipping levels)
    local prev_level=0
    while IFS= read -r line; do
        if [[ $line =~ ^(#+)[[:space:]] ]]; then
            local current_level=${#BASH_REMATCH[1]}
            if [ $current_level -gt $((prev_level + 1)) ]; then
                echo "  ❌ Heading level skipped: $line"
                errors=$((errors + 1))
            fi
            prev_level=$current_level
        fi
    done < "$file"
    
    # Check 5: Unclosed code blocks
    local code_blocks=$(grep -c "^\\\`\\\`\\\`" "$file" 2>/dev/null || echo "0")
    if [ "$code_blocks" -gt 0 ] && [ $((code_blocks % 2)) -ne 0 ]; then
        echo "  ❌ Unclosed code block found"
        errors=$((errors + 1))
    fi
    
    # Check 6: Empty lines at end of file
    if [ -s "$file" ] && [ "$(tail -c1 "$file")" != "" ]; then
        echo "  ⚠️  File should end with newline"
        warnings=$((warnings + 1))
    fi
    
    if [ $errors -eq 0 ] && [ $warnings -eq 0 ]; then
        echo "  ✅ Valid"
        return 0
    elif [ $errors -eq 0 ]; then
        echo "  ⚠️  $warnings warning(s)"
        return 1
    else
        echo "  ❌ $errors error(s), $warnings warning(s)"
        return 2
    fi
}

# Auto-fix common issues
fix_markdown() {
    local file="$1"
    local fixed=false
    
    echo "🔧 Fixing: $(basename "$file")"
    
    # Create backup
    cp "$file" "${file}.backup"
    
    # Fix 1: Remove trailing whitespace
    if sed -i '' 's/[[:space:]]*$//' "$file"; then
        echo "  ✅ Removed trailing whitespace"
        fixed=true
    fi
    
    # Fix 2: Remove multiple consecutive blank lines
    awk 'BEGIN{blank=0} /^[[:space:]]*$/{blank++; if(blank<=1) print; next} {blank=0; print}' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
    if [ $? -eq 0 ]; then
        echo "  ✅ Fixed multiple blank lines"
        fixed=true
    fi
    
    # Fix 3: Ensure file ends with newline
    if [ -s "$file" ] && [ "$(tail -c1 "$file")" != "" ]; then
        echo "" >> "$file"
        echo "  ✅ Added final newline"
        fixed=true
    fi
    
    if [ "$fixed" = true ]; then
        echo "  ✅ File fixed"
    else
        echo "  ✅ No fixes needed"
        rm "${file}.backup"
    fi
}

# Main function
main() {
    local action="${1:-validate}"
    local files="${2:-$(find . -name "*.md" -not -path "./docs/zArchive/*" -not -path "./node_modules/*" -not -path "./.git/*")}"
    
    case "$action" in
        "validate")
            echo "🔍 Validating markdown files..."
            local total_errors=0
            for file in $files; do
                if [ -f "$file" ]; then
                    validate_markdown "$file"
                    total_errors=$((total_errors + $?))
                fi
            done
            echo ""
            if [ $total_errors -eq 0 ]; then
                echo "✅ All markdown files are valid!"
            else
                echo "❌ Found $total_errors files with issues"
                exit 1
            fi
            ;;
        "fix")
            echo "🔧 Fixing markdown files..."
            for file in $files; do
                if [ -f "$file" ]; then
                    fix_markdown "$file"
                fi
            done
            echo "✅ Markdown fixes completed!"
            ;;
        *)
            echo "Usage: $0 [validate|fix] [files...]"
            exit 1
            ;;
    esac
}

main "$@"
