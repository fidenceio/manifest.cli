#!/usr/bin/env bats
# bats file_tags=smoke
#
# Tagged smoke because this is a WHOLE-TREE invariant, not a test of one module.
# `--changed` selects by path via coverage-map.tsv and always unions the smoke
# tier; a per-path map cannot express "this test is about every file that cites
# the tracker", so without the tag no code change ever selects it (TRACKER §48).
#
# ---------------------------------------------------------------------------
# TRACKER §20 — the guard for the mechanism that broke 245 citations.
# ---------------------------------------------------------------------------
#
# The drift policy says: when an item ships, delete it and add a "Retired IDs"
# row. The deletion half was obeyed and the row half was not, so every shipped
# item took its inbound citations down with it — measured 2026-08-24 at **245
# of 308 citations pointing at nothing**, with `§5.10` alone cited 39 times
# with no target. Nothing failed; a citation that resolves to nothing reads
# exactly like one that resolves.
#
# This test makes that failure loud. It is at its most valuable during a
# rebuild, because a rebuild is the event that breaks citations.
#
# THREE DESIGN CONSTRAINTS, each discovered by getting it wrong:
#
#   1. The resolvable set is parsed from the retired tables' **ID columns**,
#      never grepped from the section. The section deliberately carries a
#      `§999` row (the fabricated control) and a foreign `CODEX_AUDIT_13Aug2026.md §0` row,
#      so a section-grep makes the control below pass vacuously — it did.
#   2. `docs/zArchive/**` is out of scope permanently (standing instruction,
#      2026-08-26) and `CHANGELOG.md` is append-only history that §20
#      deliberately leaves unrepaired.
#   3. Never `comm` or `sort -t'§'` on `§`-prefixed keys. Multibyte collation
#      returns a wrong answer with no warning (`sort: §: Invalid argument` is
#      the *lucky* case; a silently wrong ordering is the usual one).
#
# JURISDICTION. A bare `§N` is ambiguous across documents and already collides:
# `STANDARD.md §2.7` and this tracker's own retired `§2.7`-shaped IDs share the
# namespace. This test claims jurisdiction over every `§N` citation EXCEPT
# those a line qualifies with a foreign document, and the foreign list is
# **parsed from the tracker's own "Not this tracker's IDs" table** rather than
# hardcoded here — one source of truth, so a new foreign namespace must be
# declared there instead of silently exempted here (TRACKER §6's
# duplicated-derivation shape).
#
# THE TRACKER ITSELF IS OUT OF SCOPE. §20's incident is about *inbound*
# citations from code and docs breaking when an item is deleted. Inside the
# tracker a citation sits next to its definition, and the Retired section
# contains non-IDs by design that any resolver must special-case.

load 'helpers/setup'

TRACKER='docs/TRACKER.md'

# --- the resolvable set ----------------------------------------------------

# Live items are TOP-LEVEL bullets: `- **§N …**`. The leading `^- ` matters —
# an indented sub-bullet is not an item header, and the tracker records that a
# line beginning `- **§N` is indistinguishable from a header to every census
# that reads the file. Anchoring at column 0 is what separates them.
_live_ids() {
    grep -oE '^- \*\*§[0-9]+[a-z]?' "$TEST_REPO_ROOT/$TRACKER" \
        | grep -oE '§[0-9]+[a-z]?'
}

# Lettered sub-items (`§15a`, `§21b`) are real citable IDs per the preamble and
# are declared in an entry's body at any indent. Collected explicitly so that
# `§21b` resolves EXACTLY, rather than by stripping the letter — letter
# stripping would also resolve a fabricated `§21z`.
_sub_ids() {
    grep -oE '§[0-9]+[a-z]\b' "$TEST_REPO_ROOT/$TRACKER"
}

# Retired IDs, from the ID columns only (constraint 1). The renumber table is
# three `Old | New` pairs per row, so the Old cells are the even-offset ones.
_retired_ids() {
    awk '/^### Renumbered/{s=1;next} /^### Shipped or absorbed/{s=0}
         s && /^\| §/ { n=split($0,c,"|")
                        for (i=2;i<=n;i++) if ((i-2)%2==0) print c[i] }' \
        "$TEST_REPO_ROOT/$TRACKER" \
        | grep -oE '§[0-9]+(\.[0-9]+)?[a-z]?(\([a-z0-9]+\))?'

    awk '/^### Shipped or absorbed/{s=1;next} /^### Not this tracker/{s=0}
         s && /^\| §/ { n=split($0,c,"|"); print c[2] }' \
        "$TEST_REPO_ROOT/$TRACKER" \
        | grep -oE '§[0-9]+(\.[0-9]+)?[a-z]?(\([a-z0-9]+\))?'
}

