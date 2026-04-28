# Shell completions

Tab-completion for `manifest` covering top-level commands, scopes (`repo|fleet`), bump types (`patch|minor|major|revision`), config subcommands, PR subcommands, layer flags, and config keys (queried dynamically from `manifest config list`).

## Bash

```sh
# One-off (current shell):
source /path/to/manifest-cli/completions/manifest.bash

# Persistent (~/.bashrc):
echo 'source /path/to/manifest-cli/completions/manifest.bash' >> ~/.bashrc
```

If you have [bash-completion](https://github.com/scop/bash-completion) installed, you can drop the file into its completion dir instead:

```sh
ln -s /path/to/manifest-cli/completions/manifest.bash \
      $(brew --prefix)/etc/bash_completion.d/manifest
```

## Zsh

```sh
# Add the completions dir to fpath, then run compinit:
fpath=(/path/to/manifest-cli/completions $fpath)
autoload -U compinit && compinit
```

Or symlink directly into the standard site-functions directory:

```sh
ln -s /path/to/manifest-cli/completions/_manifest \
      $(brew --prefix)/share/zsh/site-functions/_manifest
```

After installing, restart your shell or run `compinit` again.

## What you get

- `manifest <TAB>` → all top-level commands
- `manifest init <TAB>` → `repo  fleet`
- `manifest ship repo <TAB>` → `patch minor major revision --local --dry-run`
- `manifest config <TAB>` → `show list get set unset describe doctor setup time`
- `manifest config get <TAB>` → all 83 config keys (cached after first lookup)
- `manifest config set --layer <TAB>` → `global  project  local`
