#!/bin/bash

# Manifest Local CLI Installer
# Installs the local development CLI for Git operations and cloud service integration

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.manifest-local"
BIN_DIR="$HOME/.local/bin"

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')]${NC} $1"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
}

# Header
echo "=========================================="
echo "   Manifest Local CLI Installer"
echo "=========================================="
echo ""

# Check prerequisites
log "Checking prerequisites..."

# Check Node.js
if ! command -v node &> /dev/null; then
    error "Node.js is not installed. Please install Node.js first."
    exit 1
fi
success "Node.js is available"

# Check Git
if ! command -v git &> /dev/null; then
    error "Git is not installed. Please install Git first."
    exit 1
fi
success "Git is available"

echo ""

# Create installation directory
log "Creating installation directory..."
mkdir -p "$INSTALL_DIR"
mkdir -p "$BIN_DIR"
success "Installation directory created: $INSTALL_DIR"

# Copy project files
log "Copying project files..."
cp -r "$SCRIPT_DIR/src" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/examples" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/package.json" "$INSTALL_DIR/"
cp "$SCRIPT_DIR/README.md" "$INSTALL_DIR/"
success "Project files copied"

# Install Node.js dependencies
log "Installing Node.js dependencies..."
cd "$INSTALL_DIR"
npm install --only=production
success "Node.js dependencies installed"

# Create default configuration
log "Creating default configuration..."
cat > "$INSTALL_DIR/.env" << 'ENVEOF'
# Manifest Local Configuration
MANIFEST_CLOUD_URL=http://localhost:3001
MANIFEST_CLOUD_API_KEY=your-api-key-here

# Git Configuration
GIT_AUTO_COMMIT=true
GIT_AUTO_TAG=true
GIT_PUSH_ALL_REMOTES=true
ENVEOF
success "Default configuration created"

# Create Manifest Local CLI
log "Creating Manifest Local CLI..."
cat > "$BIN_DIR/manifest" << 'CLIEOF'
#!/bin/bash

# Manifest Local CLI
# Local development tool for Git operations and cloud service integration

set -e

