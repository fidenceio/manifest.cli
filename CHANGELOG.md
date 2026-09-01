# Changelog

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


## [59.6.0] - 2026-08-26

**Release Type:** Minor

### Changes

- Fix(gitignore): apply the template's own secret- and temp-file rules to this repo
- Docs(tracker): rank by blast radius; tag all 42 items CANONICAL-ONLY/PRODUCT/BOTH
- Chore(claude): add the manifest-commit-steward agent
- Test(gitignore): guard the self-application fix, ordering included
- Docs(tracker): file Class B's six real findings; cut three; correct two entries
- Fix(git)!: pass git argv instead of re-splitting a string, and validate ref names
- Fix(config): take auto-confirm consent from the process env, never a config file
- Fix(yaml,security)!: refuse YAML lists that have no comma encoding, in yq's dialect
- Docs(tracker): record the 2026-08-25 verification pass, incl. a regression I shipped
- Fix(hooks): anchor the home-path check, apply exemptions per match, resolve hooksPath
- Docs(tracker): close §50/§55, file §56 and §57 from verifying an agent's claim
- Fix(help): document config show|setup|time, and guard help/dispatch parity
- Test(yaml): guard every yq program in modules/ against jq dialect drift
- Docs(tracker): close §53, close §52's config half, narrow §54
- Fix(security,yaml): one derivation for the private-file default, unforgeable sentinel
- Fix(fleet): restore delegated apply consent without reopening §46
- Docs(env): make the .env.example contract text say what the generator does
- Refactor(yaml,security): move four private globals into the _MANIFEST_CLI_ namespace
- Docs(tracker): close §49/§51/§54/§6(16), file §58/§59/§60, clear the fleet blocker
- Docs(tracker): make the release-state block a complete resume point
- Test(guards): un-stale four guards, close the selection gap that hid them, fix a 1s race
- Docs(tracker): re-evaluate every item; retire §19, file §63/§64; embargo unfixed detail


## [59.5.0] - 2026-08-24

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Add smart ship preview summaries
- Update documentation and examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [59.4.3] - 2026-08-24

**Release Type:** Patch

### Changes

- Docs(tracker): consolidate after v59.4.2 — delete shipped items, fold 17 adjudications
- Fix(cleanup)!: bound the ship-time temp sweep to what the caller asked for
- Fix(docs): write CHANGELOG.md through temp+rename, preserving its mode
- Fix(fleet): a refused fleet-root commit unstages only what the run staged
- Docs(tracker): file §9.30 and §6.5 from the Fidence plan; record §9.23 progress
- Update 1 file before release


## [59.4.2] - 2026-08-21

**Release Type:** Patch

### Changes

- Add GitHub Release publishing support
- Update documentation and examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [59.4.1] - 2026-08-21

**Release Type:** Patch

### Changes

- Fix(fleet): preview runs the workspace policy gate and withdraws -y when it would refuse
- Fix(tests): portable file hashing, and stop the grep|head SIGPIPE flakes
- Fix(fleet)!: preview announces the workspace policy gate instead of running it
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [59.4.0] - 2026-08-21

**Release Type:** Minor

### Changes

- Record the v59.3.0 release in §9.20 and add a cold-start resume point
- Rewrite the user-facing docs for readability, and fix three untruths found doing it
- Make the CLI's own help agree with the CLI, and document recovery
- Guard the command surfaces against each other (TRACKER §9.26)
- Update 1 file before release
