# Manifest CLI Command Reference

Complete reference for all commands, flags, and options.
Reflects the command dispatcher in `modules/core/manifest-core.sh`.

---

## Top-Level Commands

| Command | Description |
| ------- | ----------- |
| `manifest prep <type> [-i]` | Local release preparation (sync, bump, docs, commit) |
| `manifest ship <type> [-i]` | Full publish (prep + tag + push + Homebrew) |
| `manifest sync` | Pull latest changes from remote |
| `manifest revert` | Revert to previous version |
| `manifest commit <message>` | Commit with custom message |
| `manifest version [type]` | Bump version only |
| `manifest docs [sub]` | Documentation generation |
| `manifest cleanup` | Archive old documentation |
| `manifest config [sub]` | Configuration management |
| `manifest security` | Security audit |
| `manifest test [suite]` | Run test suites |
| `manifest time` | Get trusted HTTPS timestamp |
| `manifest pr <sub>` | Pull request operations |
| `manifest fleet <sub>` | Polyrepo fleet operations |
| `manifest cloud <sub>` | Manifest Cloud connector |
| `manifest agent <sub>` | Containerized agent management |
| `manifest upgrade [flags]` | Check for and install updates |
| `manifest uninstall [--force]` | Remove Manifest CLI |
| `manifest reinstall` | Full uninstall + reinstall |
| `manifest help` | Show help |

---

## `manifest prep`

Local-only release preparation. Runs sync, version bump, documentation generation,
markdown validation, and commit. Does not tag, push, or update Homebrew.

