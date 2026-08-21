# Manifest CLI

Manifest CLI runs your releases. It handles the whole chore — raising the version
number, writing the changelog, regenerating docs, tagging, pushing, publishing a
GitHub Release, opening pull requests — and it does the same job across many
repositories at once. Every command that changes something shows you a plan first and
waits for you to say yes.

[![tests](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml/badge.svg)](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml)

<!-- Keep the version line below FIRST among any `x.y.z` in backticks. At release
     time Manifest finds the first backticked version string in this file and
     replaces every copy of it (manifest-documentation.sh, update_readme_version).
     Adding another backticked bare version above this line would retarget that
     rewrite at the wrong string. -->
**Version:** `59.4.1`
**Platforms:** macOS, Linux
**Primary interface:** `manifest <verb> <scope> [options]`

## Why It Exists

When you work with an AI assistant, changes pile up fast. Shipping them safely is the
slow part. Manifest turns releasing into the same short, repeatable path every time:

- Look at what state things are actually in.
- See exactly what would change, locally and on GitHub.
- Change nothing until you add `-y`.
- Keep the version number, changelog, generated docs, tag, and GitHub Release telling
  the same story.
- Use the identical commands whether you have one repository or thirty.

## The One Rule Worth Knowing

**Nothing that changes anything happens without `-y`.**

Run a command bare and Manifest prints a plan and stops. Add `-y` and it does the work.

```bash
manifest ship repo patch        # shows the plan, changes nothing
manifest ship repo patch -y     # actually releases
manifest ship repo patch --local -y
```

`--dry-run` is a longer way to spell "just show me the plan". `--local -y` does the
release work on your own machine only — it skips the tag, the push, the GitHub Release,
and the Homebrew publish, so nothing becomes public.

There is an environment variable, `MANIFEST_CLI_AUTO_CONFIRM=1`, that answers follow-up
prompts for you. It is **not** a substitute for `-y`: it cannot start an apply, only
answer questions once you already asked for one. This matters in CI, where a variable
set in the environment must never be able to trigger a release on its own.

## Which Version File Manifest Owns

Manifest treats a plain file named `VERSION` as the one true version for a release.
That file is what it reads and writes.

It deliberately leaves package-manager files alone — `package.json`,
`package-lock.json`, `pyproject.toml`, `Cargo.toml`, lockfiles — unless you ask for
them. This is so Manifest can never surprise you by editing a file your build depends
on.

If you *do* want other files to follow along, `version.sync` is an opt-in list of them.
Leave it unset and `manifest ship repo patch -y` touches only `VERSION`. Set it and
Manifest updates a top-level `version` field in JSON, TOML, or YAML files. It skips
anything it cannot handle — a missing file, or a version buried deeper than the top
level — and never creates a file that was not already there.

Separately, Manifest keeps a catalog of places version numbers commonly hide:
[modules/catalog/version-handlers.tsv](modules/catalog/version-handlers.tsv). It uses
that only to **tell you** about them in `manifest status`, `manifest doctor`,
`manifest status fleet`, and fleet release previews. It reads; it does not write, and it
never blocks a script. Tune what gets reported with `version.surfaces.enabled`,
`version.surfaces.catalog`, `version.surfaces.scan_depth`, and
`version.surfaces.notification_mode` (`summary`, `list`, or `off`).

There is a config key `files.version` for naming a different canonical file. The
detection side honours it, but repo and fleet releases still write `VERSION` today —
so treat that key as not yet finished.

For Manifest's own releases only, the Homebrew formula is published after the GitHub
Release exists. That is a distribution update and must not add a commit back to this
repository. Before reporting success, a release checks two things: that your working
copy is clean, and that nothing has been committed on top of the release you just
pushed.

## Install

Normal use — install from the Homebrew tap (a "tap" is a third-party Homebrew source):

```bash
brew tap fidenceio/tap
brew install manifest
```

Prefer the install script? Download it, read it, then run it. Manifest does not ask you
to pipe code off the internet straight into a shell:

```bash
curl -fsSLO https://raw.githubusercontent.com/fidenceio/manifest.cli/main/bootstrap.sh
# read bootstrap.sh, then:
bash bootstrap.sh                                      # newest published release
MANIFEST_CLI_INSTALL_VERSION=v59.3.0 bash bootstrap.sh # or pin an exact one
```

`bootstrap.sh` downloads the release archive, checks its SHA-256 checksum against the
published one (or against `MANIFEST_CLI_INSTALL_SHA256` if you supply your own), and
only runs the installer if that check passes.

Working *on* Manifest rather than with it? Don't install its dependencies on your
machine — use the container:

```bash
./scripts/run-tests-container.sh
```

More detail: [docs/INSTALLATION.md](docs/INSTALLATION.md).

## Runtime Requirements

