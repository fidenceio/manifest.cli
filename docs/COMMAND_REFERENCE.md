# Manifest CLI Command Reference

Every supported command, with its flags. For live help, run
`manifest <command> --help`.

If you have not met the preview/apply model, `MANIFEST_CLI_AUTO_CONFIRM`, or the release
gate yet, read the [Migration Guide](MIGRATION.md) first — this page assumes them.

## Global Rules

| Rule | Detail |
| ---- | ------ |
| Shape of a command | `manifest <verb> <scope>`, for example `manifest ship repo patch` |
| Plan by default | Anything that changes something only plans, unless `-y` / `--yes` is present |
| Explicit plan | `--dry-run` always means plan only |
| Local apply | `--local -y` does the local work and skips everything remote |
| Which repo? | Repo scope uses the `.git` root of your current directory |
| Which repos? | Fleet scope uses the fleet config and the selected rows of the fleet TSV |

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Success — either an apply finished, or a plan was printed (the default) |
| `1` | Error: bad arguments, a failed pre-flight check, a declined confirmation, or a failed apply |
| `3` | Protective skip — a safety guard refused something destructive (for example `uninstall` running under a temporary `HOME`) |
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

### `manifest first`

```bash
manifest first
manifest first --dry-run
manifest first -y
manifest first --depth N|auto
manifest first --name NAME
manifest first -f|--force
```

The guided front door. By default it inspects your current directory without changing
anything and shows a proposed setup — recognising a single repository, a folder that
could become a fleet, or something already configured.

With `-y` it applies that setup through the audited apply path, writing one audit record
per run. For a single repository the apply needs no extra environment variable as long as
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

### `manifest init`

```bash
manifest init repo [--dry-run] [-y|--yes] [--create-repo-private|--create-repo-public]
manifest init fleet [--dry-run] [-y|--yes] [--depth N] [--all-folders] [--name NAME] [--force] [--create-repo-private|--create-repo-public]
```

`init repo` creates the files a Manifest project needs.

**How it treats an existing `.gitignore`.** It never overwrites it. Instead it *adds*
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

### `manifest prep`

```bash
manifest prep repo [--dry-run] [-y|--yes]
manifest prep fleet [--dry-run] [-y|--yes] [--parallel]
```

Gets remotes and workspace state ready before release work.

### `manifest refresh`

```bash
manifest refresh repo [--dry-run] [-y|--yes]
manifest refresh fleet [--dry-run] [-y|--yes]   # DEPRECATED — use 'manifest update fleet'
```

Refreshes generated metadata, docs, and fleet membership.

`refresh fleet` is **deprecated**. It still works and warns. Prefer
`manifest update fleet` to re-scan which repositories are members, and
`manifest docs fleet` to regenerate documentation.

### `manifest ship`

```bash
manifest ship repo patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--explain] [--force-bump] [-i]
manifest ship fleet patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--force-bump] [--noprep]
manifest ship repo resume [--dry-run] [-y|--yes]
manifest ship fleet resume [--dry-run] [-y|--yes]
```

A repo release can raise the version, generate docs, commit, tag, push, publish GitHub
Release notes, and — where applicable — publish the Homebrew formula. Before reporting
success it requires a clean source tree, and for a published release it also requires
that `HEAD` is still the commit it pushed.

A fleet release applies the same policy to each release-enabled member that has
something to release. Members that are already tagged and clean are listed and skipped
as `no changes`.

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
manifest plan fleet [--apply]
manifest reconcile fleet [--do|--apply] [--commit] [--push] [--adopt-submodules]
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

`manifest init repo` and `manifest prep repo` create a missing `.env.example` — never
overwriting an existing one — using the spec when an `env:` block exists, and honouring
the configured prefix.

## Recovery

```bash
manifest ship repo resume     # continue a release that stopped partway
manifest revert               # check out an older version tag
```

`revert` lists the ten highest version tags and checks out the one you pick. It acts as
soon as you choose — there is no `-y` step — but it only moves where you are looking. It
rewrites nothing and deletes no commits, and git refuses if you have local changes that
the checkout would overwrite.

Afterwards you are in **detached HEAD**: viewing that tag rather than being on a branch.
`git switch -` returns you to the branch you came from. `revert` is therefore a way to
*look at* an old release, not a way to undo a published one — see §8.8 of
[TRACKER.md](TRACKER.md) for the open question of whether a guarded `rollback` should
exist at all.

When a release fails partway, run `manifest ship repo resume` first. The failure report
may also suggest `git reset --hard <sha>`; read it before running it. A release **begins**
by committing whatever you had uncommitted (see
[User Guide](USER_GUIDE.md#what-the-automatic-commit-includes-and-what-it-leaves-out)), so
that `<sha>` is from before your own work was committed, and a hard reset discards your
changes together with Manifest's. Check `git log` and `git status` first; `git reflog` can
still find a commit you have moved away from.

## Maintenance

```bash
manifest upgrade
manifest uninstall [--dry-run] [-y|--yes]
manifest reinstall [--dry-run] [-y|--yes]
manifest security [--write]
manifest test [suite]
```

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
| `MANIFEST_CLI_DOCS_GENERATE_SITE` | Turn on documentation-website generation (default off) |
| `MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES` | Ask GitHub to enable Pages via `gh api` |
| `MANIFEST_CLI_GITHUB_ACTIONS_WAIT` | Wait for GitHub Actions during release paths |
| `MANIFEST_CLI_ENV_PREFIX` | Prefix policy: empty means derived from the project name (the default, and on); an explicit value overrides; `off` disables |
| `MANIFEST_CLI_ENV_NAMING_ENFORCEMENT` | `strict` (default, blocks) or `warn` (advisory) |
| `MANIFEST_CLI_ENV_NAMING_ALLOW` | Extra allowed names, comma-separated; a trailing `_` means prefix |

Every setting has a matching variable. For the authoritative mapping of a specific key,
including which layer currently wins, run `manifest config describe <key>`.
