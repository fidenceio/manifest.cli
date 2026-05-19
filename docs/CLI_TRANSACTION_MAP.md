# Manifest CLI Transaction Map

This maps the implemented Manifest CLI command tree from the dispatcher and
scope handlers, plus the Homebrew tap transaction surface used to install and
upgrade the CLI. It is intentionally organized by route and transaction effect,
not by user-guide narrative.

Primary sources:

- `scripts/manifest-cli.sh` loads `modules/core/manifest-core.sh`.
- `modules/core/manifest-core.sh` owns top-level dispatch in `main()`.
- Scope dispatchers live under `modules/core/`, `modules/fleet/`,
  `modules/pr/`, `modules/recipe/`, and `modules/system/`.
- The Homebrew tap repo is `../fidenceio.homebrew.tap`; its live formula is
  `Formula/manifest.rb`.

## Legend

| Mark | Meaning |
| ---- | ------- |
| `R` | Read-only or informational |
| `P` | Preview by default; no writes without apply |
| `L` | Local filesystem or local Git writes in apply mode |
| `G` | Git commit, tag, branch, or checkout mutation |
| `N` | Network or remote service mutation |
| `O` | Optional plugin or provider route |
| `D` | Deprecated, legacy, or plumbing route |

Global write policy for mutating commands:

```text
plain command       -> preview when the route supports preview
--dry-run           -> explicit preview
-y, --yes           -> apply
--local             -> local-only effect boundary
--dry-run + -y      -> invalid
```

## ASCII Command Tree

