# Changelog

## [56.3.0] - 2026-07-03

**Release Type:** Minor

### Changes

- Add GitHub Release publishing support
- Update release copy and configuration examples
- Wire first-class CLI commands to inspectable built-in recipe definitions
- Update shell completions for new command options
- Add regression coverage for the changed CLI workflow


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


## [55.3.0] - 2026-06-22

**Release Type:** Minor

### Changes

- Fix(status): source fleet roster from TSV; add bootstrap preview
- Fix(security): harden release-chain integrity (audit C3)
- Merge fix/release-chain-c3: harden release-chain integrity (audit C3)
- Merge fix/status-tsv-bootstrap: source fleet roster from TSV + bootstrap preview
- Fix(test): compare gate-exec cwd by inode, not string


## [55.2.1] - 2026-06-21

**Release Type:** Patch

### Changes

- Feat(fleet): 6-col TSV (drop TYPE) + graceful ^services: skip for TSV-based fleets
