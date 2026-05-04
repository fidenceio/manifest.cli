# Fleet Adoption Handoff

**Status:** Implementation and documentation landed locally and verified.
**Last verified:** Disposable Ubuntu container run passed `224/224`.

## What Changed

- Added `manifest plan fleet`.
  - Dry-run by default.
  - `--apply` and `--do` are exact aliases.
  - Writes `manifest.fleet.plan.yaml`.
  - Generates plan entries for `track`, `init`, `move`, `adopt_submodule`, and `skip`.

- Added `manifest reconcile fleet`.
  - Dry-run by default.
  - `--apply` and `--do` apply local filesystem/config changes.
  - `--commit` requires `--apply` or `--do`.
  - `--push` requires `--commit`.
  - `--force` requires `--apply` or `--do`, but does not bypass target path collisions.
  - `--adopt-submodules` is required before any `adopt_submodule` action can apply.

- Improved submodule detection.
  - Fleet discovery now treats a `.git` file as a git working tree marker, which is normal for hydrated submodules.

- Added smart documentation review before Manifest-created commits.
  - Generates a deterministic local review report.
  - Adds review context to the commit body when enabled.
  - Supports a command provider for external review integration.
  - Maps `docs.review.*` YAML settings to `MANIFEST_CLI_DOC_REVIEW*` env vars.

## Files Changed

- `modules/fleet/manifest-fleet-plan.sh`
- `modules/fleet/manifest-fleet-apply.sh`
- `modules/fleet/manifest-fleet-detect.sh`
- `modules/fleet/manifest-fleet.sh`
- `modules/core/manifest-core.sh`
- `modules/core/manifest-config.sh`
- `modules/core/manifest-yaml.sh`
- `modules/git/manifest-doc-review.sh`
- `modules/git/manifest-git.sh`
- `modules/git/manifest-git-changes.sh`
- `tests/fleet_plan_reconcile.bats`
- `tests/doc_review.bats`
- `tests/yaml.bats`
- `README.md`
- `docs/COMMAND_REFERENCE.md`
- `docs/USER_GUIDE.md`
- `docs/EXAMPLES.md`
- `examples/manifest.config.yaml.example`
- `completions/manifest.bash`
- `completions/_manifest`
- `tests/completions.bats`

## Safety Contract

Fleet adoption/conversion commands should be safe to mistype:

```bash
manifest plan fleet
manifest reconcile fleet
```

Both are read-only by default. Local mutation requires:

```bash
--apply
```

or:

```bash
--do
```

The escalation ladder is:

```text
default              inspect, validate, explain
--apply / --do       write local files, move folders, init repos
--commit             create local commits; requires --apply/--do
--push               push remotes; requires --commit
```

Target path collisions stay blocked even with `--force`. If `target_path` already exists, the user must resolve it deliberately by editing the plan or moving/archiving the existing target.

## Tests Added

`tests/fleet_plan_reconcile.bats` covers:

- `plan fleet` dry-run default writes nothing.
- `plan fleet --do` writes `manifest.fleet.plan.yaml`.
- `--apply` and `--do` are compatible aliases.
- `reconcile fleet` dry-run validates and writes nothing.
- `reconcile fleet --apply` initializes and tracks a plain directory.
- `reconcile fleet --do` behaves like `--apply`.
- `--commit`, `--push`, and `--force` ladder guards.
- Target path collision blocking.
- Nested target path blocking.
- `.gitmodules` discovery as `adopt_submodule`.
- `adopt_submodule` blocked unless `--adopt-submodules` is present.
- Nested submodule adoption removes the parent-relative path.

`tests/doc_review.bats` covers:

- Local documentation-impact classification.
- Commit report generation and commit body attachment.
- Release note extraction from committed review reports.
- Required external provider failure handling.
- External provider subject/body/release-note overrides.
- Configurable report directory.

## Verification Commands

Focused:

```bash
scripts/run-tests.sh tests/fleet_plan_reconcile.bats
scripts/run-tests.sh tests/fleet_private_routes.bats tests/fleet_plan_reconcile.bats
```

Regression:

```bash
scripts/run-tests.sh tests/fleet_dry_run.bats tests/fleet_init_phase.bats tests/create_repo.bats tests/fleet_private_routes.bats tests/help_dispatch.bats
```

Full:

```bash
scripts/run-tests.sh
```

Latest full run passed `224/224`.

## Remaining Work

- None for the verified local implementation.
