# Manifest CLI User Guide

This guide covers how to use `manifest` as it is currently implemented.

## Release Workflow Model

- `manifest prep <type>`: local release preparation (`type` is required).
- `manifest ship <type>`: publish flow (prep + tag/push/homebrew path).
- `manifest pr ...`: pull request operations.
- `manifest fleet ...`: multi-repo operations.

Supported release types: `patch`, `minor`, `major`, `revision`.

## First-Time Usage

```bash
manifest --help
manifest config show
manifest test all
```

## Daily Commands

```bash
# Prepare a patch release
manifest prep patch

# Publish a minor release
manifest ship minor

# Bump version only
manifest version patch

# Regenerate docs for current version
manifest docs
```

## Prep vs Ship

### `prep`

`prep` runs repository checks, sync, version bump, documentation generation, and commits. It does not create/push tags in prep mode.

### `ship`

`ship` runs prep in publish mode and then performs publish steps, including tag/push operations and formula update flow where applicable.

## Pull Request Workflows

```bash
manifest pr                  # interactive
manifest pr create
manifest pr update
manifest pr status
manifest pr ready
manifest pr checks
manifest pr queue
manifest pr policy show
manifest pr policy validate
```

## Fleet Workflows

```bash
manifest fleet init
manifest fleet discover
manifest fleet status
manifest fleet sync
manifest fleet ship
manifest fleet add
manifest fleet pr
manifest fleet validate
```

Current status: `fleet prep` and `fleet docs` are scaffolded and not implemented.

## Test Suites

```bash
manifest test all
manifest test versions
manifest test security
manifest test config
manifest test docs
manifest test git
manifest test ntp
manifest test os
manifest test modules
manifest test integration
manifest test cloud
manifest test agent
manifest test zsh
manifest test bash32
manifest test bash4
manifest test bash
```

Test logs are written under `~/.manifest-cli/logs/tests/<run-id>/`.

## Configuration

Use:

```bash
manifest config
manifest config show
manifest config ntp
manifest config setup
```

Config loading order is install-level, user-level, then project-level env files, followed by defaults. See examples in `examples/`.

## Security and Maintenance

```bash
manifest security
manifest cleanup
manifest update --check
manifest uninstall --force
manifest reinstall
```

For git hook behavior and secret-scanning workflow, see `docs/GIT_HOOKS.md`.
