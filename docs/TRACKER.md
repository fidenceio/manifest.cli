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

### T2 — contract integrity (8)

- §1.1 Halt clearly when fleet release requires PR review first
- §1.7 Single-flight lock for fleet apply
- §2.1 Shared apply-guard and replay-command helpers
- §2.2 Shared plan rendering and plan fingerprints
- §2.3 Execution-policy edge audit
- §2.8 Reconcile remaining `validation:` knobs with their gates
- §5.5 Pre-tag ship steps re-entrancy audit
- §5.6 Per-run ship logs for forensic replay

### T3 — coverage, audit, docs (9)

- §2.4 `MANIFEST_CLI_AUTO_CONFIRM` no-write regression
- §2.6 Local-only apply tests
- §2.7 Sensitive-value redaction audit across output surfaces
- §3.8 Cloud apply-intent contract stubs
- §4.1 Safe-by-default help/doc audit
- §4.3 Public-release migration note
- §4.4 Archive cleanup obeys the read-only archive rule
- §5.4 e2e coverage for brew-managed tap dir scenario
- §5.8 CLI apply-event audit log

### DEFER — post-enterprise (12)

- §1.3 Detect workspace/fleet membership drift
- §3.1–§3.7 Cloud handoff CLI side (gated by Cloud milestones)
- §4.2 Fish completions
- §5.1 Extract user global-config migration from `install-cli.sh`
- §5.2 `--json` for `refresh`/`ship`
- §5.3 Cached-timestamp precision label

§6 lists items explicitly cut (command-creep candidates) so they don't reappear by accident.

---

## 1. Fleet operations

