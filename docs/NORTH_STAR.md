# Manifest North Star (CLI)

**Status:** Active
**Repository role:** Workflow and release orchestration
**Updated:** v39.0.0

---

## Mission

Provide a reliable, explicit, and automatable release control plane for Git repositories.

---

## Strategic Direction

- **Deterministic release mechanics** — the `prep` vs `ship` split keeps local work
  separate from publishing. Every version bump requires an explicit release type.
- **Strong local/offline behavior** — cloud features enrich decisions but are never
  a hard runtime requirement.
- **PR and fleet as first-class workflows** — without breaking single-repo simplicity.
- **Security by default** — pre-commit hooks, `.gitignore` enforcement, and smart
  scaffolding protect repositories automatically.

---

## Current Product Truth

- `manifest prep <type>` — local release preparation
- `manifest ship <type>` — full publish path
- `manifest pr ...` — explicit PR lifecycle operations
- `manifest fleet ...` — multi-repo coordination with auto-discovery (v39.0.0)
- Smart `.gitignore` scaffolding across single-repo and fleet workflows (v39.0.0)

---

## 12-Month Priorities

1. **Reliability hardening** for prep/ship and rollback safety
2. **Documentation quality** and consistency of generated artifacts
3. **Fleet maturity** — implement `fleet prep`, `fleet docs`, and dependency-aware operations

---

## Cross-Repo Contract

- **CLI** is the operator-facing entry point
- **Cloud** enriches decisions but is not a hard runtime requirement
- **Tap** distributes updates quickly enough to keep CLI and docs current
