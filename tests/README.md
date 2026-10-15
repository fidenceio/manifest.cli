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

## Safety contracts and line coverage

Full, smoke, and change-aware runs enforce every contract registered in
`tests/safety-contracts.tsv`. Each contract names two smoke tests: a passing
control and a challenging case (refusal, preservation, or recovery). The runner
checks actual TAP results and refuses missing, failed, duplicate, or skipped
proofs. The registry itself has removal and stale-reference guards. Explicit
file/filter runs stay focused and do not claim complete contract coverage.
Use `--no-cache` to demand fresh execution; release checks already require it.
Changes to verification scripts invalidate cached results.

This is 100% of the **registered critical safety contracts**, not proof that
all possible failure modes are tested. Changes to a mutating workflow need a
review of the register as well as meaningful regression tests.

Measure executable-line coverage separately:

```bash
./scripts/coverage.sh
# Optional explicit line target; an unmet target exits nonzero:
MANIFEST_CLI_COVERAGE_MIN_PERCENT=100 ./scripts/coverage.sh
```

The container parses a zero-hit inventory before merging actual traces, so a
module that tests never load still counts. The scope is every `modules/**/*.sh`
file plus `scripts/manifest-cli.sh`, `scripts/manifest-cli-wrapper.sh`, and
`scripts/migrate-user-config.sh`. Installer scripts, completions, test tooling,
and tests are outside this runtime metric. Inventory mismatches and malformed
reports always fail. A rounded `100%` headline cannot hide uncovered lines.

The default line target is zero for measurement; it does **not** assert 100%
line coverage or act as a release qualification. Test failures still fail the
coverage command. `coverage/report/index.html` contains the report and
`coverage/uncovered-lines.tsv` lists gaps. The source mount is read-only;
fixtures and report output remain writable inside the disposable container.

To check coverage reporting with a TAP stream larger than a pipe buffer:

```bash
./scripts/coverage.sh tests/fixtures/coverage_stdout_probe.bats
```

The traced runner writes TAP directly to `coverage/tests.tap`, which is emitted
after tracing. This avoids a kcov stdout-pipe deadlock on large suites.

CI runs the project inside Linux containers. GitHub's macOS runners do not
provide Docker; the former native Homebrew test-install step is removed to
honor the no-host-dependencies policy. Platform-specific skips remain reported;
this lane does not establish native macOS behavior.
