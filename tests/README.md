# Manifest CLI Tests

Run the tests in containers. Do not install test dependencies on your own machine (the
host).

The tests are written for bats, a test runner for Bash. `scripts/run-tests-container.sh`
builds a local container image from `tests/containers/run-tests.Dockerfile` and reuses
it on later runs. The image tag includes a hash of the Dockerfile, so the image is
rebuilt only when the Dockerfile changes. The script then mounts the repository into
the container at `/work`.

## Full Suite

```bash
./scripts/run-tests-container.sh
```

## Focused Suite

To run one test file, name it:

```bash
./scripts/run-tests-container.sh tests/docs_generation.bats
./scripts/run-tests-container.sh tests/command_surface_inventory.bats
```

## What Is Covered

- Command dispatch and help behavior
- Preview/apply safety gates
- YAML config layering and the mapping from config keys to environment variables
- Version arithmetic and changelog updates
- Ownership of the canonical version, and opt-in `version.sync` for JSON, TOML and YAML
  files
- Read-only discovery of other files that carry a version, the YAML policy for them,
  and their reporting in status, doctor and fleet output
- The shared discovery walker that the fleet scanner and the version scanner use
- Repo and fleet release paths
- Fleet ship skipping an unchanged member that is already tagged at its current version
- Homebrew tap updates
- GitHub Actions and GitHub Release integration
- Docs generation, including the managed GitHub Pages workflow
- Uninstall and the guards on destructive paths

## Conventions

- Tests use scratch directories. They must not change the developer's real home
  directory.
- A test that needs destructive behavior must keep it inside the test sandbox.
- New command behavior that a user can see needs help text and docs, and tests for
  both.
- A new command path that changes something must advertise `--dry-run`, `-y` and
  `--yes`.
- An internal detection helper should document the format of its output and have its
  own bats tests, even when it adds no public command.

## Host Runner

`scripts/run-tests.sh` runs the suite directly on a machine that already has the right
tools. It is not the default way to work in this repository. Use it only in a
controlled environment.

## Safety contracts and line coverage

A *safety contract* is a critical safety behavior that the suite must prove. The
contracts are registered in `tests/safety-contracts.tsv`.

- Each contract names two smoke tests: a passing control, and a challenging case
  (a refusal, a preservation or a recovery).
- Full, smoke and change-aware runs enforce every registered contract.
- The runner checks the actual TAP results. (TAP is the plain-text result format that
  bats prints.) It refuses a proof that is missing, failed, duplicated or skipped.
- The registry itself has guards against removed entries and stale references.
- A run that names files or a filter stays focused. It does not claim complete contract
  coverage.
- `--no-cache` forces every test to run again. Release checks already use it.
- A change to a verification script invalidates cached results.

This is 100% of the **registered critical safety contracts**. It is not proof that
every possible failure mode is tested. A change to a workflow that changes something
needs a review of the register as well as meaningful regression tests.

Line coverage is measured separately:

```bash
./scripts/coverage.sh
# Optional explicit line target; an unmet target exits nonzero:
MANIFEST_CLI_COVERAGE_MIN_PERCENT=100 ./scripts/coverage.sh
```

How the measurement works:

- **Scope.** Every `modules/**/*.sh` file, plus `scripts/manifest-cli.sh`,
  `scripts/manifest-cli-wrapper.sh` and `scripts/migrate-user-config.sh`. Installer
  scripts, completions, test tooling and the tests themselves are outside this metric.
- **Unloaded modules count.** The container first lists every line in scope with zero
  hits and then merges in the real traces. A module that no test loads therefore still
  counts as uncovered.
- **Failures.** A mismatch in that list, or a malformed report, always fails the
  command. A headline that rounds to `100%` cannot hide uncovered lines. A failing test
  also fails the coverage command.
- **Default target.** The default line target is zero, which means "measure only". It
  does **not** assert 100% line coverage, and it is not a release requirement.
- **Output.** The report is `coverage/report/index.html`. The gaps are listed in
  `coverage/uncovered-lines.tsv`.
- **Mounts.** The source is mounted read-only. Fixtures and report output stay
  writable inside the container, which is thrown away after the run.

To check coverage reporting with a TAP stream that is larger than a pipe buffer:

```bash
./scripts/coverage.sh tests/fixtures/coverage_stdout_probe.bats
```

The traced runner writes TAP straight to `coverage/tests.tap` and prints that file
after tracing ends. This avoids a deadlock on the stdout pipe of kcov, the coverage
tool, on large suites.

## Where the suite runs

- **Local development and Linux CI** run in containers. Do not install test
  dependencies on a developer machine.
- **Full CI also runs the suite natively on macOS**, on GitHub's disposable macOS
  runners. This is the one approved exception to the container rule, and it applies
  only in CI. The macOS job installs its own Homebrew tools. It exercises
  macOS-specific behavior that a Linux container cannot.
- **Pull requests, pushes to `main`, nightly runs and manual runs** use both platforms
  and do not use the test cache.
- **Other pushes to a feature branch** run only the Linux smoke tests, selected by what
  changed.
- **Keep the name of the native job as `bats (macos-latest)`.** Branch protection
  requires a job with that name.
