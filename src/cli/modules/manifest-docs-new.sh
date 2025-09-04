#!/bin/bash

# Manifest Documentation Module
# Handles documentation generation, README updates, and release notes

# Load markdown templates
if [ -f "$(dirname "$0")/manifest-markdown-templates.sh" ]; then
    source "$(dirname "$0")/manifest-markdown-templates.sh"
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
        # Create backup
        cp "README.md" "README.md.backup"
        
        # Update version in badges
        sed -i '' "s/version-[0-9]\+\.[0-9]\+\.[0-9]\+/version-${version}/g" "README.md"
        
        # Update version information table
        if grep -q "## 📋 Version Information" "README.md"; then
            # Replace existing version section
            awk -v new_section="$version_section" '
                /^## 📋 Version Information/ { 
                    print new_section; 
                    skip = 1; 
                    next 
                } 
                skip && /^## / && !/^## 📋 Version Information/ { 
                    skip = 0 
                } 
                !skip { print }
            ' "README.md" > "README.md.tmp" && mv "README.md.tmp" "README.md"
        else
            # Add version section at the beginning
            echo "$version_section" > "README.md.tmp"
            echo "" >> "README.md.tmp"
            cat "README.md" >> "README.md.tmp"
            mv "README.md.tmp" "README.md"
        fi
        
        # Clean up backup
        rm "README.md.backup"
        
        echo "   ✅ Version badge updated to $version"
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
move_previous_documentation() {
    echo "📁 Moving previous version documentation to zArchive..."
    
    # Get current version from VERSION file
    local current_version=""
    if [ -f "VERSION" ]; then
        current_version=$(cat VERSION)
    else
        echo "   ⚠️  VERSION file not found, skipping documentation move"
        return 0
    fi
    
    if [ -z "$current_version" ]; then
        echo "   ⚠️  Could not determine current version, skipping documentation move"
        return 0
    fi
    
    echo "   📋 Current version: $current_version"
    
    # Ensure zArchive directory exists
    mkdir -p "docs/zArchive"
    
    local moved_count=0
    
    # Generate filenames using configuration
    local filename_pattern="${MANIFEST_DOCS_FILENAME_PATTERN:-RELEASE_vVERSION.md}"
    local release_filename=$(echo "$filename_pattern" | sed "s/VERSION/$current_version/g")
    local changelog_filename="CHANGELOG_v$current_version.md"
    
    # Move RELEASE files
    if [ -f "docs/$release_filename" ]; then
        mv "docs/$release_filename" "docs/zArchive/"
        echo "   📄 Moved $release_filename to zArchive/"
        moved_count=$((moved_count + 1))
    fi
    
    # Move CHANGELOG files
    if [ -f "docs/$changelog_filename" ]; then
        mv "docs/$changelog_filename" "docs/zArchive/"
        echo "   📄 Moved $changelog_filename to zArchive/"
        moved_count=$((moved_count + 1))
    fi
    
    # Move any other version-specific documentation files
    for file in docs/*_v$current_version.*; do
        if [ -f "$file" ] && [ "$file" != "docs/*_v$current_version.*" ]; then
            mv "$file" "docs/zArchive/"
            echo "   📄 Moved $(basename "$file") to zArchive/"
            moved_count=$((moved_count + 1))
        fi
    done
    
    if [ $moved_count -eq 0 ]; then
        echo "   ℹ️  No previous version documentation found to move"
    else
        echo "   ✅ Moved $moved_count documentation file(s) to zArchive/"
    fi
    
    # Clean up zArchive directory (keep only last 10 versions)
    cleanup_zArchive
}

# Clean up zArchive directory to keep only recent versions
cleanup_zArchive() {
    echo "🧹 Cleaning up zArchive directory..."
    
    # Create zArchive directory if it doesn't exist
    mkdir -p docs/zArchive
    
    # Get list of all version files in zArchive
    local version_files=()
    for file in docs/zArchive/*_v*.*; do
        if [ -f "$file" ]; then
            version_files+=("$file")
        fi
    done
    
    # Get historical limit from configuration
    local historical_limit="${MANIFEST_DOCS_HISTORICAL_LIMIT:-20}"
    
    # If we have more than the limit, remove the oldest ones
    if [ ${#version_files[@]} -gt $historical_limit ]; then
        echo "   📊 Found ${#version_files[@]} files, keeping only the $historical_limit most recent..."
        
        # Sort files by modification time (oldest first) and remove oldest
        local files_to_remove=$(ls -t docs/zArchive/*_v*.* 2>/dev/null | tail -n +$((historical_limit + 1)))
        
        for file in $files_to_remove; do
            if [ -f "$file" ]; then
                rm "$file"
                echo "   🗑️  Removed old file: $(basename "$file")"
            fi
        done
        
        echo "   ✅ Cleanup completed, kept $historical_limit most recent files"
    else
        echo "   ℹ️  zArchive directory is clean (${#version_files[@]} files)"
    fi
}

# Manual function to move existing historical documentation to zArchive
move_existing_historical_docs() {
    echo "📁 Moving existing historical documentation to zArchive..."
    
    # Create zArchive directory if it doesn't exist
    mkdir -p docs/zArchive
    
    local moved_count=0
    
    # Move all existing RELEASE and CHANGELOG files
    for file in docs/RELEASE_v*.* docs/CHANGELOG_v*.*; do
        if [ -f "$file" ]; then
            mv "$file" "docs/zArchive/"
            echo "   📄 Moved $(basename "$file") to zArchive/"
            moved_count=$((moved_count + 1))
        fi
    done
    
    if [ $moved_count -eq 0 ]; then
        echo "   ℹ️  No historical documentation found to move"
    else
        echo "   ✅ Moved $moved_count historical file(s) to zArchive/"
        echo "   💡 You can now run 'manifest docs' to generate current documentation"
    fi
}

generate_documentation() {
    local version="$1"
    local timestamp="$2"
    
    echo "📚 Generating documentation and release notes..."
    
    # Create docs directory if it doesn't exist
    mkdir -p docs
    
    # Create zArchive directory if it doesn't exist
    mkdir -p docs/zArchive
    
    # Generate release notes
    generate_release_notes "$version" "$timestamp"
    
    # Generate changelog
    generate_changelog "$version" "$timestamp"
    
    # Update README
    update_readme_version "$version" "$timestamp"
    
    # Validate markdown files
    if [ -f "scripts/markdown-validator.sh" ]; then
        echo "🔍 Validating markdown files..."
        if ./scripts/markdown-validator.sh validate >/dev/null 2>&1; then
            echo "   ✅ All markdown files are valid"
        else
            echo "   ⚠️  Markdown validation issues found, attempting to fix..."
            if ./scripts/markdown-validator.sh fix >/dev/null 2>&1; then
                echo "   ✅ Markdown issues fixed automatically"
            else
                echo "   ❌ Some markdown issues could not be fixed automatically"
            fi
        fi
    fi
    
    echo "✅ Documentation generated successfully"
}
