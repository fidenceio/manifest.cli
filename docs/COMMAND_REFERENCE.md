# Manifest CLI Command Reference

Every supported command, with its flags. For live help, run
`manifest <command> --help`.

If you have not met the preview/apply model, `MANIFEST_CLI_AUTO_CONFIRM`, or the release
gate yet, read the [Migration Guide](MIGRATION.md) first — this page assumes them.

## Command Tree

The main workflow uses a verb, a scope, and an optional action:

```text
manifest
├── init [repo|fleet]                          guided or explicit setup; --connect on explicit scopes
├── status repo|fleet                           inspect current state
├── ship
│   ├── repo patch|minor|major|revision         release one repo
│   ├── repo resume                            finish an interrupted release
│   ├── fleet patch|minor|major|revision        release members, then ship the manager
│   ├── fleet resume                           finish interrupted member releases
│   └── fleet manager                          ship only the coordination root
├── discover|add|update|validate fleet          manage membership
├── plan|reconcile fleet                       prepare and apply adoption repairs
├── docs [fleet]                               generate documentation
├── topics fleet                               add GitHub topics
├── pr create|status|checks|ready|merge|update   manage a pull request
├── pr fleet                                   manage fleet pull requests
├── config show|setup|list|get|set|unset|describe|doctor|time
├── env generate|validate
├── revert
│   ├── repo [<tag>]                           preview or apply a local tag checkout
│   └── fleet [<snapshot>]                     restore manager and recorded member commits
├── doctor|security                            inspect health and security
├── recipe list|show|explain                    inspect execution recipes
├── cleanup repo|fleet|state
├── upgrade|reinstall|uninstall
└── version|help
```

Cloud commands and the remaining specialist options appear below. Removed
spellings and their replacements are listed in the [Migration Guide](MIGRATION.md).

## Global Rules

| Rule | Detail |
| ---- | ------ |
| Shape of a command | `manifest <verb> <scope>`, for example `manifest ship repo patch` |
| Plan by default | Anything that changes something only plans, unless `-y` / `--yes` is present |
| Explicit plan | `--dry-run` always means plan only |
| Conflicting modes | `--dry-run` cannot be combined with an apply flag, in either order |
| Local apply | `--local -y` does the local work and skips everything remote |
| Which repo? | Repo scope uses the `.git` root of your current directory |
| Which repos? | Fleet scope uses the fleet config and the selected rows of the fleet TSV |

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Success — either an apply finished, or a plan was printed (the default) |
| `1` | Error: bad arguments, a failed pre-flight check, a declined confirmation, or a failed apply in which nothing was released |
| `2` | Partial completion of `ship fleet` or `revert fleet`: one or more member releases or checkouts applied, then a later step failed. Read the closing block and the recovery report; a retry without `--force-bump` skips members already at their tag. |
| `3` | Protective skip — a safety guard refused something destructive (for example `uninstall` running under a temporary `HOME`) |
| `4` | Paused for a documentation handoff (`docs.handoff`). Not a failure: no release commit, tag or push was made. A brief naming what the documentation needs is written under `.git/`, and its path is printed. Edit the documentation and re-run the identical command — that run verifies the edits and continues the release |
| `10` | A plan was printed and no consent was given — only ever returned when `preview.exit_code` is set to `distinct` |

**Why `0` covers both cases.** A plan is a successful run, so by default it exits `0`
just like an apply. That is fine for a human and awkward for a script that needs to tell
"I printed a plan, waiting for `-y`" apart from "I released something".

If you need that distinction, set `preview.exit_code: distinct` (or
`MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct`). Every plan surface — `ship`, `ship fleet`,
and the `pr` plans — then returns `10` instead of `0`. Nothing else changes: `--dry-run`
is still a plan, apply exit codes are untouched, and Manifest re-checks the plan
fingerprint at apply time so a plan that drifted since you read it prints a warning
without blocking.

## Core Journey

### `manifest init` — guided setup

```bash
manifest init
manifest init --dry-run
manifest init -y
manifest init --depth N|auto
manifest init --name NAME
manifest init -f|--force
```

The guided front door. By default it inspects your current directory without changing
anything and shows a proposed setup — recognising a single repository, a folder that
could become a fleet, or something already configured.

With `-y` it applies that setup through the audited apply path. When setup is
applied, one audit record is written. For a single repository the apply needs no extra environment variable as long as
the target is unambiguous — meaning you are on a named branch. An `origin` remote is not
required during onboarding, since you may not have created one yet.