SCRIPT_DIR="$HOME/.manifest-local"
cd "$SCRIPT_DIR"

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
            
            # Update README.md if it exists
            if [ -f "README.md" ]; then
                sed -i.bak "s/version.*$new_version/version: $new_version/" README.md 2>/dev/null || true
                rm -f README.md.bak 2>/dev/null || true
            fi
        fi
        
        # Commit version changes
        git add .
        git commit -m "Bump version to $new_version"
        
        # Create tag
        git tag -a "v$new_version" -m "Release version $new_version"
        
        # Push to all remotes
        for remote in $(git remote); do
            echo "Pushing to $remote..."
            git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || git push "$remote" "$(git branch --show-current)"
            git push "$remote" --tags
        done
        
        echo "Successfully pushed version $new_version to all remotes"
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
            echo "📝 Uncommitted changes detected. Committing first..."
            git add .
            git commit -m "Auto-commit before revert"
            echo "✅ Changes committed"
        else
            echo "✅ No uncommitted changes"
        fi
        
        # Get git tags sorted by version
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "   Current version: $current_version"
            
            # Get all available versions from git tags
            echo ""
            echo "📋 Available versions to revert to:"
            available_versions=($(git tag --sort=-version:refname | grep -v "v$current_version" | head -10))
            
            if [ ${#available_versions[@]} -eq 0 ]; then
                echo "⚠️  No previous versions found in git tags"
                echo "   Current version will remain: $current_version"
                exit 1
            fi
            
            # Display available versions with numbers
            for i in "${!available_versions[@]}"; do
                version=${available_versions[$i]#v}
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
            
            # Create tag
            echo ""
            echo "🏷️  Creating git tag..."
            git tag -a "v$previous_version" -m "Revert to version $previous_version"
            echo "✅ Tag v$previous_version created"
            
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
        else
            echo "⚠️  No package.json found, cannot revert version"
            exit 1
        fi
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
    "go")
        echo "🚀 Starting automated Manifest process..."
        echo ""
        
        # Parse version increment type
        increment_type="patch"  # Default to patch
        if [ -n "$2" ]; then
            case "$2" in
                -patch|--patch|patch) increment_type="patch";;
                -minor|--minor|minor) increment_type="minor";;
                -major|--major|major) increment_type="major";;
                -revision|--revision|revision) increment_type="patch";;  # Alias for patch
                -p|p) increment_type="patch";;
                -m|m) increment_type="minor";;
                -M|M) increment_type="major";;
                -r|r) increment_type="patch";;  # Alias for patch
                *)
                    echo "Usage: manifest go [patch|minor|major|revision]"
                    echo "  patch     - Increment patch version (1.0.0 -> 1.0.1)"
                    echo "  minor     - Increment minor version (1.0.0 -> 1.1.0)"
                    echo "  major     - Increment major version (1.0.0 -> 2.0.0)"
                    echo "  revision  - Alias for patch (1.0.0 -> 1.0.1)"
                    echo ""
                    echo "Examples:"
                    echo "  manifest go        # Default: patch increment"
                    echo "  manifest go patch  # Explicit patch increment"
                    echo "  manifest go minor  # Minor version bump"
                    echo "  manifest go major  # Major version bump"
                    echo "  manifest go -m     # Short form for minor"
                    exit 1
                    ;;
            esac
        fi
        
        echo "📋 Version increment type: $increment_type"
        echo ""
        
        # Check if we're in a git repository
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            echo "Error: Not in a git repository"
            exit 1
        fi
        
        # Check git status
        if ! git diff-index --quiet HEAD --; then
            echo "📝 Uncommitted changes detected. Committing first..."
            git add .
            git commit -m "Auto-commit before Manifest process"
            echo "✅ Changes committed"
        else
            echo "✅ No uncommitted changes"
        fi
        
        # Analyze commits using cloud service
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo ""
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
        else
            echo "⚠️  Manifest Cloud service not configured, skipping analysis"
        fi
        
        # Get version recommendation
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo ""
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
                    console.log('   - Confidence:', result.confidence || 'medium');
                })
                .catch(error => {
                    console.log('⚠️  Version recommendation failed:', error.message);
                    console.log('   Using default patch increment...');
                });
            "
        fi
        
        # Bump version using specified increment type
        echo ""
        echo "📦 Bumping version..."
        if [ -f "package.json" ]; then
            current_version=$(node -p "require('./package.json').version")
            echo "   Current version: $current_version"
            
            # Parse and increment version based on increment type
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
            
            # Update package.json
            node -e "const pkg = require('./package.json'); pkg.version = '$new_version'; require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');"
            
            # Update README.md if it exists
            if [ -f "README.md" ]; then
                sed -i.bak "s/version.*$new_version/version: $new_version/" README.md 2>/dev/null || true
                rm -f README.md.bak 2>/dev/null || true
            fi
            
            echo "✅ Version bumped to $new_version"
        else
            echo "⚠️  No package.json found, skipping version bump"
        fi
        
        # Generate changelog
        if [ -n "$MANIFEST_CLOUD_URL" ]; then
            echo ""
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
        
        # Commit version changes
        echo ""
        echo "💾 Committing version changes..."
        git add .
        git commit -m "Bump version to $new_version"
        echo "✅ Version changes committed"
        
        # Create tag
        echo ""
        echo "🏷️  Creating git tag..."
        git tag -a "v$new_version" -m "Release version $new_version"
        echo "✅ Tag v$new_version created"
        
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
        echo "🎉 Manifest process completed successfully!"
        echo ""
        echo "📋 Summary:"
        echo "   - Version: $new_version"
        echo "   - Tag: v$new_version"
        echo "   - Remotes: $(git remote | wc -l) pushed"
        echo "   - Cloud integration: $([ -n "$MANIFEST_CLOUD_URL" ] && echo "enabled" || echo "disabled")"
        ;;
    "help"|*)
        echo "Manifest Local CLI"
        echo ""
        echo "Usage: manifest <command>"
        echo ""
        echo "Commands:"
        echo "  go        - 🚀 Automated Manifest process (recommended)"
        echo "    go [patch|minor|major|revision]  # Specify version increment"
        echo "    go -p|-m|-M|-r                   # Short form options"
        echo "  revert    - 🔄 Revert to previous version"
        echo "  push      - Version bump, commit, and push changes"
        echo "  commit    - Commit changes with custom message"
        echo "  version   - Bump version (patch/minor/major)"
        echo "  analyze   - Analyze commits using cloud service"
        echo "  changelog - Generate changelog using cloud service"
        echo "  help      - Show this help"
        echo ""
        echo "This CLI provides local Git operations and integrates with"
        echo "the Manifest Cloud service for LLM-powered analysis."
        ;;
esac
CLIEOF

chmod +x "$BIN_DIR/manifest"
success "Manifest Local CLI created: $BIN_DIR/manifest"

# Add to PATH if not already there
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
    log "Adding $BIN_DIR to PATH..."
    echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.zshrc"
    echo "export PATH=\"\$PATH:$BIN_DIR\"" >> "$HOME/.bashrc"
    warning "Please restart your terminal or run 'source ~/.zshrc' to use the CLI"
fi

echo ""
log "Installation completed successfully!"
echo ""

# Verification
log "Verifying installation..."
if [ -f "$BIN_DIR/manifest" ]; then
    success "Manifest Local CLI is accessible"
else
    error "Manifest Local CLI installation failed"
    exit 1
fi

if [ -f "$INSTALL_DIR/package.json" ]; then
    success "Project files are ready"
else
    error "Project files are missing"
    exit 1
fi

echo ""
echo "=========================================="
echo "   Installation Summary"
echo "=========================================="
echo "Installation Directory: $INSTALL_DIR"
echo "CLI Location: $BIN_DIR/manifest"
echo "Configuration: $INSTALL_DIR/.env"
echo ""

echo "Next steps:"
echo "1. Configure your cloud service URL in $INSTALL_DIR/.env"
echo "2. Use manifest CLI for Git operations: manifest help"
echo "3. Integrate with Manifest Cloud service for LLM features"
echo ""

echo -e "${GREEN}Installation completed! 🎉${NC}"
echo ""
echo "For help, run: manifest help"
echo ""
echo "Note: This CLI is for local development and Git operations."
echo "It integrates with the Manifest Cloud service for LLM capabilities."