| Requirement | Version | Why |
| ----------- | ------- | --- |
| Bash | 5.0+ | Needs associative arrays, which Bash 3 (still shipped by macOS) lacks |
| yq | 4.0+ (Mike Farah's) | Reads the YAML config. Note there is another, unrelated `yq` — this is not it |
| Git | Any current release | Status, tags, commits, pushes |
| coreutils | Any | macOS only, for a `timeout` command that behaves as expected |
| Docker | Running | Only for the containerized development and test workflow |

## Your First Release

New to Manifest? `manifest first` looks at where you are — one repository, or a folder
containing several — tells you what is already set up, and proposes the rest as a plan.
It writes nothing until you add `-y`:

```bash
cd your-project

manifest first                  # look and propose; changes nothing
manifest first -y               # do the proposed setup (recorded in the audit log)
```

Prefer to drive each step yourself:

```bash
manifest init repo              # show which files are missing
manifest init repo -y           # create VERSION, CHANGELOG.md, docs/, ignore files
manifest init repo --create-repo-private       # also show the GitHub repo it would create
manifest init repo --create-repo-private -y    # create it; github.owner picks the org or user

manifest prep repo              # show remote and config preparation
manifest prep repo -y           # do it

manifest ship repo patch        # show the release
manifest ship repo patch -y     # publish it
```

Checks that never change anything:

```bash
manifest status
manifest doctor
manifest config list
```

## Releasing Many Repositories At Once

A **fleet** is a folder holding several independent Git repositories that you want to
release together. Two files describe it: `manifest.fleet.config.yaml` for the settings
and `manifest.fleet.tsv` for the list of members and which ones are selected.

```bash
manifest init fleet             # scan the folder, or read an existing fleet TSV
manifest init fleet --create-repo-private      # show which members have no remote yet
manifest status fleet           # inspect the selected repositories
manifest ship fleet patch       # show which members would be released
manifest ship fleet patch -y    # release them
```

**A fleet release skips members with nothing to release.** Being release-enabled only
makes a member *eligible*. It is actually bumped when one of two things is true: its
working copy has release-worthy changes, or its latest commit is not the one its current
`VERSION` tag points at.

Adopting an existing folder into a fleet, or repairing one, is also plan-first:

```bash
manifest plan fleet             # write a plan describing what adoption would do
manifest plan fleet --apply
manifest reconcile fleet        # show the changes that plan implies
manifest reconcile fleet --do
```

More detail: [docs/FLEET_DESIGN_SPEC.md](docs/FLEET_DESIGN_SPEC.md).

## Command Model

Commands read as `manifest <verb> <scope>`, where scope is usually `repo` or `fleet`.

| Area | Commands |
| ---- | -------- |
| Setup | `manifest first`, `manifest config`, `manifest init repo`, `manifest init fleet` |
| Preparation | `manifest prep repo`, `manifest prep fleet` |
| Refresh | `manifest refresh repo`, `manifest update fleet` (once called `refresh fleet`) |
| Release | `manifest ship repo <type>`, `manifest ship fleet <type>` |
| Diagnostics | `manifest status`, `manifest doctor`, `manifest security` |
| Pull requests | `manifest pr create`, `manifest pr checks`, `manifest pr ready`, `manifest pr merge`, `manifest pr update` |
| Recipes | `manifest recipe list`, `manifest recipe show`, `manifest recipe explain` |

Release types are `patch`, `minor`, `major`, and `revision`. The first three follow the
usual semantic-versioning meanings: `patch` for fixes, `minor` for additions, `major`
for breaking changes. `revision` re-cuts a release without claiming it is a new one.

Complete grammar: [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md).

## Configuration

Settings live in YAML and stack in layers. Later layers win:

1. Manifest's built-in defaults
2. Your personal global config
3. A fleet-wide layer, if this repo belongs to a fleet
4. The project's config
5. A local, private config that you do not commit
6. `MANIFEST_CLI_*` environment variables

Every setting has a matching `MANIFEST_CLI_*` environment variable, so anything you can
put in a file you can also set for a single command. To find out what a setting is
currently doing, and *which layer decided that*, ask:

```bash
manifest config describe <key>
```

Full explanation: [docs/USER_GUIDE.md#configuration](docs/USER_GUIDE.md#configuration).
Worked example file: [examples/manifest.config.yaml.example](examples/manifest.config.yaml.example).

## Documentation Map

| Document | Purpose |
| -------- | ------- |
| [docs/INDEX.md](docs/INDEX.md) | Index, organised by what you are trying to do |
| [docs/USER_GUIDE.md](docs/USER_GUIDE.md) | Day-to-day workflows and how the tool thinks |
| [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md) | Every command, flag, and exit code |
| [docs/EXAMPLES.md](docs/EXAMPLES.md) | Copy-and-paste recipes |
| [docs/INSTALLATION.md](docs/INSTALLATION.md) | Installing, upgrading, removing; and contributor setup |
| [docs/FLEET_DESIGN_SPEC.md](docs/FLEET_DESIGN_SPEC.md) | How fleets are designed and named |
| [docs/CLI_TRANSACTION_MAP.md](docs/CLI_TRANSACTION_MAP.md) | Exactly what a release touches, in order |
| [modules/catalog/version-handlers.tsv](modules/catalog/version-handlers.tsv) | Places version numbers commonly hide |
| [tests/README.md](tests/README.md) | Running the tests in a container |

## Optional Cloud

Manifest works fully without Manifest Cloud. Cloud plugins can add nicer release notes,
queue and policy behaviour, MCP reports, and agent workflows. If a Cloud plugin is not
installed, Manifest tells you how to get it and carries on — a missing plugin never
blocks an ordinary release.

Cloud repository: [fidenceio.manifest.cloud](https://github.com/fidenceio/manifest.cloud)

## Project

| Document | Purpose |
| -------- | ------- |
| [LICENSE](LICENSE) | Apache License 2.0 |
| [SECURITY.md](SECURITY.md) | Security policy and how to report a vulnerability privately |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, tests, and how to contribute |

Licensed under the [Apache License 2.0](LICENSE).