```text
manifest
|-- help | -h | --help                                      [R]
|-- version | -v | -V | --version                            [R]
|
|-- config                                                    [R/L]
|   |-- (none)                                                [R/L: TTY wizard, non-TTY show]
|   |-- show                                                  [R]
|   |-- time                                                  [R]
|   |-- doctor [--fix | --dry-run]                            [P/L]
|   |-- setup                                                 [L]
|   |-- --non-interactive                                     [R]
|   |-- list [--layer global|project|local] [--json]          [R]
|   |-- get <key>                                             [R]
|   |-- describe <key>                                        [R]
|   |-- set [-y|--yes] [--dry-run] [--layer L] <key> <value>  [P/L]
|   `-- unset [-y|--yes] [--dry-run] [--layer L] <key>        [P/L]
|
|-- init                                                      [P/L]
|   |-- repo [--force] [--create-repo-private|--create-repo-public]
|   `-- fleet [--dry-run] [--depth N] [--all-folders] [--name NAME]
|            [--force] [--create-repo-private|--create-repo-public]
|
|-- quickstart                                                [P/L]
|   `-- fleet [-y|--yes] [--dry-run] [--name NAME] [--force]
|
|-- plan                                                      [P/L]
|   `-- fleet [--apply|--do] [--dry-run] [--depth N|auto]
|            [--safety-cap N] [--plan FILE] [--name NAME] [--force]
|
|-- reconcile                                                 [P/L/G/N]
|   `-- fleet [--apply|--do] [--dry-run] [--plan FILE]
|            [--commit] [--push] [--force] [--adopt-submodules]
|
|-- status                                                    [R]
|   |-- (auto: repo or fleet)
|   |-- repo [--json]
|   `-- fleet [--json]
|
|-- discover                                                  [R]
|   `-- fleet [--depth N] [--json] [--quiet|-q]
|
|-- update                                                    [P/L]
|   `-- fleet [-y|--yes] [--dry-run] [--depth N] [--json] [--quiet|-q]
|
|-- add                                                       [P/L]
|   `-- fleet <path-or-url> [-y|--yes] [--dry-run] [--name NAME] [--type TYPE]
|
|-- validate                                                  [R]
|   `-- fleet
|
|-- prep                                                      [P/L/G/N]
|   |-- repo [--create-repo-private|--create-repo-public]
|   `-- fleet [-y|--yes] [--dry-run] [--parallel|-p]
|            [--clone-only] [--pull-only]
|
|-- refresh                                                   [P/L/G]
|   |-- repo [-y|--yes] [--dry-run] [--commit]
|   `-- fleet [-y|--yes] [--dry-run] [--commit]
|
|-- docs                                                      [P/L/D]
|   |-- (default generate) [-y|--yes] [--dry-run]
|   |-- metadata [-y|--yes] [--dry-run]
|   |-- cleanup [-y|--yes] [--dry-run]
|   |-- homebrew                                             [R]
|   `-- fleet
|       |-- generate [-y|--yes] [--dry-run] [--strategy STRATEGY]
|       |            [--fleet-only] [--services-only]
|       |-- status                                           [R]
|       |-- patch|minor|major|revision [-y|--yes] [--dry-run]
|       `-- <flags directly>                                 [P/L]
|
|-- recipe                                                    [R/L]
|   |-- list                                                  [R]
|   |-- show <id>                                             [R]
|   |-- explain <id>                                          [R]
|   `-- run <id>                                             [L: implemented direct execution]
|
|-- ship                                                      [P/L/G/N]
|   |-- repo <patch|minor|major|revision>
|   |       [-y|--yes] [--dry-run] [--local] [-i|--interactive] [--explain]
|   |-- repo <-p|-m|-M|-r>
|   |       [-y|--yes] [--dry-run] [--local] [-i|--interactive] [--explain]
|   |-- repo resume
|   |-- fleet <patch|minor|major|revision>
|   |       [-y|--yes] [--dry-run] [--local] [--explain] [--noprep]
|   `-- <patch|minor|major|revision>                         [D: legacy -> ship repo]
|
|-- pr                                                        [R/P/N]
|   |-- (none)                                                [R/P: current PR or creation prompt]
|   |-- create [-y|--yes] [--dry-run] [--draft] [gh args...]  [P/N]
|   |-- update [-y|--yes] [--dry-run] [target] [gh args...]   [P/N]
|   |-- status [target]                                      [R/N]
|   |-- checks [target] [--watch]                            [R/N]
|   |-- ready [-y|--yes] [--dry-run] [target]                 [P/N]
|   |-- merge [-y|--yes] [--dry-run] [target] [--squash|--merge|--rebase] [--auto]
|   |                                                         [P/N]
|   |-- queue [-y|--yes] [--dry-run] [args...]                [P/N/O]
|   |-- policy
|   |   |-- show                                             [R/O]
|   |   `-- validate                                         [R/O]
|   `-- fleet
|       |-- (none) | queue [-y|--yes] [--dry-run] [--method METHOD] [--force]
|       |                                                         [P/N/O]
|       |-- create [-y|--yes] [--dry-run] [options]          [P/N/O]
|       |-- status                                           [R/N/O]
|       |-- checks                                           [R/N/O]
|       |-- ready [-y|--yes] [--dry-run] [options]           [P/N/O]
|       `-- help                                             [R]
|
|-- doctor                                                    [R]
|-- security [--check]                                        [L/R]
|-- test [suite]                                              [R/O]
|-- upgrade                                                   [N/O]
|-- uninstall [-y|--yes] [--dry-run] [--force]                [P/L]
|-- reinstall [-y|--yes] [--dry-run]                         [P/L/N]
|-- revert                                                    [G]
|
|-- cloud                                                     [O]
|   |-- config                                                [L/O]
|   |-- status                                                [R/O]
|   `-- generate <version> [timestamp] [release_type]         [N/O]
|
|-- agent <subcommand> [options]                              [O]
|
|-- fleet                                                     [D]
|   `-- add|discover|docs|init|prep|pr|quickstart|ship|start|status|sync|update|validate
|       -> replacement hint only; use action-first routes
|
|-- sync                                                      [D: -> prep repo]
|-- time                                                      [D: -> config time/display time info]
|-- commit <message>                                          [D/G: plumbing]
|-- bump-version <patch|minor|major|revision>                 [D/L: plumbing]
`-- cleanup                                                   [D/L: docs cleanup plumbing]
```

## Transaction Map By Route

