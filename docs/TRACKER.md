# Manifest CLI - Tracker

Open work for the Manifest CLI repo.

## Conventions

- Items are grouped by area, not by tier or session.
- Every item names a concrete deliverable and an anchor.
- Drift policy: when an item ships, delete it from this file. Provenance lives in the merge commit and release history.

---

## 1. Release Correctness

- **1.1 Eliminate the ship workflow's version double-cycle.**
  - **Why:** every canonical CLI `manifest ship repo minor|major|revision` currently runs the intended release, updates the in-repo Homebrew formula, then treats that formula commit as new work for a follow-up patch. Observed 2026-05-16: `47.13.0 -> 47.13.1` and `47.14.0 -> 47.14.1`.
  - **Deliverable:** choose and implement one policy: fold the formula update into the same release commit, or classify formula-only changes as non-shippable for the follow-up patch. Add a regression proving one canonical ship produces one release tag.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`formula/manifest.rb`](../formula/manifest.rb), [`tests/ship_resume.bats`](../tests/ship_resume.bats).

- **1.2 Make archive cleanup obey the read-only archive rule.**
  - **Why:** archive cleanup still creates `docs/zArchive/v<major>/` directories and regenerates archive `INDEX.md` files. The active rule is: moved files only; no new generated output inside the archive.
  - **Deliverable:** flatten future archive moves into `docs/zArchive/`, remove archive index generation and its call sites, and add a regression proving cleanup moves files without creating archive-side generated files.
  - **Anchor:** [`modules/docs/manifest-cleanup-docs.sh`](../modules/docs/manifest-cleanup-docs.sh), [`tests/archive_move_log.bats`](../tests/archive_move_log.bats), [`tests/archive_pre_move_safety.bats`](../tests/archive_pre_move_safety.bats).

- **1.4 Stop `brew install manifest` from triggering a `Tapping homebrew/core` step.**
  - **Why:** observed 2026-05-17 on a modern Homebrew install with JSON API enabled: `brew tap fidenceio/tap && brew install manifest` taps cleanly, then forces `==> Tapping homebrew/core` which fails to clone (permissions on `/opt/homebrew/Library/Taps/homebrew/homebrew-core`). Modern Homebrew should resolve our `depends_on "bash"`, `git`, `yq`, `coreutils` via the JSON API without ever cloning homebrew/core. Some property of our formula or install path forces the legacy core-tap clone path. Result: end-to-end canonical install is currently broken on this host even after the right `brew tap` + `brew install`.
  - **Deliverable:** identify the trigger (formula attribute, post-install command, dependency declaration, or something Manifest is setting in the brew environment) and either remove the trigger or document the required user env so the JSON API path is used. Add a container or CI check that `brew install fidenceio/tap/manifest` completes without `Tapping homebrew/core`.
  - **Anchor:** [`formula/manifest.rb`](../formula/manifest.rb), any post-install hook touched by the formula.

