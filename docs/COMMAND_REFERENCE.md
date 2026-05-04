# Manifest CLI Command Reference

Complete reference for all commands, flags, and options.
Reflects the v42 command dispatcher in `modules/core/manifest-core.sh`.

---

## Command Model

Manifest v42 uses a `verb scope` pattern for core journey commands:

```bash
manifest <verb> <scope> [type] [options]
```

- **Verb**: what to do (`init`, `prep`, `refresh`, `ship`)
- **Scope**: where to do it (`repo` for single repository, `fleet` for polyrepo)
- **Type**: release type for `ship` (`patch`, `minor`, `major`, `revision`)

Supporting commands (`pr`, `config`, `test`, etc.) do not require a scope.

---

## Top-Level Commands

### Core Journey

| Command | Description |
| ------- | ----------- |
| `manifest config [sub]` | Configuration management |
| `manifest init repo\|fleet` | Scaffold a repository or fleet |
| `manifest prep repo\|fleet` | Connect remotes, pull latest |
| `manifest refresh repo\|fleet` | Regenerate docs, metadata, membership |
| `manifest ship repo\|fleet <type>` | Publish a release |

### Supporting

| Command | Description |
| ------- | ----------- |
| `manifest pr [sub]` | Pull request lifecycle |
| `manifest revert` | Revert to previous version |

### Maintenance

| Command | Description |
| ------- | ----------- |
| `manifest upgrade [flags]` | Check for and install updates |
| `manifest uninstall [--force]` | Remove Manifest CLI |
| `manifest reinstall` | Full uninstall + reinstall |
| `manifest security` | Security audit |
| `manifest test [suite]` | Run diagnostic tests |

### Cloud / Agent

| Command | Description |
| ------- | ----------- |
| `manifest cloud <sub>` | Manifest Cloud connector |
| `manifest agent <sub>` | Containerized agent management |

### Recovery

| Command | Description |
| ------- | ----------- |
| `manifest revert` | Roll back to a previous version |

### Hidden Plumbing And Removed Routes

| Command | Routes To |
| ------- | --------- |
| `manifest prep <type>` | `manifest ship repo <type> --local` (deprecation warning) |
| `manifest ship <type>` | `manifest ship repo <type>` |
| `manifest sync` | `manifest prep repo` |
| `manifest fleet <action>` | Removed; use `manifest <action> fleet` |
| `manifest time` | Time info display |
| `manifest update` | Removed as an upgrade alias; use `manifest upgrade` |
| `manifest docs [sub]` | Documentation generation (plumbing) |
| `manifest cleanup` | Archive old docs (plumbing) |
| `manifest commit <msg>` | Commit with timestamp (plumbing) |
| `manifest version <type>` | Bump version only (plumbing) |

---

## `manifest config`

Configuration management. Loads YAML config with layered precedence.

```bash
manifest config               # Interactive wizard (TTY) or show config (pipe)
manifest config show          # Display effective configuration
manifest config setup         # Force interactive wizard
manifest config time          # Show time server configuration
manifest config doctor        # Detect deprecated settings
manifest config doctor --fix  # Auto-fix deprecated settings
manifest config doctor --dry-run  # Preview fixes without applying
```

**Subcommands:**

| Subcommand | Description |
| ---------- | ----------- |
| *(none)* | Interactive wizard (TTY) or `show` (non-interactive) |
| `show` | Print full effective configuration |
| `setup` | Force interactive configuration wizard |
| `time` | Print time server configuration |
| `doctor` | Detect stale/deprecated config |
| `doctor --fix` | Auto-fix deprecated settings |
| `doctor --dry-run` | Preview fixes without applying |

**Source:** `manifest-core.sh` lines 393-433, delegates to `manifest-config.sh`.

---

## `manifest init`

Scaffold a repository or fleet. Local-only operation — creates files, never touches remotes.

**Source:** [manifest-init.sh](../modules/core/manifest-init.sh) `manifest_init_dispatch()`

### `manifest init repo`

Creates the standard file scaffolding for a Manifest-managed repository.

```bash
manifest init repo             # Scaffold VERSION, CHANGELOG.md, docs/, .gitignore
manifest init repo --force     # Re-create files even if they already exist
```