### `manifest config`

```bash
manifest config
manifest config show
manifest config setup
manifest config list [--layer local|project|fleet|global] [--json]
manifest config get <key>
manifest config set [--layer local|project|global] <key> <value>
manifest config unset [--layer local|project|global] <key>
manifest config describe <key>
manifest config doctor
manifest config doctor --fix
```

Reads and writes the layered YAML configuration.

`list`, `get`, and `describe` look at every layer: `env`, `local`, `project`, `fleet`
(inherited from the fleet root), `global`, and the built-in defaults.

`set` and `unset` can write only `global`, `project`, or `local`. `--layer fleet` is
rejected on purpose — those files live in a **different repository**, so writing them
from inside a member would modify a repo you never named. Change fleet-wide values by
running the same command at the fleet root. Writing the global config, and destructive
fixes, both require confirmation.

Layer model: [User Guide — Configuration](USER_GUIDE.md#configuration).

### `manifest init repo|fleet`

```bash
manifest init repo [--dry-run] [-y|--yes] [--remote URL] [--no-connect] [--create-repo-private|--create-repo-public]
manifest init fleet [--dry-run] [-y|--yes] [--depth N] [--all-folders] [--name NAME] [--force]
                    [--connect] [--parallel] [--clone-only] [--pull-only]
                    [--create-repo-private|--create-repo-public]
```

Repository setup is **dry-run by default**. `manifest init repo -y` initializes
Git on the configured release branch when necessary, connects `origin`, scaffolds
missing files, and runs the same configured local release check as ship. It does
not bump a version, create a commit or tag, publish a release, or push.

When `origin` is missing, the preview proposes a **private GitHub repository**;
`-y` creates it using `github.owner` or the authenticated GitHub user. Use
`--remote URL` to connect an existing remote, or `--create-repo-public` to choose
public visibility explicitly. Existing origins are preserved. Empty origins need
no pull; populated origins are fast-forwarded before scaffolding. Unreachable
remotes, conflicts and diverged histories fail setup instead of being hidden.

`--no-connect` requests only a local scaffold and explicitly leaves readiness
unverified. Fleet initialization retains its reviewed, two-phase membership flow
and opt-in `--connect`; `--create-repo-*` creates selected member remotes in Phase 2.

`init repo` creates the files a Manifest project needs: `VERSION`, `README.md`,
`CHANGELOG.md`, `.gitignore`, `docs/`, `scripts/run-tests.sh`, `.env.example`,
`robots.txt`, `ai.txt`, and `manifest.config.local.yaml`. Each is written only if absent.
`--dry-run` lists them with a one-line purpose for each; the
[User Guide](USER_GUIDE.md#first-time-setup) has the same table in full, including why the
two crawl-privacy files are there.

**Guided or explicit setup.** Bare `manifest init` handles an empty directory
as a new repository, checks an existing repository for missing files, or offers
fleet discovery when child repositories exist. An existing `VERSION` alone does
not mean setup is complete. Both bare and explicit repository setup use the same
plan and readiness checks. `init -y` on a fleet candidate writes the membership
list and stops for review; `init fleet -y` applies the reviewed selection.

Readiness checks the release branch, Git author/committer identity, valid version,
required files, available origin CI, and the configured release check. A failed or missing real check returns nonzero
with a blocker; init preserves existing checks and does not disable verification.
New generated checks run in containers; applying may build images and download
dependencies inside those containers. A new scaffold can pass structural
verification of its bounded file inventory. Adding application files makes that
check fail until real project verification is supplied; it is not a passing
placeholder for untested application code. Remote CI cannot be certified before
publication; init reports that limitation without publishing to test it. A passing
init establishes current local readiness, not a guarantee of later remote service
availability or push permissions.

**How `init` treats an existing `.gitignore`.** It never overwrites it. Instead it *adds*
missing recommended rules under a marked header and tells you how many it added. This is
how a `.gitignore` written by an older version of Manifest picks up rules added since —
notably the `KEY MATERIAL` block that refuses to commit private keys.

The upgrade is strictly append-only. Nothing existing is rewritten, reordered, or
removed. If a rule's exact opposite is already present, it is skipped rather than
reversing a choice you made deliberately. Running it again adds nothing. Releases never
do this — `manifest ship` only reports the gap.

`init fleet` discovers a fleet in two phases: the first run writes the member list for
you to review, the second acts on it.

**Creating GitHub repositories is always explicit.** Pass exactly one of
`--create-repo-private` or `--create-repo-public`. Set `github.owner` to a user or
organisation and both the plan and the apply target `<owner>/<repo>`; leave it unset and
`gh` uses whichever account you are logged in as. Phase 2 re-checks each selected
directory's own `.git` state from disk, so a stale `HAS_GIT` value in the TSV cannot
cause a member to inherit the fleet root's repository or remote.

### `manifest ship`

```bash
manifest ship repo patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--explain] [--force-bump] [-i]
manifest ship fleet patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--force-bump] [--require-clean]
manifest ship repo resume [--dry-run] [-y|--yes]
manifest ship fleet resume [--dry-run] [-y|--yes]
manifest ship fleet manager [--dry-run] [-y|--yes] [--local]
```

A repo release can raise the version, generate docs, commit, tag, push, publish GitHub
Release notes, and — where applicable — publish the Homebrew formula. Before reporting
success it requires a clean source tree, and for a published release it also requires
that `HEAD` is still the commit it pushed.

A fleet release applies the same policy to each release-enabled member that has
something to release. Members that are already tagged and clean are listed and skipped
as `no changes`.

The fleet ship then commits and pushes the **manager**, the fleet coordination
root. This also runs when every member is skipped, and with `fleet.versioning:
none`; that setting disables the version stamp, not the manager commit or push.
Only the coordination allowlist is staged. A pending fleet version is landed
without another bump when no new member release is being made. `--local` keeps
the manager commit local. `ship fleet manager` remains available for a root-only
change or retry.

`--require-clean` refuses a fleet ship if a member has uncommitted changes.
The former `--noprep` spelling has been removed.

`--force-bump` releases even when nothing has changed since the last tag. It is
forward-only: you get a new commit and a new tag, and no history is ever rewritten.

`resume` picks up a release that stopped partway. It does not repeat the whole release —
it continues the remaining steps for the version and tag already on disk, such as pushing
the tag or publishing the formula. `manifest ship fleet resume` does the same for each
stranded member, and does not accept `--local`.

### Version increments

A version is an ordered list of numbers of **any length** — nothing here assumes three
or four. An increment names one position; raising it resets every position to its right
to zero, or removes it:

| From | `major` | `minor` | `patch` | `revision` |
| ---- | ------- | ------- | ------- | ---------- |
| `20.1.0` | `21.0.0` | `20.2.0` | `20.1.1` | `20.1.0.1` |
| `20.1.0.3` | `21.0.0` | `20.2.0` | `20.1.1` | `20.1.0.4` |
| `1.2.3.4.5` | `2.0.0` | `1.3.0` | `1.2.4` | `1.2.3.5` |

**Read a fourth number as belonging to the third, not running alongside it.** `20.1.0.3`
means "the third re-cut of `20.1.0`". So a `patch` from there gives `20.1.1` — a patch
that has had no re-cuts — and the fourth number simply goes away.

Use `revision` when you need to re-cut a version you already released (a bad tag, a
packaging-only fix) and the code identity of `20.1.0` still stands. **It is not a
durable counter**: it lasts only until the next `patch`, `minor`, or `major`. That is by
design.

> **Locked 2026-08-16.** `revision` meaning a non-durable re-cut is settled, not a
> placeholder waiting for a better idea. Anything that must survive ordinary releases
> needs its own field, because it has to be able to hold still while `VERSION` moves and
> move while `VERSION` holds still. `VERSION` cannot do both: its single job is to answer
> "is production this tree?", and release verification depends on it having exactly one
> meaning and one lifecycle. Two meanings sharing one field would break that, and no
> amount of arithmetic on a single field can give two meanings separate lifecycles.

**Positions are what matter; names are just aliases.** You can address any position by
number, named or not:

```bash
manifest ship repo patch      # the 3rd number
manifest ship repo 3          # exactly the same thing
manifest ship repo 6          # the 6th number (1.2.3 -> 1.2.3.0.0.1)
```

**You can rename the positions** with `version.components`, an ordered list where the
index *is* the position — so there is no second place to declare a position and no way
for the two to disagree. It defaults to `major,minor,patch,revision`, and even those four
can be replaced:

```yaml
version:
  components: "generation,major,minor,patch"   # `major` now means position 2
```

Naming positions beyond the fourth is just a longer list
(`major,minor,patch,revision,build,hotfix`).

An unusable list is **refused**, not quietly replaced with the defaults. That covers a
duplicate name, an all-digit name that would collide with addressing positions by
number, and a blank entry that would silently shift every later name one position left.
Falling back to the standard four for a project that configured something else would cut
the release against the wrong position.

Versions containing non-numeric text (`1.2.3-rc1`, `v1.2.3`) are refused rather than
guessed at, and `VERSION` is left alone. `version.separator` (default `.`) applies
throughout.

Which files get written:

- Repo and fleet releases write `VERSION`, and only `VERSION`, today.
- `version.sync` is opt-in. Unset, no package manifest or lockfile is touched.
- `version.sync` handles a `version` field at the **top level** of JSON, TOML, and YAML.
  Missing files, versions nested deeper, and unsupported formats are skipped.
- A read-only scanner uses `modules/catalog/version-handlers.tsv` to recognise known
  package and version files. `manifest status`, `manifest status --json`,
  `manifest doctor`, fleet status, and fleet release plans report what they found and
  change nothing.
- Tune that reporting with `version.surfaces.enabled`, `version.surfaces.catalog`,
  `version.surfaces.scan_depth`, and `version.surfaces.notification_mode`.

## Fleet Operations

```bash
manifest status fleet [--bootstrap]
manifest discover fleet [--depth N] [--all-folders]
manifest add fleet <path> --name <name> [--dry-run] [-y|--yes]
manifest update fleet [--dry-run] [-y|--yes]
manifest validate fleet
manifest docs fleet [--dry-run] [-y|--yes]
manifest topics fleet [--dry-run] [-y|--yes]
manifest plan fleet [-y|--yes] [--dry-run]
manifest reconcile fleet [-y|--yes] [--dry-run] [--commit] [--push] [--adopt-submodules]
```

Verb-first is the supported spelling (`manifest topics fleet`, not `manifest fleet topics`).

`manifest topics fleet` turns the pieces of a repository's dotted name into GitHub
topics, and only ever **adds** them. It runs only when `topics.from_name` is set to
`inner`, `all`, or `all-but-first` — either in `manifest.fleet.config.yaml` for the whole
fleet, or just for your machine with:

```bash
manifest config set topics.from_name inner --layer global
```

A layered or environment value beats the fleet YAML. Note the distinction:
`manifest.fleet.config.yaml` is the fleet *definition*, not the `fleet` configuration
layer — see [User Guide — Configuration](USER_GUIDE.md#configuration).

Once enabled, the same projection also runs as part of `manifest update fleet`, and
quietly — one summary line at most — at the end of a completed `manifest ship fleet -y`.

## Diagnostics

```bash
manifest status [repo|fleet] [--json] [--bootstrap]
manifest doctor
manifest security [--write]
manifest recipe list
manifest recipe show <recipe-id>
manifest recipe explain <recipe-id>
```

Diagnostics change nothing unless a command explicitly says otherwise.

## Pull Requests

These wrap `gh` and need no Cloud:

```bash
manifest pr
manifest pr create [--draft] [gh flags...]
manifest pr status [<number|branch>]
manifest pr checks [<number|branch>] [--watch]
manifest pr ready [<number|branch>] [-y|--yes]
manifest pr merge [<number|branch>] [--squash|--merge|--rebase] [-y|--yes]
manifest pr update [<number|branch>] [-y|--yes]
```

These need Cloud:

```bash
manifest pr queue
manifest pr policy show
manifest pr policy validate
```

## Documentation

```bash
manifest docs
manifest docs metadata
manifest docs cleanup
manifest docs fleet --dry-run
```

The documentation website is **off by default**. Turn it on with `docs.generate.site`
(or `docs.site.enabled`) and see [DOCS_SITE.md](DOCS_SITE.md) for the rest of the keys.

## Env Schema

```bash
manifest env generate [--check] [--dry-run] [-y|--yes]
manifest env validate
```

A component spec's `env:` block is the single source of truth for a repository's
environment variables. `env generate` builds the derived files from it:

- `.env.example` — always
- `k8s/env/configmap.yaml` and `k8s/env/external-secret.yaml` — when a `k8s/` directory exists
- the Dockerfile `ARG`→`ENV` marker block, for values needed at build time

Planning is the default and `-y` writes. `--check` is the drift gate for use in a
release: it exits `1` if any generated file is out of date. `env validate` only reads —
it checks the prefix policy, whether generated files have drifted, and that `.env` is
properly git-ignored.

**The prefix policy is on by default**, to keep environment-variable names tidy. Your
application's own variable names must start with this repository's prefix. Well-known
framework names (`DATABASE_URL`, `NEXT_PUBLIC_*`, and similar) and the `MANIFEST_CLI_*`
namespace are always allowed.

With no `env.prefix` set, the prefix is **derived from the project name** and stays
vendor-neutral: `fidence.app.kanizsa` becomes `FIDENCE_APP_KANIZSA_`, and `my-tool`
becomes `MY_TOOL_`. Set `env.prefix` to something explicit (`ACME_`) to require that
instead, or `env.prefix: off` to switch the policy off.

How strictly it is enforced is configurable: `env.naming_enforcement` is `strict` by
default, which blocks; `warn` makes violations advisory. `env.naming_allow` takes extra
allowed entries, comma-separated, where a trailing `_` means "treat as a prefix".

`manifest init repo` and its connect phase create a missing `.env.example` — never
overwriting an existing one — using the spec when an `env:` block exists, and honouring
the configured prefix.

## Recovery

```bash
manifest ship repo resume     # continue a release that stopped partway
manifest revert repo v1.2.3    # preview a tag checkout
manifest revert repo v1.2.3 -y # apply the checkout
manifest revert fleet          # list available snapshot commits
manifest revert fleet <commit> # preview a recorded fleet checkout
manifest revert fleet <commit> -y # apply member checkouts, then manager
```

`revert repo [<tag>]` previews by default. Specify a local tag, or select one of the
ten highest version tags when running in a terminal. Without a terminal, omitting
the tag lists available versions; applying requires an explicit tag. `-y` / `--yes`
applies the checkout, and `--dry-run` explicitly previews.

The target is the tag's resolved commit, even when a branch has the same name.
Git refuses to overwrite conflicting tracked, untracked, or ignored files; no force,
stash, reset, commit, tag, or push is performed. Submodule working trees stay as they
are. No origin remote or current branch is required for this local checkout.
`revert fleet [<snapshot>]` restores the exact member commits recorded in
`manifest.fleet.snapshot.json`, then checks out the manager at the selected commit.
A snapshot is a manager commit containing that file. Fleet ships record the map
after members finish and include it in the manager coordination commit; it is
available after cloning the manager's Git history. No extra tag is created.
Omit the snapshot to list recent manager commits that changed the map. Applying
requires an explicit manager commit or ref and `-y` / `--yes`.

Fleet revert requires clean manager and member working trees, every recorded
repository inside the fleet root, and every recorded commit available locally.
It acquires the fleet and repository locks and checks all targets before checkout.
Ignored-file conflicts and Git hooks can still stop a later checkout; failures
report the completed count and return `2` after any checkout completed. Members
are restored first and the manager last; no automatic rollback or push occurs.
Submodule working trees are preserved. Non-Git/missing members are recorded with
an unavailable commit and make that snapshot ineligible for fleet revert.

Manager history from before snapshot recording cannot reconstruct member
versions. Fleet snapshots record committed state; uncommitted files are not backups.

Afterwards you are in **detached HEAD**: viewing that tag rather than being on a branch.
`git switch -` returns you to the branch you came from. `revert repo` is therefore a way to
*look at* an old release, not a way to undo a published one. Undoing a published release
is a declared Non-Goal ([NORTH_STAR.md](NORTH_STAR.md)): recovery is roll-forward — ship
a new version.

When a release fails partway, run `manifest ship repo resume` first. The failure report
may also suggest `git reset --hard <sha>`; read it before running it. A release **begins**
by committing whatever you had uncommitted (see
[User Guide](USER_GUIDE.md#what-the-automatic-commit-includes-and-what-it-leaves-out)), so
that `<sha>` is from before your own work was committed, and a hard reset discards your
changes together with Manifest's. Check `git log` and `git status` first; `git reflog` can
still find a commit you have moved away from.

## Maintenance

```bash
manifest cleanup [repo|fleet|state] [--dry-run] [-y|--yes]
manifest upgrade
manifest uninstall [--dry-run] [-y|--yes]
manifest reinstall [--dry-run] [-y|--yes]
manifest security [--write]
manifest test [suite]
```

### `manifest cleanup`

Removes **Manifest's own leftovers** — never your work. Previews by default like every
other mutating command; `-y` applies with no prompt.

| Scope | What it covers |
| --- | --- |
| `repo` (default) | This repository |
| `fleet` | Every member of the fleet roster |
| `state` | This machine's Manifest caches — not repo-specific, so it is deliberately a third word rather than a repo/fleet scope |

**What it removes**

- Retired scaffold sidecars: `.gitignore.manifest`, `robots.txt.manifest`,
  `ai.txt.manifest`, `scripts/run-tests.sh.manifest`, `.env.example.manifest`. Manifest
  wrote these beside an existing file as a merge reference until v58.0.0, when the
  mechanism was removed for drifting from the CLI that generated them. The writer went;
  the files did not, so any repo scaffolded by an older CLI still carries them.
- Manifest's own temporary files.
- Stale `git worktree` records, via `git worktree prune`.
- `state` only: stale runtime cache files under `TMPDIR`, empty scratch directories, and
  ship logs past the keep-last-N window.

**What it never removes**

- **A git-tracked file.** A committed sidecar is named in the summary with the exact
  `git rm` command instead, so removing it stays a reviewable commit you make.
- Your build output — `node_modules/`, `target/`, `dist/`, `build/`, `vendor/`, `.venv/`.
  Those belong to your build system.
- A git worktree directory or anything inside one. `prune` only drops records for
  directories that are already gone; reclaiming a live worktree's space needs
  `git worktree remove --force`, which would destroy uncommitted work, so `cleanup`
  reports those directories and stops.
- `manifest.config.global.yaml`, the `audit/` compliance log, live locks, and `gh-rate/`
  — the last is not a cache despite the name: it paces GitHub mutations, and clearing it
  removes the protection that keeps you under the rate limit.

Because it publishes nothing, `cleanup -y` applies even on a detached HEAD or in a repo
with no `origin` remote, where release commands correctly refuse.

`security` is **read-only by default**. It reports private files that are tracked in git,
anything that looks like personal data, and environment-file hygiene — and writes
nothing. `--write` additionally saves a timestamped report to the docs archive. Neither
mode writes `docs/SECURITY_ANALYSIS_REPORT.md`, which is maintained by hand. `--check` is
still accepted and also means read-only, so existing hooks and recipes keep working.

`uninstall` plans by default, and keeps your global config unless you confirm removing it
separately.

## Optional Cloud And Agent

```bash
manifest cloud config|status|generate
manifest agent init|auth|status
```

These need Manifest Cloud plugins. Ordinary repo and fleet releases do not.

## Environment

Frequently used variables:

| Variable | Purpose |
| -------- | ------- |
| `MANIFEST_CLI_AUTO_CONFIRM` | Allow an ambiguous apply target (detached HEAD, or no origin) **after** `-y`. Not needed for an ordinary apply, and cannot start one |
| `MANIFEST_CLI_PREVIEW_EXIT_CODE` | `zero` (default) or `distinct` — the exit code for a plan with no consent; see Exit Codes |
| `MANIFEST_CLI_SHIP_FOLLOWUP_PATCH` | Controls the canonical follow-up patch behaviour |
| `MANIFEST_CLI_DOCS_HANDOFF` | `off` (default), `auto` or `always` — pause before the release commit so whoever is driving can finish the documentation; see Exit Codes `4`. Also settable as `docs.handoff`, including in a committed config: it names no program |
| `MANIFEST_CLI_DRIVER` | Override who Manifest thinks is driving: `none`, `ci`, `claude-code` or `other-agent`. Environment only, never a config key — a committed file must not assert who is at the keyboard. Affects only the `auto` handoff default, never a safety control |
| `MANIFEST_CLI_DOCS_GENERATE_SITE` | Turn on documentation-website generation (default off) |
| `MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES` | Ask GitHub to enable Pages via `gh api` |
| `MANIFEST_CLI_GITHUB_ACTIONS_WAIT` | Wait for GitHub Actions during release paths |
| `MANIFEST_CLI_ENV_PREFIX` | Prefix policy: empty means derived from the project name (the default, and on); an explicit value overrides; `off` disables |
| `MANIFEST_CLI_ENV_NAMING_ENFORCEMENT` | `strict` (default, blocks) or `warn` (advisory) |
| `MANIFEST_CLI_ENV_NAMING_ALLOW` | Extra allowed names, comma-separated; a trailing `_` means prefix |

Every setting has a matching variable. For the authoritative mapping of a specific key,
including which layer currently wins, run `manifest config describe <key>`.
