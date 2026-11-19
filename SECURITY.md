# Security Policy

Manifest CLI carries out high-consequence operations for you: version bumps, commits,
tags, pushes, GitHub Releases, and releases across a fleet of repositories. We take the
security of those operations seriously, and we welcome responsible disclosure.

## Supported Versions

Manifest CLI is released from a single main branch, and each release replaces the one
before it. We provide security fixes for the **current major series only**. That is the
series of the latest published release. Every earlier major series is unsupported.

This policy is a rule and not a table of versions, because a table goes out of date
between releases. To see which series is supported, upgrade and read the version:

```bash
brew upgrade manifest
manifest version
```

Always upgrade to the latest release before you report a problem.

## Reporting a Vulnerability

**Do not open a public issue or pull request for a security report.**

Email **developer@fidence.co** with:

- A description of the issue and its impact.
- Steps to reproduce it: a minimal sequence of commands, the state of the repository,
  and the environment.
- The output of `manifest version`, and your operating system and Bash version.
- Any proof of concept, logs or screenshots, with secrets removed.

If you believe the issue exposes credentials or lets someone run arbitrary commands,
say so in the subject line so that we can give it priority.

### Response targets

| Stage | Target |
| --- | --- |
| Acknowledgement | within 3 business days |
| Initial assessment | within 7 business days |
| Fix or mitigation plan | within 30 days, depending on severity |

We keep you informed until the issue is resolved. We credit you in the release notes
unless you prefer to remain anonymous.

## Scope

In scope:

- Command injection, path traversal or privilege escalation in the CLI, the installer
  (`install-cli.sh`) or the uninstaller (`uninstall-cli.sh`).
- Leaks of secrets (tokens, API keys) into stdout or stderr, logs, the ship status
  file, generated docs or committed content.
- Destructive operations that escape their guards. Examples: a sandbox or test run that
  changes the real system, or a global `brew` uninstall that runs unexpectedly.
- Any way around the preview/apply safety model or the release gate.

Out of scope:

- Vulnerabilities in third-party dependencies (`git`, `gh`, `yq`, `brew`, Docker).
  Report those to their maintainers. We still appreciate being told.
- Issues that need a host that is already compromised, or a local install that has
  been modified maliciously.
- Social-engineering scenarios and scenarios that need physical access.

## Built-in Safeguards

Manifest CLI includes several protective controls that you can rely on and audit:

- **Preview by default.** A command that changes something only previews unless you
  pass `-y` or `--yes`.
- **Release gate.** `release.gate` (`local-tests` by default) blocks publishing a
  release unless the tests pass. The value `none` turns the gate off, prints a loud
  warning and is recorded in the audit log. The gate command itself is configurable.
  The next item says who may set it. A gate that a repository could choose for you
  would not be a gate.
- **Configuration that names a program.** Five config keys name something the CLI runs
  during a ship: `release.gate_command`, `docs.review.command`,
  `docs.release_notes.command`, and the two selectors that make those commands
  reachable, `docs.review.provider` and `docs.release_notes.provider`.
  - Each program runs as **a list of arguments, never through a shell**. There is no
    `eval` and no `bash -c` interpolation, so a value cannot inject shell
    metacharacters.
  - The keys are honoured **only from layers you own**: your global config, any
    `*.local.yaml` file (which the scaffold adds to `.gitignore`), and the process
    environment.
  - A **committed `manifest.config.yaml` is refused**, in the project and at the fleet
    root. That file travels with a clone. If it were honoured, cloning a repository and
    shipping it would let the repository choose what runs on your machine. The project
    layer also overrides your global one, so your own safe settings would not protect
    you.
  - The refusal is **announced**, never silent. It names the key and the layer.
  - You can opt in for one run with `MANIFEST_CLI_TRUST_REPO_COMMANDS=1`. You can opt
    in once with `=remember`, which records the decision in
    `~/.manifest-cli/trusted-repo-commands.tsv`. The record is keyed on the
    repository's remote and on a digest of the exact values you accepted. A changed
    value is refused again until you review it. `=forget` deletes the record.
  - Trust is an environment variable on purpose, and the record lives outside every
    repository. A committed file must not be able to grant itself trust.
  - Both the preview and the applied run **list every program that a config names and
    that may run, with the layer that supplied it**.
  - The gate status tells you whose command ran. A gate command from your own global
    config or a `*.local.yaml` file has the same trust as the auto-detected test suite
    and reports the ordinary status `verified-local`. A gate command taken from a
    committed config under the opt-in reports the distinct status
    `verified-local-repo-command`. A gate that the repository chose therefore cannot be
    mistaken for one that you chose.
- **Guards on destructive operations.** Removal and global `brew` operations are
  guarded. Under a sandbox or test `HOME` they are skipped, so they cannot touch the
  real system.
- **Secret scanning.** A pre-commit hook (`.git-hooks/pre-commit`) blocks commits that
  contain token-shaped strings or private environment files. Cloning does not turn the
  hook on. It runs only after you enable it with `git config core.hooksPath .git-hooks`.
  CI runs gitleaks on every push to `main` and on every pull request that targets
  `main`.
- **Output redaction.** Known token shapes and the values of credential environment
  variables are removed from log output and from the ship status file.
- **Single-flight locks.** Concurrent fleet releases in the same workspace take turns,
  and so do concurrent `ship repo` runs in the same repository. This prevents races on
  shared version, tag and formula state.

A summary of the current security controls and their known gaps is in
[docs/SECURITY_ANALYSIS_REPORT.md](docs/SECURITY_ANALYSIS_REPORT.md).
