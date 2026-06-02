# Changelog

## [51.2.0] - 2026-06-02

**Release Type:** Minor

### Changes

- Add layered test-cost reduction (tier / select / parallelize / cache) — §5.10


## [51.1.0] - 2026-06-01

**Release Type:** Minor

### Changes

- Add smart ship preview summaries
- Update release copy and configuration examples
- Add regression coverage for the changed CLI workflow
- Add regression coverage for the changed CLI workflow
- Add GitHub Release publishing support
- Add GitHub Release publishing support
- Add regression coverage for the changed CLI workflow


## [51.0.0] - 2026-05-31

**Release Type:** Major

### Changes

- Add Apache-2.0 LICENSE, SECURITY.md, and CONTRIBUTING.md
- Add shellcheck + gitleaks CI lint workflow
- Add release gate: block publishing until verification passes
- Add shared apply-guard helpers, plan fingerprints, fleet Version column
- Add single-flight lock for fleet ship apply (tracker 1.7) [BLOCKER]
- Add pre-tag re-entrancy: resume an interrupted ship in place (tracker 5.5)
- Add token redaction across log output and the ship status file (tracker 2.7)
- Refresh SECURITY_ANALYSIS_REPORT to v50.2.0
- Add public-release migration note (tracker 4.3)
- Reconcile tracker after enterprise-hardening pass


## [50.2.0] - 2026-05-30

**Release Type:** Minor

### Changes

- Always generate docs site; make GitHub Pages enablement best-effort


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
