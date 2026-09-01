#!/usr/bin/env bats
# bats file_tags=smoke

# A `case` that branches on the OS must read the name the OS module assigns —
# and that name must not be one people mistype by instinct.
#
# The incident, live from before v51 until 2026-08-31: the module assigned
# `MANIFEST_CLI_OS_OS`, while two `case` statements in
# `manifest-shared-functions.sh` branched on `MANIFEST_CLI_OS` — one suffix
# short — a name assigned nowhere in the product. Both therefore took their
# `:-Unknown` default on every platform and matched no arm.
#
# **The variable has since been renamed to `MANIFEST_CLI_OS_NAME`, and that is
# the actual fix.** Making the consumers spell `MANIFEST_CLI_OS_OS` correctly
# treats the symptom: a stuttering name invites exactly the typo that caused
# this, because `MANIFEST_CLI_OS` is what a reasonable person writes when the
# real name looks like a mistake. `_NAME` also pairs with the `_FAMILY` and
# `_VERSION` siblings, so the module's triple now reads as one scheme instead of
# one oddity and two normal names. **Both bad spellings are banned below** — the
# bare name because it was the bug, and the doubled name because reintroducing
# it would recreate the conditions for it.
#
# Three properties made the original survive for months, and each is a reason
# this guard reads the way it does:
#
#   1. **The `:-Unknown` default turned a broken read into a supported case.**
#      With no default, `set -u` would have aborted. With one, the mismatch is
#      indistinguishable from an unrecognized platform.
#   2. **Nothing failed.** `check_network_connectivity` fell through to a
#      fallback that works, and `get_latest_version` computed a `timeout_cmd`
#      it never read. Silent degradation, no error, correct-looking output.
#   3. **The register's own entry got it wrong.** TRACKER §65 was filed in
#      answer to "what happened to our OS detection?" and concluded the whole
#      module was unreachable — including that `detect_os` had "zero callers",
#      when it is auto-called at the foot of its own file. The claim was
#      established by reading rather than by running: `manifest config time`
#      prints `OS: macOS` and always did. So the one true finding of three sat
#      inside an item whose headline was false, and anyone who checked the
#      headline would have discarded it.
#
# The guard is deliberately narrow: it pins the names that broke, rather than
# attempting the general "every variable a case branches on is assigned
# somewhere" census. That census is worth having (TRACKER §67) but a wide sweep
# written now would need an exclusion list for every legitimately-external
# variable, and an exclusion list is where this kind of check goes to die.

load 'helpers/setup'

# Files that legitimately reference the bare name: none. The producer uses
# `MANIFEST_CLI_OS_NAME`; there is no supported `MANIFEST_CLI_OS` variable.
shipped_shell_files() {
    find "$TEST_REPO_ROOT/modules" "$TEST_REPO_ROOT/scripts" \
         -name '*.sh' -type f 2>/dev/null | sort
}

@test "control: the file sweep finds the shipped shell modules" {
    # Without this, a broken find empties every check below and the file goes
    # green while guarding nothing.
    local files
    files="$(shipped_shell_files)"
    [ -n "$files" ]
    [ "$(printf '%s\n' "$files" | grep -c .)" -ge 20 ]
    grep -qF 'manifest-shared-functions.sh' <<<"$files"
    grep -qF 'manifest-os.sh' <<<"$files"
}

# A READ (`$MANIFEST_CLI_OS`, `${MANIFEST_CLI_OS:-...}`) or a WRITE
# (`MANIFEST_CLI_OS=`) of the bare name. `[^_A-Z]` after the name excludes the
# legitimate longer names (MANIFEST_CLI_OS_NAME, _FAMILY, _VERSION, _BASH_MAJOR).
#
# Matching the expansion/assignment rather than the bare token is not cosmetic:
# the first version of this pattern matched any mention and immediately flagged
# the two code comments that document the historical bug — a guard tripping over
# its own explanation, which is at least the sixth instance of that shape in this
# suite. Prose naming the defect must stay legal; only code that reads or writes
# the name is the defect.
#
# Two spellings are banned, for different reasons. `MANIFEST_CLI_OS` (bare) is
# the name that was actually read and never assigned. `MANIFEST_CLI_OS_OS` is
# the name that was assigned, and is banned because it is the reason the first
# one got written — a doubled suffix reads as a typo, so consumers "corrected"
# it. Renaming to `MANIFEST_CLI_OS_NAME` is what makes the bug hard to repeat;
# this test is what makes it stay renamed.
BARE_OS_NAME_RE='(\$\{?MANIFEST_CLI_OS[^_A-Z]|^[[:space:]]*MANIFEST_CLI_OS=)'
STUTTER_OS_NAME_RE='MANIFEST_CLI_OS_OS'

@test "os vars: nothing reads or writes the bare MANIFEST_CLI_OS name" {
    local hits="" f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if grep -nE "$BARE_OS_NAME_RE" "$f" >/dev/null 2>&1; then
            hits+="  ${f#$TEST_REPO_ROOT/}"$'\n'
            hits+="$(grep -nE "$BARE_OS_NAME_RE" "$f" | sed 's/^/      /')"$'\n'
        fi
    done <<<"$(shipped_shell_files)"

    if [ -n "$hits" ]; then
        printf 'the bare name MANIFEST_CLI_OS is assigned nowhere; these use it:\n%s' \
            "$hits" >&2
        return 1
    fi
}