| Route family | Default | Apply trigger | Main effect boundary |
| ------------ | ------- | ------------- | -------------------- |
| `help`, `version`, `status`, `doctor`, `validate fleet`, `discover fleet` | Read | None | Inspects local state and prints output. |
| `config show/time/list/get/describe` | Read | None | Reads merged YAML/env config. |
| `config doctor` | Preview | `--fix` where supported | Detects stale config; fix path writes YAML. |
| `config set/unset` | Preview | `-y`, `--yes` | Writes `global`, `project`, or `local` YAML layer. |
| `init repo` | Local write | Route-specific flags | Scaffolds repo files and may initialize Git. |
| `init fleet`, `quickstart fleet` | Preview/local write | `-y`, `--yes` or phase-specific apply | Scans folders and writes fleet TSV/config/scaffolding. |
| `plan fleet` | Preview | `--apply`, `--do` | Writes `manifest.fleet.plan.yaml`. |
| `reconcile fleet` | Preview | `--apply`, `--do`; optional `--commit`, `--push` | Applies adoption plan; may move/init repos, commit, and push. |
| `add/update fleet` | Preview | `-y`, `--yes` | Writes fleet membership config. |
| `prep repo` | Operational | Route execution | Adds missing remote interactively and pulls remotes. |
| `prep fleet` | Preview | `-y`, `--yes` | Clones missing repos and pulls existing repos. |
| `refresh repo` | Preview | `-y`, `--yes`; optional `--commit` | Regenerates docs/metadata; optionally commits. |
| `refresh fleet` | Preview | `-y`, `--yes`; optional `--commit` | Re-scans fleet, validates config, regenerates fleet docs; optionally commits. |
| `docs` | Preview | `-y`, `--yes` | Generates metadata/docs or archives docs. |
| `recipe list/show/explain` | Read | None | Inspects recipe files. |
| `recipe run` | Direct execution | Route-specific | Runs a recipe directly; implemented but not the public workflow model. |
| `ship repo <type>` | Preview | `-y`, `--yes` | Bumps version, docs, commits, tags, pushes, updates Homebrew/GitHub Release unless `--local`. |
| `ship repo resume` | Operational | Route-specific | Resumes safe post-release steps for current version/tag. |
| `ship fleet <type>` | Preview | `-y`, `--yes` | Ships release-enabled fleet services; may tag/push per repo unless `--local`. |
| `pr create/ready/merge/update/queue` | Preview | `-y`, `--yes` | Calls `gh` or Cloud provider to mutate PR state. |
| `pr status/checks/policy show/policy validate` | Read | None | Calls `gh` or Cloud provider for PR state. |
| `security` | Write report | `--check` makes it read-only | Audits tracked private files, PII patterns, env-file hygiene. |
| `test` | Read/diagnostic | Plugin-dependent | Cloud test plugin or stub diagnostic output. |
| `upgrade` | Provider operation | Provider-dependent | Optional Cloud/Homebrew upgrade provider. |
| `uninstall` | Preview | `-y`, `--yes` | Removes Manifest CLI installation artifacts; `--force` only narrows prompts after apply. |
| `reinstall` | Preview | `-y`, `--yes` | Uninstalls then reinstalls via Homebrew/provider/manual install path. |
| `revert` | Git mutation | Interactive route | Checks out a previous version tag. |
| `cloud` | Optional | Subcommand-specific | Optional Manifest Cloud connector config/status/generation. |
| `agent` | Optional | Subcommand-specific | Optional containerized Cloud agent manager. |
| Legacy/plumbing routes | Mixed | Mixed | Compatibility or internal dispatcher routes; prefer first-class routes above. |

## Source Module Map

