# Manifest CLI

**The release layer for AI-era developers.**

When you can spin up four features in parallel, you also need to ship four features without dropping any. Manifest handles versions, tags, changelogs, docs, and the multi-repo coordination so the human stays in flow.

[![tests](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml/badge.svg)](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml)
**Version** `47.2.0` · **Platform** macOS · Linux · FreeBSD · **Requires** Bash 5+, Git, yq v4+

---

## Why it exists

The bottleneck of modern dev work has shifted. Writing the code is no longer the slow part — maintaining coherent shipping across repos and in-flight changes is. Manifest solves this.

- **One command per repo, the same command across a fleet.** `manifest ship repo patch` and `manifest ship fleet patch` do the same five things — version bump, docs, commit, tag, push — at one repo or across all of them, with synced version metadata.
- **Read-only first.** `manifest status` answers "what would happen if I shipped now?" before you act. `manifest doctor` answers "is my environment OK?" with a single command.
- **No silent surprises.** Auto-migrations and global-config writes go through a confirmation gate (`MANIFEST_CLI_AUTO_CONFIRM=1` for CI). The CLI never rewrites your settings without telling you.
- **PRs are first-class and Cloud-free.** `manifest pr create / status / checks / ready / merge / update` ride on top of `gh` — no paid dependency for what GitHub already gives you. Cloud extends with `pr queue` (auto-merge orchestration) and `pr policy`.
- **Fleet-aware out of the box.** A repo of repos becomes a fleet with one TSV file. Every verb gains a `fleet` scope.

### Design principles

1. **Explicit over implicit.** You name the bump (`patch | minor | major | revision`). No "auto-detect what changed" magic.
2. **Local before remote.** `--local` previews every release op on your machine. Push only when you're sure.
3. **Read-only diagnostics are first-class.** `status` and `doctor` exist precisely because the rest of the CLI is consequential. Look before you ship.
4. **Tested and CI-gated.** A broad bats-core suite exercises release flow, YAML layering, version bumps, canonical-repo detection, safety gates, status output, Homebrew packaging, and recovery paths. CI runs it on macOS and Linux on every push.

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
manifest doctor             # one-command health check (deps + config + repo)
manifest status             # what would happen if I shipped now?
```

---

## A 30-second tour

Each block below shows the current command shape from this repo -- representative, not aspirational.

**`manifest status`** — read-only snapshot. Auto-detects repo vs fleet context; use `manifest status repo` or `manifest status fleet` to force a scope.

```text
Manifest status
===============
  Repository:  fidenceio/manifest.cli  (canonical — Homebrew formula updates here)
  Branch:      main → origin/main  (in sync)

Repo identity
-------------
  Git root:    /Users/you/coderepos/manifest/fidenceio.manifest.cli
  Origin:      fidenceio/manifest.cli
  Branch:      main → origin/main
  Fleet:       not detected
  Target:      this Git repository only
  Working:     clean
  Version:     46.9.0
               patch → 46.9.1
               minor → 46.10.0
               major → 47.0.0
  Mode:        single-repo
  Config:      ✓ global   /Users/you/.manifest-cli/manifest.config.global.yaml
               · project  /Users/you/coderepos/manifest/fidenceio.manifest.cli/manifest.config.yaml
               · local    /Users/you/coderepos/manifest/fidenceio.manifest.cli/manifest.config.local.yaml
```

**`manifest doctor`** — every dependency, every config layer, every repo state, in one screen.

```text
Manifest doctor
===============

