# Manifest CLI Tests

Run tests in containers. Do not install test dependencies on the host.

`scripts/run-tests-container.sh` builds a reusable local image from
`tests/containers/run-tests.Dockerfile`, keyed by the Dockerfile hash, then
bind-mounts the repo into `/work`.

## Full Suite

```bash
./scripts/run-tests-container.sh
```

## Focused Suite

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
./scripts/run-tests-container.sh tests/command_surface_inventory.bats
```

## What Is Covered

- Command dispatch and help behavior
- Preview/apply safety gates
- YAML config layering and env mapping
- Version math and changelog updates
- Canonical-version ownership and opt-in JSON/TOML/YAML `version.sync`
- Passive version-surface discovery, YAML policy, status/doctor/fleet reporting
- Shared iterative discovery used by fleet and version scanners
- Repo and fleet release paths
- Fleet ship skips unchanged members that are already tagged at their current version
- Homebrew tap update behavior
- GitHub Actions and GitHub Release integration
- Docs generation and managed Pages workflow generation
- Uninstall and destructive-path guards

## Conventions

- Tests use scratch directories and must not mutate the developer's real home directory.
- Tests that need destructive behavior must keep it inside the test sandbox.
- New command behavior needs help/docs coverage when user-visible.
- New mutating routes must advertise `--dry-run`, `-y`, and `--yes`.
- Internal detection helpers should document their output contracts and add focused Bats coverage even when they do not add a public command.

## Host Runner

`scripts/run-tests.sh` exists for controlled environments that already provide the right tools. It is not the default workflow for this workspace.