**What it creates:**

- `VERSION` (set to `1.0.0` if missing)
- `CHANGELOG.md`
- `README.md`
- `docs/` directory
- `.gitignore` entries
- `manifest.config.local.yaml` (git-ignored local config template)
- Initializes a Git repository if none exists

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `-f`, `--force` | Re-create files even if they already exist |

**Delegates to:** `ensure_required_files()` in `manifest-shared-functions.sh`

### `manifest init fleet`

Two-phase fleet initialization using TSV-based directory discovery.

```bash
manifest init fleet                        # Phase 1 (no TSV) or Phase 2 (TSV exists)
manifest init fleet --dry-run              # Preview current phase without writes
manifest init fleet --depth 3              # Custom scan depth (default: 2)
manifest init fleet --name "my-fleet"      # Named fleet
manifest init fleet --force                # Overwrite existing files
```

**Phase 1** (no `manifest.fleet.tsv` exists): Scans directories up to `--depth` levels, creates `manifest.fleet.tsv` for user review.

**Phase 2** (TSV exists): Reads selections from TSV, scaffolds each repo, creates fleet configuration.

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--depth N` | Scan depth (default: 2) |
| `-f`, `--force` | Overwrite existing files |
| `--dry-run` | Preview Phase 1 or Phase 2 without writing files |
| `-n`, `--name NAME` | Fleet name (prompted if not provided) |

**Delegates to:** `_fleet_start()` (phase 1) and `_fleet_init()` (phase 2) in `manifest-fleet.sh`

---

### `manifest plan fleet`

Generate a YAML fleet adoption plan. Dry-run is the default.

```bash
manifest plan fleet                  # Preview plan generation, writes nothing
manifest plan fleet --apply          # Write manifest.fleet.plan.yaml
manifest plan fleet --do             # Alias for --apply
manifest plan fleet --depth auto     # Adaptive scan guardrail
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--apply`, `--do` | Write the plan file |
| `--dry-run` | Explicit no-op; dry-run is already the default |
| `--depth N\|auto` | Scan depth guardrail |
| `--safety-cap N` | Auto-depth ceiling |
| `--plan FILE` | Plan file path |

### `manifest reconcile fleet`

Validate and apply a fleet adoption plan. Dry-run is the default.

```bash
manifest reconcile fleet                         # Validate and explain, writes nothing
manifest reconcile fleet --do                    # Apply local filesystem/config changes
manifest reconcile fleet --apply --commit        # Apply and commit local changes
manifest reconcile fleet --apply --commit --push # Apply, commit, and push
```

**Mutation ladder:**

| Flag | Description |
| ---- | ----------- |
| `--apply`, `--do` | Apply local filesystem/config changes |
| `--commit` | Commit local changes; requires `--apply` or `--do` |
| `--push` | Push commits; requires `--commit` |
| `--force` | Reserved for explicit overrides; requires `--apply` or `--do` |
| `--adopt-submodules` | Allow `adopt_submodule` actions |

### `manifest.fleet.plan.yaml`

`manifest plan fleet --apply` writes an editable adoption plan. `manifest reconcile fleet` reads that file, validates every active entry, and either explains the actions in dry-run mode or applies them with `--apply`/`--do`.

Top-level sections:

| Section | Purpose |
| ------- | ------- |
| `plan` | Schema version, generation timestamp, and fleet root |
| `fleet` | Fleet name to write into `manifest.fleet.config.yaml` |
| `discovery` | Scan depth and safety cap used to build the plan |
| `rules` | Generated path/depth hints for human review |
| `entries` | One action per discovered repo, directory, or submodule |

Entry fields:

| Field | Purpose |
| ----- | ------- |
| `name` | Service key written under `services:` |
| `kind` | `git_repo`, `plain_dir`, or `submodule` |
| `source_path` | Existing relative path under the fleet root |
| `target_path` | Desired relative path under the fleet root |
| `action` | `track`, `init`, `move`, `adopt_submodule`, or `skip` |
| `type` | Fleet service type, usually `service` |
| `remote_url` | Git remote URL when known or required |
| `branch` | Branch to track in fleet config |
| `parent_path` | Parent git repo for submodule adoption |
| `submodule_name` | `.gitmodules` section name for submodule adoption |
| `pinned_commit` | Submodule commit to check out after cloning |

Actions:

| Action | Behavior |
| ------ | -------- |
| `track` | Add an existing git repo to fleet config without moving it |
| `init` | Initialize a plain directory as a git repo and track it |
| `move` | Move a source path to `target_path`, then track it |
| `adopt_submodule` | Clone the submodule as a standalone repo, remove it from the parent, then track it |
| `skip` | Leave the entry untouched |

Safety rules:

- `manifest plan fleet` and `manifest reconcile fleet` are read-only unless `--apply` or `--do` is present.
- `--commit` requires `--apply`/`--do`; `--push` requires `--commit`.
- `--force` does not override target path collisions.
- `target_path` must be relative, non-empty, and not nested inside another active `target_path`.
- `adopt_submodule` entries require `--adopt-submodules` and a clean parent repo.

---

## `manifest prep`

Prepare workspace: connect remotes, pull latest. This is the v42 meaning of "prep" — it replaces the old `manifest sync`.

**Source:** [manifest-prep.sh](../modules/core/manifest-prep.sh) `manifest_prep_dispatch()`

### `manifest prep repo`

Ensures remotes are configured and pulls latest from all remotes.

```bash
manifest prep repo             # Add remote if missing, pull latest
```

If no remote is configured and the terminal is interactive (TTY), prompts for a remote URL. In non-interactive mode, skips silently.

**Delegates to:** `sync_repository()` in `manifest-git.sh`

### `manifest prep fleet`

Clones missing repositories and pulls existing ones across the fleet.

```bash
manifest prep fleet                # Clone missing, pull existing
manifest prep fleet --parallel     # Run operations in parallel
manifest prep fleet --clone-only   # Only clone missing repos
manifest prep fleet --pull-only    # Only pull existing repos
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `-p`, `--parallel` | Run operations in parallel |
| `--clone-only` | Only clone missing repos (skip pull) |
| `--pull-only` | Only pull existing repos (skip clone) |

