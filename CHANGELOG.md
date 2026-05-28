# Changelog

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


## [48.6.1] - 2026-05-26

**Release Type:** Patch

### Changes

- Fix(install-cli): keep shell completions out of Homebrew-managed dirs


## [48.6.0] - 2026-05-26

**Release Type:** Minor

### Changes

- Apply 2026-05-22 enterprise-readiness triage to CLI tracker
- Close CLI tracker §1.5: pre-flight .git writability before fleet ship
- Close CLI tracker §1.2: structured fleet partial-failure recovery output
- Close CLI tracker §1.6: fleet-level resume entrypoint
- Close CLI tracker §2.5: broad preview no-write coverage matrix
- Add destructive-target sandbox tripwire to uninstall code paths
- Extend sandbox tripwire tests to every destructive site
- Add --manual flag to install-cli.sh for installing local source
- Re-exec install-cli.sh under Bash 5+ when invoked via /bin/bash 3.2
- Differentiate manual-fallback status when --manual was explicitly requested
- Fix post-install manifest --help and --version
- Dedupe install_dirs so uninstall does not list ~/.manifest-cli twice
- Fix install-cli silent exit when first profile is cleaned
- Feat(install-paths): canonical cleanup_profile_entries and runtime path helpers
- Refactor(install,uninstall): delegate cleanup_environment_variables to install-paths
- Feat(install-cli): atomic versioned-dir upgrades with current symlink
- Feat(install-cli): migrate legacy flat layout on first upgrade
- Test(install-cli): fault-injection regression suite for atomic upgrade
- Drop §5.7 from CLI tracker (atomic install-cli.sh upgrades shipped)
