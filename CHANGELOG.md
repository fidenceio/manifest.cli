# Changelog

## [57.0.1] - 2026-08-01

**Release Type:** Patch

### Changes

- Add regression coverage for the changed CLI workflow


## [57.0.0] - 2026-08-01

**Release Type:** Major

### Changes

- Add GitHub Release publishing support
- Add regression coverage for the changed CLI workflow


## [56.8.1] - 2026-07-20

**Release Type:** Patch

### Changes

- Add GitHub Release publishing support
- Add regression coverage for the changed CLI workflow


## [56.8.0] - 2026-07-20

**Release Type:** Minor

### Changes

- Add regression coverage for the changed CLI workflow


## [56.7.0] - 2026-07-17

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [56.6.0] - 2026-07-17

**Release Type:** Minor

### Changes

- Fix(tests): revert mk_scratch canonicalization; assert canonical paths with -ef
- Feat(consent): -y applies without a confirmation prompt; close release-gate stdin
- Test: dedup suite (-5), hermetic release gate, ship-path coverage (+10)
- Feat(config): nested repos inherit fleet-root config (github.owner et al.)
- Test: fill coverage backlog — apply paths, installer branches, helpers (+113); kcov target
- Add regression coverage for the changed CLI workflow


## [56.5.0] - 2026-07-16

**Release Type:** Minor

### Changes

- Canonicalize the test scratch dir so macOS path assertions hold
- Update 1 file before release


## [56.4.2] - 2026-07-16

**Release Type:** Patch

### Changes

- Fix fleet update diff to read the TSV roster, not the YAML services map
- Update 1 file before release


## [56.4.1] - 2026-07-13

**Release Type:** Patch

### Changes

- Fix fleet init Git ownership and GitHub targets
- Update 1 file before release


## [56.4.0] - 2026-07-09

**Release Type:** Minor

### Changes

- Docs(changelog): correct 56.3.0 entry — release adds 'manifest env' + env scaffolding + naming audit, not the auto-generated copy
- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow
