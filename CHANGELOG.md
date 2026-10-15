# Changelog

## [62.0.0] - 2026-09-18

**Release Type:** Major

### Behaviour changes on upgrade

- **Command cleanup is intentionally breaking.** Use bare `manifest init` for guided onboarding. `first`, `prep`, `refresh`, `sync`, `time`, the noun-first `fleet` route, bare `ship <bump>`, and `recipe run` are removed rather than retained as hidden aliases. Use `init repo` / `init fleet`, `ship repo <bump>` / `ship fleet <bump>`, and the documented recipe commands. Removed routes and flags refuse before configuration or upgrade side effects. See docs/MIGRATION.md.
- **Init prepares the repository for shipping and previews by default.** Apply with `-y` to initialize Git, establish or create the origin (private by default), connect existing history before scaffolding, preserve existing files, and run the configured readiness checks. Init does not commit, bump, tag, release, or push. Existing project checks retain their execution behavior; generated checks install their dependencies inside Docker.
- **Fleet ships include the manager repository**, including manager-only coordination changes and fleets with versioning disabled. Manager commits stage only coordination files and report partial failures accurately.
- **Revert requires an explicit scope.** `revert repo` restores an exact release tag; `revert fleet` restores the member commits recorded in a manager snapshot. Both preview by default. Apply validates targets and write guards; fleet restore preflights all repositories and restores the manager last. Earlier manager history without a snapshot map cannot reconstruct a fleet.
- **A `MANIFEST_CLI_*` environment override containing spaces or newlines now takes effect correctly.** GNU `env` quoting previously corrupted that highest-precedence layer from v47.11.0 through v61.2.1. After upgrading, settings that were silently ignored may become active.

### Fixes

- Redact credentials in init remote previews and replay hints while retaining the actual URL for execution.
- Preserve local and remote content during init; refuse unreadable origins, divergence, conflicting targets, incorrect release branches, missing identity, invalid versions, and failed or missing verification. Project configuration and configuration fetched from origin select the same checks and release branch as the next ship.
- Preserve conflicting tracked, untracked, and ignored files during revert; resolve annotated tags to exact commits; reject fleet traversal, symlink escapes, duplicate paths, malformed snapshots, and locked targets. Partial restore failures identify the unfinished work.
- Preserve readonly module constants during uninstall's exported-variable sweep, and enumerate exported names without parsing `env` output.
- Honor `MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT` for formula publication from containers and CI without a local Homebrew installation; an invalid explicit checkout fails rather than choosing another tap.
- Continue HTTPS timestamp verification, caching, and labelled system-time fallback through the retained timestamp functions and `manifest config time`.

### Tests and verification

- Run CI validation inside containers without installing dependencies on runner hosts. Native macOS-only cases remain an explicit coverage gap.
- Add init-to-first-local-ship, manager shipping, and repo/fleet restore regressions using disposable local Git repositories.
- Enforce both passing controls and challenging cases for all 24 registered safety contracts in full, smoke, and change-aware runs. Missing, failed, duplicated, or skipped proofs fail the contract gate.
- Include all runtime shell files in the executable-line coverage denominator, including never-loaded files. Report line coverage separately from the safety-contract gate; this release does not claim 100% executable-line coverage.
- Validate parser failure with malformed syntax supported by both older and current yq; current yq intentionally accepts conditional expressions that an obsolete negative control rejected.
- Keep coverage source mounts read-only, preserve the checkout's version in malformed-input fixtures, and prevent large TAP streams from blocking the coverage tracer. Verification-script changes invalidate cached green results.

### Documentation

- Update command reference, migration instructions, workflow examples, shell completions, installer command catalogs, and transaction documentation to match the final command surface. Preserve historical tracker evidence while pointing live onboarding links at the retained modules.



## [61.2.1] - 2026-09-14

**Release Type:** Patch

### Changes

- Docs(tracker,agents): trim the register to what is open, and stand up the review panel (§2, §3, §25, §36, §52, §69, §78, §81, §82, §88, §90, §91)
- Docs(tracker): state the VERSION-ahead-of-code fact as a derivation, not a number (§5)


## [61.2.0] - 2026-09-13

**Release Type:** Minor — no user-facing changes.


## [61.1.0] - 2026-09-13

**Release Type:** Minor — no user-facing changes.


## [61.0.0] - 2026-09-13

**Release Type:** Major

### Changes

- Feat(git): one commit executor; hook output shown and cause named (§82)
- Feat(fleet): one closing block, exit 2 on partial, gate captured (§83)
- Feat(ship): pause the release so the driver can finish the docs, then verify (§78)
- Fix(changelog): stop asserting what a release did from the paths it touched (§78)
- Feat(fleet): coordination files are declared, not hard-coded (§77a)
- Fix(handoff,fleet): verification that can fail, and an allowlist that refuses directories and secrets (§78, §77a)
- Docs(tracker,migration): retire §77 and §83, file §87, and say what v61 changes on upgrade (§77, §83, §78, §82, §87)
- Fix(changelog): read the previous tag from HEAD, not HEAD~1 (§78)
- Chore(gitignore): ignore the lint containers' scratch file lists (§88)
- Test(wizard): drop the SIGPIPE race from the review-and-confirm assertions (§90)
- Fix(test,docs): make the executor's identity precondition its own, not the platform's (§82, §91)
- Test(container): raise the skip budget 6 -> 7 for §83's SIGINT-disposition skip


## [60.1.1] - 2026-09-09

**Release Type:** Patch

### Changes

- Fix(config,fleet): the reset shipped in v60.1.0 wiped the bypass reason on every publishing ship (§81, §77)
- Docs(gate): correct C-locale residue comment; file two leads (§77, §81)


## [60.1.0] - 2026-09-07

**Release Type:** Minor

### Changes

- Docs(tracker): correct §77(c)'s scope — the symptom needs a changed version_file, not every fleet root (§77)
- Fix(fleet): converge an existing root's allowlist when version_file changes, and refuse '.', '..' and '.git' (§77)
- Feat(config): make release.gate=none explain itself with a reason and its layer (§81)
- Fix(fleet,config): repair four defects the pre-ship review found in yesterday's two fixes (§77, §81)
- Fix(fleet): report the two new .gitignore outcomes in init fleet's summary (§77)


## [60.0.0] - 2026-09-07

**Release Type:** Major

### Changes

- Feat(fleet): add 'ship fleet manager' to commit and push the coordination root only (§77)
- Docs(tracker): record §77(b) decided as 'ship fleet manager' and (c) fixed; (a) stays open (§77)
- Feat(config): make repo-command trust durable with MANIFEST_CLI_TRUST_REPO_COMMANDS=remember|forget (§44)
- Fix(ship): disclose config-named programs in the ship repo and ship fleet previews; --explain points at the preview (§44)
- Docs(config): document remember/forget and the trust record (§44)
- Docs(tracker): §44(3) landed and the --explain lead reproduced; file §6(19) and the §79 nested-ship lead (§44)
- Docs(tracker): file §80 — a gate that hangs on docker stalls a fleet ship silently (§80)
- Fix(config): keep the whole command and its trust annotation in the execution disclosure (§44)


## [59.10.1] - 2026-09-05

**Release Type:** Patch

### Changes

- Fix(config): refuse execution-naming config keys from committed layers (§44)
- Docs(config): document that a committed config cannot name a program (§44)
- Update documentation and examples


## [59.10.0] - 2026-09-03

**Release Type:** Minor

### Changes

- Fix(fleet): drop the roster's REMOTE_URL column so a credential cannot be committed
- Fix(fleet): stop fleet init silently rewriting each member's own .gitignore
- Update documentation and examples
