#!/bin/bash

# Manifest Local CLI
# Local development tool for Git operations and cloud service integration

set -e

SCRIPT_DIR="$HOME/.manifest-local"
# Don't change directory - stay in the current working directory
# cd "$SCRIPT_DIR"

# Load environment variables
if [ -f ".env" ]; then
    export $(cat .env | grep -v '^#' | xargs)
fi

case "$1" in
    "push")
        echo "Version bump, commit, and push changes..."
        if [ -z "$2" ]; then
            echo "Usage: manifest push [patch|minor|major]"
            echo "  patch  - Increment patch version (1.0.0 -> 1.0.1)"
            echo "  minor  - Increment minor version (1.0.0 -> 1.1.0)"
            echo "  major  - Increment major version (1.0.0 -> 2.0.0)"
            exit 1
        fi
        increment_type="$2"
        echo "Incrementing $increment_type version..."
        
        # Check git status
        if ! git diff-index --quiet HEAD --; then
            echo "Uncommitted changes detected. Committing first..."
            git add .
            git commit -m "Auto-commit before version bump"
        fi
        
        # Bump version
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "Current version: $current_version"
            
            # Parse and increment version
            major=$(echo "$current_version" | cut -d. -f1)
            minor=$(echo "$current_version" | cut -d. -f2)
            patch=$(echo "$current_version" | cut -d. -f3)
            
            case "$increment_type" in
                patch) patch=$((patch + 1)); new_version="$major.$minor.$patch";;
                minor) minor=$((minor + 1)); patch=0; new_version="$major.$minor.$patch";;
                major) major=$((major + 1)); minor=0; patch=0; new_version="$major.$minor.$patch";;
            esac
            
            echo "New version: $new_version"
            
            # Update package.json
            node -e "const pkg = require('./package.json'); pkg.version = '$new_version'; require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');"
            
            # Create/update VERSION file
            echo "$new_version" > VERSION
            echo "✅ VERSION file updated: $new_version"
            
            # Update README.md if it exists
            if [ -f "README.md" ]; then
                sed -i.bak "s/version.*$new_version/version: $new_version/" README.md 2>/dev/null || true
                rm -f README.md.bak 2>/dev/null || true
            fi
            
            echo "Version bumped to $new_version"
        else
            echo "No package.json found in current directory"
            exit 1
        fi
        
        # Commit version changes
        git add .
        git commit -m "Bump version to $new_version"
        
        # Create tag (handle conflicts gracefully)
        if git tag -a "v$new_version" -m "Release version $new_version" 2>/dev/null; then
            echo "✅ Tag v$new_version created"
        else
            echo "⚠️  Tag v$new_version already exists, skipping tag creation"
        fi
        
        # Simple and reliable push logic
        echo "🚀 Pushing to all remotes..."
        push_success=true
        for remote in $(git remote); do
            echo "   Pushing to $remote..."
            remote_success=true
            
            # Try to push main branch first
            if git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || git push "$remote" "$(git branch --show-current)" 2>/dev/null; then
                echo "   ✅ Main branch pushed successfully"
            else
                echo "   ⚠️  Push failed, attempting to sync..."
                
                # Fetch latest from remote
                if git fetch "$remote" 2>/dev/null; then
                    echo "   ✅ Fetched latest from $remote"
                    
                    # Try a simple pull and push approach
                    if git pull "$remote" main --no-edit 2>/dev/null || git pull "$remote" master --no-edit 2>/dev/null; then
                        echo "   ✅ Synced with remote"
                        echo "   🚀 Retrying push..."
                        
                        if git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || git push "$remote" "$(git branch --show-current)" 2>/dev/null; then
                            echo "   ✅ Successfully pushed after sync"
                        else
                            echo "   ❌ Push still failed after sync"
                            echo "   💡 Manual intervention required: git pull $remote main --rebase"
                            remote_success=false
                            push_success=false
                        fi
                    else
                        echo "   ❌ Failed to sync with remote"
                        echo "   💡 Manual intervention required: git pull $remote main --rebase"
                        remote_success=false
                        push_success=false
                    fi
                else
                    echo "   ❌ Failed to fetch from remote"
                    remote_success=false
                    push_success=false
                fi
            fi
            
            # Push tags
            if git push "$remote" --tags 2>/dev/null; then
                echo "   ✅ Tags pushed to $remote"
            else
                echo "   ⚠️  Tag push failed to $remote, some tags may already exist"
                # Tag push failure doesn't fail the entire operation
            fi
            
            # Report remote status
            if [ "$remote_success" = false ]; then
                echo "   ❌ Failed to push to $remote"
            fi
        done
        
        # Report overall push status
        if [ "$push_success" = true ]; then
            echo "✅ Successfully pushed version $new_version to all remotes"
        else
            echo "❌ Failed to push version $new_version to some remotes"
            echo ""
            echo "💡 Manual intervention required:"
            echo "   • Check remote status: git remote -v"
            echo "   • Sync with remote: git pull origin main --rebase"
            echo "   • Try push again: git push origin main --tags"
            echo ""
            echo "⚠️  Version bump completed locally, but remote sync failed"
            exit 1
        fi
        ;;
    "commit")
        echo "Committing changes with intelligent message..."
        if [ -z "$2" ]; then
            echo "Usage: manifest commit <message>"
            exit 1
        fi
        commit_message="$2"
        git add .
        git commit -m "$commit_message"
        echo "Changes committed: $commit_message"
        ;;
    "revert")
        echo "🔄 Reverting to previous version..."
        echo ""
        
        # Check if we're in a git repository
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            echo "Error: Not in a git repository"
            exit 1
        fi
        
        # Check git status
        if ! git diff-index --quiet HEAD --; then
            echo "📝 Uncommitted changes detected. Please commit or stash them first."
            exit 1
        fi
        
        # Get current version
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "📋 Current version: $current_version"
        else
            echo "❌ No package.json found, cannot revert version"
            exit 1
        fi
        
        # Get available versions from git tags
        echo ""
        echo "📋 Available versions to revert to:"
        available_versions=($(git tag --sort=-version:refname | head -10))
        
        if [ ${#available_versions[@]} -eq 0 ]; then
            echo "❌ No version tags found in repository"
            exit 1
        fi
        
        # Display available versions
        for i in "${!available_versions[@]}"; do
            version=${available_versions[$i]}
            echo "   $((i+1)). $version"
        done
        
        echo ""
        echo "💡 Note: Only showing the 10 most recent versions"
        
        # Ask user to select version
        echo ""
        read -p "Select version to revert to (1-${#available_versions[@]}) or 'q' to quit: " selection
        
        if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
            echo "❌ Revert cancelled by user"
            exit 0
        fi
        
        # Validate selection
        if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt ${#available_versions[@]} ]; then
            echo "❌ Invalid selection. Please choose a number between 1 and ${#available_versions[@]}"
            exit 1
        fi
        
        # Get selected version
        selected_index=$((selection-1))
        selected_tag=${available_versions[$selected_index]}
        previous_version=${selected_tag#v}
        
        echo ""
        echo "🎯 Selected version: $previous_version"
        
        # Show what will happen
        echo ""
        echo "📋 Revert Summary:"
        echo "   - From: $current_version"
        echo "   - To: $previous_version"
        echo "   - Will update: package.json, README.md"
        echo "   - Will create: git tag v$previous_version"
        echo "   - Will push to: all remotes"
        
        # Final confirmation
        echo ""
        read -p "Are you sure you want to revert to version $previous_version? (y/N): " confirm
        
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo "❌ Revert cancelled by user"
            exit 0
        fi
        
        echo ""
        echo "🔄 Proceeding with revert to version $previous_version..."
        
        # Update package.json to selected version
        node -e "const pkg = require('./package.json'); pkg.version = '$previous_version'; require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');"
        
        # Update VERSION file
        echo "$previous_version" > VERSION
        echo "   ✅ VERSION file updated: $previous_version"
        
        # Update README.md if it exists
        if [ -f "README.md" ]; then
            sed -i.bak "s/version.*$previous_version/version: $previous_version/" README.md 2>/dev/null || true
            rm -f README.md.bak 2>/dev/null || true
        fi
        
        echo "✅ Reverted to version $previous_version"
        
        # Commit version changes
        echo ""
        echo "💾 Committing version changes..."
        git add .
        git commit -m "Revert to version $previous_version"
        echo "✅ Version changes committed"
        
        # Create tag (handle conflicts gracefully)
        echo ""
        echo "🏷️  Creating git tag..."
        if git tag -a "v$previous_version" -m "Revert to version $previous_version" 2>/dev/null; then
            echo "✅ Tag v$previous_version created"
        else
            echo "⚠️  Tag v$previous_version already exists, skipping tag creation"
        fi
        
        # Push to all remotes
        echo ""
        echo "🚀 Pushing to all remotes..."
        for remote in $(git remote); do
            echo "   Pushing to $remote..."
            git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || git push "$remote" "$(git branch --show-current)"
            git push "$remote" --tags
            echo "   ✅ Pushed to $remote"
        done
        
        echo ""
        echo "🎉 Revert completed successfully!"
        echo ""
        echo "📋 Summary:"
        echo "   - Previous version: $previous_version"
        echo "   - Tag: v$previous_version"
        echo "   - Remotes: $(git remote | wc -l) pushed"
        ;;
    "version")
        echo "Bumping version..."
        if [ -z "$2" ]; then
            echo "Usage: manifest version [patch|minor|major]"
            echo "  patch  - Increment patch version (1.0.0 -> 1.0.1)"
            echo "  minor  - Increment minor version (1.0.0 -> 1.1.0)"
            echo "  major  - Increment major version (1.0.0 -> 2.0.0)"
            exit 1
        fi
        increment_type="$2"
        
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "Current version: $current_version"
            
            # Parse and increment version
            major=$(echo "$current_version" | cut -d. -f1)
            minor=$(echo "$current_version" | cut -d. -f2)
            patch=$(echo "$current_version" | cut -d. -f3)
            
            case "$increment_type" in
                patch) patch=$((patch + 1)); new_version="$major.$minor.$patch";;
                minor) minor=$((minor + 1)); patch=0; new_version="$major.$minor.$patch";;
                major) major=$((major + 1)); minor=0; patch=0; new_version="$major.$minor.$patch";;
            esac
            
            echo "New version: $new_version"
            
            # Update package.json
            node -e "const pkg = require('./package.json'); pkg.version = '$new_version'; require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');"
            
            # Create/update VERSION file
            echo "$new_version" > VERSION
            echo "✅ VERSION file updated: $new_version"
            
            # Update README.md if it exists
            if [ -f "README.md" ]; then
                sed -i.bak "s/version.*$new_version/version: $new_version/" README.md 2>/dev/null || true
                rm -f README.md.bak 2>/dev/null || true
            fi
            
            echo "Version bumped to $new_version"
        else
            echo "No package.json found in current directory"
            exit 1
        fi
        ;;
    "analyze")
        echo "Analyzing commits using Manifest Cloud service..."
        if [ -z "$MANIFEST_CLOUD_URL" ]; then
            echo "Error: MANIFEST_CLOUD_URL not set. Please configure in ~/.manifest-local/.env"
            exit 1
        fi
        
        # Use the local client to call cloud service
        node -e "
        const { ManifestCloudClient } = require('./src/client/manifestCloudClient');
        const client = new ManifestCloudClient({
            baseURL: '$MANIFEST_CLOUD_URL',
            apiKey: '$MANIFEST_CLOUD_API_KEY'
        });
        
        client.analyzeCommits(process.cwd(), { limit: 10 })
            .then(result => {
                console.log('Analysis result:', JSON.stringify(result, null, 2));
            })
            .catch(error => {
                console.error('Analysis failed:', error.message);
                process.exit(1);
            });
        "
        ;;
    "changelog")
        echo "Generating changelog using Manifest Cloud service..."
        if [ -z "$MANIFEST_CLOUD_URL" ]; then
            echo "Error: MANIFEST_CLOUD_URL not set. Please configure in ~/.manifest-local/.env"
            exit 1
        fi
        
        # Use the local client to call cloud service
        node -e "
        const { ManifestCloudClient } = require('./src/client/manifestCloudClient');
        const client = new ManifestCloudClient({
            baseURL: '$MANIFEST_CLOUD_URL',
            apiKey: '$MANIFEST_CLOUD_API_KEY'
        });
        
        client.generateChangelog(process.cwd(), { format: 'markdown' })
            .then(result => {
                console.log('Changelog generated:', result.changelog);
            })
            .catch(error => {
                console.error('Changelog generation failed:', error.message);
                process.exit(1);
            });
        "
        ;;
    "docs")
        echo "📚 Creating documentation and release notes..."
        echo ""
        
        # Check if we're in a git repository
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            echo "❌ Error: Not in a git repository"
            exit 1
        fi
        
        # Get current version
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "📋 Current version: $current_version"
        else
            echo "❌ No package.json found, cannot determine version"
            exit 1
        fi
        
        # Create docs directory if it doesn't exist
        if [ ! -d "docs" ]; then
            mkdir -p docs
            echo "📁 Created docs directory"
        fi
        
        # Generate RELEASE file
        echo "📝 Generating RELEASE_v$current_version.md..."
        cat > "docs/RELEASE_v$current_version.md" << RELEASEEOF
