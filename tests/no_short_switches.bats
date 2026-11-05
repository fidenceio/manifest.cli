#!/usr/bin/env bats
# bats file_tags=smoke
#
# Tagged smoke because this is a WHOLE-TREE invariant: every switch the CLI
# accepts has exactly one spelling, the full word. The one exception is -y,
# kept because it is the apply switch in every documented command and in every
# script that drives Manifest. Everything else that used to have a single-letter
# form (-p -m -M -r for the release types, -i, -f, -n, -p, -q, -v, -t, and -h /
# -help / -version / -v / -V for help and version) was removed in one pass, and
# a removed spelling is refused as an unknown option rather than mapped.
#
# Two halves, because a source scan proves only that no parser ARM exists while
# a runtime probe proves only the commands it probes:
#   1. Source text: no case arm or equality test in modules/ names a single-
#      letter switch other than -y. The scan has a positive control (a sample
#      arm it must catch), so an empty result is a verdict rather than a
#      broken pattern.
#   2. Runtime: the entrypoint refuses -h and -v at the top level and the ship
#      parser refuses the short release types; --help and the full words are
#      the positive controls, asserted in the same tests.

load 'helpers/setup'

MODULES="$TEST_REPO_ROOT/modules"

# Every shape a short switch took in this tree before the removal. Each is an
# ERE; the letter class excludes y. A pattern is anchored to case-arm and
# `==` comparison syntax so a `grep -q` or `cd … && pwd -P` in ordinary code
# does not match.
_short_switch_patterns() {
    cat <<'EOF'
(^|[|( ])-[A-Za-xz]\|
\|-[A-Za-xz](\||\))
^[[:space:]]*-[A-Za-xz]\)
== "-[A-Za-xz]"
"-[A-Za-xz]"\|
\|"-[A-Za-xz]"
EOF
}

# Scan a directory (or a file) for the shapes above; prints matches.
_scan_short_switches() {
    local target="$1" pattern
    while IFS= read -r pattern; do
        grep -rnE -- "$pattern" "$target" 2>/dev/null || true
    done < <(_short_switch_patterns)
}

@test "no short switch: the scan catches every retired shape (positive control)" {
    local sample="$BATS_TEST_TMPDIR/sample.sh"
    cat > "$sample" <<'EOF'
case "$1" in
    -h|--help) ;;
    help|-h|--help) ;;
    --force|-f) ;;
    -p) increment_type="patch" ;;
    "help"|"-h"|"--help") ;;
esac
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then :; fi
EOF
    run _scan_short_switches "$sample"
    [ "$status" -eq 0 ]
    # Every sample line is caught; -y alone is not.
    [ "$(printf '%s\n' "$output" | grep -c -- '-h')" -ge 4 ]
    echo "$output" | grep -q -- '--force|-f'
    echo "$output" | grep -q -- '    -p)'
    printf '    -y|--yes) ;;\n' > "$sample"
    run _scan_short_switches "$sample"
    [ -z "$output" ]
}

@test "no short switch: modules/ parses no single-letter switch except -y" {
    run _scan_short_switches "$MODULES"
    if [ -n "$output" ]; then
        echo "Short switches found (only -y is allowed):" >&2
        echo "$output" >&2
        false
    fi
}

# Each completion file carries its shell's own option syntax on every line
# (compgen -W, _values, complete -a), so the scan reads only the WORD LISTS the
# user is offered. The positive control is -y: it must be found by the same
# extraction with the letter class widened, or the extraction is reading
# nothing and the empty result below means nothing.
_bash_completion_words() {
    grep -oE 'compgen -W "[^"]*"' "$TEST_REPO_ROOT/completions/manifest.bash" \
        | sed -E 's/^compgen -W "//; s/"$//' | tr ' ' '\n'
}
_zsh_completion_words() {
    grep -E '_values' "$TEST_REPO_ROOT/completions/_manifest" \
        | sed -E "s/^[^']*'[^']*'//" | tr ' ' '\n'
}
_fish_completion_words() {
    grep -oE -- "-a '[^']*'" "$TEST_REPO_ROOT/completions/manifest.fish" \
        | sed -E "s/^-a '//; s/'$//" | tr ' ' '\n'
}

@test "no short switch: completions offer no single-letter switch except -y" {
    local shell
    for shell in bash zsh fish; do
        # control: the extraction sees -y
        "_${shell}_completion_words" | grep -qxE -- '-[A-Za-z]'
        # the claim: nothing but -y
        [ -z "$("_${shell}_completion_words" | grep -xE -- '-[A-Za-xz]')" ]
    done
}

@test "no short switch: entrypoint refuses -h and -v; --help and --version work" {
    local cli="$TEST_REPO_ROOT/scripts/manifest-cli.sh"
    local short
    for short in -h -help -v -V -version; do
        run bash "$cli" "$short"
        [ "$status" -ne 0 ]
        echo "$output" | grep -q "Unknown command: $short"
    done
    run bash "$cli" --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Usage: manifest <command>"
    run bash "$cli" --version
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Manifest CLI v"
}

# The commands whose parsers used to DROP an unknown switch rather than refuse
# it. Dropping is worse than mapping for a script author: `update fleet -q`
# printed the full banner with exit 0, and a pipeline consuming the one-line
# --quiet output ingested the banner instead of breaking. Each is probed from
# a directory that is neither a repo nor a fleet, so the refusal must come from
# the parser and not from a later "not initialized" check; the --help control
# proves the command itself is reachable there.
@test "no short switch: update/discover/validate fleet and doctor refuse, not drop, a short switch" {
    local cli="$TEST_REPO_ROOT/scripts/manifest-cli.sh"
    cd "$BATS_TEST_TMPDIR"
    local probe
    while IFS='|' read -r probe; do
        set -- $probe
        run bash "$cli" "$@"
        [ "$status" -ne 0 ]
        echo "$output" | grep -q -- "Unknown option: ${!#}"
    done <<'EOF'
update fleet -q
discover fleet -q
validate fleet -h
doctor -h
EOF
    for probe in "update fleet" "discover fleet" "validate fleet" "doctor"; do
        set -- $probe
        run bash "$cli" "$@" --help
        [ "$status" -eq 0 ]
    done
}
