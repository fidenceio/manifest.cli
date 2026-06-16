# Changelog

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


## [54.1.0] - 2026-06-15

**Release Type:** Minor

### Changes

- Feat(ship): add --force-bump for repo + fleet; symmetric no-changes gate
- Docs(tracker): fold §8.1h tap-sync resolution into a §8.1e disambiguation


## [54.0.1] - 2026-06-15

**Release Type:** Patch

### Changes

- Fix(ship): reconcile tap checkout after the bottle-wait upgrade
- Fix(upgrade): fast-forward the workspace tap checkout in the auto-upgrade worker


## [54.0.0] - 2026-06-15

**Release Type:** Major

### Changes

- Docs(tracker): §9.1 status — shipped in v53.4.0
- Docs(tracker): file §9.2 — rate limiting for fleet gh loops (user directive: 150)
- Docs(tracker): file §9.3 — GitHub owner/org targeting for repo creation
- Docs(tracker): §9.3 — mixed-owner fleets (pre-existing-remote escape hatch + TSV OWNER column cost)
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [53.4.0] - 2026-06-12

**Release Type:** Minor

### Changes

- Fix(ship): wait for the tap bottle so a canonical ship lands locally
- Feat(fleet): §9.1 — topics command, quiet post-ship pass, host-local key
- Fix(completions): drop ship flags the parsers reject


## [53.3.0] - 2026-06-12

**Release Type:** Minor

### Changes

- Docs(tracker): file §9.1 — GitHub topics projection from repo-name slugs
- Feat(fleet): project repo-name slugs onto GitHub topics (§9.1)
- Docs(tracker): §9.1 Phase 2 — roster from the full org list, not the topic-filtered query
- Feat(fleet): §9.1 Phase 2 — read-only roster of unenrolled family repos
