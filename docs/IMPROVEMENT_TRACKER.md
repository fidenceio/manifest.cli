# Manifest CLI — Improvement Tracker

**Started:** 2026-04-24 (against v44.1.1, ~15K LOC)
**Status legend:** `[ ]` open · `[~]` in progress · `[x]` done · `[-]` declined/won't-fix

Check items off as work lands. Add a `→ <commit-or-PR>` note on the right when resolving. Keep this file updated alongside changes.

---

## 1 · What's working (keep)

No action needed — listed so we don't accidentally regress these strengths.

- [x] v42 journey: `config → init → prep → refresh → ship` with `repo|fleet` scope. Thin router modules, no duplication.
- [x] Plugin/stub model keeps CLI self-contained (Cloud features load if present, stubs otherwise).
- [x] YAML layering (code defaults → global → project → project-local).
- [x] Canonical-repo gate for Homebrew is clean and isolated ([manifest-core.sh:121-138](../modules/core/manifest-core.sh#L121-L138)).
- [x] `display_help()` output is concise and groups commands logically.

---

## 2 · Findings

> **Read order note for pickup:** Section 2 is the **diagnosis** (what was wrong on 2026-04-24). It is descriptive, not a work queue — bullets stay as plain dashes, never checkboxes. The actual checkbox-driven work queue lives in **Section 3** below.

### A · Naming lies and control-flow inversion

- `manifest_prep_workflow()` in [modules/workflow/manifest-orchestrator.sh](../modules/workflow/manifest-orchestrator.sh) actually *does the ship* (version bump, docs, commit, tag, push, Homebrew).
- [manifest-ship.sh:96](../modules/core/manifest-ship.sh#L96) calls `manifest_prep_workflow` — `ship` looks like a wrapper around `prep`, which is the opposite of what v42 says.
- Verify: `grep -n 'manifest_prep_workflow\|manifest_ship_workflow' modules/`

### B · Dead code and vestigial modules

- [manifest-env-management.sh](../modules/core/manifest-env-management.sh) (270 lines) — legacy `.env` parser at lines 181-213 never called; shell-profile cleanup (lines 76-129) invoked by a cleanup command that no longer exists.
- [manifest-yaml.sh:354](../modules/core/manifest-yaml.sh#L354) & `:418` — comments reference a Python fallback that doesn't exist anymore.
- Legacy fleet helpers (`fleet_start`, `fleet_init`, `fleet_sync`) still exist inside 2031-line [manifest-fleet.sh](../modules/fleet/manifest-fleet.sh) alongside v42 entry points. Two paths to the same behavior.
- Stubs silently hide missing features: [manifest-pr-stub.sh](../modules/stubs/manifest-pr-stub.sh) returns "requires Manifest Cloud" for 13 functions — **design mistake**, PRs don't need Cloud (see finding G).
- Verify: `grep -rn 'export_env_from_config\|manifest_env_' modules/ | grep -v env-management.sh`

### C · Bloat in auxiliary modules

| Module | Lines | Problem |
| --- | --- | --- |
| [manifest-time.sh](../modules/system/manifest-time.sh) | 764 | Over-engineered for "curl Date header → cache → return". Should be ~250 lines. |
| [manifest-security.sh](../modules/system/manifest-security.sh) | 578 | Three checks explicitly disabled with "Temporarily disabled due to false positives" (lines 41-46, 61-62). Audit theater. |
| [manifest-shared-functions.sh](../modules/core/manifest-shared-functions.sh) | 1090 | Dumping ground. File scaffolding (lines 593-894) belongs in `manifest-init.sh`. |

- Slim time module
- Fix-or-delete disabled security checks
- Re-home scaffolding
- Verify: `wc -l modules/system/manifest-time.sh modules/system/manifest-security.sh modules/core/manifest-shared-functions.sh`

### D · Config system: strong bones, weak surface

- 83 YAML keys exist but no `manifest config list` or `manifest config describe <key>`. Users must read source.
- `set_default_configuration()` called **three times per CLI invocation**.
- **Safety gap (critical):** double-confirm rule for `~/.manifest-cli/manifest.config.global.yaml` is **not enforced anywhere**. Silent writes in `install-cli.sh migrate_user_global_configuration`, `config doctor --fix`, `set_yaml_value()`.
- Verify: `grep -rn 'manifest.config.global.yaml' modules/ install-cli.sh | grep -iE 'confirm|prompt' # expect empty`

### E · UX inconsistencies

- Short flags only on `ship` (`-p/-m/-M/-r`); missing from `prep`, `init`, `refresh`.
- Three different deprecation styles: `sync` silent, `update` warns, `prep <type>` fallthrough-warn.
- Config wizard writes immediately after ~25 prompts with no confirm screen.
- Fleet-init two-phase flow is implicit (TSV existence switches phase). No guard against re-running phase 1 after edits.
- `ship fleet --noprep` is in code but absent from help.
- Error messages: some show usage, some just log. No shared template.

### F · Missing power-user affordances

- No `manifest status` / `manifest show`.
- No shell completions (bash/zsh/fish).
- No `--json` output mode.
- No journey-level `--dry-run` (only `ship --local`).
- No `manifest --version` short form.
- No top-level `manifest doctor`.

### G · PR is an unowned feature, not a Cloud feature

- [manifest-pr-stub.sh](../modules/stubs/manifest-pr-stub.sh) forces users toward Cloud for operations `gh` handles natively.
- Correct split:
  - **Native in CLI** (new): `pr create`, `pr status`, `pr checks`, `pr ready`, `pr update`, `pr merge` — thin wrappers over `gh`.
  - **Cloud-extended** (plugin): `pr queue` (auto-merge), `pr policy show|validate`, advanced fleet PR coordination.
- Unblocks `fleet_ship`'s commented-out "prep → pr create → checks → queue" pipeline.

### H · Zero test coverage for a 15K-LOC tool

- No `.bats`, no `test_*.sh`, no `tests/` directory.
- `manifest test` is a Cloud stub — no self-tests to run.
- [install-cli.sh:33](../install-cli.sh#L33) header advertises a non-existent "Automated testing framework".
- Verify: `find . -name '*.bats' -o -name 'test_*.sh' -o -name '*_test.sh' # expect empty`

### I · Incomplete migration residue

- [examples/env.manifest.global.example](../examples/env.manifest.global.example) and [examples/env.manifest.local.example](../examples/env.manifest.local.example) ship alongside YAML examples.
- [examples/env.manifest.examples.md](../examples/env.manifest.examples.md) references `.env` format authoritatively.
- New users see both config formats advertised.

### J · install-cli.sh sprawl

- [install-cli.sh](../install-cli.sh) is 1066 lines / 28 functions — larger than most core modules.
- Header (lines 7-37) markets non-existent features ("Automated testing framework" etc.).
- Target: under 500 lines; split migrate logic out if it must survive.

---

## 3 · Recommendations (prioritized tracker)

Each recommendation is a discrete unit of work. Check off when complete.

### Tier 1 — Correctness & safety (ship-blocking)

- [x] **1. Enforce global-config double-confirm.** Added `_confirm_global_config_write` gatekeeper in `manifest-config.sh:33`. Wired into: `auto_migrate_user_global_configuration` (now warn-only by default — was silent rewrite on every CLI run), `config_doctor --fix`, .env→YAML migration in `config_doctor`, and `cleanup_config_files` in uninstall. Modify ops use single confirm + session cache; delete/overwrite require typing `yes` twice. `MANIFEST_CLI_AUTO_CONFIRM=1` bypass for CI. `install-cli.sh migrate_user_global_configuration` left alone — install is implicit authorization (user explicitly invoked the script).
- [x] **2. Rename `manifest_prep_workflow` → `manifest_ship_workflow`** — done in place; back-compat shim added in `manifest-orchestrator.sh`. Relocation into `manifest-ship.sh` deferred (orchestrator file is 576 lines and contains more than just the entry point — moving the whole file is a separate decision).
- [x] **3. Delete dead Python-fallback comments** in `manifest-yaml.sh`. Added `require_yaml_parser()` and called from `load_configuration()` so missing yq fails fast with a clear install hint instead of a confusing later error.
- [x] **4. Start a test harness.** bats-core adopted. Suite at `tests/` (29 tests across `yaml.bats`, `version.bats`, `canonical_repo.bats`, `safety_gate.bats`). Runner at `scripts/run-tests.sh`. Surfaced two findings:
  - **Bug fixed:** `manifest_origin_repo_slug`'s HTTPS regex captured `.git` suffix into the repo name (`[^/]+(\.git)?` is greedy). Fixed in both `manifest-core.sh` and `manifest-shared-functions.sh` by stripping `%.git` from the second capture group.
  - **New finding:** `manifest_origin_repo_slug` is defined in **two** modules with subtly different signatures, and the canonical-repo gate exists as both `should_update_homebrew_for_repo` (uses `MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS`) and `manifest_is_canonical_repo` (uses `MANIFEST_CLI_CANONICAL_REPO_SLUGS`). Two env vars for the same concept. See new tracker item #27 below.

### Tier 2 — Remove fat (elegance)

- [x] **5. Delete `manifest-env-management.sh`.** Removed (270 lines). Inlined the only still-useful piece (shell-profile cleanup) into `install-cli.sh` and `manifest-uninstall.sh`. Callers in `install-cli.sh` (`source_manifest_env_management`, `cleanup_environment_variables`) replaced with self-contained inline cleanup.
- [ ] **6. Slim `manifest-time.sh`** to ~250 lines. One server, one curl, one cache file.
- [x] **7. Decide on `manifest security`** — deleted. Removed the three "Temporarily disabled due to false positives" stubs in `manifest_security()` and the dead function bodies (`check_actual_sensitive_data`, `check_recent_secret_commits`, `check_actual_credentials` — 146 lines). Audit now reports honestly on the three real checks: git-tracking of private files, PII detection, environment-file gitignore enforcement.
- [ ] **8. Re-home scaffolding.** Move `ensure_required_files` + helpers from `manifest-shared-functions.sh:593-894` into `manifest-init.sh`.
- [ ] **9. Collapse dual fleet paths.** Make `fleet_start`/`fleet_init`/`fleet_sync` private (`_fleet_*`), remove dispatcher routes.
- [x] **10. Purge legacy `.env` examples.** Deleted `examples/env.manifest.global.example`, `examples/env.manifest.local.example`, `examples/env.manifest.examples.md`. Updated `README.md`, `docs/USER_GUIDE.md`, `docs/INDEX.md` to point at `examples/manifest.config.yaml.example` instead. Also removed the legacy `.env→YAML` migration block in `config_doctor` and the legacy-detection warning loop in `load_configuration` and the `.env.manifest.local` entry from the gitignore template.
- [x] **11. Shrink `install-cli.sh`** — 1052 → 919 lines (~13%, -133 lines). Replaced the 38-line marketing header with an honest 8-line description; added `_install_hint <pkg>` helper covering 7 package managers and used it to collapse two duplicated 30-line per-distro hint blocks; trimmed `get_system_info` (49 → 15) by dropping unused globals; rewrote `display_post_install_info` (53 → 18) around v42 commands; replaced a 30-line inline post-install block in `main()` with a single call to that helper. The aspirational <500 target requires extracting `migrate_user_global_configuration` to its own script — left as a focused follow-up since this pass kept behavior identical and shipping the marketing-lie removal was the load-bearing fix.

### Tier 3 — UX consistency (polish)

- [x] **12. One flag vocabulary.** Audited 2026-04-25. All four v42 dispatchers (init, prep, refresh, ship) have consistent `-h|--help` at verb / repo / fleet levels. Short bump flags `-p/-m/-M/-r` are on `ship` — the only verb that takes a bump type. The `--dry-run` portion of the wording is the substantive feature tracked separately as #22 (journey-level --dry-run) and stays on the queue.
- [x] **13. One deprecation format.** `log_deprecated <old> <new> [<note>]` added to `manifest-shared-utils.sh`. Wired into `manifest sync`, `manifest update`, `manifest prep <type>`, and `MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS`. Single-emit-per-session via `_MANIFEST_DEPRECATIONS_WARNED`; suppressed by `MANIFEST_CLI_QUIET_DEPRECATIONS=1`. Four bats tests in `tests/deprecation.bats`.
- [ ] **14. Config wizard: add review-and-confirm step** before persisting. Show diff from current, ask once.
- [x] **15. Fleet-init phase clarity.** `manifest_init_fleet` now banners "Phase 1/2: Discovering directories…" before delegating to `fleet_start` (with explicit "edit TSV, then re-run" instructions) and "Phase 2/2: Applying TSV selections…" before delegating to `fleet_init`. Added `_fleet_init_tsv_is_stale` guard: `generate_start_tsv` embeds a `# DEFAULT-SELECT-HASH` fingerprint into the TSV header; Phase 2 recomputes the SELECT-column hash and refuses to apply if it still matches the default (i.e. the user ran Phase 2 without editing). The guard is bypassed by `--force`. Falls back to "not stale" if the header is missing (back-compat with pre-#15 TSVs). Six new bats tests in `tests/fleet_init_phase.bats` covering: unedited-flagged, edited-not-flagged, missing-header (back-compat), config-already-present short-circuit, missing-TSV, and `_manifest_hash_short` portability.
- [x] **16. Help template.** Added `_render_help` and `_render_help_error` to `manifest-shared-utils.sh`. Every `manifest <verb> --help` (init/prep/refresh/ship at scope+dispatch levels) plus `manifest config list/get/set/unset/describe` and `manifest pr create/status/checks/ready/merge/update` now route through the same renderer. Format: `Usage: …` line, blank, description (multi-line OK), then alternating `Heading:` + body sections. Six bats tests in `tests/help_template.bats`.

### Tier 4 — New capability (power)

- [x] **17. `manifest status`** — implemented in `modules/core/manifest-status.sh`. Shows repo, canonical-gate marker, branch+sync state, working tree, current VERSION + previews of patch/minor/major bumps, single-vs-fleet mode, config layer presence. Read-only. Six bats tests in `tests/status.bats`.
- [x] **18. `manifest config list` / `get` / `set` / `unset` / `describe`** — implemented in `modules/core/manifest-config-crud.sh`. Layer-aware (`--layer global|project|local`, default `local`). Writing global goes through the safety gate. `describe` shows per-layer values + env var. Round-trip verified via temp-repo smoke test.
- [ ] **19. `--json` output** on `status`, `config list`, `refresh`, `ship` summary.
- [x] **20. Shell completions (bash + zsh).** Files at `completions/manifest.bash` and `completions/_manifest`. Cover top-level commands, `repo|fleet` scopes, bump types, config subcommands (with dynamic key lookup via `manifest config list`), PR subcommands, layer flag values. Install instructions in `completions/README.md`. Verified: `manifest init <TAB>` → `repo fleet`, `manifest ship repo <TAB>` → `patch minor major revision --local --dry-run`, etc. Fish deferred — bash + zsh cover ~95% of dev shells.
- [x] **21. `manifest doctor`** as top-level — implemented in `modules/core/manifest-doctor.sh`. Checks dependencies (yq, git, Bash, gh-optional), config (global file presence, schema version, drift via `_manifest_config_detect_issues`), repository (git, origin remote, canonical-repo gate, VERSION file). Color-coded ✓/⚠/✗, exit 1 on errors only.
- [ ] **22. Journey-level `--dry-run`** on `init`, `prep`, `refresh` (not just `ship --local`).
- [x] **23. Native `manifest pr` (no Cloud dependency).** Implemented in `modules/pr/manifest-pr-native.sh`. `pr create / status / checks / ready / merge / update / interactive` all wrap `gh`. Loader chain: native first → Cloud plugin (overrides if installed) → stub (fills queue/policy/etc. with "requires Cloud"). Stub now uses type-guards so it only defines what's missing. Help text + dispatcher updated. Verified `pr help` shows native + Cloud-only sections; `pr queue` correctly falls through to stub.

### Tier 5 — Fleet power

- [ ] **24. `manifest ship fleet --only <service>` / `--except <service>`** for partial fleet ships.
- [x] **25. Surface hidden fleet flags in help.** `manifest ship fleet --help` now lists every flag that fleet_ship accepts: `--noprep`, `--safe`, `--method <merge|squash|rebase>`, `--force`, `--no-delete-branch`, `--draft`. Help also includes a "Flow:" section showing the default vs. `--safe` pipeline so users know which step `--safe` adds. Bats coverage verifies all six flags appear in `--help` output.
- [ ] **26. `manifest refresh fleet --commit`** — don't redirect users to `ship fleet --local` for a semantically-different operation.

### Tier 2 (additions found while resolving Tier 1)

- [x] **27. Consolidate canonical-repo detection.** Deleted the duplicate `manifest_origin_repo_slug` and `should_update_homebrew_for_repo` from `manifest-core.sh`; replaced with a one-line back-compat shim that delegates to `manifest_is_canonical_repo`. The latter now accepts the legacy `MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS` env var as a deprecated fallback (one-time warning via `log_deprecated`) when `MANIFEST_CLI_CANONICAL_REPO_SLUGS` is unset. Two new bats tests verify both back-compat paths.

### CI / Infrastructure (added during the build-out)

- [x] **28. GitHub Actions CI** — `.github/workflows/test.yml` runs the bats suite + smoke-tests `version`, `help`, `status`, `doctor` on `ubuntu-latest` and `macos-latest` for every push to main and every PR. `manifest --version` badge added to README.

---

## 4 · Suggested sequencing

1. **Tier 1** first — safety/correctness blocks other refactors. Items #1 and #4 are load-bearing; #2 is cheap and removes the single biggest readability trap.
2. **Tier 4 quick wins** next — #17, #18, #20, #23. Each is high-visibility, self-contained, doesn't perturb existing paths.
3. **Tiers 2-3 incrementally** — fold in while touching each module for other reasons. #10 (example purge) can go any time.
4. **Tier 5** only when fleet users specifically ask.

---

## 5 · Working notes

Use this section as a scratchpad when resolving items — capture non-obvious decisions, scope changes, or follow-ups spawned by each task.

### Session 2026-04-24 — initial Tier 1 + Tier 4 sweep

Resolved in this session: **#1, #2, #3, #4, #5, #10, #17, #18, #20, #21, #23, #28**.

**Decisions made along the way:**

- **Auto-migration default flipped to warn-only.** `auto_migrate_user_global_configuration` previously rewrote the global config silently on every CLI run. Now warns + tells the user to run `manifest config doctor --fix`. Opt-in to silent migration via `MANIFEST_CLI_AUTO_CONFIRM=1`.
- **`manifest_prep_workflow` rename done in place.** Decided NOT to physically relocate the function from `manifest-orchestrator.sh` to `manifest-ship.sh` — the orchestrator file is 576 lines containing more than just the entry point. Function renamed in place; back-compat shim added. Relocation is a separate (larger) refactor.
- **PR loader chain redesigned.** Native first → Cloud plugin (overrides) → stub (gap-fill via type-guards). Means `pr create/status/checks/...` always works; only `pr queue / pr policy` fall through to the "requires Cloud" message.
- **Legacy `.env` support fully removed (deepened scope of #5+#10).** User explicitly authorized full deprecation. Removed: legacy file detection in `install-cli.sh` and `manifest-config.sh`, `.env→YAML` migration block in `config_doctor`, `manifest-env-management.sh` module entirely, three example files, three docs links. Inlined the only useful bit (shell-profile cleanup) into install + uninstall.
- **Test harness surfaced a real bug.** `manifest_origin_repo_slug` HTTPS regex captured `.git` into the repo name (greedy `[^/]+(\.git)?`). Fixed in both copies via `${repo%.git}`. Tests caught it on first run.
- **New tracker item #27** opened during testing: `manifest_origin_repo_slug` is duplicated across two modules with subtly different signatures, and there are two functions / two env vars for the same canonical-repo concept. Worth consolidating.

**Files added** (12): `modules/core/manifest-status.sh`, `modules/core/manifest-doctor.sh`, `modules/core/manifest-config-crud.sh`, `modules/pr/manifest-pr-native.sh`, `tests/{yaml,version,canonical_repo,safety_gate,status}.bats`, `tests/helpers/setup.bash`, `tests/README.md`, `scripts/run-tests.sh`, `completions/{manifest.bash,_manifest,README.md}`, `.github/workflows/test.yml`.

**Files removed** (4): `modules/core/manifest-env-management.sh`, `examples/env.manifest.global.example`, `examples/env.manifest.local.example`, `examples/env.manifest.examples.md`.

**Test count:** 35 bats tests, all passing on macOS. CI runs on Ubuntu + macOS via GitHub Actions.

### Session 2026-04-25 — UX consistency cluster (#15, #16, #25)

Resolved: **#15, #16, #25**. (After this batch: 20/28 done, 8 open: #6, #8, #9, #14, #19, #22, #24, #26.)

**Decisions:**

- **#16 first, then #25, then #15.** Building the help template (#16) first made #25 (surface fleet hidden flags) and #15 (fleet-init phase messaging) cheap — each is just a `_render_help` call with the right sections.
- **#15 stale-detection design pivoted twice.** First draft used a heuristic ("any SELECT cell that isn't literally `true`/`false` means edited") — but the most common edit IS flipping `true`↔`false`, which the heuristic missed. Second design: embed a default-selection fingerprint into the TSV header (`# DEFAULT-SELECT-HASH:`) and recompute on Phase 2. Robust for any edit, including whitespace/comment changes. Old-format TSVs (no header) are deliberately treated as "not stale" so we don't break users on existing fleet directories.
- **`_manifest_hash_short` lives in shared-utils, not fleet-detect.** Originally placed it next to `generate_start_tsv` but that made `manifest-init.sh` depend on the fleet module just to read its own TSVs. Moved to `manifest-shared-utils.sh` — both writers (fleet) and readers (init) get it without coupling.
- **Help template kept deliberately simple.** API: `_render_help "<usage>" "<description>" [section_name body]…`. No nested formatting, no fancy alignment — callers control body alignment via plain text. This matches existing help conventions while eliminating per-verb echo blocks.
- **`-x` + brackets in grep.** First test pass failed because `grep -qx "Usage: foo [--bar]"` interprets `[--bar]` as a regex character class. Switched to `grep -qFx` (fixed-string, exact-line) throughout `tests/help_template.bats`.

**Files added (2):** `tests/help_template.bats`, `tests/fleet_init_phase.bats`.
**Files modified (10):** `modules/core/manifest-shared-utils.sh` (helpers), `modules/core/manifest-{init,prep,refresh,ship,config-crud}.sh` (use template), `modules/pr/manifest-pr-native.sh` (use template), `modules/fleet/manifest-fleet-detect.sh` (TSV fingerprint).
**Test count:** 53 bats tests (was 41, +6 help-template +6 fleet-init phase guard, all passing on macOS).

### Session 2026-04-25 — Tier 2 cleanups + Tier 3 polish

Resolved: **#7, #11, #12, #13, #27**. Plus shipped **v44.2.0** publicly via Homebrew earlier in the session.

**Decisions:**

- **#12** turned out to already be satisfied. Audit confirmed the v42 dispatchers are flag-consistent (`-h|--help` everywhere, short bump flags only on `ship` since that's the only verb taking a bump). The `--dry-run` portion of the original wording is the substantive feature already tracked as #22 — kept on the queue.
- **#11** stopped at 919 lines instead of the aspirational <500. Hitting 500 requires structural changes (extracting migrate_user_global_configuration to its own script) that go beyond this pass. Shipped the load-bearing fix (kill marketing-copy header, dedupe per-distro hints, trim duplicated post-install block).
- **#7** went the delete route rather than fix. The disabled checks had a fundamental design problem (regex too broad — flagged any `password=`/`token=` line including legitimate variable renames). A redesign needs proper test fixtures and a fresh implementation; not in scope for this pass.

**Files added (2):** `tests/deprecation.bats`, archived security report snapshot.
**Files removed (~146 lines from manifest-security.sh, ~133 from install-cli.sh):** 3 dead security functions; install-cli marketing header + duplicated per-distro hints + duplicated post-install block.
**Test count:** 41 bats tests (was 35, +4 deprecation tests +2 canonical-repo back-compat tests).
