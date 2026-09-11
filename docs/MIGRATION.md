# Migration Guide

This guide covers the two things most likely to catch out someone new to Manifest CLI,
or someone upgrading a pipeline that already existed. Both come back to one rule:

**Manifest shows you the plan and changes nothing until you explicitly say go.**

## The preview / apply model

Every command that could change something — `init`, `prep`, `refresh`, `ship` — prints
what it *would* do and then stops. Nothing is written until you ask:

```bash
manifest ship repo patch        # plan only: no writes, no commit, no tag, no push
manifest ship repo patch -y     # do it: performs the release
```

| What you type | What it means |
| -------- | ------- |
| nothing extra | Plan only. Prints what would happen; changes nothing. |
| `--dry-run` | The same thing, written out. Use it in scripts so a reader can see the intent. |
| `-y` / `--yes` | Do it. Performs the planned work. |
| `--local -y` | Do only the local part — no tag, no push, no GitHub Release, no Homebrew publish. |

You cannot pass `--dry-run` and `-y` together. Plan-only is already the default, so
rather than guess which one you meant, Manifest refuses the combination.

### `-y` does not then ask "are you sure?"

`-y` is the confirmation. Manifest applies immediately, whether or not you are sitting
at a terminal — this is deliberate, because a command that blocks waiting for input in
CI is a command that hangs a pipeline.

For an ordinary repository — one on a named branch, with an `origin` remote — `-y` on
its own is all you need.

There is one exception. If Manifest cannot tell what it would be acting on, it
**refuses** rather than prompting. Two cases cause that:

- **Detached HEAD** — your checkout is sitting on a specific commit rather than on a
  branch, so there is no branch to push.
- **No `origin` remote** on a command that needs to push somewhere.

Fix the repository, or authorise it explicitly with the variable below.

### `MANIFEST_CLI_AUTO_CONFIRM` is not a way to apply

`MANIFEST_CLI_AUTO_CONFIRM=1` does exactly one job: it authorises an *ambiguous* target
like the two above, and only **after** you have already asked for apply with `-y`.

It cannot start an apply. A command without `-y` still only prints a plan, even with the
variable set. And you do not need it for a normal apply.

```bash
manifest ship repo patch -y                              # ordinary repo: applies, no prompt
MANIFEST_CLI_AUTO_CONFIRM=1 manifest ship repo patch -y  # also allows an ambiguous target
```

This separation exists so that a variable sitting in a CI environment can never, by
itself, publish a release.

For a fleet, `manifest ship fleet <type> -y` treats that single `-y` as consent for
every selected member. It does not ask again for each one.

## The release gate

Before publishing, Manifest can require that something has passed. One setting controls
it: `release.gate` (or the variable `MANIFEST_CLI_RELEASE_GATE`).

| Value | What must pass |
| ----- | -------- |
| `local-tests` (default) | Your project's tests, run **first** — before the automatic commit, before syncing with the remote, before any version change. If they fail, the run stops and your repository is untouched. |
| `remote-ci` | GitHub's checks on the pushed commit must be green before the GitHub Release and Homebrew publish. Note the tag has already been pushed by this point. |
| `all` | Both of the above. |
| `none` | Nothing. Prints a loud warning and records the bypass in the audit log. |

For `local-tests`, Manifest looks for `./scripts/run-tests.sh`. Point it somewhere else
if your project differs — in a layer you own, because `gate_command` names a program to
run and a committed config may not do that (see the next section). The policy is shared;
the command is yours:

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

**One sharp edge worth knowing.** If you choose `local-tests` but Manifest cannot work
out a test command, it refuses to release rather than publish unverified:
*"Release gate (local-tests): no test command found — refusing to release unverified."*
The ways out are to set `release.gate_command` in a layer you own, to add
`./scripts/run-tests.sh`, or to choose `release.gate: none` deliberately — which is
recorded in the audit log and disclosed on every ship.

**Upgrading a pipeline that already worked.** If your automation previously released
without running tests and you are not ready to change that, set `release.gate: none`
explicitly. It is logged and recorded in the ship status file, so the choice is visible
rather than implied. When you are ready, point `release.gate_command` at your tests.

## A committed config can no longer name a program to run

This one changes behaviour for repositories that already worked, so it is worth reading
even if nothing else here applies to you.

Five config keys name something Manifest executes during a ship:

| Key | What it names |
| --- | --- |
| `release.gate_command` | the test command the release gate runs |
| `docs.review.command` | the documentation-review program |
| `docs.release_notes.command` | the release-notes program |
| `docs.review.provider` | the selector that makes the review command reachable |
| `docs.release_notes.provider` | the selector that makes the notes command reachable |

These five are now honoured **only from a layer you own** — your global config under
`~/.manifest-cli/`, any `*.local.yaml` (which the scaffold gitignores), or the process
environment. Set in a **committed `manifest.config.yaml`**, in a project or at a fleet
root, they are ignored, and the refusal is printed with the key and the layer it came
from. It is never silent.

The reason is that a committed config travels with a clone, and the project layer loads
*after* your global one and overrides it — so a repository you cloned could choose what
runs on your machine during a ship, and configuring safely would not have protected you.
[SECURITY.md](../SECURITY.md) states the full boundary.

**What to change.** Move the key out of the committed file:

```yaml
# manifest.config.local.yaml — gitignored, yours, honoured
release:
  gate_command: "pytest -q"
```

