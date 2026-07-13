# Changelog

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


## [56.3.0] - 2026-07-03

**Release Type:** Minor

### Changes

- Add `manifest env generate|validate` (ENV-001): spec `env:`-driven `.env.example`, k8s configmap/external-secret env bridges, Dockerfile public-vars bridge block, `--check` drift gate
- Scaffold `.env.example` at `manifest init`/`manifest prep` (no-clobber; seeds a starter spec `env:` block when absent)
- Add env naming-law audit to `manifest security`: `FIDENCE_*` law with framework-name allowlist (mirrors `env_framework_names.json`; `MANIFEST_CLI_*` permanently exempt); `env.naming_enforcement` warn (default) / strict, extra entries via `env.naming_allow`
- Update shell completions and command reference for `manifest env`
- Test hermeticity: the bats helper strips ambient `MANIFEST_CLI_AUTO_CONFIRM`, so declined-consent tests hold even under non-interactive ship runs


## [56.2.0] - 2026-07-02

**Release Type:** Minor

### Changes

- Feat(init): scaffold the release-gate run-tests.sh at repo/fleet init
- Update 1 file before release


## [56.1.0] - 2026-07-01

**Release Type:** Minor

### Changes

- Feat(fleet): root-only fleet release + honest preview count
- Update 1 file before release


## [56.0.0] - 2026-06-25

**Release Type:** Major

### Changes

- Feat(release+status): gate staleness re-test window (#7 Part 2) + vocab-aware fleet status


## [55.5.0] - 2026-06-24

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Add smart ship preview summaries
- Update release copy and configuration examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Add regression coverage for the changed CLI workflow


## [55.4.2] - 2026-06-23

**Release Type:** Patch

### Changes

- Fix(release-gate): force-bump skips the gate for clean, at-tag version stamps


## [55.4.1] - 2026-06-22

**Release Type:** Patch

### Changes

- Add regression coverage for the changed CLI workflow


## [55.4.0] - 2026-06-22

**Release Type:** Minor

### Changes

- Add regression coverage for the changed CLI workflow
