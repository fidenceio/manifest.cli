# Manifest CLI Documentation

**Version:** 46.13.12 | **Updated:** 2026-05-05

---

## Getting Started

| Document | Description |
| -------- | ----------- |
| [Installation Guide](INSTALLATION.md) | Setup, upgrade, uninstall, and troubleshooting |
| [User Guide](USER_GUIDE.md) | Workflows, daily commands, and configuration |
| [Examples](EXAMPLES.md) | Real-world workflow recipes |

## Reference

| Document | Description |
| -------- | ----------- |
| [Command Reference](COMMAND_REFERENCE.md) | Every command, flag, and option |
| [YAML config example](../examples/manifest.config.yaml.example) | Full schema with all keys + comments |

## Architecture

| Document | Description |
| -------- | ----------- |
| [Fleet Design Spec](FLEET_DESIGN_SPEC.md) | Polyrepo orchestration architecture |
| [Improvement Tracker](IMPROVEMENT_TRACKER.md) | Active and completed engineering work queue |
| [North Star](NORTH_STAR.md) | Strategic direction and 12-month priorities |
| [Security Notes](SECURITY_ANALYSIS_REPORT.md) | Current security posture and historical audit pointer |

## Current Release

| Document | Description |
| -------- | ----------- |
| [Release Notes v46.13.10](RELEASE_v46.13.10.md) | What's new in this release |
| [Changelog v46.13.10](CHANGELOG_v46.13.10.md) | Detailed change log |
| [Archived Releases](zArchive/INDEX.md) | Previous version documentation, grouped by major |

---

## Quick Start

```bash
# Install
brew tap fidenceio/tap && brew install manifest

# Scaffold a new project
manifest init repo

# Connect remotes and pull latest
manifest prep repo

# Ship a patch release
manifest ship repo patch

# Preview a release locally first
manifest ship repo minor --local

# Initialize a fleet
manifest init fleet

# Get help
manifest --help
```
