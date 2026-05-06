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

Fleet adoption has two extra commands before the normal fleet journey:
`manifest plan fleet` generates an editable plan, and `manifest reconcile fleet`
validates or applies it. Both are dry-run by default.

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

#### Tag Placement (`release.tag_target`)

The release tag can point at either of two commits:

| Value | Tag points at | When to use |
| ----- | ------------- | ----------- |
| `version_commit` (default) | The "Bump version to X" commit | Most projects — keeps the tag anchored to the canonical release artifact even when a CHANGELOG commit lands after the bump |
| `release_head` | Whatever HEAD is when the tag is created (post-bump, post-CHANGELOG, pre-Homebrew) | Projects that want the CHANGELOG entry inside the tag |

The Homebrew formula commit is intentionally outside the tag in both cases:
`update_homebrew_formula` curls the GitHub tarball at the tag URL to compute
SHA256, which would require the formula to contain its own SHA256
(chicken-and-egg). So `release_head` means "last commit *before* Homebrew",
not literally the final commit of the release.

Configure in `manifest.config.yaml`:

```yaml
release:
  tag_target: "version_commit"   # or "release_head"
```

The value is whitespace- and case-tolerant (`Version_Commit`, `" release_head "` all work). The deprecated alias `final_release_commit` continues to work but emits a warning — switch to `release_head`.

> **Behavior change in v44.10.1.** Before v44.10.1, the release tag always pointed at HEAD at tag-creation time (effectively `release_head`). v44.10.1 introduced this option and changed the default to `version_commit`. If your automation reads `git for-each-ref` or `git rev-list <tag>..main` and expects post-CHANGELOG content inside the tag, set `release.tag_target: "release_head"` to restore the old behavior.

### Regenerate Documentation

```bash
manifest refresh repo              # Regenerate docs and metadata
manifest refresh repo --commit     # Also commit the refreshed files
```

Use `refresh` between releases to keep docs current without bumping the version.

### Release-Notes Provider Hook

By default, every `manifest ship` produces a release-notes bullet list from
the cleaned commit subjects since the last tag. The local generator is
boilerplate-free: a single `### Changes` section, narrative bullets, no
counts table. Empty ranges produce a one-liner `**Release Type:** Patch — no
user-facing changes.` and no body.

If you want richer prose, you can plug in any LLM:

```yaml
# manifest.config.yaml
docs:
  release_notes:
    provider: command
    command: /absolute/path/to/your-provider.sh
    required: false   # true → ship aborts on provider failure
```

The provider is called as `your-provider.sh REQUEST_FILE OUTPUT_FILE`:

- `REQUEST_FILE` is markdown Manifest writes for you. It contains the prompt,
  the version metadata, the cleaned commit subjects, and the changed-file
  list. **Manifest owns the prompt and the output schema** — your provider
  is a thin transport that hands the request to an LLM and writes the
  response back.
- `OUTPUT_FILE` is where you write the LLM's response. Manifest validates
  the response before splicing it into `CHANGELOG.md`:
  - Bullets only (lines starting with a `-` followed by a space); preamble
    before the first bullet and prose after the last bullet are stripped.
  - Banned LLM-preamble phrases ("As an AI…", "Sure, here…", etc.) cause
    the output to be rejected.
  - Hard cap at 15 bullets; excess is truncated.
- Any LLM works (Claude, GPT, a local model). See
  [examples/release-notes-providers/example-provider.sh](../examples/release-notes-providers/example-provider.sh)
  for the contract and a stub you can copy.

If the provider exits non-zero or its output fails validation, Manifest logs
a warning and falls back to the local generator. Set `required: true` to
abort the ship instead.

### Other Common Operations

```bash
manifest revert               # Revert to previous version
manifest security --check     # Run read-only security checks
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

### Adopt an Existing Fleet

Use `plan` and `reconcile` when a workspace already contains multiple repos,
plain directories, or submodules and you want an explicit adoption file before
anything changes.

```bash
manifest plan fleet                    # Preview plan generation, writes nothing
manifest plan fleet --apply            # Write manifest.fleet.plan.yaml
manifest plan fleet --name "my-platform" --apply

# Review and edit manifest.fleet.plan.yaml.

manifest reconcile fleet               # Validate and explain, writes nothing
manifest reconcile fleet --do          # Apply local filesystem/config changes
manifest reconcile fleet --apply --commit
```

`--apply` and `--do` are aliases. `--commit` requires `--apply`/`--do`, and
`--push` requires `--commit`. `--force` does not bypass target path collisions.

The plan file supports these actions:

| Action | Behavior |
| ------ | -------- |
| `track` | Add an existing git repo to fleet config |
| `init` | Initialize a plain directory as a git repo and track it |
| `move` | Move a directory/repo to `target_path`, then track it |
| `adopt_submodule` | Convert a submodule into a standalone tracked repo |
| `skip` | Leave the entry untouched |

Submodule adoption is intentionally gated:

```bash
manifest reconcile fleet --apply --adopt-submodules
```

Only use it after reviewing the generated `parent_path`, `submodule_name`,
`remote_url`, and `pinned_commit` fields.

### Initialize a New Fleet

```bash
# Phase 1: Scan directories, choose repo depth per folder, create manifest.fleet.tsv
manifest init fleet
manifest init fleet --dry-run

