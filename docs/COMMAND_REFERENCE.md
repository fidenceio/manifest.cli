# Manifest CLI Command Reference

This page lists every supported command and its flags. For live help, run
`manifest <command> --help`.

This page assumes you know three ideas: preview and apply, `MANIFEST_CLI_AUTO_CONFIRM`,
and the release gate. If any of them is new to you, first read
[Preview And Apply](USER_GUIDE.md#preview-and-apply) in the User Guide and the
[Migration Guide](MIGRATION.md).

Some words used on this page:

- A **plan** (also called a **preview**) is a printed list of what a command would do. It
  changes nothing.
- To **apply** is to carry the plan out.
- A **fleet** is a folder of repositories that Manifest manages together. Each
  repository in it is a **member**.
- The **manager** is the repository at the top of a fleet. It is also called the
  **coordination root**. It holds the fleet's member list and settings.
- The **release gate** is the check, usually your test command, that must pass before
  Manifest makes a release.

## Command Tree

The main workflow uses a verb, a scope, and an optional action:

```text
manifest
├── init [repo|fleet]                          guided or explicit setup; --connect on explicit scopes
├── status repo|fleet                           inspect current state
├── ship
│   ├── repo patch|minor|major|revision         release one repo, or finish its unfinished release
│   ├── fleet patch|minor|major|revision        release members, then ship the manager
│   └── fleet manager                          ship only the coordination root
├── discover|add|update|validate fleet          manage membership
├── plan|reconcile fleet                       prepare and apply adoption repairs
├── docs [fleet]                               generate documentation
├── topics fleet                               add GitHub topics
├── pr create|status|checks|ready|merge|update   manage a pull request
├── pr fleet                                   manage fleet pull requests
├── config show|setup|list|get|set|unset|describe|doctor|time
├── env generate|validate|export
├── revert
│   ├── repo [<tag>]                           preview or apply a local tag checkout
│   └── fleet [<snapshot>]                     restore manager and recorded member commits
├── doctor|security                            inspect health and security
├── recipe list|show|explain                    inspect execution recipes
├── cleanup repo|fleet|state
├── upgrade|reinstall|uninstall
└── version|help
```

The Cloud commands and the less common options are described further down this page.
Commands that have been removed, and what to use instead, are listed in the
[Migration Guide](MIGRATION.md).

## Global Rules

| Rule | Detail |
| ---- | ------ |
| Shape of a command | `manifest <verb> <scope>`, for example `manifest ship repo patch` |
| Plan by default | A command that changes something only prints a plan, unless you add `-y` / `--yes` |
| Explicit plan | `--dry-run` always means plan only |
| Conflicting modes | `--dry-run` and `-y` / `--yes` cannot be used together, in either order |
| Local apply | `ship ... --local -y` does the local work, including the commit. It makes no tag, pushes nothing, and publishes nothing |
| Which repo? | Repo scope uses the `.git` root of your current directory |
| Which repos? | Fleet scope uses the fleet config and the selected rows of the fleet TSV (`manifest.fleet.tsv`) |

### Exit Codes

| Code | Meaning |
| ---- | ------- |
| `0` | Success. Either an apply finished, or a plan was printed (the default) |
| `1` | Error: bad arguments, a failed pre-flight check, a declined confirmation, or a failed apply. A release that fails after its tag was pushed also exits `1`, with the tag already public; the failure report says how far it got, and running the same command again plans finishing it |
| `2` | Partial completion of `ship fleet` or `revert fleet`: one or more member releases or checkouts were applied, and then a later step failed. Read the closing block and the recovery report. If you retry without `--force-bump`, members that are already at their tag are skipped. `init fleet -y` also returns `2` when the member list names a directory that does not exist |
| `3` | Protective skip. A safety guard refused to do something destructive (for example, `uninstall` running under a temporary `HOME`) |
| `4` | Paused for a documentation handoff (`docs.handoff`). This is not a failure: no release commit, tag or push was made. Manifest writes a brief that says what the documentation needs, under `.git/manifest-ship/handoff/`, and prints its path. Edit the documentation, then run the same command again. That run checks the edits and continues the release |
| `10` | A plan was printed and no consent was given. Returned only when `preview.exit_code` is set to `distinct` |

**Why `0` covers both cases.** A plan is a successful run, so by default it exits `0`,
the same as an apply. That suits a person. It does not suit a script that must tell
"a plan was printed and is waiting for `-y`" apart from "a release was made".

If your script needs to tell them apart, set `preview.exit_code: distinct` (or
`MANIFEST_CLI_PREVIEW_EXIT_CODE=distinct`). These plans then return `10` instead of `0`:

- `ship repo` and `ship fleet`, including `ship fleet manager`
- `topics fleet`
- `pr create`, `pr ready`, `pr merge` and `pr update`

Nothing else changes. `--dry-run` is still a plan, and the exit codes of an apply stay the
same. Plans of other commands still return `0`.

A `ship repo` or `ship fleet` plan also prints a fingerprint, a short code that
identifies the plan. When you apply, Manifest computes the fingerprint again. If the
plan has changed since you read it, Manifest prints a warning. The warning does not
stop the apply.

## Core Journey

### `manifest init` — guided setup

```bash
manifest init
manifest init --dry-run
manifest init -y
manifest init --depth N|auto
manifest init --name NAME
manifest init --force
```

`manifest init` is the guided way to set up. By default it inspects your current
directory, changes nothing, and shows a proposed setup. It recognises three cases: a
single repository, a folder that could become a fleet, and a folder that is already
configured.

With `-y` it applies that setup and writes one record to Manifest's audit log.

For a single repository, `-y` is enough when the target is clear. The target is clear
when you are on a named branch. You do not need an `origin` remote during setup,
because you may not have created one yet.

### `manifest config`

```bash
manifest config
manifest config show
manifest config setup
manifest config time
manifest config list [--layer local|project|fleet|global] [--json]
manifest config get <key>
manifest config set [--layer local|project|global] <key> <value> [--dry-run] [-y|--yes]
manifest config unset [--layer local|project|global] <key> [--dry-run] [-y|--yes]
manifest config describe <key>
manifest config doctor
manifest config doctor --fix [--dry-run] [-y|--yes]
```

These commands read and write Manifest's settings. The settings are YAML files arranged
in layers. A higher layer overrides a lower one. From highest to lowest, the layers are
`env`, `local`, `project`, `fleet` (inherited from the fleet root), `global`, and the
built-in defaults.

| Command | What it does |
| ------- | ------------ |
| `config` | In a terminal, starts the setup wizard. Otherwise prints the settings |
| `config show` | Prints the settings in effect |
| `config setup` | Starts the setup wizard |
| `config time` | Prints the time servers used for timestamps |
| `config list` | Lists every key and the layer its value comes from |
| `config get <key>` | Prints the value in effect for one key |
| `config set`, `config unset` | Writes or removes one key in one layer |
| `config describe <key>` | Prints the key's value at every layer, and its environment variable |
| `config doctor` | Reports out-of-date settings. `--fix` repairs them |

`list`, `get`, and `describe` read every layer.

`set` and `unset` plan by default. Add `-y` to write. They write the `local` layer unless
you name another one. Put `--layer` before the key: a `--layer` placed after the value is
ignored.

`set` and `unset` can write only `global`, `project`, or `local`. `--layer fleet` is
refused, because those files live in a **different repository**. Writing them from
inside a member would change a repository you did not name. To change a fleet-wide
value, run the same command at the fleet root.

`config doctor --fix` also plans by default. Add `-y` to apply the repairs.

Writing the global config file asks you to confirm first.

For the full layer model, see [User Guide — Configuration](USER_GUIDE.md#configuration).

### `manifest init repo|fleet`

```bash
manifest init repo [--dry-run] [-y|--yes] [--force] [--remote URL] [--no-connect] [--create-repo-private|--create-repo-public]
manifest init fleet [--dry-run] [-y|--yes] [--depth N|auto] [--all-folders] [--name NAME] [--force]
                    [--connect|--no-connect] [--parallel] [--clone-only] [--pull-only]
                    [--create-repo-private|--create-repo-public]
```

**What `init repo` does.** Repository setup is a **dry run by default**. With `-y`,
`manifest init repo` does four things:

1. It initializes Git on the configured release branch, if the folder is not yet a
   repository.
2. It connects `origin`.
3. It creates the project files that are missing.
4. It runs the same local release check that `ship` runs.

It does not bump a version, create a commit or a tag, publish a release, or push.

**How `origin` is handled.**

- When `origin` is missing, the plan proposes a **private GitHub repository**. With
  `-y`, Manifest creates it under `github.owner`, or under the GitHub user you are
  signed in as.
- Use `--remote URL` to connect a remote that already exists.
- Use `--create-repo-public` to make the new repository public.
- An existing `origin` is kept as it is.
- An empty `origin` needs no pull. An `origin` that has commits is fast-forwarded
  before any file is created.
- If the remote cannot be reached, or the histories conflict or have diverged, setup
  fails and says so.

`--no-connect` creates the local files only. Readiness is then not verified, and
Manifest says so. `--force` recreates the local config and keeps your project content.

**The files `init repo` creates.** These are the files a Manifest project needs:
`VERSION`, `README.md`, `CHANGELOG.md`, `.gitignore`, `docs/`, `scripts/run-tests.sh`,
`.env.example`, `robots.txt`, `ai.txt`, and `manifest.config.local.yaml`. Each one is
written only if it is absent. `--dry-run` lists them with a one-line purpose for each.
The [User Guide](USER_GUIDE.md#first-time-setup) has the same table in full, and
explains why the two crawl-privacy files (`robots.txt` and `ai.txt`) are there.

**Guided or explicit setup.** Plain `manifest init` chooses for you:

- In an empty directory, it sets up a new repository.
- In an existing repository, it checks for missing files.
- In a folder that contains repositories, it offers fleet discovery.

An existing `VERSION` file alone does not mean setup is complete. Plain `init` and
`init repo` use the same plan and the same readiness checks. On a folder that could
become a fleet, `init -y` writes the member list and stops so that you can review it.
`init fleet -y` then applies the selection you reviewed.

**Readiness checks.** Readiness covers the release branch, the Git author and committer
identity, a valid version, the required files, the CI on `origin` when it is available,
and the configured release check.

- A real check that fails or is missing makes the command return a nonzero code and
  name the blocker.
- `init` keeps existing checks. It does not turn verification off.
- Newly generated checks run in containers. Applying may build images and download
  dependencies inside those containers.
- A new scaffold passes a structural check of its own short list of files. When you add
  application files, that check fails until you supply real verification for the
  project. It is not a passing placeholder for untested code.
- Remote CI cannot be confirmed before the repository is published. `init` reports
  that limit and does not publish in order to test it.
- A passing `init` shows that the repository is ready locally, now. It does not
  promise that the remote service will be available later, or that you may push.

**How `init` treats an existing `.gitignore`.** It never overwrites the file. It
*adds* the recommended rules that are missing, under a marked header, and tells you how
many it added. In this way an older `.gitignore` gains the rules it lacks, including the
`KEY MATERIAL` block, which keeps private keys out of commits.

The change only appends. Nothing that exists is rewritten, reordered, or removed. If
the exact opposite of a rule is already present, the rule is skipped, so a choice you
made on purpose is not reversed. Running `init` again adds nothing. A release never
does this: `manifest ship` only reports the missing rules.

**What `init fleet` does.** It sets up a fleet in two phases. The first run writes the
member list (`manifest.fleet.tsv`) for you to review. The second run acts on it. The
connect phase clones missing members and pulls existing ones. It is off unless you pass
`--connect`. `--parallel`, `--clone-only` and `--pull-only` shape the connect phase and
turn it on.

If the member list names a directory that does not exist, `init fleet -y` reports it
and returns exit code `2`.

**Creating GitHub repositories is always explicit.** Pass exactly one of
`--create-repo-private` or `--create-repo-public`. With these flags, the second phase
creates a remote for each selected member. If `github.owner` is set to a user or an
organisation, both the plan and the apply target `<owner>/<repo>`. If it is unset, `gh`
uses the account you are signed in as.

The second phase reads each selected directory's own `.git` state from disk. An
out-of-date `HAS_GIT` value in the member list therefore cannot make a member take
over the fleet root's repository or remote.

### `manifest ship`

```bash
manifest ship repo patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--explain] [--force-bump] [--interactive]
manifest ship fleet patch|minor|major|revision [--dry-run] [-y|--yes] [--local] [--explain] [--force-bump] [--require-clean]
manifest ship fleet manager [patch|minor|major|revision] [--dry-run] [-y|--yes] [--local]
```

**A repo release** can raise the version, generate docs, commit, tag, push, and publish
GitHub Release notes. For Manifest's own repository it also publishes the Homebrew
formula. Before it reports success, it requires a clean source tree. For a published
release it also requires that `HEAD` is still the commit it pushed.

**A fleet release** applies the same rules to each release-enabled member that has
something to release. A member that is already tagged and clean is listed and skipped
as `no changes`.

The fleet ship then commits and pushes the **manager**. This step also runs when every
member is skipped, and when `fleet.versioning` is `none`. That setting turns off the
fleet version stamp. It does not turn off the manager commit or push. Only the files on
the coordination allowlist are staged. When a fleet version is pending (written to the
fleet version file but not yet committed) and no new member release is being made, the
manager commits that version without raising it again. `--local` keeps the manager
commit local.

**`ship fleet manager`** commits and pushes the manager alone. Use it for a change that
touches only the manager, or to retry the manager step. No member is touched. Without a
release type, the fleet version file is stamped only together with a commit. With a
release type, it is stamped even when nothing else changed. Only
`fleet.versioning: semver` reads the release type itself; the other versioning schemes
ignore the word.

Flags:

- `--local`, with `-y`, does the local work only. It still commits. It makes no tag,
  pushes nothing, and publishes nothing.
- `--require-clean` refuses a fleet ship if any member has uncommitted changes.
- `--force-bump` releases even when nothing has changed since the last tag. It only
  moves forward: you get a new commit and a new tag, and history is never rewritten.
- `--explain` prints the built-in recipe for the command and runs nothing.
- `--interactive` turns on the interactive safety prompts.

### An unfinished release

A release is **unfinished** when its ship stopped after it created the tag. The cause
may be a failed push, a release gate that failed after the push, a failed formula
publish, or a run that was killed. A GitHub Release that fails does not stop the ship
unless `github.release.required` is `true`, so by default it does not leave a release
unfinished. You finish an unfinished release with the same command you would run next.
There is no separate command for it.

```bash
manifest ship repo patch      # the plan: "Unfinished release", what remains, no bump
manifest ship repo patch -y   # finishes it; changes no version, makes no commit or tag
manifest ship repo patch      # now the ordinary plan for the next release
```

- **How Manifest knows.** A publishing ship writes a small record at
  `.git/manifest-ship/in-flight` just before it creates the tag. It removes the record
  when the release completes. If a record names the version in `VERSION` and the commit
  that the version's tag points at, that release is unfinished. Manifest does not use
  the network to decide this. The record lives inside `.git`, so only the checkout that
  started the release has it. Finish the release from that checkout.
- **The release type you name is not applied** by a run that finishes a release.
  `patch`, `minor`, `major` and `revision` all produce the same finish plan. Run the
  command again afterwards to make the next release.
- **Finishing repeats only steps that are safe to repeat.** It pushes the branch and
  the tag; a ref that is already pushed is left as it is. It runs the release gate's
  post-push check, when `release.gate` asks for one, and publishes nothing if that
  check fails. The check is of the commit the tag points at, not of any commit made
  after it. It publishes the GitHub Release where configured and, for Manifest's own
  repository, the Homebrew formula. Then it runs the completion check.
- **Commits made after the tag are pushed too.** A finish pushes the branch, so any
  commit you made after the tag goes with it. The plan lists those commits. They are
  not part of the release being finished.
- **Three states block a finish.** The plan says `BLOCKED`, and `-y` refuses, when the
  working tree has unrelated uncommitted changes, when `HEAD` is detached, or when the
  tag is not in the current branch's history. Commit or stash the changes, or check out
  the branch the release was made from, and run the command again.
- **`--local` cannot finish a release**, because finishing means pushing. It refuses in
  both the plan and the apply.
- **To leave it and move on,** add `--force-bump`. The unfinished release stays as it
  is, and Manifest makes the next release.
- **In a fleet,** the plan of `manifest ship fleet <type>` marks such a member
  `would finish`. With `-y`, Manifest finishes that member and does not bump it. With
  `--local`, the plan marks the member `BLOCKED`, and `ship fleet <type> --local -y`
  refuses before it touches any member. A member whose release cannot be finished from
  its current state, for example one with uncommitted changes, is also marked
  `BLOCKED`, with the reason, and the apply refuses in the same way. `--force-bump`
  leaves such members unfinished and bumps them instead. As always, it also releases
  every other eligible member, changed or not. To leave one member unfinished and
  release the others normally, run `manifest ship repo <type> --force-bump -y` in that
  member first.

A run that stopped earlier is a different case. If a run wrote the new version to
`VERSION` but stopped before the release commit, the next `ship repo` run with the same
release type keeps that version. It does not bump a second time.

`manifest ship repo resume` and `manifest ship fleet resume` are not commands. Use the
commands above. See the [Migration Guide](MIGRATION.md).

### Version increments

A version is an ordered list of numbers of **any length**. Nothing here assumes three
numbers, or four. An increment names one position. Raising that position sets every
position to its right to zero, or removes it:

| From | `major` | `minor` | `patch` | `revision` |
| ---- | ------- | ------- | ------- | ---------- |
| `20.1.0` | `21.0.0` | `20.2.0` | `20.1.1` | `20.1.0.1` |
| `20.1.0.3` | `21.0.0` | `20.2.0` | `20.1.1` | `20.1.0.4` |
| `1.2.3.4.5` | `2.0.0` | `1.3.0` | `1.2.4` | `1.2.3.5` |

**Read a fourth number as belonging to the third, not as running beside it.**
`20.1.0.3` means "the third re-cut of `20.1.0`". So a `patch` from there gives `20.1.1`,
a patch that has had no re-cuts, and the fourth number goes away.

Use `revision` when you need to re-cut a version you already released, and the code
that `20.1.0` names is still the same. A bad tag and a packaging-only fix are examples.
**`revision` is not a lasting counter.** It lasts only until the next `patch`, `minor`,
or `major`. This is by design.

If you need a number that survives ordinary releases, such as a build number, keep it
in a field of its own, outside `VERSION`. `VERSION` has one job: to say which tree a
release is. Release verification depends on `VERSION` having that one meaning.

**Positions are what matter. Names are only aliases.** You can address any position by
its number, whether or not it has a name:

```bash
manifest ship repo patch      # the 3rd number
manifest ship repo 3          # exactly the same thing
manifest ship repo 6          # the 6th number (1.2.3 -> 1.2.3.0.0.1)
```

**You can rename the positions** with `version.components`. It is an ordered list, and
a name's place in the list *is* its position. There is no second place to state a
position, so the two cannot disagree. The default is `major,minor,patch,revision`, and
you can replace even those four:

```yaml
version:
  components: "generation,major,minor,patch"   # `major` now means position 2
```

To name positions beyond the fourth, write a longer list
(`major,minor,patch,revision,build,hotfix`).

A list that cannot be used is **refused**. Manifest does not quietly use the defaults
in its place. The following are refused:

- a name that appears twice;
- a name made only of digits, because it could be confused with a position number;
- a blank entry, because it would shift every later name one position to the left;
- a name with characters other than letters, digits, `_` and `-`.

Manifest refuses because the alternative is worse. If a project configured its own
names and Manifest used the standard four in their place, the release would raise the
wrong position.

A version that contains non-numeric text (`1.2.3-rc1`, `v1.2.3`) is refused, not
guessed at, and `VERSION` is left alone. `version.separator` (default `.`) applies
everywhere.

Which files a release writes the version to:

- By default, a repo or fleet release writes the new version to `VERSION` and to no
  other version file.
- `version.sync` is opt-in. It lists more files to keep in step with `VERSION`. When it
  is unset, no package manifest or lockfile is touched.
- `version.sync` updates a `version` field at the **top level** of a JSON, TOML, or
  YAML file. A missing file, a version nested deeper, and an unsupported format are
  each skipped.
- A read-only scanner uses `modules/catalog/version-handlers.tsv` to recognise known
  package and version files. `manifest status`, `manifest status --json`,
  `manifest doctor`, fleet status, and fleet release plans report what the scanner
  found. They change nothing.
- To adjust that report, use `version.surfaces.enabled`, `version.surfaces.catalog`,
  `version.surfaces.scan_depth`, and `version.surfaces.notification_mode`.

## Fleet Operations

```bash
manifest status fleet [--json] [--bootstrap] [--verify]
manifest discover fleet [--depth N|auto] [--json] [--quiet]
manifest add fleet <path-or-url> [--name NAME] [--dry-run] [-y|--yes]
manifest update fleet [--depth N|auto] [--json] [--quiet] [--dry-run] [-y|--yes]
manifest validate fleet
manifest docs fleet [--dry-run] [-y|--yes]
manifest topics fleet [--dry-run] [-y|--yes]
manifest plan fleet [--depth N|auto] [--plan FILE] [--name NAME] [--dry-run] [-y|--yes]
manifest reconcile fleet [--plan FILE] [--commit] [--push] [--adopt-submodules] [--dry-run] [-y|--yes]
```

| Command | What it does |
| ------- | ------------ |
| `status fleet` | Shows a read-only table of the fleet's repositories |
| `discover fleet` | Finds repositories that could become members. It writes nothing |
| `add fleet` | Adds one local path or remote URL to the member list |
| `update fleet` | Scans again and adds newly found repositories to the member list |
| `validate fleet` | Checks the fleet configuration and the member paths |
| `docs fleet` | Generates fleet documentation |
| `topics fleet` | Adds GitHub topics taken from repository names |
| `plan fleet` | Builds an adoption plan. With `-y` it writes the plan file (`manifest.fleet.plan.yaml` by default) |
| `reconcile fleet` | Checks that plan and, with `-y`, applies it |

For `reconcile fleet`, `--commit` needs `-y`, and `--push` needs `--commit`.
`--adopt-submodules` allows the plan entries that adopt a submodule.

Put the verb first: `manifest topics fleet`, not `manifest fleet topics`.

`manifest topics fleet` turns the parts of a repository's dotted name into GitHub
topics. It only ever **adds** topics. It runs only when `topics.from_name` is set to
`inner`, `all`, or `all-but-first`. Set it in `manifest.fleet.config.yaml` for the whole
fleet, or for your machine only with:

```bash
manifest config set --layer global topics.from_name inner -y
```

A value from a config layer or from the environment overrides the value in
`manifest.fleet.config.yaml`. Note the difference between the two: that file is the
fleet *definition*. It is not the `fleet` configuration layer. See
[User Guide — Configuration](USER_GUIDE.md#configuration).

Once the setting is on, the same step also runs in two other places. It runs as part of
`manifest update fleet`. It also runs at the end of a completed `manifest ship fleet -y`
that released at least one member and did not use `--local`. There it is quiet and
prints one summary line at most.

## Diagnostics

```bash
manifest status [repo|fleet] [--json] [--bootstrap] [--verify]
manifest doctor
manifest security [--write]
manifest recipe list
manifest recipe show <recipe-id>
manifest recipe explain <recipe-id>
```

| Command | What it does |
| ------- | ------------ |
| `status` | Shows the state of the repository or the fleet. `--json` prints JSON |
| `status --bootstrap` | Lists the fleet members that are declared but absent and would be cloned. It clones nothing |
| `status --verify` | Checks each member's remote with a read-only `git ls-remote`. It uses the network and saves nothing |
| `doctor` | Checks your tools, your config, and the health of the repository |
| `security` | Looks for private files tracked in Git, likely personal data, and unsafe handling of environment files |
| `recipe list` | Lists the recipes. A recipe is the ordered list of steps behind a command |
| `recipe show`, `recipe explain` | Prints one recipe's definition, or explains its steps |

A diagnostic command changes nothing, unless its description says otherwise.

## Pull Requests

These commands wrap the `gh` command-line tool. They do not need Manifest Cloud:

```bash
manifest pr
manifest pr create [--draft] [gh flags...] [--dry-run] [-y|--yes]
manifest pr status [<number|branch>]
manifest pr checks [<number|branch>] [--watch]
manifest pr ready [<number|branch>] [--dry-run] [-y|--yes]
manifest pr merge [<number|branch>] [--squash|--merge|--rebase] [--dry-run] [-y|--yes]
manifest pr update [<number|branch>] [--dry-run] [-y|--yes]
```

`manifest pr` alone shows the pull request for the current branch, or offers to open
one. `create`, `ready`, `merge` and `update` plan by default and act with `-y`. `merge`
squashes unless you choose another method. Flags that Manifest does not handle are
passed on to `gh`.

These commands need Manifest Cloud:

```bash
manifest pr queue
manifest pr policy show
manifest pr policy validate
manifest pr fleet [queue|create|status|checks|ready] [--dry-run] [-y|--yes]
```

## Documentation

```bash
manifest docs [--dry-run] [-y|--yes]
manifest docs metadata [--dry-run] [-y|--yes]
manifest docs cleanup [--dry-run] [-y|--yes]
manifest docs fleet --dry-run
```

| Command | What it does |
| ------- | ------------ |
| `docs` | Generates the documentation for the current version |
| `docs metadata` | Updates the repository metadata |
| `docs cleanup` | Moves older documentation into the archive folder and removes temporary files. The plan names the files it would remove |
| `docs fleet` | Generates fleet documentation |

Each of these plans by default and writes with `-y`.

The documentation website is **on by default**: `manifest docs -y` and every release
write its source into the `docs-site` folder. To turn it off, set `docs.generate.site`
to `false`. See [DOCS_SITE.md](DOCS_SITE.md) for the other keys.

## Env Schema

```bash
manifest env generate [--check] [--dry-run] [-y|--yes]
manifest env validate
manifest env export [--format json]
```

A component spec is the file `service.spec.yaml` or `app.spec.yaml` at the root of a
repository. Its `env:` block is the single source of truth for the repository's
environment variables: their names, descriptions and defaults, and whether each is
required, secret or needed at build time.

Manifest keeps that list in one place and checks it. It does not decide how the
variables reach a running workload. It writes no deployment file, and it names no
secret store.

### `env generate`

`env generate` builds two things from the `env:` block:

- `.env.example` — always. A variable that is not a secret carries its default. A
  secret is commented out and has no value.
- the Dockerfile `ARG`→`ENV` marker block, for variables marked `public: true`. It is
  written only when a `Dockerfile` exists.

`env generate` plans by default, and `-y` writes. `--check` is for use in a release or
in CI. It exits `1` if either output is out of date.

**A flag is a boolean.** An entry's `secret`, `required` and `public` take `true` or
`false`. You may write `true`, `True` or `TRUE`, and `false` in the same three ways.
The quoted strings `"true"` and `"false"` are accepted too. A flag that is left out is
`false`. Any other value (`yes`, `on`, `1`) is refused and named; Manifest does not
guess. In that case `env generate` exits `1` and writes nothing, `env validate` fails,
`env export` prints nothing, and `manifest init` does not write `.env.example`.

**`env generate` replaces only the file it wrote.** The `.env.example` it generates
starts with a Manifest header line. If an existing `.env.example` starts with any other
line, Manifest treats the file as yours:

- the plan names it as *hand-authored, left untouched*;
- `-y` does not write it;
- `--check` does not count it as out of date.

Delete the file if you want Manifest to generate it. An empty file is replaced.

A file that is written keeps the permissions it had. This includes the Dockerfile. If
`.env.example` cannot be read as a file (a directory, a file you cannot read, a symlink
that points to nothing), the plan names it, and `--check` and `-y` exit `1`. A write
that fails also exits `1`.

### `env validate`

`env validate` only reads. It checks the prefix policy, whether the two generated
outputs are out of date, and whether `.env` value files are ignored by Git.

### `env export`

`env export` prints the `env:` block as JSON on standard output. It writes no file. It
is for a tool of your own that renders deployment files from the same list.

```json
{
  "schema": 1,
  "identity": "billing-service",
  "env": [
    {
      "name": "ACME_BILLING_LOG_LEVEL",
      "description": "How much the service logs",
      "required": false,
      "default": "info",
      "secret": false,
      "group": "app",
      "public": false,
      "framework_name": null
    }
  ]
}
```

| Field | Meaning |
| --- | --- |
| `schema` | `1`. It changes only if the shape of this document changes |
| `identity` | The name of the origin repository. When the repository has no `origin` remote, or its URL does not end in a plain name, the name of its folder |
| `env` | One object for each variable, in the order the spec lists them |
| `name`, `description` | Strings. `description` is `""` when the spec sets none |
| `required`, `secret`, `public` | `true` or `false`, read the same way `env generate` reads them |
| `default` | A string, or `null` when the spec sets none. A default of `false` or `0` is the string `"false"` or `"0"`. **For a secret it is always `null`:** a secret's default is never printed |
| `group` | A string. `"app"` when the spec sets none |
| `framework_name` | A string, or `null` when the spec sets none |

Every entry has all eight fields. Strings are JSON-encoded, so quotes, backslashes and
line breaks in a description or default arrive intact. A YAML alias or merge key in the
spec is exported as the value it stands for.

`env export` either prints the whole document and exits `0`, or prints nothing on
standard output and exits `1` with the reason on standard error. It refuses, and names
the entry, when:

- the spec file is missing, cannot be parsed as YAML, or holds more than one document;
- `env:` is not a list;
- an entry has no `name`, or a name is used twice;
- a flag is neither `true` nor `false`;
- a `description`, `default`, `group` or `framework_name` is a list or a map.

A spec with no `env:` block exports an empty list and exits `0`.

### Deployment files

Manifest does not write files under `k8s/env`, and it does not read `env.secrets`.
Earlier releases did both. See the [Migration Guide](MIGRATION.md) if you are upgrading.

If your repository still holds a file that an earlier Manifest generated under
`k8s/env`, or a config that still sets `env.secrets`, then `env generate` and
`env validate` print a note on standard error that says so. The note does not change
the exit code. Manifest does not update, compare or delete those files; they are yours.

To keep generating them, copy `examples/env-k8s-render.sh` from the Manifest CLI into
your own repository and change it to suit your platform. It reads `manifest env export`
and writes the four files that Manifest wrote. The [Migration Guide](MIGRATION.md) lists
the two values it writes differently:

```bash
manifest env export | ./env-k8s-render.sh \
    --provider external-secrets --store-name <store-name> \
    --path 'secret/data/{env}/{identity}/{group}' --env-label env
```

The script is an example and not a supported command. Nothing in Manifest runs it or
checks what it writes. Run it with `--help` for its options.

**The prefix policy is on by default.** It keeps the names of environment variables
tidy. The names of your application's own variables must start with this repository's
prefix. Well-known framework names (`DATABASE_URL`, `NEXT_PUBLIC_*`, and similar) and
names that start with `MANIFEST_CLI_` are always allowed.

When `env.prefix` is not set, the prefix is **derived from the repository's directory
name**: `fidence.app.kanizsa` becomes `FIDENCE_APP_KANIZSA_`, and `my-tool` becomes
`MY_TOOL_`. Set `env.prefix` to a value of your own (`ACME_`) to require that prefix.
Set `env.prefix: off` to turn the policy off.

You can choose how strictly the policy is enforced. `env.naming_enforcement` is `strict`
by default, which blocks. `warn` only reports the violations. `env.naming_allow` takes
more allowed entries, separated by commas. An entry that ends in `_` is treated as a
prefix.

`manifest init repo` and its connect phase create `.env.example` when it is missing.
They never overwrite an existing one. They use the spec when it has an `env:` block,
and they follow the configured prefix.

## Recovery

```bash
manifest ship repo patch       # after a failed release: plans finishing it (no bump)
manifest ship repo patch -y    # finishes it
manifest revert repo v1.2.3    # preview a tag checkout
manifest revert repo v1.2.3 -y # apply the checkout
manifest revert fleet          # list available snapshot commits
manifest revert fleet <commit> # preview a recorded fleet checkout
manifest revert fleet <commit> -y # apply member checkouts, then manager
```

**`revert repo [<tag>]`** checks out a local tag. It previews by default. Name a local
tag, or, in a terminal, pick one of the ten highest version tags. Without a terminal,
leaving out the tag lists the available versions, and applying needs a tag that you
name. `-y` / `--yes` applies the checkout. `--dry-run` asks for the preview explicitly.

The target is the commit the tag points at, even when a branch has the same name. Git
refuses to overwrite tracked, untracked, or ignored files that conflict. Manifest does
not force, stash, reset, commit, tag, or push. Submodule working trees stay as they
are. This local checkout needs no `origin` remote and no current branch.

**`revert fleet [<snapshot>]`** restores the exact member commits recorded in
`manifest.fleet.snapshot.json`, and then checks out the manager at the commit you
chose. A snapshot is a manager commit that contains that file. A fleet ship records the
member commits after the members finish, and includes the file in the manager's
coordination commit. The snapshot is therefore available to anyone who clones the
manager's Git history. No extra tag is created. Leave out the snapshot to list the ten
most recent manager commits that changed the file. Applying needs a manager commit or
ref that you name, and `-y` / `--yes`.

Fleet revert has these requirements:

- The manager and every member have a clean working tree.
- Every recorded repository is inside the fleet root.
- Every recorded commit is available locally.

It takes the fleet lock and the repository locks, and checks every target before any
checkout. An ignored-file conflict or a Git hook can still stop a later checkout. A
failure reports how many checkouts completed, and the command returns `2` if any
checkout completed. Members are restored first and the manager last. There is no
automatic rollback and no push. Submodule working trees are kept. A member that is
missing, or is not a Git repository, is recorded with an unavailable commit, and a
snapshot that holds such a member cannot be used for fleet revert.

A manager commit that has no snapshot file cannot be used, because it does not record
the member commits. A snapshot records committed state only. Uncommitted files are not
backed up.

After a revert you are in **detached HEAD**. This means you are viewing that tag and
are not on a branch. `git switch -` returns you to the branch you came from. So
`revert repo` is a way to *look at* an old release. It is not a way to undo a published
one. Manifest does not undo a published release; that is a stated non-goal
([NORTH_STAR.md](NORTH_STAR.md)). To recover, move forward: ship a new version.

**When a release fails partway,** run `manifest ship repo patch` first. If the release
reached its tag, the plan shows it as unfinished, and `-y` finishes it.

The failure report may also suggest `git reset --hard <sha>`. Read the report before
you run that command. A release **begins** by committing whatever you had uncommitted
(see
[User Guide](USER_GUIDE.md#what-the-automatic-commit-includes-and-what-it-leaves-out)).
So `<sha>` is from before your own work was committed, and a hard reset discards your
changes together with Manifest's. Check `git log` and `git status` first. `git reflog`
can still find a commit that you have moved away from.

## Maintenance

```bash
manifest cleanup [repo|fleet|state] [--dry-run] [-y|--yes]
manifest upgrade
manifest uninstall [--dry-run] [-y|--yes] [--force]
manifest reinstall [--dry-run] [-y|--yes]
manifest security [--write]
manifest test [suite]
```

### `manifest cleanup`

`cleanup` removes **Manifest's own leftovers**. It never removes your work. Like every
other command that changes something, it previews by default. `-y` applies without a
prompt.

| Scope | What it covers |
| --- | --- |
| `repo` (default) | This repository |
| `fleet` | Every member of the fleet |
| `state` | This machine's Manifest caches. They do not belong to any one repository, which is why `state` is a separate word and not a repo or fleet scope |

**What it removes**

- Retired scaffold sidecars: `.gitignore.manifest`, `robots.txt.manifest`,
  `ai.txt.manifest`, `scripts/run-tests.sh.manifest`, `.env.example.manifest`. Versions
  of Manifest before v58.0.0 wrote these files beside an existing file, as a reference
  for merging by hand. Manifest does not write them now, but a repository set up by one
  of those versions may still hold them.
- Manifest's own temporary files.
- Stale `git worktree` records, by running `git worktree prune`.
- `state` only: stale runtime cache files under `TMPDIR`, empty scratch directories, and
  ship logs older than the number of logs Manifest keeps.

**What it never removes**

- **A file tracked by Git.** A committed sidecar is named in the summary together with
  the exact `git rm` command. Removing it then stays a commit that you make and can
  review.
- Your build output: `node_modules/`, `target/`, `dist/`, `build/`, `vendor/`, `.venv/`.
  Those belong to your build system.
- A Git worktree directory, or anything inside one. `prune` only drops the records of
  directories that are already gone. Freeing the space of a live worktree needs
  `git worktree remove --force`, which would destroy uncommitted work. So `cleanup`
  reports those directories and stops there.
- `manifest.config.global.yaml`, the `audit/` log, live locks, and `gh-rate/`. Despite
  its name, `gh-rate/` is not a cache. It spaces out the changes Manifest makes on
  GitHub. Clearing it would remove the protection that keeps you under the rate limit.

`cleanup` publishes nothing. So `cleanup -y` works even on a detached HEAD, or in a
repository with no `origin` remote, where the release commands refuse.

### Other maintenance commands

`upgrade` updates Manifest CLI. It needs a Manifest Cloud plugin. If you installed with
Homebrew, run `brew update && brew upgrade manifest`.

`uninstall` plans by default. It keeps your global config unless you separately confirm
its removal. `--force` skips the extra prompts, and only after `-y` has chosen to
apply.

`reinstall` removes Manifest CLI and installs it again. It plans by default.

`security` is **read-only by default**. It reports private files that are tracked in
Git, anything that looks like personal data, and unsafe handling of environment files.
It writes nothing. `--write` also saves a report, with a timestamp, to the docs archive.
Neither mode writes `docs/SECURITY_ANALYSIS_REPORT.md`, which is kept by hand.
`--check` is also accepted and means read-only.

`test` runs diagnostic tests. It needs Manifest Cloud.

## Optional Cloud And Agent

```bash
manifest cloud config|status|generate
manifest agent init|auth|status
```

These commands need Manifest Cloud plugins. Ordinary repo and fleet releases do not.

## Machine-Readable Catalog

Every install writes a catalog for coding assistants and scripts to
`~/.manifest-cli/ide/`:

| File | What it holds |
| ---- | ------------- |
| `manifest-cli-commands.json` | `top_level_commands` (the complete set of commands; the test suite keeps it equal to the commands Manifest accepts), `commands` (the command strings to prefer), the preview and apply flags, and the exit codes |
| `manifest-cli-commands.md` | The preferred commands, in groups, each with a one-line purpose |
| `AGENTS.md`, `CLAUDE.md` | A short guide for coding assistants: commands preview by default, `-y` applies, where the docs are, and what to do on exit code `4` (the documentation handoff) |

An agent or a script should read the JSON file. It should not parse the output of
`manifest help`.

## Environment

Frequently used variables:

| Variable | Purpose |
| -------- | ------- |
| `MANIFEST_CLI_AUTO_CONFIRM` | Allows an apply whose target is unclear (a detached HEAD, or no `origin`), and only **after** `-y`. An ordinary apply does not need it, and it cannot start an apply |
| `MANIFEST_CLI_PREVIEW_EXIT_CODE` | `zero` (default) or `distinct`. Sets the exit code of a plan that was given no consent. See Exit Codes |
| `MANIFEST_CLI_SHIP_FOLLOWUP_PATCH` | Applies only to Manifest's own repository. After a release that is not a `patch`, Manifest may run one more `patch` release with the newly installed CLI. `false` turns that off (default on) |
| `MANIFEST_CLI_DOCS_HANDOFF` | `off` (default), `auto` or `always`. Pauses a release before the release commit, so that whoever is running it can finish the documentation. See exit code `4` under Exit Codes. You can also set it as `docs.handoff`, including in a committed config file, because it names no program to run |
| `MANIFEST_CLI_DRIVER` | Overrides Manifest's guess about who is running it: `none`, `ci`, `claude-code` or `other-agent`. It is an environment variable only and never a config key, because a committed file must not state who is at the keyboard. It affects only the `auto` handoff default, and never a safety control |
| `MANIFEST_CLI_DOCS_GENERATE_SITE` | Generation of the documentation website. On by default; set it to `false` to turn it off |
| `MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES` | Asks GitHub to enable Pages, through `gh api` |
| `MANIFEST_CLI_GITHUB_ACTIONS_WAIT` | Waits for GitHub Actions to finish during a release (default off) |
| `MANIFEST_CLI_ENV_PREFIX` | The prefix policy. Empty means the prefix is derived from the repository's directory name (the default, and on). A value of your own replaces it. `off` turns the policy off |
| `MANIFEST_CLI_ENV_NAMING_ENFORCEMENT` | `strict` (default, blocks) or `warn` (reports only) |
| `MANIFEST_CLI_ENV_NAMING_ALLOW` | More allowed names, separated by commas. An entry that ends in `_` is a prefix |

Every setting has a matching variable. To see the variable for one key, and which layer
currently supplies its value, run `manifest config describe <key>`.
