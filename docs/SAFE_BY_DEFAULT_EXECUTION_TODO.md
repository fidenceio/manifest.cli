# Safe-by-Default Execution Notes

**Status:** Implemented for the core journey and ship paths; remaining work tracks edge commands and Cloud integrations.
**Created:** 2026-05-06
**Goal:** Keep every mutating Manifest workflow preview-first, require `-y` or `--yes` to apply, and keep PR operations out of release shipping.

## Current Contract

Manifest CLI uses one execution contract for the public workflow surface:

```text
default = preview
--dry-run = explicit preview
-y / --yes = apply
--local -y = apply local writes only
```

`manifest_execution_parse()` in `modules/core/manifest-execution-policy.sh`
centralizes the contract for `ship` and other migrated commands. `--dry-run`
and `-y` are contradictory; `--local` narrows scope but does not authorize
writes by itself; `MANIFEST_CLI_AUTO_CONFIRM=1` answers prompts only after
apply mode is already selected.

## Ecosystem Operating Model

Safe-by-default must be an ecosystem contract, not only a CLI parsing change.

```text
Manifest CLI defines execution intent.
Recipes describe effects.
Fleet expands scope.
Manifest Cloud enforces remote/policy/queue behavior.
No layer silently escalates preview into apply.
```

| Component | Responsibility | Current state |
| --- | --- | --- |
| Manifest CLI | Own the user-facing execution contract and normalize `preview|apply`, `local|remote`, and service scope | Core journey docs teach preview-first and `-y` apply |
| Manifest Fleet | Expand one command across many repos without changing intent | Fleet ship previews by default and applies only with `-y` |
| Manifest Cloud | Own Cloud APIs, queueing, policy, and hosted automation | Keep Cloud mutating behavior behind explicit PR/Cloud commands |
| Recipes | Make workflows explainable and testable behind first-class commands | Built-in ship recipes declare ordered steps and effect metadata |
| Manifest CLI canonical repo | Dogfood the contract first | Repo ship, GitHub Release creation, Homebrew publishing, and follow-up patch are covered by release tests |
| Homebrew Tap | Distribution-only formula repo | Updated only from the canonical CLI release path |
| Documentation | Teach the behavior clearly | Public docs use "command previews, command -y applies" wording |

## Verification Checklist

- [ ] A command that can mutate local files, commits, tags, pushes, remotes, PRs, or queues must preview by default.
- [ ] `--dry-run` must be accepted as an explicit spelling of the default preview mode on every mutating command.
- [ ] `-y` and `--yes` are the only normal user-facing flags that authorize mutation.
- [ ] `--local` limits the apply scope; it does not authorize apply by itself.
- [ ] `--local -y` may write local files and commits when the command allows local writes, but must not push, tag remote refs, create PRs, queue PRs, merge, or mutate remote repositories.
- [ ] `MANIFEST_CLI_AUTO_CONFIRM=1` may bypass interactive prompts only after apply mode has already been selected; it must not convert preview mode into apply mode.
- [ ] `ship` must never create, queue, ready, merge, or check PRs. PR behavior belongs only under `manifest pr ...`.
- [ ] Recipes must declare whether a step is read-only, local-write, or remote-write so preview/apply behavior is visible before execution.
- [ ] Help text, examples, completions, tests, and docs must all teach the same contract.

## Remaining Hardening

- [ ] Build the shared execution-policy module first. Do not retrofit one command at a time with ad hoc parsing.
- [ ] Treat this as a major release. The change is safer, but it intentionally changes long-standing behavior.
- [ ] Add plan objects before apply logic. Every mutating command should be able to produce a useful plan without doing the work.
- [x] Make `--dry-run` and `-y` mutually exclusive. If both are present, fail with a clear contradictory-flags error instead of guessing.
- [ ] Keep `--force` separate from `-y`. `--force` may bypass a readiness gate only after `-y` has selected apply mode.
- [ ] Keep `MANIFEST_CLI_AUTO_CONFIRM=1` separate from `-y`. Automation may answer prompts, but it must not authorize mutation.
- [ ] Move PR orchestration out of `ship fleet` before broad command migration so the highest-risk semantic bug is fixed early.
- [ ] Define a service releaseability model in fleet config instead of relying only on file presence over time.
- [ ] Prefer a single "plan then apply" renderer for repo, fleet, PR, and Cloud-backed commands.
- [ ] Include exact replay commands in every preview so users do not have to infer how to apply.
- [ ] Make Cloud APIs require explicit apply intent even when called by automation, not only when called through the CLI.
- [ ] Keep the Homebrew Tap formula-only and release-disabled by default.
- [ ] Use the five-repo Manifest workspace as the acceptance test before public release.

