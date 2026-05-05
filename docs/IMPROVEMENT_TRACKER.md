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
- [x] **6. Slim `manifest-time.sh`** — 764 → 342 lines (-55%). Removed dead code (`get_timestamp`, `get_formatted_timestamp`, `display_time_os_info` had zero callers). Folded `calculate_time_timestamp` (70 lines of bc-fallback ceremony) into a 6-line `_manifest_time_apply_offset` helper using pure shell integer arithmetic — the previous code always cut at `.` anyway, so floating-point added no precision. Consolidated repeated `if [ "$MANIFEST_DEBUG" = "1" ]` blocks behind a `_manifest_time_debug` helper. Extracted `_manifest_time_export` and `_manifest_time_print_result` so cache-hit / network-success / stale-fallback paths share one display block instead of three near-identical copies. Public API preserved (`get_time_timestamp`, `format_timestamp`, `display_time_info`, `display_time_config` and the `MANIFEST_CLI_TIME_*` exported vars). Cache file format unchanged for back-compat. Twelve bats tests in `tests/time.bats` cover `_parse_http_date` (BSD+GNU+python3 fallback), `_manifest_time_apply_offset` (positive/negative/malformed), cache write+read round-trip, fresh TTL expiration, stale-cache fallback, server list defaults+overrides, and `get_time_timestamp` cache-hit path. → 91/91 bats tests passing.
- [x] **7. Decide on `manifest security`** — deleted. Removed the three "Temporarily disabled due to false positives" stubs in `manifest_security()` and the dead function bodies (`check_actual_sensitive_data`, `check_recent_secret_commits`, `check_actual_credentials` — 146 lines). Audit now reports honestly on the three real checks: git-tracking of private files, PII detection, environment-file gitignore enforcement.
- [x] **8. Re-home scaffolding.** Moved `ensure_required_files`, `create_default_readme`, `create_default_changelog`, `ensure_gitignore_smart`, `create_default_gitignore` (~485 lines incl. `.gitignore` template) from `manifest-shared-functions.sh` into `manifest-init.sh`. Updated `export -f` lines on both sides; added a SCAFFOLDING HELPERS note in the init module's docblock listing the cross-module callers (orchestrator, documentation, fleet). Bash resolves function bodies at call time, so the load-order in manifest-core.sh (init at line 78, after orchestrator/documentation/fleet) doesn't matter functionally — calls only happen at command-invocation time, by which point init is loaded. Public function names + signatures unchanged. shared-functions.sh: 1102 → 614 lines (-488, -44%); manifest-init.sh: 348 → 844 (+496). 91/91 bats tests still pass; `init repo` smoke-tested end-to-end in /tmp/init-smoke.
- [x] **9. Collapse dual fleet paths.** Renamed `fleet_start` → `_fleet_start`, `fleet_init` → `_fleet_init`, `fleet_sync` → `_fleet_sync` in `modules/fleet/manifest-fleet.sh` so they are no longer part of the public function surface. Removed the `start`, `init`, `sync` cases from `fleet_main`'s dispatcher; invoking those verbs now hits a dedicated `start|init|sync)` arm that prints a one-line migration hint (`'manifest fleet start' is no longer a dispatcher route. Use: manifest init fleet`) and returns 1. Updated three call sites that still needed access: `fleet_quickstart` (now `_fleet_init --_quickstart`), `manifest_init_fleet` (Phase 1/2 now hit `_fleet_start` / `_fleet_init`), and `manifest_prep_fleet` (now `_fleet_sync`). Refreshed `fleet_help`, the top-of-file COMMANDS docblock, in-body status hints, and TSV header (`# Generated by: manifest init fleet`) to reference the v42 entry points. Updated user-facing docs: `USER_GUIDE.md` legacy table (added the three entries with "Removed in v44.9.0 — emits migration hint"), `EXAMPLES.md` migration grid + footnote, `COMMAND_REFERENCE.md` legacy section reorganized as "v42 entry points (preferred)" + "Legacy-only fleet commands", `FLEET_DESIGN_SPEC.md` section 5.5 wording. Added 7 bats tests in `tests/fleet_private_routes.bats` covering: legacy public names absent, private names present, each removed verb prints a hint pointing at the right v42 command, surviving routes still in `fleet_help`, and `fleet_quickstart` body references `_fleet_init` (no bare `fleet_init`). 106/106 bats pass.
- [x] **10. Purge legacy `.env` examples.** Deleted `examples/env.manifest.global.example`, `examples/env.manifest.local.example`, `examples/env.manifest.examples.md`. Updated `README.md`, `docs/USER_GUIDE.md`, `docs/INDEX.md` to point at `examples/manifest.config.yaml.example` instead. Also removed the legacy `.env→YAML` migration block in `config_doctor` and the legacy-detection warning loop in `load_configuration` and the `.env.manifest.local` entry from the gitignore template.
- [x] **11. Shrink `install-cli.sh`** — 1052 → 919 lines (~13%, -133 lines). Replaced the 38-line marketing header with an honest 8-line description; added `_install_hint <pkg>` helper covering 7 package managers and used it to collapse two duplicated 30-line per-distro hint blocks; trimmed `get_system_info` (49 → 15) by dropping unused globals; rewrote `display_post_install_info` (53 → 18) around v42 commands; replaced a 30-line inline post-install block in `main()` with a single call to that helper. The aspirational <500 target requires extracting `migrate_user_global_configuration` to its own script — left as a focused follow-up since this pass kept behavior identical and shipping the marketing-lie removal was the load-bearing fix.

