# Manifest CLI Command Reference

This reference reflects the command dispatcher in `modules/core/manifest-core.sh`.

## Top-Level Commands

- `manifest ntp`
- `manifest prep <patch|minor|major|revision> [-i|--interactive]`
- `manifest ship <patch|minor|major|revision> [-i|--interactive]`
- `manifest sync`
- `manifest revert`
- `manifest commit <message>`
- `manifest version [patch|minor|major|revision]`
- `manifest docs [metadata|homebrew|cleanup]`
- `manifest cleanup`
- `manifest config [show|ntp|setup|--non-interactive]`
- `manifest security`
- `manifest test [suite] [--strict-redact|--no-strict-redact]`
- `manifest update [--check|--force]`
- `manifest uninstall [--force]`
- `manifest reinstall`
- `manifest cloud [config|status|generate]`
- `manifest agent [init|auth|status|logs|uninstall]`
- `manifest pr <subcommand>`
- `manifest fleet <subcommand>`
- `manifest help`

## `manifest prep`

```bash
manifest prep patch
manifest prep minor -i
manifest prep -M
```

Notes:

- Release type is required.
- Short flags: `-p`, `-m`, `-M`, `-r`.
- Interactive flag: `-i`, `--interactive`.

## `manifest ship`

```bash
manifest ship patch
manifest ship major -i
```

Runs prep in publish mode (tag/push path enabled).

## `manifest docs`

```bash
manifest docs
manifest docs metadata
manifest docs homebrew
manifest docs cleanup
```

## `manifest config`

```bash
manifest config
manifest config show
manifest config ntp
manifest config setup
manifest config --non-interactive
```

## `manifest test`

```bash
manifest test all
manifest test cloud
manifest test bash32
manifest test all --no-strict-redact
```

## `manifest pr`

```bash
manifest pr                     # interactive
manifest pr create
manifest pr update
manifest pr status
manifest pr ready
manifest pr checks
manifest pr queue
manifest pr policy show
manifest pr policy validate
manifest pr help
```

## `manifest fleet`

Implemented subcommands:

```bash
manifest fleet init
manifest fleet status
manifest fleet discover
manifest fleet sync
manifest fleet ship
manifest fleet validate
manifest fleet add
manifest fleet pr
manifest fleet help
```

Scaffolded/not yet implemented:

- `manifest fleet prep`
- `manifest fleet docs`

## `manifest cloud`

```bash
manifest cloud config
manifest cloud status
manifest cloud generate <version> [timestamp] [release_type]
```

## `manifest agent`

```bash
manifest agent init docker
manifest agent auth github
manifest agent auth manifest
manifest agent status
manifest agent logs
manifest agent uninstall
```

## Deprecated/Not Available

These are not currently dispatched as top-level commands:

- `manifest diagnose`
- `manifest analyze`
- `manifest changelog`
- `manifest --version`
