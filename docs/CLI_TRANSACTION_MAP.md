# Manifest CLI Transaction Map

This map covers the commands whose effects matter most. For each one it lists the
steps in order and says what each step changes: nothing, your machine, or a remote
service.

## Effect Classes

Each step belongs to one of these classes:

| Effect | Meaning |
| ------ | ------- |
| `read` | Inspect repo, config, fleet, or remote state |
| `local-write` | Change files, commits, tags, or local metadata |
| `remote-write` | Push, publish, create a release, or change anything outside your machine |
| `pr` | Create, update, merge, or queue pull requests |

## Repository Initialization

`init` and `init repo` preview by default. A preview writes nothing and makes no
network call.

Applying (`-y`) does the following:

- initializes Git on the configured branch, if needed;
- connects an existing `origin`, or creates a private GitHub repository;
- fast-forwards existing history;
- creates the project files that are absent;
- runs the configured release check.

It keeps existing content. It refuses when the remote, the history, or the check
fails. `--remote URL` selects an existing remote. `--no-connect` creates the local
files only, and readiness is then not verified.

Applying runs no release workflow. It makes no version bump, no new commit, no tag and
no push. The readiness checks can create ordinary build and test output. Reviewing
fleet membership is a separate flow with two phases.

## Release Transaction

`manifest ship repo patch -y` runs these steps, in this order, when every optional
feature is turned on:

