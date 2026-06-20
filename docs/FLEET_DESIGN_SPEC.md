# Manifest Fleet Design Spec

Manifest Fleet coordinates independent Git repositories from one workspace. It does not require submodules and does not collapse child repos into the parent Git history.

## Goals

- Make repo and fleet release workflows use the same command model.
- Keep fleet membership explicit and reviewable.
- Support release-enabled and release-disabled services in the same workspace.
- Preview every mutation before apply.
- Keep parent workspace metadata separate from child repo implementation.

## Core Files

| File | Purpose |
| ---- | ------- |
| `manifest.fleet.tsv` | Human-reviewable scan output and selection table |
| `manifest.fleet.config.yaml` | Canonical fleet config used by commands |
| `manifest.fleet.plan.yaml` | Adoption/reconciliation plan written by `manifest plan fleet --apply` |

## Fleet States And Vocabulary

The fleet model has exactly one universe and one selected subset; everything else is a label derived from observation, never a stored state.

### Corpus, Members, Benched

```text
CORPUS  = git repositories discovered <= depth ceiling   (observed — the universe)
MEMBER  = a corpus repo explicitly selected              (declared — the fleet)
BENCHED = every other corpus repo, by default            (persisted — records triage)
```

Membership is a single binary — `member` or `benched`, default `benched`. Nothing auto-enrolls. Benched is **persisted** (the `SELECT` column), not recomputed, so a rescan does not re-triage the whole corpus on every run.

### Depth

Discovery is bounded by a global depth **ceiling** (`MANIFEST_CLI_FLEET_MAX_DISCOVERY_DEPTH = 10`) — a deliberately high guardrail, not a target. The ceiling stays high; it is never lowered to fit a particular fleet.

`--depth auto` is **per-branch adaptive**: each branch of the tree is walked down to *its own* first git repo — discovery prunes at a repo (nested repos are excluded by default) — or to the ceiling if that branch holds none. Because every branch resolves independently, a **mixed-depth** workspace is captured completely in one pass with no global under- or over-scan: shallow direct-child repos and deeper bucketed repos are both found, and a deep branch never drags a shallow one to its level (or vice-versa). An explicit `--depth N` still forces a fixed scan depth when wanted.

The TSV's `# Depth:` header records the **observed deepest** repo depth — a derived diagnostic, not the ceiling. Per-branch resolution removes the older hazard where re-running `auto` could shrink a TSV that had been scanned deeper.

