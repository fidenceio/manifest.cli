# Bash 5 Runtime TODO

**Status:** Active implementation plan
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

- [ ] Centralize Bash 5 resolution so repo-local and Homebrew wrappers do not drift.
- [ ] Replace inherited `MANIFEST_CLI_BASH_REEXEC=1` behavior with a process-local guard or a safe child invocation helper.
- [ ] Add a helper for Manifest calling Manifest, preserving workflow guards while clearing only Bash re-exec state.
- [ ] Update `manifest_ship_run_followup_patch` to use the safe helper.
- [ ] Update runtime Bash reporting to use `$BASH_VERSION` and `${BASH_VERSINFO}` from the current process.
- [ ] Audit installed wrapper generation in `formula/manifest.rb`.
- [ ] Audit repo-local wrappers in `scripts/manifest-cli.sh` and `scripts/manifest-cli-wrapper.sh`.
- [ ] Audit generated hooks and hook tests so they intentionally clear inherited Bash re-exec state.
- [ ] Audit subprocess call sites for direct `manifest`, `bash -lc`, `/bin/bash`, and `command -v bash` usage.
- [ ] Add tests for nested Manifest execution with inherited `MANIFEST_CLI_BASH_REEXEC=1`.
- [ ] Add tests for follow-up patch invocation under a simulated old PATH Bash.
- [ ] Add tests proving status reports the current Bash runtime.
- [ ] Add or update Homebrew wrapper tests for the centralized Bash 5 guard.
- [ ] Run the focused container tests.
- [ ] Run the full container test suite.
- [ ] Ship a patch release after verification.

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

After shipping:

```bash
manifest --version
manifest status repo
```

## Release Notes Target

The release notes should state that Manifest CLI now enforces Bash 5+ consistently across wrappers, nested invocations, and release follow-up automation, preventing macOS Bash 3.2 from leaking into runtime paths.
