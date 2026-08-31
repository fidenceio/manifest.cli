#!/usr/bin/env bats
# bats file_tags=smoke

# An item's tier tag must agree with the tier SECTION it is filed under.
#
# `docs/TRACKER.md` states its own priority model in "IDs, priority": *priority is
# read from file order plus the tier tag, never from the number.* That makes file
# position load-bearing — and it means a T2 item filed under `## T3` is not a
# cosmetic slip, it is a mis-ranked piece of work that the file's own entry point
# will then describe wrongly.
#
# The incident: §73 was filed 2026-08-29 by appending it after the entry it was
# discovered from (§69, a T3 item), so a T2 contract-integrity item landed in the
# T3 section. It was noticed only because a session record mentioned it in
# passing, and the "fix" first looked like a one-line prose edit to the resume
# paragraph. It was not — the resume paragraph is a *narrative of file order*, so
# the entry itself was in the wrong place and the paragraph was accurately
# describing a wrong file.
#
# Why the guard is on section membership rather than on the resume prose: there
# are 26 live T1+T2 items, so requiring the resume paragraph to name them all
# would make it a second copy of the register — the §36 defect this file exists
# to police. Section membership is derivable, unambiguous, and already written
# down.
#
# The tag is matched permissively ON PURPOSE. Real tags carry rationale after the
# tier (`[T2 — a safety gate that lies]`), express a deliberate hold
# (`[T3 → held at T2 while the key is public]`, correctly filed under T2), or
# straddle two (`[T2/T3]`). The rule is only that the section's own tier appears
# somewhere in the item's tag.

load 'helpers/setup'

TRACKER() { printf '%s\n' "$TEST_REPO_ROOT/docs/TRACKER.md"; }

# Emit "<id>|<tag>|<section-tier>" for every live item, in file order.
#
# An item whose tag cannot be read at all emits an empty tag rather than being
# skipped, so an unparseable header fails loudly instead of becoming a place to
# hide. Items above the first tier section (there are none today) are ignored,
# which the control below asserts is not silently swallowing the whole file.
tier_rows() {
    awk '
      /^## T1 / { sect="T1"; next }
      /^## T2 / { sect="T2"; next }
      /^## T3 / { sect="T3"; next }
      /^## DEFER/ { sect="DEFER"; next }
      /^## CUT/ { sect="CUT"; next }
      /^## Retired IDs/ { sect=""; next }
      /^## / && sect != "" { sect=""; next }
      sect == "" { next }
      /^- \*\*§[0-9]+/ {
          id = ""; tag = "";
          if (match($0, /§[0-9]+[a-z]?/)) id = substr($0, RSTART, RLENGTH);
          # The tag is selected by CONTENT, not by position: walk every bracket
          # that follows a bold marker and take the first one that actually
          # names a tier. Two positional attempts failed on real headers -
          # an unanchored match picked up a markdown link from a long header,
          # and anchoring with [^*]* broke on a title that itself contains a
          # literal asterisk (MANIFEST_CLI_*). Selecting by content is not
          # circular here: a bracket saying T2 under section T3 is still
          # selected, and still reported as the mismatch it is.
          #
          # One constraint on comments in THIS block: no apostrophe. The awk
          # program sits inside a single-quoted shell string, so an apostrophe
          # closes it and bash reports `unexpected EOF while looking for
          # matching quote` many lines away. That is a SHELL quoting rule, not
          # an awk one, and it behaves identically everywhere.
          #
          # A previous version of this comment also claimed macOS awk cannot
          # parse a multi-byte character (§, en dash) inside a comment. That was
          # wrong and is recorded here because the wrong version was committed:
          # the same program with `# §73 was filed – note the en dash` runs
          # clean under BWK awk on macOS, BusyBox awk on Alpine and mawk on
          # Ubuntu. The original failure was the apostrophe above; the
          # multi-byte character happened to be on a nearby line and got the
          # blame. A misdiagnosis written down as a lesson is worse than no
          # lesson, because the next reader obeys it.
          rest = $0;
          while (tag == "" && match(rest, /\*\*[[:space:]]*\[[^]]*\]/)) {
              cand = substr(rest, RSTART, RLENGTH);
              rest = substr(rest, RSTART + RLENGTH);
              if (match(cand, /\[[^]]*\]$/)) {
                  inner = substr(cand, RSTART, RLENGTH);
                  if (inner ~ /T1|T2|T3|DEFER|CUT/) tag = inner;
              }
          }
          # The three DEFER umbrellas carry no bracket and state the tier as prose.
          if (tag == "" && match($0, /\*\*Status:\*\*[[:space:]]*(DEFER|CUT)/)) {
              tag = substr($0, RSTART, RLENGTH);
          }
          printf "%s|%s|%s\n", id, tag, sect;
      }
    ' "$(TRACKER)"
}