resolvable_ids() { { _live_ids; _sub_ids; _retired_ids; } | sort -u; }

# Membership as a FUNCTION, not a pipeline. `refute foo | grep -q x` pipes the
# output of `refute foo` into grep — the negation applies to the wrong command
# and the assertion silently always passes. Wrapping it makes `refute _has …`
# mean what it reads as.
_has() { printf '%s\n' "$1" | grep -Fxq "$2"; }

# Foreign qualifiers, parsed from the declared table. The Citation cell is a
# description (`workspace cross-cut §1.2`) while the code says `cross-cut
# §1.2`, so the token taken is the LAST word before the `§` — the document-ish
# part that actually appears at the call site. Rows whose cell starts at `§`
# (`§999`, `§4.C D8`) declare bare values, not qualifiers, and are skipped.
foreign_qualifiers() {
    awk '/^### Not this tracker/{s=1} s && /^\| `/ {
            n=split($0,c,"|"); cell=c[2]
            gsub(/`/,"",cell); sub(/^ +/,"",cell)
            if (cell ~ /^§/) next
            if (match(cell,/§/)) {
                pre=substr(cell,1,RSTART-1); sub(/ +$/,"",pre)
                n2=split(pre,w," "); if (n2>0) print w[n2]
            }
         }' "$TEST_REPO_ROOT/$TRACKER" | sort -u
}

# --- the scan -------------------------------------------------------------

# THIS FILE IS OUT OF ITS OWN JURISDICTION, and the reason is not convenience.
# A guard for citation resolution must NAME unresolvable citations to control
# itself: `§999` and `§777` as fabricated IDs, `§21z` as a letter-stripping
# probe, and a foreign `§0`. Every one is deliberately unresolvable, so with
# this file in scope the guard becomes its own first offender. Same category as
# the `CHANGELOG.md` and `docs/zArchive` exclusions above it — a file whose job
# is incompatible with the rule.
#
# HOW THIS WAS NEARLY SHIPPED, because it is the sharper lesson. `git grep`
# reads TRACKED files only. While this file was untracked the scan could not see
# its own controls, so the full suite reported 1785/1785 — a green that existed
# only because the guard was invisible to itself, and that would have turned red
# the instant it was committed. It was caught by A/B-ing tracked against
# untracked, not by running the suite again.
#
# That is TRACKER §56/§57's exact shape recurring one guard later: §56 was a
# file that violated the version rule it enforced, §57 a control that could
# never pass because it named its own sentinel. **A guard that must speak the
# forbidden thing has to be excluded from itself, explicitly and with a reason.**
#
# The same tracked-only property means a mutation test that plants a citation
# into a NEW file proves nothing — the first attempt at the mutation test below
# did exactly that and reported a pass. Plant into a file `git ls-files` knows.
SELF_PATH='tests/tracker_citation_resolution.bats'

cited_lines() {
    git -C "$TEST_REPO_ROOT" grep -n -E '§[0-9]' -- \
        ":!$TRACKER" ':!docs/zArchive' ':!CHANGELOG.md' ":!$SELF_PATH"
}

@test "tracker citations: every §-citation outside the tracker resolves" {
    local resolvable foreign unresolved=""
    resolvable="$(resolvable_ids)"
    foreign="$(foreign_qualifiers | tr '\n' '|')"
    foreign="${foreign%|}"
    [ -n "$foreign" ]   # a silently-empty list would exempt nothing and is a bug

    local line body id
    while IFS= read -r line; do
        body="${line#*:*:}"

        # Out of jurisdiction: the line names a foreign document.
        [[ "$body" =~ ($foreign)[[:space:]]*§ ]] && continue

        while IFS= read -r id; do
            [ -n "$id" ] || continue

            # Out of jurisdiction: three or more levels. This tracker's schemes
            # are §N, §Na, §N(x) and the retired §N.M; it has never issued a
            # three-level ID (asserted below). `tests/env_generate.bats` cites
            # `§2.7.2`, which a two-level pattern silently truncates to a §2.7
            # prefix — the miscount the tracker's own note warns about.
            [[ "$id" =~ ^§[0-9]+\.[0-9]+\.[0-9]+ ]] && continue

            printf '%s\n' "$resolvable" | grep -Fxq "$id" && continue

            # `§2(c)` resolves through its parent `§2`; likewise `§9.27(a)`.
            local base="${id%%(*}"
            if [ "$base" != "$id" ]; then
                printf '%s\n' "$resolvable" | grep -Fxq "$base" && continue
            fi

            unresolved+="  ${line%%:*}:${id}"$'\n'
        done < <(printf '%s\n' "$body" \
                   | grep -oE '§[0-9]+(\.[0-9]+)*[a-z]?(\([a-z0-9]+\))?')
    done < <(cited_lines)

    if [ -n "$unresolved" ]; then
        printf 'citations resolving to no live item and no Retired-IDs row:\n%s' \
            "$unresolved" >&2
        printf 'Fix by adding a Retired-IDs row (see the drift policy), not by deleting the citation.\n' >&2
    fi
    [ -z "$unresolved" ]
}

# ---------------------------------------------------------------------------
# Controls. Without these the test above passes when the resolver is broken:
# an over-broad resolvable set accepts everything, and an empty citation scan
# finds nothing to reject. Both read identically to "all citations resolve".
# ---------------------------------------------------------------------------

@test "positive control: a fabricated §999 does NOT resolve" {
    # §999 is the reason this control exists AND the reason it once passed
    # vacuously: the Retired section carries a literal `§999` row describing
    # this very control, so a resolver that greps the section accepts it.
    # Parsing the ID columns is what makes this assertion meaningful.
    local resolvable
    resolvable="$(resolvable_ids)"

    refute _has "$resolvable" '§999'
    refute _has "$resolvable" '§777'

    # ...while the section demonstrably does mention it, which is the trap.
    grep -Fq '§999' "$TEST_REPO_ROOT/$TRACKER"
}

@test "positive control: known-good IDs of every shape DO resolve" {
    local resolvable
    resolvable="$(resolvable_ids)"

    # A resolver that matched nothing would make the main test pass silently.
    _has "$resolvable" '§6'        # live item
    _has "$resolvable" '§21b'      # lettered sub-item
    _has "$resolvable" '§5.10'     # retired, cited 39x
    _has "$resolvable" '§9.27(a)'  # retired with sub-part
    _has "$resolvable" '§1.2'      # retired, collides with a foreign ID
}

@test "positive control: the citation scan actually finds citations" {
    # An empty scan is the other way the main test passes vacuously.
    local n
    n="$(cited_lines | grep -c . || true)"
    [ "$n" -gt 100 ]
}

@test "the self-exclusion is exactly one path, and is load-bearing" {
    # Guard against the exclusion silently widening into a way to hide real
    # offenders. Exactly one path, and it must be this file.
    [ "$SELF_PATH" = 'tests/tracker_citation_resolution.bats' ]
    [ -f "$TEST_REPO_ROOT/$SELF_PATH" ]

    # And prove the exclusion is needed rather than decorative: this file really
    # does contain citations that cannot resolve, by design. If someone removes
    # the fabricated controls, this assertion says so instead of leaving a
    # pointless exclusion behind.
    run grep -c -E '§(999|777|21z)' "$TEST_REPO_ROOT/$SELF_PATH"
    [ "$status" -eq 0 ]
    [ "$output" -gt 0 ]

    # The scan must actually be excluding it: zero hits ORIGINATING from this
    # path. Anchored on the `path:` prefix of `git grep -n` output, not on the
    # bare filename — docs/TRACKER.md cites this file by name, so an unanchored
    # count matches those mentions and fails for the wrong reason. It did.
    run bash -c "cited_lines() { git -C '$TEST_REPO_ROOT' grep -n -E '§[0-9]' -- ':!$TRACKER' ':!docs/zArchive' ':!CHANGELOG.md' ':!$SELF_PATH'; }; cited_lines | grep -c \"^$SELF_PATH:\" || true"
    [ "$output" -eq 0 ]

    # Control: without the exclusion the same anchored count is NON-zero, which
    # is what makes the assertion above meaningful rather than vacuous.
    run bash -c "git -C '$TEST_REPO_ROOT' grep -n -E '§[0-9]' -- ':!$TRACKER' ':!docs/zArchive' ':!CHANGELOG.md' | grep -c \"^$SELF_PATH:\" || true"
    [ "$output" -gt 0 ]
}

@test "the foreign-qualifier list is parsed, non-empty, and names STANDARD.md" {
    local q
    q="$(foreign_qualifiers)"
    [ -n "$q" ]
    _has "$q" 'STANDARD.md'

    # A row declaring a bare value, not a qualifier, must not become one:
    # taking a prefix from `§999` would exempt every line containing a digit.
    refute _has "$q" '§999'
}

_three_level_present() { resolvable_ids | grep -qE '^§[0-9]+\.[0-9]+\.[0-9]+'; }

@test "no resolvable ID is three-level, so skipping that shape is sound" {
    # The main test treats a three-level ID as foreign by construction. That is
    # only valid while this tracker issues none.
    refute _three_level_present

    # Control: the pattern does match a three-level ID when given one.
    printf '§2.7.2\n' | grep -qE '^§[0-9]+\.[0-9]+\.[0-9]+'
}
