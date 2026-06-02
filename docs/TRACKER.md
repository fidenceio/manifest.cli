# Manifest CLI — Tracker

Open work for the Manifest CLI repo, as one flat list.

- Every item names a concrete deliverable and an anchor; the `§X.Y` label is a stable ID (referenced from commits, memory, and the Cloud/workspace trackers — do not renumber).
- Drift policy: when an item ships, **delete it** from this file. Provenance lives in the merge commit and release history.
- Status tag (2026-05-22 enterprise-readiness triage):
  - **T1** — release-blocking; absence allows lost user state, lost git history, or unrecoverable partial fleet state.
  - **T2** — contract integrity; absence allows the safe-by-default contract to drift or bypass.
  - **T3** — coverage, audit, or docs required before declaring the v1 enterprise release done.
  - **DEFER** — real value, but absence causes no safety harm at fleet-of-dozens scale.
  - **CUT** — considered and rejected; kept here so it doesn't reappear by accident. File a fresh item rather than reviving a cut entry verbatim if the reasoning changes.

---

- **§3.1 Cloud handoff CLI work — gated by Cloud-side milestones M0–M3.**
  - **Status:** DEFER.
  - **Why:** every CLI-side Cloud item activates 1:1 with a Cloud-tracker milestone — contract sources, `cloud.*` config surface, provider wiring, payload privacy assertions, recipe metadata, user-facing docs, and container verification. Tracking them as separate CLI items duplicates the Cloud tracker and creates drift sites for two-step changes. Cloud stays a no-op stub today ([`modules/stubs/manifest-cloud-stub.sh`](../modules/stubs/manifest-cloud-stub.sh)). Source of truth: [Cloud TRACKER §1 (Contracts/M0)](../../fidenceio.manifest.cloud/docs/TRACKER.md#1-contracts-m0-gate), [§2 (Service implementation/M1/M3)](../../fidenceio.manifest.cloud/docs/TRACKER.md#2-service-implementation-m1--m3-gates), [§3 (Security & platform/M3)](../../fidenceio.manifest.cloud/docs/TRACKER.md#3-security--platform-m3-gate). When a Cloud milestone lands, re-file specific CLI deliverables as new items here against the freshly-stable Cloud contract — do not pre-fork them.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

- **§5.1 Extract user global-config migration from `install-cli.sh`.**
  - **Status:** DEFER (pure refactor).
  - **Why:** `install-cli.sh` remains large, and the global-config migration (`migrate_user_global_configuration()`, currently inline) is a clean extraction boundary.
  - **Deliverable:** new `scripts/migrate-user-config.sh`; `install-cli.sh` delegates.
  - **Anchor:** [`install-cli.sh`](../install-cli.sh).

- **§5.4 Add e2e coverage for the brew-managed tap dir scenario.**
  - **Status:** T3.
  - **Why:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats) now stubs `brew` in `setup()` to isolate the fixture, which is correct for that file but means the brew-managed candidate path — `$(brew --prefix)/Library/Taps/fidenceio/homebrew-tap`, returned by [`manifest_homebrew_tap_checkout_candidates`](../modules/core/manifest-core.sh) — is no longer exercised by any test. In production this path runs on every `manifest refresh` and during ship's post-push auto-upgrade (orchestrator → `manifest_ship_restore_tap_ssh_origin`). A regression in the candidate generator or the refresher's iteration over the brew-managed dir would not be caught.
  - **Deliverable:** a new test file (suggested: `tests/homebrew_tap_refresh_brew_dir.bats`) that isolates `$HOME`, stubs `brew --prefix` to a scratch dir containing a seeded `Library/Taps/fidenceio/homebrew-tap` checkout (matching the pattern in [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats)), and exercises the refresher with both candidates present. Assertions cover correct fast-forward of both, correct skip of dirty/divergent, and the strict count summary.
  - **Anchor:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats), [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh) (`manifest_homebrew_tap_checkout_candidates`, `manifest_refresh_homebrew_tap_checkouts`), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh) (`manifest_ship_post_push_steps`, `manifest_ship_restore_tap_ssh_origin`).

- **§5.6 Capture per-run ship logs for forensic replay.**
  - **Status:** T2.
  - **Why:** when a ship leaves the install or repo in an unexpected state (observed 2026-05-21: `$HOME/.manifest-cli/` payload empty after an interrupted run, with no record of which step ran or where the failure occurred), diagnosis falls back to guesswork from `git log` + `brew Cellar` timestamps. A timestamped per-run log would convert these incidents from "best-guess narrative" to "read the file." Note: §5.6 is *diagnostic* logging (what happened, for debug); structured audit events (who-authorized-what-when, for compliance) are the shipped apply-event audit log.
  - **Deliverable:** ship writes a per-run log to `$HOME/.manifest-cli/logs/ship-<ts>.log` capturing each step boundary, exit status, and any captured stderr (routed through `manifest_redact`, shipped 2026-05-30, so captured stderr cannot leak token-shaped values); resume reads the prior log when reporting "picking up from step X." Add log rotation (keep last N runs) tied to a TTL marker. The log path must NOT fall under [`manifest_install_paths_cache_dirs`](../modules/system/manifest-install-paths.sh) — diagnostic logs are not transient and must not be swept.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh), [`modules/system/manifest-runtime-cleanup.sh`](../modules/system/manifest-runtime-cleanup.sh).

