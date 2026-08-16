# Manifest CLI User Guide

Manifest organizes release work into explicit stages:

```text
config -> init -> prep -> refresh -> ship
```

Each mutating stage previews by default. Add `-y` or `--yes` to apply. New to
the preview/apply model or the release gate? See the [Migration Guide](MIGRATION.md).

## Core Concepts

### Repo Scope

Repo scope targets the enclosing Git repository.

```bash
manifest status repo
manifest ship repo patch
manifest ship repo patch -y
```

Manifest chooses the repo from the current directory's `.git` root. It does not accept a path selector for repo-scoped release commands.

### Fleet Scope

Fleet scope targets repositories selected by `manifest.fleet.config.yaml` and `manifest.fleet.tsv`.

```bash
manifest status fleet
manifest ship fleet patch
manifest ship fleet patch -y
```

Fleet commands print the fleet root, config path, selected services, release decisions, and branch state before apply.

### Preview And Apply

| Form | Meaning |
| ---- | ------- |
| No `-y` | Preview |
| `--dry-run` | Explicit preview |
| `-y` / `--yes` | Apply |
| `--local -y` | Apply local writes only; skip remote side effects |

`-y` applies with no confirmation prompt. `MANIFEST_CLI_AUTO_CONFIRM=1` only authorizes an *ambiguous* apply target (detached HEAD, or no `origin`) after `-y`; it is not an apply selector and is not needed for an ordinary apply.

## First-Time Setup

Start with `manifest first` — the guided onboarding front door. It inspects the current directory (a single repo, a directory of repos, or an already-configured project) and previews an opinionated setup, writing nothing until you apply.

```bash
manifest first
manifest first -y
```

`manifest first` previews by default and applies the proposed setup with `-y` (audited). Under the hood it delegates to the initializers below, so you can also drive them directly:

```bash
manifest doctor
manifest config show
manifest init repo
manifest init repo -y
```

`manifest init repo` scaffolds required project files such as `VERSION`, `CHANGELOG.md`, docs, and ignore rules.

## Repository Release Workflow

Inspect:

```bash
manifest status
manifest doctor
```

Prepare:

```bash
manifest prep repo
manifest prep repo -y
```

Preview release:

```bash
manifest ship repo patch
manifest ship repo minor
manifest ship repo major
```

Apply:

```bash
manifest ship repo patch -y
```

Local-only apply:

```bash
manifest ship repo minor --local -y
```

Repo ship can bump `VERSION`, update `CHANGELOG.md`, refresh docs, commit, tag, push, create a GitHub Release, and publish the Homebrew tap formula when the repo is the canonical CLI repo. The tap formula publish does not create a post-tag commit in the CLI repo, and ship refuses to report success if completion leaves the source tree dirty or advances `HEAD` after the pushed release head.

Ship's auto-commit stages the whole tree, then unstages any nested git repository it would have captured as a bare gitlink (a directory with its own `.git` and no `.gitmodules` entry) and prints a notice with the remediation options. Declared submodules and gitlinks already tracked in `HEAD` are left alone. To record bare gitlinks intentionally, set `git.allow_new_gitlinks: true` (`MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS`).

Auto-commit also leaves out work that appeared **after** you asked to ship. Ship records the pending set before running the release gate, and a full-tier gate takes minutes — long enough for a concurrent session, an editor autosave, or a background generator to drop files into the tree. Those are unstaged and reported, so the **auto-commit** carries only what you had when you invoked it. Note the scope: the guard holds those paths out of the auto-commit, not out of the release. The version commit later in the same ship stages the whole tree by design — `VERSION`, `CHANGELOG.md` and regenerated docs all legitimately post-date the snapshot — so anything the guard listed still lands there, one commit later. Treat the `Left out …` list as "not in the auto-commit", and confirm with `git show --stat HEAD` rather than assuming those files went unreleased. Set `git.allow_gate_drift: true` (`MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT`) to skip the guard entirely and sweep everything into the auto-commit. Manifest's own `.manifest-cli/` bookkeeping is exempt, since the gate writes its pass ledger there mid-run by design.

## Version Ownership

Manifest has one canonical release-writer file today: `VERSION`.

