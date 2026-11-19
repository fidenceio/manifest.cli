# Manifest CLI User Guide

Manifest splits release work into three stages. You run each one when you want it:

```text
config -> init -> ship
```

- `config` sets your preferences.
- `init` prepares a repository, or a group of repositories, for releasing.
- `ship` makes the release.

Two ideas appear throughout this guide:

- **Preview and apply.** Every command that would change something shows you a plan and
  then stops. Add `-y` (or `--yes`) to carry the plan out. See
  [Preview And Apply](#preview-and-apply).
- **The release gate.** This is the check that must pass before Manifest releases. By
  default it is your project's own tests. The [Migration Guide](MIGRATION.md) lists its
  settings.

## Core Concepts

### Repo Scope

A repository, or "repo", is a project folder whose history Git tracks. "Repo scope"
means the command acts on one repository: the one you are standing in.

```bash
manifest status repo
manifest ship repo patch
manifest ship repo patch -y
```

Manifest finds that repository by looking upward from your current directory for a
`.git` folder. You cannot give it a path instead. Release commands always act on where
you are, so a mistyped path can never release the wrong project.

### Fleet Scope

A **fleet** is a group of separate Git repositories that you manage together. Two files
define it:

- `manifest.fleet.config.yaml` holds the fleet's settings. The folder that contains it
  is the **fleet root**.
- `manifest.fleet.tsv` lists the member repositories and marks which ones are selected.

```bash
manifest status fleet
manifest ship fleet patch
manifest ship fleet patch -y
```

Before a fleet command changes anything, it prints five things: where the fleet root
is, which config file it read, which members are selected, what it decided to do with
each member, and which branch each member is on.

### Preview And Apply

| What you type | What happens |
| ---- | ------- |
| no `-y` | Shows the plan only |
| `--dry-run` | The same, stated explicitly |
| `-y` / `--yes` | Does the work |
| `--local -y` | Does only the parts that stay on your machine. Nothing goes to GitHub |

`-y` does not then stop to ask "are you sure?". Asking for an apply *is* the
confirmation. `--dry-run` and `-y` cannot be used together.

There is a separate environment variable, `MANIFEST_CLI_AUTO_CONFIRM=1`. It is not a
way to apply. It cannot start an apply, and a normal apply does not need it. It has two
narrow jobs:

- **It lets an apply continue when the target is ambiguous.** A target is ambiguous
  when the checkout is in "detached HEAD" (it is not on any branch), or when the
  repository has no `origin` remote (no address to push to). Without the variable,
  Manifest refuses such an apply even with `-y`. Manifest accepts the variable for this
  job only from the environment the command started in. A config file cannot grant it.
- **It lets Manifest proceed without pausing for a confirmation question.** Manifest
  asks a few of these outside a release, such as the one before it writes your global
  config file.

This split matters in CI (an automated build pipeline). There, an environment variable
must never be able to publish a release by itself.

## First-Time Setup

Start with `manifest init`. It looks at where you are: one repository, a folder of
repositories, or a project that is already set up. Then it proposes a setup. It writes
nothing until you apply.

```bash
manifest init
manifest init -y
```

Manifest records an applied setup in its audit log. Guided setup runs the commands
below for you. You can also run them yourself:

```bash
manifest doctor
manifest config show
manifest init repo
manifest init repo -y
```

When you apply it, `manifest init repo` does four things:

1. It sets up Git in the folder, if the folder is not a repository yet.
2. It connects the `origin` remote. If the repository has no `origin`, Manifest creates
   a **private** GitHub repository for it by default. Use `--remote URL` to connect an
   existing remote instead, or `--create-repo-public` to create a public repository. An
   empty remote needs no pull.
3. It creates the project files listed in the table below.
4. It runs the release check (the release gate).

Init never makes a release. It makes no commit, no version bump, no tag and no push.

If the release check fails, or Git has no author name and email set, init reports the
setup as incomplete.

A release check that Manifest generates runs in a container, so it needs Docker. For an
empty project, the check verifies the starter files themselves. Once you add
application files, the check fails until you add real project checks to it.

`--no-connect` creates the local files only. It makes no network call and does not
verify that the repository is ready to release.

`manifest init repo` creates the files a Manifest-managed project needs. It writes each
file only if the file is absent. An existing file is always preserved, even with
`--force`.

| File | What it is for |
| --- | --- |
| `VERSION` | The version that Manifest reads, and raises on each release. |
| `README.md` | The project's entry point. A release maintains a version block inside it. |
| `CHANGELOG.md` | The release history. Every release adds an entry. |
| `.gitignore` | Ignore rules, **chosen for your project's ecosystem**. See below. |
| `docs/` | The folder that Manifest generates documentation into. |
| `scripts/run-tests.sh` | The release gate. `manifest ship` runs it and refuses to release if it fails. Its checks run in a container against a read-only copy of the checkout, so nothing is written to your machine unless you set `release.gate_host_writes: true`. |
| `.env.example` | A template that lists your environment variables. Git can track it, while real `.env` files are ignored. |
| `robots.txt` | Crawl privacy: tells search and AI crawlers to stay out, by default. |
| `ai.txt` | Crawl privacy: declares no crawling, training, or indexing. |
| `manifest.config.local.yaml` | Settings for this repository. Git ignores it, and it is the only file that `--force` recreates. |

`manifest init repo --dry-run` prints this same list for your repository. It marks each
file as *would create* or *exists (preserved)*, and says what each file is for.

**Why `robots.txt` and `ai.txt`.** Manifest treats anything that might be served over
HTTP as private by default. A repository that is deployed from its root therefore
starts out refusing search indexing and AI training. If your repository is a library or
a command-line tool that is never served, the two files do nothing, and you can delete
them. A later `manifest init` will offer to create them again.

**The `.gitignore` is written for your stack, not for every stack.** Manifest looks for
marker files at the root of your repository, such as `go.mod`, `package.json`,
`Cargo.toml`, `pyproject.toml`, `pom.xml`, `build.gradle`, `Gemfile`, `*.tf` and
`Dockerfile`. It also looks for `*.sln` and `*.csproj`. Those two are the only markers
it searches for a few directories deep, because .NET project files usually sit under
`src/`.

Manifest then writes two groups of rules:

- A universal group that every repository gets: operating-system and editor clutter,
  AI-agent workspaces, env files, and a `KEY MATERIAL` block that ignores key files by
  default.
- The rules for each ecosystem it found. A Go repository does not receive
  `node_modules/` or `__pycache__/`.

When Manifest recognises no marker, it writes the rules for nearly every ecosystem.
For an unknown stack, more advice is the safe direction. **Two kinds of rule are held
back from that fallback**, because a plain directory name can match a folder you want
to keep:

- Rules that only make sense for a known stack (`TestResults/`, `*.user`) are written
  only when that stack is found.
- .NET's `bin/` and `obj/` are always tied to the directory that holds each project
  file. Manifest writes `/src/bin/`, never a bare `bin/`.

So a repository of shell scripts that keeps them in a committed `bin/` folder is never
told to ignore that folder, even if a stray `.csproj` file makes the repository match
.NET.

## Repository Release Workflow

Look first:

```bash
manifest status
manifest doctor
```

Get the repository ready:

```bash
manifest init repo
manifest init repo -y
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

Do only the local half, and leave nothing public:

```bash
manifest ship repo minor --local -y
```

A release works through these main steps, in order:

1. Run the release gate (by default, your project's tests). If it fails, the release
   stops and nothing has changed.
2. Commit whatever you had uncommitted (see the next section).
3. Bring in the latest changes from the remote.
4. Raise `VERSION`, add a `CHANGELOG.md` entry, and regenerate the docs.
5. Commit those release files.
6. Create a tag (a named marker on that commit) and push the branch and the tag.
7. Publish a GitHub Release.
8. In Manifest's own repository only, publish the Homebrew formula. This goes to the
   Homebrew tap and adds no commit to the Manifest repository.

`--local -y` stops after step 5. The
[CLI Transaction Map](CLI_TRANSACTION_MAP.md) describes every step in detail.

Before Manifest reports success, it checks two things. The working copy must be clean,
apart from files the release already told you it left out. And nothing may have been
committed on top of the release it just pushed.

If the working copy is clean and the latest commit already carries the tag for the
current `VERSION`, there is nothing to release. `ship repo` says so and stops. Add
`--force-bump` to cut a release anyway.

### What the automatic commit includes, and what it leaves out

Once the release gate has passed, a release commits whatever you had uncommitted. It
does this before it changes any file itself. Two rules shape that commit, and both are
easy to misread.

**Nested repositories are left alone.** Suppose a folder inside your project has its
own `.git`, and it is not a declared submodule (a nested repository that Git has been
told about in `.gitmodules`). Git would record that folder as a bare "gitlink": a
pointer to a commit in a repository that nobody else can find. Manifest unstages such a
folder, tells you, and lists your options. Declared submodules are not touched. A
gitlink that is already recorded in your history is also left as it is; Manifest prints
a notice if this commit moves it. If you really do want bare gitlinks committed, set
`git.allow_new_gitlinks: true` (`MANIFEST_CLI_GIT_ALLOW_NEW_GITLINKS`).

**Work that appeared after you asked to release is held back.** Manifest notes which
files were pending before it runs the release gate. A full gate takes minutes. That is
long enough for another session, an editor autosave, or a background generator to drop
new files into the folder. Manifest unstages those files and lists them.

Those files are kept out of **the automatic commit**. Later in the same run, the
release commit stages only what the release itself writes:

- `VERSION`, and the files you listed in `version.sync`
- `CHANGELOG.md`
- the README
- the docs folder and its archive
- the docs-site source folder and its Pages workflow
- the folder named by `docs.review.report_dir`, if you set one

What happens to a file that appeared mid-run depends on where it is:

- **Outside those places:** it stays in your working copy, uncommitted. The release
  names it a second time: *"Left out N files this release did not write"*.
- **Inside those places** (a new doc, for example): the release commit includes it,
  because Manifest cannot tell it apart from its own output. `git show --stat HEAD` is
  the record of what was released.

To turn both guards off and commit everything, set `git.allow_gate_drift: true`
(`MANIFEST_CLI_GIT_ALLOW_GATE_DRIFT`). Manifest's own records under `.manifest-cli/`
are always exempt, because the gate writes its results there while it runs.

### Letting whoever is driving finish the documentation

Manifest writes a `CHANGELOG.md` entry from your commit subjects. That is an honest
summary of *what was committed*. It is rarely a good summary of *what changed for a
reader*. The `docs.handoff` setting lets the driver write the real entry before the
release commit is made, and then checks the result. The driver is whoever is running
the command: a person, or an AI agent working in your terminal.

```yaml
# manifest.config.yaml — safe to commit: it names no program to run
docs:
  handoff: "auto"     # off (default) | auto | always
```

- **`off`** is the default and changes nothing.
- **`auto`** pauses when Manifest detects an AI coding agent driving the session. It
  never pauses in CI, even when an agent is running there. A pipeline that stops to
  wait for someone is broken, not careful.
- **`always`** pauses on every apply, whoever is driving. Use this setting if you want
  the checkpoint for yourself.

A fleet release never pauses its members, whatever the setting says.

When the release pauses, it exits with code `4`. This is not a failure. No release
commit, tag or push has been made. Three things are waiting for you:

- `VERSION` holds the new version, uncommitted.
- `CHANGELOG.md` holds a skeleton entry, uncommitted.
- A brief is saved under `.git/`, and its path is printed.

The brief contains the release facts, the real commit subjects, the changed files, and
the exact heading to keep. It also lists every tracked markdown line that still names
the previous version or holds a `vNEXT`-style placeholder. Edit the documentation, then
run the identical command again.

The second run **does not regenerate `CHANGELOG.md`**. Your text is what gets
committed. Manifest still regenerates everything else it owns, including the managed
version blocks in `README.md` and `docs/INDEX.md`, so leave those alone. Before it
commits anything, it verifies five rules:

| Rule | What it checks |
| ---- | -------------- |
| R1 | The `## [X.Y.Z] - <date>` heading is present exactly once, with the release date recorded when the handoff was written |
| R2 | That section has at least one bullet |
| R3 | No version placeholder is left in tracked markdown |
| R4 | The section contains no assistant boilerplate ("As an AI", "Sure, here", …) |
| R5 | That section is not byte-identical to the skeleton Manifest wrote at the pause. In other words, someone has edited it |

If a rule fails, the release stops again with code `4`, names every rule that failed,
and commits nothing. Fix the problem and run the command again.

**R5 is the rule that gives the other four their meaning.** Manifest's own skeleton has
the right heading, has bullets, carries no placeholder and contains no boilerplate.
Without R5, a driver who did nothing at all could run the command again and be told
that the handoff was verified.

Be equally clear about the limit. These rules show that the release notes were
*written*. They do not show that the notes are *true*. No check of structure can show
that, and these rules do not claim to.

**Manifest never runs a program for this.** Detection decides one thing only: whether
`auto` pauses. It is not a safety control, and it cannot choose a program to run. That
is why `docs.handoff` is safe to commit and `docs.review.command` is not.

You may prefer to hand the work to a *headless* agent, one that runs unattended with no
one at the terminal. That is the release-notes provider. You configure it yourself, in
a layer you own. See `examples/release-notes-providers/`.

### Documentation review and release-notes providers

These are two related hooks. Both are off unless you turn them on. You can configure
them **only** from a layer you own: your global config, a `*.local.yaml` file, or the
environment. If a committed `manifest.config.yaml` names either one, Manifest refuses
it and prints the key and the layer it came from. A committed config travels with every
copy of the repository, so it must not choose a program to run on your machine.

| Key | What it does |
| --- | ------------ |
| `docs.review.provider` / `docs.review.command` | Runs your program before each release commit and writes a report. The program can supply the commit subject and body |
| `docs.release_notes.provider` / `docs.release_notes.command` | Runs your program to write the release-note bullets, in place of Manifest's generated list |

Manifest calls both with plain arguments and validates their output before it uses it.
See `examples/release-notes-providers/example-provider.sh` for the contract.

## Version Ownership

Manifest writes exactly one version file: `VERSION`.

`VERSION` holds numbers separated by dots. There can be any number of them, not just
three. One place explains which number each release type changes, what the positions
are called (`version.components`), and why a fourth number does not survive a `patch`:
[Command Reference — Version increments](COMMAND_REFERENCE.md#version-increments).

Every other file that mentions a version is **non-canonical**: Manifest reads it but
does not write it. That covers `package.json`, `package-lock.json`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, `Chart.yaml`, and similar files. Manifest finds them with a
catalog that ships with the tool. Finding is all it does. It does not edit them, does
not fill your scripts with warnings, and does not stop an unattended run.

To keep some of them in step with `VERSION`, list them:

```yaml
version:
  sync: "package.json,pyproject.toml,Chart.yaml"
```

`version.sync` is unset by default. Unset means that Manifest never touches package
files or lockfiles. When you set it, Manifest updates a `version` field at the **top
level** of a JSON, TOML, or YAML file. It skips three cases: a file that does not
exist, a file whose version is nested deeper, and a format it does not handle. It never
creates a file.

You can choose how much Manifest tells you about the files it found:

```yaml
version:
  surfaces:
    enabled: true
    catalog: ""          # empty means use the built-in catalog
    scan_depth: 5
    notification_mode: summary # summary | list | off
```

- `manifest status` and fleet status say nothing when `VERSION` is the only version
  file. They give a one-line summary when other version files exist. They name each
  file when `notification_mode` is `list`.
- `manifest status --json` always includes the complete `version_surfaces` object.
- `manifest doctor` reports invalid settings and found files as warnings only, never as
  errors.

**One limitation.** A setting named `files.version` exists for naming a different
canonical file, and detection honours it. But four things read or write `VERSION`
regardless: a repo release, the main version field in `status`, the finishing of an
unfinished release, and a fleet release. Treat `files.version` as incomplete, and keep
your version in `VERSION`.

## Fleet Workflow

### Initialize A Fleet

```bash
manifest init fleet
```

The first run scans the folder and writes `manifest.fleet.tsv` for you to review. Edit
that file, in particular to choose which members are selected. Then run the command
again. The second run creates the fleet config and sets up the repositories.

Useful variants:

```bash
manifest init fleet --depth 3
manifest init fleet --all-folders
manifest init fleet --name platform-services
manifest init fleet --create-repo-private   # show local setup plus the GitHub repos it would create
manifest init fleet --create-repo-private -y
```

**Fleet setup creates GitHub repositories only when you ask for them**, with
`--create-repo-private` or `--create-repo-public`. `-y` alone never creates one. If
your repositories live under an organisation, say so once:

```yaml
github:
  owner: fidenceio
```

The preview names every repository it would create as `<owner>/<name>`, so you can read
the list before anything exists. If you do not set `github.owner`, Manifest works out
the owner like this:

- A repository that has its own `origin` remote uses that remote's owner.
- A directory with no `origin` of its own shows `<authenticated-user>`. That means `gh`
  (the GitHub command-line tool) would create it under the account you are logged in
  as.
- A directory nested inside a parent repository does **not** inherit the parent's
  owner.

If you set `github.owner` and it disagrees with an existing `origin`, your configured
value wins and Manifest reports the conflict. In a terminal, it offers to use the
origin's owner instead. In an unattended run, it never stops to ask. Members that
already have an origin keep it.

A directory with no `.git` of its own is set up from what is actually on disk. That
holds even if a leftover row in the TSV file still says `HAS_GIT=true`.

### What the coordination root carries

The fleet root is a Git repository of its own. It tracks Manifest's coordination files
and nothing else. It never tracks member repositories, their source code, or secrets.
It does this with an **allowlist** `.gitignore`: ignore everything, then re-include
only the files that are declared.

Five files are always included:

- `.gitignore`
- `manifest.fleet.config.yaml`
- `manifest.fleet.tsv`
- the fleet version file
- `CHANGELOG_FLEET.md`

A fleet release adds one more, `manifest.fleet.snapshot.json`. It records which commit
each member was at, and `manifest revert fleet` uses it.

Your fleet may coordinate on something else as well, such as a host and port map, a
runbook, or a shared inventory. Declare those files:

```yaml
# manifest.fleet.config.yaml
fleet:
  name: "my-fleet"
  coordination_files:
    - host-ports.yaml
    - runbook.md
```

A declared name is re-included in the root's `.gitignore`. It is also staged by
`manifest ship fleet manager` and by the coordination commit of a fleet release.
Editing the `.gitignore` by hand is not enough. Manifest stages files by name, so it
does not commit a file it has not been told about, even when Git would allow it.

Each entry must be a plain file name at the root. Manifest refuses:

- paths, wildcard patterns, and `..`
- `.git`
- the two config files Manifest reads at a root: `manifest.config.yaml` and
  `manifest.config.local.yaml`. The first is the fleet-wide layer that every member
  inherits. The second is meant to stay untracked.

Refused entries are named on the error output and ignored. The other entries still
apply.

Two more refusals are worth knowing about before you meet them:

- **A directory is refused**, even though its name looks valid. When Git re-includes a
  directory, it re-includes everything under it. A line such as `!/docs` would let you
  stage every file under `docs/` at the root. Manifest itself would not commit those
  files. But the first one you staged yourself would make every later coordination
  commit refuse to run, and the root would stop releasing.
- **Names that look like secrets are refused outright.** That covers `.env` and
  `.env.*`, `*.local.{yaml,yml,json,toml}`, and key files (`*.pem`, `*.key`, `*.p12`,
  `id_ed25519`, …). This setting exists to widen what the root commits and **pushes**,
  and no local action can take back a pushed credential. `.env.example` and
  `.env.template` are the two exceptions, because they exist to be committed.

A refusal costs you only a rename. If you really need a file whose name matches one of
these patterns, give it a name that does not match.

### Adopt An Existing Workspace

Use these commands to turn an existing folder of repositories into a fleet, or to
repair one:

```bash
manifest plan fleet           # preview the adoption plan
manifest plan fleet -y        # write the plan to manifest.fleet.plan.yaml
manifest reconcile fleet      # preview the changes that plan describes
manifest reconcile fleet -y   # make those changes locally
```

`reconcile fleet` has two more flags, and each one requires the one before it.
`--commit` requires `-y` / `--yes`, and `--push` requires `--commit`. You cannot skip a
step by accident.

### Operate A Fleet

```bash
manifest status fleet
manifest init fleet --connect
manifest update fleet          # re-scan which repos are members; for docs use 'manifest docs fleet'
manifest ship fleet patch
manifest ship fleet patch -y
manifest ship fleet patch --local -y
manifest ship fleet manager            # preview: what would be committed and pushed at the fleet root
manifest ship fleet manager -y         # commit + push the coordination root only
```

A fleet release skips two kinds of member, and lists them:

- Members with releases turned off.
- Members with releases turned **on** that have nothing to release. That means a clean
  working copy whose latest commit is already the one the current `VERSION` tag points
  at.

#### The coordination root on its own: `ship fleet manager`

The fleet root is a small Git repository of its own, also called the **manager**. It
carries only the coordination files described in
[What the coordination root carries](#what-the-coordination-root-carries). Its
`.gitignore` ignores everything and re-includes only those names, so member
repositories, source code and secrets can never be tracked there.

`manifest ship fleet <type>` releases the members first and then commits and pushes
this manager root. It also commits and pushes manager changes when every member is
skipped, and when `fleet.versioning` is `none`. If the manager commit or push fails,
the whole fleet release fails. Member releases that already completed stay in place.

Use `manifest ship fleet manager` to publish coordination changes on their own, or to
retry the manager after you fix a hook or a remote. It behaves the same way as the
manager step of a normal fleet release:

- It **stages files by allowlist name**. If a file outside the allowlist is already
  staged, it refuses before it makes any commit.
- It does **not** treat the root as a product. There is no `VERSION` bump, no tag, no
  GitHub Release, and no Homebrew update.
- When `fleet.versioning` is not `none`, it stamps the fleet version file along with
  the commit. A release-type word (`patch`, `minor`, …) makes it stamp even when
  nothing else changed. Only the `semver` scheme reads that word.
- `--local -y` commits without pushing. If there is nothing to commit or push, it says
  so and writes nothing.

#### Renaming the fleet version file

`fleet.version_file` sets which file at the root carries the fleet version. The default
is `FLEET_VERSION`. The name appears in two places that must agree. Manifest reads the
config key to know which file to load and stage. The allowlist `.gitignore` re-includes
the name, so that Git can see the file past its ignore-everything rule (`/*`).

**If you change the key on a fleet that is already set up, the next fleet command
updates the `.gitignore` for you:**

```text
⚠️  Fleet root .gitignore did not re-include 'FLEET.stamp' (fleet.version_file);
    added it and kept every existing rule. Commit it with the coordination files.
```

Commit that `.gitignore` along with the other coordination files. It is one of them.

**The update only ever adds.** Every `!/` line already in the file is kept. That
includes a line you added yourself and the re-include for a previous version file.
Manifest cannot tell those two apart, because nothing in the file records who wrote a
line. So it keeps both and does not guess. A re-include for a file that does not exist
does nothing in Git. Dropping a rule of yours would do harm.

So after a rename you may see the old name still listed. That is deliberate. You can
delete the line yourself if you want the file tidy.

**If you have edited the surrounding block, Manifest does not rewrite the file at
all.** The surrounding block means the header comments, the `/*` rule, or any line that
does not start with `!/`. Regenerating the file would discard those edits. What
Manifest says then depends on whether anything is actually wrong.

If the version file is still re-included correctly, it tells you so and asks nothing of
you:

```text
⚠️  Fleet root .gitignore has local edits to the managed block, so it was left
    alone. Its re-include for 'FLEET.stamp' is present and correct; no action
    needed unless you want Manifest to manage this file again.
```

If the re-include really is missing, it names the exact line to add:

```text
⚠️  Fleet root .gitignore does not re-include 'FLEET.stamp' (fleet.version_file)
    and has local edits, so it was left alone. Add the line '!/FLEET.stamp' to
    keep that file visible to git.
```

Add that one line by hand and commit it. Do **not** delete the file to make Manifest
regenerate it. Regenerating produces the standard allowlist and discards whatever you
added.

Here is the symptom if the line is missing. The `/*` rule ignores the version file, so
your own `git add .` does not pick it up. The release itself is not affected, because
Manifest force-adds coordination files by name. So you see a file that will not stage,
not a failed release. To check a root by hand:

```bash
name=$(grep -E '^[[:space:]]*version_file:' manifest.fleet.config.yaml 2>/dev/null \
       | sed -E 's/.*version_file:[[:space:]]*"?([^"]*)"?.*/\1/')
git check-ignore -q "${name:-FLEET_VERSION}"; echo "exit=$? (want 1)"
```

The `${name:-FLEET_VERSION}` default matters. On a fleet that never set the key, which
is the common case, the `grep` matches nothing. Without the default,
`git check-ignore` would fail with *"empty string is not a valid pathspec"* and would
not answer the question.

The name must be a plain file name. Manifest refuses a path or a wildcard pattern, says
so plainly, and uses the default. (A `*` in the allowlist would un-ignore every entry
at the root, member directories included.)

Some well-formed names are refused too. Manifest writes the version file with `mv -f`,
which would destroy whatever file already had that name:

| Refused | Why |
| --- | --- |
| `.`, `..` | A directory reference, not a file name |
| `.git`, `.gitmodules`, `.gitattributes` | Git metadata. Where `.git` is a *file* (in a linked worktree or a submodule), it would be overwritten and the root cut off from its repository |
| `manifest.fleet.tsv`, `manifest.fleet.config.yaml`, `.gitignore`, `CHANGELOG_FLEET.md` | A coordination file. The TSV file is the fleet's record of its members, and the config file is the one that named the version file |
| `manifest.config.yaml`, `manifest.config.local.yaml` | A config layer that Manifest reads at the root |
| Names that look like secrets, and the name of a directory at the root | The same rules as for `fleet.coordination_files`, described in [What the coordination root carries](#what-the-coordination-root-carries) |

The check ignores letter case, because macOS treats `.GIT` and `.git` as the same name.

### Project Repo Names Onto GitHub Topics

If your repository names follow a dotted convention, Manifest can copy that structure
onto GitHub **topics**. Topics are the tags shown on a repository's page. With them,
you can filter an organisation's page with a query such as `?q=topic:accounting`. Turn
the feature on with one key in `manifest.fleet.config.yaml`:

```yaml
topics:
  from_name: inner   # fidence.service.accounting.avalara -> service, accounting
```

The modes are `inner` (drop the first and last piece), `all-but-first`, and `all`. When
the fleet has a name, every member also gets a `fleet-<name>` topic.

`manifest topics fleet` shows the changes for each repository, and `-y` applies them.
`manifest update fleet` runs the same step after it re-scans the members. A fleet
release that is not `--local` also applies them, once it has released at least one
member.

**Topic changes only ever add.** Manifest reads each repository's existing topics
first. It never pushes a topic that is already there, and it never removes one. A
repository can belong to two fleets, and removing a "stale" topic during one fleet's
run would undo the other fleet's work. Deleting the config key stops topic management.
It does not undo past changes. If `gh` is missing, or you are not logged in, Manifest
skips the step and says so.

The same run also reports a roster check. It lists repositories in your organisation
that share a naming family with a member (the same first dotted piece) but are not in
your local fleet. These are usually new repositories that nobody has cloned yet. The
check only reads. To enrol one, clone it into the fleet root and run
`manifest update fleet` again.

## Pull Request Workflow

These commands wrap `gh`, the GitHub command-line tool. They do not need Manifest
Cloud. The ones that change something preview first, like every other command:

```bash
manifest pr                    # show this branch's pull request, or offer to open one
manifest pr create --draft     # preview; add -y to open the draft
manifest pr checks --watch     # watch the CI checks (read-only)
manifest pr ready              # preview; add -y to mark the draft ready for review
manifest pr update             # preview; add -y to update the branch from its base
manifest pr merge --squash     # preview; add -y to merge
```

These commands need Manifest Cloud:

```bash
manifest pr queue
manifest pr policy show
manifest pr policy validate
```

Without the Cloud plugins, the Cloud-only commands print installation guidance.
Everything above them keeps working.

## Configuration

This section is the authoritative description of how Manifest's configuration layers
work. Other documents point here and do not repeat it.

### Layer model

Manifest works out the value of a setting from six layers. **A layer lower in this
table wins over the layers above it.**

| # | Layer | Where it lives | When it applies | Can you write it? |
| - | ----- | ------ | ------- | -------- |
| 1 | `defaults` | Built into the CLI | Always | No |
| 2 | `global` | `~/.manifest-cli/manifest.config.global.yaml` | Always | Yes, behind a safety gate |
| 3 | `fleet` | The fleet root's `manifest.config.yaml`, then its `manifest.config.local.yaml` | Only when this repo sits **below** a fleet root; skipped when it **is** the root | No. Write it at the fleet root |
| 4 | `project` | `./manifest.config.yaml` | Always | Yes |
| 5 | `local` | `./manifest.config.local.yaml` | Always (and Git ignores it) | Yes, the default target |
| 6 | `env` | Exported `MANIFEST_CLI_*` variables, read when the process starts | Always | n/a |

**Five keys are the one exception to "lower wins", and the exception is deliberate.**
Each of these keys names a program that Manifest runs during a release:

- `release.gate_command`
- `docs.review.command`
- `docs.release_notes.command`
- `docs.review.provider`
- `docs.release_notes.provider`

Manifest accepts them from layers **you** own: `global`, either `*.local.yaml` file,
and `env`. It **refuses them from layers 3 and 4**, the committed
`manifest.config.yaml` at a fleet root or in a project. Those files travel with every
copy of the repository. Without this rule, a repository you had just cloned could
choose what runs on your machine when you release it. And because layer 4 overrides
layer 2, a safe setting in your own global config would not protect you.

Manifest always prints the refusal. It names the key and the layer the key came from.
You have three ways to use one of these keys:

- **Move it** to `manifest.config.local.yaml`.
- **Trust the repository for one run**, without editing anything: set
  `MANIFEST_CLI_TRUST_REPO_COMMANDS=1` in the environment.
- **Trust it and have that remembered**: set the variable to `remember`.

A remembered decision is recorded in `~/.manifest-cli/trusted-repo-commands.tsv`. The
record is tied to two things: the repository's remote, and a digest (a fingerprint) of
the exact values you accepted. So:

- A fresh clone of the same remote is still trusted.
- A changed value is refused again until you review it.
- Setting the variable to `forget` removes the record.

The preview shows, beside each committed program, whether it is trusted for this run or
by your record.

Trust is an environment variable on purpose. A committed file must not be able to grant
itself trust. So there is no config key for trust, and none for where the record lives.
See the
[Migration Guide](MIGRATION.md#a-committed-config-can-no-longer-name-a-program-to-run)
for what to change in an existing setup, and [SECURITY.md](../SECURITY.md) for the full
boundary.

### The fleet layer

A repository inside a fleet inherits the fleet root's settings as a starting point. One
setting at the root then applies to every member, with no need to copy it into each
one. Three facts about this often surprise people:

- **`manifest.fleet.config.yaml` is not one of the layers.** It defines the fleet, and
  its presence is what marks a directory as the fleet root. The two files that form the
  `fleet` layer are the root's ordinary `manifest.config.yaml` and
  `manifest.config.local.yaml`.
- **At the fleet root itself, inheritance is skipped.** There, those same two files are
  already layers 4 and 5. Counting them twice would change nothing.
- **Manifest finds the fleet root by walking up the directory tree**, looking for
  `manifest.fleet.config.yaml`. Pointing a setting at some other fleet root does not
  change this. The config layer follows that file and nothing else.

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

Values that lost still appear, so you can see exactly what overrides what.

`manifest config list` shows every key that has been set somewhere, along with the
layer that won. `--layer <name>` narrows the list to one layer, and `fleet` is allowed
there.

### Writing configuration

```bash
manifest config show
manifest config list
manifest config list --layer fleet
manifest config get git.tag_prefix
manifest config describe git.tag_prefix
manifest config set git.tag_prefix release-      # preview; add -y to write
manifest config unset git.tag_prefix             # preview; add -y to write
manifest config doctor
manifest config doctor --fix                     # preview; add -y to apply the fixes
```

`config set`, `config unset` and `config doctor --fix` preview by default, like every
other command that changes something. Add `-y` to write.

`config set` writes to your local config unless you tell it otherwise. Writing the
global config goes through an extra safety gate: Manifest asks you to confirm first.

On `set` and `unset`, `--layer` accepts only `global`, `project`, and `local`. From
inside a member, the `fleet` layer is read-only on purpose. Its files live in a
**different repository**, and writing them from a member would change a repository you
never named. To change a fleet-wide value, run the same command **at the fleet root**.
There, those files are just the ordinary `project` and `local` layers:

```bash
cd /path/to/fleet-root
manifest config set --layer project github.owner acme-corp -y
```

### Environment overrides

Every setting has a matching `MANIFEST_CLI_*` environment variable. An exported
variable beats every config file.

Two facts about this layer surprise people:

- **It is a snapshot taken when the process starts.** Exporting a variable partway
  through a session does not create an override for a command that is already running.
- **Exporting a variable *empty* is not the same as leaving it unset.** An empty value
  still hides all the file layers, so the built-in default takes over.
  `config describe` points this case out, so you do not have to guess.

## Documentation Generation

```bash
manifest docs                   # preview; add -y to regenerate the docs
manifest docs metadata          # preview; add -y to update repository metadata
manifest docs cleanup           # preview; add -y to move old docs to the archive
manifest docs fleet --dry-run   # preview the docs for a whole fleet
```

Manifest also builds a small documentation website for GitHub Pages. That is **on by
default**: it writes the site's source into the `docs-site` folder whenever it generates
documentation, which includes every release. To turn it off, set
`docs.generate.site: false`. See [DOCS_SITE.md](DOCS_SITE.md).

## Testing Manifest

This section is for people who work on Manifest itself. Contributor checks run in a
container, so you do not install test dependencies on your own machine:

```bash
./scripts/run-tests-container.sh
./scripts/run-tests-container.sh tests/docs_generation.bats
```

## When A Release Goes Wrong

A release changes several things in order: version, changelog, docs, commit, tag, push,
GitHub Release, formula. So it can stop in the middle, with some of them done.

Start here:

```bash
manifest status            # which branch and version am I on?
manifest ship repo patch   # the plan: shows the release as unfinished, and what remains
manifest ship repo patch -y
```

There is no separate recovery command. The ordinary `ship` command finishes a release
that stopped. What it does depends on how far the release got.

**If the release got as far as its tag,** the plan has a section headed "Unfinished
release". It says where the release stopped, and it lists what remains:

- push the branch and the tag
- run the release gate's check that follows the push, if your `release.gate` setting
  asks for one
- publish the GitHub Release and, in Manifest's own repository, the Homebrew formula
- check that the working copy is clean and that `HEAD` is still the commit it pushed

If you made commits after the tag, the plan lists them. Finishing pushes the branch, so
those commits are pushed too. They are not part of the release being finished.

With `-y`, Manifest does those steps and stops. It does not repeat the release. It does
not raise the version, make a commit, or create a tag. Whichever release type you name,
the version stays where it is. Run the command again afterwards for the next release.

Four more facts about finishing a release:

- **Run it from the same checkout.** Manifest knows a release is unfinished from a
  record it keeps in that checkout's `.git` folder. A fresh clone has no such record.
- **Some states block it.** The plan says `BLOCKED`, and gives the reason, in three
  cases: you have unrelated uncommitted changes, the checkout is not on a branch, or
  the tag is not in the current branch's history. Fix that first.
- **`--local` cannot finish a release**, because finishing means pushing. Manifest
  refuses, and tells you what to run.
- **To leave that release as it is and cut the next one**, add `--force-bump`.

**If the release stopped before its tag,** nothing has been published. There are three
cases:

- The release gate failed. That is the check that runs before the release writes
  anything. Nothing was committed, tagged or published. Fix the cause and run the
  release again.
- A later step failed. The version may already be raised in `VERSION` but not yet
  committed. Run the same command again, with the same release type. Manifest sees the
  raised version and continues from there. It does not raise the version a second
  time.
- The release commit was made, but creating the tag failed. `VERSION` is raised and
  committed, and no tag exists. Manifest does not continue from here: the next release
  takes the following version number, and the committed one is never tagged or
  published. Nothing else is lost. Fix what stopped the tag (the failure report names
  it) before you release again.

**For a fleet,** a release stops at the first member that fails. Members released
before it stay released. Run `manifest ship fleet patch` again to see the plan:

- It marks each member that has an unfinished release as `would finish`. `-y` finishes
  those members without raising their versions.
- `manifest ship fleet patch --local -y` refuses before it touches any member, because
  `--local` cannot finish a release.
- A member whose release cannot be finished yet, for example because it has
  uncommitted changes, is marked `BLOCKED` with the reason. `-y` then refuses before it
  touches any member. Fix that member first.
- `--force-bump` leaves the unfinished releases as they are and cuts a new release for
  those members. It also releases every other eligible member, even one with no
  changes.

**Read the suggested rollback command before you run it.** A failed release prints a
"Recovery commands" block. When nothing was pushed, that block can include
`git reset --hard <sha>`. Remember from
[the section above](#what-the-automatic-commit-includes-and-what-it-leaves-out) that a
release commits whatever you had uncommitted *before* it writes anything of its own. So
`<sha>` is the commit from before your own work was committed, and a hard reset throws
away your changes along with Manifest's. Look at `git log` and `git status` first. If
you have already run it, `git reflog` can usually still find the commit you moved away
from.

To go and look at an earlier release:

```bash
manifest revert repo v1.2.3       # Preview
manifest revert repo v1.2.3 -y    # Check out the tag
```

If you leave out the tag in a terminal, Manifest lets you choose from the ten highest
version tags. Without a terminal, it lists those tags, and applying requires you to
name one. The checkout previews by default and needs `-y` / `--yes` to apply.

Git refuses the checkout if it would overwrite local changes, including untracked and
ignored files. Submodule working copies stay as they are. Afterwards you are in
**detached HEAD**: you are viewing that tag, not sitting on a branch. Run
`git switch -` to go back.

For a fleet, `manifest revert fleet` lists the recorded snapshots. Preview one with
`manifest revert fleet <manager-commit>`, then add `-y` to restore its member commits
and its manager commit. A few rules apply:

- A fleet release records which commit each member was at in
  `manifest.fleet.snapshot.json`, and commits that file with the manager. A manager
  commit that does not contain the file cannot be restored, because nothing records
  which member commits belong with it.
- Every working copy involved must be clean.
- The checkouts are local. They leave every repository in detached HEAD and do not
  change any branch's history.
- If Git fails partway, some repositories are restored and others are not. Manifest
  reports this and exits with code `2`.

So `revert` is for looking at an old release, not for undoing a published one. Undoing
a release that is already public is a deliberate, manual job. The usual answer is a new
release that fixes the problem, not an attempt to erase the old one.

## Security And Maintenance

```bash
manifest security          # read-only checks; writes nothing
manifest security --write  # also save a timestamped report to the docs archive
manifest upgrade           # update the CLI (needs Manifest Cloud; see below)
manifest uninstall         # shows what it would remove
manifest uninstall -y
```

`manifest security` runs five checks:

- whether files meant to stay private are tracked in Git
- whether any file contains private key material
- whether anything looks like personal data
- whether environment files that exist are ignored by Git
- whether environment-variable names follow the expected prefix

It is read-only unless you pass `--write`. It never touches the hand-written
`docs/SECURITY_ANALYSIS_REPORT.md`. `--check` is also accepted and means the same as
the default: read-only.

`manifest upgrade` uses a Manifest Cloud plugin. Without that plugin, it tells you how
to upgrade through Homebrew: `brew update && brew upgrade manifest`.

The pre-commit hook is versioned in the repository, but each clone must enable it. It
is documented in [../.git-hooks/README.md](../.git-hooks/README.md).

### Publishing the CLI tap from a container

This applies only to people who publish Manifest CLI itself. They can set
`MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT` to an existing checkout of the Homebrew tap
repository, one that contains a `Formula/` folder. Manifest then publishes the formula
through that checkout, and the publishing machine does not need Homebrew installed. If
the path you set is not valid, publishing fails; Manifest does not fall back to another
tap. Manifest still verifies the release tarball's checksum independently before it
commits and pushes the formula.
