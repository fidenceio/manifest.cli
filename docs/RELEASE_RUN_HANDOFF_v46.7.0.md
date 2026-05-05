# Release Run Handoff: v46.7.0

**Date:** 2026-05-05
**Command requested:** `manifest ship repo minor`
**Repository:** `fidenceio/manifest.cli`
**Result:** Release artifacts, tag, main branch, and Homebrew tap were pushed, but the run exposed new release-flow defects that remain open.

## Final State

- Version is `46.7.0`.
- CLI repo `main` is pushed to `origin/main`.
- Tag `v46.7.0` is pushed to origin.
- Homebrew formula in this repo points at `v46.7.0`.
- Homebrew tap commit `58d84ad` updated the tap formula to `v46.7.0`.
- CLI repo commit `7f92aaf` updated this repo's formula to `v46.7.0`.
- CLI repo and local Homebrew tap checkout were clean after the run.

## Commits Created

- `2fae1f1` - Auto-commit before Manifest process; captured the fleet repo-identity planning notes and generated documentation review.
- `154f87e` - Bump version to `46.7.0`; generated release docs/changelog and archived `46.6.0` docs.
- `7f92aaf` - Update Homebrew formula to `v46.7.0`.
- Homebrew tap: `58d84ad` - Update formula to `v46.7.0`.

## What Went Wrong

1. The installed Homebrew `manifest` failed before command dispatch.
   - `manifest status` and `manifest ship repo minor` both failed from `/opt/homebrew/Cellar/manifest/46.4.2`.
   - After upgrade, `/opt/homebrew/Cellar/manifest/46.7.0` still fails the same way.
   - Error:

   ```text
   manifest-yaml.sh: line 31: version.format: syntax error: invalid arithmetic operator
   manifest-yaml.sh: line 5: main: command not found
   ```

   Likely cause: the installed entrypoint is running Bash 3.2 against `declare -gA` / associative-array YAML mapping in `modules/core/manifest-yaml.sh`.

2. The repo-local CLI had to be used as a workaround.
   - Working command: `./scripts/manifest-cli.sh ship repo minor`.
   - That path re-execed into Bash 5 and completed the local release work.

3. The ship workflow aborted at the push step even though a manual push later succeeded.
   - The workflow created commits and tag locally, then failed pushing to `origin`.
   - Manual recovery push succeeded:

   ```bash
   git push origin main --follow-tags
   git push origin v46.7.0
   ```

4. The failure report suggested `git push origin main --follow-tags`, but that did not publish the lightweight tag.
   - The explicit tag push was still required.
   - `git ls-remote --tags origin v46.7.0` later confirmed the tag only after `git push origin v46.7.0`.

5. The ship workflow does not resume after a recovered push.
   - Because the workflow returned at `push_changes`, it skipped Homebrew formula update and local upgrade.
   - Homebrew formula update had to be run manually through `update_homebrew_formula`.

6. Homebrew upgrade installed `46.7.0`, but postinstall failed.
   - `brew upgrade manifest` installed the package and removed `46.4.2`.
   - Postinstall command failed:

   ```text
   /opt/homebrew/Cellar/manifest/46.7.0/bin/manifest config doctor --fix --file ...
   manifest-yaml.sh: line 31: version.format: syntax error
   ```

7. `manifest status` output formatting exposed a counter bug.
   - During the pre-ship check, `Working:` rendered as split lines like `2 modified, 0` and `0 untracked`.
   - Likely cause: `grep -c ... || echo 0` emits both `0` from `grep -c` and `0` from `echo` when grep returns 1 on no matches.

## Open Follow-Ups

These are now tracked in `docs/IMPROVEMENT_TRACKER.md` as items #30 through #34:

- Fix installed Homebrew startup under Bash 3.2 / Bash 5 re-exec.
- Make ship push recovery/resume explicit.
- Fix tag push semantics and failure-report recovery commands.
- Fix `manifest status` working-tree count rendering.
- Make Homebrew postinstall non-fragile and covered by tests.

## Known Good Recovery Commands From This Run

```bash
git push origin main
git push origin v46.7.0
/opt/homebrew/bin/bash -lc 'source modules/core/manifest-core.sh && update_homebrew_formula'
git add formula/manifest.rb
git commit -m "Update Homebrew formula to v46.7.0"
git push origin main
brew update
brew upgrade manifest
```

The last command installed `46.7.0` but still reported postinstall failure due to the startup bug.
