# Manifest CLI Documentation

**Version:** 46.7.0 | **Updated:** 2026-04-06

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
| [Command Reference](COMMAND_REFERENCE.md) | Every command, flag, and option (v42 structure) |
| [YAML config example](../examples/manifest.config.yaml.example) | Full schema with all keys + comments |
| [Git Hooks](GIT_HOOKS.md) | Pre-commit secret protection and hook management |

## Architecture

| Document | Description |
| -------- | ----------- |
| [Fleet Design Spec](FLEET_DESIGN_SPEC.md) | Polyrepo orchestration architecture |
| [Improvement Tracker](IMPROVEMENT_TRACKER.md) | Active and completed engineering work queue |
| [v46.7.0 Release Run Handoff](RELEASE_RUN_HANDOFF_v46.7.0.md) | Ship-run state, recovery steps, and new release-flow issues |
| [North Star](NORTH_STAR.md) | Strategic direction and 12-month priorities |
| [Security Analysis](SECURITY_ANALYSIS_REPORT.md) | Security audit report |

## Current Release

| Document | Description |
| -------- | ----------- |
| [Release Notes v46.7.0](RELEASE_v46.7.0.md) | What's new in this release |
| [Changelog v46.7.0](CHANGELOG_v46.7.0.md) | Detailed change log |
| [Archived Releases](zArchive/) | Previous version documentation |

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