**Delegates to:** `fleet_sync()` in `manifest-fleet.sh`

### Legacy: `manifest prep <type>`

The old `manifest prep patch` (local release preview) now routes to `manifest ship repo <type> --local` with a deprecation warning. This is handled by the dispatch function detecting `patch|minor|major|revision` as a scope argument.

---

## `manifest refresh`

Regenerate docs, metadata, and fleet membership without any version change. Use between releases to keep documentation current.

**Source:** [manifest-refresh.sh](../modules/core/manifest-refresh.sh) `manifest_refresh_dispatch()`

### `manifest refresh repo`

Regenerates documentation and metadata for a single repository.

```bash
manifest refresh repo              # Regenerate docs and metadata
manifest refresh repo --commit     # Also commit refreshed files
```

**Steps performed:**

1. Get trusted HTTPS timestamp
2. Regenerate documentation (release notes, changelogs)
3. Archive old documentation to `zArchive/`
4. Validate markdown
5. Update repository metadata

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--commit` | Commit refreshed files after regeneration |

**Delegates to:** `generate_documents()`, `main_cleanup()`, `validate_project()`, `update_repository_metadata()`

### `manifest refresh fleet`

Re-scans fleet membership, validates configuration, regenerates fleet documentation.

```bash
manifest refresh fleet             # Full fleet refresh
manifest refresh fleet --dry-run   # Preview changes without applying
manifest refresh fleet --commit    # Commit refreshed files across fleet
```

**Steps performed:**

1. Re-scan fleet membership (discovery + merge)
2. Validate fleet configuration
3. Regenerate fleet documentation

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--dry-run` | Preview changes without applying |
| `--commit` | Commit refreshed files across fleet |

**Delegates to:** `fleet_update()`, `fleet_validate()`, `fleet_docs_dispatch()`

---

## `manifest ship`

Publish a release. The highest-consequence command in the CLI.

**Source:** [manifest-ship.sh](../modules/core/manifest-ship.sh) `manifest_ship_dispatch()`

