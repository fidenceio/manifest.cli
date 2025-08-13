#!/bin/bash

# Update Homebrew Formula Script
# Automatically updates the Homebrew formula with new version, URL, and SHA256

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to update tap repository
update_tap_repository() {
    # Check if tap repository is configured
    if [ -z "$MANIFEST_TAP_REPO" ]; then
        print_warning "MANIFEST_TAP_REPO not set, skipping tap repository update"
        print_status "Set MANIFEST_TAP_REPO to enable automatic tap updates"
        return 0
    fi
    
    print_status "🔄 Updating tap repository: $MANIFEST_TAP_REPO"
    
    # Create a temporary directory for the tap repo
    local temp_tap_dir="/tmp/manifest-tap-$$"
    print_status "📁 Creating temporary directory: $temp_tap_dir"
    mkdir -p "$temp_tap_dir"
    
    # Clone the tap repository with timeout
    print_status "📥 Cloning tap repository..."
    if timeout 30s git clone "$MANIFEST_TAP_REPO" "$temp_tap_dir" 2>/dev/null; then
        print_status "✅ Repository cloned successfully"
        
        # Copy updated formula to temp tap repo
        print_status "📋 Copying formula to temporary repository..."
        cp "$FORMULA_FILE" "$temp_tap_dir/Formula/"
        
        # Navigate to temp tap directory
        cd "$temp_tap_dir"
        
        # Check if there are changes
        print_status "🔍 Checking for changes..."
        if git diff --quiet Formula/; then
            print_warning "No changes detected in tap repository"
        else
            print_status "📝 Committing changes..."
            git add Formula/
            git commit -m "Update manifest formula to v$CURRENT_VERSION"
            
            # Push to the tap repository with timeout
            print_status "🚀 Pushing to tap repository..."
            if timeout 30s git push origin main; then
                print_success "✅ Homebrew tap updated and pushed successfully"
            else
                print_warning "⚠️  Failed to push to tap repository (continuing anyway)"
            fi
        fi
        
        # Go back to CLI repo
        cd - > /dev/null
        
        # Clean up temp directory
        print_status "🧹 Cleaning up temporary directory..."
        rm -rf "$temp_tap_dir"
    else
        print_warning "⚠️  Failed to clone tap repository: $MANIFEST_TAP_REPO"
        print_status "Skipping tap repository update"
        
        # Go back to CLI repo
        cd - > /dev/null
        
        # Clean up temp directory
        rm -rf "$temp_tap_dir"
    fi
}

# Check if we're in the right directory
if [ ! -f "VERSION" ]; then
    print_error "This script must be run from the manifest.cli project root directory"
    exit 1
fi

# Get current version
CURRENT_VERSION=$(cat VERSION)
if [ -z "$CURRENT_VERSION" ]; then
    print_error "Could not read current version from VERSION file"
    exit 1
fi

# Check if Homebrew functionality is completely disabled
if [ "$MANIFEST_BREW_OPTION" = "disabled" ] || [ "$MANIFEST_BREW_OPTION" = "false" ] || [ "$MANIFEST_BREW_OPTION" = "0" ]; then
    print_warning "Homebrew functionality is disabled (MANIFEST_BREW_OPTION=$MANIFEST_BREW_OPTION)"
    print_status "Exiting without updating Homebrew formula"
    exit 0
fi

print_status "🔄 Updating Homebrew formula for version $CURRENT_VERSION"

# Check if Formula directory exists
if [ ! -d "Formula" ]; then
    print_error "Formula directory not found. Please create it first."
    exit 1
fi

# Determine formula file name
FORMULA_FILE=""
if [ -f "Formula/manifest.rb" ]; then
    FORMULA_FILE="Formula/manifest.rb"
elif [ -f "Formula/manifest-cli.rb" ]; then
    FORMULA_FILE="Formula/manifest-cli.rb"
else
    print_error "No formula file found in Formula directory"
    exit 1
fi

print_status "📁 Using formula file: $FORMULA_FILE"

# Calculate new SHA256 for the release
print_status "🔍 Calculating SHA256 for v$CURRENT_VERSION..."
NEW_SHA256=$(curl -sL "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v$CURRENT_VERSION.tar.gz" | shasum -a 256 | cut -d' ' -f1)

