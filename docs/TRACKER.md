# Manifest CLI — Tracker

Open work for the Manifest CLI repo.

## Conventions

- Items grouped by area, not by tier or session.
- Every item names a concrete deliverable and an anchor.
- Drift policy: when an item ships, delete it from this file. Provenance lives in the merge commit and release history.
- Items carry a **Status:** marker from the 2026-05-22 enterprise-readiness triage:
  - **T1** — release-blocking; absence allows lost user state, lost git history, or unrecoverable partial fleet state.
  - **T2** — contract integrity; absence allows the safe-by-default contract to drift or bypass.
  - **T3** — coverage, audit, or docs required before declaring the v1 enterprise release done.
  - **DEFER (post-enterprise)** — real value, but absence causes no safety harm at fleet-of-dozens scale.

## Enterprise-readiness scope (2026-05-22)

The hardening-pass triage organized open work around *"does absence of this item allow harm at fleet-of-dozens scale?"*

### T2 — contract integrity (5)

- §1.1 Halt clearly when fleet release requires PR review first
- §2.2 Shared plan renderer, fingerprint comparison, preview exit code (residual; helper + Version column shipped)
- §2.3 Execution-policy edge audit
- §2.8 Reconcile remaining `validation:` knobs with their gates
- §5.6 Per-run ship logs for forensic replay

### T3 — coverage, audit, docs (5)

- §2.6 Local-only apply tests
- §3.8 Cloud apply-intent contract stubs
- §4.4 Archive cleanup obeys the read-only archive rule
- §5.4 e2e coverage for brew-managed tap dir scenario
- §5.9 PR apply-event audit coverage (follow-up to the shipped §5.8)

### DEFER — post-enterprise (4)

- §3.1 Cloud handoff CLI side (collapsed pointer; gated by Cloud milestones M0–M3)
- §4.2 Fish completions
- §5.1 Extract user global-config migration from `install-cli.sh`
- §5.10 Layered test-cost reduction (tier / select / parallelize / cache) — dev-velocity, not release-blocking — **DONE** (batch-shipping)

§6 lists items explicitly cut (command-creep candidates) so they don't reappear by accident.

---

## 1. Fleet operations

- **1.1 Halt clearly when fleet release requires PR review first.**
  - **Status:** T2.
  - **Why:** fleet release should not silently skip PR-gated members. Silent skip leaves the fleet in an inconsistent state where some members shipped and others didn't.
  - **Deliverable:** fleet ship preview lists PR-gated members; apply refuses with a structured error and a `manifest pr fleet ... -y` replay command.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

---

## 2. Execution policy & preview safety

The base contract is already live: mutating commands preview by default, `--dry-run` is explicit preview, `-y`/`--yes` selects apply, and contradictory `--dry-run` plus `-y` is rejected. Remaining work is consolidation and edge-case coverage.

- **2.2 Finish shared plan rendering, fingerprint comparison, and the preview exit code.**
  - **Status:** T2 (partially shipped 2026-05-30).
  - **Shipped:** `manifest_plan_fingerprint` helper ([`manifest-shared-utils.sh`](../modules/core/manifest-shared-utils.sh)), displayed in the ship-repo preview and apply; the `Version` column (`current → next`, ASCII arrow) in the fleet ship plan; `_manifest_hash_short` exported.
  - **Why (residual):** the fingerprint is shown but not yet (a) computed via a single shared plan-table renderer reused across ship/fleet/PR previews — each surface still renders bespoke output, and (b) persisted at preview time and re-compared on apply, so apply cannot warn when the plan changed since the preview the user read. (c) The preview exit-code convention is also unaddressed: preview-without-consent and applied-successfully both still return 0, so CI wrappers can't distinguish them.
  - **Deliverable:** extract a shared plan-table renderer used by ship/fleet/PR previews; persist the preview fingerprint (e.g. under the run/status dir) and warn on apply if the recomputed fingerprint differs; introduce a distinct preview exit code (proposed: a dedicated non-zero "preview happened, no consent" code, documented in COMMAND_REFERENCE and covered by a bats test) without breaking the existing `--dry-run` contract.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-plan.sh`](../modules/fleet/manifest-fleet-plan.sh), [`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh).

