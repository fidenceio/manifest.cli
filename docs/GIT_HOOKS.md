# Git Hooks for Sensitive Data Protection

Manifest CLI ships a `pre-commit` hook in `.git-hooks/pre-commit` that blocks
common secret-leak paths before they reach your Git history.

---

## What the Hook Checks

| Check | Description |
| ----- | ----------- |
| Private env/config files | Blocks `.env*` and similar files from being committed |
| Secret patterns | Scans staged content for tokens, API keys, and credentials |
| `.gitignore` safety | Verifies `.gitignore` is properly configured |
| Large files | Warns before accidentally committing binaries or archives |
| Manifest security | Integrates with `manifest security` when available |

---

## Install

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Blocked Commit Recovery

If the hook blocks your commit:

```bash
# Unstage the problematic file
git reset HEAD <file>

# Remove secrets or move to an ignored local config file
# Then re-stage safe files only
git add <safe-files>
git commit -m "safe commit"
```

---

## Bypass (Emergency Only)

```bash
git commit --no-verify -m "emergency change"
```

Use bypass sparingly. Always follow up with a manual `manifest security` run
to verify no secrets were committed.

---

## Team Workflow

- Keep `.git-hooks/pre-commit` version-controlled in your repository
- Reinstall the hook after pulling changes to the hook file
- Pair local hooks with CI security checks for defense in depth
- Use `manifest security` as a periodic audit on top of the pre-commit hook