### `manifest ship repo`

Ship a single repo: version bump, documentation, commit, tag, push, Homebrew update.

```bash
manifest ship repo patch           # Full patch release
manifest ship repo minor           # Full minor release
manifest ship repo major -i        # Major release with interactive prompts
manifest ship repo revision        # Revision release (e.g., 1.0.0.1)
manifest ship repo patch --local   # Everything except tag/push/Homebrew
```

**Full mode** (default): sync, bump version, generate docs, archive old docs, validate markdown, commit, tag, push to all remotes, update Homebrew formula (canonical repo only).

**Local mode** (`--local`): Everything except creating a tag, pushing to remotes, and updating Homebrew. Equivalent to the old `manifest prep <type>`.

Before any `commit_changes()` call stages files, Manifest runs a smart documentation review. The default provider is local and deterministic: it inspects the dirty tree, classifies changed files, reports whether documentation-impacting changes have matching docs updates, adds a concise review body to the commit, writes a neutral committed report under `docs/documentation-reviews/`, and feeds the review summary into generated release notes/changelogs.

Documentation review environment hooks:

| Variable | Description |
| -------- | ----------- |
| `MANIFEST_CLI_DOC_REVIEW=false` | Disable the review |
| `MANIFEST_CLI_DOC_REVIEW_OUTPUTS=commit_body,report,release_notes` | Enabled outputs; use `all` or omit an item to disable it |
| `MANIFEST_CLI_DOC_REVIEW_REPORT_DIR=docs/documentation-reviews` | Committed report directory |
| `MANIFEST_CLI_DOC_REVIEW_PROVIDER=local` | Default local reviewer |
| `MANIFEST_CLI_DOC_REVIEW_PROVIDER=command` | Run an external reviewer command after the local report is written |
| `MANIFEST_CLI_DOC_REVIEW_COMMAND=/path/to/reviewer` | Executable called as `reviewer REPORT_FILE PROJECT_ROOT` |
| `MANIFEST_CLI_DOC_REVIEW_REQUIRED=true` | Fail the commit if the external provider fails |

