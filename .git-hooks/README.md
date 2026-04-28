# Git Hooks Directory

This directory stores version-controlled git hooks that can be installed into `.git/hooks/`.

## Included Hook

- `pre-commit`: blocks likely secrets/private config from being committed.

## Install

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

## Why This Exists

Git does not version files under `.git/hooks/`. Keeping canonical hook scripts in `.git-hooks/` lets the team review and evolve hook logic in normal pull requests.

## Related Docs

- `docs/GIT_HOOKS.md`
