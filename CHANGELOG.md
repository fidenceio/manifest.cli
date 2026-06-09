# Changelog

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


## [52.7.0] - 2026-06-08

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add a containerized test runner for Manifest CLI
- Add regression coverage for the changed CLI workflow


## [52.6.0] - 2026-06-08

**Release Type:** Minor

### Changes

- Add regression coverage for the changed CLI workflow


## [52.5.2] - 2026-06-08

**Release Type:** Patch

### Changes

- Add regression coverage for the changed CLI workflow


## [52.5.1] - 2026-06-08

**Release Type:** Patch

### Changes

- Update release copy and configuration examples
- Update shell completions for new command options
- Add regression coverage for the changed CLI workflow
- Backfill and clarify release history in the root changelog


## [52.5.0] - 2026-06-08

**Release Type:** Minor

### Changes

- Docs(tracker): drop §8 top tier (shipped in 52.4.1) per drift policy; file GNU-sed guard quirk
- Add shared filesystem discovery helpers consumed by fleet detection
- Add passive version-surface detection and a committed handler catalog for known package/version files
- Add regression coverage for discovery, version-surface scans, and default no-sync package-lock behavior
