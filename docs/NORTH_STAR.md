# Manifest CLI North Star

Manifest CLI is the local release-control plane for Manifest. It should make release work explicit, auditable, and repeatable for one repo or many.

## Mission

Give developers a safe way to ship fast agent-assisted changes without losing control of versions, changelogs, docs, tags, pushes, releases, and fleet coordination.

## Product Truth

- The command grammar is `manifest <verb> <scope>`.
- Mutating commands preview by default.
- Apply requires `-y` / `--yes`.
- `-y` applies with no confirmation prompt; `MANIFEST_CLI_AUTO_CONFIRM=1` only authorizes an ambiguous target, not apply intent.
- Repo scope resolves from the current Git checkout.
- Fleet scope resolves from reviewed fleet config.
- Cloud is optional.
- Contributor validation is containerized.

## Priorities

1. Keep preview/apply policy consistent across every mutating route.
2. Keep help, docs, examples, completions, and tests in sync.
3. Make fleet dogfood acceptance boring, for a fleet of any size (two or more repos).
4. Use Cloud for optional Standard release-note enrichment without weakening local-first release mechanics.
5. Keep Homebrew publication narrow and automated: tap formula publish only.
6. Never report a completed ship while source release changes remain dirty or post-push commits have advanced the repo past the pushed release head.
7. Never bump a version or commit the user's working tree without the release gate's verdict, or a printed line saying the gate did not run and why. Each gate policy is defined for every ship mode (publish, `--local`, finishing a release), not only the one it was written for.

## Non-Goals

- No hidden auto-release based on inferred change type.
- No rollback of a published release. Recovery is **roll-forward**: ship a new version. `revert` is a viewer — it checks out a tag into detached HEAD and undoes nothing — and no guarded `rollback` verb will be built. A release that reached a remote is history, not state to unwind.
- No path selector for repo ship until the repo-identity contract is redesigned.
- No Cloud dependency for core repo or fleet release.
- No rendering of Kubernetes or other platform manifests, and no setting that names a secret store. Manifest keeps a repo's list of environment variables, writes `.env.example` from it, and exports it as JSON; how those variables reach a build or a running workload is the build's and the platform's design.
- No host dependency installation for contributor validation.
