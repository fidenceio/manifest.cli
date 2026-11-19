# Contributing to Manifest CLI

Thank you for your interest in improving Manifest CLI. This document explains how to
set up a development environment, run the tests, and submit changes.

## Code of Conduct

Be respectful and constructive. Harassment or abusive behavior is not tolerated.

## Ground Rules

- **Tests are mandatory.** Every change in behavior comes with tests written for bats,
  the Bash test runner this project uses. The suite must pass before a change is
  merged.
- **Preview first, apply only on `-y`.** Code that changes anything must preview by
  default and act only on an explicit `-y` or `--yes`. Never add a code path that
  changes something without that rule. Never let `MANIFEST_CLI_AUTO_CONFIRM` authorize
  an apply by itself. Its only job is to allow an ambiguous target (a detached HEAD, or
  no `origin`) *after* `-y` has selected apply.
- **No secrets in commits.** The pre-commit hook and the gitleaks scan in CI reject
  token-shaped strings and private environment files. Keep credentials out of test
  fixtures.
- **Match the surrounding style.** Modules are Bash libraries that are loaded with
  `source`. They use namespaced `_manifest_*` helpers and the shared `log_*` output
  functions. Follow the conventions of the file you are editing.

## Two audiences: this repository and installed copies

This repository is the **canonical Manifest CLI source**: the one place the CLI is
built and released from. Everything in it serves one of two audiences. Most mistakes
here come from serving one audience while thinking about the other.

- **This repository.** One checkout, one maintainer, always at `HEAD`. It builds, tests
  and releases the CLI.
- **Installed copies.** The released CLI, running on other people's machines, against
  repositories this project never sees, at whatever version each person last upgraded
  to. Nobody here can inspect them, patch them, or know what state they are in.

The function `manifest_is_canonical_repo` (in
`modules/core/manifest-shared-functions.sh`) is how the code tells the two apart. It
makes two checks:

1. The origin slug. It must be `fidenceio/manifest.cli`, or one of the slugs listed in
   `release.canonical_repo_slugs`.
2. The structure. Any checkout that contains the installer, the wrapper, the formula
   template and `modules/` passes, whatever its origin. This is how a fork is
   recognised.

So "this repository" below means this repository and forks of it. Never identify it by
a filesystem path or a folder name.

### What reaches an installed copy

| Install route | What lands on the user's disk | What runs |
| --- | --- | --- |
| Homebrew formula | every top-level file and folder that is not a dot-entry: `modules/`, `scripts/`, `docs/` (including `docs/TRACKER.md` and `docs/zArchive/`), `tests/`, `examples/`, `formula/`, `robots.txt`, … | `modules/` through the wrapper |
| `install-cli.sh` | `modules/`, `docs/`, `examples/`, `completions/`, `VERSION` | `modules/` through the wrapper |

So **"is this file in the repo?" does not answer "does this reach users?"**

- `.github/`, `.claude/` and `.git-hooks/` never ship.
- `docs/` always ships, as readable text.
- `tests/` ships through Homebrew and never runs there.
- A function in `modules/` that is gated on `manifest_is_canonical_repo` ships to
  everyone. It runs only where the canonical check passes: in this repository, and in
  any checkout that contains the four structural entries (three files and `modules/`),
  which is how a fork passes whatever its origin.

### What exists for this repository only, and why installed copies do not need it

| Thing | Why it exists here | Why an installed copy does not need it |
| --- | --- | --- |
| Homebrew tap publishing, the formula template, the follow-up patch (`update_homebrew_formula`, `formula/manifest.rb`) | Only this repository releases the CLI itself. | A user's ship releases *their* project. The code ships, but it prints "Skipping" and does nothing wherever the canonical check does not pass. |
| The Manifest-branded README, CHANGELOG and version-block templates (`create_default_readme`, `create_default_changelog`, `generate_readme_version_section`) | They are this repository's own documentation. | Users get the neutral template. Branding their README as ours would be a defect. |
| `tests/`, the container test run, the CI workflows, the skip budget | They are the only proof that the product works before it leaves. The suite runs two ways: on the host and in a container. Both runs must pass before a release, because each sees failures the other cannot. The maintainer follows this rule; the ship does not enforce it. | A user's repository is verified by *its own* gate, which `manifest init` scaffolds as `scripts/run-tests.sh`. |
| Shipping from `scripts/manifest-cli.sh`, not from the installed `manifest` | The installed command is the previous release. A change to the ship code must be shipped by the code that contains it. | Users have one copy and nothing newer to prefer. |
| `docs/TRACKER.md`, `.claude/agents/`, the self-application guards (`gitignore_self_apply.bats`, `version_single_source.bats`, …) | They hold the state of the project's work, and they check that this repository follows the rules its own templates give everyone else. | They describe this project, not the user's. |

### What exists for installed copies only, and why this repository does not need it

