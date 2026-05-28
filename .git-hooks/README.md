# Git Hooks

This directory contains versioned hooks for Manifest CLI contributors.

## Included Hook

| Hook | Purpose |
| ---- | ------- |
| `pre-commit` | Scans staged content for secrets, private env files, large binaries, and unsafe release artifacts |

## Install

```bash
ln -sf ../../.git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Recovery

If the hook blocks a commit:

```bash
git status --short
git restore --staged <file>
# remove the secret or move private data into an ignored local file
git add <safe-files>
```

Bypass only for emergencies and only after understanding the finding:

```bash
git commit --no-verify
```

## Related Docs

- [User Guide: Security and maintenance](../docs/USER_GUIDE.md#security-and-maintenance)
- [Tests](../tests/README.md)