Dependencies:
  ✓ yq                     yq (https://github.com/mikefarah/yq/) version v4.53.2
  ✓ git                    git version 2.54.0
  ✓ Bash                   5.3.9(1)-release
  ✓ gh (optional)          gh version 2.91.0

Configuration:
  ✓ Global config          /Users/you/.manifest-cli/manifest.config.global.yaml
  ✓ Schema version         2 (current)
  ✓ Config drift           none

Repository:
  ✓ Git repository         /path/to/your/project
  ✓ Origin remote          git@github.com:org/repo.git
  ✓ Canonical repo         no (normal for user projects)
  ✓ VERSION file           1.4.2

  All good.
```

**`manifest config describe <key>`** — every key has a layer trail and an env-var name. No more reading source to find config options.

```text
Key:       git.tag_prefix
Env var:   MANIFEST_CLI_GIT_TAG_PREFIX
Effective: v  (from defaults)

Layers (highest precedence first):
  local    ·   (./manifest.config.local.yaml — not present)
  project  ·   (./manifest.config.yaml — not present)
  global   ·   (/Users/you/.manifest-cli/manifest.config.global.yaml)
```

Pair with `manifest config list` (all 80+ keys + their effective layer) and `manifest config set --layer local <key> <value>` (writes to git-ignored local; writing global goes through the safety gate).

**`manifest pr` — native, no Cloud needed.** Thin `gh` wrappers. Cloud extends with queue and policy.

```text
Manifest PR — native (gh wrapper)

Usage:
  manifest pr                       Show current PR or prompt to create
  manifest pr create [--draft]      Create a PR from current branch
  manifest pr status [<n|branch>]   View PR details
  manifest pr checks [<n|branch>]   Show CI check status (--watch to poll)
  manifest pr ready [<n|branch>]    Mark a draft PR as ready
  manifest pr merge [<n|branch>]    Merge a PR (defaults to squash)
  manifest pr update [<n|branch>]   Update PR branch with base

Cloud-only (requires Manifest Cloud):
  manifest pr queue                 Auto-merge orchestration
  manifest pr policy show|validate  Org policy enforcement
```

**Tab completion** — drop one file in your shell's completions dir.

```sh
# bash
ln -s $(pwd)/completions/manifest.bash $(brew --prefix)/etc/bash_completion.d/manifest
# zsh
ln -s $(pwd)/completions/_manifest $(brew --prefix)/share/zsh/site-functions/_manifest
```

You then get `manifest <TAB>` for top commands, `manifest plan <TAB>` -> `fleet`, `manifest config get <TAB>` -> all 80+ config keys, etc. See [completions/README.md](completions/README.md).

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
| `manifest recipe <list\|show\|explain\|run>` | Inspect and explicitly run workflow recipes |

### Ship Options

| Option | Effect |
| ------ | ------ |
| `manifest ship repo patch` | Full publish: bump, docs, commit, tag, push, Homebrew |
| `manifest ship repo minor --local` | Everything except tag, push, and Homebrew |
| `manifest ship repo patch --explain` | Show the built-in recipe definition without running it |
| `manifest ship repo major -i` | Interactive mode with safety prompts |
| `manifest ship fleet patch --safe` | Fleet release with checks and readiness gates |

Release types: `patch` | `minor` | `major` | `revision`

Short flags: `-p` (patch), `-m` (minor), `-M` (major), `-r` (revision), `-i` (interactive)

### Read-Only Diagnostics

| Command | Purpose |
| ------- | ------- |
| `manifest status` | Repo status, or fleet repo table with branch/state/version/timestamp/latest commit |
| `manifest doctor` | Dependency, configuration, and repository health check |
| `manifest config list \| get \| describe` | Discover all 80+ configuration keys + their layer source |

### Supporting Commands

| Command | Purpose |
| ------- | ------- |
| `manifest pr` | Show current PR or prompt to create (gh wrapper) |
| `manifest pr create\|status\|checks\|ready\|merge\|update` | PR lifecycle (native, no Cloud needed) |
| `manifest pr queue\|policy` | Auto-merge orchestration, policy enforcement \[Cloud\] |
| `manifest revert` | Roll back to a previous version |

### Maintenance Commands

| Command | Purpose |
| ------- | ------- |
| `manifest upgrade` | Check for and install CLI updates \[Cloud\] |
| `manifest uninstall` | Remove Manifest CLI (preserves global config — double-confirm to delete) |
| `manifest reinstall` | Full uninstall + reinstall |
| `manifest security` | Run security audit and write reports |
| `manifest security --check` | Run read-only security checks |
| `manifest test [suite]` | Run diagnostic tests \[Cloud\] |

### Cloud and Agent \[Cloud\]

| Command | Purpose |
| ------- | ------- |
| `manifest cloud config\|status\|generate` | Manifest Cloud connector |
| `manifest agent init\|auth\|status` | Containerized cloud agent |

> Commands marked \[Cloud\] require [Manifest Cloud](https://github.com/fidenceio/fidenceio.manifest.cloud) to be installed. The CLI works fully without Cloud for the core journey (config, init, prep, refresh, ship).

### Internal Plumbing And Removed Routes

| Old Command | Routes To |
| ----------- | --------- |
| `manifest prep patch` | `manifest ship repo patch --local` (with deprecation warning) |
| `manifest ship patch` | `manifest ship repo patch` |
| `manifest sync` | `manifest prep repo` |
| `manifest fleet <action>` | Removed; use `manifest <action> fleet` |
| `manifest time` | `display_time_info` |
| `manifest update` | Removed as an upgrade alias; use `manifest upgrade` |
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
# Phase 1: Scan directories, choose repo depth per folder, create manifest.fleet.tsv
manifest init fleet
manifest init fleet --dry-run

# Phase 2: Re-run after reviewing TSV — scaffolds repos, creates fleet config
manifest init fleet
manifest init fleet --dry-run

# Custom scan depth (default: 2 levels)
manifest init fleet --depth 3

# Exhaustive review mode: list every scanned folder in manifest.fleet.tsv
manifest init fleet --all-folders

# Named fleet with forced overwrite
manifest init fleet --name "platform-services" --force
```

Fleet adoption and conversion commands are safe to explore by default:

```bash
manifest plan fleet              # Dry-run: inspect the adoption plan
manifest plan fleet --apply      # Write manifest.fleet.plan.yaml
manifest reconcile fleet         # Dry-run: validate and explain actions
manifest reconcile fleet --do    # Apply local changes (--do == --apply)
```

`--commit` requires `--apply`/`--do`, and `--push` requires `--commit`.

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

### Direct Fleet Commands

Fleet commands use action-first syntax:

```bash
manifest status fleet
manifest discover fleet --depth 3
manifest add fleet ./services/new-api --name "new-api" --dry-run
manifest validate fleet
manifest docs fleet --dry-run
manifest pr fleet queue --method squash
```

> See [Fleet Design Spec](docs/FLEET_DESIGN_SPEC.md) for architecture details.

---

## Pull Request Workflows

Native operations require only `gh` ([GitHub CLI](https://cli.github.com/)). Install it once and `manifest pr` is fully functional.

```bash
manifest pr                         # Show current PR or prompt to create
manifest pr create --draft          # Create a PR (any unrecognized flags forward to gh)
manifest pr checks --watch          # Watch CI checks in real-time
manifest pr ready                   # Mark a draft PR as ready
manifest pr merge --squash          # Merge (default is squash)
manifest pr update                  # Update PR branch from base
```

The advanced subcommands require [Manifest Cloud](https://github.com/fidenceio/fidenceio.manifest.cloud):

```bash
manifest pr queue --method squash   # Auto-merge orchestration with policy gates
manifest pr policy show             # Display org policy profile
manifest pr policy validate         # Validate the current PR against policy
```

If Cloud isn't installed, the queue/policy subcommands fail loudly with an install hint — every other PR command keeps working.

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
manifest config doctor --fix  # Auto-fix deprecated settings (gated by safety prompt)

# CRUD over individual keys (layer-aware):
manifest config list                              # All keys + effective layer
manifest config get   git.tag_prefix              # Read effective value
manifest config set   git.tag_prefix release-     # Writes to local layer (default)
manifest config set --layer global  …             # Writes to global, with double-confirm
manifest config unset git.tag_prefix              # Remove from a layer
manifest config describe git.tag_prefix           # Per-layer values + env-var name
```

> See [examples/manifest.config.yaml.example](examples/manifest.config.yaml.example) for the complete YAML config schema.

### Safety gate for global config

Anything that modifies or deletes `~/.manifest-cli/manifest.config.global.yaml` (auto-migrations, `config doctor --fix`, `config set --layer global`, `uninstall`) goes through `_confirm_global_config_write`. Modifications prompt once; destructive operations require typing `yes` twice. CI/scripted contexts can opt in with `MANIFEST_CLI_AUTO_CONFIRM=1`.

---

## Security

Manifest includes layered security protections:

- **Pre-commit hooks** scan staged content for secrets, tokens, and private environment files
- **`.gitignore` enforcement** ensures sensitive files are excluded from version control
- **Smart `.gitignore` scaffolding** creates best-practice ignore rules for new projects
- **Large file detection** warns before accidentally committing binaries
- **Security audit** via `manifest security`, with `manifest security --check` for read-only automation
- **Installation directory guard** prevents running from the CLI install directory

> See the [Git Hooks](docs/USER_GUIDE.md#git-hooks) section of the User Guide for hook installation and recovery procedures.

---

## Testing

Manifest ships with a [bats-core](https://github.com/bats-core/bats-core) test suite covering release flow, YAML layering, version-bump logic, canonical-repo detection, config safety gates, fleet workflows, JSON output, Homebrew packaging, local tap refresh, and recovery paths. CI runs the suite on Ubuntu and macOS on every push and pull request.

```sh
./scripts/run-tests-container.sh
```

Test layout includes:

```text
tests/
├── helpers/setup.bash         Shared scratch dirs and module loaders
├── ship_resume.bats           Post-push recovery behavior
├── tag_target.bats            Exact tag naming and push semantics
├── homebrew_tap_refresh.bats  Safe local Homebrew tap checkout refresh
├── homebrew_wrapper.bats      Installed-wrapper and formula smoke tests
├── recipe.bats                Recipe introspection and ship --explain
├── status.bats                Repo identity, working-tree counts, JSON status
├── fleet_*.bats               Fleet init, refresh, ship, filtering, and dry-run flows
├── config_*.bats              YAML-backed config and safety gates
└── *_*.bats                   Focused regression coverage for command surfaces
```

CI workflow: [.github/workflows/test.yml](.github/workflows/test.yml). Adding new tests is documented in [tests/README.md](tests/README.md).

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
    │                       manifest-orchestrator.sh :: manifest_ship_workflow()
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
| [YAML config example](examples/manifest.config.yaml.example) | Full schema with all keys + comments |
| [North Star](docs/NORTH_STAR.md) | Strategic direction and priorities |
| [Release Notes](docs/RELEASE_v46.13.10.md) | Current release details |

---

## Support

- **Documentation**: [docs/INDEX.md](docs/INDEX.md)
- **Issues**: [github.com/fidenceio/manifest.cli/issues](https://github.com/fidenceio/manifest.cli/issues)
- **Discussions**: [github.com/fidenceio/manifest.cli/discussions](https://github.com/fidenceio/manifest.cli/discussions)
