# Manifest CLI tests

Bash unit tests using [bats-core](https://github.com/bats-core/bats-core).

## Install bats

```sh
brew install bats-core
```

(Or follow the [upstream install docs](https://bats-core.readthedocs.io/en/stable/installation.html).)

## Run the suite

```sh
./scripts/run-tests.sh                  # everything
./scripts/run-tests.sh tests/yaml.bats  # one file
```

The runner exits 2 if `bats` is missing.

## What's covered

| File | Targets |
|---|---|
| `tests/yaml.bats` | YAML parser detection, `set_yaml_value` / `get_yaml_value` round-trip, `load_yaml_to_env` precedence, YAML↔ENV mapping |
| `tests/version.bats` | `bump_version` for patch / minor / major / revision; rejection of bad input |
| `tests/canonical_repo.bats` | `manifest_origin_repo_slug` URL parsing, `should_update_homebrew_for_repo` allowlist gate |
| `tests/safety_gate.bats` | `_confirm_global_config_write` bypass / session cache / destructive-op behavior |

## Conventions

- Each test file `load 'helpers/setup'` for shared helpers.
- `mk_scratch` returns a scratch dir under `$BATS_TEST_TMPDIR`; tests `rm -rf` it in teardown.
- Tests must not touch the developer's real `$HOME`, real config, or real git remotes. Use scratch dirs.

## Adding tests

Pick a target with clear inputs and outputs (pure or near-pure). Avoid testing functions that shell out to network / git push — keep those for end-to-end smoke tests.
