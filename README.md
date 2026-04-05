# Manifest CLI

**A deterministic release control plane for Git repositories.**

Manifest CLI orchestrates version bumping, documentation generation, Git tagging, remote publishing, and Homebrew distribution — all from a single command. It extends naturally to polyrepo fleets and pull request workflows without sacrificing single-repo simplicity.

**Version** `41.1.0` | **Platform** macOS, Linux, FreeBSD | **Requires** Bash 5+, Git

---

## Why Manifest?

Most release tooling either does too little (tag-and-push scripts) or too much (opinionated CI platforms). Manifest sits in the middle:

- **Explicit release types** — every version bump requires `patch`, `minor`, `major`, or `revision`. No magic.
- **Prep vs Ship split** — `prep` keeps everything local for review; `ship` publishes. You choose when changes leave your machine.
- **Deterministic artifacts** — changelogs, release notes, and metadata are generated from Git history with trusted HTTPS timestamps.
- **Fleet-native** — coordinate releases across dozens of repositories with auto-discovery and per-repo `.gitignore` scaffolding.
- **Security-first** — pre-commit hooks block secrets, staged content is scanned, and `.gitignore` best practices are enforced automatically.

---

## Quick Start

### Install

```bash
# Homebrew (recommended)
brew tap fidenceio/tap
brew install manifest

# Or via install script
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

### Your First Release

```bash
cd your-project

# Prepare a patch release (local only — nothing is pushed)
manifest prep patch

# When ready, publish a minor release (tag + push + Homebrew update)
manifest ship minor
```

### Verify Installation

```bash
manifest --help
manifest test all
```

---

## Core Commands

| Command | Purpose |
| ------- | ------- |
| `manifest prep <type>` | Local release preparation (sync, bump, docs, commit) |
| `manifest ship <type>` | Full publish (prep + tag + push + Homebrew formula) |
| `manifest pr <sub>` | Pull request lifecycle (create, status, checks, queue) |
| `manifest fleet <sub>` | Polyrepo coordination (init, discover, sync, ship) |
| `manifest docs` | Regenerate documentation for the current version |
| `manifest config` | Interactive configuration wizard |
| `manifest test [suite]` | Run test suites (14 available) |
| `manifest security` | Security audit and vulnerability scan |
| `manifest sync` | Pull latest changes from remote |
| `manifest upgrade` | Check for and install CLI updates |

Release types: `patch` | `minor` | `major` | `revision`

Short flags: `-p` (patch), `-m` (minor), `-M` (major), `-r` (revision), `-i` (interactive)

> See [Command Reference](docs/COMMAND_REFERENCE.md) for the complete surface area.

---

## Fleet: Polyrepo Orchestration

Manifest Fleet manages versioning across multiple repositories from a single workspace.

```bash
# Initialize fleet with auto-discovery (finds all Git repos in your workspace)
manifest fleet init

# Skip discovery and create a bare template
manifest fleet init --bare

# Coordinated release across all services
manifest fleet ship minor --safe
```

Fleet auto-discovers repositories, generates `manifest.fleet.yaml`, and ensures every repo has a properly configured `.gitignore`. Existing `.gitignore` files with entries are never overwritten — Manifest creates a `.gitignore.manifest` reference file instead.

> See [Fleet Design Spec](docs/FLEET_DESIGN_SPEC.md) for architecture details.

---

## Pull Request Workflows

```bash
manifest pr create --draft          # Create a draft PR
manifest pr checks --watch          # Watch CI checks in real-time
manifest pr ready                   # Evaluate merge readiness
manifest pr queue --method squash   # Queue auto-merge with squash strategy
```

PR operations are policy-aware and support configurable merge strategies.

---

## Configuration

Configuration loads in priority order:

| Level | File | Scope |
| ----- | ---- | ----- |
| Install | `.env.manifest.global` (under install dir) | Shared defaults |
| User | `$HOME/.env.manifest.global` | Personal preferences |
| Project | `.env.manifest.global`, `.env.manifest.local` | Repo-specific |

```bash
manifest config setup       # Interactive wizard
manifest config show        # Display current config
manifest config doctor      # Detect and fix deprecated settings
```

> See [Configuration Examples](examples/env.manifest.examples.md) for templates covering enterprise, compliance, open-source, and more.

---

## Security

Manifest includes layered security protections:

- **Pre-commit hooks** scan staged content for secrets, tokens, and private environment files
- **`.gitignore` enforcement** ensures sensitive files are excluded from version control
- **Smart `.gitignore` scaffolding** creates best-practice ignore rules for new projects
- **Large file detection** warns before accidentally committing binaries
- **Security audit** via `manifest security` for on-demand vulnerability scanning

> See [Git Hooks](docs/GIT_HOOKS.md) for hook installation and recovery procedures.

---

## Project Layout

```text
manifest.cli/
├── scripts/          # Entry points and CLI wrapper
├── modules/
│   ├── core/         # Dispatcher, shared functions, config, env management
│   ├── workflow/     # Prep/ship orchestration, auto-upgrade
│   ├── fleet/        # Fleet init, discover, sync, ship, PR, docs
│   ├── git/          # Git operations and change analysis
│   ├── pr/           # Pull request lifecycle management
│   ├── docs/         # Documentation generation and validation
│   ├── system/       # OS detection, timestamps, security, uninstall
│   ├── cloud/        # Manifest Cloud MCP connector and agent
│   └── testing/      # Test framework and compatibility suites
├── docs/             # User-facing documentation and release notes
├── formula/          # Homebrew formula source
├── examples/         # Configuration templates
├── .git-hooks/       # Version-controlled pre-commit hooks
├── install-cli.sh    # Installer (Homebrew-aware)
└── VERSION           # Current version file
```

---

## Documentation

| Document | Description |
| -------- | ----------- |
| [User Guide](docs/USER_GUIDE.md) | Complete usage guide with workflows |
| [Command Reference](docs/COMMAND_REFERENCE.md) | Every command, flag, and option |
| [Examples](docs/EXAMPLES.md) | Real-world workflow recipes |
| [Installation](docs/INSTALLATION.md) | Setup, upgrade, and troubleshooting |
| [Fleet Design Spec](docs/FLEET_DESIGN_SPEC.md) | Polyrepo architecture and design |
| [Git Hooks](docs/GIT_HOOKS.md) | Secret protection and hook management |
| [Configuration Examples](examples/env.manifest.examples.md) | Templates for every use case |
| [North Star](docs/NORTH_STAR.md) | Strategic direction and priorities |
| [Release Notes](docs/RELEASE_v41.1.0.md) | Current release details |

---

## Support

- **Documentation**: [docs/INDEX.md](docs/INDEX.md)
- **Issues**: [github.com/fidenceio/manifest.cli/issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [github.com/fidenceio/manifest.cli/discussions](https://github.com/fidenceio/manifest.cli/discussions)