## Command Contract

| Command family | Default action | With `-y` / `--yes` | Remote effects with `-y`? | PRs? |
| --- | --- | --- | --- | --- |
| `manifest help`, `--help`, `version` | Show information | Same | no | no |
| `manifest status repo/fleet` | Report state | Same | no | no |
| `manifest validate repo/fleet` | Validate state | Same | no | no |
| `manifest doctor` | Diagnose environment/repo/config | Same unless a fix flag is present | no | no |
| `manifest doctor --fix` | Preview fixes | Apply fixes | local only unless explicitly documented | no |
| `manifest config list/get/describe` | Read config | Same | no | no |
| `manifest config set/unset` | Preview config write | Write config | local/global file write only | no |
| `manifest init repo` | Preview repo scaffolding | Write repo scaffolding | no, unless explicit create-remote flag is also present | no |
| `manifest init fleet` | Preview fleet config/inventory | Write fleet config/inventory | no, unless explicit create-remote flag is also present | no |
| `manifest quickstart fleet` | Preview discovered fleet setup | Write fleet setup | no, unless explicit create-remote flag is also present | no |
| `manifest add fleet` | Preview fleet membership change | Update fleet config | no, unless explicit create-remote flag is also present | no |
| `manifest discover fleet` | Discover only | Same | no | no |
| `manifest update fleet` | Preview fleet membership refresh | Update fleet config/inventory | no | no |
| `manifest prep repo` | Preview local prep | Apply local prep | no | no |
| `manifest prep fleet` | Preview local prep across services | Apply local prep across selected services | no | no |
| `manifest refresh repo` | Preview metadata/docs refresh | Write refreshed metadata/docs | local only, unless explicit push/commit behavior is documented | no |
| `manifest refresh fleet` | Preview scan/docs/inventory refresh | Write refreshed fleet state | local only, unless explicit `--commit`/remote behavior is documented | no |
| `manifest refresh fleet --commit` | Preview refresh plus commits | Commit refreshed metadata where changed | local commits only | no |
| `manifest docs repo/fleet` | Preview documentation writes | Write documentation | no | no |
| `manifest docs cleanup` | Preview archive/cleanup changes | Move/prune docs according to policy | no | no |
| `manifest ship repo <type>` | Preview release plan | Version, docs, commit, tag, push, downstream hooks | yes | no |
| `manifest ship repo <type> --local` | Preview local release prep | Local release prep only | no | no |
| `manifest ship fleet <type>` | Preview coordinated release plan | Ship eligible fleet repos directly | yes | no |
| `manifest ship fleet <type> --local` | Preview local fleet release prep | Local release prep only | no | no |
| `manifest pr repo ...` | Preview PR operation | Execute requested PR operation | yes | yes |
| `manifest pr fleet ...` | Preview fleet PR operation | Execute requested fleet PR operation | yes | yes |
| `manifest recipe list/show/explain` | Read recipe metadata | Same | no | no |
| `manifest recipe run <id>` | Hidden compatibility shim only | Deprecated; use the mapped first-class command | no new public contract | no new public contract |
| `manifest uninstall` | Preview uninstall changes | Remove installed files/config references | local machine only | no |
| `manifest reinstall` | Preview reinstall steps | Reinstall | network/local install effects | no |

## Edge Cases and Decisions

### Flag Semantics

| Edge case | Decision |
| --- | --- |
| `--dry-run -y` together | Error. Contradictory intent should not be resolved implicitly. |
| `--local` without `-y` | Preview local-only changes. No writes. |
| `--local -y` | Apply local writes only. No remote effects. |
| `--force` without `-y` | Preview that force would be used. Do not apply. |
| `--force -y` | Apply and bypass only the documented readiness gate. Do not bypass execution-policy checks. |
| `MANIFEST_CLI_AUTO_CONFIRM=1` without `-y` | Still preview. Never apply. |
| `MANIFEST_CLI_AUTO_CONFIRM=1 -y` | Apply and skip prompts where prompt automation is already supported. |
| Repeated `-y` or `--yes` | Accept as idempotent. |
| Repeated `--dry-run` | Accept as idempotent. |
| Unknown execution flag | Fail through the shared help/error template. |
| Alternate apply flags (`--apply` or `--do`) | Either normalize into `-y` with one warning or reject consistently; choose before implementation. |

