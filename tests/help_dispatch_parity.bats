#!/usr/bin/env bats
#
# Guards docs/TRACKER.md §11.
#
# The command set is stated in four places: the dispatch `case` in
# modules/core/manifest-core.sh (the only authority), display_help, the three
# completion files, and docs/COMMAND_REFERENCE.md. Nothing compared any two of
# them, and on 2026-08-20 each had drifted differently — display_help was
# missing EIGHT dispatched, already-documented fleet commands while advertising
# the deprecated `refresh fleet`, and the completions offered no `revert` at
# all. A full 1532/1532 green suite either side of that fix proved the point:
# no test asserted on display_help, so nothing could have caught it.
#
# The authority is parsed, never restated here — a hand-kept list of commands
# in a test is just a fifth surface to drift. The one thing the file declares
# for us is intent: an arm carrying `# manifest:hidden` is deliberately absent
# from help (deprecated spellings and ship-internal plumbing). Everything else
# must be discoverable.
#
# Deliberately NOT asserted: that the completions' flag lists match each
# command's own --help. That needs a parser per help format and would fail for
# reasons unrelated to discoverability. The top-level command set is the part
# that silently rots.

load 'helpers/setup'

# Emit the primary name of every arm in the top-level command dispatch.
#
# Scoped to the dispatch `case` only. manifest-core.sh contains several other
# `case` statements over the same variable — the pre-dispatch config-loading
# one repeats many of these patterns — so an unscoped scan would read arms that
# are not dispatch targets. The range is anchored on the banner comment that
# opens the dispatch block, not on a line number.
_dispatch_arms() {
    local kind="$1"   # visible | hidden
    awk -v kind="$kind" '
        /^    # Command dispatch — / { indispatch = 1 }
        indispatch && /^    esac/    { exit }
        indispatch && /^ {8}"[a-z]/ {
            hidden = ($0 ~ /# manifest:hidden/)
            if ((kind == "hidden") != hidden) next
            line = $0
            sub(/\).*$/, "", line)          # drop everything from the closing paren
            gsub(/[[:space:]]/, "", line)
            n = split(line, pats, "|")
            for (i = 1; i <= n; i++) {
                p = pats[i]
                gsub(/"/, "", p)
                # Flag spellings of a command (-h, --help) are not commands.
                if (p ~ /^-/) continue
                print p
            }
        }
    ' "$TEST_REPO_ROOT/modules/core/manifest-core.sh" | sort -u
}

# Emit the subcommand names of the inline sub-dispatch inside ONE top-level arm.
#
# The top-level scan above stops at the first level, so a `config` arm can grow
# live subcommands that no surface mentions and the whole suite stays green:
# on 2026-08-25 `config show`, `config time` and `config setup` were all
# dispatched, all offered by all three completions, and none of the three were
# in display_help — 7/7 parity tests passing throughout. Second-level drift is
# the same defect one level down, so it needs the same parse.
#
# Parent-generic in shape: pass any top-level command whose arm opens its own
# `case`. Only `config` is wired up below; see the coverage note on the
# sub-dispatch parity test for why.
#
# Known limit, measured 2026-08-25 rather than assumed: this recognizes QUOTED
# sub-arm patterns. `config`, `pr`, `cloud` and `docs` quote theirs; the
# scope-dispatching arms (plan, reconcile, discover, add, update, topics,
# validate) write theirs bare — `fleet)`, not `"fleet")` — and this scan
# returns nothing for them. Widening the pattern is not enough to wire those
# up: they also spell their help arm `help|-h|--help`, so the rule below would
# read a bare `help` as a subcommand needing a help line.
#
# If `config` ever restyles to bare patterns this returns nothing, and the
# listing test below would pass vacuously. That is exactly what the exact-set
# positive control guards, and why the control asserts the whole set instead of
# a count — verified by mutation: breaking the indent anchor leaves the listing
# test green and turns the control red.
#
# Which patterns count as commands — the rule, applied identically here and in
# _dispatch_arms:
#   * every pattern of a multi-pattern arm counts, not just the first;
#   * a pattern starting with `-` is a FLAG spelling ('-h', '--help',
#     '--non-interactive'), not a command, and is not expected in help;
#   * the empty pattern `""` is the no-argument default, not a command;
#   * `*` is the unknown-subcommand fallback, not a command.
_sub_dispatch_arms() {
    local parent="$1" kind="$2"   # kind: visible | hidden
    awk -v parent="$parent" -v kind="$kind" '
        /^    # Command dispatch — / { indispatch = 1 }
        indispatch && /^    esac/    { exit }
        !indispatch { next }

        # Enter the parent arm, and leave it at the next top-level arm. Anchored
        # on the dispatch banner first, because the pre-dispatch case nests its
        # own "config") arm at this very indentation.
        $0 ~ "^        \"" parent "\"\\)" { inparent = 1; next }
        inparent && /^ {8}"/             { exit }

        # A sub-arm is a 16-space-indented pattern list ending in `)`. The
        # trailing-paren requirement is what keeps the heredoc that `config
        # --help` prints from being read as a set of case arms.
        inparent && /^ {16}"[^)]*\)[[:space:]]*(#.*)?$/ {
            hidden = ($0 ~ /# manifest:hidden/)
            if ((kind == "hidden") != hidden) next
            line = $0
            sub(/\).*$/, "", line)          # drop everything from the closing paren
            gsub(/[[:space:]]/, "", line)
            n = split(line, pats, "|")
            for (i = 1; i <= n; i++) {
                p = pats[i]
                gsub(/"/, "", p)
                if (p == "")      continue  # the no-argument arm
                if (p ~ /^-/)     continue  # flag spellings are not commands
                if (p ~ /^\*/)    continue  # unknown-subcommand fallback
                print p
            }
        }
    ' "$TEST_REPO_ROOT/modules/core/manifest-core.sh" | sort -u
}