if [ -z "$NEW_SHA256" ]; then
    print_error "Failed to calculate SHA256 for v$CURRENT_VERSION"
    exit 1
fi

print_success "✅ SHA256: $NEW_SHA256"

    # Update the formula file
    print_status "📝 Updating formula file..."

# Update version in formula
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: use BSD sed
    sed -i.tmp "s|url \".*manifest.cli/archive/refs/tags/v.*\.tar\.gz\"|url \"https://github.com/fidenceio/manifest.cli/archive/refs/tags/v$CURRENT_VERSION.tar.gz\"|" "$FORMULA_FILE"
    sed -i.tmp "s|sha256 \".*\"|sha256 \"$NEW_SHA256\"|" "$FORMULA_FILE"
    sed -i.tmp "s|assert_match \".*\"|assert_match \"$CURRENT_VERSION\"|" "$FORMULA_FILE"
    # Clean up temp files
    rm -f "${FORMULA_FILE}.tmp"
else
    # Linux: use GNU sed
    sed -i "s|url \".*manifest.cli/archive/refs/tags/v.*\.tar\.gz\"|url \"https://github.com/fidenceio/manifest.cli/archive/refs/tags/v$CURRENT_VERSION.tar.gz\"|" "$FORMULA_FILE"
    sed -i "s|sha256 \".*\"|sha256 \"$NEW_SHA256\"|" "$FORMULA_FILE"
    sed -i "s|assert_match \".*\"|assert_match \"$CURRENT_VERSION\"|" "$FORMULA_FILE"
fi

print_success "✅ Formula file updated successfully"

# Show the changes
print_status "📋 Changes made:"
echo "   Version: $CURRENT_VERSION"
echo "   SHA256: $NEW_SHA256"
echo "   Formula: $FORMULA_FILE"

# Check if Homebrew functionality is enabled
if [ "$MANIFEST_BREW_OPTION" = "disabled" ] || [ "$MANIFEST_BREW_OPTION" = "false" ] || [ "$MANIFEST_BREW_OPTION" = "0" ]; then
    print_warning "Homebrew functionality is disabled (MANIFEST_BREW_OPTION=$MANIFEST_BREW_OPTION)"
    print_status "Skipping Homebrew tap repository update"
elif [ "$MANIFEST_BREW_OPTION" = "enabled" ] || [ "$MANIFEST_BREW_OPTION" = "true" ] || [ "$MANIFEST_BREW_OPTION" = "1" ] || [ -z "$MANIFEST_BREW_OPTION" ]; then
    # Homebrew functionality is enabled (default behavior)
    if [ -t 0 ] && [ "$MANIFEST_BREW_INTERACTIVE" = "yes" ] || [ "$MANIFEST_BREW_INTERACTIVE" = "true" ] || [ "$MANIFEST_BREW_INTERACTIVE" = "1" ]; then
        # Interactive mode - ask user
        read -p "🤔 Do you want to also update the Homebrew tap repository? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_tap_repository
        fi
    else
        # Non-interactive mode - automatically update tap (default)
        print_status "🔄 Automatically updating Homebrew tap repository..."
        update_tap_repository
    fi
else
    print_warning "Unknown MANIFEST_BREW_OPTION value: $MANIFEST_BREW_OPTION"
    print_status "Defaulting to enabled behavior"
    
    if [ -t 0 ] && [ "$MANIFEST_BREW_INTERACTIVE" = "yes" ] || [ "$MANIFEST_BREW_INTERACTIVE" = "true" ] || [ "$MANIFEST_BREW_INTERACTIVE" = "1" ]; then
        # Interactive mode - ask user
        read -p "🤔 Do you want to also update the Homebrew tap repository? (y/N): " -n 1 -r
        echo
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            update_tap_repository
        fi
    else
        # Non-interactive mode - automatically update tap (default)
        print_status "🔄 Automatically updating Homebrew tap repository..."
        update_tap_repository
    fi
fi

print_success "🎉 Homebrew formula update complete!"
print_status "💡 Users can now update with: brew upgrade manifest"
