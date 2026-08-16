#!/usr/bin/env bats

# One implementation of "what is the next version", and proof that it is one.
#
# There used to be three, and they agreed only while every version had exactly
# three segments — which is every repo, right up until someone runs
# `ship repo revision` once. From 20.1.0.3 a `patch` produced:
#
#   20.1.0.4   manifest_test_dry_run()  (the interactive "recommended" preview)
#   20.1.1.3   get_next_version()       (the ship plan)
#   20.1.1     bump_version()           (what VERSION actually received)
#
# One command, three answers, and the two the user is shown are the two that
# are wrong. Consent was being collected against a version that would never
# exist.
#
# The knock-on: manifest_ship_repo_pretag_state() decides "is this an
# interrupted ship I should resume?" by asking get_next_version what the
# working VERSION *should* be. With the writer and the predictor disagreeing,
# a 4-segment repo could never match, so an interrupted ship was reclassified
# as a fresh one and bumped a second time — 20.1.0.3 -> 20.1.1 -> 20.1.2,
# silently skipping a version.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
    load_modules "git/manifest-git.sh" "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Runs the real writer against a throwaway repo and echoes the resulting VERSION.
_writer() {
    local from="$1" type="$2" w="$SCRATCH/w"
    rm -rf "$w"; mkdir -p "$w"
    printf '%s\n' "$from" > "$w/VERSION"
    ( MANIFEST_CLI_PROJECT_ROOT="$w" bump_version "$type" >/dev/null 2>&1 )
    cat "$w/VERSION" 2>/dev/null
}

# Runs the predictor the previews use.
_preview() {
    local from="$1" type="$2" p="$SCRATCH/p"
    rm -rf "$p"; mkdir -p "$p"
    printf '%s\n' "$from" > "$p/VERSION"
    ( cd "$p" && get_next_version "$type" 2>/dev/null )
}

# --- the invariant -----------------------------------------------------------

@test "version: the preview and the writer agree for every type and shape" {
    local from type p a
    for from in 1 1.2 1.0.0 20.1.0 0.0.0 20.1.0.3 0.0.0.9 1.2.3.4 \
                1.2.3.4.5 1.2.3.4.5.6 10.20.30.40.50.60.70; do
        for type in patch minor major revision; do
            p="$(_preview "$from" "$type")"
            a="$(_writer  "$from" "$type")"
            [ -n "$a" ]
            if [ "$p" != "$a" ]; then
                echo "DIVERGED from=$from type=$type preview=$p written=$a"
                return 1
            fi
        done
    done
}

# --- the words are aliases, not the set of levels ----------------------------

@test "version: a name and its segment number are interchangeable" {
    # major/minor/patch/revision are conventional NAMES for positions 1-4.
    # Nothing may depend on the word itself.
    [ "$(manifest_version_next 9.9.9.9 major)"    = "$(manifest_version_next 9.9.9.9 1)" ]
    [ "$(manifest_version_next 9.9.9.9 minor)"    = "$(manifest_version_next 9.9.9.9 2)" ]
    [ "$(manifest_version_next 9.9.9.9 patch)"    = "$(manifest_version_next 9.9.9.9 3)" ]
    [ "$(manifest_version_next 9.9.9.9 revision)" = "$(manifest_version_next 9.9.9.9 4)" ]
}

@test "version: any segment is addressable by number, with no upper bound" {
    # Enumerating four words capped the CLI at four segments, leaving the 5th
    # and beyond unreachable by every increment type that existed.
    [ "$(manifest_version_next 1.2.3.4.5.6.7 5)"  = "1.2.3.4.6" ]
    [ "$(manifest_version_next 1.2.3.4.5.6.7 6)"  = "1.2.3.4.5.7" ]
    [ "$(manifest_version_next 1.2.3.4.5.6.7 7)"  = "1.2.3.4.5.6.8" ]
    [ "$(manifest_version_next 1.2.3.4.5.6.7 12)" = "1.2.3.4.5.6.7.0.0.0.0.1" ]
    # A short version is padded up to the addressed segment.
    [ "$(manifest_version_next 1.2.3 6)" = "1.2.3.0.0.1" ]
}

# --- segment names are configurable, standard four included --------------------

