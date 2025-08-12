#!/bin/bash

# Manifest CLI Homebrew Release Script
# This script helps prepare a release for Homebrew installation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REPO_NAME="fidenceio/manifest.local"
FORMULA_DIR="homebrew"
VERSION=$(node -p "require('../package.json').version")
TARBALL_NAME="manifest-${VERSION}.tar.gz"
RELEASE_URL="https://github.com/${REPO_NAME}/archive/refs/tags/v${VERSION}.tar.gz"

echo -e "${BLUE}🚀 Manifest CLI Homebrew Release Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if we're in the right directory
if [ ! -f "Formula/manifest.rb" ]; then
    echo -e "${RED}❌ Error: This script must be run from the Formula directory${NC}"
    echo "   Current directory: $(pwd)"
    echo "   Expected: .../Formula/"
    exit 1
fi

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: Not in a git repository${NC}"
    exit 1
fi

# Check if the tag exists
if ! git tag --list | grep -q "v${VERSION}"; then
    echo -e "${RED}❌ Error: Git tag v${VERSION} not found${NC}"
    echo "   Available tags:"
    git tag --list | head -5
    echo ""
    echo "💡 Create the tag first: git tag v${VERSION}"
    exit 1
fi

echo -e "${GREEN}✅ Version: ${VERSION}${NC}"
echo -e "${GREEN}✅ Git tag: v${VERSION}${NC}"
echo -e "${GREEN}✅ Repository: ${REPO_NAME}${NC}"
echo ""

# Create release tarball
echo -e "${BLUE}📦 Creating release tarball...${NC}"

# Go to parent directory (repository root)
cd ..

# Create tarball from git tag
git archive --format=tar.gz --prefix="manifest.local-${VERSION}/" "v${VERSION}" > "${FORMULA_DIR}/${TARBALL_NAME}"

# Go back to Formula directory
cd "${FORMULA_DIR}"

# Calculate SHA256 hash
echo -e "${BLUE}🔐 Calculating SHA256 hash...${NC}"
SHA256_HASH=$(shasum -a 256 "${TARBALL_NAME}" | cut -d' ' -f1)

echo -e "${GREEN}✅ Tarball created: ${TARBALL_NAME}${NC}"
echo -e "${GREEN}✅ SHA256 hash: ${SHA256_HASH}${NC}"
echo ""

# Update the formula with the correct hash
echo -e "${BLUE}📝 Updating formula with SHA256 hash...${NC}"
sed -i.bak "s/sha256 \"SKIP\"/sha256 \"${SHA256_HASH}\"/" manifest.rb
rm -f manifest.rb.bak

echo -e "${GREEN}✅ Formula updated with SHA256 hash${NC}"
echo ""

# Test the formula locally
echo -e "${BLUE}🧪 Testing formula locally...${NC}"
if brew install --build-from-source manifest.rb; then
    echo -e "${GREEN}✅ Formula test successful!${NC}"
    
    # Test the CLI
    echo -e "${BLUE}🔧 Testing CLI functionality...${NC}"
    if manifest --help > /dev/null 2>&1; then
        echo -e "${GREEN}✅ CLI test successful!${NC}"
    else
        echo -e "${YELLOW}⚠️  CLI test failed, but formula installed${NC}"
    fi
    
    # Uninstall test installation
    brew uninstall manifest
    echo -e "${GREEN}✅ Test installation cleaned up${NC}"
else
    echo -e "${RED}❌ Formula test failed${NC}"
    echo "   Check the error messages above"
    exit 1
fi

echo ""
echo -e "${BLUE}🎉 Homebrew release preparation complete!${NC}"
echo ""
echo -e "${GREEN}📋 Next steps:${NC}"
echo "   1. Commit the updated formula:"
echo "      git add Formula/manifest.rb"
echo "      git commit -m 'Update Homebrew formula for v${VERSION}'"
echo ""
echo "   2. Push the changes:"
echo "      git push origin main"
echo ""
echo "   3. Create a GitHub release:"
echo "      - Tag: v${VERSION}"
echo "      - Title: Release v${VERSION}"
echo "      - Upload: ${TARBALL_NAME}"
echo ""
echo "   4. Users can now install with:"
echo "      brew install ${REPO_NAME}/manifest"
echo ""
echo -e "${BLUE}📁 Files created:${NC}"
echo "   - ${TARBALL_NAME} (release tarball)"
echo "   - manifest.rb (updated formula)"
echo "   - SHA256 hash: ${SHA256_HASH}"
echo ""
echo -e "${GREEN}✨ Happy releasing!${NC}"
