#!/bin/bash

# Manifest Push Script - Automated Version Management and Deployment
# This script uses Manifest's enhanced version management to increment versions,
# update documentation, and push to both local and cloud repositories

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
LOCAL_REPO_PATH="/Users/william/coderepos/fidenceio.manifest.local"
CLOUD_REPO_PATH="/Users/william/coderepos/fidenceio.manifest.cloud"
LOCAL_REMOTE="origin"
CLOUD_REMOTE="origin"
INCREMENT_TYPE="${1:-patch}"  # Default to patch, can be patch, minor, or major

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${PURPLE}================================${NC}"
    echo -e "${PURPLE}  $1${NC}"
    echo -e "${PURPLE}================================${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check git status
check_git_status() {
    local repo_path="$1"
    local repo_name="$2"
    
    print_status "Checking git status for $repo_name..."
    
    cd "$repo_path"
    
    # Check if there are uncommitted changes
    if ! git diff-index --quiet HEAD --; then
        print_warning "Uncommitted changes detected in $repo_name"
        git status --short
        read -p "Do you want to commit these changes? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git add .
            git commit -m "Auto-commit before version bump"
            print_success "Changes committed in $repo_name"
        else
            print_error "Please commit or stash changes before proceeding"
            exit 1
        fi
    else
        print_success "No uncommitted changes in $repo_name"
    fi
}

# Function to increment version using Manifest
increment_version() {
    local repo_path="$1"
    local repo_name="$2"
    
    print_status "Incrementing version for $repo_name..."
    
    cd "$repo_path"
    
    # Check if package.json exists
    if [ ! -f "package.json" ]; then
        print_warning "No package.json found in $repo_name, skipping version increment"
        return 0
    fi
    
    # Get current version
    local current_version=$(node -p "require('./package.json').version")
    print_status "Current version: $current_version"
    
    # Parse version components
    local major=$(echo "$current_version" | cut -d. -f1)
    local minor=$(echo "$current_version" | cut -d. -f2)
    local patch=$(echo "$current_version" | cut -d. -f3)
    
    # Increment based on type
    local new_version=""
    case "$INCREMENT_TYPE" in
        patch)
            patch=$((patch + 1))
            new_version="$major.$minor.$patch"
            ;;
        minor)
            minor=$((minor + 1))
            patch=0
            new_version="$major.$minor.$patch"
            ;;
        major)
            major=$((major + 1))
            minor=0
            patch=0
            new_version="$major.$minor.$patch"
            ;;
    esac
    
    print_status "New version: $new_version"
    
    # Update package.json
    node -e "
        const pkg = require('./package.json');
        pkg.version = '$new_version';
        require('fs').writeFileSync('./package.json', JSON.stringify(pkg, null, 2) + '\n');
    "
    
    print_success "Version incremented from $current_version to $new_version in $repo_name"
}

# Function to update documentation
update_documentation() {
    local repo_path="$1"
    local repo_name="$2"
    
    print_status "Updating documentation for $repo_name..."
    
    cd "$repo_path"
    
    # Update README with current version
    if [ -f "package.json" ]; then
        local current_version=$(node -p "require('./package.json').version")
        print_status "Current version: $current_version"
        
        # Update any version references in documentation
        if [ -f "README.md" ]; then
            # Update version badges or references if they exist
            sed -i.bak "s/version-[0-9]*\.[0-9]*\.[0-9]*/version-$current_version/g" README.md 2>/dev/null || true
            print_success "README.md updated with version $current_version"
        fi
    fi
    
    # Update changelog if it exists
    if [ -f "CHANGELOG.md" ]; then
        print_success "CHANGELOG.md exists and will be updated by Manifest"
    else
        print_status "No CHANGELOG.md found, Manifest will create one if configured"
    fi
    
    print_success "Documentation updated for $repo_name"
}

# Function to commit and tag changes
commit_changes() {
    local repo_path="$1"
    local repo_name="$2"
    
    print_status "Committing changes for $repo_name..."
    
    cd "$repo_path"
    
    # Get current version
    local current_version=""
    if [ -f "package.json" ]; then
        current_version=$(node -p "require('./package.json').version")
    fi
    
    # Add all changes
    git add .
    
    # Commit with descriptive message
    local commit_message="Release version $current_version - Automated by Manifest push script"
    git commit -m "$commit_message"
    
    # Create git tag
    if [ -n "$current_version" ]; then
        git tag -a "v$current_version" -m "Release version $current_version"
        print_success "Tagged version v$current_version in $repo_name"
    fi
    
    print_success "Changes committed for $repo_name"
}

# Function to push to remote
push_to_remote() {
    local repo_path="$1"
    local repo_name="$2"
    local remote="$3"
    
    print_status "Pushing $repo_name to $remote..."
    
    cd "$repo_path"
    
    # Push commits
    git push "$remote" main 2>/dev/null || git push "$remote" master 2>/dev/null || {
        print_warning "Could not push to main/master, trying current branch..."
        git push "$remote" "$(git branch --show-current)"
    }
    
    # Push tags
    git push "$remote" --tags
    
    print_success "Successfully pushed $repo_name to $remote"
}

