# Manifest CLI Command Reference

This reference documents the supported public command surface. Use `manifest <command> --help` for live help text. For the preview/apply model, `MANIFEST_CLI_AUTO_CONFIRM` semantics, and the release gate, see the [Migration Guide](MIGRATION.md).

## Global Rules

| Rule | Detail |
| ---- | ------ |
| Scope grammar | `manifest <verb> <scope>`, for example `manifest ship repo patch` |
| Preview default | Mutating commands preview unless `-y` / `--yes` is present |
| Explicit dry run | `--dry-run` always means preview |
| Local apply | `--local -y` applies local writes and suppresses remote side effects |
| Repo identity | Repo scope uses the current `.git` root |
| Fleet identity | Fleet scope uses fleet config and selected TSV entries |

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Command succeeded — an apply completed, or a preview ran (default) |
| `1` | Error: bad arguments, failed pre-flight, declined confirmation, or a failed apply |
| `3` | Protective skip — a sandbox guard refused a destructive op (e.g. uninstall under a temp `HOME`) |
| `10` | Preview happened, no consent — emitted only when `preview.exit_code` is set to `distinct` |

A preview returns `0` by default, exactly like a successful apply. CI wrappers that need to tell "previewed, awaiting `-y`" apart from a real apply can set `preview.exit_code: distinct` (env `MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct`); every preview surface — `ship`, `ship fleet`, and the `pr` previews — then returns `10` instead of `0`. This is purely additive: `--dry-run` stays a preview, apply exit codes are unchanged, and the recomputed plan fingerprint is compared at apply time so a plan that drifted since the preview prints a non-blocking warning.

## Core Journey

### `manifest first`

```bash
manifest first
manifest first --dry-run
manifest first -y
manifest first --depth N|auto
manifest first --name NAME
manifest first -f|--force
```

The guided onboarding front door. By default it runs a read-only inspection of the current directory and previews an opinionated setup — a single repo, a fleet candidate, or an already-configured repo/fleet — writing nothing. With `-y` it applies the proposed setup through the audited apply gate (one apply-event record per run); for a single repo the apply is confirmed with no extra env var when the target is unambiguous (a named branch — an origin remote is not required during onboarding).

`quickstart` is a deprecated alias for `manifest first` and forwards all arguments. Prefer `manifest first`.

### `manifest config`

```bash
manifest config
manifest config show
manifest config setup
manifest config list
manifest config get <key>
manifest config set [--layer local|project|global] <key> <value>
manifest config unset [--layer local|project|global] <key>
manifest config describe <key>
manifest config doctor
manifest config doctor --fix
```

Reads and writes layered YAML config. Global writes and destructive fixes are confirmation-gated.

### `manifest init`

```bash
manifest init repo [--dry-run] [-y|--yes]
manifest init fleet [--dry-run] [-y|--yes] [--depth N] [--all-folders] [--name NAME] [--force]
```

`init repo` scaffolds required repo files. `init fleet` is a two-phase fleet discovery and config creation workflow.

### `manifest prep`

```bash
manifest prep repo [--dry-run] [-y|--yes]
manifest prep fleet [--dry-run] [-y|--yes] [--parallel]
```

Prepares remotes and workspace state before release work.

### `manifest refresh`

```bash
manifest refresh repo [--dry-run] [-y|--yes]
manifest refresh fleet [--dry-run] [-y|--yes]
```

Refreshes generated metadata, docs, and fleet membership.

### `manifest ship`

```bash
manifest ship repo patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--explain] [-i]
manifest ship fleet patch|minor|major|revision [--dry-run] [-y|--yes] [--local]
```

Repo ship can bump version, generate docs, commit, tag, push, publish GitHub Release notes, and update the Homebrew tap when applicable.

Fleet ship applies the same release policy to release-enabled fleet services.

Version-file behavior:

- Repo and fleet release writers use `VERSION` as the canonical version file today.
- `version.sync` is opt-in. When unset, package manifests and lockfiles are not incremented.
- The passive version-surface scanner uses `modules/catalog/version-handlers.tsv` to describe known package/version files. It recognizes `files.version` for classification, but it is an internal detection surface today, not a separate public command.

## Fleet Operations

```bash
manifest status fleet
manifest discover fleet [--depth N] [--all-folders]
manifest add fleet <path> --name <name> [--dry-run] [-y|--yes]
manifest update fleet [--dry-run] [-y|--yes]
manifest validate fleet
manifest docs fleet [--dry-run] [-y|--yes]
manifest plan fleet [--apply]
manifest reconcile fleet [--do|--apply] [--commit] [--push] [--adopt-submodules]
```

Action-first fleet syntax is the supported surface.

## Diagnostics

```bash
manifest status [repo|fleet]
manifest doctor
manifest security --check
manifest recipe list
manifest recipe show <recipe-id>
manifest recipe explain <recipe-id>
```

Diagnostics are read-only unless a command explicitly documents otherwise.

## Pull Requests

Native `gh` wrappers:

```bash
manifest pr
manifest pr create [--draft] [gh flags...]
manifest pr status [<number|branch>]
manifest pr checks [<number|branch>] [--watch]
manifest pr ready [<number|branch>] [-y|--yes]
manifest pr merge [<number|branch>] [--squash|--merge|--rebase] [-y|--yes]
manifest pr update [<number|branch>] [-y|--yes]
```

Cloud extensions:

```bash
manifest pr queue
manifest pr policy show
manifest pr policy validate
```

## Documentation

```bash
manifest docs
manifest docs metadata
manifest docs cleanup
manifest docs fleet --dry-run
```

Docs-site publishing is controlled by `docs.generate.site`, `docs.site.enabled`, and related config keys. See [DOCS_SITE.md](DOCS_SITE.md).

## Maintenance

```bash
manifest upgrade
manifest uninstall [--dry-run] [-y|--yes]
manifest reinstall [--dry-run] [-y|--yes]
manifest security
manifest test [suite]
```

`uninstall` previews by default and preserves global config unless destructive removal is explicitly confirmed.

## Optional Cloud And Agent

```bash
manifest cloud config|status|generate
manifest agent init|auth|status
```

These routes require Manifest Cloud plugins. Core repo and fleet release commands do not require Cloud.

## Environment

Common environment variables:

| Variable | Purpose |
| -------- | ------- |
| `MANIFEST_CLI_AUTO_CONFIRM` | Answer prompts after explicit apply selection |
| `MANIFEST_CLI_PREVIEW_EXIT_CODE` | `zero` (default) or `distinct` — exit code for a preview-without-consent (see Exit Codes) |
| `MANIFEST_CLI_SHIP_FOLLOWUP_PATCH` | Control canonical follow-up patch behavior |
| `MANIFEST_CLI_DOCS_GENERATE_SITE` | Enable docs-site generation |
| `MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES` | Request Pages enablement through `gh api` |
| `MANIFEST_CLI_GITHUB_ACTIONS_WAIT` | Wait for GitHub Actions in release paths |

Use `manifest config describe <key>` for the authoritative YAML-to-env mapping.
