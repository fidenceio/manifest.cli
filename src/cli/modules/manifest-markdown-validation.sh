#!/bin/bash

# Manifest Markdown Validation Module
# Handles all markdown validation and fixing operations

# Import the docs module for file reference validation
if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-docs.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-docs.sh"
fi

# Main markdown validation function
validate_all_markdown() {
    echo "🔍 Final markdown validation and fixing..."
    
    local total_issues=0
    
    # Run file reference validation
    echo "   📋 Validating file references..."
    if validate_file_references; then
        echo "   ✅ File references validated successfully"
    else
        local file_ref_issues=$?
        total_issues=$((total_issues + file_ref_issues))
        echo "   ⚠️  File reference validation found $file_ref_issues issues"
    fi
    
    # Run markdown syntax validation and fixing
    echo "   📝 Validating and fixing markdown syntax..."
    if [ -f "scripts/markdown-validator.sh" ]; then
        if ./scripts/markdown-validator.sh; then
            echo "   ✅ All markdown files validated and fixed"
        else
            local syntax_issues=$?
            total_issues=$((total_issues + syntax_issues))
            echo "   ⚠️  Markdown syntax validation found $syntax_issues issues"
        fi
    else
        echo "   ⚠️  markdown-validator.sh not found, skipping syntax validation"
        total_issues=$((total_issues + 1))
    fi
    
    # Return status
    if [ $total_issues -eq 0 ]; then
        echo "   ✅ All markdown validation completed successfully"
        return 0
    else
        echo "   ⚠️  Markdown validation completed with $total_issues total issues"
        return $total_issues
    fi
}

# Validate file references only
validate_file_references_only() {
    echo "📋 Validating file references..."
    
    if validate_file_references; then
        echo "✅ File references validated successfully"
        return 0
    else
        local issues=$?
        echo "⚠️  File reference validation found $issues issues"
        return $issues
    fi
}

# Validate markdown syntax only
validate_syntax_only() {
    echo "📝 Validating and fixing markdown syntax..."
    
    if [ -f "scripts/markdown-validator.sh" ]; then
        if ./scripts/markdown-validator.sh; then
            echo "✅ All markdown files validated and fixed"
            return 0
        else
            local issues=$?
            echo "⚠️  Markdown syntax validation found $issues issues"
            return $issues
        fi
    else
        echo "❌ markdown-validator.sh not found"
        return 1
    fi
}

# Validate specific markdown file
validate_single_file() {
    local file="$1"
    
    if [ -z "$file" ]; then
        echo "❌ No file specified for validation"
        return 1
    fi
    
    if [ ! -f "$file" ]; then
        echo "❌ File not found: $file"
        return 1
    fi
    
    echo "🔍 Validating file: $file"
    
    local issues=0
    
    # Validate file references for this specific file
    echo "   📋 Checking file references..."
    if validate_file_references_in_file "$file"; then
        echo "   ✅ File references are valid"
    else
        local file_ref_issues=$?
        issues=$((issues + file_ref_issues))
        echo "   ⚠️  Found $file_ref_issues file reference issues"
    fi
    
    # Validate markdown syntax for this specific file
    echo "   📝 Checking markdown syntax..."
    if [ -f "scripts/markdown-validator.sh" ]; then
        if ./scripts/markdown-validator.sh "$file"; then
            echo "   ✅ Markdown syntax is valid"
        else
            local syntax_issues=$?
            issues=$((issues + syntax_issues))
            echo "   ⚠️  Found $syntax_issues syntax issues"
        fi
    else
        echo "   ⚠️  markdown-validator.sh not found, skipping syntax validation"
        issues=$((issues + 1))
    fi
    
    if [ $issues -eq 0 ]; then
        echo "✅ File validation completed successfully"
        return 0
    else
        echo "⚠️  File validation completed with $issues issues"
        return $issues
    fi
}

# Fix markdown issues automatically
fix_markdown_issues() {
    echo "🔧 Fixing markdown issues..."
    
    local fixed_files=0
    
    # Fix syntax issues
    if [ -f "scripts/markdown-validator.sh" ]; then
        echo "   📝 Fixing syntax issues..."
        if ./scripts/markdown-validator.sh; then
            echo "   ✅ Syntax issues fixed"
            fixed_files=$((fixed_files + 1))
        else
            echo "   ⚠️  Some syntax issues could not be automatically fixed"
        fi
    else
        echo "   ⚠️  markdown-validator.sh not found, skipping syntax fixes"
    fi
    
    # Note: File reference issues typically require manual intervention
    echo "   📋 File reference issues require manual review"
    
    if [ $fixed_files -gt 0 ]; then
        echo "✅ Fixed issues in $fixed_files areas"
        return 0
    else
        echo "⚠️  No issues could be automatically fixed"
        return 1
    fi
}

# Show validation summary
show_validation_summary() {
    echo "📊 Markdown Validation Summary"
    echo "=============================="
    
    local total_files=0
    local valid_files=0
    local invalid_files=0
    
    # Count markdown files
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            total_files=$((total_files + 1))
            
            # Quick validation check
            if validate_single_file "$file" >/dev/null 2>&1; then
                valid_files=$((valid_files + 1))
            else
                invalid_files=$((invalid_files + 1))
            fi
        fi
    done < <(find . -name "*.md" -type f | grep -v "docs/zArchive" | sort)
    
    echo "   Total files: $total_files"
    echo "   Valid files: $valid_files"
    echo "   Invalid files: $invalid_files"
    
    if [ $invalid_files -eq 0 ]; then
        echo "   Status: ✅ All files are valid"
        return 0
    else
        echo "   Status: ⚠️  $invalid_files files need attention"
        return $invalid_files
    fi
}

# Main function for command-line usage
main() {
    case "${1:-all}" in
        "all")
            validate_all_markdown
            ;;
        "files")
            validate_file_references_only
            ;;
        "syntax")
            validate_syntax_only
            ;;
        "single")
            validate_single_file "$2"
            ;;
        "fix")
            fix_markdown_issues
            ;;
        "summary")
            show_validation_summary
            ;;
        "help"|"-h"|"--help")
            echo "Manifest Markdown Validation"
            echo "============================"
            echo ""
            echo "Usage: $0 [command] [file]"
            echo ""
            echo "Commands:"
            echo "  all      - Validate all markdown files (default)"
            echo "  files    - Validate file references only"
            echo "  syntax   - Validate markdown syntax only"
            echo "  single   - Validate specific file"
            echo "  fix      - Fix markdown issues automatically"
            echo "  summary  - Show validation summary"
            echo "  help     - Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                    # Validate all files"
            echo "  $0 files             # Check file references only"
            echo "  $0 single README.md  # Check specific file"
            echo "  $0 fix               # Fix issues automatically"
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Use '$0 help' for usage information"
            return 1
            ;;
    esac
}

# If script is being executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