1. Find the repository: the `.git` root of the current directory.
2. Load the config layers.
3. Check the working tree and the branch. A clean tree that is already at its release
   tag has nothing to release, and the run stops there unless `--force-bump` is given.
   An unfinished release is found here (see
   [Unfinished Release Transaction](#unfinished-release-transaction)). A publishing
   release must be on the release branch. The run then takes the repository's lock, so
   that only one `ship repo` applies in a repository at a time.
4. CI verdict gate. Manifest reads the result of the latest *completed* run of the
   `tests` workflow on `origin`. If that run is red, Manifest refuses before it changes
   anything. A preview makes no `gh` call. When the result cannot be read (no `gh`, not
   signed in, no completed run, or a result such as `cancelled`), Manifest says the
   verdict is *unverified*. It does not treat it as green, and the release goes on.
   `release.require_ci_green: false` lets a release go on despite a red run; the
   finding is still printed.
5. Release gate (pre-bump). Manifest runs the repository's test gate. This step is a
   `local-write`: when the gate runs and passes, Manifest records the time in
   `.manifest-cli/release-gate-pass.epoch`. The freshness window is measured from that
   record. The `.manifest-cli/` directory holds state for this machine only, and the
   Manifest `.gitignore` template ignores it. A repository that tracks the directory
   will see this write land in the next step's commit.
6. Auto-commit of the changes that were already in the working tree. This step is a
   `local-write` that **creates a commit** from whatever the tree already held, using a
   plain `git add .`. It is listed here because it commits content that nobody reviewed
   for this release, and because it runs *after* step 3 checked the tree and step 5
   wrote to it. It is skipped when the tree is clean. Its scope is a snapshot of the
   pending paths, taken just before step 5. A path that appeared during the gate is
   unstaged and named. The snapshot is dropped after this step. Before step 5,
   `ensure_required_files` may also have created `VERSION`, `README.md`, `CHANGELOG.md`,
   `docs/` or `.gitignore`. Those new files are pending work by the time the snapshot is
   taken, so they land in this commit.
7. Sync with the remote. This is a `git pull`. If it fails, Manifest only warns. If it
   merges, the merge result lands in the tree here.
8. Compute the next version from `VERSION` as it stands after the sync. Write it to
   `VERSION` and to any JSON, TOML or YAML targets named in `version.sync`. One case
   differs: if an earlier run already wrote the next version to `VERSION` and stopped
   before committing it, this run keeps that version. It then skips steps 6 and 7 and
   does not bump again.
9. Generate the release notes and the changelog entry.
10. Update the docs metadata. A file that carries a Manifest-managed block is updated
    in place. A `README.md` or `docs/INDEX.md` with no managed block is left untouched,
    and the run says so. Manifest does not guess who wrote a file from its title or its
    wording.
11. Archive sweep. This step is a `local-write` that **deletes files**, so it is listed
    here. First, audit files that record a single point in time move into
    `docs/zArchive/`. Then temporary files are removed. That removal never touches `.git` and never touches a file that Git
    tracks. Under the docs tree it removes only `*.tmp`, `*.temp`, `*.bak`, `*.backup`
    and `*~`. Across the whole tree it removes only `.DS_Store` and `Thumbs.db`. The
    preview names the files it would remove.
12. Commit the release files. This step is a `local-write` that stages **only the
    release's own write areas**, by name. It never runs `git add .`. The write areas
    are `VERSION` and the `version.sync` targets, `CHANGELOG.md`, the README, the docs
    folder, the docs archive folder, the docs-site source folder and its Pages
    workflow, and `docs.review.report_dir` when it is set. Any other changed path is
    named and left in the working tree. Such a path may come from the merge in step 7,
    a release-notes provider command, a hook, or another session during steps 7–11.
    Step 18 accepts exactly that set of paths. `git.allow_gate_drift: true` brings back
    the whole-tree sweep. The markdown cleaning that runs just before this step
    rewrites only the README and the docs folder, so its writes are inside the write
    areas. When `docs.handoff` pauses a release, the run stops just before this commit
    with exit code `4`: nothing is committed, tagged or pushed.
13. Create the tag. Just before it does, Manifest records the release as in flight in
    `.git/manifest-ship/in-flight`. This record is a `local-write` inside `.git`, so it
    never enters a commit. It is how a later run recognises an unfinished release.
14. Push the branch and the tag. Then set the branch's upstream if it has none. The
    push uses a literal refspec, which never writes tracking config, so a repository
    that only Manifest has pushed would otherwise have no upstream. This is a
    `local-write` that happens *after* the `remote-write`. It is conditional: it is
    skipped when an upstream exists, or when several remotes make the choice unclear.
    It is announced on stdout. It can never fail the ship, because the release is
    already public by then.
15. Release gate (post-push). When `release.gate` is `remote-ci` or `all`, Manifest
    requires the CI for the pushed commit to be green before it publishes anything
    further. The tag is already pushed at this point. Only steps 16 and 17 are held
    back.
16. Create the GitHub Release, or reuse it if it exists.
17. Update the Homebrew tap. This step applies only to Manifest's own repository.
18. Check that the release ended cleanly, before printing success. The source tree
    must be clean, apart from the paths that step 12 named and left. A published ship
    must still have `HEAD` at the release commit it pushed. When the check passes,
    Manifest removes the in-flight record.

A preview changes nothing in the repository and nothing remote.

`--local -y` runs the local steps through the release commit (step 12), and then
step 18. It skips step 4, creates no tag, and runs none of steps 13 to 17.

## Unfinished Release Transaction

A release is unfinished when its in-flight record (step 13 above) is still present. The
record must name the version in the committed `VERSION` file and the commit that the
recorded tag points at. `manifest ship repo <type>` then plans a finish and no bump, and `-y` runs it:

1. Read the in-flight record and the local tag. This is a `read`. No network call is
   used to decide whether a release is unfinished.
2. Refuse before any write when `HEAD` is detached, when the tag is not in the current
   branch's history, or when the working tree has changes other than
   `formula/manifest.rb`.
3. Push the branch and the tag. This is a `remote-write`. A ref that is already pushed
   is left as it is.
4. Run the release gate's post-push check, as in step 15 above, on the commit the tag
   points at. If it fails, stop: nothing is published and the record stays.
5. Create or reuse the GitHub Release. Then, for Manifest's own repository, update the
   Homebrew tap.
6. Check that the release ended cleanly, as in step 18 above. Then remove the in-flight
   record.

A finish makes no version bump, no commit and no tag. It does not run the CI verdict
gate or the pre-bump release gate again; those ran before the tag was made. The push in
step 3 is of the branch, so commits made after the tag are pushed with it, and the plan
lists them. `--local` cannot finish a release, because a finish
pushes; it refuses in both the plan and the apply. `--force-bump` leaves the unfinished
release as it is and runs the ordinary release transaction.

## Fleet Release Transaction

`manifest ship fleet patch -y` runs these steps. Some output calls a member a "service";
the two words mean the same thing here.

1. Find the fleet root and load its config.
2. Load the selected members, which are discovered through the shared filesystem
   walker.
3. Inspect each member's branch, version, status and release policy.
4. Run the pre-flight checks. One of them is the workspace policy gate
   (`scripts/manifest-fleet-preflight.sh`). A preview names that gate and, by default,
   does not run it. Apply refuses when a pre-flight check fails. Then take the fleet lock, so that only one fleet ship
   applies at a time.
5. Skip the members that have releases turned off, and the eligible members that have
   nothing to release.
6. Run the repo release transaction for each release-enabled member that has something
   to release. A member with an unfinished release is finished and is not bumped. With
   `--local`, such a member makes the whole apply refuse before any member is touched.
7. Record the member commits in `manifest.fleet.snapshot.json`. Then commit and push
   the fleet manager (the coordination root). This also happens when every member was
   skipped, and when `fleet.versioning` is `none`. Only the declared coordination files
   are staged. With `--local`, the commit is made and nothing is pushed.
8. Report the member outcomes and the manager outcome separately. A manager failure
   returns `1` when no member was released, and `2` after a member was released.

Fleet output must name every skipped member and every failed member.

## Fleet Manager Transaction

`manifest ship fleet manager -y` commits and pushes the fleet **coordination root**
only. No member is touched. The root gets none of the repo release steps: no `VERSION`
bump, no tag, no GitHub Release and no Homebrew update.

1. Find the fleet root and load its config.
2. Plan. This is a `read`. The plan lists the coordination files that are new or
   changed. It says whether the allowlist `.gitignore` must be written, whether the
   fleet version file will be stamped (only when `fleet.versioning` is not `none`), and
   whether there is anything to push.
3. Refuse before any write if a file outside the coordination allowlist is already
   staged at the root, or if the root is on a detached `HEAD`.
4. Take the fleet lock. It is the same lock that `ship fleet` holds, because the last
   step of `ship fleet` writes the same root.
5. Make sure the root is a Git repository that has the allowlist `.gitignore`.
6. Stamp the fleet version file, if the plan said so.
7. Stage the coordination files **by name**. Check that nothing else is staged. Commit.
8. Push the current branch to `origin`, unless `--local` was given. A failed push is an
   error here, not a warning, because pushing is the purpose of the command.

The allowlist is a single list, `_fleet_coordination_files`. The `.gitignore` writer,
the stager, and the check on the staged set all read it.

## Homebrew Tap Transaction

This transaction applies only to Manifest's own repository. After the release exists,
the release may publish an updated `Formula/manifest.rb` in `fidenceio/homebrew-tap`.
Manifest generates the tap formula from the tracked template `formula/manifest.rb` in
the CLI repository. It does not commit a release-time formula change back into the CLI
repository.

After the formula is published, Manifest tries to upgrade the Manifest CLI installed on
this machine, through Homebrew when it was installed that way. This changes the
machine, not the repository. If the upgrade does not complete, Manifest prints a
warning and the ship still succeeds. After a release that is not a `patch`, Manifest may then run one
follow-up `patch` release with the newly installed CLI.
`MANIFEST_CLI_SHIP_FOLLOWUP_PATCH=false` turns that off.

Boundaries:

- A formula update is a distribution update. It is not a separate product release.
- The tap repository should hold formulas and little else.
- The CLI changelog remains the source of truth for product releases.
- The CLI release branch must not move past the release tag only to carry generated
  Homebrew formula content.
- If any step after the push changes the CLI repository's working tree, or creates a
  source commit on top of the pushed release, the ship fails and does not report
  success.

## GitHub Release Transaction

Manifest creates a GitHub Release after the tag is pushed and the post-push release
gate has passed, when `github.release.enabled` is true.

- If the release already exists, Manifest reports that and continues.
- If `gh` is not installed or not signed in, or `origin` is not a GitHub repository,
  the step is skipped and the ship continues.
- If creating the release fails, Manifest prints a command to retry it. The ship
  continues, unless `github.release.required` is true. In that case the ship fails.

This step runs before the Homebrew tap formula is published. A normal release therefore
exists even if publishing the formula fails later.

## Docs Site Transaction

When docs-site generation is turned on:

1. Write the managed Jekyll source files under the configured source directory.
2. Refuse to overwrite a file at one of those paths that Manifest does not manage.
3. Optionally write `.github/workflows/manifest-docs-pages.yml`.
4. Optionally ask GitHub, through `gh api`, to publish Pages from that workflow.

The generator does not write `_site`, `.jekyll-cache`, `.bundle`, or vendor build
output.

## Failure Principles

- Fail before changing anything when Git metadata is not writable.
- `MANIFEST_CLI_AUTO_CONFIRM` never starts an apply. Only `-y` / `--yes` does.
- Do not go on to publish remotely when a required local release file could not be
  produced.
- Take the generated docs, the changelog text, the preview summary and the GitHub
  Release notes from one source of release notes, so that they cannot disagree.