The same settings are available in `manifest.config.yaml` under `docs.review.*`.
For `provider=command`, Manifest exports sidecar paths before invoking the command:
`MANIFEST_DOC_REVIEW_COMMIT_SUBJECT_FILE`, `MANIFEST_DOC_REVIEW_COMMIT_BODY_FILE`,
and `MANIFEST_DOC_REVIEW_RELEASE_NOTE_FILE`. A provider can write those files to
override the commit subject, replace the commit body attachment, or replace the
release-note/changelog attachment.

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--local` | Local-only mode (no tag, push, or Homebrew) |
| `-i`, `--interactive` | Enable interactive safety prompts |
| `-p` | Patch (short flag) |
| `-m` | Minor (short flag) |
| `-M` | Major (short flag) |
| `-r` | Revision (short flag) |

**Delegates to:** `manifest_ship_workflow()` in `manifest-orchestrator.sh`

**Orchestrator pipeline (in order):**

1. `ensure_required_files()` — scaffold if missing
2. Interactive safety check (if `-i`)
3. `get_time_timestamp()` — trusted HTTPS timestamp
4. Auto-commit uncommitted changes, after smart documentation review
5. `sync_repository()` — pull from remotes
6. `bump_version()` — increment VERSION file
7. `generate_documents()` — release notes, changelog
8. `main_cleanup()` — archive previous version docs
9. `validate_project()` — markdown validation
10. `commit_changes()` — commit version bump
11. Update `CHANGELOG.md` at repo root
12. `validate_repository()` — post-commit check
13. *(if not --local)* `create_tag()` — Git tag
14. *(if not --local)* `push_changes()` — push to remotes
15. *(if not --local)* `update_homebrew_formula()` — Homebrew (canonical repo only)
16. *(if not --local)* Local installed Manifest CLI upgrade
17. *(if not --local and gh is available)* GitHub Actions status watch for the published HEAD
18. `update_repository_metadata()` — final metadata update

**Failure handling:** If any step after commit fails, the orchestrator emits a Ship Failure Report with recovery commands (retry push, remove tag, roll back).

**GitHub Actions status:** The Actions watch is informational because release artifacts are already pushed by the time CI runs. Disable it with `MANIFEST_CLI_GITHUB_ACTIONS_WAIT=false`, or tune it with `MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS` and `MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS`.

**Tag target** (step 13): the SHA the tag points at is resolved by `resolve_tag_target_sha()` in [manifest-git.sh](../modules/git/manifest-git.sh) from `MANIFEST_CLI_RELEASE_TAG_TARGET` (YAML key `release.tag_target`):

| Value | Tagged commit |
| ----- | ------------- |
| `version_commit` (default since v44.10.1) | Captured SHA of the "Bump version to X" commit |
| `release_head` | HEAD at tag-creation time (post-CHANGELOG, pre-Homebrew) |
| `final_release_commit` | Deprecated alias for `release_head`; emits a warning |

Value matching is whitespace- and case-tolerant. Unknown values fall back to `version_commit` and emit a warning to stderr. The Homebrew formula commit is intentionally outside the tag in all cases (see [USER_GUIDE.md#tag-placement-releasetag_target](USER_GUIDE.md#tag-placement-releasetag_target) for the chicken-and-egg explanation).

### `manifest ship fleet`

Coordinated fleet release across all repositories.

```bash
manifest ship fleet minor                       # Coordinated minor release
manifest ship fleet patch --safe                # With checks and readiness gates
manifest ship fleet minor --local               # Local-only across fleet
manifest ship fleet patch --method squash       # Squash merge strategy
manifest ship fleet minor --draft               # Create draft PRs
manifest ship fleet patch --noprep              # Skip per-service prep step
manifest ship fleet patch --only api,worker     # Ship only the named services
manifest ship fleet patch --except docs         # Ship every service except 'docs'
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--local` | Local-only mode across fleet |
| `--safe` | Run checks/ready gate before queueing |
| `--noprep` | Skip per-service prep step |
| `--method <strategy>` | Merge strategy: `merge`, `squash`, `rebase` |
| `--draft` | Create draft PRs |
| `--only <name[,name...]>` | Ship only the named service(s); repeatable |
| `--except <name[,name...]>` | Ship every service except those named; repeatable |

`--only` and `--except` are mutually exclusive. The filter applies to per-service prep, fleet doc generation, and the PR dispatch (the Cloud-side dispatcher receives the same flags).

**Delegates to:** `fleet_ship()` (full mode) or `fleet_prep()` (local mode) in `manifest-fleet.sh`

### Legacy: `manifest ship <type>`

The old `manifest ship patch` (no scope) routes to `manifest ship repo patch` automatically.

---

## `manifest pr`

Pull request lifecycle management.

```bash
manifest pr                    # Interactive PR wizard (TTY mode)
manifest pr create             # Create a pull request
manifest pr create --draft --labels "feature" --reviewers "user1"
manifest pr update             # Update PR metadata
manifest pr update --labels "ready" --reviewers "user2"
manifest pr status             # Show PR status
manifest pr status --pr 42     # Status for a specific PR
manifest pr checks             # Show CI check results
manifest pr checks --watch     # Watch checks in real-time
manifest pr ready              # Evaluate merge readiness
manifest pr queue              # Queue auto-merge
manifest pr queue --method squash --force
manifest pr policy show        # Display PR policy profile
manifest pr policy validate    # Validate against policy
manifest pr help               # PR help
```

**Subcommands:**

| Subcommand | Description |
| ---------- | ----------- |
| *(none)* | Interactive PR wizard |
| `create` | Create a pull request |
| `update` | Update PR metadata |
| `status` | Show PR status |
| `checks` | Show CI check results |
| `ready` | Evaluate merge readiness |
| `queue` | Queue auto-merge |
| `policy show` | Display PR policy profile |
| `policy validate` | Validate against policy |
| `help` | PR help text |

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

**Source:** `manifest-pr.sh`

---

## `manifest test`

Run diagnostic test suites.

```bash
manifest test                  # Basic repository status test
manifest test all              # All test suites
manifest test versions         # Version increment logic
manifest test security         # Security checks
manifest test config           # Configuration loading
manifest test docs             # Documentation generation
manifest test git              # Git operations
manifest test time             # Timestamp verification
manifest test os               # OS detection
manifest test modules          # Module loading
manifest test integration      # End-to-end tests
manifest test cloud            # Cloud connectivity
manifest test agent            # Agent functionality
manifest test zsh              # Zsh compatibility
manifest test bash5            # Bash 5 compatibility
manifest test bash             # Basic Bash tests
```

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--strict-redact` | Sanitize logs for sharing |
| `--no-strict-redact` | Keep raw output |