- **2.3 Finish the execution-policy edge audit.**
  - **Status:** T2.
  - **Why:** aliases, recursive Manifest calls, generated hooks, CI workflows, and unknown flag paths can still bypass the intended command surface if they are not checked together. Each unaudited path is a contract hole.
  - **Deliverable:** audit deprecated aliases, `scripts/`, generated hook templates, and `.github/workflows/*.yml`; route mutating calls through explicit `-y`, explicit `--dry-run`, or a shared rejection path. Centralize unknown flag handling where practical.
  - **Anchor:** [`modules/core/`](../modules/core/), [`scripts/`](../scripts/), [`.github/workflows/`](../.github/workflows/).

- **2.6 Add focused local-only apply tests.**
  - **Status:** T3.
  - **Why:** `--local -y` is its own contract and should prove local writes occur without remote dispatch. Enterprise wants offline-safe boundaries that are tested, not asserted.
  - **Deliverable:** targeted tests for local-only ship/refresh/fleet paths, including assertions that no remote push/API command is called.
  - **Anchor:** [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **2.8 Reconcile the remaining `validation:` knobs with their (missing) gates.**
  - **Status:** T2.
  - **Why:** the 2026-05-26 audit found the `validation:` block was mostly decorative. `require_expected_branch` and `allow_branch_operations` were fully inert and have been **removed** (no branch-workflow enforcement — that is left to the user). The other three knobs are still suspect: `require_clean_status`'s behavior is hardcoded-on in the apply path ([`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh) ~197) and flipping the flag changes nothing; `enforce_dependencies` and `strict` are reachable via `get_fleet_setting` short keys but no apply/preflight gate consumer was found. Config that advertises a guarantee the tool doesn't keep is a contract hole.
  - **Deliverable:** for each of `require_clean_status`, `enforce_dependencies`, `strict`, either wire it to a real gate (flag actually changes apply/preflight behavior, covered by a bats test) or remove it from the config + default heredoc — following the `require_expected_branch` removal precedent. Document the resulting honest contract.
  - **Anchor:** [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/fleet/manifest-fleet-config.sh`](../modules/fleet/manifest-fleet-config.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

---

## 3. Cloud handoff — CLI side

The local release-notes provider hook and recipe inspection surfaces exist. Remaining work is the Cloud-specific contract, payload policy, and end-to-end verification. **All §3 items except §3.8 are DEFER (post-enterprise)** — they activate as the Cloud-side milestones (M0–M3) land. Cloud is disabled by default per workspace cross-cut [§1.4](../../TRACKER.md#1-cross-cut-requirements), so the v1 enterprise CLI release can ship with these items pending.

- **3.1 Cloud handoff CLI work — gated by Cloud-side milestones M0–M3.**
  - **Status:** DEFER (post-enterprise).
  - **Why:** every CLI-side Cloud item activates 1:1 with a Cloud-tracker milestone — contract sources, `cloud.*` config surface, provider wiring, payload privacy assertions, recipe metadata, user-facing docs, and container verification. Tracking them as separate CLI items duplicates the Cloud tracker and creates drift sites for two-step changes. Source of truth: [Cloud TRACKER §1 (Contracts/M0)](../../fidenceio.manifest.cloud/docs/TRACKER.md#1-contracts-m0-gate), [§2 (Service implementation/M1/M3)](../../fidenceio.manifest.cloud/docs/TRACKER.md#2-service-implementation-m1--m3-gates), [§3 (Security & platform/M3)](../../fidenceio.manifest.cloud/docs/TRACKER.md#3-security--platform-m3-gate). When a Cloud milestone lands, re-file specific CLI deliverables as new items here against the freshly-stable Cloud contract — do not pre-fork them.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

- **3.8 Add Cloud apply-intent contract stubs.**
  - **Status:** T3.
  - **Why:** Cloud-backed mutation must fail closed when `execution_mode=apply` is missing. Enforcing this on the local stub now means that whenever §3.3 wires real Cloud calls, the contract is already pinned. Mirrors workspace cross-cut [§1.1](../../TRACKER.md#1-cross-cut-requirements).
  - **Deliverable:** local stub test that rejects a Cloud request missing apply intent before any provider or analyzer runs.
  - **Anchor:** [`modules/stubs/manifest-cloud-stub.sh`](../modules/stubs/manifest-cloud-stub.sh), new `tests/cloud_contract.bats`.

---

## 4. Docs & completions

- **4.2 Add fish-shell completions.**
  - **Status:** DEFER (post-enterprise).
  - **Why:** bash and zsh completions ship; fish remains missing. Fish users can use the CLI fine without; no contract surface.
  - **Deliverable:** `completions/manifest.fish` plus install instructions in `completions/README.md`.
  - **Anchor:** [`completions/`](../completions/), [`tests/completions.bats`](../tests/completions.bats).

- **4.4 Make archive cleanup obey the read-only archive rule.**
  - **Status:** T3.
  - **Why:** archive cleanup still creates `docs/zArchive/v<major>/` directories and regenerates archive `INDEX.md` files. The active rule is: moved files only; no new generated output inside the archive.
  - **Deliverable:** flatten future archive moves into `docs/zArchive/`, remove archive index generation and its call sites, and add a regression proving cleanup moves files without creating archive-side generated files.
  - **Anchor:** [`modules/docs/manifest-cleanup-docs.sh`](../modules/docs/manifest-cleanup-docs.sh), [`tests/archive_move_log.bats`](../tests/archive_move_log.bats), [`tests/archive_pre_move_safety.bats`](../tests/archive_pre_move_safety.bats).

---

## 5. Structural & polish

- **5.1 Extract user global-config migration from `install-cli.sh`.**
  - **Status:** DEFER (post-enterprise; pure refactor).
  - **Why:** `install-cli.sh` remains large, and the global-config migration is a clean extraction boundary.
  - **Deliverable:** new `scripts/migrate-user-config.sh`; `install-cli.sh` delegates.
  - **Anchor:** [`install-cli.sh`](../install-cli.sh).

- **5.4 Add e2e coverage for the brew-managed tap dir scenario.**
  - **Status:** T3.
  - **Why:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats) now stubs `brew` in `setup()` to isolate the fixture, which is correct for that file but means the brew-managed candidate path — `$(brew --prefix)/Library/Taps/fidenceio/homebrew-tap`, returned by [`manifest_homebrew_tap_checkout_candidates`](../modules/core/manifest-core.sh) — is no longer exercised by any test. In production this path runs on every `manifest refresh` and during ship's post-push auto-upgrade (orchestrator → `manifest_ship_restore_tap_ssh_origin`). A regression in the candidate generator or the refresher's iteration over the brew-managed dir would not be caught.
  - **Deliverable:** a new test file (suggested: `tests/homebrew_tap_refresh_brew_dir.bats`) that isolates `$HOME`, stubs `brew --prefix` to a scratch dir containing a seeded `Library/Taps/fidenceio/homebrew-tap` checkout (matching the pattern in [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats)), and exercises the refresher with both candidates present. Assertions cover correct fast-forward of both, correct skip of dirty/divergent, and the strict count summary.
  - **Anchor:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats), [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh) (`manifest_homebrew_tap_checkout_candidates`, `manifest_refresh_homebrew_tap_checkouts`), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh) (`manifest_ship_post_push_steps`, `manifest_ship_restore_tap_ssh_origin`).

- **5.6 Capture per-run ship logs for forensic replay.**
  - **Status:** T2.
  - **Why:** when a ship leaves the install or repo in an unexpected state (observed 2026-05-21: `$HOME/.manifest-cli/` payload empty after an interrupted run, with no record of which step ran or where the failure occurred), diagnosis falls back to guesswork from `git log` + `brew Cellar` timestamps. A timestamped per-run log would convert these incidents from "best-guess narrative" to "read the file." Note: §5.6 is *diagnostic* logging (what happened, for debug); structured audit events (who-authorized-what-when, for compliance) are §5.8.
  - **Deliverable:** ship writes a per-run log to `$HOME/.manifest-cli/logs/ship-<ts>.log` capturing each step boundary, exit status, and any captured stderr (routed through `manifest_redact`, shipped 2026-05-30, so captured stderr cannot leak token-shaped values); resume reads the prior log when reporting "picking up from step X." Add log rotation (keep last N runs) tied to a TTL marker. The log path must NOT fall under [`manifest_install_paths_cache_dirs`](../modules/system/manifest-install-paths.sh) — diagnostic logs are not transient and must not be swept.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh), [`modules/system/manifest-runtime-cleanup.sh`](../modules/system/manifest-runtime-cleanup.sh).

- **5.9 PR apply-event audit coverage.**
  - **Status:** T3.
  - **Why:** §5.8 (the CLI apply-event audit log) shipped — every apply that crosses the apply-guard `manifest_execution_require_apply` now appends one redacted NDJSON event to `$HOME/.manifest-cli/audit/apply-events.ndjson` with actor / source (`cli` / `cli-fleet`) / command / scope / plan hash / exit status, covering `ship repo`, `ship fleet`, `prep`, and `refresh`. But `manifest pr … -y` does **not** route through that guard ([`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh) calls `manifest_execution_apply_header` and runs `gh` directly, with no git-write boundary), so PR applies still emit no audit event. The `cli-pr` source named in the §5.8 design is therefore not yet populated.
  - **Deliverable:** emit a `cli-pr` apply event for each `-y`-gated PR mutation (create / merge / ready / update). Either route PR applies through a shared emit point or call `manifest_audit_apply_event` (shipped) directly at each PR apply boundary, setting `MANIFEST_CLI_AUDIT_SOURCE=cli-pr`. PR ops have no version plan, so the plan-hash field is empty/N/A — confirm the consumer tolerates an empty `plan_hash`. Add a regression asserting one `cli-pr` event per PR apply with the gh-backed command recorded and redaction applied.
  - **Anchor:** [`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh), [`modules/core/manifest-shared-utils.sh`](../modules/core/manifest-shared-utils.sh) (`manifest_audit_apply_event`).

- **5.10 Layered test-cost reduction.**
  - **Status:** DONE (implemented; batch-shipping as one minor). All six steps built and verified — full suite green; the suite no longer runs unconditionally in full on every push. Was: the 682-test suite ran in full on every push (CI `test.yml`, ubuntu+macos matrix) **and** pre-bump on every `ship` (the release gate). The gate runs the suite in an `env -i` clean room ([`_manifest_release_gate_exec`](../modules/workflow/manifest-orchestrator.sh)); this item layers cost controls on top without weakening it.
  - **Design (as built):** tiering by event is the spine; change-aware selection, parallelization, and TTL'd green-run caching are accelerators. `scripts/run-tests.sh` is the single shared entrypoint for both CI and the local gate. Self-describing config only (`release.gate_tier`, `test.skip_unchanged_within`) — no new subcommands ([[feedback_command_creep]], [[feedback_config_ux]]). Parallelism is context-determined (auto in container/CI, serial in the gate), not a config knob — so no `test.parallel_jobs`.
  - **Tiers:** `smoke` (safety-contract subset — execution-policy/apply-guard, ship preview+apply, fleet lock, redaction, audit log, config layering, plan fingerprint, release gate; tagged at file scope via native bats `# bats file_tags=smoke`) and `full` (all). Event map (as built in `test.yml`): routine feature-branch push → smoke + change-aware + single-OS (ubuntu); PR-to-main / push-to-main / nightly schedule / manual dispatch → full + ubuntu+macos matrix, `--no-cache`; local ship gate → full + serial + `--no-cache` (tier configurable via `release.gate_tier`). **Invariant: nothing merges to main or releases without a full run** — held structurally because both PR-to-main and push-to-main take the full, uncached path.
  - **Accelerators:**
    - *Change-aware selection* — explicit `tests/coverage-map.tsv` (module-glob → test files); diff vs merge-base (or CI's `MANIFEST_CLI_TEST_CHANGED_PATHS` seam); run mapped tests + always-on smoke; **fail-safe to full** when a core/shared/unmapped file or the map itself changes; docs-only → smoke. Log skips loudly ([[feedback_surface_defects]] / no silent caps).
    - *Parallelize* — `run-tests.sh --jobs N|auto` (default `auto`). bats parallelism is built on **GNU parallel**, a required test dependency provisioned only in environments we control: the test container (`apk add parallel`) and CI (apt/brew). A parallel run without GNU parallel is a **hard error**, never a silent serial downgrade (that would misreport what ran); `--jobs 1` is the serial escape hatch. The **local ship gate runs serial** (`--tier <tier> --jobs 1`) so shipping never requires GNU parallel on a developer's host — local-ship speed comes from the tier, not parallelism. **Prerequisite:** test hermeticity (some ship/fleet tests don't isolate `$HOME` — proven by §5.8 writing stray apply-events to the real `~/.manifest-cli/audit/`); parallel would race on shared writes (validated: full suite green under `--jobs auto`).
    - *Cache + TTL* — after a green run, record `fingerprint(modules/+tests/+run-tests.sh content + bats version, keyed by run scope=tier+selected files) -> epoch` under `.test-cache/` (gitignored; `MANIFEST_CLI_TEST_CACHE_DIR` override); skip when fingerprint matches AND within the window, else run. Window = `test.skip_unchanged_within` / `MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN` (default **4h**; accepts `30m`/`90s`/`2d`/`off`; renamed from the design's `cache_ttl` to avoid jargon and a collision with the existing `time.cache_ttl` date cache). Fail-safe to running on any doubt; `--no-cache` forces a run and is appended by both the release gate and every merge-gating CI leg, so nothing releases or merges on a cached result. Local marker only — GitHub Actions cross-run cache restore is **deliberately deferred** (ephemeral runners start with an empty `.test-cache/`, so the cache is inert-but-safe in CI; restoring it on the fast lane is a future optimization, not a correctness gap).
  - **Sequencing (DONE; batch-shipped as one minor):** (1) ✅ test hermeticity (`$HOME`/state isolation; also fixes the stray-audit-write leak); (2) ✅ tiering (smoke tags + `--tier`; gate wired to `release.gate_tier`); (3) ✅ parallelize (`--jobs`); (4) ✅ change-aware selection (coverage map + `--changed`, fail-safe + logging); (5) ✅ cache + TTL (local marker; Actions restore deferred); (6) ✅ `test.yml` event-tiered matrix + docs/reconcile.
  - **Anchor:** [`scripts/run-tests.sh`](../scripts/run-tests.sh), [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`tests/`](../tests/).

- **5.11 Standardize on GNU userland to make CI fully container-only.**
  - **Status:** DEFER (post-enterprise; enables dropping the host-native macOS CI leg).
  - **Why:** the 2026-06-01 audit fix (F3) containerized the Linux test leg + all of lint, but the macOS leg stays host-native. Two reasons keep it host-bound: GitHub's macOS runners have no Docker, **and** macOS is the only leg that exercises the BSD-userland branches of the real Homebrew release path — `sed -i ''` vs `sed -i` ([`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh)), `date -r` vs `date -d` ([`modules/core/manifest-status.sh`](../modules/core/manifest-status.sh), [`modules/system/manifest-os.sh`](../modules/system/manifest-os.sh)), `stat -f` vs `stat -c` ([`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh)). This is a *userland* (coreutils) split, independent of the Bash version — the wrapper already re-execs into Bash 5 everywhere, so escalating the shell does nothing for these. Note `coreutils` alone is insufficient: it ships `gdate`/`gstat` but **not** GNU `sed` (that's the separate `gnu-sed`/`gsed` formula).
  - **Deliverable:** add `coreutils` + `gnu-sed` as declared Homebrew deps; guarantee their `gnubin` is on `PATH` for every install/runtime channel (brew formula, source install, the re-exec preamble); convert the BSD/GNU-branched call sites to a single GNU codepath; then drop the `macos-latest` matrix leg so `test.yml` is 100% container-only and remove the host-native exception from [`.github/workflows/test.yml`](../.github/workflows/test.yml) and the container-only docs caveat. Verify no remaining BSD-first branches via grep. Confirm the new PATH ordering doesn't shadow anything users depend on.
  - **Anchor:** [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`formula/manifest.rb`](../formula/manifest.rb), [`scripts/manifest-cli-wrapper.sh`](../scripts/manifest-cli-wrapper.sh), [`modules/system/manifest-os.sh`](../modules/system/manifest-os.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **5.12 Verify the macOS-only paths on a real macOS CI runner.**
  - **Status:** T3 (verification follow-up to the 2026-06-01 audit-fix branch).
  - **Why:** the audit fixes were validated exhaustively on Linux/in-container (full suite green, shellcheck error-gate, gitleaks), but two macOS-specific paths cannot be exercised there and remain **unverified until CI runs on a real `macos-latest` runner**: (1) the BSD fallback in the portable mtime probe — `stat -f %m` in [`_fleet_dir_mtime_epoch`](../modules/fleet/manifest-fleet.sh) (Linux only ever takes the GNU-first `stat -c %Y` branch); (2) the host-native macOS test leg added in F3 ([`.github/workflows/test.yml`](../.github/workflows/test.yml)) — its brew provisioning and the now-skipped-under-root permission test. Stated plainly: everything testable on Linux is green; macOS is a known blind spot until the ubuntu+macos matrix runs.
  - **Deliverable:** on the first push to `main` / PR-to-main that triggers the full matrix, confirm the macOS leg is green — specifically that `stat -f %m` returns a clean epoch on BSD (so fleet lock-reclaim grace timing is correct) and the brew-provisioned suite passes. If the macOS leg fails, fix forward before relying on the BSD branch.
  - **Anchor:** [`.github/workflows/test.yml`](../.github/workflows/test.yml), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh) (`_fleet_dir_mtime_epoch`), [`tests/fleet_preflight_git_write.bats`](../tests/fleet_preflight_git_write.bats).

---

## 6. Explicitly out of scope

Items considered during the 2026-05-22 enterprise-readiness triage and cut. Listed here so they don't reappear by accident; if a future requirement changes the reasoning, file a new item rather than reviving a cut entry verbatim.

- **6.1 Fleet-service config editor (formerly §1.4).**
  - **Cut reason:** command creep. `manifest.fleet.config.yaml` is the source of truth for `services.<name>.release.enabled` and `services.<name>.release.strategy`; the file is human-editable and schema-validated on load. Adding a CLI subcommand that wraps `vim` of a transparent YAML file introduces a new validation surface, a new bug surface, and a new test surface in exchange for keystrokes that don't reduce risk.
  - **Original deliverable (kept for provenance):** add a safe-by-default command, final name TBD, for scoped fleet-service config edits such as enabling/disabling release and setting release strategy.

- **6.2 Workspace/fleet membership drift detection (formerly §1.3).**
  - **Cut reason:** command creep / doctor-style sprawl. Users discover drift naturally on the next `ship fleet` preview, which already enumerates members from fleet config against the working tree. A dedicated read-only diff command would add a CLI surface, a validation surface, and a test surface for information the next fleet preview already surfaces.
  - **Original deliverable (kept for provenance):** read-only workspace diff that compares discovered repos to fleet config, exposed from a low-friction command such as `manifest doctor`, `manifest update fleet --dry-run`, or a timestamped passive check.

- **6.3 `--json` summaries for `refresh` and `ship` (formerly §5.2).**
  - **Cut reason:** no current customer ask. `status` and `config list` already emit JSON; streaming side-effect commands would need a structured per-step result object plumbed through the orchestrator. Meaningful surface area for zero current demand. Re-file as a fresh item if CI/automation integration becomes a tier-1 customer request.
  - **Original deliverable (kept for provenance):** orchestrator emits a structured per-step result object; `--json` on `refresh` and `ship` serializes the final summary.

- **6.4 Cached-timestamp precision label (formerly §5.3).**
  - **Cut reason:** cosmetic. Fleet ship output reads `Trusted timestamp ±0.000000` for cached values across members. The `±0.000000` reads as bogus precision, but values themselves are correct and the label causes no compliance, safety, or workflow harm. Carry this only if a user surfaces confusion in an auditing context.
  - **Original deliverable (kept for provenance):** when emitting a cached timestamp, label it as `cached (from <source> at <time>)` and drop the precision figure, OR report the original measurement's confidence rather than zero. Add a regression covering the cached-emit path.

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
