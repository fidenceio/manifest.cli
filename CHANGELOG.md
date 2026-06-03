# Changelog

## [52.0.0] - 2026-06-03

**Release Type:** Major

### Changes

- Docs(tracker): flatten to one list; prune shipped §5.10
- Refactor(fleet): remove inert validation knobs from fleet config
- Feat(fleet): gate PR-gated members in ship-fleet preview and apply
- Feat(pr): emit cli-pr apply-event audit record for -y-gated PR mutations
- Feat(preview): shared plan renderer, fingerprint drift warning, opt-in no-consent exit code
- Fix(cli): route deprecated cleanup alias through preview/-y gate
- Fix(docs): make archive cleanup move-only, no generated archive output
- Feat(completions): add fish-shell completions
- Test(ship): cover local-only apply offline boundary
- Test(cloud): pin apply-intent contract on the cloud stub
- Test(homebrew-tap): cover brew-managed tap refresh candidate
- Feat(orchestrator): capture per-run diagnostic ship logs (§5.6)
- Refactor(install): extract user global-config migration to scripts/migrate-user-config.sh
- Fix(cloud): conform cloud execution-mode var to MANIFEST_CLI namespace
- Feat(portability): force GNU userland on macOS so CI can go container-only (§5.11)


## [51.3.0] - 2026-06-02

**Release Type:** Minor

### Changes

- Fix(fleet): set -e-safe counters and portable mtime probe
- Fix(ship): run pre-bump gate before auto-commit and remote sync
- Fix(config): reject unknown keys in config set/unset; correct help examples
- Fix(formula): correct license to Apache-2.0
- Ci: run validation via the containerized runner
- Docs: correct gate, transaction, docs-site, config-name, and security inaccuracies
- Docs(tracker): file §5.11 GNU-userland standardization and §5.12 macOS CI verification
- Fix(fleet): ship plan shows actual current branch, not configured target


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
