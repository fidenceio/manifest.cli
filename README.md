## 📋 Version Information

| Property | Value |
|----------|-------|
| **Current Version** | `37.0.0` |
| **Release Date** | `2026-03-12 02:12:42 UTC` |
| **Git Tag** | `v37.0.0` |
| **Branch** | `main` |
| **Last Updated** | `2026-03-12 02:12:42 UTC` |
| **CLI Version** | `37.0.0` |

### 📚 Documentation Files

- **Version Info**: [VERSION](VERSION)
- **CLI Modules**: [modules/](modules/)
- **Install Script**: [install-cli.sh](install-cli.sh)
## Current Version

- `VERSION`: `35.2.1`
- Primary docs index: `docs/INDEX.md`
- Install script: `install-cli.sh`

## What It Does

- Runs release preparation and publish flows with explicit release type selection.
- Manages repository docs (`RELEASE_*`, `CHANGELOG_*`, `CHANGELOG.md`) and metadata updates.
- Provides PR workflow helpers through `manifest pr`.
- Supports fleet/polyrepo operations through `manifest fleet`.
- Includes test suites, security checks, configuration wizard, and upgrade/uninstall commands.

## Install

### Homebrew (recommended on macOS/Linux)

```bash
brew tap fidenceio/tap
brew install manifest
```

### Install script

```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

The script prefers Homebrew when available and falls back to manual installation.

## Quick Start

```bash
# Show command help
manifest --help

# Prepare a patch release (local prep mode)
manifest prep patch

# Publish a minor release (prep + tag/push path)
manifest ship minor

# Run full test suite
manifest test all
```

## Command Surface (Top-Level)

- `prep <patch|minor|major|revision> [-i]`
- `ship <patch|minor|major|revision> [-i]`
- `version [patch|minor|major|revision]`
- `docs [metadata|homebrew|cleanup]`
- `sync`, `commit`, `revert`, `cleanup`
- `config [show|ntp|doctor|setup|--non-interactive]`
- `security`
- `test [suite] [--strict-redact|--no-strict-redact]`
- `pr <subcommand>`
- `fleet <subcommand>`
- `cloud <subcommand>`
- `agent <subcommand>`
- `upgrade [--check|--force]`, `update` (deprecated alias), `uninstall [--force]`, `reinstall`

For full usage and examples, see `docs/COMMAND_REFERENCE.md` and `docs/USER_GUIDE.md`.

## Configuration

Config is loaded from environment and optional files:

- install-level: `.env.manifest.global`, `.env.manifest.local` (under install dir)
- user-level: `$HOME/.env.manifest.global`
- repo-level: `.env.manifest.global`, `.env.manifest.local`

Key examples are in:

- `examples/env.manifest.global.example`
- `examples/env.manifest.local.example`

## Project Layout

```text
manifest.cli/
├── scripts/                 # Entrypoints and wrapper
├── modules/                 # Core, workflow, docs, git, system, pr, fleet, cloud, testing
├── docs/                    # User-facing docs and release docs
├── formula/                 # Homebrew formula source
├── install-cli.sh           # Installer
└── VERSION
```

## Notes

- `prep` requires an explicit release type.
- `ship` is the publish path; `pr` is handled explicitly via `manifest pr ...`.
- Some fleet subcommands are scaffolded and not fully implemented yet (`fleet prep`, `fleet docs`).

## Support

- Docs: `docs/INDEX.md`
- Issues: [https://github.com/fidenceio/manifest.cli/issues](https://github.com/fidenceio/manifest.cli/issues)