- **§5.11 Standardize on GNU userland to make CI fully container-only.**
  - **Status:** DEFER (enables dropping the host-native macOS CI leg).
  - **Why:** the 2026-06-01 audit fix (F3) containerized the Linux test leg + all of lint, but the macOS leg stays host-native. Two reasons keep it host-bound: GitHub's macOS runners have no Docker, **and** macOS is the only leg that exercises the BSD-userland branches of the real Homebrew release path — `sed -i ''` vs `sed -i` ([`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh)), `date -r` vs `date -d` ([`modules/core/manifest-status.sh`](../modules/core/manifest-status.sh), [`modules/system/manifest-os.sh`](../modules/system/manifest-os.sh)), `stat -f` vs `stat -c` ([`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh)). This is a *userland* (coreutils) split, independent of the Bash version — the wrapper already re-execs into Bash 5 everywhere, so escalating the shell does nothing for these. `coreutils` is already a declared dep but its `gnubin` is not forced onto PATH, and the BSD/GNU branches remain (verified 2026-06-02). Note `coreutils` alone is insufficient: it ships `gdate`/`gstat` but **not** GNU `sed` (that's the separate `gnu-sed`/`gsed` formula).
  - **Deliverable:** add `gnu-sed` alongside the existing `coreutils` Homebrew dep; guarantee their `gnubin` is on `PATH` for every install/runtime channel (brew formula, source install, the re-exec preamble); convert the BSD/GNU-branched call sites to a single GNU codepath; then drop the `macos-latest` matrix leg so `test.yml` is 100% container-only and remove the host-native exception from [`.github/workflows/test.yml`](../.github/workflows/test.yml) and the container-only docs caveat. Verify no remaining BSD-first branches via grep. Confirm the new PATH ordering doesn't shadow anything users depend on.
  - **Anchor:** [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`formula/manifest.rb`](../formula/manifest.rb), [`scripts/manifest-cli-wrapper.sh`](../scripts/manifest-cli-wrapper.sh), [`modules/system/manifest-os.sh`](../modules/system/manifest-os.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **§5.12 Verify the macOS-only paths on a real macOS CI runner.**
  - **Status:** T3 (verification follow-up to the 2026-06-01 audit-fix branch).
  - **Why:** the audit fixes were validated exhaustively on Linux/in-container (full suite green, shellcheck error-gate, gitleaks), but two macOS-specific paths cannot be exercised there and remain **unverified until CI runs on a real `macos-latest` runner**: (1) the BSD fallback in the portable mtime probe — `stat -f %m` in [`_fleet_dir_mtime_epoch`](../modules/fleet/manifest-fleet.sh) (Linux only ever takes the GNU-first `stat -c %Y` branch); (2) the host-native macOS test leg added in F3 ([`.github/workflows/test.yml`](../.github/workflows/test.yml)) — its brew provisioning and the now-skipped-under-root permission test. The `ubuntu+macos` matrix is present in `test.yml`; this item is passive until it runs green. Stated plainly: everything testable on Linux is green; macOS is a known blind spot until the matrix runs.
  - **Deliverable:** on the first push to `main` / PR-to-main that triggers the full matrix, confirm the macOS leg is green — specifically that `stat -f %m` returns a clean epoch on BSD (so fleet lock-reclaim grace timing is correct) and the brew-provisioned suite passes. If the macOS leg fails, fix forward before relying on the BSD branch.
  - **Anchor:** [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh) (`_fleet_dir_mtime_epoch`), [`tests/fleet_preflight_git_write.bats`](../tests/fleet_preflight_git_write.bats).

- **§6.1 Fleet-service config editor.** **Status:** CUT (command creep). `manifest.fleet.config.yaml` is the source of truth for `services.<name>.release.enabled` / `.strategy`; the file is human-editable and schema-validated on load. A CLI subcommand wrapping `vim` of a transparent YAML file adds a validation, bug, and test surface in exchange for keystrokes that don't reduce risk.

- **§6.2 Workspace/fleet membership drift detection.** **Status:** CUT (command creep / doctor-style sprawl). Users discover drift naturally on the next `ship fleet` preview, which already enumerates members from fleet config against the working tree. A dedicated read-only diff command would add CLI, validation, and test surface for information the next fleet preview already surfaces.

- **§6.3 `--json` summaries for `refresh` and `ship`.** **Status:** CUT (no current customer ask). `status` and `config list` already emit JSON; streaming side-effect commands would need a structured per-step result object plumbed through the orchestrator — meaningful surface area for zero current demand. Re-file as a fresh item if CI/automation integration becomes a tier-1 request.

- **§6.4 Cached-timestamp precision label.** **Status:** CUT (cosmetic). Fleet ship output reads `Trusted timestamp ±0.000000` for cached values; the `±0.000000` reads as bogus precision, but the values are correct and the label causes no compliance, safety, or workflow harm. Carry only if a user surfaces confusion in an auditing context.

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