```text
scripts/manifest-cli.sh
`-- modules/core/manifest-core.sh
    |-- modules/core/manifest-config.sh
    |-- modules/core/manifest-config-crud.sh
    |-- modules/core/manifest-doctor.sh
    |-- modules/core/manifest-execution-policy.sh
    |-- modules/core/manifest-init.sh
    |-- modules/core/manifest-prep.sh
    |-- modules/core/manifest-refresh.sh
    |-- modules/core/manifest-ship.sh
    |-- modules/core/manifest-shared-functions.sh
    |-- modules/core/manifest-shared-utils.sh
    |-- modules/core/manifest-yaml.sh
    |-- modules/docs/manifest-cleanup-docs.sh
    |-- modules/docs/manifest-documentation.sh
    |-- modules/fleet/manifest-fleet.sh
    |-- modules/fleet/manifest-fleet-apply.sh
    |-- modules/fleet/manifest-fleet-config.sh
    |-- modules/fleet/manifest-fleet-detect.sh
    |-- modules/fleet/manifest-fleet-docs.sh
    |-- modules/fleet/manifest-fleet-plan.sh
    |-- modules/git/manifest-doc-review.sh
    |-- modules/git/manifest-git.sh
    |-- modules/git/manifest-git-changes.sh
    |-- modules/pr/manifest-pr-native.sh
    |-- modules/recipe/manifest-recipe.sh
    |-- modules/system/manifest-os.sh
    |-- modules/system/manifest-security.sh
    |-- modules/system/manifest-time.sh
    |-- modules/system/manifest-uninstall.sh
    |-- modules/workflow/manifest-orchestrator.sh
    `-- optional Cloud modules or local stubs
```

## Homebrew Tap Transaction Map

The tap repo is intentionally small:

```text
fidenceio.homebrew.tap
|-- .gitignore
`-- Formula
    `-- manifest.rb
```

The tap remote is:

```text
origin  git@github.com:fidenceio/homebrew-tap.git
```

The formula currently declares the installable package:

```text
Formula/manifest.rb
|-- class Manifest < Formula
|-- desc/homepage/license
|-- url      https://github.com/fidenceio/manifest.cli/archive/refs/tags/<tag>.tar.gz
|-- sha256   <tarball sha256>
|-- head     https://github.com/fidenceio/manifest.cli.git, branch: main
|-- depends_on bash
|-- depends_on git => :recommended
|-- depends_on yq
|-- depends_on coreutils
|-- install
|   |-- copy release source tree to libexec
|   |-- install bash and zsh completions
|   `-- write bin/manifest wrapper
|       |-- source modules/core/manifest-requirements.sh
|       |-- re-exec into Bash 5 when needed
|       |-- source modules/core/manifest-core.sh
|       `-- main "$@"
|-- post_install
|   |-- remove legacy ~/.local/bin/manifest if present
|   `-- run manifest config doctor --fix against user global config when present
|-- test
|   `-- manifest status
`-- caveats
    |-- manifest --help
    |-- manifest test
    |-- manifest time
    |-- brew update && brew upgrade manifest
    |-- manifest uninstall
    `-- manifest uninstall -y
```

### Tap Publish Flow

`manifest ship repo <type> -y` publishes the tap only when all of these are
true:

```text
PROJECT_ROOT/formula/manifest.rb exists
repo origin is in MANIFEST_CLI_CANONICAL_REPO_SLUGS
release is not --local
release tag was created and pushed far enough for GitHub tarball download
local Homebrew tap checkout exists at brew --prefix/Library/Taps/fidenceio/homebrew-tap
```

Transaction path:

```text
manifest ship repo <type> -y
`-- manifest_ship_post_push_steps()
    `-- update_homebrew_formula()
        |-- read PROJECT_ROOT/VERSION
        |-- derive tag with manifest_release_tag_name()
        |-- fetch https://github.com/fidenceio/manifest.cli/archive/refs/tags/<tag>.tar.gz
        |-- compute sha256 with shasum -a 256
        |-- rewrite PROJECT_ROOT/formula/manifest.rb url + sha256
        |-- locate tap checkout at $(brew --prefix)/Library/Taps/fidenceio/homebrew-tap
        |-- git pull --ff-only origin main in tap checkout when possible
        |-- manifest_homebrew_tap_push_formula()
        |   |-- copy PROJECT_ROOT/formula/manifest.rb to tap Formula/manifest.rb
        |   |-- git add Formula/manifest.rb
        |   |-- git commit -m "Update formula to <tag>" when changed
        |   `-- git push git@github.com:fidenceio/homebrew-tap.git HEAD:main
        `-- manifest_refresh_homebrew_tap_checkouts()
            |-- explicit MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT
            |-- primary brew tap checkout
            |-- sibling ../fidenceio.homebrew.tap
            `-- sibling ../homebrew-tap
