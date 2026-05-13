# Bash 5 Runtime Fix

**Status:** Shipped in the v47.6.3 patch release
**Created:** 2026-05-06
**Goal:** Manifest CLI must run under Bash 5+ everywhere. Bash 3.2 may start a wrapper on macOS, but it must never reach CLI modules or nested Manifest execution.

## Problem

The `manifest ship repo minor` release to `47.4.0` exposed a runtime bug in the automatic follow-up patch. The main release completed, installed the upgraded CLI, then the follow-up patch invoked `manifest ship repo patch` as a child process. That child inherited `MANIFEST_CLI_BASH_REEXEC=1`, started under macOS `/bin/bash` 3.2, assumed re-exec had already been attempted, and failed instead of re-entering Bash 5.

There is a second observability issue: `detect_bash_version` reports `bash --version` from `PATH`, not the currently running interpreter. This can print Bash 3.2 even when the process is actually running under Bash 5.

## Design Decision

Bash 5+ is the only supported Manifest CLI runtime.

Wrappers may begin execution under an older shell only long enough to locate and `exec` Bash 5+. After that:

- CLI modules are sourced only under Bash 5+.
- Nested `manifest` invocations clear inherited re-exec sentinels.
- Runtime status reports the actual interpreter.
- Bash 3.2 is never accepted as a functional runtime.

## Implementation Checklist

- [x] Remove the inherited `MANIFEST_CLI_BASH_REEXEC=1` hard stop from repo-local wrappers.
- [x] Remove the inherited `MANIFEST_CLI_BASH_REEXEC=1` hard stop from the Homebrew wrapper template.
- [x] Add a helper for Manifest calling Manifest, preserving workflow guards while clearing only Bash re-exec state.
- [x] Update `manifest_ship_run_followup_patch` to use the safe helper.
- [x] Update runtime Bash reporting to use `$BASH_VERSION` and `${BASH_VERSINFO}` from the current process.
- [x] Audit installed wrapper generation in `formula/manifest.rb`.
- [x] Audit repo-local wrappers in `scripts/manifest-cli.sh` and `scripts/manifest-cli-wrapper.sh`.
- [x] Confirm generated hooks intentionally clear inherited Bash re-exec state.
- [x] Audit subprocess call sites for direct `manifest`, `bash -lc`, `/bin/bash`, and `command -v bash` usage.
- [x] Add tests for nested Manifest execution with inherited `MANIFEST_CLI_BASH_REEXEC=1`.
- [x] Add tests for follow-up patch invocation through the safe helper.
- [x] Add tests proving status reports the current Bash runtime.
- [x] Update Homebrew wrapper tests for the Bash 5 guard.
- [x] Run the focused container tests.
- [x] Run the full container test suite.
- [x] Ship a patch release after verification. Released in v47.6.3 on 2026-05-09.

## Remaining Hardening

- [ ] Extract the duplicated wrapper guard into a generated/shared source if wrapper drift becomes a recurring issue. The current fix keeps the small wrapper snippets aligned and tested without introducing a new bootstrap dependency.

## Likely Files

- `scripts/manifest-cli.sh`
- `scripts/manifest-cli-wrapper.sh`
- `formula/manifest.rb`
- `modules/system/manifest-os.sh`
- `modules/workflow/manifest-orchestrator.sh`
- `modules/core/manifest-shared-functions.sh`
- `tests/homebrew_wrapper.bats`
- `tests/ship_resume.bats`
- `tests/status.bats`
- `tests/security_check.bats`

## Verification Commands

```bash
./scripts/run-tests-container.sh tests/homebrew_wrapper.bats
./scripts/run-tests-container.sh tests/ship_resume.bats
./scripts/run-tests-container.sh tests/security_check.bats
./scripts/run-tests-container.sh tests/status.bats
./scripts/run-tests-container.sh
```

Local verification before release:

```bash
env MANIFEST_CLI_BASH_REEXEC=1 ./scripts/manifest-cli.sh --version
env MANIFEST_CLI_BASH_REEXEC=1 ./scripts/manifest-cli.sh status repo
```

After shipping:

```bash
manifest --version
manifest status repo
```

## Release Notes Target

The release notes should state that Manifest CLI now enforces Bash 5+ consistently across wrappers, nested invocations, and release follow-up automation, preventing macOS Bash 3.2 from leaking into runtime paths.
