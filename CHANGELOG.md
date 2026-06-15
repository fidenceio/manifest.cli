# Changelog

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


## [53.2.0] - 2026-06-09

**Release Type:** Minor

### Changes

- Feat: core auto-upgrade on invocation (brew-managed, bottle-only, detached)
- Test(runner): add opt-in --progress milestone indicator


## [53.1.0] - 2026-06-09

**Release Type:** Minor

### Changes

- Formula: make the bash-wrapper candidate list fully static (:all-bottle ready)


## [53.0.5] - 2026-06-09

**Release Type:** Patch

### Changes

- Formula: make the bash-wrapper candidate list fully static (:all-bottle ready)


## [53.0.4] - 2026-06-09

**Release Type:** Patch

### Changes

- Ship: classify Homebrew host-toolchain gate as an environmental skip


## [53.0.3] - 2026-06-09

**Release Type:** Patch

### Changes

- Docs(tracker): §8.13 — brew-managed provenance check should use filesystem, not brew list exit status
- Fix(install): base brew-managed provenance on the Cellar, not `brew list` (§8.13)


## [53.0.2] - 2026-06-09

**Release Type:** Patch

### Changes

- Fix(install): fall back to tap-level brew trust on custom-remote taps (§7.6)
