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

## Two audiences: this repository and installed copies

This repository is the **canonical Manifest CLI source**. Everything in it serves one
of two audiences, and most mistakes here come from serving one while thinking about
the other.

- **This repository** — one checkout, one maintainer, always at `HEAD`. It builds,
  tests and releases the CLI.
- **Installed copies** — the released CLI running on other people's machines, against
  repositories this project never sees, at whatever version each person last upgraded
  to. Nobody here can inspect them, patch them, or know what state they are in.

`manifest_is_canonical_repo` (in `modules/core/manifest-shared-functions.sh`) is how the
code tells them apart: by the origin slug (`fidenceio/manifest.cli`, or
`release.canonical_repo_slugs`), and then by structure: any checkout that carries the
installer, the wrapper, the formula template and `modules/` passes whatever its origin,
which is how a fork is recognised. So "this repository" below means this repository and
forks of it. Never identify it by filesystem path or folder name.

### What reaches an installed copy

| Install route | What lands on the user's disk | What runs |
| --- | --- | --- |
| Homebrew formula | every top-level file and folder that is not a dot-entry: `modules/`, `scripts/`, `docs/` (including `docs/TRACKER.md` and `docs/zArchive/`), `tests/`, `examples/`, `formula/`, `robots.txt`, … | `modules/` through the wrapper |
| `install-cli.sh` | `modules/`, `docs/`, `examples/`, `completions/`, `VERSION` | `modules/` through the wrapper |

So **"is this file in the repo" does not answer "does this reach users"**. `.github/`,
`.claude/` and `.git-hooks/` never ship. `docs/` always ships as readable text.
`tests/` ships by Homebrew and never runs. And a function in `modules/` that is gated on
`manifest_is_canonical_repo` ships to everyone and runs only where the canonical check
passes: this repository, and any checkout carrying its four structural entries — three files and `modules/` — (a fork),
whatever its origin.

### What exists for this repository only, and why installed copies do not need it

| Thing | Why it exists here | Why an installed copy does not need it |
| --- | --- | --- |
| Homebrew tap publishing, the formula template, the follow-up patch (`update_homebrew_formula`, `formula/manifest.rb`) | Only this repository releases the CLI itself. | A user's ship releases *their* project. The code ships but its gate prints "Skipping" wherever the canonical check does not pass. |
| The Manifest-branded README, CHANGELOG and version-block templates (`create_default_readme`, `create_default_changelog`, `generate_readme_version_section`) | This repository's own documentation. | Users get the neutral template; branding their README as ours would be a defect. |
| `tests/`, the container leg, the CI workflows, the skip budget | They are the only proof the product works before it leaves. Both legs must be green before a release, because each sees failures the other cannot — a rule the maintainer follows, not one the ship enforces. | A user's repository is verified by *its own* gate, which `manifest init` scaffolds as `scripts/run-tests.sh`. |
| Shipping from `scripts/manifest-cli.sh` instead of the installed `manifest` | The installed binary is the previous release; a change to the ship path must be shipped by the code that contains it. | Users have one copy and nothing newer to prefer. |
| `docs/TRACKER.md`, `.claude/agents/`, the self-application guards (`gitignore_self_apply.bats`, `version_single_source.bats`, …) | The product's work state, and checks that this repository follows the rules its own templates give everyone else. | They describe this project, not the user's. |

### What exists for installed copies only, and why this repository does not need it

| Thing | Why users need it | Why this repository does not |
| --- | --- | --- |
| Scaffold templates (`.gitignore`, `robots.txt`, `ai.txt`, the release gate, env files) and `manifest init` | A user starts from nothing and needs safe defaults for any language. | This repository's copies are hand-maintained and predate the templates. Running `init` here has reversed deliberate decisions before, which is why the self-application guards exist instead. |
| Detectors for retired output (old sidecar files, the old gate wrapper), `docs/MIGRATION.md`, and opt-out keys such as `git.allow_gate_drift` and `release.gate_host_writes` | A user may be many versions behind and still carry what an old version wrote. A change in default behaviour reaches them without warning unless it is announced, documented and reversible. | This repository is always at `HEAD`; the stale output is simply deleted here. |
| The fixing version recorded on every closed PRODUCT item | The register's *Blast radius* section gives the rule and the reason. | A canonical-only fix is complete the moment it is committed. |
| Fleet commands, `manifest env`, secret-store configuration, multi-language detection | Users run many repositories, many stacks and their own infrastructure. | This repository is one Bash repo with no deployment. **It cannot exercise these on itself**, so only fixture tests prove them — and a default that happens to match this organisation's own setup is a defect, not a convenience. |
| Refusing execution keys from committed configuration, preview-by-default, containerize-by-default | A user may clone a repository they do not trust, on a machine they care about. | The maintainer trusts this repository; the rules still apply here so that they stay tested. |

### Working rules that follow

1. **Classify by where the code runs, not where the file lives.** A canonical-gated
   function in `modules/` is CANONICAL-ONLY; a comment in `modules/` is read by users.
2. **A template and this repository's own copy are two fixes.** Correcting
   `robots.txt` here does nothing for users; correcting the template does nothing for
   this file. Say which one a change is, and do both when both are wrong.
3. **A change to what an installed copy does by default** needs a migration note and
   an opt-out where the old behaviour was relied on, and is closed the way the register
   closes PRODUCT items. A canonical-only change needs none of these.
4. **Evidence must match the audience.** A test that reads this repository's own files
   proves this repository. A claim about users needs a fixture repository, and it needs
   the container leg as well as the host suite.
5. **Nothing from this organisation in a default.** No vendor, store name, host, path
   or account that is true here may be assumed for a user.
6. **Question a canonical-only finding before filing it as local.** The register's
   *Blast radius* section says why, with the case that taught it.

The register's ranking rule built on this distinction is in
[`docs/TRACKER.md`](docs/TRACKER.md), under *Blast radius*.

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
