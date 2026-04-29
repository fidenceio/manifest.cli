# Changelog

All notable changes to Manifest CLI are documented here.
This project uses [Semantic Versioning](https://semver.org/).

## [45.6.0] - 2026-04-29

**Release Type:** Minor

### Forgiveness Contract for Config Values

- Added shared helpers `is_truthy`, `is_falsy`, `normalize_enum_value`, and `_trim_ws`
  in `modules/core/manifest-shared-utils.sh`. Truthy/falsy now accept the
  forgiving grammar `1|true|yes|on` / `0|false|no|off|''` (case-insensitive,
  whitespace-tolerant) instead of strict literal `1`/`0`.
- `load_yaml_to_env` trims leading/trailing whitespace from every loaded value.
  A trailing space in YAML used to silently break every downstream string
  comparison; now it is normalized at the boundary.
- `resolve_tag_target_sha` (`release.tag_target` dispatch) normalizes the
  enum value (trim + lowercase) before matching, so `Version_Commit`,
  `" release_head "`, and `Final_Release_Commit` all resolve correctly.
- Boolean dispatch sites swapped to `is_truthy` in `manifest-config.sh` (3 sites),
  `manifest-security.sh`, and `manifest-orchestrator.sh`. `MANIFEST_CLI_AUTO_CONFIRM=true`,
  `MANIFEST_CLI_QUIET_DEPRECATIONS=yes`, etc., now do what users expect.
- 24 new bats tests across `truthy.bats`, `yaml.bats`, `tag_target.bats`,
  and `deprecation.bats` lock the contract.

## [44.10.1] - 2026-04-27

**Release Type:** Patch

### `release.tag_target` — Configurable Release Tag Placement

- Added `release.tag_target` config key (`MANIFEST_CLI_RELEASE_TAG_TARGET`)
  that controls which commit the release tag points at:
  - `version_commit` (new default) — tag the explicit "Bump version to X" commit.
  - `release_head` — tag HEAD at tag-creation time (post-CHANGELOG, pre-Homebrew).
- `create_tag` now accepts an optional second argument (target SHA); empty
  falls through to HEAD-tagging for backward compatibility.

### Behavior Change

- **The default release tag now points at the version commit, not HEAD.**
  Before v44.10.1, the tag pointed at whatever HEAD was when the tag was
  created — typically the CHANGELOG commit. Repos with automation that reads
  `git for-each-ref` or `git rev-list <tag>..main` and expects post-CHANGELOG
  content inside the tag should set `release.tag_target: "release_head"` to
  restore the old behavior. The Homebrew formula commit is intentionally
  outside the tag in both cases (the SHA256 chicken-and-egg).

## [43.0.0] - 2026-04-06

**Release Type:** Major

### Architecture: Plugin Extraction

- Extracted PR, cloud, testing, and auto-upgrade modules (~7,000 lines) to Manifest Cloud repo
- Added plugin loader (`manifest-plugin-loader.sh`) for optional Cloud-provided modules
- Added stub files that print guidance when Cloud modules are not installed
- Deleted dead duplicate `manifest-mcp-connector-new.sh`
- CLI core journey (config, init, prep, refresh, ship) works fully standalone
- Commands requiring Cloud modules now marked `[Cloud]` in help text
- Modules removed from CLI: `modules/cloud/`, `modules/pr/`, `modules/testing/`, `modules/workflow/manifest-auto-upgrade.sh`
- Modules added to CLI: `modules/core/manifest-plugin-loader.sh`, `modules/stubs/` (4 stub files)

### Breaking Changes

- `manifest pr`, `manifest test`, `manifest cloud`, `manifest agent` now require Manifest Cloud installation
- `manifest upgrade` via manual install requires Manifest Cloud; Homebrew upgrade path unaffected
- `manifest ship fleet` (non-local) requires Manifest Cloud for PR operations

## [39.2.2] - 2026-04-04

**Release Type:** Patch

### Fixes

- Fixed CHANGELOG.md detection pattern to match `## [version]` format (not just `^[`)
- Fixed INDEX.md sed to update version in link display text (not just filenames)
- Fixed sed backup file cleanup for README.md on macOS
- Added release note link updating to README.md sed pass

## [39.2.1] - 2026-04-04

**Release Type:** Patch

### Improvements

- Upgraded installed CLI via Homebrew to activate documentation preservation fixes
- Restored polished documentation

## [39.2.0] - 2026-04-04

**Release Type:** Minor

### Documentation Preservation

- Documentation generation now preserves user-crafted README, CHANGELOG, and INDEX content
- `update_readme_version()` updates inline version strings only (no metadata block prepend)
- `generate_docs_index()` updates version references in place instead of replacing the file
- Root CHANGELOG.md is preserved when it contains Keep-a-Changelog-style entries
- Comprehensive documentation overhaul across all 12 files
- README rewritten as a polished GitHub landing page

## [39.1.0] - 2026-04-04

**Release Type:** Minor

### Documentation Overhaul

- Comprehensive documentation overhaul across all 12 documentation files
- Command Reference expanded with full flag tables and fleet subcommand sections
- Installation guide enhanced with troubleshooting table

## [39.0.0] - 2026-04-04

**Release Type:** Major

### New Features

- **Smart `.gitignore` scaffolding** — `ensure_gitignore_smart()` handles three scenarios:
  no file (create), empty file (overwrite with defaults), existing entries (create `.gitignore.manifest` reference)
- **Fleet auto-discovery by default** — `manifest fleet init` discovers repositories automatically;
  use `--bare` to skip discovery
- **Best-practice `.gitignore` template** — comprehensive ignore file

### Breaking Changes (v39.0.0)

- `manifest fleet init` runs discovery by default (previously required `--discover` flag)
- `--discover` / `--no-discover` flags replaced by `--bare`

## [38.2.0] - 2026-04-04

Maintenance release with Homebrew formula updates.

---

For version-specific changelogs, see [docs/](docs/).
For archived releases, see [docs/zArchive/](docs/zArchive/).

<!-- Maintained by Manifest CLI -->
