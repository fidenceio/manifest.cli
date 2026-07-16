# Migration Guide

This guide covers the behaviors most likely to surprise someone adopting
Manifest CLI or upgrading an existing automation. The throughline is one rule:
**Manifest is safe by default — it shows you the plan and changes nothing until
you explicitly say apply.**

## The preview / apply model

Every mutating command (`init`, `prep`, `refresh`, `ship`) **previews by
default** and writes nothing. You opt into changes explicitly:

```bash
manifest ship repo patch        # preview — no writes, commits, tags, or pushes
manifest ship repo patch -y     # apply — performs the release
```

| Spelling | Meaning |
| -------- | ------- |
| (no flag) | Preview. Prints the plan; makes no changes. |
| `--dry-run` | Explicit preview. Same as no flag; use it to be unambiguous in scripts. |
| `-y` / `--yes` | Apply. Performs the planned changes. |
| `--local -y` | Apply local release work only — no tag, push, GitHub Release, or Homebrew tap publish. |

You cannot combine `--dry-run` with `-y`; preview is already the default, so the
combination is rejected rather than silently guessed.

### `-y` applies without a confirmation prompt

`-y` is full apply authorization: it applies with **no** interactive
confirmation prompt, whether or not a terminal is attached. On a normal repo (a
named branch + an `origin` remote) `-y` alone applies. An **ambiguous** target —
detached HEAD, or no `origin` when one is required — is *refused* (never
prompted); fix the repo, or set `MANIFEST_CLI_AUTO_CONFIRM=1` to authorize it.

### `MANIFEST_CLI_AUTO_CONFIRM` is not an apply switch

`MANIFEST_CLI_AUTO_CONFIRM=1` only authorizes an *ambiguous* apply target
**after** apply mode has already been selected with `-y`. It does **not**
authorize apply on its own — a command without `-y` still previews even when it
is set — and it is not needed for an ordinary (unambiguous) apply.

```bash
manifest ship repo patch -y                              # normal repo: applies, no prompt
MANIFEST_CLI_AUTO_CONFIRM=1 manifest ship repo patch -y  # also authorizes an ambiguous target
```

Fleet apply (`manifest ship fleet <type> -y`) treats its own `-y` as consent for
every selected member and does not prompt per member.

## The release gate (new)

Releases are now gated on verification before they publish. The single
self-describing setting `release.gate` (env `MANIFEST_CLI_RELEASE_GATE`) controls
what must be green:

| Value | Behavior |
| ----- | -------- |
| `local-tests` (default) | Run the project's test command first — before auto-commit, remote sync, or any version mutation; a failure aborts with the repo untouched. |
| `remote-ci` | Require the pushed commit's GitHub checks to be green before the GitHub Release / Homebrew tap publish (the tag is already pushed). |
| `all` | `local-tests` **and** `remote-ci`. |
| `none` | No verification. Emits a loud warning and records an audited bypass. |

The `local-tests` command is auto-detected as `./scripts/run-tests.sh`, or set
your own:

```yaml
# manifest.config.yaml
release:
  gate: "local-tests"
  gate_command: "pytest -q"     # or "go test ./...", "npm test", "make test"
```

If `local-tests` is selected but no test command can be resolved, Manifest warns
and proceeds (it cannot run tests that do not exist) — set `release.gate_command` or use
`remote-ci`/`all` to enforce hard gating.

**Upgrading existing automation:** if your pipeline previously shipped without
running tests and you do not want that to change yet, set `release.gate: none`
explicitly (the bypass is logged and recorded in the ship status file). To adopt
gating, point `release.gate_command` at your test entrypoint.

## Versions are independent across a fleet

Each repository bumps from its own `VERSION`. Manifest never aligns or locksteps
versions across a fleet; a fleet ship runs each member's own release with its own
versioning, explicit `version.sync` targets, and its own release gate.

## See also

- [User Guide](USER_GUIDE.md) — daily workflows.
- [Command Reference](COMMAND_REFERENCE.md) — full grammar and flags.
- [Configuration example](../examples/manifest.config.yaml.example) — every setting with comments.
