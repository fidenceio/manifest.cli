# Manifest CLI Security Notes

**Reviewed against:** 59.2.1 — **Updated:** 2026-08-19
**Scope:** Current security posture, and the known gaps in it

> This file is **hand-maintained**. `manifest security` does not write it — it
> reports three checks and, with `--write`, archives a timestamped copy under
> `docs/zArchive/`. Until 2026-08-19 a bare `manifest security` copied a generated
> template over this file, replacing reviewed text with fixed claims ("No `eval`
> Usage", "A+ 95/100") that no check produced. See TRACKER §26.
>
> The gaps below are stated because a posture summary that lists only controls
> overstates the posture. Each names the tracker item that owns it.

---

## Current Status

Manifest CLI includes active controls for the security concerns that matter
during release automation:

### Secrets

- Pre-commit hook (`.git-hooks/pre-commit`) scans staged content for secrets,
  tokens, private environment files, and large files.
  **Gap — it is not installed by cloning.** The hook is reached via
  `core.hooksPath=.git-hooks`, which lives in `.git/config` and is not cloned, so
  on a fresh clone this control is simply absent and a teammate can commit past
  it. `CONTRIBUTING.md` documents the manual step. (TRACKER §7)
- CI runs `gitleaks` over the tree on pushes to `main`, PRs targeting `main`, and
  manual dispatch (`.github/workflows/lint.yml`). It scans the **working tree
  only** — history is fetched but not range-scanned. (TRACKER §13)
- `.gitignore` enforcement keeps local config and private environment files out
  of version control. **Gap — `.gitignore` does not apply to already-tracked
  files**, and there is no key-material scan of any kind: `manifest security`
  checks the `security.private_files` list, a PII regex, and env-var naming, so a
  private key under an unmatched name (`credentials.json`, `privkey`) is caught by
  nothing while the release commit is a bare `git add .`. (TRACKER §2)
- Output redaction: `manifest_redact` strips known credential env-var values
  (e.g. `GITHUB_TOKEN`, `HOMEBREW_GITHUB_API_TOKEN`, the cloud API key and the
  var named by `MANIFEST_CLI_CLOUD_API_KEY_ENV`) and token shapes (GitHub
  classic + fine-grained PATs, AWS, OpenAI, JWT, Bearer) from every `log_*`
  line and the ship status file.
  **Gap — value redaction is inert under `gh`-managed auth**, where no
  `GITHUB_TOKEN` exists in the environment to match; shape-based patterns still
  apply. It is also wired only into `log_*`, so output printed by a bare `echo`
  bypasses it. (TRACKER §28)

### Safe-by-default execution

- Mutating commands preview unless `-y` / `--yes`; `--dry-run` is the explicit
  preview spelling. `-y` applies with no confirmation prompt; an ambiguous apply
  target (detached HEAD / no origin) is refused unless `MANIFEST_CLI_AUTO_CONFIRM`
  authorizes it. `MANIFEST_CLI_AUTO_CONFIRM` does not authorize apply.
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
  to be green before the GitHub Release / Homebrew tap publish; `none` is loud and
  audited.
- Single-flight locks serialize concurrent `manifest ship fleet -y` runs in a
  workspace, and concurrent `ship repo` runs in one repository, so they cannot race
  on shared version/tag/tap-publish state. Stale locks are reclaimed only from a
  provably dead local holder; live or cross-host holders are never broken. Since
  2026-08-19 the fleet, repo and config locks share one implementation
  (`modules/system/manifest-lock.sh`).
  **Behaviour to know:** acquisition waits a bounded 50 × 0.1 s and then refuses.
  Contention therefore resolves as a *queue* when the holder finishes inside 5 s
  and as a *refusal* when it does not. A ship routinely exceeds 5 s, so refusal is
  the common case — this is timing-dependent by construction, not a guarantee of
  either behaviour. (TRACKER §14)
- Pre-tag re-entrancy: an interrupted ship (VERSION bumped but uncommitted)
  resumes in place instead of double-bumping.

### Static analysis & diagnostics

- CI lints shell sources with `shellcheck` — a hard gate at **error** severity
  over `modules/` and `scripts/` plus the three top-level installers. A second job
  runs at `warning` severity but is `continue-on-error`, i.e. advisory.
  **Gap — "all shell sources" is not accurate.** The glob is
  `find modules scripts -name "*.sh"`, so `tests/**.bats`, `completions/` and
  `.git-hooks/pre-commit` are never scanned. This is not academic: bash exempts a
  `!`-prefixed command from errexit, and 114 bats assertions were consequently
  inert — shellcheck's **SC2251** detects exactly that shape but is `info`
  severity, below the only blocking job. (TRACKER §9.27(b))
- `manifest status`, `manifest doctor`, and `manifest security` provide read-only
  diagnostics before consequential commands run. `manifest security` is read-only
  by default; `--write` archives a timestamped report and writes nothing else.

## Audit History

- **2026-08-19** — gaps added beside every control, and the four statements that
  contradicted `docs/TRACKER.md` corrected (hook distribution, gitleaks scope,
  redaction under `gh` auth, lock contention behaviour). `manifest security` no
  longer overwrites this file.
- **2026-05-30** — refreshed alongside an enterprise-hardening pass (release gate,
  single-flight fleet lock, pre-tag re-entrancy, output redaction, shellcheck +
  gitleaks CI, and Apache-2.0 `LICENSE` / `SECURITY.md` / `CONTRIBUTING.md`), each
  landed with bats coverage and adversarial code review.
- **2026-04-25** — point-in-time analysis of v44.2.0. Its archived copy is no
  longer present under `docs/zArchive/`; this line is the only surviving record,
  and the citation that used to point at the file has been removed rather than
  left dangling.

A full 13-phase assurance audit ran against v59.2.1 in August 2026. Its artifacts
are deliberately untracked, so **this file and `docs/TRACKER.md` are the only
record a clone can see.** Its headline verdict was Fail-or-NotProven across nine
of ten categories — but read that with TRACKER §5 in hand: of the findings
adjudicated so far only a minority were real *as filed*, two of three P0s were
defects in the audit harness rather than the product, and the remainder have not
been triaged to the same depth. Treat the audit as a lead list, not a defect list.

**Not proven, in the audit's own terms** (nobody looked, which is not the same as
clean): macOS, FreeBSD and WSL2 have no executable evidence and cannot get any
without provisioned images; the Linux evidence base is Alpine/musl on a mutable
tag, not the Ubuntu-LTS glibc target; eight mutation routes were offline-
infeasible. (TRACKER §5's absorbed §9.16 ledger, §21a)

This document should never claim that an older audit is current, and should never
list controls without their known gaps. Update it after any dedicated security
review, and update the version/date line at the same time.
