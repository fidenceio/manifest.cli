# Contributing to Manifest CLI

Thanks for your interest in improving Manifest CLI. This document covers how to set
up a development environment, run the tests, and submit changes.

## Code of Conduct

Be respectful and constructive. Harassment or abusive behavior is not tolerated.

## Ground Rules

- **Tests are mandatory.** Every behavior change ships with bats coverage. The suite
  must be green before a change is merged.
- **Preview/apply is sacred.** Mutating code paths preview by default and only act on
  explicit `-y` / `--yes`. Never add a path that mutates without that contract, and
  never make `MANIFEST_CLI_AUTO_CONFIRM` authorize apply on its own — it only answers
  prompts *after* apply is selected.
- **No secrets in commits.** The pre-commit hook and CI gitleaks scan will reject
  token-shaped strings and private env files. Keep credentials out of fixtures.
- **Match the surrounding style.** Modules are sourced Bash libraries using namespaced
  `_manifest_*` helpers and the shared `log_*` output functions. Follow the idioms
  already in the file you are editing.

## Requirements

| Requirement | Version | Notes |
| ----------- | ------- | ----- |
| Bash | 5.0+ | Associative arrays and modern shell behavior; Apple's stock 3.2 is refused |
| git | Any supported release | |
| yq | 4.0+ (Mike Farah) | YAML config parsing |
| bats | 1.5+ | Test runner |
| Docker | Running engine | For the containerized test runner |
| shellcheck | Latest | Lint (also enforced in CI) |

## Development Setup

Clone the repo and run the CLI from source without installing globally:

```bash
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli

# Enable the secret-scanning pre-commit hook
git config core.hooksPath .git-hooks

# Run the CLI from source (the wrapper sources modules/core/manifest-core.sh)
./scripts/manifest-cli-wrapper.sh version
```

Do **not** install runtime dependencies on your host for validation — use the
containerized runner so your environment stays clean and reproducible.

## Running Tests

```bash
# Canonical: containerized (no host dependencies)
./scripts/run-tests-container.sh

# Host runner (requires bats/yq/bash 5+ locally)
./scripts/run-tests.sh

# A single file
bats tests/release_gate.bats
```

Tests run with a sandboxed `HOME` so they never touch your real `~/.manifest-cli`.
Preserve that — any new test that writes global state must set
`HOME="$BATS_TEST_TMPDIR"`.

Lint before pushing:

```bash
shellcheck modules/**/*.sh scripts/*.sh install-cli.sh
```

## Submitting Changes

This project uses a trunk-based flow. To propose a change:

1. Branch from `main`.
2. Make a focused change with tests; keep commits scoped to one concern.
3. Ensure `./scripts/run-tests.sh` is green and shellcheck is clean.
4. Open a pull request describing the *why*, the user-facing impact, and how you
   verified it. CI (tests + shellcheck + gitleaks) must pass.

Do not bump `VERSION`, edit `CHANGELOG.md`, or create tags in a PR — releases are cut
by `manifest ship`, which owns versioning, changelog, docs, tags, and the GitHub
Release as one transaction.

## Reporting Security Issues

Do not file security reports publicly. Follow [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
