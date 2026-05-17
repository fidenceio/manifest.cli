# Manifest CLI Command Reference

Complete reference for all commands, flags, and options.
Reflects the current command dispatcher in `modules/core/manifest-core.sh`.

---

## Command Model

Manifest uses a `verb scope` pattern for core journey commands:

```bash
manifest <verb> <scope> [type] [options]
```

- **Verb**: what to do (`init`, `prep`, `refresh`, `ship`)
- **Scope**: where to do it (`repo` for single repository, `fleet` for polyrepo)
- **Type**: release type for `ship` (`patch`, `minor`, `major`, `revision`)

Supporting commands (`pr`, `config`, `test`, etc.) do not require a scope.

## Execution Policy

Manifest is safe by default for every command that can write files, commit,
tag, push, create PRs, merge, queue, or mutate remote state.

| Form | Behavior |
| ---- | -------- |
| `command` | Preview only |
| `command --dry-run` | Explicit preview |
| `command -y` / `command --yes` | Apply |
| `command --local` | Preview local-only effects |
| `command --local -y` | Apply local-only effects |

`--dry-run` and `-y` are contradictory and return an error when combined.
`--force` may bypass a command-specific readiness gate, but it does not imply
apply. PR operations live under `manifest pr ...`; `manifest ship ...` does not
create or queue PRs.

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
| `manifest recipe <sub>` | Inspect workflow recipes behind first-class commands |

### Supporting

| Command | Description |
| ------- | ----------- |
| `manifest pr [sub]` | Pull request lifecycle |
| `manifest revert` | Revert to previous version |

### Maintenance

| Command | Description |
| ------- | ----------- |
| `manifest upgrade [flags]` | Check for and install updates |
| `manifest uninstall [-y] [--force]` | Preview or remove Manifest CLI |
| `manifest reinstall [-y]` | Preview or run full uninstall + reinstall |
| `manifest security` | Security audit and report generation |
| `manifest test [suite]` | Run Cloud-provided diagnostic tests when the plugin is installed |

### Cloud / Agent

| Command | Description |
| ------- | ----------- |
| `manifest cloud <sub>` | Manifest Cloud connector |
| `manifest agent <sub>` | Containerized agent management |

### Recovery

| Command | Description |
| ------- | ----------- |
| `manifest revert` | Roll back to a previous version |

### Hidden Plumbing

| Command | Purpose |
| ------- | ------- |
| `manifest time` | Time info display |
| `manifest docs [sub]` | Documentation generation |
| `manifest cleanup` | Archive old docs |
| `manifest commit <msg>` | Commit with trusted timestamp |
| `manifest version <type>` | Bump version only |

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

**Phase 1** (no `manifest.fleet.tsv` exists): Scans directories up to `--depth` levels, asks for repo granularity per top-level folder when interactive, then creates a compact `manifest.fleet.tsv` for review.