| Thing | Why users need it | Why this repository does not |
| --- | --- | --- |
| Scaffold templates (`.gitignore`, `robots.txt`, `ai.txt`, the release gate, env files) and `manifest init` | A user starts from nothing and needs safe defaults for any language. | This repository's copies are maintained by hand. Do not run `init` here: it can undo deliberate decisions in those files. The self-application guards check them instead. |
| Detectors for output that older versions wrote (old sidecar files, the old gate wrapper), `docs/MIGRATION.md`, and opt-out keys such as `git.allow_gate_drift` and `release.gate_host_writes` | A user may be many versions behind and may still have files that an old version wrote. A change in default behaviour reaches them without warning unless it is announced, documented and reversible. | This repository is always at `HEAD`. Out-of-date output is deleted here. |
| The fixing version recorded on every closed PRODUCT item (an item that affects installed copies) | A user needs to know which release carries a fix. The *Blast radius* section of the register gives the rule and the reason. | A canonical-only fix is complete the moment it is committed. |
| Fleet commands, `manifest env`, secret-store configuration, multi-language detection | Users run many repositories, many language stacks and their own infrastructure. | This repository is one Bash repository with no deployment. **It cannot exercise these features on itself**, so only tests against fixture repositories prove them. A default that happens to match this organisation's own setup is a defect, not a convenience. |
| Refusing execution keys (config keys that name a program to run) from committed configuration, preview by default, containers by default | A user may clone a repository they do not trust, on a machine they care about. | The maintainer trusts this repository. The rules still apply here so that they stay tested. |

### Working rules that follow

Two labels are used below. CANONICAL-ONLY means that something runs only in this
repository. PRODUCT means that it reaches installed copies.

1. **Classify by where the code runs, not where the file lives.** A function in
   `modules/` that is gated on the canonical check is CANONICAL-ONLY. A comment in
   `modules/` is read by users.
2. **A template and this repository's own copy are two fixes.** Correcting
   `robots.txt` here does nothing for users. Correcting the template does nothing for
   this file. Say which one a change is, and do both when both are wrong.
3. **A change to what an installed copy does by default** needs a migration note. It
   also needs an opt-out where users relied on the old behaviour. Close it the way the
   register closes PRODUCT items. A canonical-only change needs none of these.
4. **Evidence must match the audience.** A test that reads this repository's own files
   proves this repository. A claim about users needs a fixture repository, and it needs
   the container test run as well as the host run.
5. **Nothing from this organisation in a default.** Do not assume that a vendor, store
   name, host, path or account that is true here is true for a user.
6. **Question a canonical-only finding before filing it as local.** The *Blast radius*
   section of the register says why.

The register is [`docs/TRACKER.md`](docs/TRACKER.md). Its ranking rule, which is built
on this distinction, is under *Blast radius*.

## Requirements

| Requirement | Version | Notes |
| ----------- | ------- | ----- |
| Bash | 5.0+ | Associative arrays and modern shell behavior. The Bash 3.2 that comes with macOS is refused. |
| git | Any supported release | |
| yq | 4.0+ (Mike Farah) | YAML config parsing |
| bats | 1.5+ (1.8+ for the `smoke` tier) | Test runner. Needed on your machine only for the host runner. |
| Docker | Running engine | For the containerized test runner |
| shellcheck | Latest | Lint (also enforced in CI) |

## Development Setup

Clone the repository and run the CLI from source, without installing it globally:

```bash
git clone https://github.com/fidenceio/manifest.cli.git
cd manifest.cli

# Enable the secret-scanning pre-commit hook
git config core.hooksPath .git-hooks

# Run the CLI from source (the wrapper sources modules/core/manifest-core.sh)
./scripts/manifest-cli-wrapper.sh version
```

Do **not** install runtime dependencies on your machine to validate a change. Use the
containerized runner, so that your environment stays clean and results can be
reproduced.

## Running Tests

```bash
# The standard way: in a container (no dependencies on your machine)
./scripts/run-tests-container.sh

# A single file, in the container
./scripts/run-tests-container.sh tests/release_gate.bats

# Host runner (requires bats, yq and Bash 5+ on your machine)
./scripts/run-tests.sh

# A single file, on the host
bats tests/release_gate.bats
```

Tests must never touch your real `~/.manifest-cli`. They run with a sandboxed `HOME`.
Keep it that way: any new test that writes global state must set
`HOME="$BATS_TEST_TMPDIR"`.

Lint before pushing:

```bash
shellcheck modules/**/*.sh scripts/*.sh install-cli.sh
```

## Submitting Changes

This project uses a trunk-based flow: changes branch from `main` and merge back into
it. To propose a change:

1. Branch from `main`.
2. Make a focused change with tests. Keep each commit to one concern.
3. Make sure that `./scripts/run-tests-container.sh` passes and that shellcheck reports
   nothing.
4. Open a pull request. Describe why the change is needed, what users will notice, and
   how you verified it. CI (tests, shellcheck and gitleaks) must pass.

Do not bump `VERSION`, edit `CHANGELOG.md` or create tags in a pull request.
`manifest ship` cuts releases. It handles the version, the changelog, the docs, the
tags and the GitHub Release as one operation.

## Reporting Security Issues

Do not report a security issue in public. Follow [SECURITY.md](SECURITY.md).

## License

By contributing, you agree that your contributions are licensed under the
[Apache License 2.0](LICENSE).
