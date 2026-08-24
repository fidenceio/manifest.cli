# Manifest CLI Installation

This document has two halves, and you only need one of them:

- **Installing the tool** to use it on your projects — read "Product Installation".
- **Working on Manifest itself** — read "Contributor Validation". You do not install
  Manifest's dependencies on your machine for that; everything runs in a container.

## Product Installation

### Homebrew

The recommended route on macOS and Linux. A "tap" is just a third-party source
Homebrew can install from:

```bash
brew tap fidenceio/tap
brew install manifest
```

Homebrew pulls in what Manifest needs — Bash 5, yq, Git, coreutils — and sets up shell
completions (tab-completion for Manifest's commands).

To upgrade later:

```bash
brew update
brew upgrade manifest
```

#### About Homebrew "trust"

Newer Homebrew versions will refuse to load a tap you have not marked as trusted.
Manifest handles this for you: the install script, `manifest upgrade`,
`manifest reinstall`, and the automatic self-upgrade after a release all mark the
formula trusted, falling back to trusting the whole tap only if Homebrew rejects
trusting a single formula from a custom-remote tap. Older Homebrew versions have no
`brew trust` command and skip this entirely.

If Homebrew ever warns that `fidenceio/tap` is untrusted — or an upgrade quietly leaves
you on the old version — do it by hand:

```bash
brew trust --formula fidenceio/tap/manifest
```

If Homebrew replies that it cannot trust individual items because the tap uses a custom
remote, trust the tap:

```bash
brew trust fidenceio/tap
```

> **What trust does and does not protect you from.** Marking something trusted only
> keeps a tap you already chose loadable. It trusts by Homebrew *identity* — "this is
> the tap I picked" — not by *content*, and it is re-applied on every upgrade. So it is
> **not** protection against a tap that has been compromised. If that is your concern,
> pin an expected formula revision, so any content change forces a fresh trust prompt
> that you have to look at.

### Install Script

Use this when Homebrew is not what you want.

**Do not pipe a remote script straight into a shell.** Doing so runs code you have not
seen. Instead use the bootstrap script, which downloads a specific release archive,
checks its SHA-256 checksum against the published one, and only then runs the installer
from the verified files:

```bash
curl -fsSLO https://raw.githubusercontent.com/fidenceio/manifest.cli/main/bootstrap.sh
# read bootstrap.sh, then run it:
bash bootstrap.sh                                            # newest published release
MANIFEST_CLI_INSTALL_VERSION=<release-tag> bash bootstrap.sh # or pin an exact release
```

For the strongest guarantee, supply the checksum you expect as well. The install then
stops if anything differs:

```bash
MANIFEST_CLI_INSTALL_VERSION=<release-tag> \
MANIFEST_CLI_INSTALL_SHA256=<sha256-of-the-source-tarball> \
  bash bootstrap.sh
```

Where do you get that checksum? It is the `sha256` value in the tap's formula file, at
`fidenceio/homebrew-tap` in `Formula/manifest.rb`.

The installer checks your runtime requirements before installing anything, and keeps
Manifest's own state in `~/.manifest-cli/`.

## Verify Product Install

```bash
manifest --help
manifest doctor
manifest status
manifest config show
```

`manifest doctor` checks your dependencies, your configuration layers, and the state of
the repository you are in. `manifest status` changes nothing and tells you what Manifest
would act on from where you are standing — a good habit before any release command.

## Contributor Validation

To work on this codebase, do not install its dependencies on your machine. Run the
tests through the container:

```bash
./scripts/run-tests-container.sh
```

To run a single file rather than the whole suite:

```bash
./scripts/run-tests-container.sh tests/command_surface_inventory.bats
```

The container supplies the toolchain that bats and the shell integration tests need, so
results do not depend on what happens to be installed on your machine. More detail:
[tests/README.md](../tests/README.md).

## Runtime Requirements

| Dependency | Why it is needed |
| ---------- | ------- |
| Bash 5+ | Manifest uses associative arrays, which Bash 3 — still what macOS ships — does not have |
| Git | Reading repository state; commits, tags, pushes |
| yq v4+ | Reading the YAML configuration. Must be Mike Farah's `yq`; there is an unrelated tool with the same name |
| coreutils | Consistent `date`, `stat`, and `timeout` behaviour across macOS and Linux |
| curl | API calls and the trusted-timestamp lookup |
| Docker | The containerized test workflow, and a few other flows |
| gh | Optional. Needed for GitHub pull request and release commands |

If a document and the code ever disagree about requirements, the code wins:
`modules/core/manifest-requirements.sh` is what actually runs the checks.

## Shell Completions

Homebrew sets these up for you. If you installed another way, the manual steps are in
[completions/README.md](../completions/README.md).

## Uninstall

See what would be removed:

```bash
manifest uninstall
```

Actually remove it:

```bash
manifest uninstall -y
```

Deleting your global configuration takes an extra confirmation on top of `-y`, so
`~/.manifest-cli/manifest.config.global.yaml` cannot go by accident.

## Troubleshooting

| Symptom | What to check |
| ------- | ----- |
| `manifest: command not found` | Is `brew --prefix`'s `bin`, or `~/.local/bin`, on your `PATH`? |
| Bash version error | Run `manifest doctor`. Homebrew installs Bash 5 alongside the formula; macOS's built-in Bash 3 is too old |
| YAML config error | Run `yq --version` and confirm it reports Mike Farah's yq, v4 or newer |
| GitHub release or PR commands fail | Run `gh auth status` — you are probably not logged in |
| A repo command acts on the wrong project | Run `manifest status` from the checkout you meant. Repo commands use your current directory, not a path argument |
