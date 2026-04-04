# Manifest CLI User Guide

This guide covers how to use Manifest CLI as it is currently implemented (v39.0.0).

---

## Release Workflow Model

Manifest separates release preparation from publishing:

- **`manifest prep <type>`** — local-only release preparation (sync, version bump, docs, commit).
  Nothing leaves your machine.
- **`manifest ship <type>`** — full publish flow (prep + Git tag + remote push + Homebrew formula update).
- **`manifest pr ...`** — pull request lifecycle operations.
- **`manifest fleet ...`** — coordinated multi-repo operations.

Supported release types: `patch`, `minor`, `major`, `revision`.

---

## First-Time Setup

```bash
# View all available commands
manifest --help

# Review your current configuration
manifest config show

# Run the full test suite to verify installation
manifest test all

# Launch the interactive configuration wizard
manifest config setup
```

---

## Daily Commands

### Prepare a Release (Local Only)

```bash
manifest prep patch       # Patch release
manifest prep minor       # Minor release
manifest prep -M          # Major release (short flag)
manifest prep revision    # Revision (e.g., 1.0.0.1)
```

Prep runs: sync, version bump, documentation generation, markdown validation, commit.
It does **not** create tags, push to remotes, or update Homebrew.

### Publish a Release

```bash
manifest ship minor       # Full publish flow
manifest ship patch -i    # Interactive mode (confirmation prompts)
```

Ship runs everything prep does, then: creates a Git tag, pushes to all remotes,
and updates the Homebrew formula (in the canonical repository).

### Other Common Operations

```bash
manifest sync             # Pull latest from remote
manifest version patch    # Bump version without full prep
manifest docs             # Regenerate docs for current version
manifest docs metadata    # Update repository metadata
manifest commit "msg"     # Commit with a custom message
manifest revert           # Revert to previous version
manifest cleanup          # Archive old documentation
```

---

## Pull Request Workflows

```bash
manifest pr               # Interactive PR wizard (TTY mode)
manifest pr create        # Create a new pull request
manifest pr create --draft --labels "feature,v2"
manifest pr update        # Update PR metadata
manifest pr status        # Show PR status
manifest pr checks        # Show CI check results
manifest pr checks --watch  # Watch checks in real-time
manifest pr ready         # Evaluate merge readiness
manifest pr queue         # Queue auto-merge
manifest pr queue --method squash --force
manifest pr policy show   # Display PR policy profile
manifest pr policy validate  # Validate against policy
```

---

## Fleet Workflows

Fleet manages versioning and releases across multiple repositories.

### Initialize a Fleet

```bash
# Auto-discover repos in your workspace (default behavior)
manifest fleet init

# Auto-discover with a custom fleet name
manifest fleet init --name "my-platform"

# Skip discovery, create a bare template
manifest fleet init --bare

# Overwrite existing fleet config
manifest fleet init --force
```

During initialization, Manifest ensures every discovered repo has a `.gitignore`.
Existing `.gitignore` files with entries are preserved; a `.gitignore.manifest`
reference file is created instead.

### Fleet Operations

```bash
manifest fleet discover          # Find new repos in workspace
manifest fleet discover --depth 3 --json
manifest fleet status            # Overview of all services
manifest fleet status --verbose
manifest fleet sync              # Clone/pull all services
manifest fleet sync --parallel
manifest fleet validate          # Check fleet configuration
manifest fleet add ./new-service # Add a service to the fleet
manifest fleet ship minor --safe # Coordinated release with safety gates
manifest fleet pr queue          # Auto-merge PRs across fleet
```

**Current status:** `fleet prep` and `fleet docs` are scaffolded and not yet implemented.

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
manifest config             # Interactive wizard (TTY)
manifest config setup       # Force interactive wizard
manifest config show        # Display current configuration
manifest config time        # Show time server settings
manifest config doctor      # Detect deprecated settings
manifest config doctor --fix  # Auto-fix deprecated settings
manifest config doctor --dry-run  # Preview fixes without applying
```

### Configuration Loading Order

Configuration files are loaded in this order (later files override earlier ones):

1. **Install-level:** `.env.manifest.global`, `.env.manifest.local` (under install dir)
2. **User-level:** `$HOME/.env.manifest.global`
3. **Project-level:** `.env.manifest.global`, `.env.manifest.local`

For configuration templates covering enterprise, compliance, open-source, and specialized
use cases, see [Configuration Examples](../examples/env.manifest.examples.md).

---

## Security and Maintenance

```bash
manifest security           # Run security audit
manifest cleanup            # Archive old documentation
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
