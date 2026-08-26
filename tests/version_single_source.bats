#!/usr/bin/env bats
# bats file_tags=smoke
#
# Tagged smoke because this is a WHOLE-TREE invariant, not a test of one module.
# `--changed` selects by path via coverage-map.tsv and always unions the smoke
# tier; a per-path map cannot express "this test is about every file", so without
# the tag no code change ever selects it. That gap is what let §56 and §57 sit
# red — the guard was correct and simply never ran (TRACKER §48).
#
# VERSION is the single definition site of this repo's version. Every other
# tracked file that used to restate it drifted: formula/manifest.rb sat six
# majors behind for months, and README.md/docs/INDEX.md only stayed current
# because a canonical-repo-only rewriter patched them on every ship — a second
# derivation of the same fact, positional and self-warning, now deleted.
#
# The rule this pins is deliberately not "no version-shaped literal anywhere":
# historical statements ("reviewed against 59.2.1", "INERT as of 59.3.0") are
# correct BECAUSE they are stale, and test fixtures use fake versions on
# purpose. Instead it compares against the CURRENT contents of VERSION, so
# nothing needs annotating and nothing needs maintaining — a file only fails
# when it claims to be the version we are on right now.
#
# Exempt files are exactly those whose JOB is to record which release something
# happened in. That is a criterion, not an allowlist to grow by habit: if a new
# file needs exempting, the question to answer first is why it restates the
# current version at all.

load 'helpers/setup'

# Files permitted to contain the current version literal.
#   VERSION       — the definition site itself.
#   CHANGELOG.md  — release history; its newest entry states the current version
#                   permanently, which is a record rather than a restatement.
#   docs/TRACKER.md — the open-work register, which cites the release an item
#                   shipped in ("shipped in v59.4.2").
#   docs/zArchive/ — archived point-in-time documents.
#   .claude/agents/ — authoring instructions that cite the specific past release
#                   a measurement was taken on, alongside its commit sha. Same
#                   category as TRACKER.md, and the discriminator is testable: a
#                   RECORD names a past release and stays correct across the next
#                   bump, while a RESTATEMENT claims the current version and
#                   silently goes stale. Exempted per-directory on purpose — a
#                   sibling under .claude/ gets this judgement made again rather
#                   than inheriting a blanket pass (TRACKER §56).
#
# Deliberately no version literal appears anywhere in this file. Writing one into
# a comment here makes THIS file an offender and fails the scan below — which is
# how the first cut of the §56 exemption broke, in the file whose whole job is
# forbidding that.
#
# One pathspec, used by the scan and by its own negative control. Two copies
# would let the control exercise a different exclusion set than the thing it
# controls, which is what made test 3 unpassable (§6's duplicated derivation).
version_scan_pathspec() {
    printf '%s\n' ':!VERSION' ':!CHANGELOG.md' ':!docs/TRACKER.md' \
        ':!docs/zArchive' ':!.claude/agents'
}

version_scan() {
    local -a _spec=()
    while IFS= read -r _p; do _spec+=("$_p"); done < <(version_scan_pathspec)
    git -C "$TEST_REPO_ROOT" grep -F -l -- "$1" -- "${_spec[@]}" || true
}

@test "version: no tracked file outside the release record restates the current version" {
    local current
    current="$(cat "$TEST_REPO_ROOT/VERSION")"
    [ -n "$current" ]

    local offenders
    offenders="$(version_scan "$current")"

    if [ -n "$offenders" ]; then
        printf 'files restating the current version (%s):\n%s\n' "$current" "$offenders" >&2
    fi
    [ -z "$offenders" ]
}

# ---------------------------------------------------------------------------
# Controls in both directions. Without the first, a broken pathspec or a `git
# grep` that silently matches nothing makes the test above pass vacuously —
# which is the exact failure this repo keeps finding (a `git grep -E '\b…'`
# pattern that matches nothing reads identically to "no offenders").
# ---------------------------------------------------------------------------

@test "positive control: the scan DOES find the current version where it belongs" {
    local current
    current="$(cat "$TEST_REPO_ROOT/VERSION")"

    # Same mechanism, without the CHANGELOG exclusion: it must find it there.
    run git -C "$TEST_REPO_ROOT" grep -F -l -- "$current" -- CHANGELOG.md
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "negative control: the scan does NOT match a version that is not in the tree" {
    # A fabricated version proves the scan discriminates rather than matching
    # every file it is pointed at.
    #
    # Assembled from two halves so the full literal never appears in this file.
    # Naming it inline made this control UNPASSABLE: the scan searches all
    # tracked files, found the sentinel in the very test asserting its absence,
    # and failed forever — the mirror of a control that cannot fail
    # (TRACKER §57). Keep the halves split; do not "tidy" them back together.
    local absent="0.0.0-not-a"
    absent="${absent}-real-version"

    # Same pathspec as the real scan, so this controls the mechanism actually
    # used rather than a bare tree-wide grep. Without the exclusions this fails
    # on docs/TRACKER.md, which discusses the sentinel by name — a file the scan
    # itself exempts by design.
    local -a spec=()
    while IFS= read -r p; do spec+=("$p"); done < <(version_scan_pathspec)

    run git -C "$TEST_REPO_ROOT" grep -F -l -- "$absent" -- "${spec[@]}"
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "version: the formula template carries a sentinel, never a real release" {
    local current
    current="$(cat "$TEST_REPO_ROOT/VERSION")"

    # The tracked formula is a template; the only concrete formula is the copy
    # rendered into the tap at publish time. A real-looking pin here reads as
    # authoritative and cannot be kept current — it drifted six majors before.
    grep -Fq 'refs/tags/v0.0.0.tar.gz' "$TEST_REPO_ROOT/formula/manifest.rb"
    grep -Fq 'sha256 "0000000000000000000000000000000000000000000000000000000000000000"' \
        "$TEST_REPO_ROOT/formula/manifest.rb"
    refute grep -Fq "$current" "$TEST_REPO_ROOT/formula/manifest.rb"
}