# Release v$current_version

## Overview
This release includes various improvements and bug fixes.

## Changes
- Version bump to $current_version
- Documentation updates
- Bug fixes and improvements

## Installation
\`\`\`bash
# Update your existing installation
git pull origin main
npm install
\`\`\`

## Breaking Changes
None

## Known Issues
None

## Contributors
Generated by Manifest CLI
RELEASEEOF
        echo "✅ RELEASE_v$current_version.md created"
        
        # Generate CHANGELOG file
        echo "📝 Generating CHANGELOG_v$current_version.md..."
        cat > "docs/CHANGELOG_v$current_version.md" << CHANGELOGEOF
# Changelog v$current_version

## [Unreleased]
### Added
- New features and improvements

### Changed
- Updates to existing functionality

### Deprecated
- Features that will be removed

### Removed
- Features that have been removed

### Fixed
- Bug fixes

### Security
- Security improvements

## [$current_version] - $(date +%Y-%m-%d)
### Added
- Initial release
- Core CLI functionality
- Git operations support
- Cloud service integration

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A
CHANGELOGEOF
        echo "✅ CHANGELOG_v$current_version.md created"
        
        # Update README.md if it exists
        if [ -f "README.md" ]; then
            echo "📝 Updating README.md..."
            # Add a changelog section if it doesn't exist
            if ! grep -q "## Changelog" README.md; then
                echo "" >> README.md
                echo "## Changelog" >> README.md
                echo "" >> README.md
                echo "See [docs/CHANGELOG_v$current_version.md](docs/CHANGELOG_v$current_version.md) for detailed changes." >> README.md
            fi
            echo "✅ README.md updated"
        fi
        
        echo ""
        echo "🎉 Documentation generated successfully!"
        echo "📁 Files created:"
        echo "   - docs/RELEASE_v$current_version.md"
        echo "   - docs/CHANGELOG_v$current_version.md"
        echo "   - README.md updated (if it exists)"
        ;;
    "diagnose")
        echo "🔍 Diagnosing common Manifest issues..."
        echo ""
        
        # Check if we're in a git repository
        if git rev-parse --git-dir > /dev/null 2>&1; then
            echo "✅ Git repository: Yes"
        else
            echo "❌ Git repository: No"
            echo "   💡 Run this command from within a git repository"
            exit 1
        fi
        
        # Check for uncommitted changes
        if ! git diff-index --quiet HEAD --; then
            echo "⚠️  Uncommitted changes: Yes"
            echo "   💡 Consider committing or stashing changes first"
        else
            echo "✅ Uncommitted changes: No"
        fi
        
        # Check remotes
        if [ -n "$(git remote)" ]; then
            echo "✅ Git remotes: $(git remote | wc -l) configured"
            for remote in $(git remote); do
                echo "   - $remote: $(git remote get-url "$remote")"
            done
        else
            echo "❌ Git remotes: None configured"
            echo "   💡 Add remotes with: git remote add origin <url>"
        fi
        
        # Check branch status
        current_branch=$(git branch --show-current)
        echo "✅ Current branch: $current_branch"
        
        # Check SSH authentication
        if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
            echo "✅ SSH authentication: Working"
        else
            echo "⚠️  SSH authentication: May have issues"
            echo "   💡 Test with: ssh -T git@github.com"
        fi
        
        # Check VERSION file
        if [ -f "VERSION" ]; then
            version_content=$(cat VERSION)
            echo "✅ VERSION file: $version_content"
        else
            echo "⚠️  VERSION file: Missing"
            echo "   💡 Will be created automatically by manifest commands"
        fi
        
        # Check Manifest Cloud configuration
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo "✅ Manifest Cloud: Configured ($MANIFEST_CLOUD_URL)"
        else
            echo "⚠️  Manifest Cloud: Not configured"
            echo "   💡 Set MANIFEST_CLOUD_URL in ~/.manifest-local/.env"
        fi
        
        echo ""
        echo "🎯 Diagnosis complete! Follow the suggestions above to fix any issues."
        ;;
    "go")
        echo "🚀 Starting automated Manifest process..."
        echo ""
        
        # Parse version increment type and flags
        increment_type="patch"  # Default to patch
        test_mode=false
        interactive_mode=false
        
        # Parse arguments
        shift  # Remove "go" from arguments
        for arg in "$@"; do
            case "$arg" in
                -patch|--patch|patch) increment_type="patch";;
                -minor|--minor|minor) increment_type="minor";;
                -major|--major|major) increment_type="major";;
                -revision|--revision|revision) increment_type="patch";;  # Alias for patch
                -p|p) increment_type="patch";;
                -m|m) increment_type="minor";;
                -M|M) increment_type="major";;
                -r|r) increment_type="patch";;  # Alias for patch
                test) test_mode=true; increment_type="patch";;
                -i|--interactive) interactive_mode=true;;
                *)
                    if [[ "$arg" != -* ]]; then
                        # Non-flag argument, treat as increment type
                        case "$arg" in
                            patch|minor|major|revision) increment_type="$arg";;
                            *) 
                                echo "Usage: manifest go [patch|minor|major|revision|test] [-i|--interactive]"
                                echo "  patch        - Increment patch version (1.0.0 -> 1.0.1)"
                                echo "  minor        - Increment minor version (1.0.0 -> 1.1.0)"
                                echo "  major        - Increment major version (1.0.0 -> 2.0.0)"
                                echo "  revision     - Alias for patch (1.0.0 -> 1.0.1)"
                                echo "  test         - Show what would happen without executing"
                                echo "  -i, --interactive - Interactive mode (confirm each step)"
                                echo ""
                                echo "Examples:"
                                echo "  manifest go                    # Default: patch increment"
                                echo "  manifest go patch             # Explicit patch increment"
                                echo "  manifest go minor -i          # Minor version bump with interactive mode"
                                echo "  manifest go major --interactive # Major version bump with interactive mode"
                                echo "  manifest go test              # Test mode - show what would happen"
                                echo "  manifest go -m -i             # Short form for minor with interactive mode"
                                exit 1
                                ;;
                        esac
                    fi
                    ;;
            esac
        done
        
        echo "📋 Version increment type: $increment_type"
        if [ "$test_mode" = true ]; then
            echo "🧪 TEST MODE: No changes will be made"
        fi
        if [ "$interactive_mode" = true ]; then
            echo "🔄 INTERACTIVE MODE: Each step will be confirmed"
        fi
        echo ""
        
        # Check if we're in a git repository
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            echo "Error: Not in a git repository"
            exit 1
        fi
        
        # Check git status
        if ! git diff-index --quiet HEAD --; then
            if [ "$test_mode" = true ]; then
                echo "📝 Uncommitted changes detected. Would commit first in real mode."
            elif [ "$interactive_mode" = true ]; then
                echo "📝 Uncommitted changes detected."
                echo "Changes to be committed:"
                git diff --name-status HEAD
                echo ""
                read -p "Commit these changes before proceeding? (y/N): " commit_confirm
                if [[ "$commit_confirm" =~ ^[Yy]$ ]]; then
                    echo "💾 Committing changes..."
                    git add .
                    git commit -m "Auto-commit before Manifest process"
                    echo "✅ Changes committed"
                else
                    echo "❌ Process cancelled by user"
                    exit 0
                fi
            else
                echo "📝 Uncommitted changes detected. Committing first..."
                git add .
                git commit -m "Auto-commit before Manifest process"
                echo "✅ Changes committed"
            fi
        else
            echo "✅ No uncommitted changes"
        fi
        
        # Analyze commits using cloud service
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo ""
            if [ "$test_mode" = true ]; then
                echo "🧠 Would analyze commits using Manifest Cloud service in real mode..."
            else
                echo "🧠 Analyzing commits using Manifest Cloud service..."
                node -e "
                const { ManifestCloudClient } = require('./src/client/manifestCloudClient');
                const client = new ManifestCloudClient({
                    baseURL: '$MANIFEST_CLOUD_URL',
                    apiKey: '$MANIFEST_CLOUD_API_KEY'
                });
                
                client.analyzeCommits(process.cwd(), { limit: 20 })
                    .then(result => {
                        console.log('📊 Analysis complete:');
                        console.log('   - Total commits analyzed:', result.commits?.length || 0);
                        console.log('   - Analysis depth:', result.metadata?.analysisDepth || 'unknown');
                        console.log('   - Operation ID:', result.metadata?.operationId || 'unknown');
                    })
                    .catch(error => {
                        console.log('⚠️  Analysis failed:', error.message);
                        console.log('   Continuing with version bump...');
                    });
                "
            fi
        else
            echo "⚠️  Manifest Cloud service not configured, skipping analysis"
        fi
        
        # Get version recommendation
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo ""
            if [ "$test_mode" = true ]; then
                echo "🎯 Would get version recommendation in real mode..."
            else
                echo "🎯 Getting version recommendation..."
                node -e "
                const { ManifestCloudClient } = require('./src/client/manifestCloudClient');
                const client = new ManifestCloudClient({
                    baseURL: '$MANIFEST_CLOUD_URL',
                    apiKey: '$MANIFEST_CLOUD_API_KEY'
                });
                
                client.getVersionRecommendation(process.cwd(), { strategy: 'semantic' })
                    .then(result => {
                        console.log('💡 Version recommendation:', result.recommendedVersion || 'patch');
                        console.log('   - Reason:', result.reason || 'Based on commit analysis');
                        console.log('   - Confidence:', result.confidence || 'unknown');
                    })
                    .catch(error => {
                        console.log('⚠️  Version recommendation failed:', error.message);
                        console.log('   Using default increment type: $increment_type');
                    });
                "
            fi
        fi
        
        # Bump version
        echo ""
        echo "📦 Bumping version..."
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "   Current version: $current_version"
            
            # Parse and increment version
            major=$(echo "$current_version" | cut -d. -f1)
            minor=$(echo "$current_version" | cut -d. -f2)
            patch=$(echo "$current_version" | cut -d. -f3)
            
            case "$increment_type" in
                patch|revision)
                    patch=$((patch + 1))
                    new_version="$major.$minor.$patch"
                    echo "   Incrementing patch version"
                    ;;
                minor)
                    minor=$((minor + 1))
                    patch=0
                    new_version="$major.$minor.$patch"
                    echo "   Incrementing minor version"
                    ;;
                major)
                    major=$((major + 1))
                    minor=0
                    patch=0
                    new_version="$major.$minor.$patch"
                    echo "   Incrementing major version"
                    ;;
            esac
            
            echo "   New version: $new_version"
            
            # Interactive confirmation for version bump
            if [ "$interactive_mode" = true ] && [ "$test_mode" = false ]; then
                echo ""
                read -p "🔄 Confirm version bump from $current_version to $new_version? (y/N): " version_confirm
                if [[ ! "$version_confirm" =~ ^[Yy]$ ]]; then
                    echo "❌ Version bump cancelled by user"
                    exit 0
                fi
                echo "✅ Version bump confirmed"
            fi
            
            if [ "$test_mode" = true ]; then
                echo "   🧪 TEST MODE: Would update package.json to $new_version"
                echo "   🧪 TEST MODE: Would update README.md if it exists"
                echo "✅ Version bump simulation complete: $new_version"
            else
                # Update package.json
                node -e "const pkg = require('./package.json'); pkg.version = '$new_version'; require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');"
                
                # Create/update VERSION file
                echo "$new_version" > VERSION
                echo "   ✅ VERSION file updated: $new_version"
                
                # Update README.md if it exists
                if [ -f "README.md" ]; then
                    sed -i.bak "s/version.*$new_version/version: $new_version/" README.md 2>/dev/null || true
                    rm -f README.md.bak 2>/dev/null || true
                fi
                
                echo "✅ Version bumped to $new_version"
            fi
        else
            echo "⚠️  No package.json found, skipping version bump"
        fi
        
        # Generate changelog
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo ""
            if [ "$test_mode" = true ]; then
                echo "📝 Would generate changelog in real mode..."
            else
                echo "📝 Generating changelog..."
                node -e "
                const { ManifestCloudClient } = require('./src/client/manifestCloudClient');
                const client = new ManifestCloudClient({
                    baseURL: '$MANIFEST_CLOUD_URL',
                    apiKey: '$MANIFEST_CLOUD_API_KEY'
                });
                
                client.generateChangelog(process.cwd(), { 
                    version: '$new_version',
                    format: 'markdown',
                    includeDetails: true 
                })
                    .then(result => {
                        console.log('✅ Changelog generated');
                        console.log('   - Format:', result.format || 'markdown');
                        console.log('   - Version:', result.version || '$new_version');
                    })
                    .catch(error => {
                        console.log('⚠️  Changelog generation failed:', error.message);
                    });
                "
            fi
        fi
        
        # Commit version changes
        if [ "$test_mode" = false ]; then
            echo ""
            if [ "$interactive_mode" = true ]; then
                echo "💾 Ready to commit version changes..."
                echo "   Files to be committed:"
                git diff --name-only --cached 2>/dev/null || git status --porcelain | grep '^[AM]' | cut -c4-
                echo ""
                read -p "🔄 Commit version changes with message 'Bump version to $new_version'? (y/N): " commit_confirm
                if [[ ! "$commit_confirm" =~ ^[Yy]$ ]]; then
                    echo "❌ Commit cancelled by user"
                    exit 0
                fi
                echo "💾 Committing version changes..."
                git add .
                git commit -m "Bump version to $new_version"
                echo "✅ Version changes committed"
            else
                echo "💾 Committing version changes..."
                git add .
                git commit -m "Bump version to $new_version"
                echo "✅ Version changes committed"
            fi
            
            # Create tag (handle conflicts gracefully)
            echo ""
            if [ "$interactive_mode" = true ]; then
                echo "🏷️  Ready to create git tag..."
                read -p "🔄 Create tag 'v$new_version' with message 'Release version $new_version'? (y/N): " tag_confirm
                if [[ ! "$tag_confirm" =~ ^[Yy]$ ]]; then
                    echo "❌ Tag creation cancelled by user"
                    exit 0
                fi
                echo "🏷️  Creating git tag..."
                if git tag -a "v$new_version" -m "Release version $new_version" 2>/dev/null; then
                    echo "✅ Tag v$new_version created"
                else
                    echo "⚠️  Tag v$new_version already exists, skipping tag creation"
                fi
            else
                echo "🏷️  Creating git tag..."
                if git tag -a "v$new_version" -m "Release version $new_version" 2>/dev/null; then
                    echo "✅ Tag v$new_version created"
                else
                    echo "⚠️  Tag v$new_version already exists, skipping tag creation"
                fi
            fi
            
            # Simple and reliable push logic
            echo ""
            if [ "$interactive_mode" = true ]; then
                echo "🚀 Ready to push to remotes..."
                echo "   Remotes to push to:"
                for remote in $(git remote); do
                    echo "   - $remote: $(git remote get-url "$remote")"
                done
                echo ""
                read -p "🔄 Push version $new_version and tag v$new_version to all remotes? (y/N): " push_confirm
                if [[ ! "$push_confirm" =~ ^[Yy]$ ]]; then
                    echo "❌ Push cancelled by user"
                    exit 0
                fi
                echo "🚀 Pushing to all remotes..."
            else
                echo "🚀 Pushing to all remotes..."
            fi
            
            push_success=true
            for remote in $(git remote); do
                echo "   Pushing to $remote..."
                remote_success=true
                
                # Try to push main branch first
                if git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || git push "$remote" "$(git branch --show-current)" 2>/dev/null; then
                    echo "   ✅ Main branch pushed successfully"
                else
                    echo "   ⚠️  Push failed, attempting to sync..."
                    
                    # Fetch latest from remote
                    if git fetch "$remote" 2>/dev/null; then
                        echo "   ✅ Fetched latest from $remote"
                        
                        # Try a simple pull and push approach
                        if git pull "$remote" main --no-edit 2>/dev/null || git pull "$remote" master --no-edit 2>/dev/null; then
                            echo "   ✅ Synced with remote"
                            echo "   🚀 Retrying push..."
                            
                            if git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || git push "$remote" "$(git branch --show-current)" 2>/dev/null; then
                                echo "   ✅ Successfully pushed after sync"
                            else
                                echo "   ❌ Push still failed after sync"
                                echo "   💡 Manual intervention required: git pull $remote main --rebase"
                                remote_success=false
                                push_success=false
                            fi
                        else
                            echo "   ❌ Failed to sync with remote"
                            echo "   💡 Manual intervention required: git pull $remote main --rebase"
                            remote_success=false
                            push_success=false
                        fi
                    else
                        echo "   ❌ Failed to fetch from remote"
                        remote_success=false
                        push_success=false
                    fi
                fi
                
                # Push tags
                if git push "$remote" --tags 2>/dev/null; then
                    echo "   ✅ Tags pushed to $remote"
                else
                    echo "   ⚠️  Tag push failed to $remote, some tags may already exist"
                    # Tag push failure doesn't fail the entire operation
                fi
                
                # Report remote status
                if [ "$remote_success" = false ]; then
                    echo "   ❌ Failed to push to $remote"
                fi
            done
            
            # Report overall push status
            if [ "$push_success" = true ]; then
                echo ""
                echo "🎉 Manifest process completed successfully!"
                echo ""
                echo "📋 Summary:"
                echo "   - Version: $new_version"
                echo "   - Tag: v$new_version"
                echo "   - Remotes: $(git remote | wc -l) pushed successfully"
                echo "   - Cloud integration: $([ -n "$MANIFEST_CLOUD_URL" ] && echo "enabled" || echo "disabled")"
            else
                echo ""
                echo "❌ Manifest process completed with errors!"
                echo ""
                echo "📋 Summary:"
                echo "   - Version: $new_version"
                echo "   - Tag: v$new_version"
                echo "   - Remotes: $(git remote | wc -l) pushed successfully"
                echo "   - Cloud integration: $([ -n "$MANIFEST_CLOUD_URL" ] && echo "enabled" || echo "disabled")"
            fi
        else
            echo ""
            echo "🧪 TEST MODE: Manifest process simulation complete!"
            echo ""
            echo "📋 What would happen:"
            echo "   - Version would be bumped to: $new_version"
            echo "   - Changes would be committed"
            echo "   - Tag v$new_version would be created"
            echo "   - Changes would be pushed to all remotes"
            echo ""
            echo "💡 Run 'manifest go $increment_type' (without 'test') to execute for real"
        fi
        ;;
    "uninstall")
        echo "🗑️  Uninstalling Manifest CLI..."
        echo ""
        
        # Check if we're running from the installed location
        if [[ "$SCRIPT_DIR" == *"/.manifest-local" ]]; then
            echo "✅ Running from installed location, proceeding with uninstall..."
        else
            echo "⚠️  Not running from installed location. This command should be run after installation."
            exit 1
        fi
        
        # Show what will be removed (based on install script)
        echo "📋 Files and directories that will be removed:"
        echo "   - CLI executable: $HOME/.local/bin/manifest"
        echo "   - Installation directory: $SCRIPT_DIR"
        echo "   - All project files (src/, examples/, package.json, etc.)"
        echo "   - Node.js dependencies (node_modules/)"
        echo "   - Configuration files (.env, .manifestrc.example)"
        echo "   - Documentation files (README.md, *.md)"
        echo "   - Docker files (Dockerfile*, docker-compose.yml)"
        echo ""
        
        # Safety check: ensure we're not trying to remove the script while it's running
        if [ "$0" = "$HOME/.local/bin/manifest" ]; then
            echo "⚠️  Safety check: This script is currently running from the CLI location"
            echo "   The uninstall will complete, but you may need to restart your terminal"
            echo "   or run 'hash -r' to clear the command cache"
        fi
        
        # Track what was actually removed
        cli_removed=false
        dir_removed=false
        bin_dir_removed=false
        
        # Remove the CLI executable
        if [ -f "$HOME/.local/bin/manifest" ]; then
            echo "🗑️  Removing CLI executable: $HOME/.local/bin/manifest"
            if rm -f "$HOME/.local/bin/manifest" 2>/dev/null; then
                echo "✅ CLI executable removed successfully"
                cli_removed=true
            else
                echo "❌ Failed to remove CLI executable"
            fi
        else
            echo "ℹ️  CLI executable not found at: $HOME/.local/bin/manifest"
        fi
        
        # Remove the installation directory
        if [ -d "$SCRIPT_DIR" ]; then
            echo "🗑️  Removing installation directory: $SCRIPT_DIR"
            if rm -rf "$SCRIPT_DIR" 2>/dev/null; then
                echo "✅ Installation directory removed successfully"
                dir_removed=true
            else
                echo "❌ Failed to remove installation directory"
            fi
        else
            echo "ℹ️  Installation directory not found at: $SCRIPT_DIR"
        fi
        
        # Remove empty .local/bin directory if it exists and is empty
        if [ -d "$HOME/.local/bin" ]; then
            if [ -z "$(ls -A "$HOME/.local/bin" 2>/dev/null)" ]; then
                echo "🗑️  Removing empty .local/bin directory"
                if rmdir "$HOME/.local/bin" 2>/dev/null; then
                    echo "✅ Empty .local/bin directory removed"
                    bin_dir_removed=true
                else
                    echo "❌ Failed to remove empty .local/bin directory"
                fi
            else
                echo "ℹ️  .local/bin directory not empty, leaving in place"
            fi
        else
            echo "ℹ️  .local/bin directory not found"
        fi
        
        # Verify uninstallation - comprehensive file-by-file check
        echo ""
        echo "🔍 Verifying uninstallation (comprehensive check)..."
        verification_passed=true
        files_remaining=()
        
        # Check CLI executable
        if [ -f "$HOME/.local/bin/manifest" ]; then
            echo "❌ CLI executable still exists at: $HOME/.local/bin/manifest"
            verification_passed=false
            files_remaining+=("CLI executable")
        fi
        
        # Check main installation directory
        if [ -d "$SCRIPT_DIR" ]; then
            echo "❌ Main installation directory still exists at: $SCRIPT_DIR"
            verification_passed=false
            files_remaining+=("Main installation directory")
        fi
        
        # Check for any remaining files in the installation location
        if [ -d "$SCRIPT_DIR" ]; then
            echo "🔍 Checking for remaining files in installation directory..."
            remaining_files=$(find "$SCRIPT_DIR" -type f -o -type d 2>/dev/null | head -20)
            if [ -n "$remaining_files" ]; then
                echo "⚠️  Found remaining files/directories:"
                echo "$remaining_files" | while read -r file; do
                    echo "   - $file"
                done
                verification_passed=false
                files_remaining+=("Remaining files in installation directory")
            fi
        fi
        
        # Check for any remaining CLI-related files in .local/bin
        if [ -d "$HOME/.local/bin" ]; then
            echo "🔍 Checking for remaining CLI files in .local/bin..."
            cli_files=$(find "$HOME/.local/bin" -name "*manifest*" 2>/dev/null)
            if [ -n "$cli_files" ]; then
                echo "⚠️  Found remaining manifest-related files:"
                echo "$cli_files" | while read -r file; do
                    echo "   - $file"
                done
                verification_passed=false
                files_remaining+=("Remaining CLI files in .local/bin")
            fi
        fi
        
        # Check for any remaining configuration files
        if [ -f "$HOME/.manifestrc" ]; then
            echo "⚠️  Global configuration file still exists: $HOME/.manifestrc"
            files_remaining+=("Global configuration file")
        fi
        
        # Check for any remaining environment files
        if [ -f "$HOME/.env" ]; then
            echo "⚠️  Global environment file still exists: $HOME/.env"
            files_remaining+=("Global environment file")
        fi
        
        # Check for any remaining shell configuration additions
        if [ -f "$HOME/.zshrc" ] && grep -q "manifest-local" "$HOME/.zshrc" 2>/dev/null; then
            echo "⚠️  PATH modification still exists in ~/.zshrc"
            files_remaining+=("PATH modification in .zshrc")
        fi
        
        if [ -f "$HOME/.bashrc" ] && grep -q "manifest-local" "$HOME/.bashrc" 2>/dev/null; then
            echo "⚠️  PATH modification still exists in ~/.bashrc"
            files_remaining+=("PATH modification in .bashrc")
        fi
        
        # Summary of verification
        if [ "$verification_passed" = true ] && [ ${#files_remaining[@]} -eq 0 ]; then
            echo "✅ Comprehensive verification passed - all files removed successfully"
        else
            echo "⚠️  Verification found remaining items:"
            for item in "${files_remaining[@]}"; do
                echo "   - $item"
            done
        fi
        
        # Summary
        echo ""
        if [ "$cli_removed" = true ] || [ "$dir_removed" = true ]; then
            echo "🎉 Manifest CLI uninstallation completed!"
            if [ "$cli_removed" = true ]; then
                echo "   - CLI executable: Removed"
            fi
            if [ "$dir_removed" = true ]; then
                echo "   - Installation directory: Removed"
            fi
            if [ "$bin_dir_removed" = true ]; then
                echo "   - Empty .local/bin directory: Removed"
            fi
        else
            echo "ℹ️  No files were removed (they may not have existed)"
        fi
        
        echo ""
        echo "💡 Note: You may need to restart your terminal or run 'hash -r' to clear command cache"
        echo "💡 To reinstall, run: bash install-cli.sh from the source repository"
        ;;
    "selfupdate")
        echo "🔄 Self-updating Manifest CLI..."
        echo ""
        
        # Check if we're running from the installed location
        if [[ "$SCRIPT_DIR" == *"/.manifest-local" ]]; then
            echo "✅ Running from installed location, proceeding with self-update..."
        else
            echo "⚠️  Not running from installed location. This command should be run after installation."
            exit 1
        fi
        
        # Get the current version
        if [ -f "$SCRIPT_DIR/package.json" ]; then
            current_version=$(node -p "require('$SCRIPT_DIR/package.json').version")
            echo "📋 Current version: $current_version"
        else
            echo "⚠️  Could not determine current version"
            current_version="unknown"
        fi
        
        # Check if we're in a git repository (the source repo)
        if git rev-parse --git-dir > /dev/null 2>&1; then
            echo "📁 Running from source repository, updating from local changes..."
            
            # Check for uncommitted changes
            if ! git diff-index --quiet HEAD --; then
                echo "📝 Uncommitted changes detected. Please commit or stash them first."
                exit 1
            fi
            
            # Pull latest changes
            if git pull origin main 2>/dev/null || git pull origin master 2>/dev/null; then
                echo "✅ Pulled latest changes from remote"
            else
                echo "⚠️  Failed to pull from remote, continuing with local changes"
            fi
            
            # Reinstall the CLI
            echo "🔄 Reinstalling CLI with latest changes..."
            if [ -f "install-cli.sh" ]; then
                bash install-cli.sh
                echo "✅ CLI reinstalled successfully"
            else
                echo "❌ install-cli.sh not found in current directory"
                exit 1
            fi
        else
            echo "📁 Not running from source repository"
            echo "💡 To update, please run this command from the fidenceio.manifest.local repository"
            exit 1
        fi
        
        # Show new version
        if [ -f "$SCRIPT_DIR/package.json" ]; then
            new_version=$(node -p "require('$SCRIPT_DIR/package.json').version")
            if [ "$new_version" != "$current_version" ]; then
                echo ""
                echo "🎉 Updated from version $current_version to $new_version!"
            else
                echo ""
                echo "✅ CLI is up to date (version $new_version)"
            fi
        fi
        ;;
    "help"|*)
        echo "Manifest Local CLI"
        echo ""
        echo "Usage: manifest <command>"
        echo ""
        echo "Commands:"
        echo "  go        - 🚀 Automated Manifest process (recommended)"
        echo "    go [patch|minor|major|revision|test] [-i]  # Specify version increment, test mode, or interactive"
        echo "    go -p|-m|-M|-r [-i]                        # Short form options with interactive mode"
        echo "  revert    - 🔄 Revert to previous version"
        echo "  push      - Version bump, commit, and push changes"
        echo "  commit    - Commit changes with custom message"
        echo "  version   - Bump version (patch/minor/major)"
        echo "  analyze   - Analyze commits using cloud service"
        echo "  changelog - Generate changelog using cloud service"
        echo "  docs      - 📚 Create documentation and release notes"
        echo "  diagnose  - 🔍 Diagnose and fix common issues"
        echo "  uninstall - 🗑️  Remove Manifest CLI from system"
        echo "  selfupdate- 🔄 Update CLI to latest version"
        echo "  help      - Show this help"
        echo ""
        echo "This CLI provides local Git operations and integrates with"
        echo "the Manifest Cloud service for LLM-powered analysis."
        ;;
esac