- **1.1 Halt clearly when fleet release requires PR review first.**
  - **Status:** T2.
  - **Why:** fleet release should not silently skip PR-gated members. Silent skip leaves the fleet in an inconsistent state where some members shipped and others didn't.
  - **Deliverable:** fleet ship preview lists PR-gated members; apply refuses with a structured error and a `manifest pr fleet ... -y` replay command.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **1.3 Detect workspace/fleet membership drift.**
  - **Status:** DEFER (post-enterprise; read-only convenience).
  - **Why:** fleet config goes stale when repos are added outside Manifest.
  - **Deliverable:** read-only workspace diff that compares discovered repos to fleet config, exposed from a low-friction command such as `manifest doctor`, `manifest update fleet --dry-run`, or a timestamped passive check.
  - **Anchor:** [`modules/fleet/manifest-fleet-detect.sh`](../modules/fleet/manifest-fleet-detect.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **1.7 Single-flight lock for fleet apply.**
  - **Status:** T2.
  - **Why:** nothing currently prevents two concurrent `manifest ship fleet … -y` invocations on the same workspace. Two parallel runs would race on shared per-member state — VERSION bumps, tag creation, formula updates — and one run's writes would silently overwrite the other's, possibly creating divergent published artifacts. The risk is highest in CI/cron environments where re-trigger semantics aren't always idempotent, and grows linearly with fleet size.
  - **Deliverable:** acquire a workspace-scoped file lock at the start of any `ship fleet … -y` apply (path under `$HOME/.manifest-cli/locks/fleet-<workspace-hash>.lock`, owner-PID + start timestamp + invoking command recorded inside). Refuse with a structured error naming the holding PID, command, and start time when held. Release on normal exit, signal, or trap. Stale-lock detection by PID liveness. Preview mode (no `-y`) does not acquire the lock. Add a regression that starts a sleeping ship under a stub orchestrator, asserts a second concurrent apply is refused with the structured error, and asserts the lock releases on SIGTERM.
  - **Anchor:** [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh).

---

## 2. Execution policy & preview safety

The base contract is already live: mutating commands preview by default, `--dry-run` is explicit preview, `-y`/`--yes` selects apply, and contradictory `--dry-run` plus `-y` is rejected. Remaining work is consolidation and edge-case coverage.

- **2.1 Add shared apply-guard and replay-command helpers.**
  - **Status:** T2.
  - **Why:** call sites still build "preview or apply" branches and replay commands by hand. Every hand-built branch is a future drift site where the contract gets weakened silently. Also a hard dependency for §5.8 (audit emission lives in the apply-guard).
  - **Deliverable:** add `manifest_execution_require_apply` and `manifest_execution_replay_hint` in [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), migrate representative call sites, and cover them in tests.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **2.2 Add shared plan rendering and plan fingerprints.**
  - **Status:** T2.
  - **Why:** preview output is still bespoke per command, and apply mode cannot warn when the plan changed since preview. Plan fingerprint is also the audit primitive shared with [Cloud §3.4](../../fidenceio.manifest.cloud/docs/TRACKER.md#3-security--platform-m3-gate) and the input to CLI §5.8.
  - **Deliverable:** add a shared plan-table renderer plus a stable plan fingerprint helper; use them in ship/fleet/PR previews and compare fingerprints where apply recomputes work. Concrete content additions, surfaced by the 2026-05-19 fleet-ship trial:
    - a `Version` column showing `current → next` per member — required to disambiguate divergent SemVer trains (workspace `2.0.1 → 2.0.2` alongside cli `48.0.1 → 48.0.2`) before the user types `-y`;
    - a clearer preview exit-code convention so CI wrappers can distinguish "preview happened, no consent" from "applied successfully" (current behavior: both return 0).
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-plan.sh`](../modules/fleet/manifest-fleet-plan.sh), [`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh).

- **2.3 Finish the execution-policy edge audit.**
  - **Status:** T2.
  - **Why:** aliases, recursive Manifest calls, generated hooks, CI workflows, and unknown flag paths can still bypass the intended command surface if they are not checked together. Each unaudited path is a contract hole.
  - **Deliverable:** audit deprecated aliases, `scripts/`, generated hook templates, and `.github/workflows/*.yml`; route mutating calls through explicit `-y`, explicit `--dry-run`, or a shared rejection path. Centralize unknown flag handling where practical.
  - **Anchor:** [`modules/core/`](../modules/core/), [`scripts/`](../scripts/), [`.github/workflows/`](../.github/workflows/).

- **2.4 Add the missing `MANIFEST_CLI_AUTO_CONFIRM` no-write regression.**
  - **Status:** T3.
  - **Why:** code documents `MANIFEST_CLI_AUTO_CONFIRM=1` as prompt automation only, but the exact preview no-write regression should be explicit. Pins workspace cross-cut [§1.3](../../TRACKER.md#1-cross-cut-requirements) with a direct test.
  - **Deliverable:** test that a preview command with `MANIFEST_CLI_AUTO_CONFIRM=1` still writes nothing and prints an apply replay command instead of mutating.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`tests/dry_run.bats`](../tests/dry_run.bats).

- **2.6 Add focused local-only apply tests.**
  - **Status:** T3.
  - **Why:** `--local -y` is its own contract and should prove local writes occur without remote dispatch. Enterprise wants offline-safe boundaries that are tested, not asserted.
  - **Deliverable:** targeted tests for local-only ship/refresh/fleet paths, including assertions that no remote push/API command is called.
  - **Anchor:** [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **2.7 Sensitive-value redaction audit across CLI output surfaces.**
  - **Status:** T3.
  - **Why:** the Cloud side has [§3.5 no-plaintext logging](../../fidenceio.manifest.cloud/docs/TRACKER.md#3-security--platform-m3-gate); the CLI has no parallel audit. Enterprise customers will assume any `GITHUB_TOKEN`, `HOMEBREW_GITHUB_API_TOKEN`, bearer token, or other env-var-supplied secret cannot appear in stdout, stderr, `--verbose` output, `manifest doctor` output, or any captured log. Today this is asserted by convention, not by test — any single `printf "$value"` in an error path could leak.
  - **Deliverable:** sweep every output call site (printf/echo/error helpers/log helpers) for direct interpolation of env-sourced or config-sourced values that could be tokens or secrets; route through a shared redaction helper that recognizes token-shaped values, bearer-prefix tokens, secret-key patterns, and known env-var names. Add a regression that seeds fake-token-shaped values into the relevant env vars (`GITHUB_TOKEN`, `HOMEBREW_GITHUB_API_TOKEN`, etc.), exercises representative happy and error paths across ship/fleet/refresh/doctor, and asserts the fake tokens appear nowhere in captured stdout/stderr or per-run ship logs (see §5.6) or audit log (§5.8).
  - **Anchor:** [`modules/core/`](../modules/core/), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/system/`](../modules/system/).

- **2.8 Reconcile the remaining `validation:` knobs with their (missing) gates.**
  - **Status:** T2.
  - **Why:** the 2026-05-26 audit found the `validation:` block was mostly decorative. `require_expected_branch` and `allow_branch_operations` were fully inert and have been **removed** (no branch-workflow enforcement — that is left to the user). The other three knobs are still suspect: `require_clean_status`'s behavior is hardcoded-on in the apply path ([`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh) ~197) and flipping the flag changes nothing; `enforce_dependencies` and `strict` are reachable via `get_fleet_setting` short keys but no apply/preflight gate consumer was found. Config that advertises a guarantee the tool doesn't keep is a contract hole.
  - **Deliverable:** for each of `require_clean_status`, `enforce_dependencies`, `strict`, either wire it to a real gate (flag actually changes apply/preflight behavior, covered by a bats test) or remove it from the config + default heredoc — following the `require_expected_branch` removal precedent. Document the resulting honest contract.
  - **Anchor:** [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/fleet/manifest-fleet-config.sh`](../modules/fleet/manifest-fleet-config.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

---

## 3. Cloud handoff — CLI side

The local release-notes provider hook and recipe inspection surfaces exist. Remaining work is the Cloud-specific contract, payload policy, and end-to-end verification. **All §3 items except §3.8 are DEFER (post-enterprise)** — they activate as the Cloud-side milestones (M0–M3) land. Cloud is disabled by default per workspace cross-cut [§1.4](../../TRACKER.md#1-cross-cut-requirements), so the v1 enterprise CLI release can ship with these items pending.

- **3.1 Decide and document the CLI/Cloud contract source.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M0).
  - **Deliverable:** decide whether CLI stores copied schemas under `docs/contracts/` or references Cloud as source of truth; document Standard and Verbose payload expectations.
  - **Anchor:** [`docs/contracts/`](contracts/), [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **3.2 Complete the `cloud.*` YAML/env config surface.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M0).
  - **Deliverable:** add the remaining `cloud.{enabled,endpoint,release_notes.*,security.*}` mappings; keep Cloud disabled by default and secrets referenced by env name, not committed values.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`examples/manifest.config.yaml.example`](../examples/manifest.config.yaml.example), [`tests/yaml.bats`](../tests/yaml.bats).

- **3.3 Wire Cloud as a release-notes provider option.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M1/M3).
  - **Deliverable:** Cloud provider command selectable by config; local fallback preserved when optional; required mode aborts doc generation on failure; CLI remains owner of changelog writes.
  - **Anchor:** [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`tests/release_notes_provider.bats`](../tests/release_notes_provider.bats).

- **3.4 Add payload preview and privacy assertions.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M0/M3).
  - **Deliverable:** preview output shows Cloud mode, endpoint, fallback, identity, and upload decision; tests assert Standard mode excludes source bodies, raw diffs, raw commit bodies, author emails, full remotes, absolute paths, and secret-looking values.
  - **Anchor:** new `tests/cloud_payload.bats`, [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **3.5 Add Cloud handoff metadata to recipes.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M0/M2).
  - **Deliverable:** recipe schema accepts step `policy`/`privacy`/`fallback` metadata; ship recipes include a Cloud handoff step; `manifest ship repo patch --explain` shows Cloud status without uploading.
  - **Anchor:** [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`recipes/builtin/manifest.builtin.ship.repo.*.yaml`](../recipes/builtin/), [`tests/recipe.bats`](../tests/recipe.bats).

- **3.6 Finish CLI docs for Cloud handoff.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M0–M4 landing).
  - **Deliverable:** document Standard mode, Verbose mode, no-code default, fallback behavior, provider-hook integration, recipe-backed commands, and the Fidence platform assumption for production Cloud.
  - **Anchor:** [`README.md`](../README.md), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md), [`docs/INDEX.md`](INDEX.md).

- **3.7 Verify the Cloud handoff path in containers.**
  - **Status:** DEFER (post-enterprise; gated by Cloud M3).
  - **Deliverable:** `./scripts/run-tests-container.sh tests/yaml.bats tests/release_notes_provider.bats tests/docs_generation.bats tests/recipe.bats tests/cloud_payload.bats` passes; `manifest ship repo patch --explain` works without GitHub or Cloud; full container suite is green.
  - **Anchor:** [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

- **3.8 Add Cloud apply-intent contract stubs.**
  - **Status:** T3.
  - **Why:** Cloud-backed mutation must fail closed when `execution_mode=apply` is missing. Enforcing this on the local stub now means that whenever §3.3 wires real Cloud calls, the contract is already pinned. Mirrors workspace cross-cut [§1.1](../../TRACKER.md#1-cross-cut-requirements).
  - **Deliverable:** local stub test that rejects a Cloud request missing apply intent before any provider or analyzer runs.
  - **Anchor:** [`modules/stubs/manifest-cloud-stub.sh`](../modules/stubs/manifest-cloud-stub.sh), new `tests/cloud_contract.bats`.

---

## 4. Docs & completions

- **4.1 Finish safe-by-default help/doc audit.**
  - **Status:** T3.
  - **Why:** user-facing docs and bash/zsh completions already describe most of the contract, but command help can still drift. Help text and examples are part of the contract surface — wrong examples teach the wrong reflex.
  - **Deliverable:** audit mutating command help examples so preview examples are bare commands and apply examples include `-y`; add tests where practical.
  - **Anchor:** [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md).

- **4.2 Add fish-shell completions.**
  - **Status:** DEFER (post-enterprise).
  - **Why:** bash and zsh completions ship; fish remains missing. Fish users can use the CLI fine without; no contract surface.
  - **Deliverable:** `completions/manifest.fish` plus install instructions in `completions/README.md`.
  - **Anchor:** [`completions/`](../completions/), [`tests/completions.bats`](../tests/completions.bats).

- **4.3 Write the public-release migration note.**
  - **Status:** T3 — user-guide half landed (`docs/USER_GUIDE.md` "Migrating to safe-by-default"); release-docs/`MIGRATION.md` copy still pending.
  - **Why:** users upgrading from pre-safe-by-default releases need a concise explanation of preview default, `-y` apply, and `MANIFEST_CLI_AUTO_CONFIRM` semantics. Mirrors workspace [§2.1](../../TRACKER.md#2-workspace-level-open-items).
  - **Deliverable:** migration copy in release docs or `docs/MIGRATION.md`, with matching language in the user guide before the next major release.
  - **Anchor:** [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md).

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

- **5.2 Add `--json` summaries to `refresh` and `ship`.**
  - **Status:** DEFER (post-enterprise; revisit when CI/automation integration becomes a tier-1 customer ask).
  - **Why:** `status` and `config list` have JSON, but streaming side-effect commands need structured step-result plumbing first.
  - **Deliverable:** orchestrator emits a structured per-step result object; `--json` on `refresh` and `ship` serializes the final summary.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-refresh.sh`](../modules/core/manifest-refresh.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **5.3 Stop reporting bogus precision on cached trusted timestamps.**
  - **Status:** DEFER (post-enterprise; cosmetic).
  - **Why:** fleet ship output reads `Trusted timestamp ±0.000000` for cached values across all members within seconds of each other. The `±0.000000` is technically the cache's confidence-of-itself, but reads as "we measured to sub-microsecond precision" — confusing for anyone auditing release timing. Observed 2026-05-19 across 4 members.
  - **Deliverable:** when emitting a cached timestamp, label it as `cached (from <source> at <time>)` and drop the precision figure, OR report the original measurement's confidence rather than zero. Add a regression covering the cached-emit path.
  - **Anchor:** [`modules/system/manifest-time.sh`](../modules/system/manifest-time.sh).

- **5.4 Add e2e coverage for the brew-managed tap dir scenario.**
  - **Status:** T3.
  - **Why:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats) now stubs `brew` in `setup()` to isolate the fixture, which is correct for that file but means the brew-managed candidate path — `$(brew --prefix)/Library/Taps/fidenceio/homebrew-tap`, returned by [`manifest_homebrew_tap_checkout_candidates`](../modules/core/manifest-core.sh) — is no longer exercised by any test. In production this path runs on every `manifest refresh` and during ship's post-push auto-upgrade (orchestrator → `manifest_ship_restore_tap_ssh_origin`). A regression in the candidate generator or the refresher's iteration over the brew-managed dir would not be caught.
  - **Deliverable:** a new test file (suggested: `tests/homebrew_tap_refresh_brew_dir.bats`) that isolates `$HOME`, stubs `brew --prefix` to a scratch dir containing a seeded `Library/Taps/fidenceio/homebrew-tap` checkout (matching the pattern in [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats)), and exercises the refresher with both candidates present. Assertions cover correct fast-forward of both, correct skip of dirty/divergent, and the strict count summary.
  - **Anchor:** [`tests/homebrew_tap_refresh.bats`](../tests/homebrew_tap_refresh.bats), [`tests/homebrew_tap_ssh_restore.bats`](../tests/homebrew_tap_ssh_restore.bats), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh) (`manifest_homebrew_tap_checkout_candidates`, `manifest_refresh_homebrew_tap_checkouts`), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh) (`manifest_ship_post_push_steps`, `manifest_ship_restore_tap_ssh_origin`).

