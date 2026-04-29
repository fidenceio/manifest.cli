# release.tag_target — Post-Ship Self-Review (v44.10.1)

**Status:** Feature shipped 2026-04-26 in v44.10.1. Self-critique below identified
issues to fix methodically before considering the feature production-grade.

**Context.** The feature wires `MANIFEST_CLI_RELEASE_TAG_TARGET` into the ship
workflow so it actually controls which commit the release tag points at:

- `version_commit` (default) — tag the explicit "Bump version to X" commit even
  when a CHANGELOG commit lands after it.
- `final_release_commit` — tag whatever HEAD is at tag-creation time
  (post-CHANGELOG, pre-Homebrew). Homebrew commits are out of reach because
  `update_homebrew_formula` `curl`s the GitHub tarball at the tag URL to compute
  SHA256 — a tag pointing at the formula commit would require the formula to
  contain its own SHA256 (chicken-and-egg).

**Implementation that shipped:**
- [modules/git/manifest-git.sh:227-260](../modules/git/manifest-git.sh#L227-L260) — `create_tag` accepts optional 2nd arg (target SHA).
- [modules/workflow/manifest-orchestrator.sh:267](../modules/workflow/manifest-orchestrator.sh#L267) — captures `workflow_version_commit_sha` after the bump commit.
- [modules/workflow/manifest-orchestrator.sh:316-339](../modules/workflow/manifest-orchestrator.sh#L316-L339) — case block dispatching on the env var.
- [tests/tag_target.bats](../tests/tag_target.bats) — 9 tests.

---

## High severity

### [x] H1. Test mirrors production logic instead of testing it
The dispatch tests in [tests/tag_target.bats](../tests/tag_target.bats) define a
local `resolve_tag_target_sha` helper that's a *copy* of the orchestrator's
case statement. If somebody edits the orchestrator's case block, the tests
still pass against the stale helper — a regression-suite that lies.

**Fix:** Extract the dispatch into a real function (e.g., `resolve_tag_target_sha`)
in `modules/git/manifest-git.sh` (or a new `modules/workflow/manifest-tag-target.sh`).
Have the orchestrator call that function. Have the test source the module and
test the real function. Removes both the test-mirror problem and the
future-drift problem.

### [x] H2. `final_release_commit` is a name that overpromises
The name reads as "the very last commit of the release," but Homebrew commits
cannot be the target due to the SHA256 chicken-and-egg. So the value actually
means "last release-prep commit *before* Homebrew." A user setting this and
seeing a `Update Homebrew formula` commit *past* their tag will reasonably
ask why `final` didn't include it.

**Fix options:**
- (A) Rename the value to something honest: `release_head`, `pre_publish_head`,
  or `pre_homebrew_commit`. Breaking change to the YAML key value, but the
  feature only shipped today — early enough to swap.
- (B) Keep the name and document the asterisk loudly in:
  - `examples/manifest.config.yaml.example` (multi-line comment, not one-liner)
  - `docs/USER_GUIDE.md` and/or `docs/COMMAND_REFERENCE.md`
  - The output of `manifest config show`

Recommendation: (A). A misleading name is a bug; documentation can't fully
patch it. Pair the rename with a backward-compat alias that warns on the old
value for one minor version.

### [x] H3. Silent degradation when SHA capture fails
In [orchestrator.sh:267](../modules/workflow/manifest-orchestrator.sh#L267):
```bash
workflow_version_commit_sha="$(git rev-parse HEAD 2>/dev/null || echo "")"
```
If `git rev-parse` fails, the SHA is empty. The case block then hands `""` to
`create_tag`, which falls through to "tag HEAD" — i.e., `version_commit`
silently behaves like `final_release_commit`, no warning. Worst kind of
degradation: invisible.

**Fix:** If `MANIFEST_CLI_RELEASE_TAG_TARGET=version_commit` and
`workflow_version_commit_sha` is empty, log an error and abort the ship rather
than silently retargeting. Or at minimum log a clear warning saying "version
commit SHA unavailable; falling back to current HEAD."

---

## Medium severity

### [x] M4. `commit_changes` return code unchecked before SHA capture
At [orchestrator.sh:266](../modules/workflow/manifest-orchestrator.sh#L266) the
orchestrator calls `commit_changes "Bump version to $new_version"` without
checking its return code, then captures `git rev-parse HEAD` as the "version
commit SHA." If the commit no-ops (nothing staged, hook reject), the captured
SHA is the *previous* HEAD — likely the auto-commit — and the version tag
lands on a commit titled "Auto-commit before Manifest process."

This is pre-existing behavior, but the new feature makes the misalignment
more consequential (the SHA is now used downstream, not just implicit-via-HEAD).

**Fix:** Either (a) check `commit_changes` return code and abort on failure,
or (b) compare pre/post SHAs and abort if HEAD didn't move when it should
have.

### [x] M5. YAML whitespace tolerance
`tag_target: " version_commit "` (surrounding whitespace, easy to slip in on
copy/paste) loads into the env var verbatim. The case match fails, the user
gets a warning + silent default, and they have no idea why their valid-looking
config didn't take.

**Fix:** Trim whitespace at config load time in `manifest-config.sh` or
`load_yaml_to_env`, OR make the case dispatch tolerant by lowercasing and
trimming first.

### [x] M6. `log_warning` for unknown values isn't test-verified
[tests/tag_target.bats:96-100](../tests/tag_target.bats#L96-L100) checks that
unknown values fall back to `version_commit` semantically, but doesn't capture
stderr to confirm the warning was emitted. A future refactor that drops the
warning would pass tests.

**Fix:** Add an assertion that captures stderr and matches the warning
substring (after H1 lands and the test calls the real function).

### [ ] M7. No coverage for the "CHANGELOG commit between bump and tag" scenario
This is the *only* case where `version_commit` and `final_release_commit`
actually diverge. Without a test that exercises it, the feature's central
distinction is uncovered.

**Fix:** Bats test that sets up a repo with a real CHANGELOG.md, runs through
`manifest_ship_workflow` (or a stripped-down test harness that exercises just
the relevant orchestrator slice), and verifies that:
- With `version_commit`: tag points at the bump commit (pre-CHANGELOG).
- With `final_release_commit`: tag points at the CHANGELOG commit (post-bump).

This requires a workflow-level integration test, which is heavier than the
current unit-style tests. Worth the cost for the feature's only meaningful
behavior delta.

### [x] M8. No CHANGELOG / USER_GUIDE entry for behavior change
The shipped behavior changed: today's release tags now point at the version
commit instead of post-CHANGELOG HEAD by default. For repos with a real
CHANGELOG, that's a visible difference for any automation reading
`git for-each-ref` or `git rev-list <tag>..main`. No release note acknowledges
this.

**Fix:** Update USER_GUIDE.md / COMMAND_REFERENCE.md (or whichever doc
describes the ship workflow) and add a CHANGELOG entry under v44.10.1
(retroactive note is fine — it's the truth).

---

## Maintainability

### [ ] L9. Adding a third tag-target value requires updating two case blocks
The orchestrator's case block + the test helper's case block. After H1 this
collapses to one place — good. Until then, drift risk.

### [ ] L10. The `case` block duplicates the warning text inline
If H1 lands, the warning lives in one place (the extracted function). Until
then the warning text in the orchestrator is unstructured.

---

## Cross-cutting footguns introduced

These aren't separate items to check off — they're the *user impact* of the
issues above. Listed here for completeness:

- **Silent name/behavior mismatch on `final_release_commit`** (H2). Likely
  user report: "why isn't my Homebrew commit inside the tag?"
- **Typo or whitespace in YAML value** (M5). No validation at load time —
  failure is deferred to ship-time and presented as a generic warning.
- **Test-helper duplicates case statement** (H1). Six months from now,
  someone refactors, tests pass, behavior is wrong.
- **Silent fall-back when version-commit SHA is empty** (H3). No telemetry,
  no warning, behavior swap goes unnoticed.

---

## Recommended fix order for tomorrow

1. **H1 first** (extract dispatch to real function). This unblocks honest
   testing for everything else and removes the test-mirror lie.
2. **H3 + M4** (input validation in the orchestrator: SHA capture + commit
   return code). Cheap, defensive, makes silent failures loud.
3. **H2** (rename `final_release_commit` to something honest, with a
   deprecation alias). Now is the time — feature is one day old.
4. **M5** (whitespace/case tolerance in config load).
5. **M7** (integration test for the CHANGELOG-between-bump-and-tag scenario).
6. **M6** (assert the warning is emitted).
7. **M8** (USER_GUIDE + CHANGELOG entry).

After all of these land, the feature is genuinely production-grade rather
than "shipped and tested for the happy path."

---

## What's solid and doesn't need rework

- `create_tag` change itself: small, backward-compatible, well-tested for
  the unit it covers (HEAD vs explicit SHA, prefix/suffix interaction,
  invalid SHA failure).
- Homebrew chicken-and-egg reasoning was re-verified against
  [modules/core/manifest-core.sh:151-159](../modules/core/manifest-core.sh#L151-L159) — it does in fact `curl` the
  GitHub tag URL for SHA256.
- The default (`version_commit`) is what most users want — the "Bump version
  to X" commit is the canonical release artifact.
- The fallback-to-default-on-unknown-value is conservative behavior.
- Verified end-to-end: tag `v44.10.1` points at `eca3e6b` ("Bump version to
  44.10.1"), not at `998fe1f` ("Update Homebrew formula to v44.10.1") —
  proving the dispatch worked on the very release that introduced it.
