# Git Hooks - Sensitive Data Protection

## Overview

The Manifest CLI includes a robust git hooks system that prevents developers from accidentally committing sensitive data like API keys, passwords, tokens, and private configuration files. This system integrates seamlessly with the existing Manifest CLI security module to provide comprehensive protection.

## Table of Contents

- [Quick Start](#quick-start)
- [What Gets Protected](#what-gets-protected)
- [Installation](#installation)
- [How It Works](#how-it-works)
- [Security Checks Performed](#security-checks-performed)
- [Handling Blocked Commits](#handling-blocked-commits)
- [Bypassing the Hook (Use with Caution)](#bypassing-the-hook-use-with-caution)
- [Testing the Hook](#testing-the-hook)
- [Updating Hooks](#updating-hooks)
- [Uninstalling Hooks](#uninstalling-hooks)
- [Troubleshooting](#troubleshooting)
- [Best Practices](#best-practices)

---

## Quick Start

### Automatic Installation (Recommended)

Git hooks are automatically installed when you run the main installation script:

```bash
./install-cli.sh
```

The installation script will detect if you're in a git repository and automatically install the pre-commit hooks.

### Manual Installation

If you need to reinstall or update the hooks:

```bash
./install-git-hooks.sh
```

That's it! The pre-commit hook is now active and will automatically check all commits for sensitive data.

---

## What Gets Protected

The git hooks system prevents committing:

### 1. Private Environment Files
- `.env`
- `.env.local`
- `.env.manifest.local`
- `.env.development`
- `.env.test`
- `.env.production`
- `.env.staging`
- Any `.env.*` files

### 2. Sensitive Data Patterns
- **Passwords**: `password = "actual_value"`
- **API Keys**: `api_key = "sk-xxxxx"`
- **Secrets**: `secret = "abc123xyz"`
- **Tokens**: `access_token = "ghp_xxxx"`
- **Private Keys**: `private_key = "-----BEGIN"`
- **AWS Credentials**: `AKIA[0-9A-Z]{16}`
- **GitHub Tokens**: `gh[ps]_[a-zA-Z0-9]{36,}`
- **OpenAI Keys**: `sk-[a-zA-Z0-9]{48}`
- **JWT Tokens**: `eyJ...` (Base64 encoded tokens)

### 3. Credential Files
- `*.pem` (Private keys)
- `*.key` (Key files)
- `*.p12`, `*.pfx` (Certificates)
- `id_rsa`, `id_dsa`, `id_ecdsa` (SSH keys)
- `secrets.json`, `secrets.yml` (Secret files)
- Cloud credentials (`aws-credentials.json`, etc.)

### 4. Large Files
- Files over 10MB (warning only)
- Helps prevent accidentally committing binary artifacts

---

## Installation

### For New Developers

When you first clone the repository, run:

```bash
./install-git-hooks.sh
```

This will:
1. Copy the pre-commit hook from `.git-hooks/` to `.git/hooks/`
2. Make the hook executable
3. Verify the installation
4. Display helpful information

### Automated Installation

You can add hook installation to your onboarding process:

```bash
# In your setup script
./install-git-hooks.sh --quiet
```

### Manual Installation

If you prefer manual installation:

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## How It Works

### Pre-Commit Hook Flow

```
Developer runs: git commit -m "message"
           ↓
    Pre-commit hook runs automatically
           ↓
    ┌─────────────────────────────────┐
    │  5 Security Checks Performed:   │
    │  1. Private files check         │
    │  2. Sensitive data scan         │
    │  3. .gitignore verification     │
    │  4. Large files detection       │
    │  5. Manifest CLI security audit │
    └─────────────────────────────────┘
           ↓
    ┌──────────┴──────────┐
    ↓                     ↓
 PASS                   FAIL
    ↓                     ↓
Commit proceeds      Commit blocked
                          ↓
                   Error message displayed
                   Developer fixes issues
```

### Integration with Manifest CLI

The hook integrates with the existing `manifest security` command:

```bash
# Manual security audit
manifest security

# Runs automatically during git commit
# (via pre-commit hook)
```

---

## Security Checks Performed

### Check 1: Private Environment Files

**Purpose**: Prevent committing files that should never be in version control

**Example**:
```bash
# This will be BLOCKED
git add .env.local
git commit -m "Update config"

# Output:
❌ CRITICAL: Attempting to commit private file: .env.local
   Action: This file contains sensitive data and should NOT be committed.
```

### Check 2: Sensitive Data Patterns

**Purpose**: Scan staged file contents for secrets and credentials

**Example**:
```bash
# This will be BLOCKED
echo 'api_key = "sk-1234567890abcdef"' > config.sh
git add config.sh
git commit -m "Add config"

# Output:
❌ CRITICAL: Potential sensitive data found in staged files:
   File: config.sh
   Pattern: api_key[[:space:]]*=[[:space:]]*['"]...['"']
```

### Check 3: .gitignore Verification

**Purpose**: Ensure sensitive patterns are properly ignored

**Checks for**:
- `.env` patterns
- `.env.local` patterns
- `manifest.config`
- Other sensitive file patterns

**Example**:
```bash
# If .gitignore is missing patterns
⚠️ WARNING: Missing patterns in .gitignore:
   - .env.*.local
```

### Check 4: Large Files Detection

**Purpose**: Warn about accidentally committing large binaries or artifacts

**Example**:
```bash
# Warning for files > 10MB
⚠️ WARNING: Large files detected (>10MB):
   - build/output.bin (25MB)
```

### Check 5: Manifest CLI Security Audit

**Purpose**: Run comprehensive security checks using the built-in security module

**What it checks**:
- Git tracking of private files
- Actual sensitive data in code
- PII (Personally Identifiable Information)
- Environment file security
- Hardcoded credentials

---

## Handling Blocked Commits

When the hook blocks a commit, you'll see output like this:

```
❌ COMMIT BLOCKED: 2 critical issue(s) found!

🚨 ACTION REQUIRED:
   1. Remove sensitive data from staged files
   2. Add sensitive files to .gitignore
   3. Use 'git reset HEAD <file>' to unstage files
   4. Review the output above for specific issues

💡 TIP: Use environment variables or config files for sensitive data
   Example: source .env.local (which is already gitignored)
```

### Resolution Steps

#### Step 1: Identify the Issue

Review the error message to see what triggered the block:

```bash
❌ CRITICAL: Attempting to commit private file: .env.local
```

#### Step 2: Unstage the Problematic File

```bash
git reset HEAD .env.local
```

#### Step 3: Fix the Issue

**Option A - Remove the file from tracking (recommended)**:
```bash
# File is already in .gitignore
git rm --cached .env.local
```

**Option B - Move sensitive data to environment variables**:
```bash
# Before (in code):
api_key = "sk-1234567890"

# After (in code):
api_key = "${MANIFEST_CLI_API_KEY}"

# In .env.local (gitignored):
export MANIFEST_CLI_API_KEY="sk-1234567890"
```

**Option C - Use example files**:
```bash
# Create an example file without real values
cp .env.local .env.local.example

# Edit the example to use placeholder values
# .env.local.example:
export MANIFEST_CLI_API_KEY="your-api-key-here"

# Commit the example
git add .env.local.example
git commit -m "Add example environment configuration"
```

#### Step 4: Retry the Commit

```bash
git commit -m "Your commit message"
```

---

## Bypassing the Hook (Use with Caution)

### When to Bypass

⚠️ **WARNING**: Only bypass the hook if you are **absolutely certain** the commit is safe.

Valid reasons to bypass:
- Updating the security patterns themselves
- Committing example files with fake credentials
- Emergency hotfixes (review immediately after)

### How to Bypass

```bash
git commit --no-verify -m "Update security patterns"
```

Or use the short form:

```bash
git commit -n -m "Update security patterns"
```

### Important Notes

- **Document why**: Always explain in the commit message why you bypassed
- **Review immediately**: Have another developer review the commit ASAP
- **Run manual audit**: After bypassing, run `manifest security`
- **Never make it a habit**: Bypassing should be rare and justified

---

## Testing the Hook

### Test 1: Attempt to Commit a Private File

```bash
# Create a test .env file
echo "SECRET_KEY=test123" > .env

# Try to commit it
git add .env
git commit -m "Test commit"

# Expected: ❌ COMMIT BLOCKED
# ✅ Success if blocked
```

### Test 2: Attempt to Commit Sensitive Data

```bash
# Create a file with a fake API key
echo 'api_key = "sk-1234567890abcdefghijklmnopqrstuvwxyz123456"' > test-config.sh

# Try to commit it
git add test-config.sh
git commit -m "Test commit"

# Expected: ❌ COMMIT BLOCKED
# ✅ Success if blocked
```

### Test 3: Commit a Safe File

```bash
# Create a safe file
echo "# README" > test-readme.md

# Commit it
git add test-readme.md
git commit -m "Test commit"

# Expected: ✅ All security checks passed!
# ✅ Success if allowed
```

### Test 4: Clean Up

```bash
# Remove test files
rm .env test-config.sh test-readme.md

# Reset the last commit if needed
git reset --soft HEAD~1
```

---

## Updating Hooks

### When to Update

Update hooks when:
- You pull new changes that include hook updates
- Security patterns are updated
- New security features are added
- You encounter issues with the current hook

### How to Update

Simply re-run the installation script:

```bash
./install-git-hooks.sh
```

The script will:
1. Backup your existing hook (if you customized it)
2. Install the latest version
3. Verify the installation

### Checking Hook Version

View the hook content:

```bash
head -5 .git/hooks/pre-commit
```

Should show:
```bash
#!/bin/bash

# Manifest CLI Pre-Commit Hook
# Prevents committing sensitive data by leveraging the Manifest CLI security module
# This hook runs automatically before each commit
```

---

## Uninstalling Hooks

### Complete Removal

```bash
rm .git/hooks/pre-commit
```

### Disabling Temporarily

Rename instead of deleting (easy to re-enable):

```bash
mv .git/hooks/pre-commit .git/hooks/pre-commit.disabled
```

To re-enable:

```bash
mv .git/hooks/pre-commit.disabled .git/hooks/pre-commit
```

### Restoring from Backup

If you have a backup:

```bash
# List available backups
ls -la .git/hooks/pre-commit.backup.*

# Restore a specific backup
cp .git/hooks/pre-commit.backup.20250924_143022 .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Troubleshooting

### Issue: Hook Not Running

**Symptoms**: Commits succeed without any security checks

**Solutions**:

1. **Check if hook exists**:
   ```bash
   ls -la .git/hooks/pre-commit
   ```

2. **Check if hook is executable**:
   ```bash
   chmod +x .git/hooks/pre-commit
   ```

3. **Verify hook content**:
   ```bash
   head -5 .git/hooks/pre-commit
   ```

4. **Reinstall the hook**:
   ```bash
   ./install-git-hooks.sh
   ```

### Issue: False Positives

**Symptoms**: Hook blocks legitimate commits

**Solutions**:

1. **Review the specific pattern that triggered**:
   - Check the error message for the pattern
   - Verify if it's a false positive

2. **Use different variable names**:
   ```bash
   # Instead of:
   my_password = "example"

   # Use:
   my_credentials = "example"  # Or use MANIFEST_CLI_PASSWORD env var
   ```

3. **Add exclusions to example files**:
   - Ensure example files use obviously fake values
   - Use placeholder patterns like `your-key-here`

### Issue: Hook Runs Too Slowly

**Symptoms**: Commits take a long time to process

**Solutions**:

1. **Check for large changesets**:
   ```bash
   git diff --cached --stat
   ```

2. **Commit files in smaller batches**:
   ```bash
   git add file1.sh file2.sh
   git commit -m "Update scripts"
   ```

3. **Disable Manifest CLI integration** (if not installed):
   - The hook gracefully skips if `manifest` is not available
   - No action needed

### Issue: Permission Denied

**Symptoms**: `permission denied: .git/hooks/pre-commit`

**Solution**:

```bash
chmod +x .git/hooks/pre-commit
```

### Issue: Hook Bypassed Accidentally

**Symptoms**: Realized you used `--no-verify` by mistake

**Solution**:

1. **Check the commit**:
   ```bash
   git show HEAD
   ```

2. **Run manual security audit**:
   ```bash
   manifest security
   ```

3. **If issues found, amend the commit**:
   ```bash
   # Fix the issues
   git add .
   git commit --amend --no-edit
   ```

---

## Best Practices

### 1. Always Use Environment Variables for Secrets

❌ **BAD**:
```bash
API_KEY="sk-1234567890abcdef"
```

✅ **GOOD**:
```bash
API_KEY="${MANIFEST_CLI_API_KEY}"
```

And in `.env.local` (gitignored):
```bash
export MANIFEST_CLI_API_KEY="sk-1234567890abcdef"
```

### 2. Commit Example Files, Not Real Configs

❌ **BAD**:
```bash
git add .env.local
```

✅ **GOOD**:
```bash
# Create example file
cp .env.local env.manifest.local.example

# Replace real values with placeholders
sed -i '' 's/sk-[a-zA-Z0-9]\{48\}/your-openai-api-key-here/g' env.manifest.local.example

# Commit the example
git add env.manifest.local.example
git commit -m "Add example environment configuration"
```

### 3. Review Hook Output Carefully

- Don't ignore warnings
- Investigate why a pattern was triggered
- Fix the root cause, don't just bypass

### 4. Keep Hooks Updated

```bash
# Regularly update hooks
git pull
./install-git-hooks.sh
```

### 5. Educate Your Team

Share this documentation with:
- New team members during onboarding
- All developers when hooks are first introduced
- Anyone who encounters blocked commits

### 6. Use `.gitignore` Proactively

Add patterns before creating sensitive files:

```bash
# Add to .gitignore first
echo "my-secrets.json" >> .gitignore
git add .gitignore
git commit -m "Ignore secrets file"

# Then create the file
touch my-secrets.json
```

### 7. Run Manual Security Audits

Don't rely only on git hooks:

```bash
# Before important commits
manifest security

# Regularly during development
manifest security
```

### 8. Document Exceptions

If you must bypass the hook:

```bash
git commit --no-verify -m "Update security patterns

Bypassing hook to update the patterns themselves.
Reviewed by: @security-team
Ticket: SEC-123"
```

---

## Integration with CI/CD

### GitHub Actions

Add security checks to your workflow:

```yaml
name: Security Check

on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Manifest CLI
        run: ./install-cli.sh

      - name: Run Security Audit
        run: manifest security
```

### Pre-Receive Hooks (Server-Side)

For additional protection, install server-side hooks:

```bash
# On your Git server
cp .git-hooks/pre-commit /path/to/repo.git/hooks/pre-receive
chmod +x /path/to/repo.git/hooks/pre-receive
```

---

## Related Documentation

- [Security Analysis Report](SECURITY_ANALYSIS_REPORT.md) - Detailed security audit
- [Command Reference](COMMAND_REFERENCE.md) - All Manifest CLI commands
- [Installation Guide](INSTALLATION.md) - Setup instructions
- [User Guide](USER_GUIDE.md) - General usage guide

---

## Support

If you encounter issues with the git hooks:

1. **Check this documentation** for troubleshooting steps
2. **Run the security audit**: `manifest security`
3. **Reinstall hooks**: `./install-git-hooks.sh`
4. **Review logs**: Check `.git/hooks/pre-commit` output
5. **Open an issue**: If the problem persists

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 23.2.0 | 2025-09-23 | Initial git hooks implementation |

---

*Generated by Manifest CLI Security Module*

*Last updated: 2025-09-23*
