# Manifest CLI

Manifest CLI runs your releases. It does the whole job: it raises the version number,
writes the changelog, regenerates the docs, creates the tag, pushes, and publishes a
GitHub Release. It can also open pull requests. It does the same job for one repository
or for many at once. Every command that changes something shows you a plan first and
waits for you to say yes.

[![tests](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml/badge.svg)](https://github.com/fidenceio/manifest.cli/actions/workflows/test.yml)

**Platforms:** macOS, Linux
**Primary interface:** `manifest <verb> <scope> [options]`

## Why It Exists

When you work with an AI assistant, changes pile up fast. Releasing them safely is the
slow part. Manifest turns a release into the same short path every time:

- Look at the real state of things.
- See exactly what would change, on your machine and on GitHub.
- Change nothing until you add `-y`.
- Keep the version number, the changelog, the generated docs, the tag, and the GitHub
  Release in agreement.
- Use the same commands whether you have one repository or thirty.

## The One Rule Worth Knowing

**Nothing that changes anything happens without `-y`.**

Run a command without `-y`, and Manifest prints a plan and stops. Add `-y`, and it does
the work.

```bash
manifest ship repo patch        # shows the plan, changes nothing
manifest ship repo patch -y     # actually releases
manifest ship repo patch --local -y
```

`--dry-run` is a longer way to say "just show me the plan". `--local -y` does the
release work on your own machine only. It still commits, but it skips the tag, the
push, the GitHub Release, and the Homebrew publish, so nothing becomes public.

There is also an environment variable, `MANIFEST_CLI_AUTO_CONFIRM=1`. It is **not** a
substitute for `-y`, and it cannot start an apply. It does two narrow things. It lets
an apply continue when the checkout is not on a branch or the repository has no
`origin` remote. And it lets Manifest proceed without pausing for a confirmation
question, such as the one before it writes your global config. This matters in CI (an
automated build pipeline), where a variable set in the environment must never be able
to trigger a release on its own.

## Which Version File Manifest Owns

Manifest treats a plain file named `VERSION` as the one true version for a release. It
reads and writes that file.

It leaves package-manager files alone unless you ask for them. That covers
`package.json`, `package-lock.json`, `pyproject.toml`, `Cargo.toml`, and lockfiles. So
Manifest never surprises you by editing a file your build depends on.

If you *do* want other files to follow `VERSION`, list them in `version.sync`. Leave it
unset, and `manifest ship repo patch -y` touches only `VERSION`. Set it, and Manifest
also updates a top-level `version` field in the JSON, TOML, or YAML files you listed.
It skips what it cannot handle: a missing file, or a version nested deeper than the top
level. It never creates a file that was not already there.

Separately, Manifest keeps a catalog of the places where version numbers are commonly
found: [modules/catalog/version-handlers.tsv](modules/catalog/version-handlers.tsv). It
uses the catalog only to **tell you** about those files, in `manifest status`,
`manifest doctor`, `manifest status fleet`, and fleet release previews. It reads them.
It does not write them, and it never blocks a script. Four settings control what is
reported: `version.surfaces.enabled`, `version.surfaces.catalog`,
`version.surfaces.scan_depth`, and `version.surfaces.notification_mode` (`summary`,
`list`, or `off`).

A config key named `files.version` exists for naming a different canonical file.
Detection honours it, but repo and fleet releases write `VERSION` regardless. Treat
that key as incomplete, and keep your version in `VERSION`.

For Manifest's own releases only, the Homebrew formula is published after the GitHub
Release exists. That update goes to the Homebrew tap and adds no commit to this
repository.

Before a release reports success, it checks two things. Your working copy must be
clean, apart from files the release already told you it left out. And nothing may have
been committed on top of the release it just pushed.

## Install

For normal use, install from the Homebrew tap. (A "tap" is a third-party source of
Homebrew packages.)

```bash
brew tap fidenceio/tap
brew install manifest
```

If you prefer the install script, download it, read it, and then run it. Manifest does
not ask you to pipe code from the internet straight into a shell:

```bash
curl -fsSLO https://raw.githubusercontent.com/fidenceio/manifest.cli/main/bootstrap.sh
# read bootstrap.sh, then:
bash bootstrap.sh                                            # newest published release
MANIFEST_CLI_INSTALL_VERSION=<release-tag> bash bootstrap.sh # or pin an exact one
```

`bootstrap.sh` downloads the release archive and checks its SHA-256 checksum. It
compares the checksum against the published one, or against
`MANIFEST_CLI_INSTALL_SHA256` if you supply your own. It runs the installer only if
that check passes.

If you are working *on* Manifest, not just using it, do not install its dependencies on
your machine. Use the container:

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
| Docker | Running | Needed for the release check that `manifest init` generates, which runs in a container, and for developing and testing Manifest itself |

## Your First Release

If you are new to Manifest, start with `manifest init`. It looks at where you are: one
repository, or a folder that contains several. It tells you what is already set up and
proposes the rest as a plan. It writes nothing until you add `-y`:

```bash
cd your-project

manifest init                  # look and propose; changes nothing
manifest init -y               # do the proposed setup (recorded in the audit log)
```

If the repository has no `origin` remote, the proposed setup creates a **private**
GitHub repository for it. To avoid that, connect an existing remote with
`--remote <url>`, or pass `--no-connect` to create local files only.

To run each step yourself:

```bash
manifest init repo              # preview Git, origin, scaffold and readiness
manifest init repo -y           # prepare and verify; no release or push
manifest init repo --create-repo-private       # also show the GitHub repo it would create
manifest init repo --create-repo-private -y    # create it; github.owner picks the org or user

manifest init repo --remote <url>          # connect an existing remote instead
manifest init repo --no-connect -y         # scaffold only; readiness not verified

manifest ship repo patch        # show the release
manifest ship repo patch -y     # publish it
```

These checks never change anything:

```bash
manifest status
manifest doctor
manifest config list
```

If a release stops partway, run the same `manifest ship repo <type>` command again. Its
plan shows the release as unfinished, and `-y` finishes it without raising the version.
See [When A Release Goes Wrong](docs/USER_GUIDE.md#when-a-release-goes-wrong).

## Releasing Many Repositories At Once

A **fleet** is a folder that holds several independent Git repositories that you want
to release together. Two files describe it. `manifest.fleet.config.yaml` holds the
settings. `manifest.fleet.tsv` lists the members and marks which ones are selected.

```bash
manifest init fleet             # scan the folder, or read an existing fleet TSV
manifest init fleet --create-repo-private      # also show the GitHub repos it would create
manifest status fleet           # inspect the selected repositories
manifest ship fleet patch       # show which members would be released
manifest ship fleet patch -y    # release members, then commit + push the manager
manifest ship fleet manager -y  # commit + push the fleet coordination root only
```

The **manager** is the fleet's coordination root: the small repository at the top of
the fleet that holds the two files above. A fleet release commits and pushes the
manager as well, even when every member is skipped or fleet versioning is turned off.
`ship fleet manager` runs that step alone.

**A fleet release skips members with nothing to release.** Turning releases on for a
member only makes it *eligible*. Manifest releases it when one of two things is true:
its working copy has uncommitted changes, or it has commits after the one its current
`VERSION` tag points at.

Adopting an existing folder into a fleet, or repairing a fleet, also starts with a
plan:

```bash
manifest plan fleet             # preview a plan of what adoption would do
manifest plan fleet -y          # write that plan to a file
manifest reconcile fleet        # show the changes the plan describes
manifest reconcile fleet -y     # make those changes
```

More detail: [docs/FLEET_DESIGN_SPEC.md](docs/FLEET_DESIGN_SPEC.md).

## Command Model

Commands have the form `manifest <verb> <scope>`. The scope is usually `repo` or
`fleet`.

| Area | Commands |
| ---- | -------- |
| Setup | `manifest init`, `manifest init repo`, `manifest init fleet`, `manifest config` |
| Connect remotes | `manifest init repo --connect`, `manifest init fleet --connect` |
| Membership | `manifest discover fleet`, `manifest update fleet` |
| Adopt or repair a fleet | `manifest plan fleet`, `manifest reconcile fleet` |
| Release | `manifest ship repo <type>`, `manifest ship fleet <type>`, `manifest ship fleet manager` |
| Look at an earlier release | `manifest revert repo`, `manifest revert fleet` |
| Diagnostics | `manifest status`, `manifest doctor`, `manifest security` |
| Documentation | `manifest docs`, `manifest docs fleet` |
| Pull requests | `manifest pr create`, `manifest pr checks`, `manifest pr ready`, `manifest pr merge`, `manifest pr update` |
| Recipes | `manifest recipe list`, `manifest recipe show`, `manifest recipe explain` |

The release types are `patch`, `minor`, `major`, and `revision`. The first three have
their usual semantic-versioning meanings: `patch` for fixes, `minor` for additions, and
`major` for breaking changes. `revision` adds or raises a fourth number (`1.2.3`
becomes `1.2.3.1`). Use it to re-cut a version you have already released.

Complete grammar: [docs/COMMAND_REFERENCE.md](docs/COMMAND_REFERENCE.md).

## Configuration

Settings are written in YAML files and stack in layers. A later layer in this list wins
over an earlier one:

1. Manifest's built-in defaults
2. Your personal global config
3. A fleet-wide layer, if this repository belongs to a fleet
4. The project's config
5. A local, private config that you do not commit
6. `MANIFEST_CLI_*` environment variables

Every setting has a matching `MANIFEST_CLI_*` environment variable. So anything you can
put in a file, you can also set for a single command. To find out what value a setting
has now, and *which layer decided it*, ask:

```bash
manifest config describe <key>
```

One exception protects you. A setting that names a program for Manifest to run is
refused when it comes from a committed config file. The User Guide explains why.

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

Manifest works fully without Manifest Cloud. Cloud plugins can add richer release
notes, queue and policy behaviour, MCP reports, and agent workflows. If a Cloud plugin
is not installed, Manifest tells you how to get it and carries on. A missing plugin
never blocks an ordinary release.

Cloud repository: `fidenceio/fidence.service.manifest` (private)

## Project

| Document | Purpose |
| -------- | ------- |
| [LICENSE](LICENSE) | Apache License 2.0 |
| [SECURITY.md](SECURITY.md) | Security policy and how to report a vulnerability privately |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, tests, and how to contribute |

Licensed under the [Apache License 2.0](LICENSE).