@test "os vars: the stuttering MANIFEST_CLI_OS_OS name does not come back" {
    # Banned outright, mentions included — unlike the bare name, which has to
    # stay quotable in comments that explain the bug. Nothing needs to say
    # `MANIFEST_CLI_OS_OS` in shipped shell any more, and a mention is how a
    # rename quietly half-reverts.
    local hits="" f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if grep -nF "$STUTTER_OS_NAME_RE" "$f" >/dev/null 2>&1; then
            hits+="  ${f#$TEST_REPO_ROOT/}"$'\n'
            hits+="$(grep -nF "$STUTTER_OS_NAME_RE" "$f" | sed 's/^/      /')"$'\n'
        fi
    done <<<"$(shipped_shell_files)"

    if [ -n "$hits" ]; then
        printf 'MANIFEST_CLI_OS_OS was renamed to MANIFEST_CLI_OS_NAME; these still use it:\n%s' \
            "$hits" >&2
        return 1
    fi
}

@test "positive control: the stutter detector fires on a planted name" {
    local fixture="$BATS_TEST_TMPDIR/stutter.sh"
    printf '%s\n' 'MANIFEST_CLI_OS_OS="macOS"' > "$fixture"
    run grep -cF "$STUTTER_OS_NAME_RE" "$fixture"
    [ "$status" -eq 0 ]
    [ "$output" = "1" ]

    # ...and spares the name that replaced it, which shares its prefix.
    local ok="$BATS_TEST_TMPDIR/ok.sh"
    printf '%s\n' 'MANIFEST_CLI_OS_NAME="macOS"' > "$ok"
    run grep -cF "$STUTTER_OS_NAME_RE" "$ok"
    [ "$status" -ne 0 ]
}

@test "os vars: the name consumers DO read is the name the module assigns" {
    # The other direction. Asserting only "nobody reads the bare name" would
    # also pass if the OS case statements had been deleted outright, so this
    # pins that the branch still exists and now reads the assigned name.
    grep -qE 'case "\$\{MANIFEST_CLI_OS_NAME:-Unknown\}"' \
        "$TEST_REPO_ROOT/modules/core/manifest-shared-functions.sh"

    # ...and that the module really does assign it.
    grep -qE '^[[:space:]]*MANIFEST_CLI_OS_NAME="macOS"' \
        "$TEST_REPO_ROOT/modules/system/manifest-os.sh"
}

@test "os vars: the OS name is actually populated at runtime, not just assigned" {
    # §65's false claim was that none of this runs. It runs: detect_os is called
    # at the foot of manifest-os.sh on load. This is the executable form of that
    # correction — the check the item needed and did not make.
    run bash -c "source '$TEST_REPO_ROOT/modules/system/manifest-os.sh' >/dev/null 2>&1; \
                 printf '%s' \"\$MANIFEST_CLI_OS_NAME\""
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    # Any of the five known arms is fine; empty or "Unknown" is not, on a host
    # the suite can run on at all.
    [[ "$output" == "macOS" || "$output" == "Linux" \
       || "$output" == "FreeBSD" || "$output" == "OpenBSD" || "$output" == "NetBSD" ]]
}

@test "positive control: the bare-name detector fires on a planted read" {
    # Proves the sweep above can go red, using the exact historical defect. Uses
    # the same regex variable as the sweep, so the two cannot drift apart — an
    # earlier version hardcoded the pattern here and would have kept passing
    # after the sweep's pattern changed.
    local fixture="$BATS_TEST_TMPDIR/planted.sh"
    {
        printf '%s\n' 'case "${MANIFEST_CLI_OS:-Unknown}" in'
        printf '%s\n' 'MANIFEST_CLI_OS="macOS"'
    } > "$fixture"
    run grep -cE "$BARE_OS_NAME_RE" "$fixture"
    [ "$status" -eq 0 ]
    [ "$output" = "2" ]
}

@test "positive control: the detector spares the legitimate longer names" {
    # The narrow half: banning the prefix outright would flag every correct use.
    local fixture="$BATS_TEST_TMPDIR/legit.sh"
    {
        printf '%s\n' 'MANIFEST_CLI_OS_NAME="macOS"'
        printf '%s\n' 'echo "$MANIFEST_CLI_OS_FAMILY $MANIFEST_CLI_OS_VERSION"'
        printf '%s\n' 'x="$MANIFEST_CLI_OS_BASH_MAJOR"'
    } > "$fixture"
    run grep -cE "$BARE_OS_NAME_RE" "$fixture"
    [ "$status" -ne 0 ]
}

@test "positive control: prose naming the defect is NOT flagged" {
    # The other narrow half, and the reason the pattern matches expansions
    # rather than mentions: the fix commit's own comments name the bare variable
    # while explaining it, and must remain legal.
    local fixture="$BATS_TEST_TMPDIR/prose.sh"
    printf '%s\n' '# This branched on `MANIFEST_CLI_OS` (no _OS suffix) until 2026-08-31.' > "$fixture"
    run grep -cE "$BARE_OS_NAME_RE" "$fixture"
    [ "$status" -ne 0 ]
}
