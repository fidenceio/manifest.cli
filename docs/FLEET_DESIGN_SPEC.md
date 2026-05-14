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
| `init fleet` | Initialize fleet with auto-discovery (default) or `--bare` template |
| `status` | Service overview with version, branch, and health indicators |
| `discover fleet` | Find new repos in workspace with configurable depth |
| `prep fleet` | Clone/pull all services (supports `--parallel`) |
| `ship fleet` | Coordinated release across all services |
| `validate fleet` | Validate fleet configuration and service paths |
| `add fleet` | Add a service to the fleet |
| `pr fleet` | Fleet-wide PR operations (create, status, checks, ready, queue) |
| `docs fleet` | Unified fleet documentation generation |

### Scaffolded (Not Yet Implemented)

| Command | Planned Behavior |
| ------- | ---------------- |
| `quickstart fleet` | Quick auto-discovery path for existing git repos |

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

As of v39.0.0, `manifest init fleet` **discovers Git repositories by default**.

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

## Repo Identity in Fleet Workspaces

Fleet users may work from editor workspaces that include several unrelated Git
repositories at once. A VS Code multi-root workspace is the clearest example:
the terminal's current directory, the editor's visible folder, and the fleet
root may all point at different repositories. Manifest must therefore make the
target repository explicit before any repo-scoped ship operation mutates files,
commits, tags, or pushes.

For `manifest ship repo <type>`, `repo` means the current enclosing Git
repository resolved from the shell working directory, not the currently visible
editor folder and not a selected fleet member by name. In a fleet context the
preflight output should show all three identities:

- current Git root: absolute path and origin slug for the repository that will
  be changed
- enclosing fleet root: absolute path and fleet name when the repo is inside a
  known fleet
- fleet member: configured service name when the Git root matches a fleet
  member path, or an explicit `(not a fleet member)` / `(fleet root)` marker

`manifest status repo` should expose the same identity block as a read-only
preview. If the current Git root is inside a fleet but does not match a
configured member, Manifest should warn before `ship repo` proceeds. If the
current Git root is the fleet root, Manifest should explicitly say that
`ship repo` targets the fleet-root repository only and is not equivalent to
`ship fleet`.

Current selector limitation: `manifest ship repo` has no `--repo`, `--path`, or
`--member` argument. Users must run it from inside the target checkout, for
example `cd services/example && manifest ship repo patch`, or use a shell
subcommand such as `(cd services/example && manifest ship repo patch)`.

Recommended follow-up:

- add a global `manifest -C <path> ...` option that changes the working
  directory before command dispatch and preserves the same identity preflight
- add a fleet-aware `manifest ship repo <type> --member <name>` selector after
  fleet membership resolution is stable enough to make names unambiguous
- reject conflicting selectors, such as `-C <path>` pointing at one repo while
  `--member <name>` resolves to another

### Repo-Local Fleet Hint

Each Git repository may carry a concise, human-readable fleet hint. The hint
should be understandable from the key names alone: which fleet this repository
belongs to, and what this repository is called inside that fleet.

Recommended project file:

```yaml
fleet:
  name: acme-platform
  member: api
```

Optional local-only pointer when the fleet root cannot be discovered by walking
up from the repository path, such as in a VS Code multi-root workspace:

```yaml
fleet:
  root: /work/acme-platform
```

The repo-local hint is a claim, not authority. Manifest must verify it
against the fleet configuration before a repo-scoped ship proceeds:

- `fleet.name` must match the fleet name or slug
- `fleet.member` must exist in the fleet configuration
- the configured member path and/or origin URL must match the current Git root
- `fleet.root`, when present, must contain the named fleet config

If validation fails, Manifest should stop with a mismatch report showing the
repo's claim, the fleet's configured value, and the current Git root. If no hint
exists, Manifest falls back to discovery and still prints the resolved identity.

---

## Future Work

- Implement fleet-wide `prep` and `docs` generation
- Add dependency and compatibility signaling between services
- Improve partial-failure recovery and resume semantics
- Support fleet-level changelogs with breaking change aggregation
- Add repo-identity preflight output for fleet-aware `status repo` and
  `ship repo`, including VS Code multi-root workspace ambiguity handling
- Add the repo-local `fleet` hint to repo initialization and validation,
  keeping project hints portable and local root pointers git-ignored