# Emit every subcommand token display_help attributes to one parent command,
# reading the help listing on stdin.
#
# A bare word search cannot answer this: 'show' appears in help today on the
# `recipe list|show|explain` line, so asking "is the word show in help?" would
# report `config show` as documented while it was not. Only the command column
# of a line that starts with the parent counts.
_help_sub_tokens() {
    local parent="$1"
    awk -v parent="$parent" '
        $0 !~ "^    " parent "([[:space:]]|$)" { next }
        {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            # The command column ends at the first run of two or more spaces;
            # what follows is prose and must not be mined for command names.
            if (match(line, /[[:space:]][[:space:]]+/)) line = substr(line, 1, RSTART - 1)
            gsub(/\|/, " ", line)
            n = split(line, toks, /[[:space:]]+/)
            for (i = 1; i <= n; i++) {
                t = toks[i]
                if (t == "" || t == parent) continue
                if (t ~ /^[<[]/) continue   # <key>, [fleet] are placeholders
                print t
            }
        }
    ' | sort -u
}

@test "parity: the dispatch scan finds a believable command set (positive control)" {
    run _dispatch_arms visible
    [ "$status" -eq 0 ]

    # If the awk range or indent pattern ever stops matching, this returns
    # nothing and every parity assertion below would vacuously pass. Assert the
    # scan found something, and that it found specific known-current commands.
    [ "${#lines[@]}" -gt 15 ]
    echo "$output" | grep -qx "ship"
    echo "$output" | grep -qx "reconcile"
    echo "$output" | grep -qx "revert"

    # The hidden aliases must NOT show up in the visible set — if they did, the
    # "every dispatched command is listed in help" test would demand help lines
    # for deprecated spellings, and the marker would be decorative.
    local alias_name
    for alias_name in fleet sync time commit bump-version cleanup; do
        refute grep -qx "$alias_name" <<< "$output"
    done

    # And that the marker is doing its job in the other direction.
    run _dispatch_arms hidden
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 6 ]
    for alias_name in fleet sync time commit bump-version cleanup; do
        echo "$output" | grep -qx "$alias_name"
    done
}

@test "parity: every dispatched command is listed in 'manifest --help'" {
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" --help 2>/dev/null)"
    [ -n "$help_text" ]

    local missing=() cmd
    while read -r cmd; do
        [ -n "$cmd" ] || continue
        # Listed means the command name appears as a word in the listing.
        grep -qE "(^|[[:space:]|])${cmd}([[:space:]|]|$)" <<< "$help_text" || missing+=("$cmd")
    done < <(_dispatch_arms visible)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Dispatched but absent from 'manifest --help': ${missing[*]}" >&2
        echo "Add each to display_help, or mark its arm '# manifest:hidden'" >&2
        echo "in modules/core/manifest-core.sh if it is deliberately hidden." >&2
        return 1
    fi
}

@test "parity: every dispatched command is offered by the bash completion" {
    local top_cmds
    top_cmds="$(grep -m1 'local top_cmds=' "$TEST_REPO_ROOT/completions/manifest.bash")"
    [ -n "$top_cmds" ]

    local missing=() cmd
    while read -r cmd; do
        [ -n "$cmd" ] || continue
        grep -qE "(^|[[:space:]\"])${cmd}([[:space:]\"]|$)" <<< "$top_cmds" || missing+=("$cmd")
    done < <(_dispatch_arms visible)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Dispatched but absent from completions/manifest.bash top_cmds: ${missing[*]}" >&2
        return 1
    fi
}

