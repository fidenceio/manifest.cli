# Manifest CLI tests

Bash unit tests using [bats-core](https://github.com/bats-core/bats-core).

## Run The Suite

The default path is containerized. Do not install bats, yq, or other test
dependencies on the host.

```sh
./scripts/run-tests-container.sh                  # everything
./scripts/run-tests-container.sh tests/yaml.bats  # one file
```

The container runner uses Alpine with Bash, Git, bats-core, Mike Farah yq, and
coreutils installed inside the disposable container.

## Host Runner

```sh
./scripts/run-tests.sh                  # everything
./scripts/run-tests.sh tests/yaml.bats  # one file
```

This runner is intended for CI images or development containers that already
provide dependencies. It exits 2 if `bats` is missing.

## What's covered

| File | Targets |
|---|---|
| `tests/yaml.bats` | YAML parser detection, `set_yaml_value` / `get_yaml_value` round-trip, `load_yaml_to_env` precedence, YAML↔ENV mapping |
| `tests/version.bats` | `bump_version` for patch / minor / major / revision; rejection of bad input |
| `tests/canonical_repo.bats` | `manifest_origin_repo_slug` URL parsing, `should_update_homebrew_for_repo` allowlist gate |
| `tests/recipe.bats` | Built-in recipe introspection and `ship --explain` routing |
| `tests/safety_gate.bats` | `_confirm_global_config_write` bypass / session cache / destructive-op behavior |
| `tests/security_check.bats` | `manifest security --check` read-only behavior and pre-commit hook integration |

## Conventions

- Each test file `load 'helpers/setup'` for shared helpers.
- `mk_scratch` returns a scratch dir under `$BATS_TEST_TMPDIR`; tests `rm -rf` it in teardown.
- Tests must not touch the developer's real `$HOME`, real config, or real git remotes. Use scratch dirs.

## Adding tests

Pick a target with clear inputs and outputs (pure or near-pure). Avoid testing functions that shell out to network / git push — keep those for end-to-end smoke tests.
