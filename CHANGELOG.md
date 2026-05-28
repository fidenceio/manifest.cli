# Changelog

## [50.1.3] - 2026-05-28

**Release Type:** Patch

### Changes

- Add Manifest-generated Jekyll docs site and Pages workflow


## [50.1.2] - 2026-05-28

**Release Type:** Patch — no user-facing changes.


## [50.1.1] - 2026-05-28

**Release Type:** Patch

### Changes

- Triage CLI tracker after the 2026-05-28 ship cycle


## [50.1.0] - 2026-05-28

**Release Type:** Minor

### Changes

- Rewrite CLI documentation
- Restore README runtime contract
- Fix atomic-upgrade symlink swap on Linux


This changelog is the product release history for Manifest CLI. Workspace
coordination changes live in the parent workspace changelog; Homebrew formula
distribution history lives in `fidenceio.homebrew.tap/CHANGELOG.md`.

## [50.0.1] - 2026-05-28

**Release Type:** Patch

### Changes

- Stop a ship that would land on the wrong branch
- Stop prescribing a branching workflow to users


## [50.0.0] - 2026-05-27

**Release Type:** Major

### Changes

- Notice brand-new untracked files before auto-commit sweeps them in
- Fix install/upgrade channel divergence with one provenance predicate
- Make --manual remove an existing Homebrew install (symmetric channel switch)
- Merge branch 'fix-install-channel-provenance'
- Harden destructive-op guards so a sandbox can never touch real installs
- Merge branch 'notice-new-untracked-on-autocommit'
- Uninstall: sweep shell completions across versions and both channels


## [49.0.2] - 2026-05-27

**Release Type:** Patch

### Changes

- Drop 3 dead links from docs INDEX.md Architecture table
- Remove inert branch-enforcement knobs from fleet config (B)


## [49.0.1] - 2026-05-26

**Release Type:** Patch — no user-facing changes.


## [49.0.0] - 2026-05-26

**Release Type:** Major

### Changes

- Remove 45 dead functions across 11 modules
- Draft safe-by-default migration note in user guide (§4.3)


## [48.6.2] - 2026-05-26

**Release Type:** Patch — no user-facing changes.
