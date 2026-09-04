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
if your project differs:

```yaml
# manifest.config.yaml
release:
  gate: "local-tests"
  gate_command: "pytest -q"     # or "go test ./...", "npm test", "make test"
```

**One sharp edge worth knowing.** If you choose `local-tests` but Manifest cannot work
out a test command, it warns and continues — it cannot run tests that do not exist. That
means `local-tests` alone is not a guarantee. If you need the gate to be able to *stop* a
release, either set `release.gate_command` explicitly or use `remote-ci` / `all`.

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

The variable is an environment variable on purpose. A committed file must not be able to
grant itself trust, so there is deliberately no config key for it.

**Fleets are the case most likely to be affected.** Members are cloned from URLs the
fleet config supplies, so a member's committed `manifest.config.yaml` is the
clone-from-elsewhere case exactly. A fleet whose members declare their own gate commands
in committed config must move each one to that member's `manifest.config.local.yaml`, or
run with the trust variable set.

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