**Source:** `manifest-test.sh`

---

## `manifest security`

Run security audit: scans for exposed secrets, validates `.gitignore`, checks for large binary files.

```bash
manifest security
```

**Source:** `manifest-security.sh`

---

## `manifest upgrade`

Check for and install CLI updates.

```bash
manifest upgrade               # Check and install updates
manifest upgrade --check       # Check only (no install)
manifest upgrade --force       # Force upgrade regardless of version
```

Use `manifest upgrade` explicitly for CLI upgrades.

**Source:** `manifest-auto-upgrade.sh`

---

## `manifest cloud`

Manifest Cloud MCP connector.

```bash
manifest cloud config          # Configure API key and endpoint
manifest cloud status          # Show connection status
manifest cloud generate <version> [timestamp] [release_type]
```

Requires `MANIFEST_CLI_CLOUD_API_KEY`.

---

## `manifest agent`

Containerized cloud agent management.

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

## Fleet Commands

Fleet commands use the same action-first shape as the rest of the CLI:
`manifest <action> fleet ...`. The old object-first `manifest fleet <action>`
routes are not dispatcher routes.

```bash
manifest init fleet                    # Scaffold fleet
manifest init fleet --dry-run          # Preview current init phase
manifest quickstart fleet --dry-run    # Auto-discover preview, skip TSV selection
manifest status --verbose              # Fleet status when in fleet mode
manifest discover fleet --depth 3      # Find new repos (alias for update --dry-run)
manifest update fleet                  # Re-scan membership
manifest update fleet --dry-run        # Preview changes
manifest add fleet ./path --name "svc" --dry-run # Preview service YAML
manifest validate fleet                # Validate config
manifest prep fleet --parallel         # Clone/pull all
manifest refresh fleet                 # Re-scan + regenerate docs
manifest docs fleet --dry-run          # Preview fleet documentation writes
manifest pr fleet queue --method squash  # Fleet PR operations
manifest ship fleet minor --safe       # Coordinated release
```

**Service types for `add fleet`:** `service`, `library`, `infrastructure`, `tool`

> See [Fleet Design Spec](FLEET_DESIGN_SPEC.md) for architecture details.

---

## Plumbing Commands (Hidden)

Low-level operations used internally by the ship pipeline. Available for scripting but not shown in help.

```bash
manifest commit "message"      # Commit with trusted timestamp
manifest version patch         # Bump version without full pipeline
manifest docs                  # Generate docs for current version
manifest docs metadata         # Update repository metadata
manifest docs cleanup          # Archive old docs to zArchive
manifest cleanup               # Archive old documentation
manifest time                  # Display trusted timestamp info
```

---

## Global Behavior

### Pre-Dispatch Validation

Before any command runs, the dispatcher:

1. **Commands not requiring Git** (`help`, `uninstall`, `reinstall`, `upgrade`, `config`): skip Git validation.
2. **`init`**: loads config without requiring a Git repository (may create one).
3. **All other commands**: validate Git repository root, load configuration, check for auto-upgrade.

### Error Handling

- Unknown commands print an error message followed by help text.
- Missing required arguments (e.g., `manifest ship repo` without a type) print usage and return exit code 1.
- The ship pipeline emits a failure report with recovery commands if any step fails after the commit phase.

### Environment Variables

All configuration settings map to `MANIFEST_CLI_*` environment variables. See `manifest config show` for the full list, or review the `_MANIFEST_YAML_TO_ENV` mapping in [manifest-yaml.sh](../modules/core/manifest-yaml.sh).
