# Changelog

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


## [59.3.0] - 2026-08-20

**Release Type:** Minor

### Changes

- File the input-shape sweep that the shipped entries took with them
- Record that the audit is 9/13 phases unrun where a clone can see it
- File the 13-phase audit results: 3 P0, 34 P1, 35 P2
- Run the suite under the shipped shell options (pipefail was missing)
- Stop repository config from reaching shell execution (SEC-017)
- Withdraw two of the audit's three P0s; they did not survive reproduction
- Declare status/doctor read-only at the entry point (ATOM-003)
- Record the fix-campaign state in §9.20 so it can be resumed cold
- Correct the suite count: 1508, not 1507
- Reconcile the P1 count with the register: 32 remaining, not 33
- Add GitHub Release publishing support
- Update release copy and configuration examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [59.2.1] - 2026-08-17

**Release Type:** Patch

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [59.2.0] - 2026-08-16

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Add smart ship preview summaries
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [59.1.1] - 2026-08-16

**Release Type:** Patch

### Changes

- Update release copy and configuration examples


## [59.1.0] - 2026-08-16

**Release Type:** Minor

### Changes

- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [59.0.1] - 2026-08-12

**Release Type:** Patch

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