### Tier 3 — UX consistency (polish)

- [x] **12. One flag vocabulary.** Audited 2026-04-25. All four v42 dispatchers (init, prep, refresh, ship) have consistent `-h|--help` at verb / repo / fleet levels. Short bump flags `-p/-m/-M/-r` are on `ship` — the only verb that takes a bump type. The `--dry-run` portion of the wording is the substantive feature tracked separately as #22 (journey-level --dry-run) and stays on the queue.
- [x] **13. One deprecation format.** `log_deprecated <old> <new> [<note>]` added to `manifest-shared-utils.sh`. Wired into `manifest sync`, `manifest update`, `manifest prep <type>`, and `MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS`. Single-emit-per-session via `_MANIFEST_DEPRECATIONS_WARNED`; suppressed by `MANIFEST_CLI_QUIET_DEPRECATIONS=1`. Four bats tests in `tests/deprecation.bats`.
- [x] **14. Config wizard: add review-and-confirm step** before persisting. The 25-prompt `configure_interactive` flow now ends with a grouped review block (Project / Git / Time / Docs+automation+PR sections) showing every value the user just entered plus the destination path, then asks one explicit "Write these settings to PATH? [y/N]". An empty answer or anything other than y/yes aborts with "Aborted. No changes written." Logic extracted into `_manifest_config_review_and_confirm` so it's unit-testable; `MANIFEST_CLI_AUTO_CONFIRM=1` skips the prompt for CI. Five bats tests in `tests/wizard_confirm.bats`.
- [x] **15. Fleet-init phase clarity.** `manifest_init_fleet` now banners "Phase 1/2: Discovering directories…" before delegating to `fleet_start` (with explicit "edit TSV, then re-run" instructions) and "Phase 2/2: Applying TSV selections…" before delegating to `fleet_init`. Added `_fleet_init_tsv_is_stale` guard: `generate_start_tsv` embeds a `# DEFAULT-SELECT-HASH` fingerprint into the TSV header; Phase 2 recomputes the SELECT-column hash and refuses to apply if it still matches the default (i.e. the user ran Phase 2 without editing). The guard is bypassed by `--force`. Falls back to "not stale" if the header is missing (back-compat with pre-#15 TSVs). Six new bats tests in `tests/fleet_init_phase.bats` covering: unedited-flagged, edited-not-flagged, missing-header (back-compat), config-already-present short-circuit, missing-TSV, and `_manifest_hash_short` portability.
- [x] **16. Help template.** Added `_render_help` and `_render_help_error` to `manifest-shared-utils.sh`. Every `manifest <verb> --help` (init/prep/refresh/ship at scope+dispatch levels) plus `manifest config list/get/set/unset/describe` and `manifest pr create/status/checks/ready/merge/update` now route through the same renderer. Format: `Usage: …` line, blank, description (multi-line OK), then alternating `Heading:` + body sections. Six bats tests in `tests/help_template.bats`.

### Tier 4 — New capability (power)

- [x] **17. `manifest status`** — implemented in `modules/core/manifest-status.sh`. Shows repo, canonical-gate marker, branch+sync state, working tree, current VERSION + previews of patch/minor/major bumps, single-vs-fleet mode, config layer presence. Read-only. Six bats tests in `tests/status.bats`.
- [x] **18. `manifest config list` / `get` / `set` / `unset` / `describe`** — implemented in `modules/core/manifest-config-crud.sh`. Layer-aware (`--layer global|project|local`, default `local`). Writing global goes through the safety gate. `describe` shows per-layer values + env var. Round-trip verified via temp-repo smoke test.
- [x] **19. `--json` output** on `status` and `config list`. Added `_json_escape`, `_json_kv_str`, `_json_kv_raw`, `_json_value` helpers in `manifest-shared-utils.sh` (no jq dependency — booleans/null/integers stay raw, everything else is escaped+quoted). `manifest status --json` emits a single-line object with `repository`, `branch`, `version`, `fleet`, `config` keys. `manifest config list --json` and `--layer X --json` emit a sorted array of `{key,layer,value}` records. Validates as JSON via python3. Twelve bats tests in `tests/json_output.bats`. `refresh` and `ship` summary deferred — those are streaming side-effect operations whose JSON output requires deeper plumbing through orchestrator step results; better as a focused follow-up.
- [x] **20. Shell completions (bash + zsh).** Files at `completions/manifest.bash` and `completions/_manifest`. Cover top-level commands including action-first fleet verbs, `repo|fleet` scopes, bump types, config subcommands (with dynamic key lookup via `manifest config list`), PR subcommands, layer flag values. Install instructions in `completions/README.md`. Verified: `manifest init <TAB>` → `repo fleet`, `manifest ship repo <TAB>` → `patch minor major revision --local --dry-run`, etc. Fish deferred — bash + zsh cover ~95% of dev shells.
- [x] **21. `manifest doctor`** as top-level — implemented in `modules/core/manifest-doctor.sh`. Checks dependencies (yq, git, Bash, gh-optional), config (global file presence, schema version, drift via `_manifest_config_detect_issues`), repository (git, origin remote, canonical-repo gate, VERSION file). Color-coded ✓/⚠/✗, exit 1 on errors only.
- [x] **22. Journey-level `--dry-run`** on repo and fleet commands where previewing is meaningful. Repo coverage includes `init repo`, `prep repo`, and `refresh repo`; fleet coverage includes `init fleet`, `quickstart fleet`, `prep fleet`, `refresh fleet`, `update/discover fleet`, `add fleet`, and `docs fleet`. Each preview ends with "No changes written. Re-run without --dry-run to apply." Hard guarantee: zero filesystem or network side-effects in dry-run mode, covered by `tests/dry_run.bats`, `tests/fleet_dry_run.bats`, and refresh/prep fleet tests.
- [x] **23. Native `manifest pr` (no Cloud dependency).** Implemented in `modules/pr/manifest-pr-native.sh`. `pr create / status / checks / ready / merge / update / interactive` all wrap `gh`. Loader chain: native first → Cloud plugin (overrides if installed) → stub (fills queue/policy/etc. with "requires Cloud"). Stub now uses type-guards so it only defines what's missing. Help text + dispatcher updated. Verified `pr help` shows native + Cloud-only sections; `pr queue` correctly falls through to stub.

### Tier 5 — Fleet power

- [x] **24. `manifest ship fleet --only <service>` / `--except <service>`** — implemented. New `_fleet_filter_services` helper resolves a comma-separated/repeatable list against `$MANIFEST_FLEET_SERVICES`, errors on unknown names, and uses exact-token matching (so `--only alpha` won't accidentally match `alpha-svc`). `fleet_ship` parses both flags, rejects them as mutually exclusive, validates them before `--method`/init checks, and applies the filter by overriding `$MANIFEST_FLEET_SERVICES` for the workflow's lifetime. The override flows through `_fleet_prep_run`, `fleet_docs_generate`, and the `--noprep` dirty-check loop automatically; `--only`/`--except` are also forwarded to `manifest_fleet_pr_dispatch` so the Cloud plugin honors the same filter. The whole workflow runs inside a one-shot `while :; do ... break; done` block so any early failure restores the saved service list before returning. Help text on `manifest ship fleet --help` documents both flags + the mutual-exclusion rule. Thirteen bats tests in `tests/fleet_ship_filter.bats` cover the helper (only, except, csv, unknown service, word-boundary safety, no-op) and arg parsing (mutual exclusion, missing values, --help surface).
- [x] **25. Surface hidden fleet flags in help.** `manifest ship fleet --help` now lists every flag that fleet_ship accepts: `--noprep`, `--safe`, `--method <merge|squash|rebase>`, `--force`, `--no-delete-branch`, `--draft`. Help also includes a "Flow:" section showing the default vs. `--safe` pipeline so users know which step `--safe` adds. Bats coverage verifies all six flags appear in `--help` output.
- [x] **26. `manifest refresh fleet --commit`** — implemented. `manifest_refresh_fleet` now wires `--commit` through to a new `_refresh_fleet_commit_changes` helper that stages and commits refreshed metadata across the fleet root + each non-excluded service repo. Skips paths that are not git repos or have nothing to commit. Single fixed message ("Refresh fleet metadata") — no version bump, no tag, distinct from `ship fleet`. `--dry-run --commit` prints a "Would commit refreshed metadata across fleet root + services" preview and exits without writes. Removes the previous "redirect to ship fleet --local" stub. Uses `git -C "$path"` so subshell `cd` failures can't land commits in the wrong directory; protects against double-commits when a service's path equals the fleet root. Eight bats tests in `tests/refresh_fleet_commit.bats` cover help text, fleet-root committed/clean, service iteration, excluded-skip, non-git-skip, root/service path collision, and the dry-run preview.

### Tier 2 (additions found while resolving Tier 1)

- [x] **27. Consolidate canonical-repo detection.** Deleted the duplicate `manifest_origin_repo_slug` and `should_update_homebrew_for_repo` from `manifest-core.sh`; replaced with a one-line back-compat shim that delegates to `manifest_is_canonical_repo`. The latter now accepts the legacy `MANIFEST_CLI_HOMEBREW_ALLOWED_REPO_SLUGS` env var as a deprecated fallback (one-time warning via `log_deprecated`) when `MANIFEST_CLI_CANONICAL_REPO_SLUGS` is unset. Two new bats tests verify both back-compat paths.

### CI / Infrastructure (added during the build-out)

- [x] **28. GitHub Actions CI** — `.github/workflows/test.yml` runs the bats suite + smoke-tests `version`, `help`, `status`, `doctor` on `ubuntu-latest` and `macos-latest` for every push to main and every PR. `manifest --version` badge added to README.

### Fleet UX follow-ups (added 2026-05-04)

- [ ] **29. Fleet-aware repo identity preflight for `ship repo`.** In third-party use, especially from VS Code multi-root workspaces, the user may have several disparate repositories open at once. `manifest ship repo <type>` currently means "ship the enclosing Git repository for the terminal working directory"; that is correct mechanically but not explicit enough in a fleet. Before any mutation, `ship repo` should print the current Git root, origin slug, local branch/upstream, enclosing fleet root/name when detected, and matching fleet member name when configured. `manifest status repo` should show the same identity block read-only. Add a concise repo-local fleet hint whose variable names explain the relationship: `fleet.name` and `fleet.member` in project config, plus optional git-ignored `fleet.root` when the fleet root is not discoverable by walking upward. Treat the hint as a claim to verify against fleet config, not as authority. If the Git root is inside a fleet but does not match a configured member, warn before proceeding. If the Git root is the fleet root, explicitly say this targets only the fleet-root repo and is not `ship fleet`. This resolves the ambiguity where the editor's visible workspace folder, terminal cwd, fleet root, and target repo may differ.

### Release workflow regressions exposed by v46.7.0 (added 2026-05-05)

- [x] **30. Fix installed Homebrew CLI startup under Bash 3.2.** `manifest status`, `manifest ship repo minor`, and Homebrew postinstall all failed from the installed Cellar path with `manifest-yaml.sh: line 31: version.format: syntax error: invalid arithmetic operator`. Fixed by making Homebrew Bash a required formula dependency and generating an installed wrapper that re-execs into Bash 5 before sourcing `manifest-core.sh`. Added `tests/homebrew_wrapper.bats` to lock the wrapper ordering and dependency status.
- [ ] **31. Add ship resume/recovery for post-push failures.** During `v46.7.0`, the workflow committed the release and created `v46.7.0`, failed at `push_changes`, then manual push succeeded. The workflow had no supported "resume after push" path, so Homebrew formula update and local upgrade had to be run manually. Add `manifest ship repo resume` or an idempotent recovery mode that detects version/tag/push state and continues with skipped post-push steps.
- [ ] **32. Make tag push semantics exact and recovery text correct.** The failure report suggested `git push origin main --follow-tags`, but the lightweight tag still required `git push origin v46.7.0`. Either create annotated tags so `--follow-tags` is correct, push the explicit tag in `push_changes`, or update recovery output to use the exact tag push. Tests should cover the generated recovery command text at minimum.
- [ ] **33. Fix `manifest status` working-tree count rendering.** `manifest status` rendered `Working: 2 modified, 0` followed by `0 untracked`. Likely cause: `grep -c ... || echo 0` emits a counted `0` and then the fallback `0` when grep returns no matches. Replace these pipelines with count helpers that normalize output to a single integer.
- [ ] **34. Harden Homebrew postinstall and test it as an installed command.** `brew upgrade manifest` installed `46.7.0` but postinstall failed when it ran `manifest config doctor --fix --file ...`. Add a packaging/install smoke test that invokes the installed wrapper under the same shell path Homebrew uses, and make postinstall non-destructive and non-fatal when global config repair fails.

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

### Session 2026-04-25 (afternoon) — power features cluster (#19, #22, #14)

Resolved: **#14, #19, #22**. v44.4.0 was shipped public earlier in the day capturing the UX-cluster batch (#15/#16/#25).

**Decisions:**

- **JSON without jq.** Hand-rolled `_json_escape` / `_json_kv_str` / `_json_kv_raw` / `_json_value` in `manifest-shared-utils.sh`. Booleans/null/integers stay raw; everything else gets quoted+escaped. Keeps `--json` working in CI environments that don't have jq installed (and avoids a hard dependency for a low-volume use case).
- **Scope cut: `--json` on refresh + ship summary deferred.** Those are streaming side-effect operations whose JSON output requires plumbing structured step results back through orchestrator/fleet code. Doable but not cheap, and orthogonal to the read-only `status`/`config list` cases users actually need today for CI assertions. Left as a focused follow-up.
- **Fleet dry-runs are now part of the command surface.** `init fleet` previews Phase 1 TSV creation or Phase 2 selected-row application without prompts, GitHub checks, `git init`, or file writes. `quickstart fleet`, `add fleet`, and `docs fleet` also have read-only previews; `prep fleet` and `refresh/update/discover fleet` already had dry-run behavior.
- **Wizard helper extraction was test-driven.** Originally inlined the review block into `configure_interactive`, but that function gates on `[ -t 0 ]` which makes it nearly impossible to drive from bats without a TTY shim. Extracted the review+confirm into `_manifest_config_review_and_confirm` (positional args, returns 0/1, honors `MANIFEST_CLI_AUTO_CONFIRM=1`). Now unit-testable via plain bash, and the prod call site is one helper invocation instead of 50+ lines of echo/printf.
- **`_manifest_config_review_and_confirm` reuses `MANIFEST_CLI_AUTO_CONFIRM`** rather than introducing a wizard-specific bypass — same env var the global-config safety gate already honors, so users learn one knob.

**Files added (3):** `tests/json_output.bats` (12 tests), `tests/dry_run.bats` (7 tests), `tests/wizard_confirm.bats` (5 tests).
**Files modified (5):** `modules/core/manifest-shared-utils.sh` (JSON helpers), `modules/core/manifest-status.sh` (--json), `modules/core/manifest-config-crud.sh` (--json on list), `modules/core/manifest-{init,prep,refresh}.sh` (--dry-run on repo verbs), `modules/core/manifest-config.sh` (review-and-confirm helper extracted + called from wizard).
**Test count:** 79 bats tests (was 53, +12 JSON +7 dry-run +5 wizard +2 misc helpers, all passing on macOS).
**Open queue (5):** #6 (slim time module), #8 (re-home scaffolding), #9 (collapse dual fleet paths), #24 (ship fleet --only/--except), #26 (refresh fleet --commit).

### Session 2026-04-26 — Tier 2 cleanup batch 1 (#6)

Resolved: **#6**. (After this batch: 24/28 done, 4 open: #8, #9, #24, #26.)

**Decisions:**

- **`calculate_time_timestamp` collapsed into 6 lines.** The original 70-line implementation guarded against `bc` being absent, validated offset format with regex, branched on sign, and fell back to system time on bc errors — but at the very end it always did `cut -d. -f1` to drop the fractional part. Since the truncation was unconditional, the bc machinery was theatre. Replaced with `_manifest_time_apply_offset` doing pure-shell integer arithmetic via `BASH_REMATCH`. No precision loss versus the old code; one fewer external dependency.
- **Three dead functions removed without back-compat shims.** `get_timestamp`, `get_formatted_timestamp`, `display_time_os_info` had zero callers across modules + install-cli + tests (verified via grep). No reason to keep stubs around.
- **Sub-250 target deferred.** Hit 342 lines instead of the aspirational ~250. Further reduction would require either dropping the Cloudflare-trace sub-second precision branch or merging the two cache-mode paths in `_manifest_time_read_cache_data` — both are real features in active use, so the remaining line count is now mostly load-bearing logic, not bloat.
- **Tests use dynamic epoch generation.** First draft hard-coded `1775661917` for `"Fri, 04 Apr 2026 15:25:17 GMT"`, but BSD `date -jf` is strict about weekday consistency and Apr 4 2026 is actually a Saturday. Switched to building the date string from a known epoch using `date -u -r "$epoch"` (BSD) or `date -u -d "@$epoch"` (GNU) so the weekday is guaranteed correct on both platforms.

**Files added (1):** `tests/time.bats` (12 tests).
**Files modified (1):** `modules/system/manifest-time.sh` (764 → 342 lines, -422).
**Test count:** 91 bats tests (was 79, +12 time, all passing on macOS).

### Session 2026-04-26 (cont.) — Tier 2 cleanup batch 2 (#8)

Resolved: **#8**. (After this batch: 25/28 done, 3 open: #9, #24, #26.)

**Decisions:**

- **Pure mechanical move, zero behavior change.** The five scaffolding functions (`ensure_required_files`, `create_default_readme`, `create_default_changelog`, `ensure_gitignore_smart`, `create_default_gitignore`) along with their `.gitignore` template heredoc moved verbatim from `manifest-shared-functions.sh` into `manifest-init.sh`. The corresponding `export -f` line moved with them. No callers updated — all four cross-module consumers (`manifest-orchestrator.sh`, `manifest-documentation.sh`, `manifest-fleet.sh`, plus `manifest-init.sh` itself) reference these by bare name and bash resolves at call time, so load-order is a non-issue.
- **Why init owns scaffolding semantically.** These functions answer "what does a fresh manifest-managed repo look like?" — that's the init journey's defining contract. Other modules borrow them for repair/idempotency on existing repos (orchestrator's pre-flight, documentation's defensive recreate, fleet's per-repo gitignore wiring), but the source-of-truth for "default README/CHANGELOG/.gitignore" belongs with init. Added a SCAFFOLDING HELPERS comment block in init.sh's docblock to make the borrowing explicit.
- **Smoke-tested end-to-end.** Ran `manifest init repo --dry-run` and `manifest init repo` against an empty `/tmp/init-smoke` directory — produced .git/, VERSION, README.md, CHANGELOG.md, docs/, .gitignore, manifest.config.local.yaml exactly as before.

**Files modified (2):** `modules/core/manifest-shared-functions.sh` (1102 → 614, -488), `modules/core/manifest-init.sh` (348 → 844, +496).
**Test count:** 91 bats tests (unchanged — the helpers are exercised by existing tests via `manifest init` callers).

### Session 2026-04-26 (cont.) — Tier 5 — refresh fleet --commit (#26)

Resolved: **#26**. (After this batch: 26/28 done, 2 open: #9, #24.)

**Decisions:**

- **`--commit` is additive, not a replacement for `ship fleet`.** The previous stub redirected users to `ship fleet --local`, but those are different operations: `refresh` re-syncs state without bumping version or tagging, while `ship` is the bump-and-tag pipeline. The fixed commit message ("Refresh fleet metadata") makes it clear in `git log` that this commit is metadata maintenance, not a release.
- **`git -C "$path"` over `(cd "$path" && git ...)`.** Subshell `cd` followed by a chained `git add .` could land commits in the parent dir if `cd` fails (e.g., race-deleted path). `git -C` errors cleanly with no side effect.
- **Double-commit guard.** Single-repo fleets (where `MANIFEST_FLEET_ROOT == service.path`) would otherwise emit two commits — fleet root pass + service pass — for the same staged tree. Helper short-circuits the service iteration when `path == root_dir`.
- **Helper extraction made it testable.** Putting the commit pass in `_refresh_fleet_commit_changes` lets bats stub `get_fleet_service_property` + `MANIFEST_FLEET_SERVICES` and exercise the matrix without booting the full fleet stack (which requires `manifest.fleet.config.yaml`, `load_fleet_config`, `_fleet_require_initialized`, etc.).
- **Help text rewritten.** Old text said "Commit refreshed files across fleet (not yet implemented)" — actively misleading. Now describes what it does and points the user to `ship fleet` for releases so the boundary stays clear.

**Files modified (1):** `modules/core/manifest-refresh.sh`.
**Files added (1):** `tests/refresh_fleet_commit.bats` (8 tests).
**Test count:** 99 bats tests (was 91, +8 refresh-fleet-commit, all passing on macOS).

### Session 2026-04-26 (cont.) — Tier 2 — collapse dual fleet paths (#9)

Resolved: **#9**. (After this batch: 27/28 done, 1 open: #24.)

**Decisions:**

- **Strict interpretation: rename + remove the dispatcher routes outright.** Tracker said "remove dispatcher routes" — not "soft-deprecate". Did the strict version: `fleet_main` no longer has `start)`, `init)`, `sync)` cases. The unknown-command fallback grew a small `start|init|sync)` arm that detects each removed verb and prints a one-line hint pointing at the v42 entry point (`manifest init fleet` for start/init, `manifest prep fleet` for sync). This is the same pattern as `fleet_main *)` but with a useful migration message instead of generic help-dump-on-error.
- **The renamed functions are still callable internally — only the public surface narrowed.** `fleet_quickstart` still works (calls `_fleet_init --_quickstart`); `manifest init fleet` still scaffolds (Phase 1 → `_fleet_start`, Phase 2 → `_fleet_init`); `manifest prep fleet` still clones/pulls (→ `_fleet_sync`). The bats suite proves the function visibility flip — `declare -F fleet_start` now fails, `declare -F _fleet_start` succeeds.
- **Why not soft-deprecate via `log_deprecated` like #13 did for `manifest sync`/`manifest update`?** Those wrap *the entire CLI verb* and there's no strong reason to remove them — the alias has no maintenance cost. Here the dual fleet path is a *structural* problem: same logic reachable two ways means future changes have to update both call sites and reason about both surfaces. Removing the routes (rather than wrapping them) is what actually collapses the duality. The migration hint covers users mid-flight without keeping the second path alive.
- **Doc updates were load-bearing, not cosmetic.** `COMMAND_REFERENCE.md` had the legacy fleet block as the canonical fleet reference for users — that's been wrong since v42 introduced `manifest init/prep/refresh/ship fleet`. Reorganized it to lead with the v42 entry points and demote the still-supported legacy commands (status, update, discover, add, validate, prep, pr, docs, quickstart) to a "Legacy-only" subsection. `FLEET_DESIGN_SPEC.md` §5.5 updated to say "manifest init fleet" instead of "manifest fleet init" (this was a v39-era line).
- **Migration label: "Removed in v44.9.0".** Used a forward-pointing version since the next ship from this branch will be v44.9.0 (#9 is the only Tier 2 change in this batch). If the ship lands at a different version, the doc note can be corrected then — better to commit a specific version than the vague "recently".

**Files modified (5):** `modules/fleet/manifest-fleet.sh` (renames, dispatcher rewrite, help text), `modules/core/manifest-init.sh` (callsite + docblock), `modules/core/manifest-prep.sh` (callsite + docblock), `docs/USER_GUIDE.md`, `docs/EXAMPLES.md`, `docs/COMMAND_REFERENCE.md`, `docs/FLEET_DESIGN_SPEC.md`.
**Files added (1):** `tests/fleet_private_routes.bats` (7 tests).
**Test count:** 106 bats tests (was 99, +7 fleet-private-routes, all passing on macOS).

### Session 2026-04-26 (cont.) — Tier 5 — fleet ship --only/--except (#24)

Resolved: **#24**. (After this batch: 28/28 done. Tracker complete.)

**Decisions:**

- **Filter mechanism: env-override of `$MANIFEST_FLEET_SERVICES`.** Both `_fleet_prep_run` and `fleet_docs_generate` iterate the env var directly, so overriding it for the duration of `fleet_ship` filters every code path that respects it — no need to thread an extra "service list" arg through five functions. The override is restored on every exit path (success or failure) via a `while :; do ... break; done` one-shot block + a single `MANIFEST_FLEET_SERVICES="$_saved_services"` cleanup line.
- **Forward `--only`/`--except` to `manifest_fleet_pr_dispatch` too.** The Cloud plugin owns its own service iteration; if it doesn't read `$MANIFEST_FLEET_SERVICES` (we can't see the plugin source from this repo), forwarding the flags lets it apply the same filter on its side. The native stub harmlessly ignores extra args ("PR feature requires Manifest Cloud").
- **Word-boundary safety: substring match with space padding, not `grep -w`.** `grep -w` treats hyphens as separators, so `--only alpha` would falsely match `alpha-svc`. Switched to `[[ " $MANIFEST_FLEET_SERVICES " == *" $name "* ]]` — only spaces are token separators, which matches how the service list is actually built.
- **Validation order matters.** Mutual-exclusion check fires first, then `--method` validation, then init-required gate, then filter resolution. This means `manifest ship fleet --only foo --except bar` errors out cleanly without ever touching fleet config.
- **Filter result message.** Print "🎯 Filter applied: alpha charlie" before the workflow banner so users can see which subset is shipping. Suppressed when no filter is in play to avoid noise on the common path.

**Files modified (4):** `modules/fleet/manifest-fleet.sh` (helper, parsing, override + restore, forwarding), `docs/COMMAND_REFERENCE.md`, `docs/USER_GUIDE.md`, `docs/EXAMPLES.md`.
**Files added (1):** `tests/fleet_ship_filter.bats` (13 tests).
**Test count:** 119 bats tests (was 106, +13 fleet-ship-filter, all passing on macOS).

### Session 2026-05-05 — v46.7.0 ship run exposed new release workflow debt

The user requested `manifest ship repo minor`. The installed Homebrew command failed before dispatch with the YAML mapping / Bash startup error, so the repo-local CLI was used to complete the release. `v46.7.0` was created, pushed, and the Homebrew tap was updated, but the run exposed more new problems than old tracker items closed.

Durable handoff: [RELEASE_RUN_HANDOFF_v46.7.0.md](RELEASE_RUN_HANDOFF_v46.7.0.md).

New tracker items opened: **#30-#34**.

Final release state:

- CLI repo `origin/main`: `7f92aaf Update Homebrew formula to v46.7.0`
- Release tag: `v46.7.0` at `154f87e`
- Homebrew tap: `58d84ad Update formula to v46.7.0`
- Homebrew formula SHA: `cbefe6648491575a9fe86544c067e6c96d446d6e22f444737c1b1fdbde0bd61b`
- Known unresolved in the installed `v46.7.0` package: `manifest` still fails at startup after `brew upgrade manifest` until a build containing item #30 is installed.
