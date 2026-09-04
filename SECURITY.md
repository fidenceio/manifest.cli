# Security Policy

Manifest CLI executes high-consequence operations on your behalf — version bumps,
commits, tags, pushes, GitHub Releases, and multi-repo fleet releases. We take the
security of those paths seriously and welcome responsible disclosure.

## Supported Versions

Manifest CLI ships from a single trunk; each release supersedes the prior one. We
provide security fixes for the **current major series only** — the one published as
the latest release. Every earlier major is unsupported.

This is stated as a rule rather than a version table on purpose: a pinned table goes
stale silently between releases and then misinforms exactly the person trying to
find out whether they are covered. To see the supported series, read the latest
release rather than this file:

```bash
brew upgrade manifest
manifest version
```

Always upgrade to the latest release before reporting.

## Reporting a Vulnerability

**Do not open a public issue or pull request for security reports.**

Email **developer@fidence.co** with:

- A description of the issue and its impact.
- Steps to reproduce (a minimal command sequence, repo state, and environment).
- The output of `manifest version` and your OS / Bash version.
- Any proof-of-concept, logs, or screenshots — with secrets redacted.

If you believe the issue exposes credentials or allows arbitrary command execution,
say so in the subject line so we can prioritize.

### Response targets

| Stage                  | Target            |
| ---------------------- | ----------------- |
| Acknowledgement        | within 3 business days |
| Initial assessment     | within 7 business days |
| Fix or mitigation plan | within 30 days, severity-dependent |

We will keep you informed through remediation and credit you in the release notes
unless you prefer to remain anonymous.

## Scope

In scope:

- Command injection, path traversal, or privilege escalation in the CLI, installer
  (`install-cli.sh`), or uninstaller (`uninstall-cli.sh`).
- Leakage of secrets (tokens, API keys) into stdout/stderr, logs, the ship status
  file, generated docs, or committed content.
- Destructive operations escaping their guards (e.g. a sandbox/test run mutating the
  real system, or a global `brew` uninstall firing unexpectedly).
- Bypass of the preview/apply safety model or the release gate.

Out of scope:

- Vulnerabilities in third-party dependencies (`git`, `gh`, `yq`, `brew`, Docker) —
  report those upstream, though we appreciate a heads-up.
- Issues requiring a pre-compromised host or a maliciously modified local install.
- Social-engineering or physical-access scenarios.

## Built-in Safeguards

Manifest CLI ships several defensive controls you can rely on and audit:

- **Preview by default.** Mutating commands preview unless `-y` / `--yes` is given.
- **Release gate.** `release.gate` (`local-tests` by default) blocks publishing a
  release unless tests pass; `none` is loud and audited. The gate command itself is
  configurable, so see **Configuration that names a program** below for who is
  allowed to set it — a gate a repository could choose would not be a gate.
- **Configuration that names a program.** Five config keys name something the CLI
  executes during a ship: `release.gate_command`, `docs.review.command`,
  `docs.release_notes.command`, and the `docs.review.provider` /
  `docs.release_notes.provider` selectors that make the commands reachable.
  - They are executed as **argv, never through a shell** — no `eval`, no `bash -c`
    interpolation — so a value cannot inject shell metacharacters.
  - They are honoured **only from layers you own**: your global config, any
    `*.local.yaml` (which the scaffold gitignores), and the process environment.
    A **committed `manifest.config.yaml` is refused**, in the project and at the
    fleet root, because that file travels with a clone — otherwise cloning a
    repository and shipping it would let the repository choose what runs on your
    machine, and the project layer overrides your global one, so configuring
    safely would not have protected you.
  - The refusal is **announced**, never silent, and names the key and the layer.
  - Opt in per run with `MANIFEST_CLI_TRUST_REPO_COMMANDS=1`. It is an environment
    variable deliberately: a committed file must not be able to grant itself trust.
  - Both the preview and the applied run **disclose every config-named program that
    may execute and the layer that supplied it**, and a gate supplied by
    configuration reports a distinct status (`verified-local-config-command`) so it
    cannot be mistaken for the auto-detected suite.
- **Destructive-op guards.** Removal and global `brew` operations are gated; under a
  sandbox/test `HOME` they protectively skip rather than touch the real system.
- **Secret scanning.** A pre-commit hook (`.git-hooks/pre-commit`) blocks committing
  token-shaped strings and private env files, and CI runs gitleaks.
- **Output redaction.** Known token shapes and credential env-var values are redacted
  from log output and the ship status file.
- **Single-flight fleet lock.** Concurrent fleet releases in the same workspace are
  serialized to prevent races on shared version/tag/formula state.

A current security posture summary is maintained in
[docs/SECURITY_ANALYSIS_REPORT.md](docs/SECURITY_ANALYSIS_REPORT.md).
