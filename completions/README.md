# Shell Completions

A shell completion lets you press Tab to fill in a command, a scope, or a flag.
Manifest ships completions for Bash, zsh, and fish.

## Installed By Homebrew

The Homebrew formula installs all three files for you:

- `completions/manifest.bash` as the Bash completion
- `completions/_manifest` as the zsh completion
- `completions/manifest.fish` as the fish completion

If you installed Manifest with Homebrew, you do not need the manual steps below.

## Installed By The Manual Installer

`install-cli.sh` links two of the files into your own completion directories:

- Bash: `${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/manifest`.
  Bash loads it by itself when `bash-completion` is turned on.
- zsh: `~/.zsh/completions/_manifest`. Your `~/.zshrc` must add that directory to
  `fpath` and run `compinit`. The installer prints the two lines to add.

It does not install the fish completion. Use the manual fish setup below.

## Manual Bash Setup

Run this from the root of a Manifest CLI checkout:

```bash
source completions/manifest.bash
```

This lasts for the current shell session only. To keep it, load the file from your
shell profile, or place it in your completion directory. Use the Homebrew formula when
you can.

## Manual Zsh Setup

Run this from the root of a Manifest CLI checkout:

```bash
fpath=("$PWD/completions" $fpath)
autoload -Uz compinit
compinit
```

## Manual Fish Setup

Run this from the root of a Manifest CLI checkout:

```fish
mkdir -p ~/.config/fish/completions
ln -sf "$PWD/completions/manifest.fish" ~/.config/fish/completions/manifest.fish
```

Fish loads completions from this directory by itself. You need no other configuration.

## Coverage

The completions cover:

- Top-level commands
- Repo and fleet scopes
- Release types
- Config keys
- Common flags

To complete config keys, the shell runs `manifest config list` and reads the key names
from its output.

When you add or remove a public command, update three things in the same change: the
completions, the help text, and the command reference
([docs/COMMAND_REFERENCE.md](../docs/COMMAND_REFERENCE.md)).

Internal scanners, catalogs, and detection helpers get no completion entry. Add an
entry only when one of them becomes a public command or a public flag.