```

### Tap Transactions

| Transaction | Default | Apply trigger | Main effect boundary |
| ----------- | ------- | ------------- | -------------------- |
| `brew tap fidenceio/tap` | Apply | User command | Clones/registers the tap under Homebrew's tap directory. |
| `brew install fidenceio/tap/manifest` | Apply | User command | Downloads the tagged CLI tarball, verifies `sha256`, installs files under Homebrew Cellar, writes `bin/manifest`, installs completions, runs `post_install`. |
| `brew upgrade manifest` | Apply | User command or post-ship local upgrade step | Replaces the installed Cellar version, re-runs formula install/post-install behavior, and may change the live `manifest` binary during long-running release flows. |
| `manifest ship repo <type> -y` from canonical CLI repo | Apply | `-y`, `--yes` | Updates the CLI repo formula copy, commits/pushes that copy, updates the tap formula, commits/pushes the tap, then may upgrade the local install. |
| `manifest ship repo <type> --local -y` | Apply local only | `--local -y` | Skips tag, push, Homebrew formula update, GitHub Release, and local Homebrew upgrade. |
| `manifest_refresh_homebrew_tap_checkouts` | Safe fast-forward | Called after tap push | Fast-forwards clean known tap checkouts; skips dirty/mismatched checkouts. |
| `manifest uninstall` | Preview | None | Shows Homebrew package and tap removal plan when installed via Homebrew. |
| `manifest uninstall -y` | Apply | `-y`, `--yes` | Runs `brew uninstall fidenceio/tap/manifest` or `brew uninstall manifest`, then `brew untap fidenceio/tap`, plus local artifact cleanup. |
| Formula `post_install` | Apply | Homebrew install/upgrade | Removes legacy manual binary and migrates user global config with `manifest config doctor --fix` if present. |
| Formula `test do` | Read/diagnostic | Homebrew test | Runs installed `manifest status`. |

### Tap Failure Boundaries

```text
tarball SHA fetch fails
  -> update_homebrew_formula returns failure
  -> ship emits homebrew_update failure report

tap checkout missing
  -> update_homebrew_formula returns failure
  -> no silent stale-tap success

tap push fails
  -> manifest_homebrew_tap_push_formula returns failure
  -> ship emits homebrew_update failure report

CLI repo formula changed but commit/push fails
  -> ship emits homebrew_commit or homebrew_push failure report

local brew upgrade fails after successful tap publish
  -> ship warns and continues; published release is already remote

dirty sibling tap checkout exists
  -> safe fast-forward refresh should skip it instead of overwriting local edits
```

### Tap State Notes

- The tap is release-disabled as a fleet service; it is updated by the canonical
  CLI release flow rather than shipped as its own versioned product.
- The tap commit subject pattern is `Update formula to <tag>`.
- The source-of-truth formula for shipping starts in the CLI repo at
  `formula/manifest.rb`; the public tap receives a copied formula at
  `Formula/manifest.rb`.
- The tap formula pins immutable release tarballs by tag and SHA, while `head`
  remains available for main-branch development installs.

## High-Consequence Paths

```text
manifest ship repo <type> -y
  -> repo identity check
  -> recipe effect validation
  -> repo apply confirmation
  -> timestamp
  -> auto-commit dirty worktree after docs review
  -> pull remotes
  -> bump VERSION
  -> generate docs/changelog/release notes
  -> archive old docs
  -> markdown validation
  -> commit release changes
  -> tag
  -> push
  -> Homebrew formula update when canonical
  -> GitHub Release when enabled
  -> optional installed CLI upgrade / Actions watch / follow-up patch

manifest ship fleet <type> -y
  -> load fleet config
  -> render fleet identity and included repositories
  -> validate recipe effects
  -> dispatch per-release-enabled service
  -> run each service release path with fleet-scoped repo confirmation

manifest reconcile fleet --apply [--commit [--push]]
  -> load and validate manifest.fleet.plan.yaml
  -> apply track/init/move/adopt_submodule actions
  -> optionally commit changed files
  -> optionally push committed changes
```
