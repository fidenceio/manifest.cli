# Manifest CLI Security Notes

**Version:** 50.2.0
**Updated:** 2026-05-30
**Scope:** Current security posture and audit status

---

## Current Status

Manifest CLI includes active controls for the security concerns that matter
during release automation:

### Secrets

- Pre-commit hook (`.git-hooks/pre-commit`) scans staged content for secrets,
  tokens, private environment files, and large files.
- CI runs `gitleaks` over the tree on every push/PR (`.github/workflows/lint.yml`).
- `.gitignore` enforcement keeps local config and private environment files out
  of version control.
- Output redaction: `manifest_redact` strips known credential env-var values
  (e.g. `GITHUB_TOKEN`, `HOMEBREW_GITHUB_API_TOKEN`, the cloud API key and the
  var named by `MANIFEST_CLI_CLOUD_API_KEY_ENV`) and token shapes (GitHub
  classic + fine-grained PATs, AWS, OpenAI, JWT, Bearer) from every `log_*`
  line and the ship status file.

### Safe-by-default execution

- Mutating commands preview unless `-y` / `--yes`; `--dry-run` is the explicit
  preview spelling. `MANIFEST_CLI_AUTO_CONFIRM` only answers prompts after apply
  is selected — it does not authorize apply.
- Global configuration writes require confirmation, with stricter confirmation
  for destructive global-config changes.
- Destructive operations (removal, global `brew uninstall`) are gated and
  protectively skip under a sandbox/test `HOME` so a test run can never mutate
  the real system.
- Release commands validate version formats, tag names, repository state, and
  canonical-repo boundaries before mutating, and refuse to ship off the release
  branch.

### Release integrity

- Release gate (`release_gate`, default `local-tests`) blocks publishing a
  release until verification passes; `remote-ci` requires the pushed commit's CI
  to be green before the GitHub Release / Homebrew publish; `none` is loud and
  audited.
- Single-flight fleet lock serializes concurrent `manifest ship fleet -y` runs
  in a workspace so they cannot race on shared version/tag/formula state. Stale
  locks are reclaimed only from a provably dead local holder; live or cross-host
  holders are never broken.
- Pre-tag re-entrancy: an interrupted ship (VERSION bumped but uncommitted)
  resumes in place instead of double-bumping.

### Static analysis & diagnostics

- CI lints all shell sources with `shellcheck` (hard gate at error severity).
- `manifest status`, `manifest doctor`, and `manifest security --check` provide
  read-only diagnostics before consequential commands run.

## Audit History

This document was refreshed on 2026-05-30 alongside an enterprise-hardening pass
(release gate, single-flight fleet lock, pre-tag re-entrancy, output redaction,
shellcheck + gitleaks CI, and Apache-2.0 `LICENSE` / `SECURITY.md` /
`CONTRIBUTING.md`), each landed with bats coverage and adversarial code review.

The previous point-in-time security analysis covered Manifest CLI v44.2.0 on
2026-04-25. It is retained as historical evidence in
[zArchive/SECURITY_ANALYSIS_REPORT_v44.2.0_20260425T195739Z.md](zArchive/SECURITY_ANALYSIS_REPORT_v44.2.0_20260425T195739Z.md).

This live document should not claim that an older audit is current. Regenerate
this report after any future dedicated security review and update the
version/date above at the same time.