# Phase 2: Re-run after reviewing TSV — scaffolds repos, creates fleet config
manifest init fleet
manifest init fleet --dry-run

# Custom scan depth (default: 2 levels)
manifest init fleet --depth 3

# Exhaustive review mode: list every scanned folder in the TSV
manifest init fleet --all-folders

# Named fleet
manifest init fleet --name "my-platform"
```

The two-phase approach lets you choose repo granularity before committing to a fleet configuration. In an interactive shell, Phase 1 asks how deep repos should be under each top-level folder: `0` means the folder itself, `1` means direct children such as `apps/*`, and `2` means grandchildren such as `apps/*/*`. During initialization, Manifest ensures every selected repo has a `.gitignore`. Existing `.gitignore` files with entries are preserved; a `.gitignore.manifest` reference file is created instead.

For messy existing workspaces, prefer `manifest plan fleet` and
`manifest reconcile fleet`; they keep the adoption decisions in an editable
YAML plan with a dry-run default.

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
manifest ship fleet minor                       # Coordinated minor release
manifest ship fleet patch --safe                # With checks and readiness gates
manifest ship fleet minor --local               # Local-only across fleet
manifest ship fleet patch --method squash       # Squash merge strategy
manifest ship fleet minor --draft               # Create draft PRs
manifest ship fleet patch --only api,worker     # Ship only the named services
manifest ship fleet patch --except docs         # Ship every service except 'docs'
```

### Direct Fleet Commands

Fleet commands use action-first syntax:

```bash
manifest status fleet              # Fleet repository status table
manifest discover fleet --depth 3  # Find new repos
manifest add fleet ./new-service --dry-run   # Preview service YAML
manifest validate fleet            # Check configuration
manifest pr fleet queue            # Auto-merge PRs across fleet
manifest docs fleet --dry-run      # Preview docs generation
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
manifest security --check   # Run read-only security checks
manifest upgrade --check    # Check for updates (no install)
manifest upgrade            # Install latest version
manifest upgrade --force    # Force upgrade regardless of version
manifest uninstall          # Remove Manifest CLI
manifest uninstall --force  # Remove without confirmation
manifest reinstall          # Full uninstall + reinstall cycle
```

### Git Hooks

Manifest CLI ships a `pre-commit` hook in `.git-hooks/pre-commit` that blocks common secret-leak paths before they reach your Git history.

#### What the Hook Checks

| Check | Description |
| ----- | ----------- |
| Private env/config files | Blocks `.env*` and similar files from being committed |
| Secret patterns | Scans staged content for tokens, API keys, and credentials |
| `.gitignore` safety | Verifies `.gitignore` is properly configured |
| Large files | Warns before accidentally committing binaries or archives |
| Manifest security | Integrates with `manifest security --check` when available |

#### Install

```bash
cp .git-hooks/pre-commit .git/hooks/pre-commit
chmod +x .git/hooks/pre-commit
```

#### Blocked Commit Recovery

If the hook blocks your commit:

```bash
# Unstage the problematic file
git reset HEAD <file>

# Remove secrets or move to an ignored local config file
# Then re-stage safe files only
git add <safe-files>
git commit -m "safe commit"
```

#### Bypass (Emergency Only)

```bash
git commit --no-verify -m "emergency change"
```

Use bypass sparingly. Always follow up with a manual `manifest security --check` run to verify no secrets were committed.

#### Team Workflow

- Keep `.git-hooks/pre-commit` version-controlled in your repository.
- Reinstall the hook after pulling changes to the hook file.
- Pair local hooks with CI security checks for defense in depth.
- Use `manifest security --check` as a periodic read-only audit on top of the pre-commit hook.

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
| `manifest fleet <action>` | `manifest <action> fleet` | Removed object-first fleet routes |
| `manifest update` | `manifest upgrade` | Use explicit upgrade command |
| `manifest docs` | `manifest refresh repo` | Still works as plumbing |
| `manifest cleanup` | `manifest refresh repo` | Still works as plumbing |
| `manifest time` | `manifest config time` | Still works |
| `manifest commit "msg"` | *(plumbing)* | Still works |
| `manifest version patch` | *(plumbing)* | Still works |

If you have scripts using the old commands, they will continue to function. Update them at your convenience.
