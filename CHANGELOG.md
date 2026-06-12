# Changelog

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


## [53.0.1] - 2026-06-08

**Release Type:** Patch

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [53.0.0] - 2026-06-08

**Release Type:** Major

### Changes

- Add GitHub Release publishing support
- Add smart ship preview summaries
- Update release copy and configuration examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [52.7.1] - 2026-06-08

**Release Type:** Patch

### Changes

- Add regression coverage for the changed CLI workflow