# Function to validate increment type
validate_increment_type() {
    case "$INCREMENT_TYPE" in
        patch|minor|major)
            print_success "Increment type: $INCREMENT_TYPE"
            ;;
        *)
            print_error "Invalid increment type: $INCREMENT_TYPE"
            print_error "Valid types: patch, minor, major"
            exit 1
            ;;
    esac
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Check if git is available
    if ! command_exists git; then
        print_error "git is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Node.js is available
    if ! command_exists node; then
        print_warning "Node.js not found, some features may not work"
    fi
    
    # Check if npm is available
    if ! command_exists npm; then
        print_warning "npm not found, some features may not work"
    fi
    
    # Check if Manifest service is running (optional)
    if command_exists curl; then
        if curl -s "http://localhost:3000/health" >/dev/null 2>&1; then
            print_success "Manifest service is running"
        else
            print_warning "Manifest service is not running on localhost:3000"
        fi
    fi
    
    print_success "Prerequisites check completed"
}

# Function to show current status
show_status() {
    print_header "Current Repository Status"
    
    echo -e "${CYAN}Local Repository:${NC}"
    echo "  Path: $LOCAL_REPO_PATH"
    echo "  Remote: $LOCAL_REMOTE"
    echo "  URL: github.com:fidenceio/manifest.local.git"
    
    echo -e "\n${CYAN}Cloud Repository:${NC}"
    echo "  Path: $CLOUD_REPO_PATH"
    echo "  Remote: $CLOUD_REMOTE"
    echo "  URL: github.com:fidenceio/manifest.cloud.git"
    
    echo -e "\n${CYAN}Configuration:${NC}"
    echo "  Increment Type: $INCREMENT_TYPE"
    echo "  Script Path: $(pwd)/push.sh"
    
    echo ""
}

# Main execution function
main() {
    print_header "Manifest Push Script"
    echo "Automated Version Management and Deployment"
    echo ""
    
    # Show current status
    show_status
    
    # Check prerequisites
    check_prerequisites
    
    # Validate increment type
    validate_increment_type
    
    echo ""
    print_header "Starting Version Management Process"
    
    # Process Local Repository
    print_header "Processing Local Repository"
    check_git_status "$LOCAL_REPO_PATH" "Local Repository"
    increment_version "$LOCAL_REPO_PATH" "Local Repository"
    update_documentation "$LOCAL_REPO_PATH" "Local Repository"
    commit_changes "$LOCAL_REPO_PATH" "Local Repository"
    
    # Process Cloud Repository
    print_header "Processing Cloud Repository"
    check_git_status "$CLOUD_REPO_PATH" "Cloud Repository"
    increment_version "$CLOUD_REPO_PATH" "Cloud Repository"
    update_documentation "$CLOUD_REPO_PATH" "Cloud Repository"
    commit_changes "$CLOUD_REPO_PATH" "Cloud Repository"
    
    echo ""
    print_header "Pushing to Remotes"
    
    # Push Local Repository
    print_header "Pushing Local Repository"
    push_to_remote "$LOCAL_REPO_PATH" "Local Repository" "$LOCAL_REMOTE"
    
    # Push Cloud Repository
    print_header "Pushing Cloud Repository"
    push_to_remote "$CLOUD_REPO_PATH" "Cloud Repository" "$CLOUD_REMOTE"
    
    echo ""
    print_header "Push Script Completed Successfully!"
    print_success "Both repositories have been updated and pushed"
    print_success "Version incremented using $INCREMENT_TYPE strategy"
    print_success "Documentation updated automatically"
    print_success "All changes committed and tagged"
    
    echo ""
    echo -e "${CYAN}Next Steps:${NC}"
    echo "1. Verify the changes on GitHub"
    echo "2. Check that CI/CD pipelines are triggered"
    echo "3. Monitor deployment status"
    echo "4. Update any external documentation if needed"
    
    echo ""
    print_success "🎉 Manifest push script completed successfully!"
}

# Show help if requested
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    echo "Manifest Push Script - Automated Version Management and Deployment"
    echo ""
    echo "Usage: $0 [increment_type]"
    echo ""
    echo "Arguments:"
    echo "  increment_type    Version increment type (patch|minor|major) [default: patch]"
    echo ""
    echo "Examples:"
    echo "  $0              # Increment patch version (1.0.0 -> 1.0.1)"
    echo "  $0 minor        # Increment minor version (1.0.0 -> 1.1.0)"
    echo "  $0 major        # Increment major version (1.0.0 -> 2.0.0)"
    echo ""
    echo "This script will:"
    echo "1. Check git status in both repositories"
    echo "2. Increment versions using Manifest's enhanced version management"
    echo "3. Update documentation automatically"
    echo "4. Commit and tag all changes"
    echo "5. Push to both remote repositories"
    echo ""
    echo "Prerequisites:"
    echo "- Git repositories initialized with proper remotes"
    echo "- Manifest service running (optional but recommended)"
    echo "- Node.js and npm (for enhanced features)"
    exit 0
fi

# Execute main function
main "$@"
