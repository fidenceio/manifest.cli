# Manifest Fleet Design Spec

A *fleet* is a set of independent Git repositories that Manifest coordinates from one
workspace folder, called the *fleet root*. A fleet does not use Git submodules, and it
does not merge the member repositories into the history of the root repository.

## Goals

- Use the same command model for one repository and for a fleet.
- Keep fleet membership explicit and easy to review.
- Support services that release and services that do not, in the same workspace.
- Preview every change before applying it.
- Keep the root workspace's metadata separate from each member's own content.

## Core Files

| File | Purpose |
| ---- | ------- |
| `manifest.fleet.tsv` | The roster. A table of scanned folders that a person reviews, with a column that selects the members. |
| `manifest.fleet.config.yaml` | The fleet config that commands read |
| `manifest.fleet.plan.yaml` | The adoption and reconciliation plan that `manifest plan fleet -y` writes |
| `manifest.config.yaml` / `manifest.config.local.yaml` (at the fleet root) | Manifest settings for the whole fleet. Every member inherits them as the read-only `fleet` config layer. See [User Guide — Configuration](USER_GUIDE.md#configuration). |

`manifest.fleet.config.yaml` defines *what the fleet is*. Its presence is what makes a
directory the fleet root. The two `manifest.config*.yaml` files beside it configure
*how Manifest behaves* for every member. They are a different mechanism.

## Fleet States And Vocabulary

The fleet model has one universe (every repository found) and one selected subset (the
members). Every other label is worked out from what Manifest observes. No other state
is stored.

### Corpus, Members, Benched

```text
CORPUS  = git repositories discovered <= depth ceiling   (observed — the universe)
MEMBER  = a corpus repo explicitly selected              (declared — the fleet)
BENCHED = every other corpus repo                        (persisted — records triage)
```

Membership has two values: `member` or `benched`. It is **stored** in the `SELECT`
column of the roster, and you change it by editing that column.

- A scan writes each new row with `SELECT` set to `true` when the folder is a Git
  repository and to `false` when it is not. Review the roster after a scan, and set
  `SELECT` to `false` for any repository that should not be a member.
- A rescan keeps the `SELECT` value of every row that is already in the roster. So you
  do not have to sort the whole corpus again.
- A rescan with `manifest update fleet -y` adds a newly found Git repository as a
  member, because its new row is written with `SELECT` set to `true`.

### Depth

Discovery walks down from the fleet root. A global **ceiling** limits how deep it goes:
`MANIFEST_CLI_FLEET_MAX_DISCOVERY_DEPTH = 10`. The ceiling is a high safety limit, not
a target. It is not lowered to fit a particular fleet.

`--depth auto` adapts to each branch of the folder tree. Discovery walks each branch
down to its first Git repository and stops there, because repositories nested inside a
repository are excluded by default. If a branch holds no repository, discovery stops at
the ceiling. `auto` then resolves to the deepest repository it found. A workspace that
mixes depths is therefore captured in one pass: repositories directly under the root
and repositories in deeper folders are all found. An explicit `--depth N` forces a
fixed scan depth.

The roster's `# Depth:` header records the **deepest repository depth observed**. It is
a diagnostic, not the ceiling. A rescan without `--depth` uses the recorded depth, so
it does not drop rows that a deeper scan recorded.

**Depth profile and health (derived, not stored).** For each top-level folder
("bucket"), the depth profile gives the shallowest and the deepest depth at which a
repository appears. Manifest works these out from the `PATH` of each row when it needs
them and never stores them (see
[Storage](#storage-store-declared-cache-the-corpus-derive-labels)). `manifest status`
reports the profile. It flags any **mixed-depth bucket**, which is a bucket whose
shallowest and deepest repository depths differ. That usually means a repository was
nested by accident or a layout convention was broken. A healthy fleet keeps each bucket
at one depth.

### Three Orthogonal Axes

Each repository is described on three independent axes.

| Axis | Values | Kind | Where it comes from |
| ---- | ------ | ---- | ---------- |
| Membership | `member` ↔ `benched` | declared | the `SELECT` column of the roster |
| Local | `absent` → `present` → `repo` (has `.git`) | observed, no network | the disk; the `HAS_GIT` column caches the last scan |
| Remote | `undeclared` → `declared` → `verified` | declared URL, then observed | the member's own `origin`, or `services.<name>.url` in the fleet config for a member that is not cloned |

`Remote` has three values for safety. A recorded URL is a *claim* (`declared`), not
proof (`verified`). See [Verification Is Cost-Bounded](#verification-is-cost-bounded).

### Named States (Derived, Never Stored)

Members, by Local × Remote:

| State | Local | Remote | Safe operation |
| ----- | ----- | ------ | -------------- |
| Backed | repo | verified | ship |
| Unverified | repo | declared | verify first |
| Stranded | repo | undeclared | create the remote, then ship |
| Uncloned | absent | declared or verified | clone to restore |
| Lost | absent | undeclared | cannot be recovered; reported loudly |

A benched repository is either a **Candidate** (Local = `repo`, so it can be promoted
to member) or **Scenery** (not a repository: a grouping folder or a deliberate
placeholder such as `_holding`).

`missing` is not a basic state. It means `member` with Local `absent`. `unlisted` means
a repository on disk that is not yet in the roster. It counts as benched until a rescan
records it.

### Identity Is Path

A fleet repository is identified by its **path relative to the workspace**. The
adoption and reconciliation merge uses the same path as its key for removing
duplicates. The remote is **not** identity, so a repository with no remote is still a
full member. A move or a rename reads as a removal plus an addition, and a rescan
reconciles it. See also [Repo Identity](#repo-identity) for how commands resolve their
target.

### Storage: Store Declared, Cache The Corpus, Derive Labels

| Item | Kind | Authority |
| ---------- | ---- | --------- |
| `SELECT` (membership) in the roster | **declared** | the truth; a scan sets it only for a new row and never changes an existing one |
| corpus rows, `HAS_GIT`, `BRANCH` and `# Last scanned:` in the roster | **cached observation** | a baseline that a rescan reconciles |
| remote URL | **never stored in the roster** | read on demand from the member's own `origin`; for a member that is not cloned, from `services.<name>.url` in the fleet config |
| remote verified | **never stored** | observed live by `manifest status fleet --verify` |
| any derived label | **never stored** | worked out again from the declared and observed facts |

The roster columns are `SELECT`, `NAME`, `PATH`, `HAS_GIT` and `BRANCH`. The roster is
committed and pushed, so it carries no remote URL: a URL can contain a credential.
Manifest refuses to write a roster row that contains one.

The roster is a **hybrid** with a freshness stamp: declared membership plus a cached
corpus. It can be out of date only by what changed since `# Last scanned:`. `HAS_GIT`
and `BRANCH` are cached observations on purpose. A rescan refreshes them.

### Verification Is Cost-Bounded

Verification is the step that turns a `declared` remote into a `verified` one.

- **It is opt-in.** `manifest status fleet --verify` probes each member's remote.
  Without `--verify`, a member with a recorded URL reads as `declared`.
- **It uses the Git protocol.** The probe is `git ls-remote`, which does not use the
  GitHub REST or GraphQL rate limit. Each probe is limited to 15 seconds and never
  prompts for a password.
- **It stores nothing.** The result is shown and then discarded. It is not cached, so
  every `--verify` run probes again. A remote that does not answer reads as
  `undeclared` for that run.
- **A push checks the remote by itself.** `git push` to a missing or unreachable remote
  fails with no side effects, so a ship does not probe before it pushes.
- **A fleet ship refuses a member that has nowhere to push.** Before a non-local
  `manifest ship fleet -y` changes anything, it checks every member it is about to
  release. If a member has no usable `origin`, Manifest adds one from
  `services.<name>.url` in the fleet config when that holds a valid Git URL. If a
  member still has no remote, Manifest refuses the whole run.
- **Creating a remote never overwrites.** `--create-repo-private` and
  `--create-repo-public` run `gh repo create` only when the repository has no `origin`.
  Preview first: creating a GitHub repository cannot be undone by Manifest.

### Verbs

| Verb | Moves | Repeatable | Safety | Available as |
| ---- | ----- | ---------- | ------ | ------------ |
| select / unselect | membership flag (`SELECT`) | yes | reversible | edit the `SELECT` column in `manifest.fleet.tsv` |
| clone | Local `absent` → `repo` | yes (skips a repository that is present) | read-only on the remote | No working command. `manifest init fleet --connect` pulls the members that exist on disk. It stops with exit `2` before the connect phase when a selected member's folder is missing, so it does not clone that member. Clone it with `git clone` first. `manifest status fleet --bootstrap` lists the absent members and changes nothing. |
| verify | Remote `declared` → `verified` | yes (read-only) | uses the network; stores nothing | `manifest status fleet --verify` |
| create-remote | Remote → `verified` | yes (creates only if absent, never overwrites) | cannot be undone; preview first | `manifest init repo\|fleet --create-repo-private\|public` |

The last column states what you can run today. Planned work is tracked in
[TRACKER.md](TRACKER.md), not here.

Whether a member is released (eligible, current, release-disabled or PR-gated) is a
separate axis. See [Release Model](#release-model).

## Initialization

`manifest init fleet` has two phases on purpose:

1. Scan directories and write `manifest.fleet.tsv`.
2. After you review the roster, read it and write the fleet config and the scaffolding
   for each selected member.

Fleet scanning uses the shared discovery walker in
`modules/core/manifest-discovery.sh` with the fleet profile. That profile skips
dependency folders, build folders and package workspace folders, which should not
become fleet members by default.

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
manifest plan fleet -y
manifest reconcile fleet
manifest reconcile fleet -y
```

Use plan and reconcile for a workspace that already exists. `plan fleet` previews an
adoption plan, and `plan fleet -y` writes it. `reconcile fleet` previews what the plan
would change, and `reconcile fleet -y` applies it. This path protects against two plan
entries that target the same place, and it adopts a submodule only when you opt in.

Each stronger action needs the one before it:

- `--commit` requires `-y` (or `--yes`).
- `--push` requires `--commit`.
- `--force` does not bypass target-collision checks.
- An `adopt_submodule` plan entry requires `--adopt-submodules`.

## Release Model

Each fleet service has a release policy:

```yaml
services:
  example:
    path: "./example"
    branch: "main"
    release:
      enabled: true
      strategy: "direct"
```

`strategy` is one field with three values:

- `direct` — `manifest ship fleet` tags and pushes the release directly.
- `none` — fleet ship never releases the member. It is skipped.
- `pr` — the member is **PR-gated**: its release must land through a reviewed pull
  request. `manifest ship fleet` lists PR-gated members in the preview and **refuses to
  apply** them. It prints the command to run instead: `manifest pr fleet -y`.

A release-disabled service appears in status and planning output, and
`manifest ship fleet` skips it. The ship preview reads the release policy from the
config before it probes anything. So it does not scan a release-disabled member for
`VERSION` or for other files that carry a version.

A release-enabled service is eligible, but it is not always released. Fleet ship skips
an eligible member when its working tree is clean and its `HEAD` is already the commit
tagged for the current `VERSION`. Uncommitted files, or commits after that tag that
touch more than the Homebrew formula, make the member releasable. A difference in the
formula alone does not: planning skips it, and the completion check of a repository
ship prevents it.

A fleet release runs each member through the single-repository release flow. That flow
updates the member's `VERSION` file and the `version.sync` targets you listed, and
nothing else. Fleet status and the ship preview can report other files that carry a
version. They only report them. Finding such a file never makes it a release target.

## Repo Identity

Repo-scoped commands use the `.git` root of the current directory. Fleet-scoped
commands use the fleet root and its config. The CLI prints the resolved target before
it applies, so a nested checkout cannot be released by accident.

## Docs Generation

Fleet docs generation can refresh each service's docs and generate a managed Jekyll
docs site. The site is controlled by `docs.generate.site`, which defaults to `true`.
See [DOCS_SITE.md](DOCS_SITE.md).

## Current Limitations

These are deliberate limits of scope, not pending work. Pending work is listed in
[TRACKER.md](TRACKER.md).

- Repo-scoped release commands do not accept a path selector. This is a Non-Goal in
  [NORTH_STAR.md](NORTH_STAR.md) until the repo-identity contract is redesigned.
- Fleet release strategies are `direct`, `none` and `pr` (PR-gated, routed to
  `manifest pr fleet`). Richer orchestration is out of scope. It would need explicit
  config that does not exist and is not planned.
- MCP fleet operations are read-only.
