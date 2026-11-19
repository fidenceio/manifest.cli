# Manifest CLI Installation

This document has two halves. You need only one of them.

- **To install the tool** and use it on your projects, read "Product Installation".
- **To work on Manifest itself**, read "Contributor Validation". You do not install
  Manifest's dependencies on your machine for that. Everything runs in a container.

## Product Installation

### Homebrew

Homebrew is the recommended route on macOS and Linux. A "tap" is a third-party source
that Homebrew can install from:

```bash
brew tap fidenceio/tap
brew install manifest
```

Homebrew installs what Manifest needs: Bash 5, yq, Git, coreutils and GNU sed. It also
sets up shell completions, which let you press Tab to complete Manifest's commands.

To upgrade later:

```bash
brew update
brew upgrade manifest
```

#### About Homebrew "trust"

Newer versions of Homebrew refuse to load a tap that you have not marked as trusted.
Manifest handles this for you in three places: the install script,
`manifest reinstall`, and the automatic self-upgrade that follows a release of Manifest
itself. Each one marks the formula as trusted. If Homebrew refuses to trust a single
formula because the tap uses a custom remote, Manifest trusts the whole tap instead.
Older versions of Homebrew have no `brew trust` command, and Manifest skips this step
for them.

Homebrew may warn that `fidenceio/tap` is untrusted, or an upgrade may leave you on the
old version without an error. In either case, trust the formula by hand:

```bash
brew trust --formula fidenceio/tap/manifest
```

If Homebrew replies that it cannot trust individual items because the tap uses a custom
remote, trust the tap:

```bash
brew trust fidenceio/tap
```

> **What trust does and does not protect you from.** Marking something as trusted only
> keeps a tap you already chose loadable. Homebrew trusts by *identity* ("this is the
> tap I picked"), not by *content*, and Manifest applies the trust again on every
> upgrade. So trust is **not** protection against a tap that has been compromised. If
> that is your concern, pin the formula revision you expect. Any change to the content
> then forces a new trust prompt that you have to read.

### Install Script

Use the install script when you do not want Homebrew.

**Do not pipe a remote script straight into a shell.** That runs code you have not
seen. Use the bootstrap script instead. It downloads one release archive, compares its
SHA-256 checksum with the published one, and runs the installer only from files that
passed the check:

```bash
curl -fsSLO https://raw.githubusercontent.com/fidenceio/manifest.cli/main/bootstrap.sh
# read bootstrap.sh, then run it:
bash bootstrap.sh                                            # newest published release
MANIFEST_CLI_INSTALL_VERSION=<release-tag> bash bootstrap.sh # or pin an exact release
```

For the strongest guarantee, also supply the checksum you expect. The install then
stops if anything differs:

```bash
MANIFEST_CLI_INSTALL_VERSION=<release-tag> \
MANIFEST_CLI_INSTALL_SHA256=<sha256-of-the-source-tarball> \
  bash bootstrap.sh
```

The checksum is the `sha256` value in the tap's formula file. That file is
`Formula/manifest.rb` in the `fidenceio/homebrew-tap` repository.

The installer checks the runtime requirements before it installs anything. It stops if
Bash 5, yq, Git, coreutils or a running Docker engine is missing. It keeps Manifest's
own state in `~/.manifest-cli/` and puts the `manifest` command in `~/.local/bin`.

## Verify Product Install

```bash
manifest --help
manifest doctor
manifest status
manifest config show
```

`manifest doctor` checks your dependencies, your configuration layers, and the state of
the repository you are in. `manifest status` changes nothing. It tells you what
Manifest would act on from your current directory. Run it before any release command.

## Contributor Validation

To work on this codebase, do not install its dependencies on your machine. Run the
tests in the container:

```bash
./scripts/run-tests-container.sh
```

To run one file and not the whole suite:

```bash
./scripts/run-tests-container.sh tests/command_surface_inventory.bats
```

The container supplies the tools that bats (the test runner) and the shell integration
tests need. Results therefore do not depend on what is installed on your machine. More
detail is in [tests/README.md](../tests/README.md).

## Runtime Requirements

| Dependency | Why it is needed |
| ---------- | ------- |
| Bash 5+ | Manifest uses associative arrays. Bash 3, which macOS still ships, does not have them. |
| Git | Reading repository state; commits, tags, pushes |
| yq v4+ | Reading the YAML configuration. It must be Mike Farah's `yq`. An unrelated tool has the same name. |
| coreutils | Consistent `date`, `stat`, and `timeout` behaviour across macOS and Linux |
| GNU sed | macOS only. Homebrew installs it with Manifest. The install script warns when it is missing but continues. |
| curl | API calls and the trusted-timestamp lookup. The install script warns when it is missing but continues. |
| Docker | The install script requires Docker with a running engine. The release gate that `manifest init` scaffolds runs your checks in a container, and so does this project's own test workflow. |
| gh | Optional. Needed for GitHub pull request and release commands. |

If a document and the code disagree about requirements, the code wins.
`modules/core/manifest-requirements.sh` is what runs the checks.

## Shell Completions

Homebrew sets up completions for you. The install script also installs them when it
finds the standard bash and zsh completion paths. If completions are missing, follow
the manual steps in [completions/README.md](../completions/README.md).

## Uninstall

See what would be removed:

```bash
manifest uninstall
```

Remove it:

```bash
manifest uninstall -y
```

Deleting your global configuration takes an extra confirmation on top of `-y`. This
protects `~/.manifest-cli/manifest.config.global.yaml` from being deleted by accident.
`--force` skips the extra confirmations, and it takes effect only together with `-y`.

## Troubleshooting

| Symptom | What to check |
| ------- | ----- |
| `manifest: command not found` | Is the `bin` directory under `brew --prefix`, or `~/.local/bin`, on your `PATH`? |
| Bash version error | Run `manifest doctor`. Homebrew installs Bash 5 with the formula. The Bash 3 that comes with macOS is too old. |
| YAML config error | Run `yq --version`. Confirm that it reports Mike Farah's yq, v4 or newer. |
| GitHub release or PR commands fail | Run `gh auth status`. You are probably not logged in. |
| A repo command acts on the wrong project | Run `manifest status` from the checkout you meant. Repo commands use your current directory, not a path argument. |
