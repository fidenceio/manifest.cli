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

The install script and `manifest upgrade` automatically trust the formula (narrow, formula-only) so Homebrew keeps loading it once tap-trust is enforced (`HOMEBREW_REQUIRE_TAP_TRUST=1`, slated to become the default in a future Homebrew). Older Homebrew without `brew trust` skips this step. If Homebrew ever warns that `fidenceio/tap` is untrusted — or an upgrade silently stays on the old version — trust it manually:

```bash
brew trust --formula fidenceio/tap/manifest
```

### Install Script

Use the install script when Homebrew is not the desired distribution path:

```bash
curl -fsSL https://raw.githubusercontent.com/fidenceio/manifest.cli/main/install-cli.sh | bash
```

The script validates runtime requirements before installing and writes Manifest runtime state under `~/.manifest-cli/`.

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
