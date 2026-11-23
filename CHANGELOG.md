# Changelog

## [66.0.0] - 2026-11-23

**Release Type:** Major

### Changes

- Feat(init)!: generate env files from init repo and status repo --env; remove the manifest env command and the Dockerfile block (§127)
- Fix(init): refuse a .env.example that is not a readable file instead of writing through it (§131)
- Test(harness): name the tests allowed to skip in the container leg, replacing the count (§115)
- Docs: describe env generation under init repo and the removed env command
- Test: replace echo-into-grep assertions with herestrings and guard the idiom (§90)
- Docs(tracker): retire §90, §115, §127 and §131; file §128, §129, §130 and §132; extend §106, §109, §110 and §12a
- Fix: test lists with a herestring so a match is not read as no match under pipefail (§133)
- Docs(tracker): retire §133; extend §132 with the product guard and the two sites it cannot see; repair the §90 commit pointer


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