@test "version: version.components renames the standard segments" {
    # A project versioning as generation.major.minor.patch: `major` must then
    # address segment 2, not segment 1.
    MANIFEST_CLI_VERSION_COMPONENTS="generation,major,minor,patch"
    [ "$(manifest_version_level generation)" = "1" ]
    [ "$(manifest_version_level major)"      = "2" ]
    [ "$(manifest_version_level minor)"      = "3" ]
    [ "$(manifest_version_level patch)"      = "4" ]
    [ "$(manifest_version_next 3.20.1.0 major)"      = "3.21.0" ]
    [ "$(manifest_version_next 3.20.1.0 generation)" = "4.0.0" ]
    # A name that is no longer configured stops being a level.
    refute manifest_version_level revision
}

@test "version: version.components can name positions beyond the standard four" {
    MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch,revision,build,hotfix"
    [ "$(manifest_version_level build)"  = "5" ]
    [ "$(manifest_version_level hotfix)" = "6" ]
    [ "$(manifest_version_next 1.2.3 hotfix)" = "1.2.3.0.0.1" ]
}

@test "version: unset or empty version.components yields the standard four" {
    local expected="major
minor
patch
revision"
    unset MANIFEST_CLI_VERSION_COMPONENTS
    [ "$(manifest_version_components)" = "$expected" ]
    MANIFEST_CLI_VERSION_COMPONENTS=""
    [ "$(manifest_version_components)" = "$expected" ]
}

@test "version: an unusable version.components refuses instead of falling back" {
    # Falling back to the defaults for a project that configured something else
    # would cut the release one segment off target, silently.
    local bad
    for bad in "major,,minor" ",major" "major,minor," "major,minor,major" \
               "major,3,patch" "major,mi nor"; do
        MANIFEST_CLI_VERSION_COMPONENTS="$bad"
        refute manifest_version_components
        refute manifest_version_level major
    done
}

@test "version: a positional name list never silently shifts a name's segment" {
    # The specific hazard: dropping an empty element moves every later name one
    # segment left. minor must be 2 here and unresolvable in the malformed list.
    MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
    [ "$(manifest_version_level minor)" = "2" ]
    MANIFEST_CLI_VERSION_COMPONENTS="major,,minor"
    refute manifest_version_level minor
}

@test "version: numbers address unnamed segments regardless of naming config" {
    MANIFEST_CLI_VERSION_COMPONENTS="major,minor,patch"
    # 4 and 9 have no name at all here; positional addressing must still work.
    [ "$(manifest_version_level 4)" = "4" ]
    [ "$(manifest_version_next 1.2.3 4)" = "1.2.3.1" ]
    [ "$(manifest_version_next 1.2.3 9)" = "1.2.3.0.0.0.0.0.1" ]
}

@test "version: level resolution rejects non-levels" {
    local bad
    for bad in 0 -1 foo "" 1.5 " " patchy; do
        refute manifest_version_level "$bad"
    done
}

@test "version: the increment validator and the arithmetic cannot disagree" {
    local level
    # Anything the arithmetic can address, the CLI must accept...
    for level in major minor patch revision 1 4 5 99; do
        run validate_increment_type "$level"
        [ "$status" -eq 0 ]
        run manifest_version_level "$level"
        [ "$status" -eq 0 ]
    done
    # ...and anything it rejects, the CLI must reject.
    for level in foo 0 -1 ""; do
        refute validate_increment_type "$level"
        refute manifest_version_level "$level"
    done
}

@test "version: no module re-enumerates the four words as the definition of a level" {
    # The alias table in manifest-shared-functions.sh is the only place the
    # words appear as data. A case pattern that decides validity or assigns an
    # increment type is a second, cappable authority.
    run grep -rnE '(patch\|minor\|major\|revision|major\|minor\|patch\|revision)\)[[:space:]]*(return 0|increment_type=)' \
        "$TEST_REPO_ROOT/modules" --include='*.sh'
    [ "$status" -ne 0 ]
}

# --- arbitrary arity ---------------------------------------------------------

