# Manifest CLI Examples

All mutating examples preview unless they include `-y` or `--yes`.

## New Repository

```bash
cd my-project
manifest doctor
manifest init repo
manifest init repo -y
manifest status
```

## Patch Release

```bash
manifest ship repo patch
# review preview
manifest ship repo patch -y
```

## Local Minor Release Prep

```bash
manifest ship repo minor --local -y
```

Use local apply when you want the version, changelog, docs, and commit locally but do not want tag, push, GitHub Release, or tap publication yet.

## Inspect A Built-In Recipe

```bash
manifest recipe list
manifest recipe explain manifest.builtin.ship.repo.patch
manifest ship repo patch --explain
```

## First Fleet

```bash
manifest init fleet
# review manifest.fleet.tsv
manifest init fleet
manifest status fleet
```

## Adopt An Existing Fleet

```bash
manifest plan fleet
manifest plan fleet --apply
# review manifest.fleet.plan.yaml
manifest reconcile fleet
manifest reconcile fleet --do
```

## Fleet Release

```bash
manifest ship fleet patch
manifest ship fleet patch -y
manifest ship fleet minor --local -y
```

## Pull Request

```bash
manifest pr create --draft
manifest pr checks --watch
manifest pr ready -y
manifest pr merge --squash -y
```

## Config Lookup

```bash
manifest config list
manifest config describe git.tag_prefix
manifest config set git.tag_prefix release-
manifest config unset git.tag_prefix
```

## Docs Site Generation

```bash
manifest config set docs.generate.site true
manifest config set docs.site.source_dir docs-site
manifest docs
```

Run the focused generator regression in a container:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

## Offline Or No-Cloud Release

```bash
manifest ship repo patch --local -y
MANIFEST_CLI_CLOUD_ENABLED=false manifest ship repo patch
```

Core release workflows are local-first. Cloud enriches optional paths but is not required for repo or fleet releases.