- **5.5 Audit pre-tag ship steps for re-entrancy.**
  - **Status:** T2.
  - **Why:** `manifest_ship_repo_resume` only re-enters at the push step ([`manifest-orchestrator.sh:460`](../modules/workflow/manifest-orchestrator.sh)). The pre-tag pipeline (version bump → docs/release notes → archive → commit) is non-resumable: an interruption between bump and commit leaves the repo with a half-applied state (VERSION bumped but uncommitted, generated docs on disk, no tag) and the user must manually undo before retrying. For 30+ repos shipping, the probability of mid-pre-tag interruption is meaningful; the cost is manual recovery per member.
  - **Deliverable:** for each pre-tag step (version bump, docs generation, archive moves, commit), document the partial-state-detection rule and add a "re-running on already-applied state is a no-op" regression. Where idempotency requires a marker, prefer reading git state over writing a sidecar file.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/docs/manifest-cleanup-docs.sh`](../modules/docs/manifest-cleanup-docs.sh), [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh).

- **5.6 Capture per-run ship logs for forensic replay.**
  - **Status:** T2.
  - **Why:** when a ship leaves the install or repo in an unexpected state (observed 2026-05-21: `$HOME/.manifest-cli/` payload empty after an interrupted run, with no record of which step ran or where the failure occurred), diagnosis falls back to guesswork from `git log` + `brew Cellar` timestamps. A timestamped per-run log would convert these incidents from "best-guess narrative" to "read the file." Note: §5.6 is *diagnostic* logging (what happened, for debug); structured audit events (who-authorized-what-when, for compliance) are §5.8.
  - **Deliverable:** ship writes a per-run log to `$HOME/.manifest-cli/logs/ship-<ts>.log` capturing each step boundary, exit status, and any captured stderr; resume reads the prior log when reporting "picking up from step X." Add log rotation (keep last N runs) tied to a TTL marker. The log path must NOT fall under [`manifest_install_paths_cache_dirs`](../modules/system/manifest-install-paths.sh) — diagnostic logs are not transient and must not be swept.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh), [`modules/system/manifest-runtime-cleanup.sh`](../modules/system/manifest-runtime-cleanup.sh).

- **5.8 CLI apply-event audit log.**
  - **Status:** T3.
  - **Why:** workspace cross-cut [§1.2](../../TRACKER.md#1-cross-cut-requirements) requires every apply request to emit an audit event with actor id, source, command, scope, and plan hash. The Cloud side owns this for Cloud-routed apply requests via [Cloud §3.4](../../fidenceio.manifest.cloud/docs/TRACKER.md#3-security--platform-m3-gate); CLI-local apply requests (the dominant case today: `manifest ship repo … -y`, `manifest ship fleet … -y`, `manifest pr … -y`) currently emit nothing structured. Per-run diagnostic logs (§5.6) are the *what-happened-for-debug* record; audit events are the *who-authorized-what-when* record. Enterprise compliance demands both, kept separate so retention/access policy can differ.
  - **Deliverable:** add an append-only audit log at `$HOME/.manifest-cli/audit/apply-events.ndjson`, one NDJSON event per apply, recording: ISO-8601 timestamp, actor id (`$USER` plus optional `MANIFEST_CLI_ACTOR` override), source (`cli` / `cli-fleet` / `cli-pr` / future `mcp`), command, scope (repo path or fleet members), plan hash (from §2.2 fingerprint helper — hard dependency), and exit status. Emission lives in the apply-guard helper (§2.1) so every `-y`-gated path emits exactly once. Add a regression that runs a fleet apply, asserts one event per member with matching plan hashes and a coherent timestamp ordering. The audit log path, like §5.6 diagnostic logs, must NOT fall under [`manifest_install_paths_cache_dirs`](../modules/system/manifest-install-paths.sh).
  - **Depends on:** §2.1 (apply-guard helper) and §2.2 (plan fingerprint). Land both before §5.8.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh).

---

## 6. Explicitly out of scope

Items considered during the 2026-05-22 enterprise-readiness triage and cut. Listed here so they don't reappear by accident; if a future requirement changes the reasoning, file a new item rather than reviving a cut entry verbatim.

- **6.1 Fleet-service config editor (formerly §1.4).**
  - **Cut reason:** command creep. `manifest.fleet.config.yaml` is the source of truth for `services.<name>.release.enabled` and `services.<name>.release.strategy`; the file is human-editable and schema-validated on load. Adding a CLI subcommand that wraps `vim` of a transparent YAML file introduces a new validation surface, a new bug surface, and a new test surface in exchange for keystrokes that don't reduce risk.
  - **Original deliverable (kept for provenance):** add a safe-by-default command, final name TBD, for scoped fleet-service config edits such as enabling/disabling release and setting release strategy.

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