**Phase 2** (TSV exists): Reads selections from TSV, scaffolds each repo, creates fleet configuration.

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--depth N` | Scan guardrail (default: 2) |
| `--all-folders` | Write every scanned folder to the TSV instead of the compact repo-depth view |
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

Prepare workspace: connect remotes, pull latest. Replaces the old `manifest sync` command.

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

**Delegates to:** `_fleet_sync()` in `manifest-fleet.sh`

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

## `manifest recipe`

Inspect the recipe definitions that back first-class Manifest workflows.
Built-in recipes live in [recipes/builtin](../recipes/builtin), and the schema
lives at [docs/contracts/recipe.schema.json](contracts/recipe.schema.json).

```bash
manifest recipe list
manifest recipe show manifest.builtin.ship.repo.patch
manifest recipe explain manifest.builtin.ship.repo.patch
```

First-class commands are the canonical entry points. For example,
`manifest ship repo patch` is the command to run, and
`manifest ship repo patch --explain` shows the recipe definition that declares
that workflow. Project recipes may
compose or extend built-ins explicitly, but they do not silently override
reserved built-in command mappings.

Direct recipe execution is intentionally not part of the public workflow model.
It is ambiguous which user-facing command, safety policy, and help text should
own the operation. Add or extend a first-class command instead, then expose the
recipe through `--explain`.

Mapped first-class commands validate recipe effects before local apply. A
`--local -y` command can run local-write steps, but it refuses any active
`remote-write` recipe step before dispatching the workflow.

**Source:** [manifest-recipe.sh](../modules/recipe/manifest-recipe.sh) `manifest_recipe_dispatch()`

**Subcommands:**

| Subcommand | Description |
| ---------- | ----------- |
| `list` | List built-in and project recipes |
| `show <id>` | Print the recipe YAML |
| `explain <id>` | Show command mapping, definition path, and ordered steps |

---

## `manifest ship`

Publish a release. The highest-consequence command in the CLI.

**Source:** [manifest-ship.sh](../modules/core/manifest-ship.sh) `manifest_ship_dispatch()`

### `manifest ship repo`

Preview or ship a single repo: version bump, documentation, commit, tag, push, Homebrew update, and GitHub Release creation when enabled.

```bash
manifest ship repo patch           # Preview full patch release
manifest ship repo patch -y        # Apply full patch release
manifest ship repo major -i -y     # Apply major release with interactive prompts
manifest ship repo patch --local   # Preview local-only release
manifest ship repo patch --local -y # Apply local-only release
manifest ship repo patch --explain # Show the built-in recipe definition
```

`repo` is a scope, not a selector. The target is the enclosing Git repository
resolved from the shell working directory; Manifest changes to that Git root
before running the workflow. Repo-scoped commands fail outside a Git repository.
To ship a different repo today, start the command from that repo:

```bash
cd /path/to/repo
manifest ship repo patch
```

Manifest does not accept a repo path or fleet-member selector on `ship repo`.
Path selectors and fleet-member selectors are intentionally deferred so `.git`
root selection remains the source of truth.

**Preview mode** (default): prints the resolved repo identity first, including `You are in:`, then the release plan, and writes nothing. The plan includes current and next version, a short narrative summary, pending working-tree files that would be auto-committed, and release documentation artifacts.

**Apply mode** (`-y` / `--yes`): prints the resolved repo identity and an
explicit target summary, then prompts `Apply to this repository? [y/N]` before
mutation. Non-interactive apply exits before mutation with helper text to rerun
from the intended repo folder. After confirmation, apply syncs, bumps version,
generates docs, archives old docs, validates markdown, commits, tags, pushes to
all remotes, updates the Homebrew formula (canonical repo only), creates a
matching GitHub Release when enabled, and safely fast-forwards clean local
Homebrew tap checkouts that the release process updated remotely. Canonical CLI
`minor`, `major`, and `revision` ships also run one guarded follow-up patch
under the upgraded installed CLI; set `MANIFEST_CLI_SHIP_FOLLOWUP_PATCH=false`
to skip it.

**Local apply mode** (`--local -y`): Everything except creating a tag, pushing to remotes, updating Homebrew, creating a GitHub Release, or watching GitHub Actions.

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
`MANIFEST_CLI_DOC_REVIEW_COMMIT_SUBJECT_FILE`, `MANIFEST_CLI_DOC_REVIEW_COMMIT_BODY_FILE`,
and `MANIFEST_CLI_DOC_REVIEW_RELEASE_NOTE_FILE`. A provider can write those files to
override the commit subject, replace the commit body attachment, or replace the
release-note/changelog attachment.

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--dry-run` | Explicit preview; no writes |
| `-y`, `--yes` | Apply the release plan |
| `--local` | Local-only scope when combined with `-y` |
| `--explain` | Show the built-in recipe definition without running it |
| `-i`, `--interactive` | Enable interactive safety prompts |
| `-p` | Patch (short flag) |
| `-m` | Minor (short flag) |
| `-M` | Major (short flag) |
| `-r` | Revision (short flag) |

**Defined by:** `manifest.builtin.ship.repo.<type>` in [recipes/builtin](../recipes/builtin)

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
15. *(if not --local)* `update_homebrew_formula()` — Homebrew (canonical repo only), including safe refresh of clean local tap checkouts
16. *(if not --local)* `manifest_create_github_release_for_tag()` — idempotent matching GitHub Release when enabled
17. *(if not --local)* Local installed Manifest CLI upgrade
18. *(if not --local and MANIFEST_CLI_GITHUB_ACTIONS_WAIT=true)* GitHub Actions status watch for the published HEAD
19. `update_repository_metadata()` — final metadata update
20. *(canonical CLI non-patch ships only)* one guarded follow-up `manifest ship repo patch -y` under the upgraded installed CLI

**Failure handling:** If any step after commit fails, the orchestrator emits a Ship Failure Report with recovery commands (retry push, remove tag, roll back).

**GitHub Actions status:** The Actions watch is opt-in because release artifacts are already pushed by the time CI runs, and waiting would slow the default ship path. Enable it with `MANIFEST_CLI_GITHUB_ACTIONS_WAIT=true`, or tune it with `MANIFEST_CLI_GITHUB_ACTIONS_TIMEOUT_SECONDS` and `MANIFEST_CLI_GITHUB_ACTIONS_POLL_SECONDS`.

**GitHub Release creation:** Manifest creates a matching GitHub Release after the release tag is pushed when `github.release.enabled` is true. The step is idempotent: an existing Release is reported and left alone. Missing `gh`, missing authentication, or non-GitHub origins skip the step unless `github.release.required` is true. Configure with `github.release.enabled`, `github.release.required`, `github.release.draft`, and `github.release.prerelease`.

**Tag target** (step 13): the SHA the tag points at is resolved by `resolve_tag_target_sha()` in [manifest-git.sh](../modules/git/manifest-git.sh) from `MANIFEST_CLI_RELEASE_TAG_TARGET` (YAML key `release.tag_target`):

| Value | Tagged commit |
| ----- | ------------- |
| `version_commit` (default) | Captured SHA of the "Bump version to X" commit |
| `release_head` | HEAD at tag-creation time (post-CHANGELOG, pre-Homebrew) |

