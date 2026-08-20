# Manifest CLI User Guide

Manifest breaks release work into named stages, each of which you run when you want it:

```text
config -> init -> prep -> refresh -> ship
```

Every stage that would change something shows you a plan and stops. Add `-y` (or
`--yes`) to actually do it. If preview-and-apply or the release gate are new to you,
read the [Migration Guide](MIGRATION.md) first — it covers just those two ideas.

## Core Concepts

### Repo Scope

"Repo scope" means the command acts on the one Git repository you are standing in.

```bash
manifest status repo
manifest ship repo patch
manifest ship repo patch -y
```

Manifest works out which repository that is by looking upward from your current
directory for the `.git` folder. You cannot pass it a path instead — release commands
deliberately act on where you are, so a mistyped path can never release the wrong
project.

### Fleet Scope

A **fleet** is a group of separate Git repositories you manage together. Two files
define it: `manifest.fleet.config.yaml` holds the settings, and `manifest.fleet.tsv`
lists the members and marks which are selected.

```bash
manifest status fleet
manifest ship fleet patch
manifest ship fleet patch -y
```

Before changing anything, fleet commands print where the fleet root is, which config
file they read, which members are selected, what they decided to do with each, and what
branch each one is on.

### Preview And Apply

| What you type | What happens |
| ---- | ------- |
| no `-y` | Shows the plan only |
| `--dry-run` | Same thing, spelled out |
| `-y` / `--yes` | Does the work |
| `--local -y` | Does only the parts that stay on your machine; nothing goes to GitHub |

`-y` does not then stop to ask "are you sure?" — asking for apply *is* the
confirmation.

There is a separate variable, `MANIFEST_CLI_AUTO_CONFIRM=1`. It exists for one narrow
job: letting an apply continue when Manifest cannot tell what it would act on — a
"detached HEAD" (your checkout is not on any branch) or a repository with no `origin`
remote. It only has an effect *after* you have already passed `-y`. It cannot start an
apply, and you do not need it for a normal one. This split matters in CI, where an
environment variable must never be able to publish a release by itself.

## First-Time Setup

Start with `manifest first`. It is the guided front door: it looks at where you are —
one repository, a folder of repositories, or a project already set up — and proposes a
sensible setup. It writes nothing until you apply.

```bash
manifest first
manifest first -y
```

Applying is recorded in the audit log. Underneath, `manifest first` just calls the
commands below, so you can run them yourself instead:

```bash
manifest doctor
manifest config show
manifest init repo
manifest init repo -y
```

`manifest init repo` creates the files a Manifest-managed project needs: `VERSION`,
`CHANGELOG.md`, a docs folder, and ignore rules.

## Repository Release Workflow

Look first:

```bash
manifest status
manifest doctor
```

Get the repository ready:

```bash
manifest prep repo
manifest prep repo -y
```

See what a release would do:

```bash
manifest ship repo patch
manifest ship repo minor
manifest ship repo major
```

Do it:

```bash
manifest ship repo patch -y
```

Do only the local half, leaving nothing public:

```bash
manifest ship repo minor --local -y
```

A repo release can raise `VERSION`, add a `CHANGELOG.md` entry, regenerate docs, commit,
create a tag, push, publish a GitHub Release, and — only in Manifest's own repository —
update the Homebrew formula. That formula update does not add a commit back here. Before
Manifest reports success it checks two things: that your working copy is clean, and that
nothing has been committed on top of the release it just pushed.

### What the automatic commit includes, and what it leaves out

Releasing starts by committing whatever you had uncommitted. Two rules shape that
commit, and both are easy to misread.

**Nested repositories are left alone.** If a folder inside your project has its own
`.git` and is not a declared submodule, Git would otherwise record it as a bare
"gitlink" — a pointer to a commit in a repository nobody can find. Manifest unstages
those and tells you, with your options. Declared submodules, and gitlinks already
recorded in history, are untouched. If you genuinely want bare gitlinks committed, set
`git.allow_new_gitlinks: true` (`MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS`).