**Depth profile + health (derived, not stored).** Per-subfolder depth facts — for each top-level bucket, the shallowest and deepest depth at which a repo appears — are **derived from the row `PATH`s on demand**, never persisted: the rows already encode them (see [Storage](#storage-store-declared-cache-the-corpus-derive-labels)). `status` reports this profile and flags any **mixed-depth bucket** — one where a bucket's shallowest and deepest repo depth differ — as a health signal, since that usually means an accidental nested repo or a broken layout convention. A clean fleet keeps every bucket internally uniform.

### Three Orthogonal Axes

| Axis | Values | Kind | TSV column |
| ---- | ------ | ---- | ---------- |
| Membership | `member` ↔ `benched` (default) | declared | `SELECT` |
| Local | `absent` → `present` → `repo` (has `.git`) | observed (cheap) | `HAS_GIT` |
| Remote | `undeclared` → `declared` → `verified` | declared URL, then observed | `REMOTE_URL` |

`Remote` is a **secure tri-state**: a recorded URL is a *claim* (`declared`), not proof (`verified`). Outward actions gate on `verified` — see [Verification Is Cost-Bounded](#verification-is-cost-bounded).

### Named States (Derived, Never Stored)

Members, by Local × Remote:

| State | Local | Remote | Safe operation |
| ----- | ----- | ------ | -------------- |
| Backed | repo | verified | ship |
| Unverified | repo | declared | verify first |
| Stranded | repo | undeclared | create remote (idempotent), then ship |
| Uncloned | absent | verified | clone to restore |
| Lost | absent | undeclared | unrecoverable — flag loudly |

Benched repos are either **Candidate** (Local = repo; promotable to member) or **Scenery** (Local = non-repo: a grouping folder or a deliberate placeholder such as `_holding`).

`missing` is not a primitive — it is `member` + Local `absent`. `unlisted` is an on-disk repo not yet in the TSV (benched-by-omission until a rescan records it).

### Identity Is Path

The operational identity of a fleet repo is its **workspace-relative path**, which is also the key the adoption/reconcile merge dedups on. The remote slug (the `REMOTE_URL` basename) is recorded only to flag two anomalies — *rehomed* (a path's remote changed) and *collision* (two paths claim one remote) — and is **not** identity. A remoteless/stranded repo is therefore still a first-class member. A move or rename reads as remove + add; a rescan reconciles it. See also [Repo Identity](#repo-identity) for command-target resolution.

### Storage: Store Declared, Cache The Corpus, Derive Labels

| In the TSV | Kind | Authority |
| ---------- | ---- | --------- |
| `SELECT` (membership) | **declared** | truth — never auto-changed |
| corpus rows + `HAS_GIT` + `# Last scanned:` | **cached observation** | baseline, reconciled on rescan |
| `REMOTE_URL` | **declared** (a claim) | the remote declaration |
| remote-verified | **never persisted** | observed live, TTL-cached in `~/.manifest-cli/cache/` only |
| any derived label | **never stored** | recomputed `f(declared ⋈ observed)` |

The TSV is a freshness-stamped **hybrid** (declared membership + cached corpus). Drift is bounded to "what changed since `# Last scanned:`". `HAS_GIT`/`BRANCH` are deliberately cached observations, refreshed on rescan — not leaks of live state.

### Verification Is Cost-Bounded

Outward actions — push, GitHub Release, create-remote — gate on `verified`, never `declared`. The guarantee is kept cheap so it scales to a large fleet without exhausting GitHub rate limits:

- **Scoped, not fleet-wide.** A fleet operation verifies only the members it is about to act on (the release/push set — usually a handful), never the whole corpus. A full-corpus sweep is its own explicit, opt-in command.
- **Implicit in the action.** `git push` is atomic and locally safe: a push to a missing or unreachable remote fails with no side effects and downgrades the cached state, so the steady-state path does not probe-then-push. A mandatory *pre-flight* `verified` gate is reserved for the one **irreversible** action — `create-remote` (`gh repo create`), where acting on a wrong assumption is destructive.
- **Git-protocol probe.** Existence/reachability uses `git ls-remote` (already used internally), which does **not** consume the REST/GraphQL rate-limit quota. `gh` is the fallback only when richer metadata is needed; batched sweeps alias ~100 repos per GraphQL query.
- **TTL-cached.** `verify` is a pure, idempotent read, cached in `~/.manifest-cli/cache/` and never written to the TSV. Repeat operations inside the TTL window do **zero** network.

### Verbs

| Verb | Moves | Idempotent | Safety | Status |
| ---- | ----- | ---------- | ------ | ------ |
| select / unselect | membership flag (`SELECT`) | yes | default benched; reversible | realized (TSV toggle) |
| clone | Local `absent` → `repo` | yes (skip if present) | read-only on remote | designed |
| verify | Remote `declared` → `verified` | yes (pure read) | grants outward trust | primitive in use (`git ls-remote`); user-facing sweep designed |
| create-remote | Remote → `verified` | yes (create-if-absent, never clobber) | irreversible — dry-run first | repo-scoped (`--create-repo-*`); fleet bootstrap is backlog |

Release disposition (eligible / current / release-disabled / PR-gated) is an orthogonal axis — see [Release Model](#release-model).

## Initialization

`manifest init fleet` is intentionally two-phase:

1. Scan directories and write `manifest.fleet.tsv`.
2. After review, consume the TSV and write fleet config/scaffolding.

Fleet scanning uses the shared discovery walker in `modules/core/manifest-discovery.sh` with the fleet profile. That profile preserves fleet-specific pruning, including dependency/build directories and package workspace directories that should not become fleet members by default.

Useful flags:

```bash
manifest init fleet --depth 3
manifest init fleet --all-folders
manifest init fleet --name platform-services
manifest init fleet --force
```

## Adoption And Reconciliation

```bash
manifest plan fleet
manifest plan fleet --apply
manifest reconcile fleet
manifest reconcile fleet --do
```

The plan/reconcile path exists for existing workspaces. It protects against target collisions and requires explicit opt-in for submodule adoption.

Mutation ladder:

- `--commit` requires `--apply` or `--do`.
- `--push` requires `--commit`.
- `--force` does not bypass target-collision checks.
- `adopt_submodule` requires `--adopt-submodules`.

## Release Model

Each fleet service has a release policy:

```yaml
services:
  example:
    path: "./example"
    type: "service"
    branch: "main"
    release:
      enabled: true
      strategy: "direct"
```

`strategy` is a single self-describing field. Its values read in plain English:

- `direct` — `manifest ship fleet` tags and pushes the release directly.
- `none` — the member is never released by fleet ship (skipped).
- `pr` — the member is **PR-gated**: its release must land through a reviewed pull request. `manifest ship fleet` lists PR-gated members in the preview and **refuses to apply** them (fail-closed), printing a `manifest pr fleet ... -y` replay command. Release them with `manifest pr fleet -y`.

Release-disabled services appear in status and planning output but are skipped by `manifest ship fleet`. Ship preview classifies them from config before release probes, so a release-disabled member is not scanned for `VERSION` or non-canonical version surfaces during ship planning.

Release-enabled services are eligible, not unconditional. Fleet ship skips an eligible member when its worktree is clean and its HEAD is already the commit tagged for the current `VERSION`. Dirty files or non-formula commits after that tag make the member releaseable; formula-only drift is skipped by planning and prevented at repo ship completion.

Fleet release still operates each member through the repo release flow, whose version writer updates that member's `VERSION` file and explicit `version.sync` targets only. Fleet status and ship preview can report non-canonical package/version surfaces read-only; detection never adds a release target by itself.

## Repo Identity

Repo-scoped commands use the current `.git` root. Fleet-scoped commands use the fleet root and config. The CLI prints the resolved target before apply so a nested checkout cannot be released by accident.

## Docs Generation

Fleet docs generation can refresh per-service docs and generate a managed Jekyll docs site. Docs-site generation is on by default and covered in [DOCS_SITE.md](DOCS_SITE.md).

## Current Limitations

- Repo-scoped release commands do not accept a path selector.
- Fleet release strategies are `direct`, `none`, or `pr` (PR-gated, routed to `manifest pr fleet`); more advanced orchestration belongs behind explicit future config.
- MCP fleet operations are planned as read-only in v1.
