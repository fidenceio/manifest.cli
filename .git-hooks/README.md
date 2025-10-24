# Git Hooks Directory

This directory contains git hooks that can be installed by developers to prevent committing sensitive data.

## Available Hooks

### `pre-commit`

**Purpose**: Prevents committing sensitive data like API keys, passwords, tokens, and private configuration files.

**What it checks**:
1. Private environment files (`.env`, `.env.local`, etc.)
2. Sensitive data patterns (API keys, tokens, passwords)
3. .gitignore configuration
4. Large files (>10MB)
5. Manifest CLI security audit (if available)

## Installation

### Quick Install

```bash
./install-git-hooks.sh
```

### Manual Install

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Why This Directory?

Git hooks in `.git/hooks/` are **not** tracked by version control. This `.git-hooks/` directory allows us to:

1. **Version control** hooks alongside the code
2. **Share** hooks with all developers
3. **Update** hooks easily across the team
4. **Document** hook behavior and usage

## Usage

Once installed, the hooks run automatically:

```bash
git commit -m "message"
# ↓
# Pre-commit hook runs automatically
# ↓
# Commit proceeds OR is blocked with helpful error
```

## Documentation

- **Quick Start**: [../docs/GIT_HOOKS_QUICK_START.md](../docs/GIT_HOOKS_QUICK_START.md)
- **Full Guide**: [../docs/GIT_HOOKS.md](../docs/GIT_HOOKS.md)
- **Security**: [../docs/SECURITY_ANALYSIS_REPORT.md](../docs/SECURITY_ANALYSIS_REPORT.md)

## Customization

### For Your Team

If you need to customize the hooks for your organization:

1. Edit the hooks in this directory (`.git-hooks/`)
2. Commit the changes
3. Have team members re-run: `./install-git-hooks.sh`

### For Individual Use

If you need personal customizations:

1. Install the base hook: `./install-git-hooks.sh`
2. Edit your personal copy: `.git/hooks/pre-commit`
3. Your changes stay local (not committed)

## Hook Maintenance

### Updating Hooks

```bash
# Pull latest changes
git pull

# Reinstall hooks
./install-git-hooks.sh
```

### Testing Hooks

```bash
# Test sensitive data detection
echo 'password = "test123"' > test.sh
git add test.sh
git commit -m "test"  # Should be blocked

# Test safe commits
echo "# README" > test.md
git add test.md
git commit -m "test"  # Should succeed

# Clean up
git reset --soft HEAD~1
rm test.sh test.md
```

## CI/CD Integration

These hooks can also be used in CI/CD pipelines:

```yaml
# Example: GitHub Actions
- name: Run pre-commit checks
  run: .git-hooks/pre-commit
```

## Contributing

When contributing new hooks or improvements:

1. Add/modify hooks in this directory
2. Update documentation
3. Test thoroughly
4. Submit a pull request

## Support

Questions? Issues? See:
- [Full documentation](../docs/GIT_HOOKS.md)
- Run: `manifest security`
- Open an issue on GitHub

---

**Last updated**: 2025-09-23
**Version**: 23.2.0
