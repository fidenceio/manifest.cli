# Manifest CLI — Tracker

Open work for the Manifest CLI repo. Closed items and historical findings live in [`zArchive/trackers/`](zArchive/trackers/).

## Conventions

- Items are grouped by area, not by tier or session.
- Every item names a concrete deliverable (file, test, module) and an anchor.
- Drift policy: when an item ships, delete it from this file. Provenance lives in the merge commit.

---

## 1. Execution policy — helpers and adoption gaps

The shared contract (`preview` default, `--dry-run` explicit, `-y`/`--yes` to apply, contradictory-flags detection) is already enforced in [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh) and adopted at 25+ call sites across `init`, `prep`, `refresh`, `ship`, `fleet`, `pr`, `config`, and `core`. What remains is the helper surface and the last edge commands.

- **1.1 `manifest_execution_require_apply` helper.**
  - **Why:** every command currently re-implements the "preview-or-apply" branch inline. A single guard would let new commands opt in without re-introducing ad-hoc parsing.
  - **Deliverable:** function in [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh) that returns non-zero in preview mode with the standard "Re-run with -y" footer; bats coverage in `tests/execution_policy.bats`.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

- **1.2 `manifest_execution_replay_hint` helper.**
  - **Why:** `manifest_execution_footer` accepts a single apply-command string, but call sites assemble it inline. A helper that takes the original argv and emits the exact replay command — including `-y`, original subcommand path, and preserved flags — is the missing piece for L243 (preserve original user command) and L313 (end every preview with the exact replay command).
  - **Deliverable:** helper that captures `$0 "$@"` at command-dispatch entry, strips flags via `manifest_execution_strip_apply_flags`, re-appends `-y`, returns the string.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **1.3 `manifest_execution_plan_table` renderer.**
  - **Why:** preview output today is bespoke per command. A shared renderer is the foundation for the consistent `Effect | Scope | Apply command` columns called for in L305/L315/L327.
  - **Deliverable:** function that takes step rows and emits a uniform Markdown table; consumers in `ship`, `fleet`, `pr`, and Cloud-backed previews.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

- **1.4 Plan-fingerprint helper.**
  - **Why:** L244 calls for a hash so apply-time recomputation can warn if the plan changed since preview.
  - **Deliverable:** stable hash over the rendered plan (sha256 over canonicalized step rows); store alongside the preview, compare on apply.
  - **Anchor:** new helper next to `manifest_execution_plan_table`.

- **1.5 Unknown / misplaced execution flags fail through the shared help template.**
  - **Why:** L241 — today, an unknown flag may silently survive parsing.
  - **Deliverable:** common error path in `manifest_execution_parse` for unknown tokens that look like flags (`^-`); test in `tests/execution_policy.bats`.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

- **1.6 Legacy `--apply` / `--do` decision.**
  - **Why:** L223 — accept as deprecated aliases or reject outright. Either is fine; what's not fine is leaving it undecided.
  - **Deliverable:** decision recorded in this tracker as a one-line resolution, plus the chosen implementation (rejected-with-message vs alias-with-deprecation-warning).
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

- **1.7 `--force` stays separate from `-y`.**
  - **Why:** L64 — `--force` may bypass a readiness gate only after `-y` has selected apply mode.
  - **Deliverable:** in commands that accept `--force`, require apply mode before `--force` has effect; test that `--force` alone never mutates.
  - **Anchor:** call sites of `--force` (grep `--force` under `modules/`).

- **1.8 `MANIFEST_CLI_AUTO_CONFIRM=1` stays prompt-automation only.**
  - **Why:** L65, L240 — must not convert preview mode into apply mode.
  - **Deliverable:** explicit test in `tests/execution_policy.bats` proving preview + `AUTO_CONFIRM=1` does not write.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

- **1.9 Audit legacy aliases and deprecation paths.**
  - **Why:** L259 — aliases must inherit the same execution policy; otherwise they're a back door.
  - **Deliverable:** find every deprecation alias (`grep -rn "deprecated alias" modules/`); confirm it routes through `manifest_execution_parse` or rejects explicitly.
  - **Anchor:** [`modules/core/`](../modules/core/).

