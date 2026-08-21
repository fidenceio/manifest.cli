# Manifest CLI Documentation

Find what you need by what you are trying to do. The [README](../README.md) is the place
to start; the documents here go into detail.

**Version:** 59.4.0 | **Updated:** 2026-08-21

## Start

| I want to… | Read |
| ---- | -------- |
| Understand what Manifest is for | [README](../README.md) |
| Install it and check it works | [Installation](INSTALLATION.md) |
| Work on Manifest itself, and run its tests | [tests/README.md](../tests/README.md) |
| Learn the day-to-day workflow | [User Guide](USER_GUIDE.md) |
| Understand "plan first, then apply", and the release gate | [Migration Guide](MIGRATION.md) |

New to the project? Read the README, then the Migration Guide. Those two cover the one
rule that shapes everything else: nothing changes until you pass `-y`.

## Operate

| I want to… | Read |
| ---- | -------- |
| Release one repository | [User Guide: Repository release workflow](USER_GUIDE.md#repository-release-workflow) |
| Release several repositories together | [User Guide: Fleet workflow](USER_GUIDE.md#fleet-workflow) |
| Know which version files Manifest writes, and which it only reads | [User Guide: Version ownership](USER_GUIDE.md#version-ownership) |
| Open, check, or merge pull requests | [User Guide: Pull request workflow](USER_GUIDE.md#pull-request-workflow) |
| Change a setting, or find out why one is what it is | [User Guide: Configuration](USER_GUIDE.md#configuration) |
| Recover from a release that stopped partway | [User Guide: When a release goes wrong](USER_GUIDE.md#when-a-release-goes-wrong) |
| Publish a documentation website | [Docs site generation](DOCS_SITE.md) |
| Copy a working command for a common job | [Examples](EXAMPLES.md) |

## Reference

| Reference | What is in it |
| --------- | -------- |
| [Command Reference](COMMAND_REFERENCE.md) | Every command and flag, exit codes, and the environment variables |
| [Fleet Design Spec](FLEET_DESIGN_SPEC.md) | How fleets are defined, detected, adopted, repaired, and released |
| [CLI Transaction Map](CLI_TRANSACTION_MAP.md) | Exactly what a release changes, in what order, and where it can fail |
| [User Guide — Configuration](USER_GUIDE.md#configuration) | The authoritative layer model: defaults → global → fleet → project → local → env |
| [YAML config example](../examples/manifest.config.yaml.example) | Every setting, with comments |
| [Version handler catalog](../modules/catalog/version-handlers.tsv) | Places version numbers commonly hide, used for read-only detection |
| [Recipe schema](contracts/recipe.schema.json) | The contract a built-in or project recipe must satisfy |

## Project Direction

| Document | What is in it |
| -------- | -------- |
| [North Star](NORTH_STAR.md) | What Manifest is for, what it will not do, and the cross-repo contract |
| [Tracker](TRACKER.md) | The open-work register — every known defect and decision, with evidence |
| [Changelog](../CHANGELOG.md) | Release history |

## Supporting Docs

| Document | What is in it |
| -------- | -------- |
| [Shell completions](../completions/README.md) | Installing tab-completion for bash and zsh |
| [Git hooks](../.git-hooks/README.md) | The pre-commit hook — versioned here, but enabled per clone |
| [Security notes](SECURITY_ANALYSIS_REPORT.md) | Hand-maintained security posture, with the known gaps stated alongside each control |
| [Archive](zArchive/INDEX.md) | Superseded docs, reports, and trackers |