Value matching is whitespace- and case-tolerant. Unknown values fall back to `version_commit` and emit a warning to stderr. The Homebrew formula commit is intentionally outside the tag in all cases (see [USER_GUIDE.md#tag-placement-releasetag_target](USER_GUIDE.md#tag-placement-releasetag_target) for the chicken-and-egg explanation).

### `manifest ship fleet`

Preview or apply a coordinated fleet release across release-enabled repositories.

```bash
manifest ship fleet minor                       # Preview coordinated minor release
manifest ship fleet minor -y                    # Apply coordinated minor release
manifest ship fleet minor --local -y            # Apply local-only across fleet
manifest ship fleet patch --noprep              # Skip per-service prep step
```

`ship fleet` is release-only. It does not create, ready, queue, or merge PRs.
Use `manifest pr fleet ...` explicitly for PR workflows.

Preview and apply both start with a fleet scope block showing the fleet name,
root path, config file, command scope, and service count.
The status and ship plan then list `Included repositories` with service name, type, branch,
release/read effect, decision, and path or skip reason where relevant. This is the authoritative
answer to "which repos will this fleet command touch?"

Fleet membership and per-service release eligibility are read from
`manifest.fleet.config.yaml`. Toggle `services.<name>.release.enabled` to
include or exclude a service from coordinated releases.

**Flags:**

| Flag | Description |
| ---- | ----------- |
| `--local` | Local-only mode across fleet |
| `--noprep` | Skip per-service prep step |

Release eligibility is conservative: services with `VERSION` are releaseable by
default, Homebrew tap/formula repositories and the fleet root are skipped, and
services without `VERSION` are skipped unless explicitly configured with
`services.<name>.release.enabled: true` and
`services.<name>.release.strategy: direct`.

**Delegates to:** `fleet_ship()` in `manifest-fleet.sh`; local mode passes `--local` through that same fleet ship path.

## `manifest pr`

Pull request lifecycle management.

```bash
manifest pr                    # Interactive PR wizard (TTY mode)
manifest pr create             # Preview pull request creation
manifest pr create -y          # Create a pull request
manifest pr create --draft --labels "feature" --reviewers "user1" -y
manifest pr update             # Preview branch update
manifest pr update -y          # Update PR branch
manifest pr status             # Show PR status
manifest pr status --pr 42     # Status for a specific PR
manifest pr checks             # Show CI check results
manifest pr checks --watch     # Watch checks in real-time
manifest pr ready              # Preview marking draft PR ready
manifest pr ready -y           # Mark draft PR ready
manifest pr queue              # Preview auto-merge queueing
manifest pr queue --method squash -y
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
| `--dry-run` | Explicit preview for mutating PR operations |
| `-y`, `--yes` | Apply mutating PR operations |
| `--pr <selector>` | Target a specific PR (number or branch) |
| `--labels <list>` | Comma-separated label list |
| `--reviewers <list>` | Comma-separated reviewer list |
| `--draft` | Create as draft PR |
| `--method <strategy>` | Merge strategy: `merge`, `squash`, `rebase` |
| `--force` | Force the operation |
| `--watch` | Watch checks in real-time |

Bare mutating PR commands preview. Use `-y` or `--yes` to create, mark ready,
merge, update, or queue. Read-only PR commands such as `status`, `checks`, and
`policy show` do not require apply mode.

**Source:** `manifest-pr.sh`

---

## `manifest test`

Run extended diagnostic suites when the Manifest Cloud test plugin is installed.
Without that plugin, the command prints an install hint and points to basic
diagnostics.

```bash
manifest test all
manifest test cloud
manifest test agent
```

For Manifest CLI development, use the repository test runner instead:

```bash
./scripts/run-tests-container.sh
./scripts/run-tests-container.sh tests/recipe.bats
```

**Source:** `modules/stubs/manifest-test-stub.sh`, or a Cloud plugin when installed.

---

## `manifest security`

Run security audit: scans for tracked private files, likely PII, and environment-file hygiene. Plain `manifest security` writes report files; use `--check` for read-only automation.

```bash
manifest security
manifest security --check
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
manifest status fleet                  # Fleet repository status table
manifest discover fleet --depth 3      # Find new repos (alias for update --dry-run)
manifest update fleet                  # Preview membership rescan
manifest update fleet -y               # Apply membership rescan
manifest update fleet --dry-run        # Preview changes
manifest add fleet ./path --name "svc" --dry-run # Preview service YAML
manifest validate fleet                # Validate config
manifest prep fleet --parallel         # Preview clone/pull all
manifest prep fleet --parallel -y      # Apply clone/pull all
manifest refresh fleet                 # Preview re-scan + regenerate docs
manifest refresh fleet -y              # Apply re-scan + regenerate docs
manifest docs fleet --dry-run          # Preview fleet documentation writes
manifest pr fleet queue --method squash -y # Fleet PR operations
manifest ship fleet minor              # Preview coordinated release
manifest ship fleet minor -y           # Apply coordinated release
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