`VERSION` holds an ordered list of numeric segments of any length. How an increment maps to a segment, how segments are named (`version.components`), and why a fourth segment does not survive a `patch` are documented once, in [Command Reference — Version increments](COMMAND_REFERENCE.md#version-increments).

Other version-bearing files are non-canonical. This includes package manifests, package locks, module files, and chart files such as `package.json`, `package-lock.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, and `Chart.yaml`. Manifest detects these surfaces from the committed handler catalog, but detection is passive: it does not rewrite them, print noisy warnings during scripts, or stop non-interactive runs.

To mirror the canonical version into selected package/version files, opt in with `version.sync`:

```yaml
version:
  sync: "package.json,pyproject.toml,Chart.yaml"
```

Unset `version.sync` is the default and leaves package files and lockfiles untouched. The current writer updates only top-level JSON, TOML, and YAML `version` fields and skips missing, nested-only, or unsupported targets.

Version-surface reporting is configurable:

```yaml
version:
  surfaces:
    enabled: true
    catalog: ""          # empty = built-in catalog
    scan_depth: 5
    notification_mode: summary # summary | list | off
```

Human `manifest status` and fleet status stay quiet when only canonical version files are present, summarize non-canonical detections by default, and list files when `notification_mode` is `list`. `manifest status --json` includes the full `version_surfaces` object. `manifest doctor` reports invalid policy and non-canonical detections as warnings only.

`files.version` is available in configuration and is used by the passive scanner to classify a custom version file as canonical. Repo ship, the main status version field, resume, and fleet release paths still treat `VERSION` as the release-writer file; full custom canonical filename support is tracked in [TRACKER §8.12](TRACKER.md#8--enterprise-readiness-audit-2026-06-05).

## Fleet Workflow

### Initialize A Fleet

```bash
manifest init fleet
```

The first run scans and writes `manifest.fleet.tsv` for review. After editing the TSV, run the command again to create fleet config and repo scaffolding.

Useful variants:

```bash
manifest init fleet --depth 3
manifest init fleet --all-folders
manifest init fleet --name platform-services
manifest init fleet --create-repo-private   # preview local init + remote targets
manifest init fleet --create-repo-private -y
```

Remote creation remains explicit even with `-y`. Configure the destination namespace once when repositories belong to an organization:

```yaml
github:
  owner: fidenceio
```

The preview prints every repository that would be created as `<owner>/<name>`. With `github.owner` unset, the owner is taken from the repository's own `origin` remote; only a directory with no origin of its own displays `<authenticated-user>`, where `gh` creates under its authenticated account. A directory nested inside a parent repository does not inherit that parent's owner. When `github.owner` is set and disagrees with `origin`, the configured value wins and the conflict is reported — an interactive run offers the origin owner instead, a non-interactive one never blocks. Existing member origins win; directories without their own `.git` are initialized from live disk state even if the preserved TSV still says `HAS_GIT=true`.

### Adopt An Existing Workspace

```bash
manifest plan fleet
manifest plan fleet --apply
manifest reconcile fleet
manifest reconcile fleet --do
```

`--commit` requires `--apply` / `--do`. `--push` requires `--commit`.

### Operate A Fleet

```bash
manifest status fleet
manifest prep fleet
manifest update fleet          # re-scan membership (was 'refresh fleet'; docs: 'manifest docs fleet')
manifest ship fleet patch
manifest ship fleet patch -y
manifest ship fleet patch --local -y
```

Release-disabled services are listed and skipped by ship. Release-enabled services are still skipped when they have no release changes, which means a clean worktree whose HEAD already matches the current `VERSION` tag.

### Project Repo Names Onto GitHub Topics

Fleets whose repo names follow a dot-separated convention can mirror that taxonomy as GitHub topics, making the org page filterable (`?q=topic:accounting`). Opt in with one key in `manifest.fleet.config.yaml`:

```yaml
topics:
  from_name: inner   # fidence.service.accounting.avalara -> service, accounting
```

Modes: `inner` (drop first and last slug), `all-but-first`, `all`. Members also receive a `fleet-<name>` topic. `manifest update fleet` previews the per-repo delta; `-y` applies it. Pushes are additive-only — Manifest reads each repo's existing topics first, never re-pushes one that is already defined, and never removes anything. Removing the key stops topic management without undoing prior pushes. When `gh` is missing or unauthenticated the step is skipped with a notice.

The same run also reports a roster check: org repos that share a naming family with an enrolled member (same first dot-slug) but are not in the local fleet — typically new repos nobody has cloned yet. The roster is read-only; clone a listed repo into the fleet root and rerun `manifest update fleet` to enroll it.

## Pull Request Workflow

Native PR commands wrap `gh` and do not require Manifest Cloud:

```bash
manifest pr
manifest pr create --draft
manifest pr checks --watch
manifest pr ready
manifest pr update
manifest pr merge --squash
```

Cloud-only extensions:

```bash
manifest pr queue
manifest pr policy show
manifest pr policy validate
```

If Cloud plugins are missing, Cloud-only routes print install guidance. Native PR routes continue to work.

## Configuration

This section is the canonical description of Manifest's configuration layers.

### Layer model

Every setting is resolved from six layers. Later layers win.

| # | Layer | Source | Applies | Writable |
| - | ----- | ------ | ------- | -------- |
| 1 | `defaults` | Built into the CLI | Always | No |
| 2 | `global` | `~/.manifest-cli/manifest.config.global.yaml` | Always | Yes (safety-gated) |
| 3 | `fleet` | `<fleet-root>/manifest.config.yaml`, then `<fleet-root>/manifest.config.local.yaml` | Only when this repo sits **below** a fleet root; skipped when it **is** the fleet root | No — write it at the fleet root |
| 4 | `project` | `./manifest.config.yaml` | Always | Yes |
| 5 | `local` | `./manifest.config.local.yaml` | Always (git-ignored) | Yes (default) |
| 6 | `env` | Exported `MANIFEST_CLI_*` captured at process start | Always | n/a |

### The fleet layer

A repository nested inside a fleet inherits the fleet root's configuration as a
baseline, so one fleet-wide setting applies to every member without being copied
into each repo. Three things about it are easy to get wrong:

- **`manifest.fleet.config.yaml` is not a configuration layer.** It is the fleet
  *definition*, and the sentinel whose presence makes a directory the fleet root.
  The two files that form the `fleet` layer are the fleet root's ordinary
  `manifest.config.yaml` and `manifest.config.local.yaml`.
- **Inheritance is skipped at the fleet root itself.** There, those same two
  files are already layers 4 and 5; counting them twice would be meaningless.
- **The fleet root is found by walking up for the sentinel**, starting from the
  project root. Setting a fleet root explicitly does not redirect this — the
  config layer follows the sentinel and nothing else.

### Inspecting layers

`manifest config describe <key>` shows every layer, highest precedence first,
with the file each value came from:

```text
Key:       github.owner
Env var:   MANIFEST_CLI_GITHUB_OWNER
Fleet:     /work/acme
Effective: acme-corp  (from fleet)

Layers (highest precedence first):
  env      ·   (MANIFEST_CLI_GITHUB_OWNER — not exported at process start)
  local    ·   (/work/acme/services/api/manifest.config.local.yaml — not present)
  project  ·   (/work/acme/services/api/manifest.config.yaml — not present)
  fleet    acme-corp   (/work/acme/manifest.config.local.yaml)
  fleet    ·   (/work/acme/manifest.config.yaml — not present)
  global   ·   (~/.manifest-cli/manifest.config.global.yaml — not present)
  defaults ·   (built-in)
```

A shadowed value stays visible, so you can see what is overriding what.
`manifest config list` shows every key that has an explicit source, with its
winning layer; `--layer <name>` narrows to one layer, including `fleet`.

### Writing configuration

```bash
manifest config show
manifest config list
manifest config list --layer fleet
manifest config get git.tag_prefix
manifest config describe git.tag_prefix
manifest config set git.tag_prefix release-
manifest config unset git.tag_prefix
manifest config doctor
manifest config doctor --fix
```

`config set` writes local config by default. Global writes go through an
additional safety gate.

`--layer` on `set`/`unset` accepts only `global`, `project` and `local`. The
`fleet` layer is read-only from inside a member because its files live in a
**different repository** — writing them from here would mutate a repo you did
not name. To change a fleet-wide value, run the same command **at the fleet
root**, where those files are ordinary `project`/`local` layers:

```bash
cd /path/to/fleet-root
manifest config set --layer project github.owner acme-corp
```

### Environment overrides

Every user-facing key maps to a `MANIFEST_CLI_*` environment variable. An
exported variable outranks every configuration file.

This layer is a **snapshot taken when the process starts**: exporting a variable
part-way through a session does not create an override. And a variable exported
*empty* is not a no-op — it suppresses all the file layers and falls through to
the built-in default. `config describe` reports that case explicitly.

## Documentation Generation

```bash
manifest docs
manifest docs metadata
manifest docs cleanup
manifest docs fleet --dry-run
```

Docs-site generation for Jekyll/GitHub Pages is on by default; disable it via config if you don't want it. See [DOCS_SITE.md](DOCS_SITE.md).

## Testing Manifest

Contributor validation is containerized:

```bash
./scripts/run-tests-container.sh
./scripts/run-tests-container.sh tests/docs_generation.bats
```

Do not install test dependencies on the host.

## Security And Maintenance

```bash
manifest security --check
manifest security
manifest upgrade
manifest uninstall
manifest uninstall -y
```

The versioned pre-commit hook is documented in [../.git-hooks/README.md](../.git-hooks/README.md).
