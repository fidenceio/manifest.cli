# Changelog

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


## [48.5.3] - 2026-05-22

**Release Type:** Patch

### Changes

- Add CLI tracker §1.6 fleet resume + §5.5–§5.7 ship reliability


## [48.5.2] - 2026-05-22

**Release Type:** Patch

### Changes

- Route raw mktemp through scratch helper; drop inert managed-temp API (Step 7c)


## [48.5.1] - 2026-05-21

**Release Type:** Patch

### Changes

- Add opportunistic runtime cache cleanup (Step 7b substrate)
- Close CLI tracker §5.4 (runtime cleanup); renumber §5.5 → §5.4
- Rename runtime-cleanup load sentinel to MANIFEST_CLI_* namespace
- Add Dirty column to fleet ship plan preview (tracker §1.1)
- Close CLI tracker §1.1 (dirty trees in fleet ship); renumber §1.2–§1.6 → §1.1–§1.5


## [48.5.0] - 2026-05-21

**Release Type:** Minor

### Changes

- Fix MANIFEST_DEBUG → MANIFEST_CLI_DEBUG in tracker §5.3
- Label broad MANIFEST_* regexes as legacy-cleanup exceptions
- Discover plugin-owned data dirs via sibling .data-dirs manifests
- Skip comment lines in namespace audit; reword legacy-cleanup notes
- Fix path-join doubling $HOME/~/.manifest-cli in temp-list
- Drop install: block from example config — defaults are correct
- Expand leading ~/ and $HOME/ in YAML values on load
- Extend namespace audit with four gap-coverage tests
- Add §1.7 fleet-ship sandbox .git write denial pre-flight
- Add §5.5 runtime cleanup subcommand; renumber tap test to §5.6
- Fleet plan Service column shows path basename, not YAML key
- Quiet OS-detection preamble by default; gate behind verbose/debug
