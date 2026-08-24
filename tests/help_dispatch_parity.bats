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

    # And that the marker is doing its job in the other direction.
    run _dispatch_arms hidden
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 6 ]
    echo "$output" | grep -qx "sync"
    echo "$output" | grep -qx "bump-version"
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
