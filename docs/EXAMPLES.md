# Manifest CLI Examples

Real-world workflow recipes for common operations.

---

## Release Workflows

### Patch Release (Local Prep)

```bash
git add .
git commit -m "fix: address edge case in parser"
manifest test all
manifest prep patch
```

### Publish a Minor Release

```bash
manifest ship minor
```

This runs the full workflow: sync, version bump, docs generation, commit, tag, push, Homebrew update.

### Major Release with Interactive Prompts

```bash
manifest ship major -i
```

Interactive mode adds confirmation prompts before destructive steps.

---

## Documentation

### Regenerate Docs for Current Version

```bash
manifest docs
manifest docs metadata
```

### Archive Old Documentation

```bash
manifest cleanup
```

---

## Pull Request Workflows

### Create and Merge a PR

```bash
manifest pr create --labels "feature,ready"
manifest pr checks --watch
manifest pr ready
manifest pr queue --method squash
```

### Review PR Status Across the Team

```bash
manifest pr status
manifest pr policy show
manifest pr policy validate
```

---

## Fleet Workflows

### Initialize a New Fleet

```bash
# Auto-discover all repos in your workspace
manifest fleet init

# Name the fleet and discover
manifest fleet init --name "platform-services"

# Bare template (no discovery)
manifest fleet init --bare
```

### Day-to-Day Fleet Operations

```bash
manifest fleet status --verbose
manifest fleet sync --parallel
manifest fleet discover --depth 3
```

### Coordinated Fleet Release

```bash
# Safe release with checks and readiness gates
manifest fleet ship minor --safe

# Fleet-wide PR queue with squash merge
manifest fleet pr queue --method squash
```

### Add a New Service to the Fleet

```bash
manifest fleet add ./services/new-api --name "new-api" --type service
manifest fleet validate
```

---

## Cloud and Agent

```bash
manifest cloud config
manifest cloud status
manifest test cloud

manifest agent init docker
manifest agent auth github
manifest agent status
```

---

## Configuration

### First-Time Setup

```bash
manifest config setup
manifest config show
manifest config time
```

### Diagnose and Fix Config Issues

```bash
manifest config doctor --dry-run
manifest config doctor --fix
```

---

## Security and Maintenance

```bash
manifest security
manifest upgrade --check
manifest cleanup
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
MANIFEST_CLI_OFFLINE_MODE=true manifest prep patch

# Skip cloud integration
MANIFEST_CLI_CLOUD_SKIP=true manifest ship minor
```
