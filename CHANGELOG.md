# Changelog

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


## [59.9.1] - 2026-09-02

**Release Type:** Patch

### Changes

- Fix(cleanup): stop the empty-dir sweep reaching into linked worktrees
- Update documentation and examples


## [59.9.0] - 2026-09-01

**Release Type:** Minor

### Changes

- Update documentation and examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Update shell completions for new command options
- Add regression coverage for the changed CLI workflow


## [59.8.0] - 2026-09-01

**Release Type:** Minor

### Changes

- Fix(docs,test): make the release-state recipe runnable, and run it in the guard
- Test(tracker): guard tier-tag/section agreement, and move §73 to T2
- Fix(os): repair the OS layer's doppelganger, stdout leak and dead Bash-3.2 branches
- Fix(test): stop the release-state guard failing on a tagless CI checkout
- Refactor(os),docs(tracker): delete the dead OS shims, and cut four registers to one
- Update documentation and examples


## [59.7.0] - 2026-08-31

**Release Type:** Minor

### Changes

- Docs(tracker): record v59.6.2 as released, and stop the post-release loop here
- Docs(tracker),test: end the per-release docs commit, and guard it shut
- Docs(tracker): sequence the user-feedback line, and record v59.6.2's increment
- Fix(init): give .NET the renderer block it never had, and anchor bin/ instead of emitting it bare
- Docs(tracker): close §69(a) at v59.7.0 and state why the increment is minor


## [59.6.2] - 2026-08-28

**Release Type:** Patch

### Changes

- Docs(tracker): make the resume block describe v59.6.1, and retire §59 as shipped
- Docs(tracker): file §68 — main's branch protection binds nobody who ships
- Update documentation and examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [59.6.1] - 2026-08-27

**Release Type:** Patch

### Changes

- Docs(tracker): close two redaction leaks the v59.6.0 publish shipped, and why
- Test(tracker): guard §-citation resolution before the rebuild that breaks it
- Fix(security)!: unexport the consent gate rather than complete its closure
- Docs(tracker): retire the 15 items v59.6.0 shipped, file §65/§66/§67, anchor by symbol
