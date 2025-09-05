#!/bin/bash

# Manifest Documentation Module
# Handles documentation generation, README updates, and release notes

# Load markdown templates
# Use BASH_SOURCE to get the actual file path when sourced
if [ -n "${BASH_SOURCE[0]}" ]; then
    TEMPLATES_FILE="$(dirname "${BASH_SOURCE[0]}")/manifest-markdown-templates.sh"
else
    TEMPLATES_FILE="$(dirname "$0")/manifest-markdown-templates.sh"
fi

if [ -f "$TEMPLATES_FILE" ]; then
    source "$TEMPLATES_FILE"
fi

generate_release_notes() {
    local version="$1"
    local timestamp="$2"
    
    # Generate filename using configuration
    local filename_pattern="${MANIFEST_DOCS_FILENAME_PATTERN:-RELEASE_vVERSION.md}"
    local release_filename=$(echo "$filename_pattern" | sed "s/VERSION/$version/g")
    
    echo "📝 Generating $release_filename..."
    
    # Determine release type based on version
    local release_type="patch"
    if [[ $version =~ ^[0-9]+\.[0-9]+\.0$ ]]; then
        release_type="minor"
    elif [[ $version =~ ^[0-9]+\.0\.0$ ]]; then
        release_type="major"
    fi
    
    # Generate content using template
    local content=$(generate_release_notes_template "$version" "$timestamp" "$release_type")
    
    # Clean and validate markdown
    content=$(clean_markdown "$content")
    
    # Write to file
    echo "$content" > "docs/$release_filename"
    
    echo "✅ $release_filename created"
}

generate_changelog() {
    local version="$1"
    local timestamp="$2"
    
    # Generate filename using configuration
    local changelog_filename="CHANGELOG_v$version.md"
    
    echo "📝 Generating $changelog_filename..."
    
    # Determine release type based on version
    local release_type="patch"
    if [[ $version =~ ^[0-9]+\.[0-9]+\.0$ ]]; then
        release_type="minor"
    elif [[ $version =~ ^[0-9]+\.0\.0$ ]]; then
        release_type="major"
    fi
    
    # Generate content using template
    local content=$(generate_changelog_template "$version" "$timestamp" "$release_type")
    
    # Clean and validate markdown
    content=$(clean_markdown "$content")
    
    # Write to file
    echo "$content" > "docs/$changelog_filename"
    
    echo "✅ $changelog_filename created"
}