- **1.10 Audit recursive Manifest calls and generated hooks.**
  - **Why:** L260 — scripts that call Manifest must add explicit `-y` only where apply is intended; today some pre-existing hooks may not.
  - **Deliverable:** grep `scripts/` and any generated hook templates for `manifest` invocations; annotate or fix each.
  - **Anchor:** [`scripts/`](../scripts/).

- **1.11 Audit CI workflows for unintended apply.**
  - **Why:** L261 — release automation that currently calls mutating commands without `-y` will now no-op silently. Either add `-y` (apply intent) or switch to `--dry-run` (preview).
  - **Deliverable:** review `.github/workflows/*.yml` for `manifest <verb>` calls; pick the right intent per call.
  - **Anchor:** [`.github/workflows/`](../.github/workflows/).

---

## 2. Plan-then-apply renderer

Currently preview output is bespoke per command. The shared renderer (item 1.3) feeds this work.

- **2.1 Standardize preview output heading.**
  - **Why:** L305 — every mutating command should open with a recognizable banner so users can tell preview from apply at a glance.
  - **Deliverable:** `manifest_execution_preview_header` is already wired; audit each command's first output line to use it.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh:75-78`](../modules/core/manifest-execution-policy.sh#L75-L78).

- **2.2 Apply mode prints the same plan first, then the apply banner.**
  - **Why:** L314 — apply runs should produce identical plan output to preview, so users can diff if needed.
  - **Deliverable:** restructure ship/fleet/pr apply paths so plan rendering precedes mutation; reuse the renderer from 1.3.
  - **Anchor:** [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh).

- **2.3 Dense, scannable preview tables for fleet commands.**
  - **Why:** L315 — current fleet previews dump one section per member; a table is faster to scan when ≥5 members.
  - **Deliverable:** fleet preview output uses the shared `manifest_execution_plan_table`.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **2.4 Effect / Scope / Apply-command columns in plan tables.**
  - **Why:** L327 — these three columns turn "preview" into a contract the user can verify.
  - **Deliverable:** renderer from 1.3 emits these columns where step rows carry effect metadata (already populated by recipe schema work).
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

---

## 3. Fleet UX

- **3.1 Stop with a clear message when fleet requires PR review first.**
  - **Why:** L279 — today `ship fleet` silently skips PR-gated members. The user should see "X members require PR review; run `manifest pr fleet ... -y` first."
  - **Deliverable:** fleet ship preview lists PR-gated members; apply mode refuses with a structured error and replay command.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.2 Fleet partial-failure recovery output.**
  - **Why:** L280 — when a multi-member apply fails mid-fleet, the user has no way to resume from where it stopped.
  - **Deliverable:** structured failure report listing which members completed, which failed, and a `--resume` flag or per-member replay command.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.3 Recompute fleet plan at apply time and warn on diff.**
  - **Why:** L281 — preview is point-in-time; if a member's state changes between preview and apply (e.g., new commits), the user should be warned.
  - **Deliverable:** apply path recomputes the plan, compares fingerprint (item 1.4), prints diff or "plan unchanged".
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.4 Fleet background-scan: detect new repos in the workspace.**
  - **Why:** fleet membership goes stale silently when new repos appear in the workspace. A passive scan that detects divergence between workspace state and fleet config (and prompts the user to refresh) would close the gap. Raised 2026-05-05; previously held as a feature-radar idea — now formalized.
  - **Deliverable:** a reusable read-only `_fleet_diff_workspace` function in [`modules/fleet/manifest-fleet-detect.sh`](../modules/fleet/manifest-fleet-detect.sh) that prints a diff; a hook invocation point (one of: shell-entry hook, `manifest doctor` check, or periodic timestamp file in `~/.manifest/state/`). Surface a prompt; do not auto-modify config.
  - **Anchor:** [`modules/fleet/manifest-fleet-detect.sh`](../modules/fleet/manifest-fleet-detect.sh).

