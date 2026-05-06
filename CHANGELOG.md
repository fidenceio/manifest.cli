# Changelog

## [46.13.8] - 2026-05-06

**Release Type:** Patch

### Summary
No notable user-facing changes were detected since the previous release tag. Only release automation or filtered bookkeeping commits were present.

## [46.13.7] - 2026-05-06

**Release Type:** Patch

### Summary
- Notable changes: 1
- New features: 0
- Improvements: 0
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 1

### Documentation
- Auto-regenerate root CHANGELOG.md on every ship

## [46.13.6] - 2026-05-06

**Release Type:** Patch

### Summary
No notable user-facing changes were detected since the previous release tag. Only release automation or filtered bookkeeping commits were present.

## [46.13.5] - 2026-05-06

**Release Type:** Patch

### Summary
- Notable changes: 2
- New features: 0
- Improvements: 0
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 2

### Documentation
- Recast docs.retain to govern archive retention, not active-docs filtering
- Refactor docs.archive retention to a single docs.retain spec

## [46.13.4] - 2026-05-05

**Release Type:** Patch

### Summary
No notable user-facing changes were detected since the previous release tag. Only release automation or filtered bookkeeping commits were present.

## [46.13.3] - 2026-05-05

**Release Type:** Patch

### Summary
- Notable changes: 2
- New features: 0
- Improvements: 1
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 1

### Improvements
- Configurable archive retention (tracker #38)

### Documentation
- Decline tracker #41 (manifest docs archive subcommands)

## [46.13.2] - 2026-05-05

**Release Type:** Patch

### Summary
No notable user-facing changes were detected since the previous release tag. Only release automation or filtered bookkeeping commits were present.

## [46.13.1] - 2026-05-05

**Release Type:** Patch

### Summary
- Notable changes: 1
- New features: 0
- Improvements: 1
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 0

### Improvements
- Archive move log (tracker #40)

## [46.13.0] - 2026-05-05

**Release Type:** Minor

### Summary
- Notable changes: 2
- New features: 0
- Improvements: 1
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 1

### Improvements
- Pre-move safety check on archive sweep (tracker #39)

### Documentation
- Prune doc-review-only and missed-timing archive stubs (tracker #42)

## [46.12.2] - 2026-05-05

**Release Type:** Patch

### Summary
- Notable changes: 1
- New features: 0
- Improvements: 0
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 1

### Documentation
- Backfill v46 entries in root CHANGELOG (tracker #37)

## [46.12.0] - 2026-05-05

**Release Type:** Minor

### Summary
- Notable changes: 7
- New features: 0
- Improvements: 2
- Bug fixes: 0
- Breaking changes: 0
- Documentation updates: 5

### Improvements
- Regroup zArchive into v<major>/ subfolders with auto-generated indexes
- Fold GIT_HOOKS into USER_GUIDE; lift CONFIG_SURFACE_AUDIT backlog to IMPROVEMENT_TRACKER

### Documentation
- Add tracker items #36–#41 for deferred Phase 2 doc-system work
- Boilerplate-free release notes; strict archive policy with auto-regenerated indexes
- Delete 438 boilerplate-stub release notes/changelogs from zArchive
- Stop committing doc-review reports by default; default report_dir to git state dir
- Delete six consolidated audit/handoff docs; clean cross-references; drop v42 wording