### Repo State

| Edge case | Decision |
| --- | --- |
| Dirty working tree in preview | Report dirty files and whether apply would stop. |
| Dirty working tree in apply | Stop unless the command explicitly owns those writes and the plan says so. |
| Untracked files | Report separately; do not silently stage unless the command owns them. |
| Detached HEAD | Preview reports; apply stops for ship and PR operations. |
| Missing upstream | Preview reports; remote apply stops unless the command explicitly creates/configures upstream. |
| Branch behind remote | Preview reports pull/rebase need; apply stops for ship unless prep/sync has handled it. |
| Branch ahead of remote | Preview reports push consequences; apply may push only on ship/PR commands with `-y`. |
| Existing tag for target version | Preview reports conflict; apply stops and points to resume/recovery if appropriate. |
| Missing `VERSION` | Fleet ship skips by default; repo ship stops with a clear "not releaseable" message. |
| Malformed `VERSION` | Preview reports invalid version; apply stops. |
| Repo path is fleet root `.` | Treat as workspace infrastructure unless explicitly release-enabled. Prevent double-apply. |
| Nested git repos | Fleet scope must select configured member paths only; no recursive surprise mutation. |
| Symlinked service path | Resolve and display real path; stop if it escapes allowed fleet root unless explicitly configured. |
| Submodules | Preview as submodule/pinned state; do not mutate by default unless fleet config opts in. |

### Fleet Scope

| Edge case | Decision |
| --- | --- |
| `--only` selects unknown service | Error before plan execution. |
| `--except` selects unknown service | Error before plan execution. |
| `--only` and `--except` together | Error. |
| Filter selects zero services | Error. |
| Service path missing | Preview reports missing; apply stops unless command is `prep fleet -y` and clone behavior is configured. |
| Service excluded in fleet config | Skip by default and show why. |
| Homebrew Tap selected explicitly | Show formula-only/release-disabled status; do not version unless config explicitly overrides. |
| Mixed releaseable and non-releaseable services | Ship releaseable services only if policy allows partial release; otherwise require an explicit fleet policy decision. |
| Partial failure during fleet apply | Stop after failed service, report completed/skipped/failed services, and print recovery commands. |
| Fleet docs generation failure | Preview reports risk; apply stops if docs are required, warns if docs are optional. |
| Multiple services share same git root | Detect and stop unless explicitly modeled to avoid double commits/tags. |

### Ship Boundary

| Edge case | Decision |
| --- | --- |
| Fleet requires PR review before release | `ship fleet` stops and tells the user to run `manifest pr fleet ... -y`. |
| PR branch exists from prior run | Handled by `manifest pr`, not `manifest ship`. |
| Ship apply after preview plan changes | Recompute the plan at apply time; do not trust stale preview output. |
| Repo ship in a fleet member | Print repo/fleet identity block and ship only the current repo. |
| Repo ship from fleet root | Make clear this is not `ship fleet`; stop unless root is release-enabled. |
| Follow-up patch automation | Must pass `-y` explicitly when it intentionally applies. |
| Homebrew formula refresh | Remains a downstream hook of CLI repo ship, not independent Tap ship. |
| Release notes provider failure | Apply follows existing required/optional policy; preview reports provider availability without invoking remote providers unless configured safe. |

### PR and Cloud

| Edge case | Decision |
| --- | --- |
| `manifest pr create` without `-y` | Preview branch/title/body/base/head and exact apply command. |
| `manifest pr queue` without `-y` | Preview queue target and policy checks. |
| `manifest pr merge` without `-y` | Preview merge method and target PR. |
| Cloud plugin receives preview intent | It must not create PRs, queue jobs, merge, or mutate policy state. |
| Cloud plugin receives apply intent | It must verify explicit apply intent and include it in audit logs. |
| CLI preview but Cloud default differs | CLI intent wins. Cloud must reject ambiguous or missing intent. |
| Offline mode with Cloud-backed command | Preview can explain missing Cloud; apply stops unless an offline/local implementation exists. |
| API tokens present in preview | Never display token values. Show token source only. |

### Recipes

