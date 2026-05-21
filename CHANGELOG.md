# Changelog

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


## [48.4.0] - 2026-05-20

**Release Type:** Minor — no user-facing changes.


## [48.3.2] - 2026-05-20

**Release Type:** Patch

### Changes

- Stub brew in homebrew_tap_refresh.bats setup
- Recreate CLI tracker — drop closed/stale items, renumber sections
- Add §5.5 — e2e coverage for brew-managed tap dir


## [48.3.1] - 2026-05-20

**Release Type:** Patch — no user-facing changes.


## [48.3.0] - 2026-05-20

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Add regression coverage for the changed CLI workflow


## [48.2.2] - 2026-05-19

**Release Type:** Patch — no user-facing changes.


## [48.2.1] - 2026-05-19

**Release Type:** Patch

### Changes

- Add smart ship preview summaries
- Add regression coverage for the changed CLI workflow


## [48.2.0] - 2026-05-19

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow


## [48.1.1] - 2026-05-19

**Release Type:** Patch — no user-facing changes.
