# Repo-Creation Code Paths — Self-Review

**Status:** 9/9 closed (2026-04-28). Bats suite 150/150 green (was 129/129;
+9 tests for `init repo`/`prep repo` create-repo flags, +7 tests covering
fleet wiring and `_manifest_require_gh` TTL memoization, +5 follow-ups from
the post-ship cohesion audit — see "Cohesion follow-ups" below).

Self-critique of the four functions that create or initialize repositories:
`manifest init repo`, `manifest prep repo`, `_fleet_init_directory`,
and `_fleet_sync_service` / `_fleet_sync_sequential`.

**Context.** Four entry points create state on disk or on the network:

| # | Path | Function | What it does |
| --- | ---- | -------- | ------------ |
| 1 | [modules/core/manifest-init.sh:606-614](../modules/core/manifest-init.sh#L606-L614) | `manifest_init_repo` | `git init` for missing local repo |
| 2 | [modules/core/manifest-prep.sh:73-100](../modules/core/manifest-prep.sh#L73-L100) | `manifest_prep_repo` | Prompts for and adds `origin` if no remote |
| 3 | [modules/fleet/manifest-fleet.sh:557-582](../modules/fleet/manifest-fleet.sh#L557-L582) | `_fleet_init_directory` | `git init` for each selected fleet dir |
| 4 | [modules/fleet/manifest-fleet.sh:959-1100](../modules/fleet/manifest-fleet.sh#L959-L1100) | `_fleet_sync_service`, `_fleet_sync_sequential` | `git clone` for missing fleet services |

`manifest-core.sh` sets `set -eo pipefail` globally, so pipeline exit-status
issues below propagate correctly today — but the constructs still mask the
*reason* a clone failed, which is the user-visible problem.

---

## High severity

### [x] H1. Path-traversal check has a side-effect before it validates

[modules/fleet/manifest-fleet.sh:987](../modules/fleet/manifest-fleet.sh#L987) and [:1061](../modules/fleet/manifest-fleet.sh#L1061):

```bash
abs_clone_path=$(cd "$MANIFEST_FLEET_ROOT" && \
  mkdir -p "$(dirname "$path")" && \
  cd "$(dirname "$path")" && \
  echo "$(pwd)/$(basename "$path")")
if [[ "$abs_clone_path" != "$MANIFEST_FLEET_ROOT"* ]]; then
    echo "Invalid path (outside fleet root)"
```

If `$path` is `../../../tmp/evil`, `mkdir -p` runs *before* validation rejects
it — so a malicious or malformed config leaves stray directories outside the
fleet root.

**Fix shipped:** New `_fleet_validate_clone_path` helper does a pure string
check (rejects empty paths, absolute paths, and any `..` segment) with no
filesystem writes. `_fleet_sync_service` calls it before any `mkdir -p`.

### [x] H2. Sequential clone is a verbatim copy of `_fleet_sync_service`

[modules/fleet/manifest-fleet.sh:1050-1074](../modules/fleet/manifest-fleet.sh#L1050-L1074) duplicates the clone branch from
[modules/fleet/manifest-fleet.sh:971-1003](../modules/fleet/manifest-fleet.sh#L971-L1003). Same for the pull branch. If somebody fixes
H1 in one branch and forgets the other, the bug persists. (Same drift risk as
the `tag_target` test-mirror issue.)

**Fix shipped:** `_fleet_sync_sequential` now calls `_fleet_sync_service` per
service, writing into a `mktemp -d` result dir. Tally extracted into a shared
`_fleet_sync_print_summary` helper that both sequential and parallel call.
Duplicated body deleted.

### [x] H3. Submodules try to clone instead of `submodule update --init`

[modules/fleet/manifest-fleet.sh:971-1003](../modules/fleet/manifest-fleet.sh#L971-L1003): when `is_submodule=true` and the path
doesn't exist, the function still falls into the `git clone --branch` branch.
Submodules should be hydrated from the parent's `.gitmodules`, not cloned
standalone. The resulting clone is not a submodule of anything; the parent's
index still lacks the gitlink.

**Fix shipped:** `_fleet_sync_service` checks `is_submodule` before falling
into the clone branch. On a missing submodule path it errors out with a
message pointing the user at `git submodule update --init` from the parent.

---

## Medium severity

### [x] M1. `git clone … 2>&1 | tail -1` swallows error context

[modules/fleet/manifest-fleet.sh:995](../modules/fleet/manifest-fleet.sh#L995), [:1068](../modules/fleet/manifest-fleet.sh#L1068). With `pipefail` set
globally the exit-status check is correct, but the user only ever sees the
last line of git's output, which for clone is usually a generic "fatal:"
without the helpful context lines. And readers reasonably wonder whether
pipefail is on.

**Fix shipped:** Clone output captured into `$clone_out` (no pipe). On
failure the last 3 lines are joined and printed prefixed with the service
name, so the real reason ("Remote branch X not found", "Permission denied",
etc.) is visible.

### [x] M2. `--branch` makes clone brittle when default branch differs

[modules/fleet/manifest-fleet.sh:995](../modules/fleet/manifest-fleet.sh#L995). Config defaults `branch` to `main`. If the
remote's default is `master` (or anything else) the entire clone fails with no
fallback. Surfaces as "fatal: Remote branch main not found" — confusing when
the repo is healthy.

**Fix shipped:** Clone without `--branch`, then post-clone `git -C "$path"
checkout "$branch"` only if the resulting HEAD differs from the configured
branch. Checkout failure is a soft warning ("Cloned, but couldn't checkout
'X' (default: Y)") rather than a hard error.

### [x] M3. `_fleet_init_directory` swallows `git init` errors

[modules/fleet/manifest-fleet.sh:567-573](../modules/fleet/manifest-fleet.sh#L567-L573):

```bash
git init "$dir_path" >/dev/null 2>&1
if [[ $? -eq 0 ]]; then ...
```

Both stderr and the exit-status idiom are wrong. On failure the user sees only
"git init failed: PATH" with no reason.

**Fix shipped:** Replaced with `if git init "$dir_path" >/dev/null; then …`
so stderr is preserved. Same change applied to `manifest_init_repo` in
`modules/core/manifest-init.sh` for consistency.

### [x] M4. `manifest_prep_repo` doesn't validate the URL it just took

[modules/core/manifest-prep.sh:84-91](../modules/core/manifest-prep.sh#L84-L91). Whatever the user types becomes `origin`.
A typo or non-existent GitHub repo only surfaces on the first push from
`manifest ship`, which is too late.

**Fix shipped:** After `git remote add origin`, the function probes the URL
via `git ls-remote --exit-code`. On failure it warns (non-fatal — offline
workflows still succeed) and prints the exact `git remote remove` command.
On success it prints `✓ Remote is reachable`.

---

## Low severity

### [x] L1. `manifest prep repo --dry-run` doesn't cover fleet dry-run

[modules/core/manifest-prep.sh](../modules/core/manifest-prep.sh) describes the pull plan, but `manifest prep
fleet` has no `--dry-run` at all — `_fleet_sync` doesn't accept the flag.
Asymmetric with `init`, which dry-runs cleanly.

**Fix shipped:** `manifest_prep_fleet` accepts `--dry-run` and forwards it
to `_fleet_sync`. New `_fleet_sync_dry_run` mirrors the live decision tree
(submodule guard, URL presence, path validation, clone-only/pull-only) and
prints a per-service plan plus a `Plan: N clone, N pull, N skip, N fail`
summary. No filesystem or network side-effects.

### [x] L2. No `gh repo create` — remote must pre-exist

Was: `manifest prep repo` adds a remote URL but never creates the GitHub repo
behind it; first `manifest ship` push fails if the URL is for a repo that
doesn't exist yet.

**Fix shipped:** Three opt-in entry points sharing one helper trio in
`modules/core/manifest-shared-functions.sh`:

- `manifest init repo --create-repo-{private,public}`
- `manifest prep repo --create-repo-{private,public}`
- `manifest init fleet --create-repo-{private,public}` (Phase-2 only;
  applied to every scaffolded directory in the same loop that runs `git init`)

The flags are mutually exclusive (`_manifest_parse_create_repo_flag` enforces).
Neither flag pushes — the user controls publishing via `manifest ship`. All
flags require `gh` installed and authenticated; `_manifest_require_gh` checks
both and prints actionable install/auth hints on failure. If `origin` already
exists, the helper warns and skips creation rather than mutating the remote.

For fleet, `_manifest_require_gh` is memoized via `_MANIFEST_GH_VALIDATED_AT`
so a 50-repo fleet pays the `gh auth status` cost once. TTL defaults to 300s
(override via `MANIFEST_GH_VALIDATION_TTL`) — bounds staleness if `gh` is
uninstalled or auth changes mid-session. `_fleet_init_directory` returns 2
(distinct from 1 = init failed) when `gh repo create` fails so the caller
can tally `GitHub: K ready, P failed` separately.

`manifest prep repo --create-repo-*` short-circuits the URL prompt entirely
when no remotes are configured. Dry-run for both repo commands prints the
planned `gh repo create <name> (<visibility>)` line without invoking `gh`.
Phase-1 `init fleet --create-repo-*` prints a notice that the flag will
apply on Phase-2 re-run (since Phase 1 is read-only directory scanning).

`tests/create_repo.bats` covers mutual exclusion across all three commands,
dry-run plumbing, the "origin already exists" branch (both dry-run preview
and the live guard at `_manifest_gh_repo_create`), help-text exposure,
fleet wiring (`_fleet_init_directory` invokes/skips the helper correctly,
returns 2 on gh failure, returns 3 on missing path), the end-to-end
visibility-forwarding flow from `manifest_init_fleet` through to
`_fleet_init_directory`, the Phase-1 notice, the user-facing fix-it block
for missing paths, and the TTL memoization (cache hit, cache expiry).

### [x] L3. Parallel clone races on shared parent dirs

[modules/fleet/manifest-fleet.sh:1118-1122](../modules/fleet/manifest-fleet.sh#L1118-L1122). Two services that share
`dirname "$path"` both call `mkdir -p` concurrently. `mkdir -p` is generally
safe under concurrent calls on the same path, but the side-effect-during-
validation pattern (H1) made the race observable.

**Fix shipped:** Dissolved by H1 — validation is now pure, and `mkdir -p`
runs only after validation passes. Concurrent `mkdir -p` on the same parent
remains harmless under POSIX semantics.

---

## Out of scope (noted, not tracked)

- `manifest init repo` dry-run wording differs from the live run ("would
  create: .git/" vs "Created: .git/"). Cosmetic.
- `manifest_prep_repo` only handles a remote literally named `origin`; if the
  user already has a differently-named remote, the "no remotes configured"
  branch never fires anyway. Working as intended.

---

## Cohesion follow-ups (post-ship, 2026-04-28)

A self-audit after v44.12.0 surfaced two design smells worth fixing now and
five test gaps. All shipped on top of the L2 work.

### Flag-style symmetry

External entry points (`init repo`, `prep repo`, `init fleet`) accept
`--create-repo-private` / `--create-repo-public`. The internal `_fleet_init`
previously accepted a single `--create-repo VISIBILITY` form, with
`manifest_init_fleet` transforming the external form on the way in. Removed
the asymmetry: `_fleet_init` now accepts the same two flags directly and
uses the shared `_manifest_parse_create_repo_flag` helper. One flag style
across the codebase, no transformation seam.

### Skip-reporting overhaul (`_fleet_init_directory` exit codes)

The previous scheme conflated "path missing" (TSV typo) with "git init
failed" (real failure) under exit code 1, and the caller tallied both as
"Skipped" — wrong user signal for a TSV typo. New scheme:

| Code | Meaning | Caller behaviour |
| --- | --- | --- |
| 0 | init ok | `((init_count++))` |
| 1 | git init failed | `init_failed_paths+=("$path")` |
| 2 | init ok, gh repo create failed | `gh_failed_paths+=("$path")` |
| 3 | path missing on disk | `missing_paths+=("$path")` |

Caller now accumulates per-row paths into arrays and prints a fix-it block
naming the offending paths plus a one-line "how to fix" per category:

```text
Initialized: 2   Missing: 1   Failed: 0
GitHub (private): 2 ready, 0 failed

Issues to resolve:

  Missing paths (TSV references directories that don't exist):
    - ./services/fronend
    Fix: edit manifest.fleet.tsv to correct these paths or remove their
         rows, then re-run: manifest init fleet --force
```

### Test additions

Five new tests in `tests/create_repo.bats`:

- Phase 1 notice assertion (`manifest_init_fleet --create-repo-private`
  with no TSV emits "applies in Phase 2").
- End-to-end forwarding (visibility flows from CLI parse → `fleet_args`
  rewrite → `_fleet_init` re-parse → per-row loop → `_fleet_init_directory`).
- `_fleet_init_directory` returns 3 for missing path.
- End-to-end summary names missing paths and prints the "edit
  manifest.fleet.tsv" fix-it hint.
- `_manifest_gh_repo_create` real-path "origin already exists" guard
  (gh-stub sentinel proves no `gh` invocation occurs).

Also: `tests/create_repo.bats` `teardown()` now unsets
`_MANIFEST_GH_VALIDATED_AT` and `MANIFEST_GH_VALIDATION_TTL` so memoization
state never leaks between tests.

### Considered and rejected

- **Hard-error in Phase 1 when `--create-repo-*` is set.** The soft notice
  is the right design for a two-phase command — it forward-points the
  intent rather than forcing the user to type the flag twice with a "you
  can't do that yet" wall between Phase 1 and Phase 2.
- **Refactoring `_pr_require_gh` to use `_manifest_require_gh`.** PR is an
  isolated subsystem; the duplication is acceptable.

---

## Verification

- `bash -n` passes on all modified files.
- `bats tests/*.bats` — 150/150 passing. Original 129 still green; the L2
  ship + cohesion follow-ups total 21 tests in `tests/create_repo.bats`
  covering all three entry points, the live `_manifest_gh_repo_create`
  guard, end-to-end fleet forwarding, the missing-path fix-it block, and
  TTL memoization (cache hit, cache expiry).
- Still uncovered by tests: live `gh repo create` invocation (network +
  auth-dependent) and submodule-guard refusal. These would need a `gh`
  stub harness; deferred unless they regress.
