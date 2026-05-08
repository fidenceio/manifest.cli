# Manifest CLI Documentation

**Version:** 47.6.1 | **Updated:** 2026-05-05

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
| [Bash 5 Runtime TODO](BASH_5_RUNTIME_TODO.md) | Active plan to enforce Bash 5+ across wrappers, subprocesses, and nested Manifest calls |
| [Safe-by-Default Execution TODO](SAFE_BY_DEFAULT_EXECUTION_TODO.md) | Planned breaking change to make mutating commands preview by default and require `-y` to apply |
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