**Work that appeared after you asked to ship is held back.** Manifest notes which files
were pending before it runs the test gate. A full gate takes minutes — long enough for
another session, an editor autosave, or a background generator to drop new files into
the tree. Those get unstaged and listed.

Read that list carefully, because its scope is narrower than it looks: those files are
kept out of **the automatic commit**, not out of the release. Later in the same run, the
version commit stages the whole tree on purpose — `VERSION`, `CHANGELOG.md`, and
regenerated docs all legitimately appear after the snapshot — so anything on the
"Left out …" list still gets committed one commit later. To see what actually shipped,
run `git show --stat HEAD` rather than assuming. To turn the guard off and sweep
everything into the first commit, set `git.allow_gate_drift: true`
(`MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT`). Manifest's own `.manifest-cli/` bookkeeping is
always exempt, because the gate writes its results there while running.

## Version Ownership

Manifest writes exactly one version file: `VERSION`.

`VERSION` holds numbers separated by dots — any number of them, not just three. Which
number an increment changes, what the positions are called (`version.components`), and
why a fourth number does not survive a `patch` are all explained in one place:
[Command Reference — Version increments](COMMAND_REFERENCE.md#version-increments).

Every other file that mentions a version is **non-canonical** — Manifest reads it but
will not write it. That covers `package.json`, `package-lock.json`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, `Chart.yaml`, and similar. Manifest finds them using a catalog
that ships with the tool, but finding is all it does: it will not edit them, will not
spam warnings into your scripts, and will not stop an unattended run.

Want some of them kept in step? Opt in by listing them:

```yaml
version:
  sync: "package.json,pyproject.toml,Chart.yaml"
```

Leaving `version.sync` unset is the default and means package files and lockfiles are
never touched. When set, the writer updates a `version` field at the **top level** of a
JSON, TOML, or YAML file. It skips files that do not exist, files where the version is
nested deeper, and formats it does not handle — and it never creates a file.

How much Manifest tells you about the files it found is configurable:

```yaml
version:
  surfaces:
    enabled: true
    catalog: ""          # empty means use the built-in catalog
    scan_depth: 5
    notification_mode: summary # summary | list | off
```

`manifest status` and fleet status say nothing when only `VERSION` is present, give a
one-line summary when other version files exist, and name them individually when
`notification_mode` is `list`. `manifest status --json` always includes the complete
`version_surfaces` object. `manifest doctor` reports both invalid settings and found
files as warnings only — never as errors.

One caveat worth knowing: there is a `files.version` setting for naming a different
canonical file, and the detection side honours it. But repo release, the main version
field in `status`, `resume`, and fleet release all still write `VERSION`. Until that is
finished, treat `files.version` as incomplete — it is tracked in
[TRACKER §8.12](TRACKER.md#8--enterprise-readiness-audit-2026-06-05).

## Fleet Workflow

### Initialize A Fleet

```bash
manifest init fleet
```

The first run scans the folder and writes `manifest.fleet.tsv` for you to review.
Edit that file — in particular, which members are selected — then run the command
again to create the fleet config and set up the repositories.

Useful variants:

```bash
manifest init fleet --depth 3
manifest init fleet --all-folders
manifest init fleet --name platform-services
manifest init fleet --create-repo-private   # show local setup plus the GitHub repos it would create
manifest init fleet --create-repo-private -y
```

**Creating remote repositories always has to be asked for explicitly**, even with `-y`.
If your repositories live under an organisation, say so once:

```yaml
github:
  owner: fidenceio
```

The preview names every repository it would create as `<owner>/<name>`, so you can read
the list before anything exists. Where does the owner come from if you do not set
`github.owner`?

- From the repository's own `origin` remote, if it has one.
- Only a directory with no `origin` of its own shows `<authenticated-user>`, meaning
  `gh` would create it under whichever account you are logged in as.
- A directory nested inside a parent repository does **not** inherit that parent's owner.

If you set `github.owner` and it disagrees with an existing `origin`, your configured
value wins and Manifest reports the conflict. Run interactively and it offers the origin
owner instead; run unattended and it never blocks. Members that already have an origin
keep it. A directory with no `.git` of its own is set up from what is actually on disk,
even if a leftover row in the TSV still claims `HAS_GIT=true`.

### Adopt An Existing Workspace

```bash
manifest plan fleet
manifest plan fleet --apply
manifest reconcile fleet
manifest reconcile fleet --do
```

The flags stack, so you cannot skip a step by accident: `--commit` requires `--apply` or
`--do`, and `--push` requires `--commit`.

### Operate A Fleet

```bash
manifest status fleet
manifest prep fleet
manifest update fleet          # re-scan which repos are members (once called 'refresh fleet'; for docs use 'manifest docs fleet')
manifest ship fleet patch
manifest ship fleet patch -y
manifest ship fleet patch --local -y
```

Members with releases turned off are listed and skipped. Members with releases turned
**on** are also skipped when there is nothing to release — meaning a clean working copy
whose latest commit is already the one the current `VERSION` tag points at.

### Project Repo Names Onto GitHub Topics

If your repository names follow a dotted convention, Manifest can mirror that structure
as GitHub **topics** — the tags shown on a repository page — which makes an organisation
page filterable with a query like `?q=topic:accounting`. Opt in with one key in
`manifest.fleet.config.yaml`:

```yaml
topics:
  from_name: inner   # fidence.service.accounting.avalara -> service, accounting
```

The modes are `inner` (drop the first and last piece), `all-but-first`, and `all`. Every
member also gets a `fleet-<name>` topic. `manifest update fleet` shows the per-repository
changes; `-y` applies them.

**Topic changes only ever add.** Manifest reads each repository's existing topics first,
never re-pushes one that is already there, and never removes anything — a repository can
belong to two fleets, and removing a "stale" topic on one fleet's run would fight the
other. Deleting the config key stops topic management but does not undo past changes. If
`gh` is missing or you are not logged in, the step is skipped with a notice.

The same run also reports a roster check: repositories in your organisation that share a
naming family with a member (the same first dotted piece) but are not in your local
fleet — usually new ones nobody has cloned yet. This is read-only. To enrol one, clone it
into the fleet root and run `manifest update fleet` again.

## Pull Request Workflow

These wrap the `gh` command-line tool and need no Manifest Cloud:

```bash
manifest pr
manifest pr create --draft
manifest pr checks --watch
manifest pr ready
manifest pr update
manifest pr merge --squash
```

These need Cloud:

```bash
manifest pr queue
manifest pr policy show
manifest pr policy validate
```

Without Cloud plugins, the Cloud-only commands print installation guidance. Everything
above them keeps working.

## Configuration

This section is the authoritative description of how Manifest's configuration layers
work. Other documents point here rather than repeating it.

### Layer model

A setting's value is worked out from six layers. **Lower in this table wins.**

| # | Layer | Where it lives | When it applies | Can you write it? |
| - | ----- | ------ | ------- | -------- |
| 1 | `defaults` | Built into the CLI | Always | No |
| 2 | `global` | `~/.manifest-cli/manifest.config.global.yaml` | Always | Yes, behind a safety gate |
| 3 | `fleet` | The fleet root's `manifest.config.yaml`, then its `manifest.config.local.yaml` | Only when this repo sits **below** a fleet root; skipped when it **is** the root | No — write it at the fleet root |
| 4 | `project` | `./manifest.config.yaml` | Always | Yes |
| 5 | `local` | `./manifest.config.local.yaml` | Always (and git-ignored) | Yes, the default target |
| 6 | `env` | Exported `MANIFEST_CLI_*` variables, read when the process starts | Always | n/a |

### The fleet layer

A repository inside a fleet inherits the fleet root's settings as a starting point, so
one setting at the root applies to every member without being copied into each one.
Three things about this catch people out:

- **`manifest.fleet.config.yaml` is not one of the layers.** It defines the fleet, and
  its presence is what marks a directory as the fleet root. The two files that form the
  `fleet` layer are the root's ordinary `manifest.config.yaml` and
  `manifest.config.local.yaml`.
- **At the fleet root itself, inheritance is skipped.** There, those same two files are
  already layers 4 and 5; counting them twice would mean nothing.
- **The fleet root is found by walking up the directory tree** looking for
  `manifest.fleet.config.yaml`. Pointing a setting at some other fleet root does not
  change this — the config layer follows that file and nothing else.

### Inspecting layers

`manifest config describe <key>` shows every layer, strongest first, and names the file
each value came from:

```text
Key:       github.owner
Env var:   MANIFEST_CLI_GITHUB_OWNER
Fleet:     /work/acme
Effective: acme-corp  (from fleet)

Layers (highest precedence first):
  env      ·   (MANIFEST_CLI_GITHUB_OWNER — not exported at process start)
  local    ·   (/work/acme/services/api/manifest.config.local.yaml — not present)
  project  ·   (/work/acme/services/api/manifest.config.yaml — not present)
  fleet    acme-corp   (/work/acme/manifest.config.local.yaml)
  fleet    ·   (/work/acme/manifest.config.yaml — not present)
  global   ·   (~/.manifest-cli/manifest.config.global.yaml — not present)
  defaults ·   (built-in)
```

Values that lost still appear, so you can see exactly what is overriding what.
`manifest config list` shows every key that has been set somewhere along with the layer
that won; `--layer <name>` narrows it to one layer, `fleet` included.

### Writing configuration

```bash
manifest config show
manifest config list
manifest config list --layer fleet
manifest config get git.tag_prefix
manifest config describe git.tag_prefix
manifest config set git.tag_prefix release-
manifest config unset git.tag_prefix
manifest config doctor
manifest config doctor --fix
```

`config set` writes to your local config unless told otherwise. Writing the global
config passes through an extra safety gate.

On `set` and `unset`, `--layer` accepts only `global`, `project`, and `local`. The
`fleet` layer is deliberately read-only from inside a member, because its files live in
a **different repository** — writing them from here would change a repo you never named.
To change a fleet-wide value, run the same command **at the fleet root**, where those
files are just the ordinary `project` and `local` layers:

```bash
cd /path/to/fleet-root
manifest config set --layer project github.owner acme-corp
```

### Environment overrides

Every setting has a matching `MANIFEST_CLI_*` environment variable, and an exported
variable beats every config file.

Two things about this layer surprise people:

- **It is a snapshot taken when the process starts.** Exporting a variable halfway
  through a session does not create an override for a command already running.
- **Exporting it *empty* is not the same as not setting it.** An empty value still
  suppresses all the file layers, so the built-in default takes over. `config describe`
  calls this case out explicitly rather than leaving you to guess.

## Documentation Generation

```bash
manifest docs
manifest docs metadata
manifest docs cleanup
manifest docs fleet --dry-run
```

Manifest can also build a small documentation website for GitHub Pages. That is
**off by default** — turn it on with `docs.generate.site: true`. See
[DOCS_SITE.md](DOCS_SITE.md).

## Testing Manifest

Contributor checks run in a container, so you do not install test dependencies on your
own machine:

```bash
./scripts/run-tests-container.sh
./scripts/run-tests-container.sh tests/docs_generation.bats
```

## Security And Maintenance

```bash
manifest security          # read-only checks; writes nothing
manifest security --write  # also save a timestamped report to the docs archive
manifest upgrade
manifest uninstall         # shows what it would remove
manifest uninstall -y
```

`manifest security` checks three things: whether files meant to stay private are tracked
in git, whether anything looks like personal data, and whether environment-variable names
follow the expected pattern. It is read-only unless you pass `--write`, and it never
touches the hand-written `docs/SECURITY_ANALYSIS_REPORT.md`. (`--check` is still accepted
and also means read-only, so existing hooks and scripts keep working.)

The pre-commit hook — which is versioned in the repository but must be enabled per clone
— is documented in [../.git-hooks/README.md](../.git-hooks/README.md).
