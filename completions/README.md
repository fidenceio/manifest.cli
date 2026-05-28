# Shell Completions

Manifest ships Bash and zsh completions.

## Installed By Homebrew

The Homebrew formula installs:

- `completions/manifest.bash` as Bash completion
- `completions/_manifest` as zsh completion

## Manual Bash Setup

```bash
source completions/manifest.bash
```

Persistent setup depends on your shell profile and completion directory. Prefer the Homebrew formula when possible.

## Manual Zsh Setup

```bash
fpath=("$PWD/completions" $fpath)
autoload -Uz compinit
compinit
```

## Coverage

Completions cover:

- Top-level commands
- Repo and fleet scopes
- Release types
- Config keys
- Common flags

When adding or removing public commands, update completions with help text and command-reference docs in the same change.
