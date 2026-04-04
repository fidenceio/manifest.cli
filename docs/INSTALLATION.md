# Manifest CLI Installation Guide

---

## Requirements

- **Git** (any recent version)
- **Bash 5+** (macOS ships Bash 3.2; Homebrew installs Bash 5 automatically)
- **Network access** for remote operations, timestamp verification, and cloud features

---

## Install via Homebrew (Recommended)

```bash
brew tap fidenceio/tap
brew install manifest
```

This installs the CLI, sets up the `manifest` command, and configures Bash 5 automatically.

### Upgrade

```bash
brew update && brew upgrade manifest
```

Or use the built-in upgrade command:

```bash
manifest upgrade
manifest upgrade --check   # Check only, don't install
manifest upgrade --force   # Force regardless of version
```

---

## Install via Script

```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

The install script:

1. Uses Homebrew when available (preferred path)
2. Falls back to manual installation at `~/.manifest-cli` with a launcher in `~/.local/bin`
3. Migrates configuration from legacy locations automatically

---

## Verify Installation

```bash
# Check the CLI is accessible
which manifest

# View help
manifest --help

# Run full test suite
manifest test all

# Review configuration
manifest config show
```

---

## Uninstall

```bash
manifest uninstall          # Interactive uninstall
manifest uninstall --force  # Skip confirmation
```

---

## Reinstall

Full uninstall and clean reinstall:

```bash
manifest reinstall
```

On macOS, this offers the Homebrew installation path. Configuration is preserved during migration.

---

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| `manifest: command not found` | Ensure `~/.local/bin` is on your `PATH` |
| Wrong version running | Check with `which manifest` and `manifest --help` |
| Tests failing | Run `manifest config doctor --fix` to repair deprecated settings |
| Bash version issues | Install Bash 5+ via Homebrew: `brew install bash` |
| Network errors | Check connectivity; use `MANIFEST_CLI_OFFLINE_MODE=true` for offline work |

For persistent issues, run `manifest test all --no-strict-redact` and review logs
at `~/.manifest-cli/logs/tests/`.
