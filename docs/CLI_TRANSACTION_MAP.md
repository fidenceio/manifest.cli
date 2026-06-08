# Manifest CLI Transaction Map

This map identifies high-consequence paths and their side-effect boundaries.

## Effect Classes

| Effect | Meaning |
| ------ | ------- |
| `read` | Inspect repo, config, fleet, or remote state |
| `local-write` | Modify files, commits, tags, or local metadata |
| `remote-write` | Push, publish, create release, or mutate external state |
| `pr` | Create, update, merge, or queue pull requests |

## Release Transaction

`manifest ship repo patch -y` follows this sequence when all optional features are enabled:

1. Resolve repo identity.
2. Load config layers.
3. Check working tree and branch policy.
4. Compute next version.
5. Bump `VERSION` and any explicit `version.sync` JSON targets.
6. Generate release notes and changelog entry.
7. Update README/docs metadata.
8. Commit release files.
9. Create tag.
10. Push branch and tag.
11. Create or reuse GitHub Release.
12. Update Homebrew tap when canonical CLI release rules apply.

Preview mode stops before local and remote writes. `--local -y` allows local writes and suppresses remote writes.

## Fleet Release Transaction

`manifest ship fleet patch -y`:

1. Resolve fleet root and config.
2. Load selected services discovered through the shared filesystem walker.
3. Inspect each service branch, version, status, and release policy.
4. Skip release-disabled services.
5. Execute repo release flow for release-enabled services.
6. Report per-service success or failure.

Fleet output must make skipped and failed services explicit.

## Homebrew Tap Transaction

The canonical CLI release may update `fidenceio.homebrew.tap/Formula/manifest.rb` after the CLI release artifact is available.

Boundaries:

- Formula update is a distribution update, not a separate product release.
- The tap repo should remain formula-focused.
- The CLI changelog remains the product release source of truth.

## GitHub Release Transaction

GitHub Release creation runs after tag push when `github.release.enabled` is true.

If the release already exists, Manifest reports it and continues. Missing `gh`, missing auth, or non-GitHub origin is a warning unless `github.release.required` is true. This step runs before the Homebrew formula update so a normal release artifact exists even if formula publication later fails.

## Docs Site Transaction

When docs-site generation is enabled:

1. Write managed Jekyll source files under the configured source directory.
2. Refuse unmanaged collisions.
3. Optionally write `.github/workflows/manifest-docs-pages.yml`.
4. Optionally request workflow-based Pages publishing through `gh api`.

The generator does not write `_site`, `.jekyll-cache`, `.bundle`, or vendor build artifacts.

## Failure Principles

- Fail before mutation when Git metadata is not writable.
- Do not use `MANIFEST_CLI_AUTO_CONFIRM` as apply intent.
- Do not continue remote publication when required local release artifacts fail.
- Keep generated docs, changelog text, preview summary, and GitHub Release notes on one release-note path.
