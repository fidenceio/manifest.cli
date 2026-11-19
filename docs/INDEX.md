# Manifest CLI Documentation

Find what you need by what you are trying to do. Start with the
[README](../README.md). The documents listed here go into detail. For the current
version, see [CHANGELOG.md](../CHANGELOG.md). Its newest entry always states it.

## Start

| I want to… | Read |
| ---- | -------- |
| Understand what Manifest is for | [README](../README.md) |
| Install it and check it works | [Installation](INSTALLATION.md) |
| Work on Manifest itself, and run its tests | [tests/README.md](../tests/README.md) |
| Learn the day-to-day workflow | [User Guide](USER_GUIDE.md) |
| Understand "plan first, then apply" | [User Guide: Preview and apply](USER_GUIDE.md#preview-and-apply) |
| Understand the release gate, or adjust scripts after an upgrade | [Migration Guide](MIGRATION.md) |

If you are new to the project, read the README first and then the User Guide. Both
explain the one rule that shapes everything else: nothing changes until you pass `-y`.

## Operate

| I want to… | Read |
| ---- | -------- |
| Release one repository | [User Guide: Repository release workflow](USER_GUIDE.md#repository-release-workflow) |
| Release several repositories together | [User Guide: Fleet workflow](USER_GUIDE.md#fleet-workflow) |
| Know which version files Manifest writes, and which it only reads | [User Guide: Version ownership](USER_GUIDE.md#version-ownership) |
| Open, check, or merge pull requests | [User Guide: Pull request workflow](USER_GUIDE.md#pull-request-workflow) |
| Change a setting, or find out why one is what it is | [User Guide: Configuration](USER_GUIDE.md#configuration) |
| Find out why a setting that names a command was ignored | [User Guide: Layer model](USER_GUIDE.md#layer-model) |
| Find out why my fleet version file will not `git add` | [User Guide: Renaming the fleet version file](USER_GUIDE.md#renaming-the-fleet-version-file) |
| Finish a release that stopped partway | [User Guide: When a release goes wrong](USER_GUIDE.md#when-a-release-goes-wrong) |
| Publish a documentation website | [Docs site generation](DOCS_SITE.md) |
| Copy a working command for a common job | [Examples](EXAMPLES.md) |

## Reference

| Reference | What is in it |
| --------- | -------- |
| [Command Reference](COMMAND_REFERENCE.md) | Every command and flag, the exit codes, and the environment variables |
| [Fleet Design Spec](FLEET_DESIGN_SPEC.md) | How fleets are defined, detected, adopted, repaired, and released |
| [CLI Transaction Map](CLI_TRANSACTION_MAP.md) | Exactly what a release changes, in what order, and where it can fail |
| [User Guide — Configuration](USER_GUIDE.md#configuration) | The authoritative description of the config layers: defaults → global → fleet → project → local → env |
| [YAML config example](../examples/manifest.config.yaml.example) | Every setting, with comments |
| [Version handler catalog](../modules/catalog/version-handlers.tsv) | The places where version numbers are commonly found. Manifest uses it to detect them, never to write them |
| [Recipe schema](contracts/recipe.schema.json) | The rules that a built-in or project recipe must follow |

## Project Direction

| Document | What is in it |
| -------- | -------- |
| [North Star](NORTH_STAR.md) | What Manifest is for, its standing priorities, and what it will not do |
| [Tracker](TRACKER.md) | The register of open work: every known defect and pending decision, with evidence |
| [Changelog](../CHANGELOG.md) | Release history |

## Supporting Docs

| Document | What is in it |
| -------- | -------- |
| [Shell completions](../completions/README.md) | Installing tab-completion for Bash, zsh, and fish |
| [Git hooks](../.git-hooks/README.md) | The pre-commit hook. It is versioned in the repository, but each clone must enable it |
| [Security notes](SECURITY_ANALYSIS_REPORT.md) | A hand-maintained account of Manifest's security controls, with the known gaps stated beside each one |
| [Archive](zArchive/INDEX.md) | Superseded docs, reports, and trackers |
