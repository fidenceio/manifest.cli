# Changelog

## [47.3.2] - 2026-05-06

**Release Type:** Patch

### Changes

- Add regression coverage for the changed CLI workflow
- Document the updated CLI workflow and release contract


## [47.3.1] - 2026-05-06

**Release Type:** Patch — no user-facing changes.


## [47.3.0] - 2026-05-06

**Release Type:** Minor

### Changes

- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow
- Document the updated CLI workflow and release contract


## [47.2.0] - 2026-05-06

**Release Type:** Minor

### Changes

- Add regression coverage for the changed CLI workflow


## [47.1.4] - 2026-05-06

**Release Type:** Patch

### Changes

- Backfilled and clarified release history in the root changelog


## [47.1.3] - 2026-05-06

**Release Type:** Patch

### Changes

- Release-only patch: refreshed version metadata, README version markers, docs index, tag, and Homebrew formula after `47.1.2`


## [47.1.2] - 2026-05-06

**Release Type:** Patch

### Changes

- Fixed changelog generation so substantive Manifest auto-commit release commits are summarized instead of filtered out as release noise
- Added category-based changelog bullets for recipe, command-surface, completion, test, container-runner, and documentation changes
- Added regression coverage proving auto-commit release changes no longer collapse to an empty changelog
- Backfilled the `47.1.0` changelog entry with the recipe-backed CLI changes it actually shipped


## [47.1.1] - 2026-05-06

**Release Type:** Patch

### Changes

- Release-only patch: refreshed version metadata, README version markers, docs index, tag, and Homebrew formula after `47.1.0`


## [47.1.0] - 2026-05-06

**Release Type:** Minor

### Changes

- Added recipe-backed workflow definitions and recipe introspection support
- Wired first-class CLI commands to inspectable built-in recipe definitions
- Added built-in recipe schema and initial recipes for ship, prep, refresh, docs, PR, and security workflows
- Added `manifest recipe list`, `show`, `explain`, and explicit `run` command support
- Added `manifest ship repo patch --explain` and related ship recipe explain paths
- Added a containerized Manifest CLI test runner so test dependencies stay out of the host environment
- Updated shell completions, command reference, README, and regression coverage for the recipe workflow


## [47.0.1] - 2026-05-06

**Release Type:** Patch

### Changes

- Release-only patch: refreshed version metadata, README version markers, docs index, tag, and Homebrew formula after `47.0.0`
