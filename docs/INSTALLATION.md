# Manifest CLI Installation

This document separates product installation from repository development.

- Product users install the CLI on their machine.
- Contributors working in this repo validate through containers and do not install repo dependencies on the host.

## Product Installation

### Homebrew

Recommended for macOS and Linux users with Homebrew:

```bash
brew tap fidenceio/tap
brew install manifest
```

Homebrew installs the formula dependencies declared in the tap: Bash 5, yq, Git, and coreutils. It also installs shell completions.

Upgrade:

```bash
brew update
brew upgrade manifest
```

The install script, `manifest upgrade`, `manifest reinstall`, and the post-ship self-upgrade automatically trust the formula when Homebrew allows formula-level trust, then fall back to tap-level trust only when Homebrew rejects individual formula trust for a custom-remote tap. This keeps Homebrew loading Manifest once tap-trust is enforced (`HOMEBREW_REQUIRE_TAP_TRUST=1`, slated to become the default in a future Homebrew). Older Homebrew without `brew trust` skips this step. If Homebrew ever warns that `fidenceio/tap` is untrusted — or an upgrade silently stays on the old version — trust it manually:

```bash
brew trust --formula fidenceio/tap/manifest
```

If Homebrew responds that it cannot trust individual items because `fidenceio/tap` uses a custom remote, trust the tap instead:

```bash
brew trust fidenceio/tap
```

> **Security boundary:** auto-trust only keeps a formula/tap you already chose loadable once Homebrew starts ignoring untrusted taps. It trusts by Homebrew *identity*, not pinned *content*, and is re-applied on every upgrade — so it is **not** a defense against a compromised tap. To defend against that, pin an expected formula revision so a content change forces a fresh `brew trust` prompt.

### Install Script

Use the install script when Homebrew is not the desired distribution path. Do
not pipe a remote script straight into a shell — that executes unverified code
before you have seen it. Instead, use the verifying bootstrap, which downloads a
pinned release tarball, checks its sha256 against the published checksum, and
only then runs the installer from the verified tree:

```bash
curl -fsSLO https://raw.githubusercontent.com/fidenceio/manifest.cli/main/bootstrap.sh
# inspect bootstrap.sh, then run it:
bash bootstrap.sh                               # latest published tag
MANIFEST_CLI_INSTALL_VERSION=v55.2.1 bash bootstrap.sh      # pin an exact version
```

For the strongest guarantee, pin the expected digest as well — the install then
aborts on any mismatch:

```bash
MANIFEST_CLI_INSTALL_VERSION=v55.2.1 \
MANIFEST_CLI_INSTALL_SHA256=<sha256-of-the-source-tarball> \
  bash bootstrap.sh
```

The published per-release sha256 is the `sha256` value in the tap formula at
`fidenceio/homebrew-tap` (`Formula/manifest.rb`). The installer validates runtime
requirements before installing and writes Manifest runtime state under
`~/.manifest-cli/`.

## Verify Product Install

```bash
manifest --help
manifest doctor
manifest status
manifest config show
```

`manifest doctor` checks dependencies, config layers, and repository state. `manifest status` is read-only and reports what Manifest would target from the current directory.

## Contributor Validation

Do not install repo dependencies on the host to work on this codebase. Run tests through the containerized harness:

```bash
./scripts/run-tests-container.sh
```

Focused suite example:

```bash
./scripts/run-tests-container.sh tests/command_surface_inventory.bats
```

The container runner provides the toolchain needed for bats and shell integration tests. See [tests/README.md](../tests/README.md).

## Runtime Requirements

Manifest requires:

| Dependency | Purpose |
| ---------- | ------- |
| Bash 5+ | Shell runtime |
| Git | Repository operations |
| yq v4+ | YAML config parsing |
| coreutils | Portable date/stat/timeout behavior |
| curl | API and timestamp calls |
| Docker | Containerized validation and some workflows |
| gh | Optional GitHub PR and release operations |

The source of truth for runtime checks is `modules/core/manifest-requirements.sh`.

## Shell Completions

Homebrew installs completions automatically. Manual setup instructions live in [completions/README.md](../completions/README.md).

## Uninstall

Preview first:

```bash
manifest uninstall
```

Apply removal:

```bash
manifest uninstall -y
```

Global config removal requires additional confirmation. This prevents accidental deletion of `~/.manifest-cli/manifest.config.global.yaml`.

## Troubleshooting

| Symptom | Check |
| ------- | ----- |
| `manifest` not found | Confirm `brew --prefix` or `~/.local/bin` is on `PATH` |
| Bash version error | Run `manifest doctor`; Homebrew installs Bash 5 for the formula |
| YAML config error | Confirm `yq --version` reports Mike Farah yq v4+ |
| GitHub release or PR commands fail | Run `gh auth status` |
| Repo command targets the wrong path | Run `manifest status` from the intended Git checkout |