# All three shells are checked, not just bash. The three files drifted apart from
# each other as well as from the dispatcher: fish kept a 'docs' description the
# other two had outgrown, and only 'ship fleet' offered `resume` while `ship
# repo` accepted it too. Each file declares its top-level set in its own syntax,
# so the pattern is per-shell.
@test "parity: every dispatched command is offered by the zsh completion" {
    local missing=() cmd
    while read -r cmd; do
        [ -n "$cmd" ] || continue
        grep -qE "^[[:space:]]*'${cmd}:" "$TEST_REPO_ROOT/completions/_manifest" || missing+=("$cmd")
    done < <(_dispatch_arms visible)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Dispatched but absent from completions/_manifest top_cmds: ${missing[*]}" >&2
        return 1
    fi
}

@test "parity: every dispatched command is offered by the fish completion" {
    local missing=() cmd
    while read -r cmd; do
        [ -n "$cmd" ] || continue
        grep -qE "__manifest_token_count 1' -a ${cmd}([[:space:]]|\$)" \
            "$TEST_REPO_ROOT/completions/manifest.fish" || missing+=("$cmd")
    done < <(_dispatch_arms visible)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Dispatched but absent from completions/manifest.fish: ${missing[*]}" >&2
        return 1
    fi
}

@test "parity: commands marked hidden stay out of 'manifest --help'" {
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" --help 2>/dev/null)"
    [ -n "$help_text" ]

    # A deprecated spelling reappearing in help is the exact defect §11
    # records: 'refresh fleet' was advertised under "Core workflow" while
    # manifest-refresh.sh called log_deprecated on it. Guard the listing
    # against the marked names returning.
    local listed=() cmd
    while read -r cmd; do
        [ -n "$cmd" ] || continue
        if grep -qE "^[[:space:]]+${cmd}([[:space:]|]|$)" <<< "$help_text"; then
            listed+=("$cmd")
        fi
    done < <(_dispatch_arms hidden)

    if [ "${#listed[@]}" -gt 0 ]; then
        echo "Marked '# manifest:hidden' but listed in help: ${listed[*]}" >&2
        echo "Either drop the marker (making it a supported command) or" >&2
        echo "remove the line from display_help." >&2
        return 1
    fi
}

@test "parity: 'refresh fleet' is not advertised as current in help" {
    # manifest-refresh.sh calls log_deprecated on it, so help must not present
    # it as a normal scope. 'refresh repo' is fine and expected.
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" --help 2>/dev/null)"
    [ -n "$help_text" ]

    # Confirm the deprecation is real before asserting on its consequence,
    # so this test fails loudly if the deprecation is ever reversed.
    grep -q 'log_deprecated "manifest refresh fleet"' \
        "$TEST_REPO_ROOT/modules/core/manifest-refresh.sh"

    refute grep -qE '^[[:space:]]+refresh repo\|fleet' <<< "$help_text"
}

# =============================================================================
# Second level: the `config` sub-dispatch.
#
# Every test above stops at the top level, which is why `config show`, `config
# time` and `config setup` could be dispatched, completed by all three shells,
# and documented in `manifest config --help` — while `manifest help` named none
# of them and this suite stayed 7/7 green.
# =============================================================================

