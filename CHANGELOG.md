# Changelog

All notable changes to Manifest CLI are documented here.
This project uses [Semantic Versioning](https://semver.org/).

## [39.1.0] - 2026-04-04

**Release Type:** Minor

### Improvements

- Comprehensive documentation overhaul across all 12 documentation files
- README rewritten as a polished GitHub landing page with clear value proposition
- All release notes and changelogs now contain actual change details instead of templates
- Command Reference expanded with full flag tables and fleet subcommand sections
- User Guide expanded with v39.0.0 fleet auto-discovery and smart gitignore coverage
- Examples updated with fleet init, coordinated releases, and offline workflows
- Fleet Design Spec updated for auto-discovery default behavior and `--bare` flag
- Installation guide enhanced with troubleshooting table
- Documentation index restructured into Getting Started, Reference, Architecture, and Release sections

## [39.0.0] - 2026-04-04

**Release Type:** Major

### New Features

- **Smart `.gitignore` scaffolding** — `ensure_gitignore_smart()` handles three scenarios automatically:
  no file (create), empty file (overwrite with defaults), existing entries (create `.gitignore.manifest` reference)
- **Fleet auto-discovery by default** — `manifest fleet init` now discovers all Git repositories
  in your workspace automatically; use `--bare` to skip discovery and create a template only
- **Best-practice `.gitignore` template** — new `create_default_gitignore()` generates a comprehensive
  ignore file covering OS files, editors, secrets, dependencies, builds, and more

### Improvements

- Fleet init ensures every discovered repo has a properly configured `.gitignore`
- Deferred warning pattern for empty-overwrite scenarios
- `.gitignore.manifest` is self-cleaning (included in the default `.gitignore` template)
- Error handling on all `.gitignore` write operations

### Breaking Changes (v39.0.0)

- `manifest fleet init` now runs discovery by default (previously required `--discover` flag)
- `--discover` / `--no-discover` flags replaced by `--bare`

## [38.2.0] - 2026-04-04

Maintenance release with Homebrew formula updates.

## [38.1.0] - 2026-04-04

Maintenance release.

---

For version-specific changelogs with full commit details, see [docs/](docs/).
For archived release documentation, see [docs/zArchive/](docs/zArchive/).

<!-- Maintained by Manifest CLI -->
