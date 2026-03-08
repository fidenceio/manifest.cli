# Manifest CLI Installation Guide

## Recommended (Homebrew)

```bash
brew tap fidenceio/tap
brew install manifest
```

Upgrade:

```bash
brew update && brew upgrade manifest
```

## Install Script

```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

Behavior:

- Uses Homebrew path when available.
- Falls back to manual install (`~/.manifest-cli` + launcher in `~/.local/bin`).

## Verify Installation

```bash
manifest --help
manifest test all
```

## Requirements

- Git
- Bash environment
- Network access for remote operations and NTP/cloud features

## Uninstall

```bash
manifest uninstall
```

Force mode:

```bash
manifest uninstall --force
```

## Reinstall

```bash
manifest reinstall
```

## Troubleshooting

- Ensure `manifest` resolves to expected binary: `which manifest`.
- For manual installs, ensure `~/.local/bin` is on your `PATH`.
- Validate shell and config with `manifest test all` and `manifest config show`.
