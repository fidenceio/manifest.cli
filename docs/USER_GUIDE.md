# Manifest CLI User Guide

This guide covers how to use Manifest CLI as it is currently implemented (v42 command structure).

---

## The Five-Stage Journey

Manifest v42 organizes commands around a five-stage workflow that mirrors how developers actually work with a repository:

```text
config  -->  init  -->  prep  -->  refresh  -->  ship
```

1. **`manifest config`** — set up your environment (interactive wizard, show settings, diagnose issues).
2. **`manifest init repo|fleet`** — scaffold required files (VERSION, CHANGELOG, docs, .gitignore).
3. **`manifest prep repo|fleet`** — connect remotes and pull latest code.
4. **`manifest refresh repo|fleet`** — regenerate docs, metadata, fleet membership without a version change.
5. **`manifest ship repo|fleet <type>`** — publish a release (bump, docs, commit, tag, push, Homebrew).

Every journey command takes a **scope**: `repo` (single repository) or `fleet` (coordinated multi-repo).

Supported release types: `patch`, `minor`, `major`, `revision`.

---

## First-Time Setup

```bash
# View all available commands
manifest --help

# Scaffold your project (creates VERSION, CHANGELOG.md, docs/, .gitignore)
manifest init repo

# Review your current configuration
manifest config show

# Run the full test suite to verify installation
manifest test all

# Launch the interactive configuration wizard
manifest config setup
```

---

## Daily Commands

### Prepare Your Workspace

```bash
manifest prep repo             # Connect remotes if missing, pull latest
```

If no remote is configured and you are in a terminal, Manifest prompts for a remote URL.

### Preview a Release Locally

```bash
manifest ship repo patch --local    # Patch release, local only
manifest ship repo minor --local    # Minor release, local only
manifest ship repo -M --local       # Major release, short flag
manifest ship repo revision --local # Revision (e.g., 1.0.0.1)
```

The `--local` flag runs the full pipeline (sync, bump, docs, commit) but skips tagging, pushing, and Homebrew updates. Nothing leaves your machine.

### Publish a Release

```bash
manifest ship repo patch       # Full patch release
manifest ship repo minor       # Full minor release
manifest ship repo major -i    # Major release with interactive safety prompts
```

Ship runs: sync, version bump, documentation generation, markdown validation, commit, Git tag, push to all remotes, and Homebrew formula update (in the canonical repository).

### Regenerate Documentation

```bash
manifest refresh repo              # Regenerate docs and metadata
manifest refresh repo --commit     # Also commit the refreshed files
```

Use `refresh` between releases to keep docs current without bumping the version.

### Other Common Operations

```bash
manifest revert               # Revert to previous version
manifest security             # Run security audit
manifest upgrade              # Check for and install CLI updates
```

---

## Pull Request Workflows

```bash
manifest pr                   # Interactive PR wizard (TTY mode)
manifest pr create            # Create a new pull request
manifest pr create --draft --labels "feature,v2"
manifest pr update            # Update PR metadata
manifest pr status            # Show PR status
manifest pr checks            # Show CI check results
manifest pr checks --watch    # Watch checks in real-time
manifest pr ready             # Evaluate merge readiness
manifest pr queue             # Queue auto-merge
manifest pr queue --method squash --force
manifest pr policy show       # Display PR policy profile
manifest pr policy validate   # Validate against policy
```

---

## Fleet Workflows

Fleet manages versioning and releases across multiple repositories.

### Initialize a Fleet

```bash
# Phase 1: Scan directories, create manifest.fleet.tsv for review
manifest init fleet

# Phase 2: Re-run after reviewing TSV — scaffolds repos, creates fleet config
manifest init fleet

# Custom scan depth (default: 2 levels)
manifest init fleet --depth 3

# Named fleet
manifest init fleet --name "my-platform"
```

The two-phase approach lets you review discovered repositories in the TSV file before committing to a fleet configuration. During initialization, Manifest ensures every discovered repo has a `.gitignore`. Existing `.gitignore` files with entries are preserved; a `.gitignore.manifest` reference file is created instead.

### Prepare Fleet Workspace

```bash
manifest prep fleet                # Clone missing, pull existing
manifest prep fleet --parallel     # Run operations in parallel
manifest prep fleet --clone-only   # Clone only (skip pull)
manifest prep fleet --pull-only    # Pull only (skip clone)
```

### Refresh Fleet

```bash
manifest refresh fleet             # Re-scan membership, validate, regenerate docs
manifest refresh fleet --dry-run   # Preview changes without applying
```

### Ship Fleet Release

```bash
manifest ship fleet minor                  # Coordinated minor release
manifest ship fleet patch --safe           # With checks and readiness gates
manifest ship fleet minor --local          # Local-only across fleet
manifest ship fleet patch --method squash  # Squash merge strategy
manifest ship fleet minor --draft          # Create draft PRs
```

### Direct Fleet Commands

The legacy `manifest fleet <sub>` interface continues to work:

