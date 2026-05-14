# Manifest CLI Examples

Real-world command examples for current Manifest CLI workflows.

---

## New Project Setup

### From Scratch

```bash
mkdir my-project && cd my-project
manifest init repo                     # Preview VERSION, CHANGELOG.md, docs/, .gitignore, git init
manifest init repo -y                  # Create VERSION, CHANGELOG.md, docs/, .gitignore, git init
manifest config setup                  # Interactive configuration wizard
manifest prep repo                     # Preview remote prep
manifest prep repo -y                  # Prompts for remote URL, pulls latest
```

### Existing Repository

```bash
cd existing-project
manifest init repo                     # Idempotent — creates only missing files
manifest config show                   # Review effective configuration
```

---

## Release Workflows

### Patch Release (Preview Locally First)

```bash
git add .
git commit -m "fix: address edge case in parser"
manifest doctor
manifest ship repo patch --local       # Preview: bump, docs, commit — no push
manifest ship repo patch --local -y    # Apply local-only release prep
# Review the changes...
manifest ship repo patch               # Preview full publish: tag, push, Homebrew
manifest ship repo patch -y            # Apply full publish
```

### Minor Release (Direct Publish)

```bash
manifest ship repo minor      # Preview the full minor release
manifest ship repo minor -y   # Apply the release
```

The apply run syncs, bumps the version, generates docs, validates markdown,
commits, tags, pushes, updates Homebrew when applicable, and creates or reuses
the matching GitHub Release when enabled. Before those mutations, Manifest shows
the resolved Git root and asks `Apply to this repository? [y/N]`.

### Major Release with Interactive Prompts

```bash
manifest ship repo major -i      # Preview with interactive option selected
manifest ship repo major -i -y   # Apply with interactive safety prompts
```

Interactive mode adds confirmation prompts and offers a dry-run before executing.

### Revision Release

```bash
manifest ship repo revision            # Bumps 1.0.0 → 1.0.0.1
```

### Using Short Flags

```bash
manifest ship repo -p                  # Patch
manifest ship repo -m                  # Minor
manifest ship repo -M                  # Major
manifest ship repo -r                  # Revision
manifest ship repo -p -i              # Patch + interactive
```

### Inspect the Recipe Behind Ship

```bash
manifest ship repo patch --explain
manifest recipe list
manifest recipe explain manifest.builtin.ship.repo.patch
manifest recipe show manifest.builtin.ship.repo.patch
```

Recipes expose the ordered workflow steps and their effects (`read`,
`local-write`, `remote-write`, or `pr`) while the first-class command remains
the stable command to run. Do not run recipes directly; add or use a named
command when a workflow should execute.

---

## Documentation and Metadata

### Regenerate Docs Between Releases

```bash
manifest refresh repo                  # Regenerate docs, validate markdown, update metadata
manifest refresh repo --commit         # Same, but also commit the changes
```

### Quick Documentation (Plumbing)

```bash
manifest docs                          # Generate docs for current version
manifest docs metadata                 # Update repository metadata
manifest docs cleanup                  # Archive old docs to zArchive
```

---

## Pull Request Workflows

### Create and Merge a PR

```bash
manifest pr create --labels "feature,ready"  # Preview PR creation
manifest pr create --labels "feature,ready" -y
manifest pr checks --watch             # Watch CI in real-time
manifest pr ready                      # Preview marking draft PR ready
manifest pr ready -y
manifest pr queue --method squash      # Preview auto-merge queueing
manifest pr queue --method squash -y
```

### Review PR Status Across the Team

```bash
manifest pr status
manifest pr policy show
manifest pr policy validate
```

### Interactive PR Wizard

```bash
manifest pr                            # Guided interactive flow (TTY only)
```

---

## Fleet Workflows

### Adopt an Existing Multi-Repo Workspace

```bash
# Generate an adoption plan without writing files
manifest plan fleet

# Write manifest.fleet.plan.yaml for review
manifest plan fleet --apply --name "platform-services"

# Validate the reviewed plan without changing the workspace
manifest reconcile fleet

# Apply local changes after review
manifest reconcile fleet --do
```

### Convert a Submodule into a Fleet Repo

```bash
manifest plan fleet --apply

# Review generated entries with action: "adopt_submodule".
# Confirm parent_path, submodule_name, remote_url, and pinned_commit.

manifest reconcile fleet --apply --adopt-submodules
```

Submodule adoption removes the submodule from its parent repo and tracks the
standalone clone in `manifest.fleet.config.yaml`. The parent repo and submodule
working tree must be clean.

### Initialize a New Fleet (Two-Phase)

```bash
# Phase 1: Scan directories, create TSV for review
manifest init fleet --depth 3
manifest init fleet --all-folders
manifest init fleet --dry-run

# (Review manifest.fleet.tsv — adjust selected/excluded repos if needed)

# Phase 2: Read TSV, scaffold repos, create fleet config
manifest init fleet
manifest init fleet --dry-run
```

### Named Fleet with Custom Depth

```bash
manifest init fleet --name "platform-services" --depth 4
```

### Prepare Fleet Workspace

```bash
manifest prep fleet                    # Clone missing repos, pull existing ones
manifest prep fleet --parallel         # Parallel operations (faster)
manifest prep fleet --pull-only        # Skip clone, just pull
```

### Refresh Fleet

```bash
manifest refresh fleet                 # Re-scan membership, validate, regenerate docs
manifest refresh fleet --dry-run       # Preview what would change
```

### Coordinated Fleet Release

```bash
# Full release with safety checks
manifest ship fleet minor
manifest ship fleet minor -y

# Local preview across fleet (no push)
manifest ship fleet patch --local -y

# Fleet release with squash merge strategy
manifest pr fleet queue --method squash

# Fleet draft PRs
manifest pr fleet create --draft

# Ship a subset of the fleet
manifest ship fleet patch --only api,worker

# Ship the whole fleet except one or more services
manifest ship fleet patch --except docs,playground
```

### Direct Fleet Operations

```bash
manifest status fleet                  # Fleet repository status table
manifest discover fleet --depth 3      # Find new repos
manifest add fleet ./services/new-api --name "new-api" --type service --dry-run
manifest validate fleet                # Check configuration
manifest docs fleet --dry-run          # Preview docs generation
manifest pr fleet queue --method squash -y  # Fleet-wide PR queue
```

---

## Cloud and Agent

```bash
manifest cloud config                  # Configure API key and endpoint
manifest cloud status                  # Show connection status
manifest test cloud                    # Test connectivity

manifest agent init docker             # Initialize Docker-based agent
manifest agent auth github             # GitHub OAuth setup
manifest agent status                  # Agent status
```

---

## Configuration

### First-Time Setup

```bash
manifest config setup                  # Interactive wizard
manifest config show                   # Display effective configuration
manifest config time                   # Show time server settings
```

### Diagnose and Fix Config Issues

```bash
manifest config doctor --dry-run       # Preview what would be fixed
manifest config doctor --fix           # Auto-fix deprecated settings
```

---

## Security and Maintenance

```bash
manifest security --check              # Run read-only security checks
manifest upgrade --check               # Check for updates (no install)
manifest upgrade                       # Install latest version
manifest uninstall                     # Remove Manifest CLI
manifest reinstall                     # Full uninstall + reinstall
```

### Install Git Hooks

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

---

## Offline Workflows

```bash
# Force offline mode (no network calls)
MANIFEST_CLI_OFFLINE_MODE=true manifest ship repo patch --local

# Skip cloud integration
MANIFEST_CLI_CLOUD_SKIP=true manifest ship repo minor
```

---
