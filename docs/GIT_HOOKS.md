# Git Hooks for Sensitive Data Protection

This repository ships a `pre-commit` hook in `.git-hooks/pre-commit` to block common secret-leak paths before commit.

## What the Hook Checks

- private env/config files (for example `.env*`)
- secret-like token and key patterns in staged content
- `.gitignore` safety expectations
- large file warnings
- integration with `manifest security` when available

## Install

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Typical Blocked Commit Recovery

```bash
git reset HEAD <file>
# remove secrets or move to ignored local config
git add <safe-files>
git commit -m "safe commit"
```

## Bypass (Emergency Only)

```bash
git commit --no-verify -m "emergency change"
```

Use bypass sparingly and follow with a manual `manifest security` run.

## Team Workflow

- Keep `.git-hooks/pre-commit` versioned in this repo.
- Reinstall hook after pulling hook changes.
- Pair local hooks with CI security checks for defense in depth.
