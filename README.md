# Manifest CLI

Manifest CLI is release control for agent-assisted development. It keeps version bumps, changelogs, docs, tags, pushes, GitHub Releases, pull requests, and multi-repo fleet releases on one explicit preview/apply path.

[![tests](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml/badge.svg)](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml)

**Version:** `53.0.1`
**Platforms:** macOS, Linux, FreeBSD
**Primary interface:** `manifest <verb> <scope> [options]`

## Why It Exists

Agent-assisted work makes it easy to create several changes at once. Shipping them safely is the harder part. Manifest gives a repository or fleet a repeatable release path:

- Inspect current state before acting.
- Preview local and remote side effects.
- Apply only after `-y` / `--yes`.
- Keep release notes, changelog entries, generated docs, tags, and GitHub Releases aligned.
- Use the same command model for one repo and for a fleet.

## Safety Model

Manifest mutating commands preview by default.

```bash
manifest ship repo patch        # preview
manifest ship repo patch -y     # apply
manifest ship repo patch --local -y
```

`--dry-run` is the explicit preview spelling. `--local -y` applies local release work without tag, push, GitHub Release, or Homebrew publication. `MANIFEST_CLI_AUTO_CONFIRM=1` can answer prompts after apply mode is selected; it does not authorize apply by itself.

## Version Ownership

Manifest treats `VERSION` as the canonical release file for repo and fleet ship today. It does not rewrite package-manager files such as `package.json`, `package-lock.json`, `pyproject.toml`, `Cargo.toml`, or lockfiles unless the project explicitly opts in.

`version.sync` is the opt-in mirror list for files whose own top-level version field should follow the canonical version during a bump. With `version.sync` unset, `manifest ship repo patch -y` updates the canonical version only. Sync writers currently support top-level JSON, TOML, and YAML `version` fields and skip missing, nested-only, or unsupported targets without creating files.

Manifest also ships a committed handler catalog at [modules/catalog/version-handlers.tsv](modules/catalog/version-handlers.tsv). The catalog powers passive detection of non-canonical version surfaces in `manifest status`, `manifest doctor`, `manifest status fleet`, and fleet ship previews without mutating files or blocking non-interactive scripts. Tune reporting with `version.surfaces.enabled`, `version.surfaces.catalog`, `version.surfaces.scan_depth`, and `version.surfaces.notification_mode` (`summary`, `list`, or `off`). `files.version` is mapped and recognized by the passive scanner, but full repo/fleet release writing still uses `VERSION` today.

Canonical CLI releases may publish the Homebrew tap formula after the GitHub Release exists. That tap formula publish is a distribution update only; Manifest must not add a generated post-tag formula commit to the CLI repo. Before reporting success, ship verifies that the source working tree is clean and that a published release has not advanced `HEAD` after the branch/tag push.

## Install

For product use, install from the Homebrew tap:

```bash
brew tap fidenceio/tap
brew install manifest
```

Install script alternative:

```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

For repository development and validation, do not install dependencies on the host. Use the containerized test runner:

```bash
./scripts/run-tests-container.sh
```

More detail: [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Runtime Requirements

| Requirement | Version | Notes |
| ----------- | ------- | ----- |
| Bash | 5.0+ | Required for associative arrays and modern shell behavior |
| yq | 4.0+ (Mike Farah) | Required for YAML configuration parsing |
| Git | Any supported release | Required for repository status, tags, commits, and pushes |
| coreutils | Any | Required on macOS for the supported timeout command |
| Docker | Running engine | Required by the containerized development and test workflow |

## First Release

New here? `manifest first` inspects the current directory (single repo or a
folder of repos), reports what's set up, and proposes the rest as a preview —
writing only when you confirm with `-y`:

```bash
cd your-project

manifest first                  # read-only: inspect + preview the setup plan
manifest first -y               # apply the proposed setup (audited)
```

Or drive each step yourself:

```bash
manifest init repo              # preview required files
manifest init repo -y           # write VERSION, CHANGELOG.md, docs/, ignores

