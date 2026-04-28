# Manifest CLI Installation Guide

---

## Requirements

| Dependency | Version | Required | Notes |
| ---------- | ------- | -------- | ----- |
| **Bash** | 5.0+ | Yes | macOS ships Bash 3.2; Homebrew installs Bash 5 automatically |
| **Git** | Any recent | Yes | Version control operations |
| **yq** | 4.0+ (Mike Farah's Go version) | Yes | YAML configuration parsing |
| **curl** | Any | Recommended | HTTPS timestamps, API calls, install script |
| **coreutils** | Any | Optional | Cross-platform `date`/`stat` on macOS |

**Important:** The `yq` dependency must be [Mike Farah's Go implementation](https://github.com/mikefarah/yq), not the Python `yq` wrapper (`kislyuk/yq`). The install script and Homebrew formula validate this automatically.

---

## Install via Homebrew (Recommended)

```bash
brew tap fidenceio/tap
brew install manifest
```

This installs the CLI, sets up the `manifest` command, and pulls in Bash 5, Git, and yq as dependencies automatically.

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

1. Validates Bash 5+ is available (with per-platform install instructions if missing)
2. Validates yq v4+ is available (detects wrong version, provides install commands)
3. Uses Homebrew when available (preferred path)
4. Falls back to manual installation at `~/.manifest-cli` with a launcher in `~/.local/bin`
5. Migrates configuration from legacy locations automatically

### Installing yq Manually

If the install script reports yq is missing, install it for your platform:

```bash
# macOS
brew install yq

# Ubuntu/Debian (via snap)
sudo snap install yq

# Fedora/RHEL
sudo dnf install yq

# Alpine
sudo apk add yq

# Arch Linux
sudo pacman -S go-yq

# Any platform (binary download)
# See https://github.com/mikefarah/yq#install
```

**Verify you have the correct version:**

```bash
yq --version
# Should show: yq (https://github.com/mikefarah/yq/) version v4.x.x
```

If you see `yq 2.x` or `kislyuk/yq`, you have the Python wrapper — uninstall it and install the Go version instead:

```bash
pip uninstall yq           # Remove Python yq
brew install yq            # Install Go yq
```

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

# Validate dependencies
manifest config doctor
```

---

## Post-Install: Initialize Your Project

```bash
cd your-project

# Scaffold required files (VERSION, CHANGELOG.md, docs/, .gitignore)
manifest init repo

# Connect remotes and pull latest
manifest prep repo

# Review your configuration
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
| `yq is not installed` | Install yq: `brew install yq` (see Installing yq Manually above) |
| `yq is not Mike Farah's Go version` | Uninstall Python yq (`pip uninstall yq`), install Go yq (`brew install yq`) |
| YAML config not loading | Run `manifest config doctor` to diagnose config issues |
| Network errors | Check connectivity; use `MANIFEST_CLI_OFFLINE_MODE=true` for offline work |

For persistent issues, run `manifest test all --no-strict-redact` and review logs
at `~/.manifest-cli/logs/tests/`.
