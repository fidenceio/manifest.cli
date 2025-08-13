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
    # Check if tap repo exists
    TAP_DIR="../fidenceio-homebrew-tap"
    if [ ! -d "$TAP_DIR" ]; then
        print_warning "Tap directory not found at $TAP_DIR"
        print_status "Please manually copy the updated formula to your tap repository"
        return 0
    fi
    
    # Copy updated formula to tap
    cp "$FORMULA_FILE" "$TAP_DIR/Formula/"
    
    # Navigate to tap directory and commit
    cd "$TAP_DIR"
    
    # Check if there are changes
    if git diff --quiet Formula/; then
        print_warning "No changes detected in tap repository"
    else
        git add Formula/
        git commit -m "Update manifest formula to v$CURRENT_VERSION"
        git push
        
        print_success "✅ Homebrew tap updated and pushed successfully"
    fi
    
    # Go back to CLI repo
    cd "../fidenceio.manifest.cli"
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

# Create backup
cp "$FORMULA_FILE" "${FORMULA_FILE}.backup"

# Update version in formula
sed -i.tmp "s|url \".*manifest.cli/archive/refs/tags/v.*\.tar\.gz\"|url \"https://github.com/fidenceio/manifest.cli/archive/refs/tags/v$CURRENT_VERSION.tar.gz\"|" "$FORMULA_FILE"

# Update SHA256
sed -i.tmp "s|sha256 \".*\"|sha256 \"$NEW_SHA256\"|" "$FORMULA_FILE"

# Update version in test section
sed -i.tmp "s|assert_match \".*\"|assert_match \"$CURRENT_VERSION\"|" "$FORMULA_FILE"

# Clean up temp files
rm -f "${FORMULA_FILE}.tmp"

print_success "✅ Formula file updated successfully"

# Show the changes
print_status "📋 Changes made:"
echo "   Version: $CURRENT_VERSION"
echo "   SHA256: $NEW_SHA256"
echo "   Formula: $FORMULA_FILE"

# Check if we should also update the tap repository
# If run from CLI workflow (non-interactive), automatically update tap
# If run manually, ask user
if [ -t 0 ] && [ -z "$MANIFEST_NONINTERACTIVE" ]; then
    # Interactive mode - ask user
    read -p "🤔 Do you want to also update the Homebrew tap repository? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        update_tap_repository
    fi
else
    # Non-interactive mode - automatically update tap
    print_status "🔄 Automatically updating Homebrew tap repository..."
    update_tap_repository
fi

print_success "🎉 Homebrew formula update complete!"
print_status "💡 Users can now update with: brew upgrade manifest"
