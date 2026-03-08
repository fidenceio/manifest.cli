# Manifest North Star (CLI)

Status: Active
Repository role: Workflow and release orchestration

## Mission

Provide a reliable, explicit, and automatable release control plane for Git repos.

## Strategic Direction

- Keep release mechanics deterministic (`prep` vs `ship` split).
- Preserve strong local/offline behavior with optional cloud augmentation.
- Make PR and fleet workflows first-class without breaking single-repo usage.

## Current Product Truth

- `manifest prep <type>`: local release preparation.
- `manifest ship <type>`: publish path.
- `manifest pr ...`: explicit PR lifecycle operations.
- `manifest fleet ...`: multi-repo coordination with some scaffolded commands.

## 12-Month Priorities

1. Reliability hardening for prep/ship and rollback safety.
2. Documentation quality and consistency of generated artifacts.
3. Fleet maturity (`fleet prep`/`fleet docs`) and dependency-aware operations.

## Cross-Repo Contract

- CLI is the operator-facing entry point.
- Cloud enriches decisions but should not be a hard runtime requirement.
- Tap distributes updates quickly enough to keep CLI and docs current.