@test "version: bump levels are positional and work at any segment count" {
    # Nothing counts to three or four. major=1, minor=2, patch=3, revision=4,
    # whatever the version's length.
    [ "$(_writer 1.2.3.4.5     major)"    = "2.0.0" ]
    [ "$(_writer 1.2.3.4.5     minor)"    = "1.3.0" ]
    [ "$(_writer 1.2.3.4.5     patch)"    = "1.2.4" ]
    [ "$(_writer 1.2.3.4.5     revision)" = "1.2.3.5" ]
    [ "$(_writer 1.2.3.4.5.6.7 patch)"    = "1.2.4" ]
    [ "$(_writer 1.2.3.4.5.6.7 revision)" = "1.2.3.5" ]

    # Short versions are padded to the floor rather than rejected.
    [ "$(_writer 1   patch)"    = "1.0.1" ]
    [ "$(_writer 1   revision)" = "1.0.0.1" ]
    [ "$(_writer 1.2 minor)"    = "1.3.0" ]
}

@test "version: a long version never bumps DOWNWARD" {
    # The tail-lumping read made revision on 1.2.3.4.5 emit 1.2.3 — lower than
    # the version it started from, with no error. Assert ordering directly.
    local from="1.2.3.4.5" type out
    for type in patch minor major revision; do
        out="$(_writer "$from" "$type")"
        [ -n "$out" ]
        # Sort numerically by segment; the bumped version must not sort first.
        [ "$(printf '%s\n%s\n' "$from" "$out" | sort -t. -k1,1n -k2,2n -k3,3n -k4,4n | tail -1)" = "$out" ]
    done
}

# --- malformed input is a stop condition, not a coercion ---------------------

@test "version: a non-numeric version refuses and leaves VERSION untouched" {
    local bad w
    for bad in "1.2.3-rc1" "v1.2.3" "1..3" "abc" "1.2.beta"; do
        w="$SCRATCH/bad"
        rm -rf "$w"; mkdir -p "$w"
        printf '%s\n' "$bad" > "$w/VERSION"

        run env -u MANIFEST_CLI_VERSION_SEPARATOR bash -c \
            "MANIFEST_CLI_PROJECT_ROOT='$w' source '$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh' >/dev/null 2>&1;
             source '$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh';
             source '$TEST_REPO_ROOT/modules/git/manifest-git.sh';
             bump_version patch"
        [ "$status" -ne 0 ]
        # Bash reads "3-rc1" as "3 - rc1" with rc1 unset, so this used to bump
        # 1.2.3-rc1 to 1.2.4 as though the suffix were not there.
        [ "$(cat "$w/VERSION")" = "$bad" ]
    done
}

# --- what the fourth segment means -------------------------------------------

@test "version: the revision segment is subordinate — patch/minor/major drop it" {
    # 20.1.0.3 is "third revision of 20.1.0". 20.1.1 has had no revisions,
    # so carrying .3 onto it would name a release that never happened.
    [ "$(_writer 20.1.0.3 patch)" = "20.1.1" ]
    [ "$(_writer 20.1.0.3 minor)" = "20.2.0" ]
    [ "$(_writer 20.1.0.3 major)" = "21.0.0" ]

    # And the previews say the same thing.
    [ "$(_preview 20.1.0.3 patch)" = "20.1.1" ]
    [ "$(_preview 20.1.0.3 minor)" = "20.2.0" ]
    [ "$(_preview 20.1.0.3 major)" = "21.0.0" ]
}

@test "version: revision appends a fourth segment, then counts it" {
    [ "$(_writer 20.1.0 revision)" = "20.1.0.1" ]
    [ "$(_writer 20.1.0.3 revision)" = "20.1.0.4" ]
    [ "$(_writer 20.1.0.9 revision)" = "20.1.0.10" ]
    # Never a fifth segment.
    [ "$(_writer 20.1.0.3 revision)" != "20.1.0.3.1" ]
}

# --- there must remain exactly one implementation ----------------------------

@test "version: the writer delegates rather than carrying its own arithmetic" {
    grep -qF 'new_version="$(get_next_version "$increment_type")"' \
        "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
    # The old private copy split the version with cut -f1/-f2/-f3.
    refute grep -qE 'cut -d"\$separator" -f[0-9]' \
        "$TEST_REPO_ROOT/modules/git/manifest-git.sh"
}

