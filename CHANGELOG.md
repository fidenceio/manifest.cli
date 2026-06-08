# Changelog

## [52.5.0] - 2026-06-08

**Release Type:** Minor

### Changes

- Docs(tracker): drop §8 top tier (shipped in 52.4.1) per drift policy; file GNU-sed guard quirk
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [52.4.1] - 2026-06-07

**Release Type:** Patch

### Changes

- Fix(config): fail loud on malformed config + back up before migration
- Feat(consent)!: model C — -y authorizes an unambiguous non-interactive apply; complete `manifest first`
- Feat(ship): per-repo single-flight lock so concurrent applies can't race
- Feat(audit): record apply OUTCOME + gate disposition; lock audit/ship logs to 0600
- Fix(ship): create GitHub Release before Homebrew + retry the tarball SHA fetch
- Docs(tracker): file §8 enterprise-readiness audit — open items + this session's done work
- Fix(ship): portable sha256 (sha256sum fallback) so the formula fetch works on Linux


## [52.4.0] - 2026-06-05

**Release Type:** Minor — no user-facing changes.


## [52.3.1] - 2026-06-05

**Release Type:** Patch

### Changes

- Fix(version.sync): target the top-level "version" by JSON depth, not first match
- Feat(doctor,install): warn before ship when GNU sed is missing on macOS
- Docs(tracker): drop §7.7 and §7.9 — implemented


## [52.3.0] - 2026-06-05

**Release Type:** Minor — no user-facing changes.


## [52.2.0] - 2026-06-04

**Release Type:** Minor — no user-facing changes.


## [52.1.1] - 2026-06-04

**Release Type:** Patch

### Changes

- Fix(install): trust the formula at all brew chokepoints; refresh --depth help (§7.6/§7.8)
- Ci: bump actions/checkout v4 → v6 (Node 24) before the Node 20 removal (§5.13)
- Ci: bump GitHub Pages actions to current majors (Node 24)


## [52.1.0] - 2026-06-04

**Release Type:** Minor

### Changes

- Fix(config): normalize leading-dot path in set_yaml_value (silent no-op)
- Feat(install): narrowly trust the Homebrew formula before install/upgrade (§7.1)
- Feat(version): opt-in package.json version-sync on bump (§7.2)
- Fleet: unify --depth on one flag, one meaning, adaptive auto
- Fix(ci): mark the bind-mounted repo as a git safe.directory in the container
- Fix(ci): system-scope safe.directory + install jq in the test container
- Feat(first): land `manifest first` onboarding command; defer Postman (§7.4/§7.5)
- Docs(tracker): reconcile CLI tracker after the backlog scrub


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
