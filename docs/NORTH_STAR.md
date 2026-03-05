# Manifest North Star (CLI Anchor)

**Status:** Active
**Last Updated:** 2026-03-05
**Repository Role:** Workflow and release orchestration layer

## North Star Companion Documents

- `manifest.cli`: `docs/NORTH_STAR.md` (this document)
- `manifest.cloud`: `docs/NORTH_STAR.md`
- `homebrew.tap`: `NORTH_STAR.md`

## Ecosystem Context

Manifest operates as one coordinated system across three repositories:

- `manifest.cli` provides command-line release workflows
- `manifest.cloud` provides AI analysis and recommendation services
- `homebrew.tap` provides installation and upgrade delivery

This document is the anchor strategy for the full system.

## Mission

Make software release operations simple, trusted, and portable through one-command workflows, intelligent automation, and strong release traceability.

## Strategic Goals

### Goal 1: Developer Experience First

Continuously improve solo and team workflows using simple commands, especially `manifest go [patch|minor|major|revision]`.

Key outcomes:

- one command handles sync, version bump, docs, archive, commit, tag, push, and optional PR creation
- lower manual overhead and fewer release mistakes
- consistent behavior from local development to CI

### Goal 2: Near-Term Product Value

Deliver immediate user value through release intelligence and documentation quality:

- smart, overrideable version recommendations
- AI-assisted changelog and release-note improvements
- consistent archiving of previous version documentation

### Goal 3: Long-Term Thin-Client Ecosystem

Enable a thin-client ecosystem where applications self-update across internet-connected edge devices:

- machine-actionable version and change metadata
- coordinated updates across fleets and dependent services
- secure, observable, rollback-capable release channels

## Repo Responsibilities (CLI)

`manifest.cli` is responsible for:

- reliable orchestration of release workflows
- deterministic local behavior with safe cloud fallback
- fleet-aware command behavior as team scale increases
- preserving auditability in version, docs, and git history

## 12-Month Priority Plan

### P1: Workflow Reliability

- harden `manifest go` safety and failure recovery paths
- standardize PR automation defaults and behavior
- improve diagnostics and dry-run confidence

### P2: Intelligence and Documentation

- improve recommendation accuracy and explainability
- tighten docs generation quality and consistency checks
- enforce archive lifecycle and naming conventions

### P3: Fleet and Edge Readiness

- complete `manifest fleet go` and unified fleet docs workflows
- add dependency-aware compatibility and impact reporting
- define update contracts for thin-client rollout patterns

## Cross-Repo Contracts

- **CLI <-> Cloud:** cloud augments decisions; CLI remains operational when cloud is unavailable
- **CLI <-> Tap:** tap should publish updates quickly so workflow improvements reach users rapidly
- **Cloud <-> Tap:** release intelligence and package delivery timelines should remain aligned

## Success Metrics

- time from code-complete to pull-request-opened
- percentage of releases completed through `manifest go*`
- documentation freshness and post-release consistency
- recovery time after failed release workflows
- number of coordinated updates executed across fleets/services/devices

## Review Cadence

Review strategy monthly or at each major release.
Update companion documents when scope, interfaces, or priorities change.
