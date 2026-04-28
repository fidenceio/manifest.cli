# Manifest CLI Examples

Real-world workflow recipes for common operations using the v42 command structure.

---

## New Project Setup

### From Scratch

```bash
mkdir my-project && cd my-project
manifest init repo                     # Creates VERSION, CHANGELOG.md, docs/, .gitignore, git init
manifest config setup                  # Interactive configuration wizard
manifest prep repo                     # Prompts for remote URL, pulls latest
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
manifest test all
manifest ship repo patch --local       # Preview: bump, docs, commit — no push
# Review the changes...
manifest ship repo patch               # Full publish: tag, push, Homebrew
```

### Minor Release (Direct Publish)

```bash
manifest ship repo minor
```

This runs the full workflow: sync, version bump, docs generation, markdown validation, commit, tag, push, Homebrew update.

### Major Release with Interactive Prompts

```bash
manifest ship repo major -i
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
manifest pr create --labels "feature,ready"
manifest pr checks --watch             # Watch CI in real-time
manifest pr ready                      # Evaluate merge readiness
manifest pr queue --method squash      # Queue auto-merge
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

### Initialize a New Fleet (Two-Phase)

```bash
# Phase 1: Scan directories, create TSV for review
manifest init fleet --depth 3

# (Review and edit manifest.fleet.tsv — mark repos as selected/excluded)

# Phase 2: Read TSV, scaffold repos, create fleet config
manifest init fleet
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
manifest ship fleet minor --safe

# Local preview across fleet (no push)
manifest ship fleet patch --local

# Fleet release with squash merge strategy
manifest ship fleet minor --method squash

# Fleet draft PRs
manifest ship fleet patch --draft

# Ship a subset of the fleet
manifest ship fleet patch --only api,worker

# Ship the whole fleet except one or more services
manifest ship fleet patch --except docs,playground
```

### Direct Fleet Operations (Legacy Interface)

```bash
manifest fleet status --verbose        # Fleet status
manifest fleet discover --depth 3      # Find new repos
manifest fleet add ./services/new-api --name "new-api" --type service
manifest fleet validate                # Check configuration
manifest fleet pr queue --method squash  # Fleet-wide PR merge
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
manifest security                      # Run security audit
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

## Migrating from Pre-v42 Commands

If you have scripts using old commands, here are the equivalents:

```bash
# Old                              # New (v42)
manifest prep patch                 manifest ship repo patch --local
manifest ship patch                 manifest ship repo patch
manifest sync                       manifest prep repo
manifest docs                       manifest refresh repo
manifest cleanup                    manifest refresh repo
manifest fleet start                manifest init fleet
manifest fleet init                 manifest init fleet
manifest fleet sync                 manifest prep fleet
manifest fleet ship minor           manifest ship fleet minor
manifest update                     manifest upgrade
```

Most old commands still work as hidden aliases. The three legacy fleet routes
(`manifest fleet start|init|sync`) were removed in v44.9.0 — invoking them now
emits a one-line migration hint pointing at the v42 entry point.
