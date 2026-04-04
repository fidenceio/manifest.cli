# Changelog

All notable changes to Manifest CLI are documented here.
This project uses [Semantic Versioning](https://semver.org/).

## [39.1.1] - 2026-04-04

**Release Type:** Patch

### Improvements

- Fixed documentation generation to preserve user-crafted README, CHANGELOG, and INDEX content
- `update_readme_version()` no longer prepends a metadata block; updates inline version strings only
- `generate_docs_index()` updates version references in place instead of replacing the file
- Root CHANGELOG.md is no longer overwritten when it contains Keep-a-Changelog-style entries
- Restored polished documentation across all files after generation logic fix

## [39.1.0] - 2026-04-04

**Release Type:** Minor

### Documentation Overhaul

- Comprehensive documentation overhaul across all 12 documentation files
- README rewritten as a polished GitHub landing page with clear value proposition
- All release notes and changelogs now contain actual change details instead of templates
- Command Reference expanded with full flag tables and fleet subcommand sections
- User Guide expanded with v39.0.0 feature coverage
- Examples updated with fleet init, coordinated releases, and offline workflows
- Fleet Design Spec updated for auto-discovery default behavior and `--bare` flag
- Installation guide enhanced with troubleshooting table

## [39.0.0] - 2026-04-04

**Release Type:** Major

### New Features

- **Smart `.gitignore` scaffolding** — `ensure_gitignore_smart()` handles three scenarios:
  no file (create), empty file (overwrite with defaults), existing entries (create `.gitignore.manifest` reference)
- **Fleet auto-discovery by default** — `manifest fleet init` discovers repositories automatically;
  use `--bare` to skip discovery
- **Best-practice `.gitignore` template** — comprehensive ignore file covering OS files, editors,
  secrets, dependencies, builds, and more

### Breaking Changes (v39.0.0)

- `manifest fleet init` runs discovery by default (previously required `--discover` flag)
- `--discover` / `--no-discover` flags replaced by `--bare`

## [38.2.0] - 2026-04-04

Maintenance release with Homebrew formula updates.

## [38.1.0] - 2026-04-04

Maintenance release.

---

For version-specific changelogs, see [docs/](docs/).
For archived releases, see [docs/zArchive/](docs/zArchive/).

<!-- Maintained by Manifest CLI -->
