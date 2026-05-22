# Manifest CLI — Tracker

Open work for the Manifest CLI repo.

## Conventions

- Items grouped by area, not by tier or session.
- Every item names a concrete deliverable and an anchor.
- Drift policy: when an item ships, delete it from this file. Provenance lives in the merge commit and release history.

---

## 1. Fleet operations

- **1.1 Halt clearly when fleet release requires PR review first.**
  - **Why:** fleet release should not silently skip PR-gated members.
  - **Deliverable:** fleet ship preview lists PR-gated members; apply refuses with a structured error and a `manifest pr fleet ... -y` replay command.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **1.2 Add fleet partial-failure recovery output.**
  - **Why:** when a fleet apply fails mid-run, users need a precise resume or replay path.
  - **Deliverable:** structured report listing completed members, failed members, skipped members, and per-member replay or resume commands. Must specifically cover the **"release tagged + code pushed + formula push failed"** state observed 2026-05-19: the current recovery banner suggests tag-delete and hard-reset, but the tag and release commit are already on `origin/main` — the correct remediation is "release is live, formula stale; retry the tap push" (e.g., `manifest ship --resume-formula`), not a rollback that would orphan a published tag.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **1.3 Detect workspace/fleet membership drift.**
  - **Why:** fleet config goes stale when repos are added outside Manifest.
  - **Deliverable:** read-only workspace diff that compares discovered repos to fleet config, exposed from a low-friction command such as `manifest doctor`, `manifest update fleet --dry-run`, or a timestamped passive check.
  - **Anchor:** [`modules/fleet/manifest-fleet-detect.sh`](../modules/fleet/manifest-fleet-detect.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **1.4 Add a fleet-service config editor.**
  - **Why:** toggling `services.<name>.release.enabled` or `services.<name>.release.strategy` still requires hand-editing `manifest.fleet.config.yaml`.
  - **Deliverable:** add a safe-by-default command, final name TBD, for scoped fleet-service config edits such as enabling/disabling release and setting release strategy.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-config.sh`](../modules/fleet/manifest-fleet-config.sh).

- **1.5 Fail fast on sandboxed `.git` write denial during fleet ship.**
  - **Why:** during the W0 Phase 6 run on 2026-05-18 (`manifest ship fleet major -y`), the sandbox denied `.git` writes for the workspace root and marketing repos, leaving both in a partial state that required manual commit/tag/release recovery; Cloud and CLI only completed because they ran under elevated permissions. Fleet ship currently has no pre-flight that detects this class of environment failure, so the user discovers it mid-run, per-member, after each repo has already done partial work.
  - **Deliverable:** add a per-member pre-flight check that probes `.git` writability before any mutation; if any member fails, refuse fleet apply with a structured error naming the affected repos and a remediation hint (rerun outside sandbox / under elevated permissions). When a mid-run denial slips past pre-flight, the partial-failure recovery output (see §1.2) must distinguish "sandbox-denied, no state written" from "partially shipped, recovery needed." Add a regression that injects a read-only `.git` and asserts both the pre-flight refusal and the post-failure recovery output.
  - **Anchor:** [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **1.6 Add fleet-level resume entrypoint.**
  - **Why:** `manifest ship repo resume` ([`manifest-orchestrator.sh:393`](../modules/workflow/manifest-orchestrator.sh)) handles the per-repo "tag pushed, formula stranded" state, but a fleet ship that dies mid-iteration has no `manifest ship fleet resume` — the user must identify which members already shipped and manually invoke per-repo resume from each one. Observed 2026-05-21: an interrupted `ship fleet patch` left the CLI repo with `v48.5.1` tag pushed but formula uncommitted; recovery required manually `cd`-ing into the repo and running `ship repo resume`, with no help from the fleet layer.
  - **Deliverable:** add `manifest ship fleet resume` that walks each releaseable member, infers per-member state with the same checks as repo resume (VERSION present, tag exists locally + remotely, only `formula/manifest.rb` dirty), and delegates to per-repo resume for any member found in the stranded state. Skip cleanly when nothing to resume. The fleet-state probe must be shared between `--dry-run` (preview which members would resume) and apply.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

---

## 2. Execution policy & preview safety

The base contract is already live: mutating commands preview by default, `--dry-run` is explicit preview, `-y`/`--yes` selects apply, and contradictory `--dry-run` plus `-y` is rejected. Remaining work is consolidation and edge-case coverage.

- **2.1 Add shared apply-guard and replay-command helpers.**
  - **Why:** call sites still build "preview or apply" branches and replay commands by hand.
  - **Deliverable:** add `manifest_execution_require_apply` and `manifest_execution_replay_hint` in [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), migrate representative call sites, and cover them in tests.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **2.2 Add shared plan rendering and plan fingerprints.**
  - **Why:** preview output is still bespoke per command, and apply mode cannot warn when the plan changed since preview.
  - **Deliverable:** add a shared plan-table renderer plus a stable plan fingerprint helper; use them in ship/fleet/PR previews and compare fingerprints where apply recomputes work. Concrete content additions, surfaced by the 2026-05-19 fleet-ship trial:
    - a `Version` column showing `current → next` per member — required to disambiguate divergent SemVer trains (workspace `2.0.1 → 2.0.2` alongside cli `48.0.1 → 48.0.2`) before the user types `-y`;
    - a clearer preview exit-code convention so CI wrappers can distinguish "preview happened, no consent" from "applied successfully" (current behavior: both return 0).
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-plan.sh`](../modules/fleet/manifest-fleet-plan.sh), [`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh).

- **2.3 Finish the execution-policy edge audit.**
  - **Why:** aliases, recursive Manifest calls, generated hooks, CI workflows, and unknown flag paths can still bypass the intended command surface if they are not checked together.
  - **Deliverable:** audit deprecated aliases, `scripts/`, generated hook templates, and `.github/workflows/*.yml`; route mutating calls through explicit `-y`, explicit `--dry-run`, or a shared rejection path. Centralize unknown flag handling where practical.
  - **Anchor:** [`modules/core/`](../modules/core/), [`scripts/`](../scripts/), [`.github/workflows/`](../.github/workflows/).

- **2.4 Add the missing `MANIFEST_CLI_AUTO_CONFIRM` no-write regression.**
  - **Why:** code documents `MANIFEST_CLI_AUTO_CONFIRM=1` as prompt automation only, but the exact preview no-write regression should be explicit.
  - **Deliverable:** test that a preview command with `MANIFEST_CLI_AUTO_CONFIRM=1` still writes nothing and prints an apply replay command instead of mutating.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`tests/dry_run.bats`](../tests/dry_run.bats).

- **2.5 Add broad preview no-write coverage.**
  - **Why:** focused dry-run tests exist, but there is no shared matrix proving every mutating preview leaves git porcelain and file snapshots unchanged.
  - **Deliverable:** `tests/preview_no_write.bats` or equivalent helper-driven coverage across repo, fleet, PR, config, docs, install/uninstall, and refresh paths.
  - **Anchor:** [`tests/dry_run.bats`](../tests/dry_run.bats), [`tests/fleet_dry_run.bats`](../tests/fleet_dry_run.bats), [`tests/pr_native_safe_by_default.bats`](../tests/pr_native_safe_by_default.bats).

- **2.6 Add focused local-only apply tests.**
  - **Why:** `--local -y` is its own contract and should prove local writes occur without remote dispatch.
  - **Deliverable:** targeted tests for local-only ship/refresh/fleet paths, including assertions that no remote push/API command is called.
  - **Anchor:** [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

---

## 3. Cloud handoff — CLI side

The local release-notes provider hook and recipe inspection surfaces exist. Remaining work is the Cloud-specific contract, payload policy, and end-to-end verification.

- **3.1 Decide and document the CLI/Cloud contract source.**
  - **Deliverable:** decide whether CLI stores copied schemas under `docs/contracts/` or references Cloud as source of truth; document Standard and Verbose payload expectations.
  - **Anchor:** [`docs/contracts/`](contracts/), [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **3.2 Complete the `cloud.*` YAML/env config surface.**
  - **Deliverable:** add the remaining `cloud.{enabled,endpoint,release_notes.*,security.*}` mappings; keep Cloud disabled by default and secrets referenced by env name, not committed values.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`examples/manifest.config.yaml.example`](../examples/manifest.config.yaml.example), [`tests/yaml.bats`](../tests/yaml.bats).

- **3.3 Wire Cloud as a release-notes provider option.**
  - **Deliverable:** Cloud provider command selectable by config; local fallback preserved when optional; required mode aborts doc generation on failure; CLI remains owner of changelog writes.
  - **Anchor:** [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`tests/release_notes_provider.bats`](../tests/release_notes_provider.bats).

- **3.4 Add payload preview and privacy assertions.**
  - **Deliverable:** preview output shows Cloud mode, endpoint, fallback, identity, and upload decision; tests assert Standard mode excludes source bodies, raw diffs, raw commit bodies, author emails, full remotes, absolute paths, and secret-looking values.
  - **Anchor:** new `tests/cloud_payload.bats`, [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **3.5 Add Cloud handoff metadata to recipes.**
  - **Deliverable:** recipe schema accepts step `policy`/`privacy`/`fallback` metadata; ship recipes include a Cloud handoff step; `manifest ship repo patch --explain` shows Cloud status without uploading.
  - **Anchor:** [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`recipes/builtin/manifest.builtin.ship.repo.*.yaml`](../recipes/builtin/), [`tests/recipe.bats`](../tests/recipe.bats).

- **3.6 Finish CLI docs for Cloud handoff.**
  - **Deliverable:** document Standard mode, Verbose mode, no-code default, fallback behavior, provider-hook integration, recipe-backed commands, and the Fidence platform assumption for production Cloud.
  - **Anchor:** [`README.md`](../README.md), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md), [`docs/INDEX.md`](INDEX.md).

- **3.7 Verify the Cloud handoff path in containers.**
  - **Deliverable:** `./scripts/run-tests-container.sh tests/yaml.bats tests/release_notes_provider.bats tests/docs_generation.bats tests/recipe.bats tests/cloud_payload.bats` passes; `manifest ship repo patch --explain` works without GitHub or Cloud; full container suite is green.
  - **Anchor:** [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

- **3.8 Add Cloud apply-intent contract stubs.**
  - **Why:** Cloud-backed mutation must fail closed when `execution_mode=apply` is missing.
  - **Deliverable:** local stub test that rejects a Cloud request missing apply intent before any provider or analyzer runs.
  - **Anchor:** [`modules/stubs/manifest-cloud-stub.sh`](../modules/stubs/manifest-cloud-stub.sh), new `tests/cloud_contract.bats`.

---

## 4. Docs & completions

- **4.1 Finish safe-by-default help/doc audit.**
  - **Why:** user-facing docs and bash/zsh completions already describe most of the contract, but command help can still drift.
  - **Deliverable:** audit mutating command help examples so preview examples are bare commands and apply examples include `-y`; add tests where practical.
  - **Anchor:** [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md).

- **4.2 Add fish-shell completions.**
  - **Why:** bash and zsh completions ship; fish remains missing.
  - **Deliverable:** `completions/manifest.fish` plus install instructions in `completions/README.md`.
  - **Anchor:** [`completions/`](../completions/), [`tests/completions.bats`](../tests/completions.bats).

- **4.3 Write the public-release migration note.**
  - **Why:** users upgrading from pre-safe-by-default releases need a concise explanation of preview default, `-y` apply, and `MANIFEST_CLI_AUTO_CONFIRM` semantics.
  - **Deliverable:** migration copy in release docs or `docs/MIGRATION.md`, with matching language in the user guide before the next major release.
  - **Anchor:** [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md).

- **4.4 Make archive cleanup obey the read-only archive rule.**
  - **Why:** archive cleanup still creates `docs/zArchive/v<major>/` directories and regenerates archive `INDEX.md` files. The active rule is: moved files only; no new generated output inside the archive.
  - **Deliverable:** flatten future archive moves into `docs/zArchive/`, remove archive index generation and its call sites, and add a regression proving cleanup moves files without creating archive-side generated files.
  - **Anchor:** [`modules/docs/manifest-cleanup-docs.sh`](../modules/docs/manifest-cleanup-docs.sh), [`tests/archive_move_log.bats`](../tests/archive_move_log.bats), [`tests/archive_pre_move_safety.bats`](../tests/archive_pre_move_safety.bats).

---

## 5. Structural & polish

- **5.1 Extract user global-config migration from `install-cli.sh`.**
  - **Why:** `install-cli.sh` remains large, and the global-config migration is a clean extraction boundary.
  - **Deliverable:** new `scripts/migrate-user-config.sh`; `install-cli.sh` delegates.
  - **Anchor:** [`install-cli.sh`](../install-cli.sh).

- **5.2 Add `--json` summaries to `refresh` and `ship`.**
  - **Why:** `status` and `config list` have JSON, but streaming side-effect commands need structured step-result plumbing first.
  - **Deliverable:** orchestrator emits a structured per-step result object; `--json` on `refresh` and `ship` serializes the final summary.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-refresh.sh`](../modules/core/manifest-refresh.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **5.3 Stop reporting bogus precision on cached trusted timestamps.**
  - **Why:** fleet ship output reads `Trusted timestamp ±0.000000` for cached values across all members within seconds of each other. The `±0.000000` is technically the cache's confidence-of-itself, but reads as "we measured to sub-microsecond precision" — confusing for anyone auditing release timing. Observed 2026-05-19 across 4 members.
  - **Deliverable:** when emitting a cached timestamp, label it as `cached (from <source> at <time>)` and drop the precision figure, OR report the original measurement's confidence rather than zero. Add a regression covering the cached-emit path.
  - **Anchor:** [`modules/system/manifest-time.sh`](../modules/system/manifest-time.sh).

- **5.4 Add e2e coverage for the brew-managed tap dir scenario.**
  - **Why:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats) now stubs `brew` in `setup()` to isolate the fixture, which is correct for that file but means the brew-managed candidate path — `$(brew --prefix)/Library/Taps/fidenceio/homebrew-tap`, returned by [`manifest_homebrew_tap_checkout_candidates`](../modules/core/manifest-core.sh) — is no longer exercised by any test. In production this path runs on every `manifest refresh` and during ship's post-push auto-upgrade (orchestrator → `manifest_ship_restore_tap_ssh_origin`). A regression in the candidate generator or the refresher's iteration over the brew-managed dir would not be caught.
  - **Deliverable:** a new test file (suggested: `tests/homebrew_tap_refresh_brew_dir.bats`) that isolates `$HOME`, stubs `brew --prefix` to a scratch dir containing a seeded `Library/Taps/fidenceio/homebrew-tap` checkout (matching the pattern in [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats)), and exercises the refresher with both candidates present. Assertions cover correct fast-forward of both, correct skip of dirty/divergent, and the strict count summary.
  - **Anchor:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats), [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh) (`manifest_homebrew_tap_checkout_candidates`, `manifest_refresh_homebrew_tap_checkouts`), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh) (`manifest_ship_post_push_steps`, `manifest_ship_restore_tap_ssh_origin`).

- **5.5 Audit pre-tag ship steps for re-entrancy.**
  - **Why:** `manifest_ship_repo_resume` only re-enters at the push step ([`manifest-orchestrator.sh:460`](../modules/workflow/manifest-orchestrator.sh)). The pre-tag pipeline (version bump → docs/release notes → archive → commit) is non-resumable: an interruption between bump and commit leaves the repo with a half-applied state (VERSION bumped but uncommitted, generated docs on disk, no tag) and the user must manually undo before retrying. Each pre-tag step should be safe to re-run against partial state without producing duplicates or stale fragments.
  - **Deliverable:** for each pre-tag step (version bump, docs generation, archive moves, commit), document the partial-state-detection rule and add a "re-running on already-applied state is a no-op" regression. Where idempotency requires a marker, prefer reading git state over writing a sidecar file.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/docs/manifest-cleanup-docs.sh`](../modules/docs/manifest-cleanup-docs.sh), [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh).

- **5.6 Capture per-run ship logs for forensic replay.**
  - **Why:** when a ship leaves the install or repo in an unexpected state (observed 2026-05-21: `$HOME/.manifest-cli/` payload empty after an interrupted run, with no record of which step ran or where the failure occurred), diagnosis falls back to guesswork from `git log` + `brew Cellar` timestamps. A timestamped per-run log would convert these incidents from "best-guess narrative" to "read the file."
  - **Deliverable:** ship writes a per-run log to `$HOME/.manifest-cli/logs/ship-<ts>.log` capturing each step boundary, exit status, and any captured stderr; resume reads the prior log when reporting "picking up from step X." Add log rotation (keep last N runs) tied to a TTL marker. The log path must NOT fall under [`manifest_install_paths_cache_dirs`](../modules/system/manifest-install-paths.sh) — diagnostic logs are not transient and must not be swept.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh), [`modules/system/manifest-runtime-cleanup.sh`](../modules/system/manifest-runtime-cleanup.sh).

- **5.7 Make `install-cli.sh` upgrades atomic.**
  - **Why:** the current upgrade flow runs `cleanup_old_installation` (rm -rf the install dir at [`install-cli.sh:458`](../install-cli.sh)) *before* `copy_cli_files` ([`install-cli.sh:504`](../install-cli.sh)). An interruption between the two leaves `$HOME/.manifest-cli/` wiped — every CLI artifact gone, no rollback. Brew avoids this by writing the new version to a versioned Cellar dir and only swapping symlinks on success; `install-cli.sh` has no equivalent. Spelled out as a tradeoff for headless/CI hosts that can't depend on brew: "If reliability is the priority for your machine: brew wins. If you want a fully scriptable, brew-free install for headless/CI hosts: install-cli.sh, but it needs the rm-then-copy made atomic (write to a sibling temp dir, then mv swap) — that's an item worth filing in the CLI tracker."
  - **Deliverable:** rewrite the install/upgrade flow to (a) populate a sibling staging dir alongside the install dir, (b) verify the staged tree (presence of entry points + module manifests), (c) swap dirs by `mv` rename (the wrapper at `$MANIFEST_CLI_BIN_DIR/manifest` is one file and can be swapped last for a brief atomic switch), (d) remove the prior install only on success. Add a fault-injection regression that kills the install partway through copy and asserts the prior install remains intact and the wrapper still runs.
  - **Anchor:** [`install-cli.sh`](../install-cli.sh) (`cleanup_old_installation`, `copy_cli_files`), [`modules/system/manifest-uninstall.sh`](../modules/system/manifest-uninstall.sh) (`uninstall_manifest`).

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
