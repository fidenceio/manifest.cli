# Manifest CLI

**A deterministic release control plane for Git repositories.**

Manifest CLI orchestrates version bumping, documentation generation, Git tagging, remote publishing, and Homebrew distribution from a single command. It extends naturally to polyrepo fleets and pull request workflows without sacrificing single-repo simplicity.

**Version** `43.0.0` | **Platform** macOS, Linux, FreeBSD | **Requires** Bash 5+, Git, yq v4+

---

## Executive Summary

Software teams ship code constantly, yet the mechanical steps surrounding a release — bumping a version number, regenerating changelogs, tagging commits, pushing to remotes, updating package managers — remain tedious and error-prone. Manifest CLI exists to collapse that entire sequence into a single, auditable command.

### What It Does

Manifest CLI is a Bash-based command-line tool that manages the full lifecycle of a software release. Given a repository with a `VERSION` file and standard Git workflow, Manifest can:

1. **Initialize** a project with the scaffolding it needs (version file, changelog, documentation directory, gitignore rules).
2. **Prepare** the workspace by connecting remotes and pulling the latest state.
3. **Refresh** documentation, metadata, and fleet membership without changing the version.
4. **Ship** a release — bumping the version, generating release notes from Git history, committing, tagging, pushing to remotes, and updating the Homebrew formula — in one atomic operation.

For organizations managing multiple repositories (microservices, libraries, infrastructure-as-code), Manifest extends every operation to work across an entire **fleet** of repositories with coordinated versioning and unified documentation.

### How It Works

At its core, Manifest is a modular Bash application comprising 29 shell scripts organized into six functional categories: core dispatch, workflow orchestration, fleet management, Git operations, documentation generation, and system utilities. Optional modules (PR workflows, cloud integration, test suites, auto-upgrade) are loaded as plugins from Manifest Cloud when installed. The entry point ([manifest-core.sh](modules/core/manifest-core.sh)) sources core modules at startup, attempts to load optional plugins via [manifest-plugin-loader.sh](modules/core/manifest-plugin-loader.sh), and routes commands through a central dispatcher.

