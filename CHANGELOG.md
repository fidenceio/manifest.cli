# Changelog

## [47.13.0] - 2026-05-16

**Release Type:** Minor

### Changes

- Archive legacy trackers ahead of consolidation
- Add consolidated CLI tracker
- Fix CLI tracker README anchor and heading level
- Docs(tracker): add §3.7 manifest select repo
- Honor MANIFEST_CLI_AUTO_CONFIRM in repo-scope confirmation


## [47.12.5] - 2026-05-14

**Release Type:** Patch

### Changes

- Normalize Manifest environment namespace


## [47.12.4] - 2026-05-14

**Release Type:** Patch

### Changes

- Ignore unrelated manifest executables on uninstall


## [47.12.3] - 2026-05-14

**Release Type:** Patch

### Changes

- Clarify Homebrew uninstall caveats


## [47.12.2] - 2026-05-14

**Release Type:** Patch

### Changes

- Harden uninstall and reinstall execution policy


## [47.12.1] - 2026-05-14

**Release Type:** Patch — no user-facing changes.


## [47.12.0] - 2026-05-14

**Release Type:** Minor

### Changes

- Update release copy and configuration examples
- Update shell completions for new command options
- Add regression coverage for the changed CLI workflow


## [47.11.2] - 2026-05-14

**Release Type:** Patch

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow
- Backfill and clarify release history in the root changelog


## [47.11.1] - 2026-05-14

**Release Type:** Patch — no user-facing changes.


## [47.11.0] - 2026-05-14

**Release Type:** Minor

### Changes

- Promote remaining user-facing `MANIFEST_CLI_*` settings to first-class YAML keys
- Preserve process environment overrides above YAML layers for CI and backward compatibility
- Add Cloud secret-reference hydration and security private-file YAML coverage