Leave the policy key `release.gate` where it is; only the five keys above are affected.
Or trust one repository for a single run, without editing anything:

```bash
MANIFEST_CLI_TRUST_REPO_COMMANDS=1 manifest ship patch -y
```

Or trust it once and have Manifest remember that decision:

```bash
MANIFEST_CLI_TRUST_REPO_COMMANDS=remember manifest ship patch -y
```

`remember` honours the committed keys for this run **and** records them in
`~/.manifest-cli/trusted-repo-commands.tsv`, keyed on the repository's remote and on a
digest of exactly the values you accepted. Later runs honour them with no variable set.
The record stays on your machine and follows the repository, not the clone, so a fresh
clone of the same remote is still trusted. If any of the five values changes in the
committed file, the record no longer matches: the keys are refused again, the refusal says
they changed since you trusted them, and reviewing and re-running with `remember` records
the new values. `MANIFEST_CLI_TRUST_REPO_COMMANDS=forget` deletes the repository's row.
The preview and the applied run both say, beside each committed program, whether it is
trusted for this run or by your record. The record is written when the configuration
loads, so `remember` on a preview records too — read the preview's program list first,
then run it with `remember` once you agree with what it names.

The variable is an environment variable on purpose. A committed file must not be able to
grant itself trust, so there is deliberately no config key for it — and none for the
record's location either.

**Fleets are the case most likely to be affected.** Members are cloned from URLs the
fleet config supplies, so a member's committed `manifest.config.yaml` is the
clone-from-elsewhere case exactly. A fleet whose members declare their own gate commands
in committed config must move each one to that member's `manifest.config.local.yaml`, or
run with the trust variable set.

## Upgrading to v61: the changelog stops guessing, and two new exit codes

Three changes in v61.0.0 are visible without you configuring anything.

**The canned changelog bullets are gone.** Manifest used to infer a *product claim* from
a touched path — three module files changed, so the entry read *"Add GitHub Release
publishing support"*, whether or not anything of the sort had happened. Those rules are
deleted. What is left describes only what was touched — documentation and examples, shell
completions, tests, the changelog — plus a count when nothing else fits, and the real
commit subjects. **Your CHANGELOG entries and ship previews will read differently from
v60 and earlier, and more modestly.** If something downstream parses those bullets, it is
parsing sentences that were never measured; stop.

**`ship fleet` now exits `2` when it completed partly** — one or more members released,
then a later member or the fleet root failed. It used to exit `0` and print the same
green closing line whether it released everything, released nothing, or failed at the
root. A pipeline that treats any non-zero as total failure will now see a partial fleet
release as a failure, which is the honest reading; one that treats `0` as "everything
published" was wrong before and is right now.

**The fleet ship's closing output changed shape along with it.** `✅ Fleet ship workflow
complete.` used to print unconditionally; it now prints only when the run actually
completed, and a partial or no-op run ends on a closing block naming members released,
skipped and failed, plus the root's own outcome. If something greps for that line to
confirm success, it will now correctly fail on a run that did not succeed — but it is
an output change, so check for it before you upgrade a pipeline.

**`fleet.coordination_files` is new, and it is a committed-config key that widens what
the coordination root commits and pushes.** Nothing changes for an existing fleet — the
default is the same five files as before — but if you adopt it, know that it is an
allowlist of plain file names, that directories and secret-shaped names are refused, and
that the resolved set is disclosed in the manager's preview before any apply. The full
rules are in [USER_GUIDE.md](USER_GUIDE.md).

**`4` is a pause, not a failure**, and it can only happen if you ask for it.
`docs.handoff` defaults to `off`, so an upgrade changes nothing here. Set it to `always`
(or `auto`, which pauses only when an AI agent is driving and never in CI) and a ship
stops before the release commit, writes a brief under `.git/` naming what the
documentation still needs, and exits `4`. No commit, no tag, no push. You edit the
documentation and re-run the identical command; Manifest verifies the result and then
releases. **Anything that reads a non-zero exit as a broken release needs to learn `4`
before you turn this on** — including CI, which is why `auto` never pauses there.

The full exit-code table is in
[COMMAND_REFERENCE.md](COMMAND_REFERENCE.md#exit-codes).

**What v61.0.0 does not carry, said plainly because it was reported as one problem.** If
your fleet root runs a pre-commit hook that enforces conventional commit subjects, v61
now shows you the hook's own output and names it as the cause instead of guessing at
`user.name`, unstages exactly what it staged, and exits `2` rather than `0`. It does not
yet make that commit *pass* — Manifest's own commit subjects come from one builder in a
follow-up. Until then, the fleet root still stops at the coordination commit on such a
repo; the difference is that it now tells you why.

## Versions are independent across a fleet

Each repository counts up from its own `VERSION` file. Manifest never aligns versions
across a fleet or moves them in lockstep. A fleet release runs each member's own
release: its own version number, its own `version.sync` targets if any, and its own
release gate.

If you want every member to share a version number, that is not something Manifest
does — and the fleet root's own version is a separate thing again, covered in
[FLEET_DESIGN_SPEC.md](FLEET_DESIGN_SPEC.md).

## See also

- [User Guide](USER_GUIDE.md) — day-to-day workflows.
- [Command Reference](COMMAND_REFERENCE.md) — every command, flag, and exit code.
- [Configuration example](../examples/manifest.config.yaml.example) — every setting, with comments.