- **3.5 Path and fleet-member selectors for repo-root confirmation.**
  - **Why:** carried forward from the closed #44 — today repo-scoped apply commands confirm against the cwd-resolved Git root only; path-based and fleet-member selectors were deferred from that change.
  - **Deliverable:** repo-scoped apply commands accept `--path <dir>` and `--member <name>` and confirm against the resolved target.
  - **Anchor:** [`modules/core/manifest-init.sh`](../modules/core/manifest-init.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **3.6 Fleet service-releaseability model in fleet config.**
  - **Why:** L67 — today releaseability is inferred from file presence (`VERSION` etc.) over time. Explicit per-service config is more honest.
  - **Deliverable:** `services.<name>.release.{enabled,strategy}` in fleet config (already partially live for top-level); per-service test in `tests/fleet_release_config.bats`.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.7 `manifest select repo` for fleet-service config edits.**
  - **Why:** today, toggling `services.<name>.release.{enabled,strategy}` (or any other per-service setting in `manifest.fleet.config.yaml`) requires hand-editing the YAML. `manifest config set` only reaches `manifest.config.yaml` keys; `manifest init fleet` is a regenerate-from-TSV flow. Surfaced 2026-05-15 when enabling release on the marketing-site service required an editor.
  - **Deliverable:** `manifest select repo [<service>] [--enable-release|--disable-release] [--strategy <s>] [-y|--dry-run]` (or equivalent flag set); interactive TTY picker when service omitted; safe-by-default preview; writes scoped to `manifest.fleet.config.yaml`. Final command name TBD — `select repo` is the user-proposed shape; alternatives are `fleet set <service>.<key> <value>` or `fleet edit <service>`.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.8 Replace per-repo TTY-only confirmation with fleet-context implicit confirm.**
  - **Why:** `manifest_repo_scope_confirm_apply` hard-checks `[[ -t 0 ]]` then `read`s, blocking any non-interactive shell even when fleet config already disambiguates the target repo. Workaround landed 2026-05-16: the function now honors `MANIFEST_CLI_AUTO_CONFIRM=1` and skips the prompt (apply is still gated by `-y` upstream). The long-term fix is a fleet-context bypass that doesn't require a blanket env var — same shape as §3.5 (path/member selectors).
  - **Deliverable:** add an internal flag to `manifest_repo_scope_confirm_apply` ("called from fleet dispatch") that the fleet ship pipeline sets; tests prove the flag is only honored when fleet context is present.
  - **Anchor:** [`modules/core/manifest-shared-utils.sh:453-506`](../modules/core/manifest-shared-utils.sh#L453-L506), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

---

## 4. Tests

- **4.1 No-write tests per preview path.**
  - **Why:** L333 — the safest proof of "preview by default" is a git porcelain + file snapshot before and after every preview run.
  - **Deliverable:** parametrized bats helper that asserts no porcelain change for each mutating command in preview mode.
  - **Anchor:** new `tests/preview_no_write.bats`.

- **4.2 Apply tests for focused local-only commands.**
  - **Why:** L334 — `--local -y` is its own contract and needs targeted coverage.
  - **Deliverable:** bats cases asserting local writes happen and remote dispatch does not.
  - **Anchor:** new `tests/local_only_apply.bats`.

- **4.3 `MANIFEST_CLI_AUTO_CONFIRM=1` does-not-imply-apply tests.**
  - **Why:** L336 — already implemented in code but untested.
  - **Deliverable:** cases in `tests/execution_policy.bats`.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh).

- **4.4 PR commands require `-y` to mutate.**
  - **Why:** L338 — PR-side tests confirming preview-default holds end-to-end (parsing already enforces it; missing the integration test).
  - **Deliverable:** `tests/pr_native_dry_run.bats` covering each PR verb.
  - **Anchor:** [`modules/pr/manifest-pr-native.sh`](../modules/pr/manifest-pr-native.sh).

- **4.5 Docs / completion tests for `-y`, `--yes`, and `--dry-run`.**
  - **Why:** L340 — drift between command surface and completions/help is a recurring user-confusion source.
  - **Deliverable:** test that for every mutating command, completions list `-y`/`--yes`/`--dry-run` and help mentions them.
  - **Anchor:** [`completions/`](../completions/), [`tests/completions.bats`](../tests/completions.bats).

- **4.6 Cloud contract stubs prove missing apply intent is rejected.**
  - **Why:** L343 — even before Cloud ships, the CLI should have a stub test proving that a contract-violating request fails fast.
  - **Deliverable:** test that posts a request missing `execution_mode=apply` against a local stub and asserts rejection.
  - **Anchor:** new `tests/cloud_contract.bats`.

- **4.7 Run targeted + full container suite after each policy phase.**
  - **Why:** L341–L342 — multi-phase rollout needs gates between phases.
  - **Deliverable:** running `./scripts/run-tests-container.sh` after each item in §1–§3 lands.
  - **Anchor:** [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

---

## 5. Docs surface

- **5.1 "Safe by default" section in user-facing docs.**
  - **Why:** L316 — the contract is invisible until users hit it.
  - **Deliverable:** new short section in [`README.md`](../README.md), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md) — same wording everywhere.
  - **Anchor:** [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **5.2 Help-example updates.**
  - **Why:** L318 — bare-command examples in help text should preview, applied examples should include `-y`. Today some still flip this.
  - **Deliverable:** audit `--help` output for every mutating command.
  - **Anchor:** dispatcher in [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **5.3 Shell completions for `-y`, `--yes`, `--dry-run`.**
  - **Why:** L317 — every mutating command needs these completions.
  - **Deliverable:** updates to [`completions/manifest.bash`](../completions/manifest.bash) and [`completions/_manifest`](../completions/_manifest); fish-shell support also lands here (#20 follow-up).
  - **Anchor:** [`completions/`](../completions/).

- **5.4 Migration note for pre-change users.**
  - **Why:** L320 — users upgrading from a pre-`-y` build will be surprised by the new preview default.
  - **Deliverable:** one short paragraph in the next major release notes plus a `docs/MIGRATION.md` (if patterns repeat).
  - **Anchor:** [`docs/USER_GUIDE.md`](USER_GUIDE.md).

---

## 6. Cross-cut to Cloud (CLI side)

Lifted from the archived workspace cloud-implementation tracker (A-track). The Cloud side lives in [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md); the workspace-level milestones gate both sides at [`../../TRACKER.md`](../../TRACKER.md).

- **6.1 A0 — Contract awareness.**
  - **Deliverable:** decide whether CLI stores copied release-notes schemas under `docs/contracts/` or references Cloud as the source of truth; document Standard and Verbose payload expectations; confirm the current release-notes provider request file contains enough metadata for Standard mode.
  - **Anchor:** [`docs/contracts/`](contracts/) (if path taken).

- **6.2 A1 — YAML and env config for `cloud.*`.**
  - **Deliverable:** add `cloud.{enabled,endpoint,release_notes.*,security.*}` YAML keys with env mappings (`MANIFEST_CLI_CLOUD_*`); defaults keep Cloud disabled; secrets referenced via env, not committed.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`examples/manifest.config.yaml.example`](../examples/manifest.config.yaml.example).

- **6.3 A2 — Provider hook integration with Cloud.**
  - **Deliverable:** Cloud provider command selectable via config; local fallback preserved when provider absent/unavailable/invalid; abort doc generation when `fallback: fail`; Cloud returns candidates only, CLI owns changelog writes.
  - **Anchor:** [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`tests/release_notes_provider.bats`](../tests/release_notes_provider.bats).

- **6.4 A3 — Payload preview and privacy policy.**
  - **Deliverable:** preview output for Cloud payload mode, identity, fallback, endpoint, and upload decision; reject `http://` endpoints unless local override is enabled; assert Standard mode excludes source bodies, raw diffs, raw commit bodies, author emails, full remotes, local absolute paths, and secret-looking values.
  - **Anchor:** new `tests/cloud_payload.bats`; [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **6.5 A4 — Recipe integration.**
  - **Deliverable:** recipe schema accepts step `policy`/`privacy`/`fallback` metadata; Cloud handoff step added to ship recipes; `manifest ship repo patch --explain` shows Cloud handoff mode without uploading.
  - **Anchor:** [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`recipes/builtin/manifest.builtin.ship.repo.*.yaml`](../recipes/builtin/).

- **6.6 A5 — CLI documentation for Cloud handoff.**
  - **Deliverable:** Standard mode, Verbose mode, no-code default, fallback behavior, provider-hook integration, recipe-backed first-class commands, and the Fidence platform assumption for production Cloud documented in `README`, `USER_GUIDE`, `COMMAND_REFERENCE`, `EXAMPLES`, `INDEX`.
  - **Anchor:** [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **6.7 A6 — CLI verification.**
  - **Deliverable:** `./scripts/run-tests-container.sh tests/yaml.bats tests/release_notes_provider.bats tests/docs_generation.bats tests/recipe.bats tests/cloud_payload.bats` passes; `manifest ship repo patch --explain` works without GitHub or Cloud; full container suite green.
  - **Anchor:** [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

---

## 7. Follow-ups from closed work

Carried forward from individual closed items in the archived [`IMPROVEMENT_TRACKER.md`](zArchive/trackers/IMPROVEMENT_TRACKER.md). Each is genuinely open.

- **7.1 Extract `migrate_user_global_configuration` from [`install-cli.sh`](../install-cli.sh).**
  - **Why:** #11 hit 919 lines vs. an aspirational 500; extracting this single function is the next structural step. Current size: 1209 lines.
  - **Deliverable:** new `scripts/migrate-user-config.sh`; `install-cli.sh` delegates.
  - **Anchor:** [`install-cli.sh`](../install-cli.sh).

- **7.2 `--json` on `refresh` and `ship` summaries.**
  - **Why:** #19 follow-up — `status` and `config list` ship `--json`; streaming side-effect operations need orchestrator step-result plumbing.
  - **Deliverable:** orchestrator emits a structured per-step result object; `--json` flag on `refresh` and `ship` serializes the summary at the end.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh).

- **7.3 Relocate `manifest_ship_workflow` into [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).**
  - **Why:** #2 follow-up — the rename landed in place with a back-compat shim at [`modules/workflow/manifest-orchestrator.sh:906-907`](../modules/workflow/manifest-orchestrator.sh#L906-L907); relocation was deferred because the orchestrator file holds more than just the entry point.
  - **Deliverable:** move the function body to `manifest-ship.sh`; keep the shim or remove it after grepping for external callers.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh).

- **7.4 Fish-shell completions.**
  - **Why:** #20 — `bash` and `zsh` ship; fish is the remaining gap.
  - **Deliverable:** `completions/manifest.fish`; install instructions in [`completions/README.md`](../completions/README.md).
  - **Anchor:** [`completions/`](../completions/).

- **7.5 Conditional: extract duplicated wrapper guard.**
  - **Why:** the only open item from the archived [`BASH_5_RUNTIME_TODO.md`](zArchive/trackers/BASH_5_RUNTIME_TODO.md). The current fix keeps the small wrapper snippets aligned and tested without a new bootstrap dependency; only worth doing if drift recurs.
  - **Deliverable:** generate or share the guard from one source. **Trigger:** wrapper drift detected in a future ship.
  - **Anchor:** [`scripts/manifest-cli.sh`](../scripts/manifest-cli.sh), [`scripts/manifest-cli-wrapper.sh`](../scripts/manifest-cli-wrapper.sh), [`formula/manifest.rb`](../formula/manifest.rb).

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
- Archived legacy trackers: [`zArchive/trackers/`](zArchive/trackers/)
