#!/bin/bash

# Manifest CLI - Git Hooks Installation Script
# Installs pre-commit hook to prevent committing sensitive data
# Safe for all developers to use

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Find the project root
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
GIT_HOOKS_SOURCE_DIR="$PROJECT_ROOT/.git-hooks"
GIT_HOOKS_TARGET_DIR="$PROJECT_ROOT/.git/hooks"

echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${CYAN}🔒 Manifest CLI - Git Hooks Installation${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# =============================================================================
# VERIFY WE'RE IN A GIT REPOSITORY
# =============================================================================
if [ ! -d "$PROJECT_ROOT/.git" ]; then
    echo -e "${RED}❌ Error: Not in a Git repository${NC}"
    echo -e "${YELLOW}   Please run this script from within the Manifest CLI repository${NC}"
    exit 1
fi

echo -e "${BLUE}📂 Project root: ${PROJECT_ROOT}${NC}"
echo ""

# =============================================================================
# CHECK IF GIT HOOKS SOURCE DIRECTORY EXISTS
# =============================================================================
if [ ! -d "$GIT_HOOKS_SOURCE_DIR" ]; then
    echo -e "${RED}❌ Error: Git hooks source directory not found${NC}"
    echo -e "${YELLOW}   Expected: $GIT_HOOKS_SOURCE_DIR${NC}"
    echo -e "${YELLOW}   This script should be run from the project root${NC}"
    exit 1
fi

# =============================================================================
# CREATE GIT HOOKS DIRECTORY IF IT DOESN'T EXIST
# =============================================================================
if [ ! -d "$GIT_HOOKS_TARGET_DIR" ]; then
    echo -e "${YELLOW}⚠️  Git hooks directory doesn't exist. Creating...${NC}"
    mkdir -p "$GIT_HOOKS_TARGET_DIR"
    echo -e "${GREEN}   ✅ Created: $GIT_HOOKS_TARGET_DIR${NC}"
    echo ""
fi

# =============================================================================
# INSTALL PRE-COMMIT HOOK
# =============================================================================
echo -e "${BLUE}🔧 Installing pre-commit hook...${NC}"

PRE_COMMIT_SOURCE="$GIT_HOOKS_SOURCE_DIR/pre-commit"
PRE_COMMIT_TARGET="$GIT_HOOKS_TARGET_DIR/pre-commit"

# Check if source hook exists
if [ ! -f "$PRE_COMMIT_SOURCE" ]; then
    echo -e "${RED}❌ Error: Pre-commit hook source not found${NC}"
    echo -e "${YELLOW}   Expected: $PRE_COMMIT_SOURCE${NC}"
    exit 1
fi

# Backup existing hook if it exists
if [ -f "$PRE_COMMIT_TARGET" ]; then
    BACKUP_FILE="$PRE_COMMIT_TARGET.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${YELLOW}   ⚠️  Existing pre-commit hook found${NC}"
    echo -e "${YELLOW}   📦 Creating backup: $BACKUP_FILE${NC}"
    cp "$PRE_COMMIT_TARGET" "$BACKUP_FILE"
fi

# Copy the hook
cp "$PRE_COMMIT_SOURCE" "$PRE_COMMIT_TARGET"

# Make it executable
chmod +x "$PRE_COMMIT_TARGET"

echo -e "${GREEN}   ✅ Pre-commit hook installed successfully${NC}"
echo ""

# =============================================================================
# VERIFY INSTALLATION
# =============================================================================
echo -e "${BLUE}🔍 Verifying installation...${NC}"

if [ -f "$PRE_COMMIT_TARGET" ] && [ -x "$PRE_COMMIT_TARGET" ]; then
    echo -e "${GREEN}   ✅ Pre-commit hook is executable${NC}"
else
    echo -e "${RED}   ❌ Pre-commit hook installation failed${NC}"
    exit 1
fi

# Check hook content
if grep -q "Manifest CLI Pre-Commit Hook" "$PRE_COMMIT_TARGET" 2>/dev/null; then
    echo -e "${GREEN}   ✅ Pre-commit hook content verified${NC}"
else
    echo -e "${RED}   ❌ Pre-commit hook content verification failed${NC}"
    exit 1
fi

echo ""

# =============================================================================
# DISPLAY INFORMATION
# =============================================================================
echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}✅ Git hooks installed successfully!${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo -e "${CYAN}📋 What was installed:${NC}"
echo -e "   • Pre-commit hook: Prevents committing sensitive data"
echo ""
echo -e "${CYAN}🔒 Security features enabled:${NC}"
echo -e "   • Blocks commits containing private environment files"
echo -e "   • Scans for sensitive data patterns (API keys, tokens, passwords)"
echo -e "   • Verifies .gitignore configuration"
echo -e "   • Detects large files (>10MB)"
echo -e "   • Integrates with Manifest CLI security module"
echo ""
echo -e "${CYAN}🧪 Testing the hook:${NC}"
echo -e "   Try committing a file with sensitive data to see it in action:"
echo -e "   ${YELLOW}echo 'password=\"supersecret123\"' > test.sh${NC}"
echo -e "   ${YELLOW}git add test.sh && git commit -m \"test\"${NC}"
echo ""
echo -e "${CYAN}🛠️  Bypassing the hook (use with caution):${NC}"
echo -e "   ${YELLOW}git commit --no-verify -m \"message\"${NC}"
echo -e "   ${RED}⚠️  Only bypass if you're absolutely certain the commit is safe!${NC}"
echo ""
echo -e "${CYAN}🔄 Updating hooks:${NC}"
echo -e "   Re-run this script anytime to update to the latest version:"
echo -e "   ${YELLOW}./install-git-hooks.sh${NC}"
echo ""
echo -e "${CYAN}🗑️  Uninstalling hooks:${NC}"
echo -e "   ${YELLOW}rm .git/hooks/pre-commit${NC}"
echo -e "   ${YELLOW}# Restore from backup if needed:${NC}"
echo -e "   ${YELLOW}mv .git/hooks/pre-commit.backup.* .git/hooks/pre-commit${NC}"
echo ""
echo -e "${CYAN}📚 More information:${NC}"
echo -e "   • Security documentation: docs/SECURITY_ANALYSIS_REPORT.md"
echo -e "   • Git hooks documentation: docs/GIT_HOOKS.md"
echo -e "   • Manifest CLI security: ${YELLOW}manifest security${NC}"
echo ""
echo -e "${GREEN}Happy secure coding! 🚀${NC}"
echo ""