- **1.5 Stop fleet ship from silently sweeping dirty trees into release commits.**
  - **Why:** observed 2026-05-19 fleet ship at `v48.0.1 → 48.0.2`: the cli repo had 1 modified + 3 untracked files unrelated to the release. Preview did not flag them. Apply created an `Auto-commit before Manifest process (4 files: install-cli.sh, ...)` commit ahead of the release commit, wrapping unrelated changes into the release without prompting. Memory note: `feedback_fleet_consent_model` says "scope block = notice, `-y` = consent" — silently auto-committing unrelated dirt exceeds the scope of that consent.
  - **Deliverable:** preview shows a `dirty: N modified, M untracked` column per member when dirty; apply either (a) refuses with a structured error and a `--include-dirty` opt-in flag, or (b) prints `Auto-committing N uncommitted/untracked files into release commit on <repo>` before the auto-commit fires. Add a regression where a fleet member with dirty state runs through `manifest ship fleet patch -y` and asserts the chosen behavior.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/git/manifest-git-changes.sh`](../modules/git/manifest-git-changes.sh), [`modules/fleet/manifest-fleet-plan.sh`](../modules/fleet/manifest-fleet-plan.sh), [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh).

- **1.6 Harden cli self-modification during fleet ship.**
  - **Why:** when `manifest ship fleet` includes the cli repo, the running `manifest` binary is shipping itself. If the formula push succeeds and brew is triggered (or a user runs `brew upgrade` mid-flight), `/opt/homebrew/bin/manifest` (a symlink into `Cellar/manifest/<old>/bin/manifest`) can be replaced or its Cellar dir removed while the orchestrator is still source'ing scripts. Today's run (2026-05-19) only avoided this because the tap push failed (§1.3) before brew could upgrade — the failure window is the only thing currently protecting against mid-script binary replacement.
  - **Deliverable:** on ship entry, when the running process is itself the binary being shipped, snapshot the script tree to a tmpdir and `exec` into the snapshot so the live process is decoupled from the install location. Alternatively, defer any local-upgrade step to a post-orchestrator hook that fires after the orchestrator process has exited. Add a regression that simulates `brew upgrade manifest` mid-ship and asserts the orchestrator completes cleanly.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`scripts/manifest-cli-wrapper.sh`](../scripts/manifest-cli-wrapper.sh), [`modules/system/manifest-install-paths.sh`](../modules/system/manifest-install-paths.sh).

---

## 2. Execution Policy Cleanup

The base contract is already live: mutating commands preview by default, `--dry-run` is explicit preview, `-y`/`--yes` selects apply, and contradictory `--dry-run` plus `-y` is rejected. Remaining work is consolidation and edge-case coverage.

- **2.1 Add shared apply guard and replay-command helpers.**
  - **Why:** call sites still build "preview or apply" branches and replay commands by hand.
  - **Deliverable:** add `manifest_execution_require_apply` and `manifest_execution_replay_hint` in [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), migrate representative call sites, and cover them in tests.
  - **Anchor:** [`modules/core/manifest-execution-policy.sh`](../modules/core/manifest-execution-policy.sh), [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh).

- **2.2 Add shared plan rendering and plan fingerprints.**
  - **Why:** preview output is still bespoke per command, and apply mode cannot warn when the plan changed since preview.
  - **Deliverable:** add a shared plan-table renderer plus a stable plan fingerprint helper; use them in ship/fleet/PR previews and compare fingerprints where apply recomputes work. Concrete content additions, surfaced by the 2026-05-19 fleet-ship trial:
    - a `Version` column showing `current → next` per member — required to disambiguate divergent SemVer trains (workspace `2.0.1 → 2.0.2` alongside cli `48.0.1 → 48.0.2`) before the user types `-y`;
    - a dirty-tree disclosure (see §1.5) inline in the plan table, not as a separate scan;
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

---

## 3. Fleet UX

- **3.1 Stop clearly when fleet release requires PR review first.**
  - **Why:** fleet release should not silently skip PR-gated members.
  - **Deliverable:** fleet ship preview lists PR-gated members; apply refuses with a structured error and a `manifest pr fleet ... -y` replay command.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.2 Add fleet partial-failure recovery output.**
  - **Why:** when a fleet apply fails mid-run, users need a precise resume or replay path.
  - **Deliverable:** structured report listing completed members, failed members, skipped members, and per-member replay or resume commands. Must specifically cover the **"release tagged + code pushed + formula push failed"** state observed 2026-05-19: the current recovery banner suggests tag-delete and hard-reset, but the tag and release commit are already on `origin/main` — the correct remediation is "release is live, formula stale; retry the tap push" (e.g., `manifest ship --resume-formula`), not a rollback that would orphan a published tag.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-apply.sh`](../modules/fleet/manifest-fleet-apply.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **3.3 Detect workspace/fleet membership drift.**
  - **Why:** fleet config goes stale when repos are added outside Manifest.
  - **Deliverable:** read-only workspace diff that compares discovered repos to fleet config, exposed from a low-friction command such as `manifest doctor`, `manifest update fleet --dry-run`, or a timestamped passive check.
  - **Anchor:** [`modules/fleet/manifest-fleet-detect.sh`](../modules/fleet/manifest-fleet-detect.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **3.4 Add a fleet-service config editor.**
  - **Why:** toggling `services.<name>.release.enabled` or `services.<name>.release.strategy` still requires hand-editing `manifest.fleet.config.yaml`.
  - **Deliverable:** add a safe-by-default command, final name TBD, for scoped fleet-service config edits such as enabling/disabling release and setting release strategy.
  - **Anchor:** [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh), [`modules/fleet/manifest-fleet-config.sh`](../modules/fleet/manifest-fleet-config.sh).

- **3.5 Preserve fleet service names in plan output.**
  - **Why:** the fleet plan table renders the `Service` column as a de-dotted slug — e.g. `fidenceiomanifestcli` instead of `fidenceio.manifest.cli`, observed 2026-05-19. The `Path` column saves comprehension, but the Service column reads as noise.
  - **Deliverable:** print the configured service name verbatim (or apply a documented slug transform that preserves dots). Add a regression that asserts the printed Service column matches the configured name for each fleet entry.
  - **Anchor:** [`modules/fleet/manifest-fleet-plan.sh`](../modules/fleet/manifest-fleet-plan.sh), [`modules/fleet/manifest-fleet-config.sh`](../modules/fleet/manifest-fleet-config.sh).

---

## 4. Verification Gaps

- **4.1 Add broad preview no-write coverage.**
  - **Why:** focused dry-run tests exist, but there is no shared matrix proving every mutating preview leaves git porcelain and file snapshots unchanged.
  - **Deliverable:** `tests/preview_no_write.bats` or equivalent helper-driven coverage across repo, fleet, PR, config, docs, install/uninstall, and refresh paths.
  - **Anchor:** [`tests/dry_run.bats`](../tests/dry_run.bats), [`tests/fleet_dry_run.bats`](../tests/fleet_dry_run.bats), [`tests/pr_native_safe_by_default.bats`](../tests/pr_native_safe_by_default.bats).

- **4.2 Add focused local-only apply tests.**
  - **Why:** `--local -y` is its own contract and should prove local writes occur without remote dispatch.
  - **Deliverable:** targeted tests for local-only ship/refresh/fleet paths, including assertions that no remote push/API command is called.
  - **Anchor:** [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh), [`modules/fleet/manifest-fleet.sh`](../modules/fleet/manifest-fleet.sh).

- **4.3 Add Cloud apply-intent contract stubs.**
  - **Why:** Cloud-backed mutation must fail closed when `execution_mode=apply` is missing.
  - **Deliverable:** local stub test that rejects a Cloud request missing apply intent before any provider or analyzer runs.
  - **Anchor:** [`modules/stubs/manifest-cloud-stub.sh`](../modules/stubs/manifest-cloud-stub.sh), new `tests/cloud_contract.bats`.

- **4.4 Keep policy phases gated by the container suite.**
  - **Why:** execution-policy work crosses many commands and must stay container-only.
  - **Deliverable:** run `./scripts/run-tests-container.sh` after each execution-policy or fleet-policy phase, and record failures in the change that introduced them.
  - **Anchor:** [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

---

## 5. Docs And Completions

- **5.1 Finish safe-by-default help/doc audit.**
  - **Why:** user-facing docs and bash/zsh completions already describe most of the contract, but command help can still drift.
  - **Deliverable:** audit mutating command help examples so preview examples are bare commands and apply examples include `-y`; add tests where practical.
  - **Anchor:** [`modules/core/manifest-core.sh`](../modules/core/manifest-core.sh), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md).

- **5.2 Add fish-shell completions.**
  - **Why:** bash and zsh completions ship; fish remains missing.
  - **Deliverable:** `completions/manifest.fish` plus install instructions in `completions/README.md`.
  - **Anchor:** [`completions/`](../completions/), [`tests/completions.bats`](../tests/completions.bats).

- **5.3 Write the public-release migration note.**
  - **Why:** users upgrading from pre-safe-by-default releases need a concise explanation of preview default, `-y` apply, and `MANIFEST_CLI_AUTO_CONFIRM` semantics.
  - **Deliverable:** migration copy in release docs or `docs/MIGRATION.md`, with matching language in the user guide before the next major release.
  - **Anchor:** [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md).

- **5.4 Surface the required `brew tap fidenceio/tap` step at point of install failure.**
  - **Why:** `brew install manifest` against a Homebrew install without the tap fails with the generic "No available formula" message and no breadcrumb to `fidenceio/tap`. Confirmed 2026-05-19 on a fresh host. Memory `reference_brew_tap_install_required` captures the contract; users hitting the failure don't see it.
  - **Deliverable:** README install section leads with `brew tap fidenceio/tap && brew install manifest` (or the qualified `brew install fidenceio/tap/manifest`) as the canonical command; `install-cli.sh` and any post-install caveats print the tap command on Homebrew-detected failures.
  - **Anchor:** [`README.md`](../README.md), [`install-cli.sh`](../install-cli.sh), [`formula/manifest.rb`](../formula/manifest.rb) (caveats block).

---

## 6. Cloud Handoff - CLI Side

The local release-notes provider hook and recipe inspection surfaces exist. Remaining work is the Cloud-specific contract, payload policy, and end-to-end verification.

- **6.1 Decide and document the CLI/Cloud contract source.**
  - **Deliverable:** decide whether CLI stores copied schemas under `docs/contracts/` or references Cloud as source of truth; document Standard and Verbose payload expectations.
  - **Anchor:** [`docs/contracts/`](contracts/), [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **6.2 Complete the `cloud.*` YAML/env config surface.**
  - **Deliverable:** add the remaining `cloud.{enabled,endpoint,release_notes.*,security.*}` mappings; keep Cloud disabled by default and secrets referenced by env name, not committed values.
  - **Anchor:** [`modules/core/manifest-yaml.sh`](../modules/core/manifest-yaml.sh), [`modules/core/manifest-config.sh`](../modules/core/manifest-config.sh), [`examples/manifest.config.yaml.example`](../examples/manifest.config.yaml.example), [`tests/yaml.bats`](../tests/yaml.bats).

- **6.3 Wire Cloud as a release-notes provider option.**
  - **Deliverable:** Cloud provider command selectable by config; local fallback preserved when optional; required mode aborts doc generation on failure; CLI remains owner of changelog writes.
  - **Anchor:** [`modules/docs/manifest-documentation.sh`](../modules/docs/manifest-documentation.sh), [`tests/release_notes_provider.bats`](../tests/release_notes_provider.bats).

- **6.4 Add payload preview and privacy assertions.**
  - **Deliverable:** preview output shows Cloud mode, endpoint, fallback, identity, and upload decision; tests assert Standard mode excludes source bodies, raw diffs, raw commit bodies, author emails, full remotes, absolute paths, and secret-looking values.
  - **Anchor:** new `tests/cloud_payload.bats`, [`docs/USER_GUIDE.md`](USER_GUIDE.md).

- **6.5 Add Cloud handoff metadata to recipes.**
  - **Deliverable:** recipe schema accepts step `policy`/`privacy`/`fallback` metadata; ship recipes include a Cloud handoff step; `manifest ship repo patch --explain` shows Cloud status without uploading.
  - **Anchor:** [`docs/contracts/recipe.schema.json`](contracts/recipe.schema.json), [`recipes/builtin/manifest.builtin.ship.repo.*.yaml`](../recipes/builtin/), [`tests/recipe.bats`](../tests/recipe.bats).

- **6.6 Finish CLI docs for Cloud handoff.**
  - **Deliverable:** document Standard mode, Verbose mode, no-code default, fallback behavior, provider-hook integration, recipe-backed commands, and the Fidence platform assumption for production Cloud.
  - **Anchor:** [`README.md`](../README.md), [`docs/USER_GUIDE.md`](USER_GUIDE.md), [`docs/COMMAND_REFERENCE.md`](COMMAND_REFERENCE.md), [`docs/EXAMPLES.md`](EXAMPLES.md), [`docs/INDEX.md`](INDEX.md).

- **6.7 Verify the Cloud handoff path in containers.**
  - **Deliverable:** `./scripts/run-tests-container.sh tests/yaml.bats tests/release_notes_provider.bats tests/docs_generation.bats tests/recipe.bats tests/cloud_payload.bats` passes; `manifest ship repo patch --explain` works without GitHub or Cloud; full container suite is green.
  - **Anchor:** [`scripts/run-tests-container.sh`](../scripts/run-tests-container.sh).

---

## 7. Structural Follow-ups

- **7.1 Extract user global-config migration from `install-cli.sh`.**
  - **Why:** `install-cli.sh` remains large, and the global-config migration is a clean extraction boundary.
  - **Deliverable:** new `scripts/migrate-user-config.sh`; `install-cli.sh` delegates.
  - **Anchor:** [`install-cli.sh`](../install-cli.sh).

- **7.2 Add `--json` summaries to `refresh` and `ship`.**
  - **Why:** `status` and `config list` have JSON, but streaming side-effect commands need structured step-result plumbing first.
  - **Deliverable:** orchestrator emits a structured per-step result object; `--json` on `refresh` and `ship` serializes the final summary.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-refresh.sh`](../modules/core/manifest-refresh.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

- **7.3 Relocate `manifest_ship_workflow` into `modules/core/manifest-ship.sh`.**
  - **Why:** the public ship entry point lives in `manifest-ship.sh`, but the workflow body still lives in the orchestrator module.
  - **Deliverable:** move the function body to `manifest-ship.sh`; keep or remove the compatibility shim after checking callers.
  - **Anchor:** [`modules/workflow/manifest-orchestrator.sh`](../modules/workflow/manifest-orchestrator.sh), [`modules/core/manifest-ship.sh`](../modules/core/manifest-ship.sh).

---

## 8. Output Polish

- **8.1 Quiet OS-detection preamble on every invocation.**
  - **Why:** every `manifest <anything>` invocation — including `--version`, `version`, and pure-preview commands like `ship fleet patch` (no `-y`) — prints a 3-line `🔍 Detecting operating system… Bash 5.3.9 detected on Darwin…` block before the requested output. For `--version` it adds ~1s and pushes the version string off-screen in CI logs; for previews it pushes the scope notice down.
  - **Deliverable:** detect OS once per process and cache; suppress the preamble unless `--verbose` or `MANIFEST_DEBUG=1` is set; treat `--version` / `version` as a fast-path that prints a single line and exits.
  - **Anchor:** [`modules/system/manifest-os.sh`](../modules/system/manifest-os.sh), [`modules/core/manifest-requirements.sh`](../modules/core/manifest-requirements.sh), [`scripts/manifest-cli.sh`](../scripts/manifest-cli.sh).

- **8.2 Stop reporting bogus precision on cached trusted timestamps.**
  - **Why:** fleet ship output reads `Trusted timestamp ±0.000000` for cached values across all members within seconds of each other. The `±0.000000` is technically the cache's confidence-of-itself, but reads as "we measured to sub-microsecond precision" — confusing for anyone auditing release timing. Observed 2026-05-19 across 4 members.
  - **Deliverable:** when emitting a cached timestamp, label it as `cached (from <source> at <time>)` and drop the precision figure, OR report the original measurement's confidence rather than zero. Add a regression covering the cached-emit path.
  - **Anchor:** [`modules/system/manifest-time.sh`](../modules/system/manifest-time.sh).

---

## See also

- Workspace milestones: [`../../TRACKER.md`](../../TRACKER.md)
- Cloud side: [`../../fidenceio.manifest.cloud/docs/TRACKER.md`](../../fidenceio.manifest.cloud/docs/TRACKER.md)