| Edge case | Decision |
| --- | --- |
| Recipe has missing effect metadata | Schema/test failure; built-in recipe cannot ship. |
| Recipe mixes read and write steps | The mapped first-class command previews the plan and applies only after `-y`. |
| Recipe has PR step under ship command | Invalid built-in recipe. |
| User recipe calls external command | Do not expose direct execution; first add a named command that owns parsing, policy, and help text. |
| Recipe step effect is `remote-write` with `--local -y` | The mapped first-class command must skip or fail according to policy; never run remote effect. |
| Recipe explain | Always read-only and must show effect metadata. |
| Recipe run | Hidden/deprecated compatibility shim; not a product path to harden as a new command surface. |

### Docs, Config, and Install

| Edge case | Decision |
| --- | --- |
| `config set` writes global config | Preview by default; `-y` applies; existing double-confirm still applies unless automated. |
| `config doctor --fix` | Preview fixes by default; `-y` applies fixes. |
| Config wizard final write | Preview/review by default; write only with `-y` or explicit final confirmation in an interactive flow that maps to apply mode. |
| Docs cleanup prune | Preview files to move/delete; `-y` applies; retain pre-delete safety checks. |
| Uninstall | Preview removals; `-y` required for removal. |
| Reinstall | Preview reinstall plan; `-y` required. |
| Generated docs examples | Must not teach bare mutating commands as apply commands. |

## Implementation Checklist

### Phase 0 - Ecosystem Alignment

- [ ] Add this contract to Manifest Cloud planning docs before Cloud implementation.
- [ ] Add a Cloud API requirement: mutating endpoints require explicit `execution_mode=apply`.
- [ ] Add a Cloud audit requirement: every apply request records actor, source, command, scope, and plan hash.
- [x] Add a Fleet config requirement for `release.enabled` and `release.strategy`.
- [x] Mark Homebrew Tap as release-disabled in the workspace fleet config.
- [ ] Add Workspace fleet dogfood acceptance criteria covering all five repos.
- [ ] Add marketing/docs migration language before the major release ships.
- [ ] Decide whether legacy `--apply` / `--do` are accepted as deprecated aliases or rejected.

### Phase 1 - Shared Execution Policy

- [x] Add a shared execution-policy module, likely `modules/core/manifest-execution-policy.sh`.
- [x] Parse `--dry-run`, `-y`, `--yes`, and `--local` consistently before command-specific mutation starts.
- [ ] Export normalized state such as:
  - `MANIFEST_CLI_EXECUTION_MODE=preview|apply`
  - `MANIFEST_CLI_EFFECT_SCOPE=read|local|remote`
  - `MANIFEST_CLI_LOCAL_ONLY=true|false`
- [ ] Add helpers:
  - `manifest_execution_parse_flags`
  - `manifest_execution_is_preview`
  - `manifest_execution_is_apply`
  - `manifest_execution_require_apply`
  - `manifest_execution_print_replay_hint`
  - `manifest_execution_render_plan_table`
- [ ] Keep `MANIFEST_CLI_AUTO_CONFIRM=1` as prompt automation only; do not treat it as `--yes`.
- [ ] Make unknown or misplaced execution flags fail through the shared help/error template.
- [x] Detect contradictory flags such as `--dry-run -y` before loading command-specific state.
- [ ] Preserve the original user command so replay hints can be generated accurately.
- [ ] Add a plan fingerprint/hash helper for comparing preview and apply runs.

### Phase 2 - Command Migration

- [ ] Convert `init repo` and `init fleet` to preview by default; require `-y` for writes.
- [ ] Convert `quickstart fleet`, `add fleet`, and `update fleet` to preview by default; keep `discover fleet` read-only.
- [ ] Convert `prep repo` and `prep fleet` to preview by default; require `-y` for local prep.
- [ ] Convert `refresh repo` and `refresh fleet` to preview by default; require `-y` for writes.
- [ ] Convert `refresh fleet --commit` so the commit pass requires `-y`.
- [ ] Convert `docs repo`, `docs fleet`, and docs cleanup/archive paths to preview by default.
- [ ] Convert `config set`, `config unset`, and `config doctor --fix` to preview by default.
- [x] Convert `ship repo` to preview by default; require `-y` for version/docs/commit/tag/push.
- [x] Convert `ship fleet` to preview by default; require `-y` for direct release of eligible services.
- [ ] Convert native PR commands so `pr create`, `ready`, `merge`, `queue`, and fleet equivalents preview by default and require `-y`.
- [ ] Audit `uninstall` and `reinstall`; require `-y` before destructive local-machine changes.
- [ ] Audit legacy aliases and deprecation paths so aliases inherit the same policy.
- [ ] Audit scripts and generated hooks that call Manifest recursively; add explicit `-y` only where apply is intended.
- [ ] Audit CI workflows and release automation that currently call mutating commands without `-y`.

