# Manifest Fleet Design Spec

**Status:** Active design reference
**Scope:** Polyrepo orchestration behavior in `manifest fleet`
**Updated:** v39.0.0

---

## Objectives

- Coordinate release, sync, and PR operations across multiple Git repositories.
- Preserve full single-repo compatibility (fleet is additive, not required).
- Keep fleet configuration explicit, auditable, and version-controlled.

---

## Current Implementation

### Implemented Subcommands

| Command | Description |
| ------- | ----------- |
| `fleet init` | Initialize fleet with auto-discovery (default) or `--bare` template |
| `fleet status` | Service overview with version, branch, and health indicators |
| `fleet discover` | Find new repos in workspace with configurable depth |
| `fleet sync` | Clone/pull all services (supports `--parallel`) |
| `fleet ship` | Coordinated release across all services |
| `fleet validate` | Validate fleet configuration and service paths |
| `fleet add` | Add a service to the fleet |
| `fleet pr` | Fleet-wide PR operations (create, status, checks, ready, queue) |
| `fleet help` | Fleet help |

### Scaffolded (Not Yet Implemented)

| Command | Planned Behavior |
| ------- | ---------------- |
| `fleet prep` | Fleet-wide local prep without publish |
| `fleet docs` | Unified fleet documentation generation |

---

## Fleet Config

**Primary file:** `manifest.fleet.yaml`

Design principles:

- Fleet-level metadata and per-service definitions
- Explicit repo paths and remote URLs
- Validation-first operations before any destructive step
- Minimal assumptions about branch naming or hosting topology

---

## Auto-Discovery (v39.0.0)

As of v39.0.0, `manifest fleet init` **discovers Git repositories by default**.

### Behavior

- Scans the workspace directory recursively for `.git` directories
- Filters out non-service directories (node_modules, vendor, build, dist, IDE dirs, archives)
- Outputs tab-separated metadata: name, path, type, branch, version, URL, submodule status
- Results populate `manifest.fleet.yaml` automatically

### Flags

| Flag | Description |
| ---- | ----------- |
| `--bare` | Skip auto-discovery; create a minimal fleet template |
| `--name <name>` | Set the fleet name |
| `--force` | Overwrite existing `manifest.fleet.yaml` |

### Smart `.gitignore` Handling

During fleet init, each discovered repo is checked for a `.gitignore`:

| Scenario | Action |
| -------- | ------ |
| No `.gitignore` | Created with best-practice defaults |
| Empty `.gitignore` (comments only) | Overwritten with defaults (deferred warning) |
| `.gitignore` with entries | Preserved; `.gitignore.manifest` created as reference |

Warnings for empty-overwrite scenarios are deferred to after the initialization summary.

---

## Operating Model

1. **Discover/validate** fleet state
2. **Sync** repositories (clone missing, pull existing)
3. **Execute** coordinated operations (`ship`, `pr`, etc.)
4. **Report** per-service outcomes clearly

---

## Future Work

- Implement fleet-wide `prep` and `docs` generation
- Add dependency and compatibility signaling between services
- Improve partial-failure recovery and resume semantics
- Support fleet-level changelogs with breaking change aggregation
