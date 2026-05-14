# Manifest CLI Installation Guide

---

## Requirements

| Dependency | Version | Required | Notes |
| ---------- | ------- | -------- | ----- |
| **Bash** | 5.0+ | Yes | macOS ships Bash 3.2; Homebrew installs Bash 5 automatically |
| **Git** | Any recent | Yes | Version control operations |
| **yq** | 4.0+ (Mike Farah's Go version) | Yes | YAML configuration parsing |
| **Docker** | Running engine | Yes | Required for the containerized execution model |
| **curl** | Any | Recommended | HTTPS timestamps, API calls, install script |
| **coreutils** | Any | Yes | Cross-platform timeout, `date`, and `stat` behavior |

**Important:** The supported dependency versions are defined in `modules/core/manifest-requirements.sh`. The CLI, installer, doctor, and Homebrew wrapper use that same contract.

---

## Install via Homebrew (Recommended)

```bash
brew tap fidenceio/tap
brew install manifest
```

This installs the CLI, sets up the `manifest` command, and pulls in Bash 5, Git, yq, and coreutils as dependencies automatically. Docker must also be installed and running.

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

1. Validates the required Bash version (with per-platform install instructions if missing)
2. Validates the required yq version and vendor (detects wrong version, provides install commands)
3. Validates coreutils timeout support (`gtimeout` on macOS, `timeout` elsewhere)
4. Ensures Homebrew first on macOS, then offers to install Docker Desktop with `brew install --cask docker`
5. Validates Docker is installed and the engine is reachable
6. Uses Homebrew when available (preferred path)
7. Falls back to manual installation at `~/.manifest-cli` with a launcher in `~/.local/bin`
8. Installs bash/zsh completions for normal terminals and IDE integrated terminals
9. Writes IDE and AI assistant command catalogs under `~/.manifest-cli/ide/`
10. Migrates configuration from legacy locations automatically

### IDE and AI Assistant Support

The installer sets up shell completions in standard bash/zsh locations when
those locations are available. VS Code, Cursor, Windsurf, Antigravity, and other
editors that use your normal login shell can then complete `manifest` commands
inside their integrated terminals.

The installer also writes a concise command catalog for AI/editor assistants:

```text
~/.manifest-cli/ide/manifest-cli-commands.md
~/.manifest-cli/ide/manifest-cli-commands.json
~/.manifest-cli/ide/AGENTS.md
~/.manifest-cli/ide/CLAUDE.md
```

These files document the first-class commands and the safe-by-default contract:
mutating commands preview by default, `--dry-run` is explicit preview, and
`-y`/`--yes` applies the plan.

### Installing Docker

On macOS, the install script uses one clean path:

```bash
brew install --cask docker
open -a Docker
docker info
```

On Linux, install Docker Engine for your distribution, start the service, then verify:

```bash
docker info
```

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

If `manifest doctor` reports the wrong `yq`, install the package listed above for your platform. Manifest rejects incompatible `yq` binaries at startup.

---

## Verify Installation

```bash
# Check the CLI is accessible
which manifest

# View help
manifest --help

# Review configuration
manifest config show

# Validate dependencies
manifest doctor
```

---

## Post-Install: Initialize Your Project

```bash
cd your-project

# Scaffold required files (VERSION, CHANGELOG.md, docs/, .gitignore)
manifest init repo
manifest init repo -y

# Connect remotes and pull latest
manifest prep repo
manifest prep repo -y

# Review your configuration
manifest config show
```

---

## Uninstall

```bash
manifest uninstall          # Preview uninstall changes
manifest uninstall -y       # Apply uninstall interactively
manifest uninstall --force -y  # Apply and skip extra confirmations
```

---

## Reinstall

Full uninstall and clean reinstall:

```bash
manifest reinstall          # Preview reinstall steps
manifest reinstall -y       # Apply full uninstall + reinstall
```

On macOS, this offers the Homebrew installation path. Configuration is preserved during migration.

---

## Troubleshooting

| Symptom | Fix |
| ------- | --- |
| `manifest: command not found` | Ensure `~/.local/bin` is on your `PATH` |
| Wrong version running | Check with `which manifest` and `manifest --help` |
| Tests failing | Run `manifest doctor` and use the repo's containerized test runner when developing Manifest CLI |
| Bash version issues | Install Bash 5+ via Homebrew: `brew install bash` |
| `yq is not installed` | Install yq: `brew install yq` (see Installing yq Manually above) |
| `yq does not satisfy the Manifest requirement` | Install the supported yq package for your platform |
| YAML config not loading | Run `manifest config doctor` to diagnose config issues |
| Network errors | Check connectivity; use `MANIFEST_CLI_OFFLINE_MODE=true` for offline work |

For persistent issues in the Manifest CLI repo, run `./scripts/run-tests-container.sh`
and review the emitted test log paths.