@test "version: the dry-run preview delegates rather than reimplementing in awk" {
    grep -qF 'next_version="$(get_next_version "$increment_type"' \
        "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    refute grep -qE "awk -F\. .\\\$NF = \\\$NF \+ 1" \
        "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
}

@test "version: no module re-reads a version into fixed major/minor/patch names" {
    # This exact read is the tail-lumping bug: the last name absorbs everything
    # past its position, so any version longer than the name list is corrupted.
    # It was present in both the repo and the fleet paths.
    run grep -rnE 'read -r +major +minor +patch' \
        "$TEST_REPO_ROOT/modules" --include='*.sh'
    [ "$status" -ne 0 ]
}

@test "version: the fleet bump agrees with the repo writer" {
    load_modules "fleet/manifest-fleet.sh"
    local from type f a
    for from in 1.0.0 20.1.0.3 1.2.3.4.5; do
        for type in patch minor major revision; do
            f="$(_fleet_next_version semver "$from" "$type")"
            a="$(_writer "$from" "$type")"
            if [ "$f" != "$a" ]; then
                echo "FLEET DIVERGED from=$from type=$type fleet=$f repo=$a"
                return 1
            fi
        done
    done
}

@test "version: the status preview agrees with the repo writer" {
    load_modules "core/manifest-status.sh"
    local from type s a
    for from in 1.0.0 20.1.0.3 1.2.3.4.5; do
        # revision included: the private copy had no case for it and printed
        # nothing at all.
        for type in patch minor major revision; do
            s="$(_status_preview_bump "$from" "$type")"
            a="$(_writer "$from" "$type")"
            if [ "$s" != "$a" ]; then
                echo "STATUS DIVERGED from=$from type=$type status=$s repo=$a"
                return 1
            fi
        done
    done
}

@test "version: the status preview still shows '?' for an unusable version" {
    load_modules "core/manifest-status.sh"
    [ "$(_status_preview_bump "not-a-version" patch)" = "?" ]
    [ "$(_status_preview_bump "" patch)" = "?" ]
}

# --- config the writer honored and the predictor did not ---------------------

@test "version: a non-default version.separator is honored by both" {
    local p a
    p="$(MANIFEST_CLI_VERSION_SEPARATOR=- _preview 20-1-0 patch)"
    a="$(MANIFEST_CLI_VERSION_SEPARATOR=- _writer  20-1-0 patch)"
    [ "$p" = "20-1-1" ]
    [ "$a" = "20-1-1" ]
}

# --- the knock-on: interrupted-ship detection --------------------------------

@test "version: an interrupted ship from a 4-segment base resumes, not re-bumps" {
    local r="$SCRATCH/repo"
    mkdir -p "$r"
    git -C "$r" init -q .
    git -C "$r" config user.email t@example.com
    git -C "$r" config user.name  t

    printf '20.1.0.3\n' > "$r/VERSION"
    git -C "$r" add VERSION
    git -C "$r" commit -qm base

    # A ship bumped VERSION and died before committing.
    printf '%s\n' "$(_writer 20.1.0.3 patch)" > "$r/VERSION"

    MANIFEST_CLI_PROJECT_ROOT="$r"
    run manifest_ship_repo_pretag_state patch
    [ "$status" -eq 0 ]
    # Must be recognized as the interrupted bump it is. Falling through to
    # "fresh" here is what caused the second bump.
    [[ "$output" == resume-in-place\|20.1.1\|* ]]
}

@test "version: a 3-segment interrupted ship still resumes (no regression)" {
    local r="$SCRATCH/repo3"
    mkdir -p "$r"
    git -C "$r" init -q .
    git -C "$r" config user.email t@example.com
    git -C "$r" config user.name  t

    printf '20.1.0\n' > "$r/VERSION"
    git -C "$r" add VERSION
    git -C "$r" commit -qm base
    printf '20.1.1\n' > "$r/VERSION"

    MANIFEST_CLI_PROJECT_ROOT="$r"
    run manifest_ship_repo_pretag_state patch
    [ "$status" -eq 0 ]
    [[ "$output" == resume-in-place\|20.1.1\|* ]]
}
