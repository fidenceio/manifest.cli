# Git Hooks

This directory contains versioned hooks for Manifest CLI contributors.

## Included Hook

| Hook | Purpose |
| ---- | ------- |
| `pre-commit` | Scans staged content for secrets, private env files, large binaries, unsafe release artifacts, and absolute home paths (`/Users/<name>`, `/home/<name>`) that would leak a developer's account name |

## Install

Point git at this directory. The path is **relative**, so it keeps working if
the repo is moved or renamed:

```bash
git config core.hooksPath .git-hooks
```

Verify it took effect — an absolute `core.hooksPath` left over from a previous
checkout location silently disables every hook, and git reports no error:

```bash
git config core.hooksPath                     # expect: .git-hooks
test -d "$(git rev-parse --show-toplevel)/$(git config core.hooksPath)" \
  && echo "hooks live" || echo "hooks DEAD"
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
