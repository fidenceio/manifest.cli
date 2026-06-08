# Manifest Fleet Design Spec

Manifest Fleet coordinates independent Git repositories from one workspace. It does not require submodules and does not collapse child repos into the parent Git history.

## Goals

- Make repo and fleet release workflows use the same command model.
- Keep fleet membership explicit and reviewable.
- Support release-enabled and release-disabled services in the same workspace.
- Preview every mutation before apply.
- Keep parent workspace metadata separate from child repo implementation.

## Core Files

| File | Purpose |
| ---- | ------- |
| `manifest.fleet.tsv` | Human-reviewable scan output and selection table |
| `manifest.fleet.config.yaml` | Canonical fleet config used by commands |
| `manifest.fleet.plan.yaml` | Adoption/reconciliation plan written by `manifest plan fleet --apply` |

## Initialization

`manifest init fleet` is intentionally two-phase:

1. Scan directories and write `manifest.fleet.tsv`.
2. After review, consume the TSV and write fleet config/scaffolding.

Fleet scanning uses the shared discovery walker in `modules/core/manifest-discovery.sh` with the fleet profile. That profile preserves fleet-specific pruning, including dependency/build directories and package workspace directories that should not become fleet members by default.

Useful flags:

```bash
manifest init fleet --depth 3
manifest init fleet --all-folders
manifest init fleet --name platform-services
manifest init fleet --force
```

## Adoption And Reconciliation

```bash
manifest plan fleet
manifest plan fleet --apply
manifest reconcile fleet
manifest reconcile fleet --do
```

The plan/reconcile path exists for existing workspaces. It protects against target collisions and requires explicit opt-in for submodule adoption.

Mutation ladder:

- `--commit` requires `--apply` or `--do`.
- `--push` requires `--commit`.
- `--force` does not bypass target-collision checks.
- `adopt_submodule` requires `--adopt-submodules`.

## Release Model

Each fleet service has a release policy:

```yaml
services:
  example:
    path: "./example"
    type: "service"
    branch: "main"
    release:
      enabled: true
      strategy: "direct"
```

`strategy` is a single self-describing field. Its values read in plain English:

- `direct` — `manifest ship fleet` tags and pushes the release directly.
- `none` — the member is never released by fleet ship (skipped).
- `pr` — the member is **PR-gated**: its release must land through a reviewed pull request. `manifest ship fleet` lists PR-gated members in the preview and **refuses to apply** them (fail-closed), printing a `manifest pr fleet ... -y` replay command. Release them with `manifest pr fleet -y`.

Release-disabled services appear in status and planning output but are skipped by `manifest ship fleet`.

Fleet release still operates each member through the repo release flow, whose version writer updates that member's `VERSION` file and explicit `version.sync` targets only.

## Repo Identity

Repo-scoped commands use the current `.git` root. Fleet-scoped commands use the fleet root and config. The CLI prints the resolved target before apply so a nested checkout cannot be released by accident.

## Docs Generation

Fleet docs generation can refresh per-service docs and generate a managed Jekyll docs site. Docs-site generation is on by default and covered in [DOCS_SITE.md](DOCS_SITE.md).

## Current Limitations

- Repo-scoped release commands do not accept a path selector.
- Fleet release strategies are `direct`, `none`, or `pr` (PR-gated, routed to `manifest pr fleet`); more advanced orchestration belongs behind explicit future config.
- MCP fleet operations are planned as read-only in v1.
