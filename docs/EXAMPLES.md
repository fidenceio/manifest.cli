# Manifest CLI Examples

Copy-and-paste recipes for common jobs.

An example that changes something only shows a *plan* unless it includes `-y` or
`--yes`. Some recipes show the same command twice: once without `-y` and once with it.
That is the intended rhythm. Read the plan, then apply it.

## New Repository

```bash
cd my-project
manifest doctor          # are my tools and config in good order?
manifest init repo       # what would be set up?
manifest init repo -y    # set it up and run the release check
manifest status          # what would Manifest act on now?
```

`manifest init repo -y` creates the starter files and connects the `origin` remote. If
the repository has no `origin`, it creates a **private** GitHub repository for it. To
avoid that, pass `--remote <url>` to connect an existing remote, or `--no-connect` to
create local files only.

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
regenerated, and the commit made, but nothing public yet. It skips the tag, the push,
the GitHub Release, and the Homebrew publish.

## Finish A Release That Stopped Partway

Run the same release command again. There is no separate recovery command.

```bash
manifest ship repo patch      # the plan shows "Unfinished release" and what remains
manifest ship repo patch -y   # finishes it; the version does not change
manifest ship repo patch      # now the ordinary plan for the next release
```

To leave the unfinished release as it is and cut the next one, add `--force-bump`.
`--local` cannot finish a release, because finishing means pushing.

## Leave Package Files Alone

This is the default. Manifest writes `VERSION` and nothing else:

```bash
manifest ship repo patch
# with version.sync unset, the plan shows VERSION only
```

To have other files follow the version, list them explicitly:

```bash
manifest config set version.sync package.json,pyproject.toml,Chart.yaml -y
manifest ship repo patch
```

Manifest updates a `version` field only at the **top level** of a JSON, TOML, or YAML
file. Lockfiles such as `package-lock.json` stay untouched unless you name them. Even
then, Manifest writes only a top-level `version`.

To hear more about other files that carry a version, which Manifest noticed but did not
change:

```bash
manifest config set version.surfaces.notification_mode list -y
manifest status
manifest doctor
```

## Inspect A Built-In Recipe

A "recipe" is a named description of what a command does. You can read it before you
run the command.

```bash
manifest recipe list
manifest recipe explain manifest.builtin.ship.repo.patch
manifest ship repo patch --explain
```

## First Fleet

`manifest init fleet` is run twice on purpose. The first run writes the member list for
you to review. The second run acts on your edits.

```bash
manifest init fleet
# open manifest.fleet.tsv and choose which repos are selected
manifest init fleet
manifest status fleet
```

## Adopt An Existing Folder Of Repos

```bash
manifest plan fleet
manifest plan fleet -y
# read manifest.fleet.plan.yaml
manifest reconcile fleet
manifest reconcile fleet -y
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
manifest pr create --draft       # preview
manifest pr create --draft -y    # open the draft pull request
manifest pr checks --watch
manifest pr ready -y
manifest pr merge --squash -y
```

## Look Up A Setting

```bash
manifest config list
manifest config describe git.tag_prefix   # value, which layer set it, and its env var
manifest config set git.tag_prefix release-      # preview
manifest config set git.tag_prefix release- -y   # write it
manifest config unset git.tag_prefix -y
```

`describe` is the command to use when a setting is not doing what you expect. It shows
every layer, so you can see what overrides what.

## Documentation Website

The website is on by default. Manifest writes its source whenever it generates
documentation:

```bash
manifest docs       # preview
manifest docs -y    # generate
```

To turn the website off for a repository:

```bash
manifest config set --layer project docs.generate.site false -y
```

The site's source files go in the `docs-site` folder. To use a different folder, set
`docs.site.source_dir`.

To run only the generator's tests, in a container:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
```

## Releasing Without Manifest Cloud

Nothing extra is required. Manifest is local-first: repo and fleet releases work fully
without Cloud. If a Cloud plugin is absent, Manifest prints installation guidance and
carries on. It does not fail.

```bash
manifest ship repo patch --local -y   # stays entirely on your machine
manifest ship repo patch -y           # also fine with no Cloud installed
```

A `cloud.skip` setting exists, but **no code reads it**. Setting it changes nothing. Do
not rely on it to turn Cloud off. Cloud is off whenever its plugins are not installed.