manifest prep repo              # preview remote/config prep
manifest prep repo -y           # apply prep

manifest ship repo patch        # preview release
manifest ship repo patch -y     # publish release
```

Useful read-only checks:

```bash
manifest status
manifest doctor
manifest config list
```

## Fleet Release

A fleet is a workspace of independent Git repositories described by `manifest.fleet.config.yaml` and `manifest.fleet.tsv`.

```bash
manifest init fleet             # scan or consume fleet TSV
manifest status fleet           # inspect selected repos
manifest ship fleet patch       # preview services with release changes
manifest ship fleet patch -y    # apply services with release changes
```

Fleet ship skips unchanged members. A release-enabled member is eligible for release, but it is only bumped when its worktree has release changes or its HEAD differs from the current `VERSION` tag.

Fleet adoption and reconciliation stay preview-first:

```bash
manifest plan fleet
manifest plan fleet --apply
manifest reconcile fleet
manifest reconcile fleet --do
```

More detail: [docs/FLEET_DESIGN_SPEC.md](docs/FLEET_DESIGN_SPEC.md).

## Command Model

| Area | Commands |
| ---- | -------- |
| Setup | `manifest first`, `manifest config`, `manifest init repo`, `manifest init fleet` |
| Preparation | `manifest prep repo`, `manifest prep fleet` |
| Refresh | `manifest refresh repo`, `manifest refresh fleet` |
| Release | `manifest ship repo <type>`, `manifest ship fleet <type>` |
| Diagnostics | `manifest status`, `manifest doctor`, `manifest security --check` |
| Pull requests | `manifest pr create`, `manifest pr checks`, `manifest pr ready`, `manifest pr merge`, `manifest pr update` |
| Recipes | `manifest recipe list`, `manifest recipe show`, `manifest recipe explain` |

Release types: `patch`, `minor`, `major`, `revision`.

Complete grammar: [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md).

## Configuration

Configuration is YAML-backed and layered:

1. Built-in defaults
2. `~/.manifest-cli/manifest.config.global.yaml`
3. `manifest.config.yaml`
4. `manifest.config.local.yaml`

Every user-facing key maps to a `MANIFEST_CLI_*` environment variable through the YAML bridge. Use `manifest config describe <key>` to see the effective value, layer source, and env-var name.

Schema example: [examples/manifest.config.yaml.example](examples/manifest.config.yaml.example).

## Documentation Map

| Document | Purpose |
| -------- | ------- |
| [docs/INDEX.md](docs/INDEX.md) | Task-based documentation index |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Daily workflows and operating model |
| [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) | Command grammar and flags |
| [docs/EXAMPLES.md](docs/EXAMPLES.md) | Copyable workflow examples |
| [docs/INSTALLATION.md](docs/INSTALLATION.md) | Product install and contributor validation |
| [docs/FLEET_DESIGN_SPEC.md](docs/FLEET_DESIGN_SPEC.md) | Fleet architecture |
| [docs/CLI_TRANSACTION_MAP.md](docs/CLI_TRANSACTION_MAP.md) | High-consequence transaction paths |
| [modules/catalog/version-handlers.tsv](modules/catalog/version-handlers.tsv) | Known non-canonical version/package surfaces |
| [tests/README.md](tests/README.md) | Containerized test workflow |

## Optional Cloud

Manifest CLI works without Manifest Cloud. Optional Cloud plugins can extend release-note generation, queue/policy behavior, MCP reports, and agent workflows. Missing Cloud plugins fall back to install guidance instead of blocking core repo and fleet releases.

Cloud repo: [fidenceio.manifest.cloud](https://github.com/fidenceio/manifest.cloud)

## Project

| Document | Purpose |
| -------- | ------- |
| [LICENSE](LICENSE) | Apache License 2.0 |
| [SECURITY.md](SECURITY.md) | Security policy and private vulnerability disclosure |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, tests, and contribution flow |

Licensed under the [Apache License 2.0](LICENSE).