### Phase 3 - Fleet Ship Boundary Fix

- [x] Remove `manifest_fleet_pr_dispatch create` from `fleet_ship`.
- [x] Remove `manifest_fleet_pr_dispatch checks` from `fleet_ship`.
- [x] Remove `manifest_fleet_pr_dispatch ready` from `fleet_ship`.
- [x] Remove `manifest_fleet_pr_dispatch queue` from `fleet_ship`.
- [x] Define releaseable fleet services conservatively:
  - [x] has `VERSION` -> releaseable by default
  - [x] no `VERSION` -> skipped by default
  - [x] Homebrew Tap -> skipped as formula-only
  - [x] fleet root workspace -> skipped unless explicitly configured
- [x] Add service-level release config for overrides:
  - `release.enabled: true|false`
  - `release.strategy: direct|none`
- [x] Preserve `--only` and `--except` filtering across preview and apply.
- [x] Produce a fleet ship plan table before any apply work.
- [ ] Stop with a clear message if a fleet requires PR review first; tell the user to run `manifest pr fleet ... -y` explicitly.
- [ ] Add fleet partial-failure recovery output.
- [ ] Recompute fleet plan at apply time and warn if it differs from a previous preview.
- [x] Add explicit behavior for releaseable/non-releaseable mixed fleets.

### Phase 4 - Recipes

- [x] Extend the recipe schema with step effect metadata:
  - `effect: read`
  - `effect: local-write`
  - `effect: remote-write`
  - `effect: pr`
- [x] Add recipe-level execution policy:
  - `default_mode: preview`
  - `requires_yes_for: [local-write, remote-write, pr]`
- [x] Update all built-in repo ship recipes.
- [x] Update all built-in fleet ship recipes and remove PR steps from them.
- [x] Update PR recipes so PR effects are explicit and require `-y`.
- [x] Make `manifest recipe explain` show effect levels per step.
- [x] Do not promote `manifest recipe run <id>` as a public command surface; recipes are inspectable contracts behind named commands.
- [x] Add schema tests so a built-in recipe cannot omit effect metadata.
- [x] Add recipe validation that rejects PR effects in built-in ship recipes.
- [x] Validate mapped first-class commands so `--local -y` cannot execute recipe steps with `remote-write` effects.

### Phase 5 - User Experience

- [ ] Standardize preview output headings:
  - `Preview - no changes written`
  - `Would write`
  - `Would commit`
  - `Would tag`
  - `Would push`
  - `Would create PR`
  - `Would queue PR`
- [ ] End every mutating preview with the exact replay command including `-y`.
- [ ] In apply mode, print the same plan first, then `Applying because -y/--yes was provided`.
- [ ] Make preview tables dense and scannable for fleet commands.
- [ ] Add a short "Safe by default" section to README, User Guide, Command Reference, and Examples.
- [ ] Update shell completions for `-y`, `--yes`, and `--dry-run` on every mutating command.
- [ ] Update help examples so bare mutating commands show previews and applied examples include `-y`.
- [x] Update error messages that currently say "Re-run without --dry-run" to "Re-run with -y to apply".
- [ ] Add a migration note for users upgrading from pre-change behavior.
- [x] Add one consistent contradictory-flags error:
  - `Cannot combine --dry-run with -y/--yes. Preview is already the default; remove --dry-run to apply.`
- [x] Add one consistent apply banner:
  - `Applying because -y/--yes was provided.`
- [x] Add one consistent preview footer:
  - `No changes written. Re-run with -y to apply this plan.`
- [ ] Make tables include `Effect`, `Scope`, and `Apply command` where useful.

### Phase 6 - Tests

- [x] Add a command-surface inventory test that verifies every mutating command accepts `--dry-run`, `-y`, and `--yes`.
  - Covered by `tests/command_surface_inventory.bats`; this also tightened stale help for quickstart/add/update/docs fleet and config doctor.
