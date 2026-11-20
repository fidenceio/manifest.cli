# Changelog

## [65.0.0] - 2026-11-20

**Release Type:** Major

### Changes

- Feat(env)!: remove k8s/env rendering and env.secrets; add env export and a reference renderer (§104)
- Docs: describe env export and the end of k8s/env rendering
- Docs(tracker): retire §104, extend §105 and §106, file §125 and §126


## [64.0.0] - 2026-11-19

**Release Type:** Major

### Changes

- Fix(ship): write every step and the result to the run log (§112)
- Feat(ship)!: finish an unfinished release from the ordinary plan; remove ship repo resume and ship fleet resume (§113)
- Fix(ship): report a release stopped by the post-push gate as pushed, with no tag-delete or reset advice (§16)
- Fix(fleet): make the topics-off hint a command that does what it says
- Docs: rewrite the guides for the unfinished-release flow
- Docs(tracker): retire §112 and §113, record the §104 re-decision, file the review findings through §124


## [63.0.3] - 2026-11-17

**Release Type:** Patch

### Changes

- Docs(tracker): file §111 as open (GitHub Actions off for the organisation; the ship's CI tick describes an older commit), put its question ahead of the order and its fix first in item 2, cross-reference §12, §68 and §91


## [63.0.2] - 2026-11-14

**Release Type:** Patch

### Changes

- Fix(homebrew): render the tap formula with its own header instead of the template's sentinel comment
- Chore(repo): delete the three retired *.manifest sidecars and their mentions in robots.txt and ai.txt
- Chore(docs): delete the three superseded trackers under docs/zArchive/trackers
- Chore(canonical): drop the pre-rename fidenceio.manifest.cli slug from every default
- Docs: correct stale names in comments, help text and examples
- Docs(contributing): write down the two audiences and point the agent charters at it
- Docs(tracker): close §1(e) and §36's shipped instance, file §107, refresh §1, §11 and §67
- Docs(tracker): file §104-§106 from the env fixture run, promote §98 to T2, order the fix release
- Fix(env): pass the Dockerfile bridge block to awk through the environment, so macOS can update it (§108)
- Fix(env): read secret, required and public through one predicate and refuse a flag that is not a boolean (§98)
- Fix(env): env generate replaces only the files it wrote; a hand-authored .env.example or k8s/env file is left untouched (§3(d))
- Docs(migration): point the §97 section at a phrase its CHANGELOG entry actually carries
- Docs(tracker): retire §98 and §108, close §3(d), file §109 and §110, re-anchor the env items and the citation table


## [63.0.1] - 2026-11-10

**Release Type:** Patch

### Changes

- Fix(docs): land every managed-doc write through one stage-beside-the-target helper (§3)
- Docs(tracker): file §3's write-then-rename slice as fixed and point the resume order at it
- Fix(init): judge .gitignore upgrades by what the file decides, not by its lines (§1(a))
- Docs(tracker): file §1(a) as fixed with its two review corrections, and §102 for the inert .yarn/ negations
- Fix(git): stage only the release write areas in the ship's version commit (§4)
- Docs(tracker): retire §4 as fixed, file §103 for the writers that ignore docs.folder and files.readme
- Test(release-gate): supply the make the gate's image would, so the copy-branch test runs on the Alpine leg
- Test(container): install kustomize in both CI legs, record the three new platform skips, and fix a backwards stat shim


## [63.0.0] - 2026-11-09

**Release Type:** Major

### Changes

- Feat(env)!: the secret store is configuration; generate fails closed without it and a Component fills {env} (§97)
- Fix(init): the scaffolded release gate mounts the checkout read-only and copies it inside; host writes are an explicit opt-out (§100)
- Docs(tracker): retire §97 and §100, file §98 and §101, re-anchor §1(d)
- Test(release-gate): supply the clean-room input instead of assuming it, and probe docker after dropping the stub


## [62.2.0] - 2026-11-09

**Release Type:** Minor

### Changes

- Fix(ci): write the ShellCheck file lists under /tmp, not into the repo mount (§88)
- Docs(agents): make the scrum-master charters' §88 deferral example historical
- Feat(install): add top_level_commands to the IDE catalog; guard it and COMMAND_REFERENCE against the dispatcher (§72)
- Docs(tracker): retire §72 into the release that follows
- Fix(security): make the PII detector fire; refuse to read a failed scan as clean (§2b)
- Fix(security): scan for private key material and refuse to sweep it into a commit (§2a)
- Docs(tracker,migration): record §2(a)/(b), re-cut the resume order PRODUCT-first, decide the d6a8cfc increment
- Docs(tracker): file the IDE-catalog lead under §11; make the resume baseline version-free; re-title §2 to its remainder and rank it below §4


## [62.1.0] - 2026-11-05

**Release Type:** Minor

### Changes

- Feat(cli)!: remove single-letter switches; only -y keeps a short form
- Docs(reference): drop short spellings from COMMAND_REFERENCE usage lines


## [62.0.1] - 2026-10-21

**Release Type:** Patch

### Changes

- Fix(ci): restore required native macOS validation
- Test(ci): isolate release recipe checks from checkout branch state
- Test(ci): exercise generated gates on native runners without Docker
- Test(ci): keep Docker fixture state outside product namespace
- Chore(agents): add Codex mirrors of the four .claude/agents charters
- Docs(site): add Fleet mechanics and decision-tree pages (v63 design preview)
- Docs(tracker): file the v63 Fleet design as §93–§96; prune §34's clone half into §95a


## [62.0.0] - 2026-09-18

**Release Type:** Major

### Behaviour changes on upgrade

- **Command cleanup is intentionally breaking.** Use bare `manifest init` for guided onboarding. `first`, `prep`, `refresh`, `sync`, `time`, the noun-first `fleet` route, bare `ship <bump>`, and `recipe run` are removed rather than retained as hidden aliases. Use `init repo` / `init fleet`, `ship repo <bump>` / `ship fleet <bump>`, and the documented recipe commands. Removed routes and flags refuse before configuration or upgrade side effects. See docs/MIGRATION.md.
- **Init prepares the repository for shipping and previews by default.** Apply with `-y` to initialize Git, establish or create the origin (private by default), connect existing history before scaffolding, preserve existing files, and run the configured readiness checks. Init does not commit, bump, tag, release, or push. Existing project checks retain their execution behavior; generated checks install their dependencies inside Docker.
- **Fleet ships include the manager repository**, including manager-only coordination changes and fleets with versioning disabled. Manager commits stage only coordination files and report partial failures accurately.
- **Revert requires an explicit scope.** `revert repo` restores an exact release tag; `revert fleet` restores the member commits recorded in a manager snapshot. Both preview by default. Apply validates targets and write guards; fleet restore preflights all repositories and restores the manager last. Earlier manager history without a snapshot map cannot reconstruct a fleet.
- **A `MANIFEST_CLI_*` environment override containing spaces or newlines now takes effect correctly.** GNU `env` quoting previously corrupted that highest-precedence layer from v47.11.0 through v61.2.1. After upgrading, settings that were silently ignored may become active.

### Fixes

- Redact credentials in init remote previews and replay hints while retaining the actual URL for execution.
- Preserve local and remote content during init; refuse unreadable origins, divergence, conflicting targets, incorrect release branches, missing identity, invalid versions, and failed or missing verification. Project configuration and configuration fetched from origin select the same checks and release branch as the next ship.
- Preserve conflicting tracked, untracked, and ignored files during revert; resolve annotated tags to exact commits; reject fleet traversal, symlink escapes, duplicate paths, malformed snapshots, and locked targets. Partial restore failures identify the unfinished work.
- Preserve readonly module constants during uninstall's exported-variable sweep, and enumerate exported names without parsing `env` output.
- Honor `MANIFEST_CLI_HOMEBREW_TAP_CHECKOUT` for formula publication from containers and CI without a local Homebrew installation; an invalid explicit checkout fails rather than choosing another tap.
- Continue HTTPS timestamp verification, caching, and labelled system-time fallback through the retained timestamp functions and `manifest config time`.

### Tests and verification

- Run CI validation inside containers without installing dependencies on runner hosts. Native macOS-only cases remain an explicit coverage gap.
- Add init-to-first-local-ship, manager shipping, and repo/fleet restore regressions using disposable local Git repositories.
- Enforce both passing controls and challenging cases for all 24 registered safety contracts in full, smoke, and change-aware runs. Missing, failed, duplicated, or skipped proofs fail the contract gate.
- Include all runtime shell files in the executable-line coverage denominator, including never-loaded files. Report line coverage separately from the safety-contract gate; this release does not claim 100% executable-line coverage.
- Validate parser failure with malformed syntax supported by both older and current yq; current yq intentionally accepts conditional expressions that an obsolete negative control rejected.
- Keep coverage source mounts read-only, preserve the checkout's version in malformed-input fixtures, and prevent large TAP streams from blocking the coverage tracer. Verification-script changes invalidate cached green results.

### Documentation

- Update command reference, migration instructions, workflow examples, shell completions, installer command catalogs, and transaction documentation to match the final command surface. Preserve historical tracker evidence while pointing live onboarding links at the retained modules.