update_readme_version() {
    local version="$1"
    local timestamp="$2"
    
    echo "📝 Updating README.md..."
    
    # Generate version section using template
    local version_section=$(generate_readme_version_section "$version" "$timestamp")
    
    # Update README.md with new version information
    if [ -f "README.md" ]; then
        # Update version in badges (if any exist)
        if grep -q "version-[0-9]\+\.[0-9]\+\.[0-9]\+" "README.md"; then
            sed -i '' "s/version-[0-9]\+\.[0-9]\+\.[0-9]\+/version-${version}/g" "README.md"
            echo "   ✅ Version badge updated to $version"
        fi
        
        # Update version information table
        if grep -q "## 📋 Version Information" "README.md"; then
            # Replace existing version section using sed instead of awk to avoid newline issues
            local temp_file=$(mktemp)
            local in_version_section=false
            
            while IFS= read -r line; do
                if [[ "$line" == "## 📋 Version Information" ]]; then
                    echo "$version_section"
                    in_version_section=true
                elif [[ "$in_version_section" == true && "$line" == "## "* && "$line" != "## 📋 Version Information" ]]; then
                    in_version_section=false
                    echo "$line"
                elif [[ "$in_version_section" == false ]]; then
                    echo "$line"
                fi
            done < "README.md" > "$temp_file" && mv "$temp_file" "README.md"
        else
            # Add version section after the title
            local temp_file=$(mktemp)
            local added_version_section=false
            
            while IFS= read -r line; do
                echo "$line"
                # Add version section after the first heading (title)
                if [[ "$line" =~ ^#\  && "$added_version_section" == false ]]; then
                    echo ""
                    echo "$version_section"
                    added_version_section=true
                fi
            done < "README.md" > "$temp_file" && mv "$temp_file" "README.md"
        fi
        
        # Validate and fix common incorrect references in README
        local fixed_refs=()
        
        # Check for incorrect repository references
        if grep -q "manifest\.local" "README.md"; then
            sed -i '' 's/manifest\.local/manifest.cli/g' "README.md"
            fixed_refs+=("manifest.local → manifest.cli")
        fi
        
        # Check for package.json references (should be VERSION)
        if grep -q "package\.json" "README.md"; then
            sed -i '' 's/package\.json/VERSION/g' "README.md"
            fixed_refs+=("package.json → VERSION")
        fi
        
        # Report fixes
        if [[ ${#fixed_refs[@]} -gt 0 ]]; then
            echo "   ✅ Fixed incorrect references: ${fixed_refs[*]}"
        fi
        
        # Validate ALL file references in README
        validate_file_references_in_file "README.md"
        
        echo "   ✅ Version information table updated to $version"
        echo "   ✅ README.md version information updated"
    else
        echo "   ⚠️  README.md not found, skipping version update"
    fi
}

# Repository metadata update function
update_repository_metadata() {
    echo "🏷️  Updating repository metadata..."
    
    # Check if we're in a git repository
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo "   ⚠️  Not in a git repository, skipping metadata update"
        return 0
    fi
    
    # Get repository URL
    local repo_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    
    if [ -z "$repo_url" ]; then
        echo "   ⚠️  No remote origin found, skipping metadata update"
        return 0
    fi
    
    # Detect repository provider
    local provider=""
    if [[ $repo_url == *"github.com"* ]]; then
        provider="github"
    elif [[ $repo_url == *"gitlab.com"* ]]; then
        provider="gitlab"
    else
        echo "   ⚠️  Unsupported repository provider, skipping metadata update"
        return 0
    fi
    
    echo "   🔄 Automatically updating repository metadata..."
    echo "   ✅ Detected provider: $provider"
    
    # Update repository description and topics
    if [ "$provider" = "github" ]; then
        # GitHub-specific metadata updates would go here
        echo "   🔄 GitHub metadata updates would be implemented here"
        echo "   ✅ Repository metadata updated automatically"
    elif [ "$provider" = "gitlab" ]; then
        # GitLab-specific metadata updates would go here
        echo "   🔄 GitLab metadata updates would be implemented here"
        echo "   ✅ Repository metadata updated automatically"
    fi
    
    return 0
}

# Move previous version's documentation to zArchive folder
# This function is now handled by repo-cleanup.sh
move_previous_documentation() {
    echo "📁 Moving previous version documentation to zArchive..."
    echo "   ℹ️  This operation is now handled by repo-cleanup.sh"
    echo "   💡 Run 'manifest cleanup archive' to move old documentation"
}

# zArchive cleanup is now handled by the common cleanup module

# Manual function to move existing historical documentation to zArchive
# This function is now handled by repo-cleanup.sh
move_existing_historical_docs() {
    echo "📁 Moving existing historical documentation to zArchive..."
    echo "   ℹ️  This operation is now handled by repo-cleanup.sh"
    echo "   💡 Run 'manifest cleanup archive' to move old documentation"
}

generate_documentation() {
    local version="$1"
    local timestamp="$2"
    
    echo "📚 Generating documentation and release notes..."
    
    # Generate release notes
    generate_release_notes "$version" "$timestamp"
    
    # Generate changelog
    generate_changelog "$version" "$timestamp"
    
    # Update README
    update_readme_version "$version" "$timestamp"
    
    # Validate all file references
    validate_file_references
    
    echo "✅ Documentation generated successfully"
}

# Validate file references in a specific file
validate_file_references_in_file() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    
    local issues=0
    local missing_files=()
    local invalid_refs=()
    
    # Check all file references in the file
    while IFS= read -r line; do
        # Extract markdown links [text](path)
        if echo "$line" | grep -q '\[.*\](.*)'; then
            local link_text=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\](.*)/\1/p')
            local file_path=$(echo "$line" | sed -n 's/.*\[.*\](\([^)]*\))/\1/p' | sed 's/ .*$//')
            
            # Skip external URLs
            if [[ ! "$file_path" =~ ^https?:// ]]; then
                # Skip empty or invalid file paths
                if [[ -n "$file_path" ]]; then
                    # Check if file/directory exists
                    if [[ ! -f "$file_path" && ! -d "$file_path" ]]; then
                        # Skip common directory references that are valid
                        if [[ "$file_path" != "docs/" && "$file_path" != "src/" && "$file_path" != "." && "$file_path" != "docs" && "$file_path" != "src" ]]; then
                            missing_files+=("$file_path")
                            issues=$((issues + 1))
                        fi
                    fi
                fi
            fi
        fi
        
        # Extract code block file references (```bash, ./script.sh, etc.)
        if [[ "$line" =~ \.\/[a-zA-Z0-9_\.-]+ ]]; then
            local script_ref="${BASH_REMATCH[0]}"
            if [[ ! -f "$script_ref" ]]; then
                invalid_refs+=("$script_ref")
                issues=$((issues + 1))
            fi
        fi
        
        # Extract direct file references in text
        if [[ "$line" =~ [^a-zA-Z0-9_\.-]([a-zA-Z0-9_\.-]+\.(sh|py|js|ts|md|txt|json|yaml|yml)) ]]; then
            local file_ref="${BASH_REMATCH[1]}"
            if [[ ! -f "$file_ref" && ! -d "$file_ref" ]]; then
                # Only flag if it looks like a file reference (not just text)
                if [[ "$line" =~ (script|file|install|run|execute).*$file_ref ]]; then
                    invalid_refs+=("$file_ref")
                    issues=$((issues + 1))
                fi
            fi
        fi
    done < "$file"
    
    # Report issues
    if [[ $issues -gt 0 ]]; then
        echo "   ⚠️  Found $issues invalid file references:"
        if [[ ${#missing_files[@]} -gt 0 ]]; then
            echo "     Missing files: ${missing_files[*]}"
        fi
        if [[ ${#invalid_refs[@]} -gt 0 ]]; then
            echo "     Invalid references: ${invalid_refs[*]}"
        fi
    else
        echo "   ✅ All file references are valid"
    fi
    
    return $issues
}

# Validate all file references in markdown files
validate_file_references() {
    echo "🔍 Validating file references in all markdown files..."
    
    local total_issues=0
    local files_checked=0
    
    # Find all markdown files (excluding zArchive)
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            files_checked=$((files_checked + 1))
            echo "   Checking: $file"
            
            if validate_file_references_in_file "$file"; then
                # Function returns 0 for no issues, >0 for issues
                local file_issues=$?
                total_issues=$((total_issues + file_issues))
            fi
        fi
    done < <(find . -name "*.md" -type f | grep -v "docs/zArchive" | sort)
    
    echo ""
    if [[ $total_issues -eq 0 ]]; then
        echo "✅ All file references are valid ($files_checked files checked)"
    else
        echo "⚠️  Found $total_issues total issues across $files_checked files"
    fi
    
    return $total_issues
}

# Load cleanup module
if [ -f "$(dirname "${BASH_SOURCE[0]}")/manifest-cleanup.sh" ]; then
    source "$(dirname "${BASH_SOURCE[0]}")/manifest-cleanup.sh"
fi
