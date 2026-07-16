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

## Version Ownership

Manifest has one canonical release-writer file today: `VERSION`.

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

The preview prints every repository that would be created as `<owner>/<name>`. With `github.owner` unset, the displayed owner is `<authenticated-user>` and `gh` creates under its authenticated account. Existing member origins win; directories without their own `.git` are initialized from live disk state even if the preserved TSV still says `HAS_GIT=true`.

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

Configuration loads in this order:

1. Built-in defaults
2. `~/.manifest-cli/manifest.config.global.yaml`
3. `manifest.config.yaml`
4. `manifest.config.local.yaml`

Commands:

```bash
manifest config show
manifest config list
manifest config get git.tag_prefix
manifest config describe git.tag_prefix
manifest config set git.tag_prefix release-
manifest config unset git.tag_prefix
manifest config doctor
manifest config doctor --fix
```

`config set` writes local config by default. Global writes go through an additional safety gate.

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
