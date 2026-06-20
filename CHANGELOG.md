# Changelog

## [55.2.0] - 2026-06-20

**Release Type:** Minor

### Changes

- Docs(fleet): add Fleet States And Vocabulary section
- Docs(fleet): per-branch adaptive depth + derived depth profile/health
- Feat(fleet): per-branch adaptive depth + observed-deepest header
- Feat(status): derived fleet depth profile + mixed-depth health flag


## [55.1.1] - 2026-06-20

**Release Type:** Patch

### Changes

- Fix(git): make release tag builder idempotent w.r.t. prefix; route ship/fleet tag construction through it + add test


## [55.1.0] - 2026-06-19

**Release Type:** Minor

### Changes

- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [55.0.4] - 2026-06-17

**Release Type:** Patch

### Changes

- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [55.0.3] - 2026-06-17

**Release Type:** Patch

### Changes

- Docs(tracker): reconcile §9.5 to SHIPPED (v55.0.0–v55.0.2)
- Update release copy and configuration examples


## [55.0.2] - 2026-06-16

**Release Type:** Patch

### Changes

- Fix init fleet -y clobbering a curated multi-depth TSV on re-run


## [55.0.1] - 2026-06-16

**Release Type:** Patch

### Changes

- Fleet: make `init fleet` re-run idempotent — preserve config, backfill members


## [55.0.0] - 2026-06-16

**Release Type:** Major

### Changes

- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [54.2.0] - 2026-06-16

**Release Type:** Minor

### Changes

- Update release copy and configuration examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Update shell completions for new command options
- Add regression coverage for the changed CLI workflow


## [54.1.1] - 2026-06-15

**Release Type:** Patch

### Changes

- Fix(ship): floor release-gate PATH + release ship lock on SIGHUP
