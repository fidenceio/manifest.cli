# Manifest CLI Security Notes

**Last security review:** v59.2.1, 2026-08-19.
**Control descriptions checked against the code:** 2026-11-18.
**Scope:** the security controls in the CLI today, and the known gaps in them.

> This file is **maintained by hand**. `manifest security` does not write it. That
> command runs five checks and prints the results. With `--write` it also saves a
> timestamped report in the docs archive folder, and it writes nothing else.
>
> Each control below is listed together with its known gaps. A summary that lists only
> controls would overstate how well the CLI is protected.

---

## Current Status

Manifest CLI has controls for the security concerns that matter during release
automation.

### Secrets

- **Pre-commit hook.** `.git-hooks/pre-commit` scans staged content for secrets,
  tokens, private environment files and large files.
  **Gap: cloning does not install it.** Git finds the hook through the setting
  `core.hooksPath=.git-hooks`. That setting lives in `.git/config`, which is not
  cloned. On a fresh clone the hook does not run until the contributor enables it.
  `CONTRIBUTING.md` gives the command.
- **CI secret scan.** CI runs `gitleaks` on pushes to `main`, on pull requests that
  target `main`, and on manual runs (`.github/workflows/lint.yml`).
  **Gap: it scans the working tree only.** The job fetches the full history but does
  not scan the range of commits.
- **`.gitignore` rules.** They keep local config and private environment files out of
  version control.
  **Gap: `.gitignore` does not apply to a file that Git already tracks.**
- **Private key scan.** `manifest security` scans the tree for private key material by
  content: PEM and PuTTY key headers. A commit made by Manifest refuses to add new key
  material. Key material that is already in the repository's history is reported, not
  refused.
  **Gap: only those key formats are recognised by content.** Other secrets are found
  by file name, through the `security.private_files` list. A secret in a file with a
  name that is not on the list, such as `credentials.json`, is not caught by
  `manifest security`.
- **Release commit scope.** The release commit stages only the files that the release
  writes. The automatic commit before it stages every pending file, so the scans above
  are what protect it.
- **Output redaction.** `manifest_redact` removes two kinds of text from every `log_*`
  line and from the ship status file:
  - the values of known credential variables, for example `GITHUB_TOKEN`,
    `HOMEBREW_GITHUB_API_TOKEN`, the cloud API key, and the variable named by
    `MANIFEST_CLI_CLOUD_API_KEY_ENV`
  - token shapes: GitHub classic and fine-grained tokens, AWS keys, OpenAI keys, JWTs
    and Bearer tokens

  **Gap: value redaction does nothing when `gh` manages authentication.** In that case
  no `GITHUB_TOKEN` exists in the environment to match. The shape patterns still apply.
  **Gap: only `log_*` output is redacted.** Output printed by a bare `echo` is not.

### Safe-by-default execution

- Commands that change something preview unless you pass `-y` or `--yes`. `--dry-run`
  asks for the preview by name. `-y` applies with no confirmation prompt.
- Manifest refuses to apply to an ambiguous target (a detached HEAD, or no `origin`)
  unless `MANIFEST_CLI_AUTO_CONFIRM` authorises it. `MANIFEST_CLI_AUTO_CONFIRM` does
  not authorise an apply by itself.
- Writes to the global configuration require confirmation. A destructive change to the
  global configuration requires a stricter confirmation.
- Destructive operations (removal, a global `brew uninstall`) are guarded. Under a
  sandbox or test `HOME` they are skipped, so a test run cannot change the real system.
- Release commands check version formats, tag names, repository state and
  canonical-repository boundaries before they change anything. They refuse to ship from
  a branch that is not the release branch.

### Release integrity

- **Release gate.** `release.gate` (default `local-tests`) blocks publishing until
  verification passes. `remote-ci` requires the pushed commit's CI to pass before the
  GitHub Release and the Homebrew tap publish. `none` prints a loud warning and is
  recorded in the audit log.
- **Single-flight locks.** A lock makes concurrent `manifest ship fleet -y` runs in one
  workspace take turns. Another lock does the same for concurrent `ship repo` runs in
  one repository. Two runs therefore cannot race on shared version, tag or tap-publish
  state. Manifest reclaims a stale lock only when it can prove that the holder was a
  local process that has died. It never breaks a lock held by a live process or by
  another host. The fleet, repo and config locks share one implementation,
  `modules/system/manifest-lock.sh`.
  **Behaviour to know:** a second run tries for the lock 50 times, 0.1 seconds apart,
  and then refuses. So the second run waits when the first finishes within 5 seconds
  and is refused when it does not. A ship usually takes longer than 5 seconds, so a
  refusal is the common result.
- **Interrupted ship.** If a ship stops after it bumped `VERSION` and before it
  committed, the next run continues from that version and does not bump a second time.

### Static analysis & diagnostics

- **ShellCheck in CI.** Two steps block the build:
  - Error severity over `modules/`, `scripts/`, every `tests/*.bats` and `tests/*.bash`
    file, and the three top-level installers.
  - Codes SC2251 and SC2314 over the test files. They catch a test assertion that
    starts with `!` and therefore can never fail.

  A third step reports warnings over `modules/`, `scripts/` and the installers. It is
  advisory and does not block.
  **Gap: not every shell file is scanned.** `completions/` and `.git-hooks/pre-commit`
  are in none of the three steps.
- **Read-only diagnostics.** `manifest status`, `manifest doctor` and
  `manifest security` report on the repository before you run a command with
  consequences. `manifest security` checks five things: private files tracked by Git,
  private key material, likely personal data (PII), environment-file hygiene, and
  environment-variable naming. It is read-only by default.

## Audit History

- **2026-08-19** — Review against v59.2.1. A gap was added beside every control. Four
  statements were corrected: hook distribution, gitleaks scope, redaction under `gh`
  authentication, and lock contention.
- **2026-05-30** — Refreshed together with a hardening pass: release gate,
  single-flight fleet lock, interrupted-ship handling, output redaction, shellcheck and
  gitleaks in CI, and the Apache-2.0 `LICENSE`, `SECURITY.md` and `CONTRIBUTING.md`.
  Each change landed with bats tests.
- **2026-04-25** — Point-in-time analysis of v44.2.0, archived at
  [`docs/zArchive/v44/`](zArchive/v44/SECURITY_ANALYSIS_REPORT_v44.2.0_20260425T195739Z.md).

**The August 2026 assurance audit.** A full 13-phase audit ran against v59.2.1. Its
working files are not in the repository, so this file and `docs/TRACKER.md` are the
only record that a clone contains. Read its result with these facts in mind:

- Its headline verdict was Fail or Not Proven in nine of ten categories.
- Only some of its findings have been checked one by one. Of those, a minority were
  real as filed. Two of its three highest-priority findings were defects in the audit
  harness, not in the product.
- The remaining findings have not been checked to the same depth. Treat the audit as a
  list of leads, not a list of defects.

**Not verified by that audit.** "Not verified" means that nobody looked. It does not
mean clean.

- macOS, FreeBSD and WSL2 had no executable evidence. Since the audit, CI runs the test
  suite natively on macOS (see [tests/README.md](../tests/README.md)). FreeBSD and WSL2
  still have none.
- The Linux evidence came from Alpine (musl) on a mutable image tag, not from Ubuntu
  LTS (glibc).
- Eight mutation routes could not be exercised offline.

**Rules for this file.** Do not present an older audit as current. Do not list a
control without its known gaps. Update the file after any dedicated security review,
and update the two date lines at the top at the same time.