- [ ] Add no-write tests for each preview path using git porcelain and file snapshots.
- [ ] Add apply tests for focused local-only commands.
- [x] Add guarded remote-effect tests so local apply rejects active `remote-write` recipe steps before dispatch.
- [ ] Add tests proving `MANIFEST_CLI_AUTO_CONFIRM=1` does not imply apply.
- [x] Add tests proving `ship fleet` never calls PR dispatch.
- [ ] Add tests proving PR commands do not execute without `-y`.
- [x] Add recipe schema tests for effect metadata.
- [ ] Add docs/completion tests for `-y`, `--yes`, and safe-by-default examples.
- [ ] Run targeted container tests after each phase.
- [ ] Run the full container suite before shipping.
- [ ] Add Cloud contract tests or API stubs proving missing apply intent is rejected.
- [ ] Add workspace-fleet dogfood tests:
  - CLI and Cloud releaseable
  - Homebrew Tap formula-only
  - Workspace root infrastructure-only
  - Marketing website non-releaseable unless configured
- [ ] Add automation tests proving recursive Manifest calls pass `-y` only when intended.

### Phase 7 - Release and Migration

- [ ] Ship as a major release because the default behavior changes.
- [ ] In release notes, lead with "Manifest is now safe by default."
- [ ] Call out the migration:
  - before: `manifest ship repo patch`
  - after preview: `manifest ship repo patch`
  - after apply: `manifest ship repo patch -y`
- [ ] Add one release-cycle warning when users run a bare mutating command in preview mode:
  - "This command now previews by default. Add -y to apply."
- [ ] Keep the warning concise and suppressible after the user has seen it.
- [ ] Verify installed Homebrew CLI behavior after release:
  - `manifest ship repo patch` previews
  - `manifest ship repo patch --dry-run` previews
  - `manifest ship repo patch -y` applies
  - `manifest ship fleet patch` previews
  - `manifest ship fleet patch --dry-run` previews
  - `manifest ship fleet patch -y` does not call PR commands

## Ecosystem Acceptance Criteria

- [ ] `manifest ship repo patch` previews in the CLI repo.
- [ ] `manifest ship repo patch --dry-run` previews in the CLI repo.
- [ ] `manifest ship repo patch -y` applies in the CLI repo.
- [ ] `manifest ship fleet patch` previews across the five-repo workspace.
- [ ] `manifest ship fleet patch --dry-run` previews across the five-repo workspace.
- [ ] `manifest ship fleet patch -y` ships only release-enabled services and never calls PR dispatch.
- [ ] `manifest pr fleet create` previews and does not call `gh` or Cloud mutation.
- [ ] `manifest pr fleet create -y` executes only the PR workflow.
- [ ] Manifest Cloud rejects mutating requests that omit explicit apply intent.
- [ ] Homebrew Tap is skipped by fleet ship and updated only through CLI formula release flow.
- [ ] Generated docs, command reference, examples, completions, and README all show the same safe-by-default model.
- [ ] The major-release notes clearly state the breaking change and migration commands.

## Likely Files

- `modules/core/manifest-core.sh`
- `modules/core/manifest-init.sh`
- `modules/core/manifest-prep.sh`
- `modules/core/manifest-refresh.sh`
- `modules/core/manifest-ship.sh`
- `modules/core/manifest-config.sh`
- `modules/core/manifest-config-crud.sh`
- `modules/core/manifest-doctor.sh`
- `modules/core/manifest-shared-utils.sh`
- `modules/fleet/manifest-fleet.sh`
- `modules/fleet/manifest-fleet-docs.sh`
- `modules/recipe/manifest-recipe.sh`
- `modules/pr/manifest-pr-native.sh`
- `modules/stubs/manifest-pr-stub.sh`
- `recipes/builtin/*.yaml`
- `docs/contracts/recipe.schema.json`
- `completions/manifest.bash`
- `completions/_manifest`
- `README.md`
- `docs/USER_GUIDE.md`
- `docs/COMMAND_REFERENCE.md`
- `docs/EXAMPLES.md`
- `docs/FLEET_DESIGN_SPEC.md`
- `../fidenceio.manifest.cloud/docs/*`
- `../fidenceio.manifest.cloud/*`
- `../manifest.fleet.config.yaml`

## Verification Commands

```bash
./scripts/run-tests-container.sh tests/dry_run.bats
./scripts/run-tests-container.sh tests/fleet_dry_run.bats
./scripts/run-tests-container.sh tests/fleet_ship_filter.bats
./scripts/run-tests-container.sh tests/recipe.bats
./scripts/run-tests-container.sh tests/refresh_fleet_commit.bats
./scripts/run-tests-container.sh tests/homebrew_wrapper.bats
./scripts/run-tests-container.sh
```

Manual installed checks after shipping:

```bash
manifest ship repo patch
manifest ship repo patch --dry-run
manifest ship fleet patch
manifest ship fleet patch --dry-run
manifest pr fleet create
manifest status fleet
```
