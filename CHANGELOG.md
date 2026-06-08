# Changelog

## [52.5.2] - 2026-06-08

**Release Type:** Patch

### Changes

- Add regression coverage for the changed CLI workflow


## [52.5.1] - 2026-06-08

**Release Type:** Patch

### Changes

- Update release copy and configuration examples
- Update shell completions for new command options
- Add regression coverage for the changed CLI workflow
- Backfill and clarify release history in the root changelog


## [52.5.0] - 2026-06-08

**Release Type:** Minor

### Changes

- Docs(tracker): drop §8 top tier (shipped in 52.4.1) per drift policy; file GNU-sed guard quirk
- Add shared filesystem discovery helpers consumed by fleet detection
- Add passive version-surface detection and a committed handler catalog for known package/version files
- Add regression coverage for discovery, version-surface scans, and default no-sync package-lock behavior


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
