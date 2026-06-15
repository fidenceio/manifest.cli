# Manifest CLI Documentation

Use this index by task. The README is the entry point; this directory carries the detailed operating model and references.

**Version:** 54.1.0 | **Updated:** 2026-06-15

## Start

| Task | Document |
| ---- | -------- |
| Understand the product | [README](../README.md) |
| Install Manifest for product use | [Installation](INSTALLATION.md) |
| Run repo validation as a contributor | [tests/README.md](../tests/README.md) |
| Learn the daily workflow | [User Guide](USER_GUIDE.md) |
| Adopt the preview/apply model & release gate | [Migration Guide](MIGRATION.md) |

## Operate

| Task | Document |
| ---- | -------- |
| Ship one repo | [User Guide: Repository release workflow](USER_GUIDE.md#repository-release-workflow) |
| Ship a fleet | [User Guide: Fleet workflow](USER_GUIDE.md#fleet-workflow) |
| Understand canonical vs non-canonical version files | [User Guide: Version ownership](USER_GUIDE.md#version-ownership) |
| Use PR commands | [User Guide: Pull request workflow](USER_GUIDE.md#pull-request-workflow) |
| Configure Manifest | [User Guide: Configuration](USER_GUIDE.md#configuration) |
| Publish generated docs | [Docs site generation](DOCS_SITE.md) |
| Copy command recipes | [Examples](EXAMPLES.md) |

## Reference

| Reference | Contents |
| --------- | -------- |
| [Command Reference](COMMAND_REFERENCE.md) | Command grammar, flags, effects, and environment behavior |
| [Fleet Design Spec](FLEET_DESIGN_SPEC.md) | Fleet config, detection, adoption, reconciliation, and release behavior |
| [CLI Transaction Map](CLI_TRANSACTION_MAP.md) | Release and tap transaction boundaries |
| [YAML config example](../examples/manifest.config.yaml.example) | Full config shape with comments |
| [Version handler catalog](../modules/catalog/version-handlers.tsv) | Known package/version surfaces used by passive detection |
| [Recipe schema](contracts/recipe.schema.json) | Built-in and project recipe contract |

## Project Direction

| Document | Contents |
| -------- | -------- |
| [North Star](NORTH_STAR.md) | Product direction and cross-repo contract |
| [Tracker](TRACKER.md) | Live implementation work |
| [Changelog](../CHANGELOG.md) | Release history |

## Supporting Docs

| Document | Contents |
| -------- | -------- |
| [Shell completions](../completions/README.md) | Bash and zsh completion installation |
| [Git hooks](../.git-hooks/README.md) | Versioned pre-commit hook |
| [Security analysis](SECURITY_ANALYSIS_REPORT.md) | Current security audit report |
| [Archive](zArchive/INDEX.md) | Historical release docs, reports, and trackers |