```bash
manifest fleet status --verbose    # Fleet status
manifest fleet discover --depth 3  # Find new repos
manifest fleet add ./new-service   # Add a service
manifest fleet validate            # Check configuration
manifest fleet pr queue            # Auto-merge PRs across fleet
manifest fleet help                # Fleet help
```

---

## Test Suites

Manifest includes 14 test suites:

```bash
manifest test all           # Run everything
manifest test versions      # Version increment logic
manifest test security      # Security checks
manifest test config        # Configuration loading
manifest test docs          # Documentation generation
manifest test git           # Git operations
manifest test time          # Timestamp verification
manifest test os            # OS detection
manifest test modules       # Module loading
manifest test integration   # End-to-end integration
manifest test cloud         # Manifest Cloud connectivity
manifest test agent         # Agent functionality
manifest test zsh           # Zsh compatibility
manifest test bash5         # Bash 5 compatibility
manifest test bash          # Basic Bash functionality
```

Flags:

- `--strict-redact` — sanitize logs for sharing (removes paths, tokens)
- `--no-strict-redact` — keep raw output

Test logs are written to `~/.manifest-cli/logs/tests/<run-id>/`.

---

## Configuration

### Interactive Setup

```bash
manifest config             # Interactive wizard (TTY) or show config (pipe)
manifest config setup       # Force interactive wizard
manifest config show        # Display current configuration
manifest config time        # Show time server settings
manifest config doctor      # Detect deprecated settings
manifest config doctor --fix      # Auto-fix deprecated settings
manifest config doctor --dry-run  # Preview fixes without applying
```

### Configuration Loading Order

Configuration uses YAML files loaded in priority order (later overrides earlier):

| Priority | File | Scope |
| -------- | ---- | ----- |
| 1 (lowest) | Code defaults | Built-in |
| 2 | `~/.manifest-cli/manifest.config.global.yaml` | User-wide |
| 3 | `manifest.config.yaml` | Project |
| 4 (highest) | `manifest.config.local.yaml` (git-ignored) | Local overrides |

All settings map to `MANIFEST_CLI_*` environment variables via a bidirectional YAML-to-env mapping in `manifest-yaml.sh`. The YAML parser is [yq v4+](https://github.com/mikefarah/yq) (Mike Farah's Go implementation), a hard dependency.

For the full configuration schema with comments on every key, see
[examples/manifest.config.yaml.example](../examples/manifest.config.yaml.example).

---

## Security and Maintenance

```bash
manifest security           # Run security audit
manifest upgrade --check    # Check for updates (no install)
manifest upgrade            # Install latest version
manifest upgrade --force    # Force upgrade regardless of version
manifest uninstall          # Remove Manifest CLI
manifest uninstall --force  # Remove without confirmation
manifest reinstall          # Full uninstall + reinstall cycle
```

### Git Hooks

Manifest ships pre-commit hooks that block common secret-leak paths before commit.
See [Git Hooks](GIT_HOOKS.md) for installation, recovery, and bypass procedures.

---

## Cloud and Agent

```bash
# Cloud (Manifest Cloud MCP connector)
manifest cloud config       # Configure API key and endpoint
manifest cloud status       # Show connection status
manifest cloud generate 1.0.0  # Generate docs via cloud

# Agent (containerized secure integration)
manifest agent init docker  # Initialize Docker-based agent
manifest agent auth github  # Set up GitHub OAuth
manifest agent auth manifest  # Set up Manifest Cloud subscription
manifest agent status       # Show agent status
manifest agent logs         # View agent logs
manifest agent uninstall    # Remove agent
```

Cloud features require `MANIFEST_CLI_CLOUD_API_KEY`. The cloud connector enriches
decisions but is never a hard runtime requirement.

---

## Legacy Command Compatibility

All pre-v42 commands continue to work. Some have changed meaning:

| Old Command | New Equivalent | Notes |
| ----------- | -------------- | ----- |
| `manifest prep patch` | `manifest ship repo patch --local` | Shows deprecation warning |
| `manifest ship patch` | `manifest ship repo patch` | Automatic redirect |
| `manifest sync` | `manifest prep repo` | Automatic redirect |
| `manifest fleet start` | `manifest init fleet` | Removed in v44.9.0 — emits migration hint |
| `manifest fleet init` | `manifest init fleet` | Removed in v44.9.0 — emits migration hint |
| `manifest fleet sync` | `manifest prep fleet` | Removed in v44.9.0 — emits migration hint |
| `manifest update` | `manifest upgrade` | Shows deprecation warning |
| `manifest docs` | `manifest refresh repo` | Still works as plumbing |
| `manifest cleanup` | `manifest refresh repo` | Still works as plumbing |
| `manifest time` | `manifest config time` | Still works |
| `manifest commit "msg"` | *(plumbing)* | Still works |
| `manifest version patch` | *(plumbing)* | Still works |

If you have scripts using the old commands, they will continue to function. Update them at your convenience.
