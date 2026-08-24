# Manifest CLI Examples

Copy-and-paste recipes for common jobs.

Every example that changes something only *plans* unless it includes `-y` or `--yes`.
Where a recipe shows the same command twice — once bare, once with `-y` — that is the
intended rhythm: read the plan, then apply it.

## New Repository

```bash
cd my-project
manifest doctor          # are my dependencies and config sane?
manifest init repo       # what files would be created?
manifest init repo -y    # create them
manifest status          # what would Manifest act on now?
```

## Patch Release

```bash
manifest ship repo patch
# read the plan
manifest ship repo patch -y
```

## Release Locally, Publish Later

```bash
manifest ship repo minor --local -y
```

Use `--local` when you want the version raised, the changelog written, the docs
regenerated, and the commit made — but nothing public yet. It skips the tag, the push,
the GitHub Release, and the Homebrew publish.

## Leave Package Files Alone

This is the default. Manifest writes `VERSION` and nothing else:

```bash
manifest ship repo patch
# with version.sync unset, the plan shows VERSION only
```

To have other files follow the version, list them explicitly:

```bash
manifest config set version.sync package.json,pyproject.toml,Chart.yaml
manifest ship repo patch
```

Manifest updates a `version` field only at the **top level** of a JSON, TOML, or YAML
file. Lockfiles such as `package-lock.json` stay untouched unless you name them — and
even then, only a top-level `version` is written.

To hear more about other version-bearing files Manifest noticed but did not change:

```bash
manifest config set version.surfaces.notification_mode list
manifest status
manifest doctor
```

## Inspect A Built-In Recipe

A "recipe" is a named, inspectable description of what a command does.

```bash
manifest recipe list
manifest recipe explain manifest.builtin.ship.repo.patch
manifest ship repo patch --explain
```

## First Fleet

Note that `manifest init fleet` is run twice on purpose. The first run writes the member
list for you to review; the second acts on your edits.

```bash
manifest init fleet
# open manifest.fleet.tsv and choose which repos are selected
manifest init fleet
manifest status fleet
```

## Adopt An Existing Folder Of Repos

```bash
manifest plan fleet
manifest plan fleet --apply
# read manifest.fleet.plan.yaml
manifest reconcile fleet
manifest reconcile fleet --do
```

## Fleet Release

```bash
manifest ship fleet patch
manifest ship fleet patch -y
manifest ship fleet minor --local -y
```

Members with nothing to release are skipped and listed, so a short plan is normal.

## Pull Request

```bash
manifest pr create --draft
manifest pr checks --watch
manifest pr ready -y
manifest pr merge --squash -y
```

## Look Up A Setting

```bash
manifest config list
manifest config describe git.tag_prefix   # value, which layer set it, and its env var
manifest config set git.tag_prefix release-
manifest config unset git.tag_prefix
```

`describe` is the one to reach for when a setting is not doing what you expect — it
shows every layer, so you can see what is overriding what.

## Documentation Website

Off by default; two settings turn it on:

```bash
manifest config set docs.generate.site true
manifest config set docs.site.source_dir docs-site
manifest docs
```

To run just the generator's tests, in a container:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

## Releasing Without Manifest Cloud

Nothing extra is required. Manifest is local-first: repo and fleet releases work fully
without Cloud, and if a Cloud plugin is absent, Manifest prints installation guidance
and carries on rather than failing.

```bash
manifest ship repo patch --local -y   # stays entirely on your machine
manifest ship repo patch -y           # also fine with no Cloud installed
```

There is a `cloud.skip` setting listed in the configuration map, but **no code reads it
today** — setting it changes nothing. Do not rely on it to disable Cloud; simply not
installing the plugins is what disables Cloud. (Tracked as part of the dead-config-key
sweep in [TRACKER.md](TRACKER.md), item §9.)
