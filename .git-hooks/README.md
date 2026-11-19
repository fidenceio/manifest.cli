# Git Hooks

A Git hook is a script that Git runs at a set moment, such as just before a commit.
This directory holds the hooks for people who contribute to Manifest CLI. The hooks are
kept in the repository, so every contributor uses the same version.

## Included Hook

| Hook | Purpose |
| ---- | ------- |
| `pre-commit` | Checks what you are about to commit for secrets, private env files, large files, and absolute home paths (`/Users/<name>`, `/home/<name>`) that would reveal a developer's account name |

The hook runs six checks. Three of them block the commit. The other three print a
warning and let the commit go ahead.

| Check | What it looks for | Result |
| ----- | ----------------- | ------ |
| 1 | A private env file staged at the root of the repository: `.env`, `.env.local`, `.env.manifest.local`, `.env.development`, `.env.test`, `.env.production` or `.env.staging` | Blocks |
| 2 | Staged lines that look like a secret: a password, an API key, a token, or a user name and password inside a URL | Blocks |
| 3 | A missing `.gitignore`, or one that lacks the rules for env files and Manifest config | Warns |
| 4 | A staged file larger than 10 MB | Warns |
| 5 | Findings from `manifest security --check`. This check is skipped when the Manifest CLI is not available | Warns |
| 6 | An absolute home path in staged content. Placeholder names such as `/Users/you` are allowed | Blocks |

## Install

Point Git at this directory. The path is **relative**, so it keeps working if the
repository is moved or renamed:

```bash
git config core.hooksPath .git-hooks
```

Then check that the setting took effect. If `core.hooksPath` holds an absolute path to
a folder that does not exist (for example, because the repository was moved), Git runs
no hooks at all and reports no error:

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

You can skip the hook, but do so only in an emergency, and only after you understand
what it found:

```bash
git commit --no-verify
```

## Related Docs

- [User Guide: Security and maintenance](../docs/USER_GUIDE.md#security-and-maintenance)
- [Tests](../tests/README.md)