@test "parity: the config sub-dispatch scan finds a believable subcommand set (positive control)" {
    run _sub_dispatch_arms config visible
    [ "$status" -eq 0 ]

    # An enumerator that silently parses nothing looks exactly like a passing
    # test, so name the full current set rather than asserting a count. If a
    # subcommand is added or renamed this list must be updated deliberately —
    # that is the point: it declares what the scan should see, and it is not a
    # restatement of what help says, which is the surface under test.
    local expected="describe
doctor
get
list
set
setup
show
time
unset"
    [ "$output" = "$expected" ]

    # Flag spellings are excluded by the rule, not missed by accident: the
    # `config` arm also dispatches "-h"|"--help" and "--non-interactive", and
    # none of the three belongs in a listing of commands.
    refute grep -qx -- "--non-interactive" <<< "$output"
    refute grep -qx -- "--help" <<< "$output"
    refute grep -qx -- "-h" <<< "$output"

    # No config subcommand is marked hidden today. Assert the hidden scan runs
    # and returns nothing, so an accidentally-marked arm shows up here as a
    # change rather than as a silently-exempted subcommand.
    run _sub_dispatch_arms config hidden
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "parity: the help-token scan reads the command column, not the prose (positive control)" {
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" help 2>/dev/null)"
    [ -n "$help_text" ]

    local tokens
    tokens="$(_help_sub_tokens config <<< "$help_text")"
    [ -n "$tokens" ]

    # Known-listed subcommands are found ...
    grep -qx "list" <<< "$tokens"
    grep -qx "doctor" <<< "$tokens"
    grep -qx "describe" <<< "$tokens"

    # ... and a word that appears in help only as prose, or under a DIFFERENT
    # parent, is not mistaken for a config subcommand. 'explain' is a recipe
    # subcommand on the `recipe list|show|explain` line and 'generate' belongs
    # to `env` and `cloud`; if either turned up here the scan would be matching
    # the whole listing and every assertion built on it would be vacuous.
    refute grep -qx "explain" <<< "$tokens"
    refute grep -qx "generate" <<< "$tokens"
}

@test "parity: every dispatched config subcommand is listed in 'manifest help'" {
    # Coverage note: `config` is the parent wired up here, and it is the parent
    # this test was written for. Surveying the others with the same scan on
    # 2026-08-25 gave:
    #
    #   config  9 sub-arms, 3 undocumented  <- fixed by this change
    #   cloud   3 sub-arms, 0 undocumented
    #   pr      9 sub-arms, 1 "undocumented" — a bare `help` arm, which the
    #           rule below counts as a command and probably should not
    #   docs    3 sub-arms, 3 undocumented  — cleanup, homebrew, metadata,
    #           under a top-level arm that is itself legacy plumbing
    #   plan, reconcile, discover, add, update, topics, validate
    #           bare (unquoted) patterns; not parsed at all — see the scan
    #
    # So `docs` is real drift and `pr` needs a help-arm rule first. Both are
    # left alone deliberately: neither is this change's defect, and adopting
    # them silently would mean marking or documenting commands nobody reviewed.
    # Adding a parent later is one more call to the same function.
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" help 2>/dev/null)"
    [ -n "$help_text" ]

    local listed
    listed="$(_help_sub_tokens config <<< "$help_text")"

    local missing=() sub
    while read -r sub; do
        [ -n "$sub" ] || continue
        if ! grep -qx "$sub" <<< "$listed"; then
            missing+=("$sub")
        fi
    done < <(_sub_dispatch_arms config visible)

    if [ "${#missing[@]}" -gt 0 ]; then
        echo "Dispatched by 'manifest config' but absent from 'manifest help': ${missing[*]}" >&2
        echo "Add each to the Settings block of display_help, or mark its arm" >&2
        echo "'# manifest:hidden' in modules/core/manifest-core.sh if it is" >&2
        echo "deliberately hidden." >&2
        return 1
    fi
}

@test "parity: a config subcommand deleted from help is reported missing (negative control)" {
    # The control the whole second level rests on. Without it, a scan that
    # quietly matched nothing would leave every assertion above vacuously
    # green — the precise failure mode §11 records. Take the REAL help text,
    # remove one line that documents a subcommand, and prove the comparison
    # notices the difference.
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" help 2>/dev/null)"
    [ -n "$help_text" ]

    # Prove the line is really there before removing it, so this control fails
    # loudly if the Settings block is reshaped, rather than passing on a no-op
    # edit that removed nothing.
    grep -qE '^    config list ' <<< "$help_text"

    local doctored
    doctored="$(grep -vE '^    config list ' <<< "$help_text")"
    [ "$doctored" != "$help_text" ]

    # `list` is still dispatched, so with its help line gone it must now be
    # reported as undocumented.
    grep -qx "list" <<< "$(_sub_dispatch_arms config visible)"
    refute grep -qx "list" <<< "$(_help_sub_tokens config <<< "$doctored")"

    # And the undoctored text must still yield it, so the assertion above
    # cannot be passing because the scan returns nothing at all.
    grep -qx "list" <<< "$(_help_sub_tokens config <<< "$help_text")"
}

@test "parity: config subcommands marked hidden stay out of 'manifest help'" {
    local help_text
    help_text="$(NO_COLOR=1 bash "$TEST_REPO_ROOT/scripts/manifest-cli.sh" help 2>/dev/null)"
    [ -n "$help_text" ]

    local listed
    listed="$(_help_sub_tokens config <<< "$help_text")"

    local shown=() sub
    while read -r sub; do
        [ -n "$sub" ] || continue
        if grep -qx "$sub" <<< "$listed"; then
            shown+=("$sub")
        fi
    done < <(_sub_dispatch_arms config hidden)

    if [ "${#shown[@]}" -gt 0 ]; then
        echo "Marked '# manifest:hidden' but listed under config in help: ${shown[*]}" >&2
        echo "Either drop the marker (making it a supported subcommand) or" >&2
        echo "remove it from the Settings block of display_help." >&2
        return 1
    fi
}
