# Manifest CLI Documentation

**Version:** 47.8.4 | **Updated:** 2026-05-08

---

## Getting Started

| Document | Description |
| -------- | ----------- |
| [Installation Guide](INSTALLATION.md) | Setup, upgrade, uninstall, and troubleshooting |
| [User Guide](USER_GUIDE.md) | Workflows, daily commands, and configuration |
| [Examples](EXAMPLES.md) | Real-world command examples |

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
| [Safe-by-Default Execution Notes](SAFE_BY_DEFAULT_EXECUTION_TODO.md) | Execution policy, recipe effects, and remaining hardening work |
| [Improvement Tracker](IMPROVEMENT_TRACKER.md) | Active and completed engineering work queue |
| [North Star](NORTH_STAR.md) | Strategic direction and 12-month priorities |
| [Security Notes](SECURITY_ANALYSIS_REPORT.md) | Current security posture and historical audit pointer |

## Release History

| Document | Description |
| -------- | ----------- |
| [Root Changelog](../CHANGELOG.md) | Current release history |
| [Archived Releases](zArchive/INDEX.md) | Versioned release documentation, grouped by major |

---

## Quick Start

```bash
# Install
brew tap fidenceio/tap && brew install manifest

# Preview and apply project scaffold
manifest init repo
manifest init repo -y

# Preview and apply remote prep
manifest prep repo
manifest prep repo -y

# Preview and apply a patch release
manifest ship repo patch
manifest ship repo patch -y

# Preview a release locally first
manifest ship repo minor --local

# Initialize a fleet
manifest init fleet

# Get help
manifest --help
```