```bash
manifest prep patch          # Patch release
manifest prep minor          # Minor release
manifest prep major          # Major release
manifest prep revision       # Revision (e.g., 1.0.0.1)
manifest prep minor -i       # Interactive mode with prompts
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `-p` | Patch (short) |
| `-m` | Minor (short) |
| `-M` | Major (short) |
| `-r` | Revision (short) |
| `-i`, `--interactive` | Enable interactive confirmation prompts |

---

## `manifest ship`

Full publish flow. Runs prep in publish mode, then creates a Git tag, pushes to
all remotes, and updates the Homebrew formula.

```bash
manifest ship patch
manifest ship major -i
```

Accepts the same flags as `prep`.

---

## `manifest docs`

```bash
manifest docs              # Generate docs for current version
manifest docs metadata     # Update repository metadata (description, topics)
manifest docs homebrew     # Note: updated automatically during prep/ship
manifest docs cleanup      # Archive old docs to zArchive
```

---

## `manifest config`

```bash
manifest config            # Interactive wizard (TTY mode)
manifest config show       # Display current configuration
manifest config setup      # Force interactive wizard
manifest config time       # Show time server configuration
manifest config doctor     # Detect deprecated settings
manifest config doctor --fix      # Auto-fix deprecated settings
manifest config doctor --dry-run  # Preview fixes without applying
manifest config --non-interactive # Non-interactive mode
```

---

## `manifest test`

```bash
manifest test all          # All test suites
manifest test versions     # Version increment logic
manifest test security     # Security checks
manifest test config       # Configuration loading
manifest test docs         # Documentation generation
manifest test git          # Git operations
manifest test time         # Timestamp verification
manifest test os           # OS detection
manifest test modules      # Module loading
manifest test integration  # End-to-end tests
manifest test cloud        # Cloud connectivity
manifest test agent        # Agent functionality
manifest test zsh          # Zsh compatibility
manifest test bash5        # Bash 5 compatibility
manifest test bash         # Basic Bash tests
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--strict-redact` | Sanitize logs for sharing |
| `--no-strict-redact` | Keep raw output |

---

## `manifest pr`

Pull request lifecycle management.

```bash
manifest pr                # Interactive PR wizard (TTY)
manifest pr create         # Create a pull request
manifest pr create --draft --labels "feature" --reviewers "user1"
manifest pr update         # Update PR metadata
manifest pr update --labels "ready" --reviewers "user2"
manifest pr status         # Show PR status
manifest pr status --pr 42 # Status for a specific PR
manifest pr checks         # Show CI check results
manifest pr checks --watch # Watch checks in real-time
manifest pr ready          # Evaluate merge readiness
manifest pr queue          # Queue auto-merge
manifest pr queue --method squash --force
manifest pr policy show    # Display PR policy profile
manifest pr policy validate  # Validate against policy
manifest pr help           # PR help
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--pr <selector>` | Target a specific PR (number or branch) |
| `--labels <list>` | Comma-separated label list |
| `--reviewers <list>` | Comma-separated reviewer list |
| `--draft` | Create as draft PR |
| `--method <strategy>` | Merge strategy: `merge`, `squash`, `rebase` |
| `--force` | Force the operation |
| `--watch` | Watch checks in real-time |

---

## `manifest fleet`

Polyrepo fleet coordination.

### `fleet init`

Initialize a new fleet with auto-discovery of Git repositories.

```bash
manifest fleet init                    # Auto-discover repos (default)
manifest fleet init --name "platform"  # Custom fleet name
manifest fleet init --bare             # Skip discovery, template only
manifest fleet init --force            # Overwrite existing config
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--name <name>` | Fleet name |
| `--bare` | Skip auto-discovery, create minimal template |
| `--force` | Overwrite existing `manifest.fleet.yaml` |

During initialization, each discovered repo gets a `.gitignore` check.

### `fleet status`

```bash
manifest fleet status            # Table view of all services
manifest fleet status --verbose  # Detailed per-service info
manifest fleet status --json     # JSON output
```

### `fleet discover`

```bash
manifest fleet discover          # Find new repos in workspace
manifest fleet discover --depth 3  # Limit search depth
manifest fleet discover --json   # JSON output
manifest fleet discover --quiet  # Minimal output
```

### `fleet sync`

```bash
manifest fleet sync              # Clone/pull all services
manifest fleet sync --parallel   # Parallel operations
manifest fleet sync --clone-only # Clone only (skip pull)
manifest fleet sync --pull-only  # Pull only (skip clone)
```

### `fleet ship`

```bash
manifest fleet ship minor                # Coordinated release
manifest fleet ship patch --safe         # With checks/ready gates
manifest fleet ship minor --method squash --draft
manifest fleet ship patch --noprep       # Skip prep step
manifest fleet ship minor --no-delete-branch
```

### `fleet pr`

```bash
manifest fleet pr                # Default: queue auto-merge
manifest fleet pr create         # Create PRs across fleet
manifest fleet pr status         # Status of all fleet PRs
manifest fleet pr checks         # CI checks across fleet
manifest fleet pr ready          # Merge readiness across fleet
manifest fleet pr queue          # Queue auto-merge for all
manifest fleet pr queue --method rebase
```

### Other Fleet Commands

```bash
manifest fleet validate          # Validate fleet configuration
manifest fleet add ./path        # Add a service
manifest fleet add ./svc --name "my-service" --type library
manifest fleet docs              # (Scaffolded, not yet implemented)
manifest fleet help              # Fleet help
```

**Service types:** `service`, `library`, `infrastructure`, `tool`

---

## `manifest cloud`

```bash
manifest cloud config    # Configure API key and endpoint
manifest cloud status    # Show connection status
manifest cloud generate <version> [timestamp] [release_type]
```

Requires `MANIFEST_CLI_CLOUD_API_KEY`. Optional: `MANIFEST_CLI_CLOUD_ENDPOINT`.

---

## `manifest agent`

```bash
manifest agent init docker     # Initialize Docker agent
manifest agent init binary     # Initialize binary agent
manifest agent init script     # Initialize script agent
manifest agent auth github     # GitHub OAuth setup
manifest agent auth manifest   # Manifest Cloud subscription
manifest agent status          # Agent status
manifest agent logs            # Agent logs
manifest agent uninstall       # Remove agent
```

---

## `manifest upgrade`

```bash
manifest upgrade          # Check and install updates
manifest upgrade --check  # Check only (no install)
manifest upgrade --force  # Force upgrade regardless of version
```

`manifest update` is a deprecated alias for `upgrade`.

---

## Not Currently Dispatched

These commands are not available as top-level commands:

- `manifest diagnose`
- `manifest analyze`
- `manifest changelog`
- `manifest --version`
