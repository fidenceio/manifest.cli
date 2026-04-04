# Manifest CLI Documentation

**Version:** 39.4.0 | **Updated:** 2026-04-04

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
| [Configuration Examples](../examples/env.manifest.examples.md) | Templates for enterprise, compliance, open-source, and more |
| [Git Hooks](GIT_HOOKS.md) | Pre-commit secret protection and hook management |

## Architecture

| Document | Description |
| -------- | ----------- |
| [Fleet Design Spec](FLEET_DESIGN_SPEC.md) | Polyrepo orchestration architecture |
| [North Star](NORTH_STAR.md) | Strategic direction and 12-month priorities |
| [Security Analysis](SECURITY_ANALYSIS_REPORT.md) | Security audit report |

## Current Release

| Document | Description |
| -------- | ----------- |
| [Release Notes v39.4.0](RELEASE_v39.4.0.md) | What's new in this release |
| [Changelog v39.4.0](CHANGELOG_v39.4.0.md) | Detailed change log |
| [Archived Releases](zArchive/) | Previous version documentation |

---

## Quick Start

```bash
# Install
brew tap fidenceio/tap && brew install manifest

# Prepare a release locally
manifest prep patch

# Publish a release
manifest ship minor

# Initialize a fleet
manifest fleet init

# Get help
manifest --help
```

<!-- Manifest CLI v39.2.1 -->
