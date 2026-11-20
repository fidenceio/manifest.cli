# Migration Guide

This guide is for two kinds of reader.

- **You are upgrading Manifest.** Read the sections below from the top. They run from
  the newest change to the oldest. Each one says what changed, who is affected, and
  what to do. Stop when you reach the version you are upgrading from.
- **You are new to Manifest.** Read two sections first:
  [The preview / apply model](#the-preview--apply-model) and
  [The release gate](#the-release-gate). Most of the changes in this guide follow from
  one rule those sections explain:

**Manifest shows you the plan and changes nothing until you explicitly say go.**

## Manifest no longer writes `k8s/env` files, and `env.secrets` is removed — the newest change; its release is the first CHANGELOG entry that mentions `env export`

**What changed.** `manifest env generate` no longer writes anything under `k8s/env`.
It used to write a ConfigMap, an ExternalSecret, a kustomization and a kustomize
Component there, using the eight `env.secrets` settings. Those settings are no longer
read. How variables reach a cluster is your platform's design, and a release tool
should not own it. This is a breaking change.

What Manifest still does with the spec's `env:` block:

- `env generate` writes `.env.example` and the Dockerfile `ARG`→`ENV` block.
- `env validate` checks the prefix policy, those two outputs, and `.gitignore`.
- `env export` is new. It prints the variables as JSON, so a tool of your own can
  render deployment files from them.

| Removed | What happens now |
| --- | --- |
| `k8s/env/configmap.yaml`, `k8s/env/external-secret.yaml`, `k8s/env/kustomization.yaml`, `k8s/env/component/kustomization.yaml` | Never written, updated, compared or deleted. Files already in your repository stay exactly as they are |
| `env.secrets.provider`, `.store.kind`, `.store.name`, `.api_version`, `.path`, `.property`, `.refresh_interval`, `.env_label` | Not read. `manifest config doctor` reports `env.secrets` as obsolete |
| The refusal when secrets are declared and no store is configured | Gone. `env generate` runs without any store setting |
| Store and path details in the `.env.example` comment for a secret | Replaced by one fixed line that names no store |

**Who is affected.**

- Anyone whose repository has a `k8s/` folder and a spec with an `env:` block. Manifest
  wrote `k8s/env` files there whether or not you set `env.secrets`.
- Anyone who sets `env.secrets`, in a repository or at a fleet root.
- Anyone whose CI runs `manifest env generate --check` or `manifest env validate` and
  relies on it to catch an out-of-date `k8s/env` file.
- Anyone whose spec declares a secret. The `.env.example` comment for it changes.
- Anyone whose spec sets `default: false` on a variable. `.env.example` now carries that
  value.

**What to do.**

- **Decide who renders your `k8s/env` files now.** The files in your repository are
  yours. Manifest will not change them, so they keep working as they are. They will
  also not follow the spec any more: when you add a variable, nothing updates them.
- **To keep generating them, take the reference script.** Copy
  `examples/env-k8s-render.sh` from the Manifest CLI into your repository. It reads
  `manifest env export` and writes those four files. Pass it the values your
  `env.secrets` settings held:

  ```bash
  manifest env export | ./env-k8s-render.sh \
      --provider external-secrets --store-name <store-name> \
      --path 'secret/data/{env}/{identity}/{group}' --env-label env
  ```

  For the same spec and settings it writes what Manifest wrote, apart from the comment
  lines and two values that Manifest wrote wrongly:

  - A `default: false` is written as `"false"`. Manifest wrote an empty string. **This
    changes the value your workload receives.** Check any variable with that default
    before you apply the new file.
  - A default that contains a `"` or a `\` is escaped. Manifest wrote it unescaped, which
    made the file invalid YAML.

  The script replaces a file that Manifest generated, and it leaves a file you wrote by
  hand alone. It is an example for you to own. Manifest does not run it or check its
  output.
- **Check the names and the secret paths if your folder and repository names differ.**
  Manifest named the objects after the checkout's folder, such as `<folder>-env`, and
  put the same name wherever the secret path uses `{identity}`. The export's `identity`
  is the repository's name. If the two differ, the script renders new object names and
  new secret paths, so it would read your secrets from a different place in the store.
  Pass `--identity <folder name>` to keep the old ones.
- **Add your own drift check.** `env generate --check` and `env validate` no longer look
  at `k8s/env`. If you relied on that, run the script with `--check` in CI. It writes
  nothing and exits `1` when a file is out of date. Run the script once without
  `--check` first: until it has rewritten the files that Manifest generated, `--check`
  reports all of them, because their comment lines differ.
- **Remove `env.secrets` from your configs.** Run `manifest config doctor --file <path>`
  on each config that sets it. Add `--fix -y` to delete the setting. `--fix` also applies
  the doctor's other safe repairs to that file; add `--dry-run` to see them first. Do
  this for the fleet root's `manifest.config.yaml` as well as each repository's. Unset
  any `MANIFEST_CLI_ENV_SECRETS_*` environment variables in CI.
- **Run `manifest env generate -y` once, if your spec declares a secret or sets
  `default: false`.** The comment above each secret in `.env.example` is now
  `# secret — set from the platform's secret store; never a literal value in any .env`.
  A variable whose default is `false` is now written as `NAME=false`; it used to be
  written with no value. Until you regenerate the file, `env generate --check` and
  `env validate` both exit `1`, so a CI job that runs either one fails.
- **Expect a note until you have done the above.** While a repository holds a file that
  Manifest generated under `k8s/env`, or a config that sets `env.secrets`,
  `env generate` and `env validate` print a note on standard error. It lists the files
  and the settings it found. It does not change the exit code. It stops when the files
  carry another header (the script writes its own) and the settings are gone.
- **If a script parsed the old output, update it.** `env generate` no longer prints
  `store drift:` or `path drift:` lines, and `env validate` no longer prints
  *secret store not configured*.

## `ship repo resume` and `ship fleet resume` are removed — its release is the first CHANGELOG entry that mentions `unfinished release`

**What changed.** The two `resume` commands are gone. The ordinary ship command now
finishes an unfinished release. An *unfinished release* is one that Manifest tagged in
your local repository and then stopped before it finished. The usual cause is a failed
push, a release gate that failed after the push, or a failed Homebrew tap publish. This
is a breaking change.

| Removed | Use instead |
| --- | --- |
| `manifest ship repo resume` | `manifest ship repo <patch\|minor\|major\|revision>`. The plan shows the unfinished release. Add `-y` to finish it. |
| `manifest ship fleet resume` | `manifest ship fleet <patch\|minor\|major\|revision>`. The plan marks each affected member `would finish`. Add `-y` to finish them. |

**Who is affected.**

- Anyone who runs either `resume` command, by hand or from a script.
- Anyone with a release that an older Manifest left unfinished.
- Anything that reads the `Resume:` lines in a failure report.

**What to do.**

- **Replace the removed commands.** Manifest refuses the word `resume` by name. It
  exits `1`, prints the replacement, and runs nothing else.
- **Add `-y` where you want the finish to happen.** The old `ship repo resume` pushed
  the branch and tag as soon as you typed it. The replacement prints a plan and stops.
  It pushes only when you add `-y`.
- **Expect a finish to stop after finishing.** A finish does not apply the release
  type you typed. `manifest ship repo minor -y` on a repository with an unfinished
  `1.2.4` finishes `1.2.4` and stops. It does not also cut `1.3.0`. Run the command
  again for the next release. A finish and a release both exit `0`, so the exit code
  does not tell them apart. The output of a finish ends with
  `finished. Nothing was bumped.` If a script assumes that one command means one new
  version, have it check for that text.
- **Finish a stranded release before you upgrade.** Manifest now recognises an
  unfinished release by a record it writes itself. A publishing ship writes
  `.git/manifest-ship/in-flight` just before it creates the tag. It removes the file
  when the release is complete. A release that an older Manifest left stranded has no
  such record, so the new version does not offer to finish it. Either finish it with
  `manifest ship repo resume` before you upgrade, or push it by hand afterwards:

  ```bash
  git push origin <branch> <tag>
  ```

  A release you push by hand gets no GitHub Release from Manifest. The next release
  publishes its own.
- **Start from a clean tree on the release branch.** A finish pushes commits that
  already exist. If the working tree has other changes, or `HEAD` is detached, or the
  tag is not in the current branch's history, the plan says `BLOCKED` and gives the
  reason.
- **Do not use `--local` to finish.** Finishing is a push, so `--local` cannot do it.
  With `--local`, `ship repo` refuses when the repository has an unfinished release.
  `ship fleet --local` refuses before it touches any member.
- **Use `--force-bump` to skip the finish.** It leaves the unfinished release as it is
  and cuts the next release.
- **Finish from the checkout that started the release.** The record is inside that
  checkout's `.git` folder. A fresh clone, or a different CI runner, does not have it
  and will not offer to finish the release. Push it by hand from there, as above.
- **Expect the post-push check to run again.** If `release.gate` is `remote-ci` or
  `all`, a finish runs that check after the push, as a release does. If the check fails,
  nothing is published and the release stays unfinished. The check reads the CI result
  of the commit the tag points at. A fix you commit on top does not change that result:
  to release the fix, add `--force-bump` and cut the next version.
- **Commit only what you want pushed.** A finish pushes the branch. Commits you made
  after the tag are pushed with it, and the plan lists them first.
- **Update anything that parses failure reports.** The single-repository failure report
  now prints a line that starts `Finish:` and names `manifest ship repo patch`. It used
  to print `Resume:  manifest ship repo resume`. The fleet recovery report now prints
  `Finish:` and `Retry:`. It used to print `Resume:` and `Or retry:`. For a member that
  failed before its push, the fleet report prints only `Retry:`. For a member that
  failed while finishing, it prints the category `unfinished`. A release stopped by the
  post-push check now reports the step `release_gate_post_push`, in the report's
  `failed step:` line and the status file's `failure_step`. It used to report
  `release_gate`, the name of the check that runs before the version is raised. Its
  recovery advice no longer prints `git tag -d` or `git reset --hard`.

**One more change in the same release.** Each `ship repo` run writes a log under
`~/.manifest-cli/logs/`. That log now records every step and the result. From v52.0.0
until this release it held only its five header lines.

This has one visible effect. To record a step's error output, Manifest holds it until
the step ends, and then prints it. During a long step, such as the release gate, you
see that step's error output when the step finishes, not while it runs. Normal output
still appears as it happens.

## `env generate` refuses a flag that is not a boolean and leaves hand-authored files alone (v63.0.2)

> **Later change.** The parts of this section about `k8s/env` files and `env.secrets` no
> longer apply. A later release removed that rendering. See the section
> *Manifest no longer writes `k8s/env` files, and `env.secrets` is removed*, above.

This release changes two things that `manifest env generate` did without telling you.

### A `secret`, `required` or `public` flag must be a boolean

**What changed.** The flags `secret`, `required` and `public` in an environment spec
accept `true`, `True`, `TRUE`, `false`, `False`, `FALSE`, and the same words in quotes.
Manifest refuses any other value and names it. Earlier releases read every value except
lowercase `true` as false. That included `secret: yes`, `secret: on`, `secret: 1` and
`secret: True`. Such an entry was treated as not secret. Its `default` was written into
`k8s/env/configmap.yaml` and into `.env.example` as a live assignment, and the command
exited `0`.

**Who is affected.** Anyone whose spec has ever spelled one of these flags in any way
other than lowercase `true` or `false`.

**What to do.**

- **Check what an earlier release generated, and rotate any exposed secret.** If a spec
  ever carried a secret flag in one of those spellings together with a `default`, that
  value is in the generated ConfigMap and in `.env.example`. If you committed those
  files, it is in your git history too. Rotate it.
- **Write `true` or `false`.** A spec with any other value makes `env generate` exit
  `1` and write nothing. This holds for the preview, for `--check` and for `-y`.
  `env validate` fails, and `manifest init` does not write `.env.example`.
- **Expect `--check` to fail after the upgrade if a spec uses `True` or `TRUE`.** This
  happens before you run `-y`, because those entries are now read as true:
  - A `secret: True` entry is now a secret. With no `env.secrets` configured, `--check`
    exits `1` because no secret store is set. With `env.secrets` configured, `--check`
    reports the ConfigMap, `.env.example` and the secret bridge as out of date. Run
    `manifest env generate -y` to move the entry out of the ConfigMap.
  - `required: True` and `public: True` entries also show as out of date until you run
    `manifest env generate -y`.

### `env generate -y` replaces only the files Manifest wrote

**What changed.** `env generate -y` replaces `.env.example` or a file under `k8s/env`
only when the file's first line is the header Manifest writes. Earlier releases
replaced `.env.example` and every `k8s/env` file except `kustomization.yaml`, whatever
they contained.

**Who is affected.** Anyone who keeps a hand-written file at one of those paths, and
anyone who runs `env generate` on macOS.

**What to do.**

- **Know how a hand-written file is treated.** The plan names it as
  *hand-authored, left untouched*. `-y` does not write it, and `--check` does not count
  it as out of date. To hand a file back to Manifest, delete it and run
  `manifest env generate -y`.
- **Reference your own secret bridge from your own kustomization.** The generated
  `k8s/env/kustomization.yaml` lists only what Manifest renders. If you write
  `k8s/env/external-secret.yaml` yourself and Manifest renders no secret bridge
  (`provider: none`), add your file to a kustomization you own.
- **Nothing to do for generated files.** Files that any earlier release generated carry
  the header and are updated as before. An empty file at one of those paths is
  replaced.
- **Expect failures to be reported as failures.** A file that cannot be written makes
  `generate -y` exit `1`. It used to print *wrote*. A directory, an unreadable file or
  a symlink that points to nothing at one of those paths is named in the plan and makes
  `--check` exit `1` as well.
- **On macOS, run `manifest env generate -y` again if `--check` kept failing on the
  Dockerfile.** Earlier releases could not update an existing Dockerfile bridge block
  on macOS. The command warned, exited `0`, and `--check` kept failing. It now updates
  the block. The Dockerfile also keeps its file permissions. It used to come back
  readable by the owner only (`600`).

## The release commit stages only what the release wrote (v63.0.1)

**What changed.** `manifest ship` makes two commits. The first is the auto-commit of
whatever was pending when you asked to ship. The second is the release commit. The
release commit now stages, by name, only the places the release itself writes:

- `VERSION` and the `version.sync` targets
- `CHANGELOG.md`
- the README
- the docs folder and the docs archive folder
- the docs-site source folder and its Pages workflow
- `docs.review.report_dir`, when you have set it

Every other changed file is named in a line that reads
*"Left out N files this release did not write"* and stays in your working tree. The
ship still completes, and it lists those paths again at the end.

Earlier releases staged the whole tree for the release commit. A file written between
the two commits was committed and shipped without review. Such a file could come from
the merge that syncs with the remote, a release-notes provider command, a hook, an
editor or another session.

A second fix rides with this one. A pending file whose name git quotes (a name with a
space, a quote or a non-ASCII byte) is now included in the auto-commit like any other
file. Earlier releases wrongly reported it as *"changed after this ship was requested"*
and held it out of the auto-commit.

**Who is affected.** Anyone who relies on a tool that writes a file outside those
places during a ship and expects the release to commit it.

**What to do.** Choose one:

- Commit the file yourself.
- Make the tool write before the ship starts.
- Set `git.allow_gate_drift: true`. This restores whole-tree staging for both commits.

## The secret store is configuration (v63.0.0)

> **Later change.** Nothing in this section applies any more; do not follow its steps. A
> later release removed `env.secrets` and the files it configured. See the section
> *Manifest no longer writes `k8s/env` files, and `env.secrets` is removed*, above.

**What changed.** The secret store and secret path in `k8s/env/external-secret.yaml`
now come only from `env.secrets` in `manifest.config.yaml`. Set `env.secrets` at the
fleet root. A repository can override it, key by key, and the repository's value wins.
There is no built-in store.

Earlier releases wrote one vendor's store name (`openbao-customer`) and one fixed path
layout (`secret/data/{env}/<repo>/<group>`) into every generated file, and nothing
filled `{env}` for each environment. If you patched those files by hand, the next
`generate -y` overwrote your patches.

**Who is affected.** Anyone whose environment spec declares secret variables.

**What to do.**

- **Configure `env.secrets` before you generate.** A spec that declares secret
  variables with no `env.secrets` configured makes `env generate` exit `1` and write
  nothing. This holds for the preview, for `--check` and for `-y`. `env validate`
  reports it as *secret store not configured*, not as out-of-date output.
- **To keep the old layout**, set these keys at the fleet root, then run
  `manifest env generate -y`:

  ```yaml
  env:
    secrets:
      provider: external-secrets
      store:
        name: openbao-customer
      path: "secret/data/{env}/{identity}/{group}"
      env_label: <label>
  ```

- **If secrets reach the workload some other way**, set `env.secrets.provider: none`.
  Manifest then writes no secret bridge at all.
- **Expect the generated files to differ.**
  - `remoteRef.key` and `remoteRef.property` are double-quoted.
  - A new `k8s/env/kustomization.yaml` makes the bridge directory a base that
    kustomize can build.
  - A new `k8s/env/component/kustomization.yaml` fills `{env}` for each environment.
  - Each overlay must label the bridge one layer down and include the Component above
    it. A single-layer overlay fails under kustomize. The exact two files are in the
    [Command Reference](COMMAND_REFERENCE.md).
  - Secret comments in `.env.example` carry the configured store and path, not a vendor
    name.

## The scaffolded release gate does not write to your machine (v63.0.0)

**What changed.** `manifest init` scaffolds a release gate script,
`scripts/run-tests.sh`, that runs your checks in a container. A newly scaffolded gate
mounts your checkout read-only, copies it inside the container, and runs the checks in
the copy. Nothing the checks write reaches your machine.

A gate scaffolded by an earlier release mounted the checkout read-write. Every run left
empty `node_modules/` and `target/` directories in the checkout (owned by root on
Linux). Any check that writes into its tree, such as `pytest`, `tox`, `dotnet build` or
a `make test` that touches files, wrote onto your machine.

**Who is affected.** Any repository whose `scripts/run-tests.sh` was scaffolded before
v63.0.0. Manifest never overwrites an existing `scripts/run-tests.sh`, so such a
repository keeps the old script until you replace it.

**What to do.**

1. Check whether a repository has the old script. This command prints a line if it
   does:

   ```bash
   grep -F -- '-v /workspace/node_modules' scripts/run-tests.sh
   ```

2. Move your project checks out of the file and keep them somewhere safe.
3. Delete `scripts/run-tests.sh`.
4. Run `manifest init repo -y`.
5. Put your checks back under the `PROJECT CHECKS` heading in the new file.

**Do not copy only the new `docker run` lines into an old file.** The read-only mount
also needs the copy block at the top of the inner script. Without that block, every
check that writes a file fails on a read-only file system.

**The opt-out.** Set `release.gate_host_writes: true`, or
`MANIFEST_CLI_RELEASE_GATE_HOST_WRITES=true`, to mount the checkout read-write again.
Use it for a checkout whose `.git` directory is very large, because the default gate
copies the checkout on every run.

## Command cleanup: removed commands (v62.0.0) and single-letter switches (v62.1.0)

**What changed.** Every command has the form `manifest <verb> <scope> [action]`. Every
switch has exactly one spelling, the full word. The only short switch is `-y`.
The spellings in the table below are removed, and there are no compatibility aliases.
The command and scope changes shipped in v62.0.0. The single-letter switches were
removed in v62.1.0.

**Who is affected.** Any script or habit that uses a spelling in the left column.

**What to do.** Use the replacement in the right column before you upgrade past
v62.0.0.

| Removed spelling | Replacement |
| --- | --- |
| `manifest prep repo` | `manifest init repo --connect` |
| `manifest prep fleet` | `manifest init fleet --connect` |
| `manifest revert` | `manifest revert repo [<tag>]`. It previews by default; `-y` applies. |
| `manifest first` | `manifest init` for guided setup. `init repo` and `init fleet` remain. |
| `manifest refresh repo` | `manifest docs`, `manifest docs metadata`, and `manifest docs cleanup`, as needed |
| `manifest sync` | `manifest init repo --connect` |
| `manifest time` | `manifest config time` |
| `manifest fleet help` | `manifest help` and the fleet commands, which put the action first |
| `manifest ship <bump>` | `manifest ship repo <bump>` |
| `manifest recipe run <id>` | The recipe's named command. `recipe list`, `recipe show` and `recipe explain` remain. |
| `manifest refresh fleet` | `manifest update fleet`, then `manifest docs fleet` as needed |
| `plan fleet --apply` / `--do` | `plan fleet -y` / `--yes` |
| `reconcile fleet --apply` / `--do` | `reconcile fleet -y` / `--yes` |
| `ship fleet --noprep` | `ship fleet --require-clean` |
| `ship repo -p` / `-m` / `-M` / `-r` | `ship repo patch` / `minor` / `major` / `revision` |
| `ship repo -i` | `ship repo --interactive` |
| `-h` / `-help` / `-version` / `-v` / `-V` | `--help` / `--version`. The bare words `help` and `version` remain. |
| `init -f`, `init fleet -n` / `-p` | `--force`, `--name` / `--parallel` |
| `discover fleet -q`, `update fleet -q` | `--quiet` |
| `status fleet -v` | `--verbose` |
| `init fleet -t` | No replacement. `manifest init fleet` does not accept `-t` or `--template`. |

Details you need to act on:

- **A removed spelling is refused, never mapped.** Manifest reports it as an unknown
  command or option, for example `Unknown option: -q`, and exits `1`.
- **One command family forwards flags it does not know.**
  `manifest pr create|status|checks|ready|merge|update` passes any flag it does not
  recognise to `gh pr …`. So `-h` there shows the help text of `gh`, not of Manifest.
- **Preview and apply flags cannot be combined.** Commands that change something
  preview by default. `-y` or `--yes` applies, and `--dry-run` asks for the preview by
  name. Passing both is an error, in either order.
- **`revert` needs a scope, and it previews.** `revert repo` shows what it would check
  out. A script that applies must name the tag.
- **`revert fleet <manager-commit>` restores a whole fleet.** It restores each member
  from the `manifest.fleet.snapshot.json` file in that manager commit, then restores
  the manager itself. A fleet ship records that file after the members finish and
  includes it in the manager's coordination commit. An older manager commit that lacks
  the file cannot rebuild fleet versions. Fleet revert needs clean working trees. If
  some checkouts fail, it exits `2` and reports them.
- **The guided setup is plain `manifest init`.** It keeps the same preview, target
  checks, audit record and fleet membership review.
- **Two recipes changed.** The connect recipe is named
  `manifest.builtin.init.repo.connect`. Its old name was `manifest.builtin.prep.repo`.
  The recipe `manifest.builtin.refresh.repo` is deleted. You can still list, show and
  explain recipes. You cannot run one by id.

**Fleet ships include the manager repository (v62.0.0).**
`manifest ship fleet <type> -y` ships the manager coordination repository after the
members. It does so even when every member is skipped or `fleet.versioning` is `none`.

- Only the declared coordination files are staged.
- `manifest ship fleet manager` commits and pushes the fleet root only. Use it to
  recover when the root step failed.
- If the manager commit or push fails, the exit code is `1` when no member released and
  `2` when at least one member released.
- `--local` commits the root without pushing.
- Root commit subjects have the form `chore(fleet): ...`. Sign-off follows the
  repository's `format.signOff` setting.

## `prep` is part of `init` (v62.0.0)

**What changed.** `manifest prep` is removed. Its work is the **connect phase** of
`manifest init`. Setup has two phases: the scaffold phase writes local files, and the
connect phase talks to the remote.

```bash
manifest prep repo             ->  manifest init repo --connect
manifest prep fleet            ->  manifest init fleet --connect
manifest prep fleet --parallel ->  manifest init fleet --connect --parallel
```

**Who is affected.** Any script that calls `manifest prep`, and any script that calls
`manifest init repo -y` and expects it to stay offline.

**What to do.**

- **Replace `manifest prep <scope>`** with `manifest init <scope> --connect` before you
  upgrade past v62.0.0.
- **Add `--no-connect` where you want a local scaffold only.** `manifest init repo -y`
  now connects `origin` and runs readiness checks by default. If the repository has no
  `origin`, it creates a **private** GitHub repository. Pass `--remote URL` to connect
  an existing repository. A pipeline that only wants the scaffold must run
  `manifest init repo --no-connect -y`.
- **Fleet connection stays opt-in.** `manifest init fleet -y` makes no network call
  unless you pass `--connect` or `--create-repo-private` / `--create-repo-public`.
- **Know the one exception.** `manifest init fleet --create-repo-private` and
  `--create-repo-public` create each member's GitHub repository during the scaffold
  phase (Phase 2), not during the connect phase.
- **Connecting also scaffolds.** `init repo --connect` and `init fleet --connect` run
  the local scaffold phase too. It keeps existing files unless you pass an explicit
  overwrite option.
- **Expect these behaviours from the connect phase.**
  - A new, empty remote is not pulled.
  - An existing remote is connected by fast-forward only. A remote failure or a history
    conflict returns a non-zero exit code.
  - Repository init checks the Git identity, the branch, the version and the real
    release check. It makes no release commit, tag, version bump or push.
  - If the project has no verification to run, init reports the setup as incomplete,
    not as a success.
- **Remove `deprecations.quiet`.** This setting and its environment variable silenced
  warnings for the old aliases. They are removed together with the aliases.

## An environment override that contains a space now takes effect (v62.0.0)

**What changed.** Manifest reads every `MANIFEST_CLI_*` environment variable as its
highest-priority configuration layer. From v47.11.0 through v61.2.1, a value that
contained a space was read wrongly on any host with GNU coreutils. The value was
captured with literal quote marks around it, it outranked the correct value from your
config files, and it then failed validation. From v62.0.0 the value is read exactly,
including spaces, newlines and quotes.

**Who is affected.** Every Linux install and every Homebrew install on macOS. The
Homebrew formula depends on `coreutils` and puts the GNU tools first on `PATH`. Stock
macOS without Homebrew coreutils read a value with a space correctly. A value that
contained a newline was corrupted on every platform.

A concrete case: an exported `MANIFEST_CLI_DOCS_RETAIN="10 versions"` was ignored.
CHANGELOG pruning was skipped, with a warning that named a value you never typed.

**What to do.**

- **Review the `MANIFEST_CLI_*` variables you export.** After the upgrade, an override
  that was being ignored takes effect. If you had stopped expecting one to work, expect
  it to work now.
- **Upgrade every machine.** Every release from v47.11.0 through v61.2.1 has the
  defect. Upgrading is the only fix.

`manifest uninstall` had a related defect, fixed in the same release. Its sweep of
exported variables skipped any `MANIFEST_*` name that contained a digit, and it could
misread a value that contained a newline as more names to unset. It now reads exported
names exactly and skips read-only module constants, so the sweep cannot stop an
uninstall partway.

## v61: plainer changelog entries, fleet exit code `2`, and the pause code `4`

v61 made seven changes. The first four are visible without any configuration. The
fifth applies only to a fleet root with a pre-commit hook. The last two apply only if
you turn them on.

**A release cut with no commits since the last one no longer repeats that release's
changelog.**

- *What changed.* If you cut a release straight after another one, for example with
  `--force-bump` on a clean tree, the new CHANGELOG entry reads
  `**Release Type:** <type> — no user-facing changes.` Before v61 the new entry claimed
  every bullet of the previous release as its own. It exited `0` with no warning.
- *What to do.* **If you published a release this way before v61, its CHANGELOG entry
  is wrong.** Manifest cannot correct it, because the text is already in your published
  changelog and release body. Correct it by hand if it matters to your readers. Nothing
  changes for an ordinary release.

**Changelog bullets no longer claim product features.**

- *What changed.* Before v61, Manifest guessed a product claim from the paths a release
  touched. For example, three changed module files produced the bullet
  *"Add GitHub Release publishing support"*, whether or not that had happened. Those
  rules are deleted. An entry now describes only what was touched (documentation and
  examples, shell completions, tests, the changelog), gives a count when nothing else
  fits, and lists the real commit subjects.
- *What to do.* Expect CHANGELOG entries and ship previews to read differently from
  v60 and earlier. If a tool of yours parses the old bullets, stop: they were guesses.

**`ship fleet` exits `2` when it completed only in part.**

- *What changed.* Exit `2` means one or more members released and then a later member
  or the fleet root failed. Before v61 the command exited `0` in that case.
- *What to do.* Check any pipeline that reads the exit code. A pipeline that treats
  every non-zero code as total failure now sees a partial fleet release as a failure.
  A pipeline that treated `0` as "everything published" is now correct.

**The closing output of a fleet ship changed.**

- *What changed.* The line `✅ Fleet ship workflow complete.` prints only when the run
  completed. A partial run, or a run that did nothing, ends with a block that names the
  members released, skipped and failed, and the outcome for the root. Before v61 the
  line printed every time.
- *What to do.* If a tool searches the output for that line to confirm success, check
  it before you upgrade. It will now fail on a run that did not succeed.

**A hook failure at the fleet root is reported as a hook failure.**

- *What changed.* This applies when the fleet root has a pre-commit hook that enforces
  conventional commit subjects and the hook rejects the coordination commit. Manifest
  shows the hook's own output and names the hook as the cause. It unstages exactly what
  it staged and exits `2`. Before v61 it guessed at `user.name` and exited `0`.
- *What to do.* Nothing on v61 makes that commit pass: the fleet root still stops at
  the coordination commit. From v62.0.0 the root commit subject has the conventional
  form `chore(fleet): ...`, and the exit code is `1` when no member released.

**`fleet.coordination_files` is a new key.**

- *What changed.* This key in a committed config adds files to what the coordination
  root commits and pushes. The default is the same five files as before, so nothing
  changes for an existing fleet.
- *What to do.* If you adopt it, know its rules. It is an allowlist of plain file
  names. Directories and names shaped like secrets are refused. The manager's preview
  shows the resolved list before any apply. The full rules are in the
  [User Guide](USER_GUIDE.md).

**Exit code `4` is a pause, not a failure.**

- *What changed.* `docs.handoff` is a new setting. Its default is `off`, so an upgrade
  changes nothing. Set it to `always`, or to `auto`, and a ship stops before the
  release commit. `auto` pauses only when an AI agent is driving, and never in CI. The
  paused ship writes a brief under `.git/` that names what the documentation still
  needs, and exits `4`. It makes no commit, no tag and no push. You edit the
  documentation and run the same command again. Manifest checks the result and then
  releases.
- *What to do.* **Before you turn this on, teach anything that reads a non-zero exit
  code as a broken release about `4`.**

The full exit-code table is in the
[Command Reference](COMMAND_REFERENCE.md#exit-codes).

## A committed config can no longer name a program to run

**What changed.** Five config keys name something Manifest runs during a ship:

| Key | What it names |
| --- | --- |
| `release.gate_command` | the test command the release gate runs |
| `docs.review.command` | the documentation-review program |
| `docs.release_notes.command` | the release-notes program |
| `docs.review.provider` | the selector that makes the review command reachable |
| `docs.release_notes.provider` | the selector that makes the notes command reachable |

Manifest honours these five keys **only from a layer you own**:

- your global config under `~/.manifest-cli/`
- any `*.local.yaml` file, which the scaffold adds to `.gitignore`
- the process environment

If one of them is set in a **committed `manifest.config.yaml`**, in a project or at a
fleet root, Manifest ignores it. It prints the refusal with the key and the layer the
key came from. The refusal is never silent.

The reason is safety. A committed config travels with a clone, and the project layer
overrides your global one. Without this rule, a repository you cloned could choose what
runs on your machine during a ship. [SECURITY.md](../SECURITY.md) states the full
boundary. This has been the rule since v59.10.1. A release older than that still runs
the programs a committed config names.

**Who is affected.** Any repository that sets one of the five keys in a committed
`manifest.config.yaml`. Fleets are the most likely case. Fleet members are cloned from
URLs that the fleet config supplies, so a member's committed config is exactly a config
that arrived with a clone.

**What to do.** Choose one of three options.

1. **Move the key to a file you own.** This is the lasting fix. Leave the policy key
   `release.gate` where it is. Only the five keys above are affected.

   ```yaml
   # manifest.config.local.yaml — gitignored, yours, honoured
   release:
     gate_command: "pytest -q"
   ```

   In a fleet, move each member's gate command to that member's
   `manifest.config.local.yaml`.

2. **Trust one repository for a single run**, without editing anything:

   ```bash
   MANIFEST_CLI_TRUST_REPO_COMMANDS=1 manifest ship repo patch -y
   ```

3. **Trust it once and have Manifest remember:**

   ```bash
   MANIFEST_CLI_TRUST_REPO_COMMANDS=remember manifest ship repo patch -y
   ```

How `remember` works:

- It honours the committed keys for this run. It also records them in
  `~/.manifest-cli/trusted-repo-commands.tsv`. Later runs honour them with no variable
  set.
- The record is keyed on the repository's remote and on a digest of the exact values
  you accepted. It stays on your machine. It follows the repository, not the clone, so
  a fresh clone of the same remote is still trusted.
- If any of the five values changes in the committed file, the record stops matching.
  Manifest refuses the keys again and says they changed since you trusted them. Review
  the new values and run with `remember` again to record them.
- `MANIFEST_CLI_TRUST_REPO_COMMANDS=forget` deletes the repository's row.
- Both the preview and the applied run say, beside each committed program, whether it
  is trusted for this run or by your record.
- **The record is written when the configuration loads, so `remember` on a preview
  records too.** Read the preview's program list first. Run with `remember` only when
  you agree with what it names.

Trust is an environment variable on purpose. A committed file must not be able to
grant itself trust. For that reason there is no config key for trust, and none for the
location of the record.

## The preview / apply model

Every command that could change something, such as `init` or `ship`, prints what it
*would* do and then stops. Nothing is written until you ask:

```bash
manifest ship repo patch        # plan only: no writes, no commit, no tag, no push
manifest ship repo patch -y     # do it: performs the release
```

| What you type | What it means |
| -------- | ------- |
| nothing extra | Plan only. Prints what would happen and changes nothing. |
| `--dry-run` | The same thing, written out. Use it in scripts so a reader can see the intent. |
| `-y` / `--yes` | Do it. Performs the planned work. |
| `--local -y` | Do only the local part. No tag, no push, no GitHub Release, no Homebrew publish. |

You cannot pass `--dry-run` and `-y` together. Plan-only is already the default.
Manifest refuses the combination instead of guessing which one you meant.

### `-y` does not then ask "are you sure?"

`-y` is the confirmation. Manifest applies at once, whether or not you are sitting at a
terminal. This is deliberate: a command that waits for input in CI (an automated build
pipeline) hangs the pipeline.

For an ordinary repository, one on a named branch with an `origin` remote, `-y` alone
is all you need.

There is one exception. If Manifest cannot tell what it would act on, it **refuses**.
It does not prompt. Two cases cause that:

- **Detached HEAD.** Your checkout sits on a specific commit, not on a branch, so there
  is no branch to push.
- **No `origin` remote** on a command that needs to push somewhere.

Fix the repository, or authorise the run with the variable below.

### `MANIFEST_CLI_AUTO_CONFIRM` is not a way to apply

`MANIFEST_CLI_AUTO_CONFIRM=1` does exactly one job. It authorises an *ambiguous* target
like the two above, and only **after** you have already asked for apply with `-y`.

It cannot start an apply. A command without `-y` still only prints a plan, even with
the variable set. You do not need the variable for a normal apply.

```bash
manifest ship repo patch -y                              # ordinary repo: applies, no prompt
MANIFEST_CLI_AUTO_CONFIRM=1 manifest ship repo patch -y  # also allows an ambiguous target
```

Because of this separation, a variable that sits in a CI environment can never publish
a release by itself.

For a fleet, `manifest ship fleet <type> -y` treats that single `-y` as consent for
every selected member. It does not ask again for each one.

## The release gate

Before it publishes, Manifest can require that something has passed. One setting
controls this: `release.gate`, or the variable `MANIFEST_CLI_RELEASE_GATE`.

| Value | What must pass |
| ----- | -------- |
| `local-tests` (default) | Your project's tests. They run **first**: before the automatic commit, before syncing with the remote, and before any version change. If they fail, the run stops and your repository is untouched. |
| `remote-ci` | GitHub's checks on the pushed commit must pass before the GitHub Release and the Homebrew publish. Note that the tag has already been pushed by this point. |
| `all` | Both of the above. |
| `none` | Nothing. Manifest prints a loud warning and records the bypass in the audit log. |

For `local-tests`, Manifest looks for `./scripts/run-tests.sh`. If your project keeps
its tests elsewhere, set `release.gate_command`. Set it in a layer you own, because
`gate_command` names a program to run and a committed config may not do that. See
[A committed config can no longer name a program to run](#a-committed-config-can-no-longer-name-a-program-to-run).
The policy is shared. The command is yours:

```yaml
# manifest.config.yaml — committed and shared: the policy
release:
  gate: "local-tests"
```

```yaml
# manifest.config.local.yaml — gitignored and yours: the command
release:
  gate_command: "pytest -q"     # or "go test ./...", "npm test", "make test"
```

**If Manifest finds no test command.** With `local-tests` and no test command, Manifest
refuses to release. It prints:
*"Release gate (local-tests): no test command found — refusing to release unverified."*
You have three ways forward:

- Set `release.gate_command` in a layer you own.
- Add `./scripts/run-tests.sh`.
- Choose `release.gate: none` on purpose. Manifest records that choice in the audit log
  and states it on every ship.

**If your pipeline released without tests before the gate existed.** Set
`release.gate: none` explicitly until you are ready to change that. The choice is
logged and recorded in the ship status file, so it is visible. When you are ready,
point `release.gate_command` at your tests.

## Versions are independent across a fleet

Each repository counts up from its own `VERSION` file. Manifest never aligns versions
across a fleet and never moves them together. A fleet release runs each member's own
release: its own version number, its own `version.sync` targets if it has any, and its
own release gate.

Manifest does not give every member the same version number. The fleet root's own
version is a separate thing, covered in
[FLEET_DESIGN_SPEC.md](FLEET_DESIGN_SPEC.md).

## See also

- [User Guide](USER_GUIDE.md) — day-to-day workflows.
- [Command Reference](COMMAND_REFERENCE.md) — every command, flag, and exit code.
- [Configuration example](../examples/manifest.config.yaml.example) — every setting, with comments.