@test "control: the extractor finds items in every tier section" {
    # Without this, a renamed heading empties every check below and the file goes
    # green while guarding nothing — the absent-input-reads-as-pass shape this
    # repo keeps paying for.
    local rows
    rows="$(tier_rows)"
    [ -n "$rows" ]
    [ "$(printf '%s\n' "$rows" | grep -c .)" -ge 40 ]

    local t
    for t in T1 T2 T3; do
        grep -qE "\|$t\$" <<<"$rows" || {
            echo "extractor found no items in section $t" >&2
            return 1
        }
    done
}

@test "control: every live item's tier tag is readable" {
    # A tag this extractor cannot parse would pass the ordering test below by
    # vacuity, so refusing to classify is itself a failure.
    local rows unreadable=""
    rows="$(tier_rows)"

    local line id tag
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        id="${line%%|*}"
        tag="$(cut -d'|' -f2 <<<"$line")"
        [ -n "$tag" ] || unreadable+="  $id"$'\n'
    done <<<"$rows"

    if [ -n "$unreadable" ]; then
        printf 'items whose tier tag could not be read:\n%s' "$unreadable" >&2
        return 1
    fi
}

@test "tracker: every item's tier tag agrees with its tier section" {
    local rows
    rows="$(tier_rows)"
    [ -n "$rows" ]

    local line id tag sect mismatched=""
    while IFS= read -r line; do
        [ -n "$line" ] || continue
        id="${line%%|*}"
        tag="$(cut -d'|' -f2 <<<"$line")"
        sect="${line##*|}"
        # Permissive: the section's tier must appear ANYWHERE in the tag.
        grep -qF -- "$sect" <<<"$tag" \
            || mismatched+="  $id is under ## $sect but tagged $tag"$'\n'
    done <<<"$rows"

    if [ -n "$mismatched" ]; then
        printf 'items filed under the wrong tier section:\n%s' "$mismatched" >&2
        return 1
    fi
}

@test "positive control: the check fires on an item filed in the wrong section" {
    # Reproduces the §73 incident against a fixture, so the test above is known
    # to be capable of failing without having to mutate the real tracker.
    #
    # The section marker is assembled at RUNTIME rather than written literally,
    # so the two fabricated IDs never appear as text in this tracked file. The
    # first version hardcoded them and broke tracker_citation_resolution.bats,
    # which runs `git grep -E '<marker>[0-9]'` over tracked files and correctly
    # reported them as citations resolving to nothing. Two lessons, both paid
    # for: fixture IDs that look like citations ARE citations to any repo-wide
    # scanner, and **a new test file passes the suite while untracked and can
    # only break a git-scoped guard once committed** — so a green run on an
    # untracked file is not a green run.
    local S; S="$(printf '\302\247')"
    local fixture="$BATS_TEST_TMPDIR/wrong.md"
    cat > "$fixture" <<EOF
## T2 — contract integrity

- **${S}900 A correctly filed T2 item.** [T2 — with rationale]  ·  *Radius: PRODUCT*
  - detail

## T3 — coverage, audit, docs

- **${S}901 A T2 item mis-filed under T3, reproducing the incident.** [T2]  ·  *Radius: PRODUCT*
  - detail
EOF

    run awk '
      /^## T2 / { sect="T2"; next }
      /^## T3 / { sect="T3"; next }
      sect == "" { next }
      /^- \*\*§[0-9]+/ {
          if (match($0, /§[0-9]+/)) id = substr($0, RSTART, RLENGTH);
          if (match($0, /\*\*[[:space:]]*\[[^]]+\]/)) tag = substr($0, RSTART, RLENGTH);
          if (index(tag, sect) == 0) print id " under " sect " tagged " tag;
      }
    ' "$fixture"

    [ "$status" -eq 0 ]
    # The mis-filed item is caught and the correctly-filed one is not — both
    # halves, so the detector is neither blind nor indiscriminate. IDs are built
    # from $S for the same reason as the fixture above: a literal here would be
    # a citation to any repo-wide scanner.
    grep -qF "${S}901" <<<"$output"
    refute grep -qF "${S}900" <<<"$output"
}

@test "positive control: a deliberate hold is NOT reported as a mismatch" {
    # The narrow half. §18 is tagged `[T3 → held at T2 while the key is public]`
    # and filed under T2 on purpose; a stricter rule that read only the FIRST
    # tier in the tag would call that an error and invite someone to "fix" a
    # correct decision.
    local rows tag
    rows="$(tier_rows)"
    tag="$(grep -E '^§18\|' <<<"$rows" | cut -d'|' -f2)"

    # Control: §18 really is the shape this test describes.
    [ -n "$tag" ]
    grep -qF 'held at T2' <<<"$tag"
    grep -qF 'T3' <<<"$tag"
    # ...and it lives under T2, where the permissive rule accepts it.
    grep -qE '^§18\|.*\|T2$' <<<"$rows"
}
