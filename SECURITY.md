# Security Policy

Manifest CLI executes high-consequence operations on your behalf — version bumps,
commits, tags, pushes, GitHub Releases, and multi-repo fleet releases. We take the
security of those paths seriously and welcome responsible disclosure.

## Supported Versions

Manifest CLI ships from a single trunk; each release supersedes the prior one. We
provide security fixes for the current major series.

| Version        | Supported          |
| -------------- | ------------------ |
| 50.x (current) | :white_check_mark: |
| < 50.0         | :x:                |

Always upgrade to the latest release before reporting:

```bash
brew upgrade manifest
manifest version
```

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
- **Release gate.** `release_gate` (`local-tests` by default) blocks publishing a
  release unless tests pass; `none` is loud and audited.
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