Configuration flows through a layered precedence system: code defaults are overridden by a global YAML config (`~/.manifest-cli/manifest.config.global.yaml`), then by a project-level config (`manifest.config.yaml`), and finally by a git-ignored local config (`manifest.config.local.yaml`). This hierarchy maps approximately 80 YAML dot-paths to `MANIFEST_CLI_*` environment variables via a bidirectional lookup table in [manifest-yaml.sh](modules/core/manifest-yaml.sh), which uses [yq](https://github.com/mikefarah/yq) (Mike Farah's Go implementation, v4+) as its sole YAML parser.

Every release is timestamped using trusted HTTPS sources (Cloudflare, Google, Apple) rather than relying on the local system clock. This makes release artifacts independently verifiable.

### Who It Is For

- **Small teams** that want deterministic releases without maintaining CI pipeline YAML.
- **Platform engineers** coordinating version bumps across dozens of microservice repositories.
- **Open-source maintainers** who need consistent changelogs, release notes, and Homebrew distribution.
- **Compliance-conscious organizations** that require auditable, timestamped release artifacts.

### Design Philosophy

Manifest follows three principles:

1. **Explicit over implicit.** Every version bump requires a type (`patch`, `minor`, `major`, `revision`). There is no "auto-detect what changed" magic.
2. **Local before remote.** The `--local` flag lets you preview every release operation on your machine before anything leaves it. Ship only when you are ready.
3. **Convention over configuration, but configurable.** Sensible defaults get you started immediately; 80+ configuration knobs let you customize everything from tag prefixes to timestamp servers.

---

## Quick Start

### Install

```bash
# Homebrew (recommended — installs Bash 5 and yq automatically)
brew tap fidenceio/tap
brew install manifest

# Or via install script
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

### Your First Release

```bash
cd your-project

# 1. Scaffold required files (VERSION, CHANGELOG.md, docs/, .gitignore)
manifest init repo

# 2. Connect remotes and pull latest
manifest prep repo

# 3. Ship a patch release (version bump + docs + tag + push)
manifest ship repo patch

# Or preview locally first, then publish when ready
manifest ship repo minor --local    # Local only — nothing pushed
manifest ship repo minor            # Full publish
```

### Verify Installation

```bash
manifest --help
manifest config show
manifest test all           # Requires Manifest Cloud
```

---

## Command Model

Manifest v42 organizes commands around a five-stage journey that mirrors how developers actually work with a repository:

```text
config  -->  init  -->  prep  -->  refresh  -->  ship
  |            |          |           |            |
 setup      scaffold   connect     update       publish
 wizard     files      remotes     docs/meta    release
```

Every journey command accepts a **scope** — `repo` for a single repository, `fleet` for coordinated multi-repo operations:

```bash
manifest <verb> <scope> [options]
```

### Core Journey Commands

| Command | Purpose |
| ------- | ------- |
| `manifest config` | Setup wizard, show config, diagnose issues |
| `manifest init repo\|fleet` | Scaffold files and directories |
| `manifest prep repo\|fleet` | Connect remotes, pull latest |
| `manifest refresh repo\|fleet` | Regenerate docs, metadata, fleet membership |
| `manifest ship repo\|fleet <type>` | Publish release (bump + docs + tag + push) |

### Ship Options

| Option | Effect |
| ------ | ------ |
| `manifest ship repo patch` | Full publish: bump, docs, commit, tag, push, Homebrew |
| `manifest ship repo minor --local` | Everything except tag, push, and Homebrew |
| `manifest ship repo major -i` | Interactive mode with safety prompts |
| `manifest ship fleet patch --safe` | Fleet release with checks and readiness gates |

Release types: `patch` | `minor` | `major` | `revision`

Short flags: `-p` (patch), `-m` (minor), `-M` (major), `-r` (revision), `-i` (interactive)

### Supporting Commands

| Command | Purpose |
| ------- | ------- |
| `manifest pr` | Interactive PR wizard \[Cloud\] |
| `manifest pr create\|status\|ready\|checks\|queue\|update` | PR lifecycle operations \[Cloud\] |
| `manifest revert` | Roll back to a previous version |

### Maintenance Commands

| Command | Purpose |
| ------- | ------- |
| `manifest upgrade` | Check for and install CLI updates \[Cloud\] |
| `manifest uninstall` | Remove Manifest CLI |
| `manifest reinstall` | Full uninstall + reinstall |
| `manifest security` | Run security audit |
| `manifest test [suite]` | Run diagnostic tests \[Cloud\] |

### Cloud and Agent \[Cloud\]

| Command | Purpose |
| ------- | ------- |
| `manifest cloud config\|status\|generate` | Manifest Cloud connector |
| `manifest agent init\|auth\|status` | Containerized cloud agent |

> Commands marked \[Cloud\] require [Manifest Cloud](https://github.com/fidenceio/fidenceio.manifest.cloud) to be installed. The CLI works fully without Cloud for the core journey (config, init, prep, refresh, ship).

### Legacy Aliases (Hidden)

All pre-v42 commands continue to work. They are not shown in `manifest --help` but remain fully functional:

| Old Command | Routes To |
| ----------- | --------- |
| `manifest prep patch` | `manifest ship repo patch --local` (with deprecation warning) |
| `manifest ship patch` | `manifest ship repo patch` |
| `manifest sync` | `manifest prep repo` |
| `manifest fleet <sub>` | `fleet_main` (unchanged behavior) |
| `manifest time` | `display_time_info` |
| `manifest update` | `manifest upgrade` (with deprecation warning) |
| `manifest docs` | Documentation generation (plumbing) |
| `manifest cleanup` | Archive old docs (plumbing) |
| `manifest commit <msg>` | Commit with timestamp (plumbing) |
| `manifest version <type>` | Bump version only (plumbing) |

> See [Command Reference](docs/COMMAND_REFERENCE.md) for the complete surface area.

---

## Fleet: Polyrepo Orchestration

Manifest Fleet manages versioning and releases across multiple repositories from a single workspace.

### Initialize

```bash
# Two-phase initialization:
# Phase 1: Scan directories, create manifest.fleet.tsv for review
manifest init fleet

# Phase 2: Re-run after reviewing TSV — scaffolds repos, creates fleet config
manifest init fleet

# Custom scan depth (default: 2 levels)
manifest init fleet --depth 3

# Named fleet with forced overwrite
manifest init fleet --name "platform-services" --force
```

### Day-to-Day Operations

```bash
# Prepare fleet workspace (clone missing, pull existing)
manifest prep fleet
manifest prep fleet --parallel

# Refresh fleet (re-scan membership, regenerate docs, validate)
manifest refresh fleet
manifest refresh fleet --dry-run

# Coordinated release
manifest ship fleet minor
manifest ship fleet patch --safe

# Preview fleet release locally
manifest ship fleet minor --local
```

### Direct Fleet Commands (Legacy)

The `manifest fleet <sub>` interface continues to work:

```bash
manifest fleet status --verbose
manifest fleet discover --depth 3
manifest fleet add ./services/new-api --name "new-api"
manifest fleet validate
manifest fleet pr queue --method squash
```

> See [Fleet Design Spec](docs/FLEET_DESIGN_SPEC.md) for architecture details.

---

## Pull Request Workflows \[Cloud\]

Requires [Manifest Cloud](https://github.com/fidenceio/fidenceio.manifest.cloud).

```bash
manifest pr                         # Interactive PR wizard
manifest pr create --draft --labels "feature,v2"
manifest pr checks --watch          # Watch CI checks in real-time
manifest pr ready                   # Evaluate merge readiness
manifest pr queue --method squash   # Queue auto-merge
manifest pr policy show             # Display PR policy profile
```

PR operations are policy-aware and support configurable merge strategies.

---

## Configuration

Configuration loads in priority order (later overrides earlier):

| Priority | File | Scope |
| -------- | ---- | ----- |
| 1 (lowest) | Code defaults | Built-in |
| 2 | `~/.manifest-cli/manifest.config.global.yaml` | User-wide |
| 3 | `manifest.config.yaml` | Project |
| 4 (highest) | `manifest.config.local.yaml` (git-ignored) | Local overrides |

All configuration is YAML-based. Approximately 80 settings map to `MANIFEST_CLI_*` environment variables. The YAML parser is [yq v4+](https://github.com/mikefarah/yq) (Mike Farah's Go implementation), a hard dependency validated at install time.

```bash
manifest config               # Interactive wizard (TTY) or show config
manifest config show          # Display effective configuration
manifest config setup         # Force interactive wizard
manifest config doctor        # Detect deprecated settings
manifest config doctor --fix  # Auto-fix deprecated settings
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
- **Installation directory guard** prevents running from the CLI install directory

> See [Git Hooks](docs/GIT_HOOKS.md) for hook installation and recovery procedures.

---

## Architecture

### Module Organization

```text
manifest.cli/
├── scripts/            Entry points and CLI wrapper
├── modules/
│   ├── core/           Dispatcher, config, YAML, shared functions
│   │   ├── manifest-core.sh             Main dispatcher (routes all commands)
│   │   ├── manifest-plugin-loader.sh    Plugin loader for optional Cloud modules
│   │   ├── manifest-config.sh           Layered YAML config loading
│   │   ├── manifest-yaml.sh             yq-based YAML parser + env var mapping
│   │   ├── manifest-init.sh             init repo|fleet (v42)
│   │   ├── manifest-prep.sh             prep repo|fleet (v42)
│   │   ├── manifest-refresh.sh          refresh repo|fleet (v42)
│   │   ├── manifest-ship.sh             ship repo|fleet (v42)
│   │   ├── manifest-shared-functions.sh Version math, file scaffolding
│   │   └── manifest-shared-utils.sh     Logging, formatting, guards
│   ├── workflow/       Orchestration engine (prep/ship pipeline)
│   ├── fleet/          Fleet dispatcher, config, detection, docs
│   ├── git/            Git operations and change analysis
│   ├── docs/           Documentation generation and validation
│   ├── system/         OS detection, timestamps, security, uninstall
│   └── stubs/          Fallback stubs for optional Cloud modules
├── docs/               User-facing documentation and release notes
├── formula/            Homebrew formula source
├── examples/           Configuration templates
├── .git-hooks/         Version-controlled pre-commit hooks
├── install-cli.sh      Installer (validates Bash 5+, yq v4+, Git)
└── VERSION             Current version file
```

Optional modules (PR, cloud, testing, auto-upgrade) live in the [Manifest Cloud](https://github.com/fidenceio/fidenceio.manifest.cloud) repo under `cli-plugins/` and are loaded at runtime when installed to `~/.manifest-cloud/cli-plugins/`.

### Data Flow

```text
User command
    │
    ▼
manifest-core.sh :: main()
    │
    ├─ Pre-dispatch: load config, validate git repo
    │
    ├─ Core journey dispatch ──► manifest-init.sh
    │                           manifest-prep.sh
    │                           manifest-refresh.sh
    │                           manifest-ship.sh
    │                               │
    │                               ▼
    │                       manifest-orchestrator.sh :: manifest_prep_workflow()
    │                           │
    │                           ├── sync_repository()          [git module]
    │                           ├── bump_version()             [git module]
    │                           ├── generate_documents()       [docs module]
    │                           ├── main_cleanup()             [docs module]
    │                           ├── validate_project()         [docs module]
    │                           ├── commit_changes()           [git module]
    │                           ├── create_tag()               [git module]
    │                           ├── push_changes()             [git module]
    │                           └── update_homebrew_formula()   [core module]
    │
    ├─ Fleet dispatch ──► manifest-fleet.sh :: fleet_main()
    │                       ├── fleet-config.sh   (YAML parsing)
    │                       ├── fleet-detect.sh   (auto-discovery)
    │                       └── fleet-docs.sh     (unified docs)
    │
    ├─ PR dispatch ──► manifest-pr.sh        [Cloud plugin]
    │
    └─ Legacy aliases ──► (route to new implementations)
```

### Configuration Pipeline

```text
Code defaults (set_default_configuration)
    │
    ▼
~/.manifest-cli/manifest.config.global.yaml    ← User-wide
    │
    ▼
manifest.config.yaml                           ← Project-level
    │
    ▼
manifest.config.local.yaml (.gitignored)       ← Local overrides
    │
    ▼
~80 MANIFEST_CLI_* environment variables       ← Runtime state
    │
    ▼
_MANIFEST_YAML_TO_ENV[] bidirectional map      ← In manifest-yaml.sh
```

---

## Dependencies

| Dependency | Version | Purpose | Install |
| ---------- | ------- | ------- | ------- |
| Bash | 5.0+ | Shell runtime (macOS ships 3.2) | `brew install bash` |
| Git | Any recent | Version control operations | `brew install git` |
| yq | 4.0+ (Mike Farah's Go version) | YAML configuration parsing | `brew install yq` |
| curl | Any | HTTPS timestamps, API calls | Usually pre-installed |
| coreutils | Any (optional) | Cross-platform date/stat | `brew install coreutils` |

Homebrew installation handles all dependencies automatically. The install script validates Bash 5+ and yq v4+ with platform-specific error messages and install instructions.

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
| [Release Notes](docs/RELEASE_v42.0.3.md) | Current release details |

---

## Support

- **Documentation**: [docs/INDEX.md](docs/INDEX.md)
- **Issues**: [github.com/fidenceio/manifest.cli/issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [github.com/fidenceio/manifest.cli/discussions](https://github.com/fidenceio/manifest.cli/discussions)
