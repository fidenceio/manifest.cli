# Manifest CLI North Star

Manifest CLI is the local release-control plane for Manifest. It should make release work explicit, auditable, and repeatable for one repo or many.

## Mission

Give developers a safe way to ship fast agent-assisted changes without losing control of versions, changelogs, docs, tags, pushes, releases, and fleet coordination.

## Product Truth

- The command grammar is `manifest <verb> <scope>`.
- Mutating commands preview by default.
- Apply requires `-y` / `--yes`.
- `MANIFEST_CLI_AUTO_CONFIRM=1` is prompt automation, not apply intent.
- Repo scope resolves from the current Git checkout.
- Fleet scope resolves from reviewed fleet config.
- Cloud is optional.
- Contributor validation is containerized.

## Priorities

1. Keep preview/apply policy consistent across every mutating route.
2. Keep help, docs, examples, completions, and tests in sync.
3. Make five-repo fleet dogfood acceptance boring.
4. Use Cloud for optional Standard release-note enrichment without weakening local-first release mechanics.
5. Keep Homebrew publication narrow and automated: formula update only.

## Non-Goals

- No hidden auto-release based on inferred change type.
- No path selector for repo ship until the repo-identity contract is redesigned.
- No Cloud dependency for core repo or fleet release.
- No host dependency installation for contributor validation.
