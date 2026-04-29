#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    unset _MANIFEST_DEPRECATIONS_WARNED MANIFEST_CLI_QUIET_DEPRECATIONS
}

@test "log_deprecated emits a warning containing both old and new names" {
    run log_deprecated "old.thing" "new.thing"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "old.thing"
    echo "$output" | grep -q "new.thing"
}

@test "log_deprecated only warns once per old-name per session" {
    # First call emits the warning.
    run log_deprecated "manifest update" "manifest upgrade"
    local first_output="$output"
    echo "$first_output" | grep -q "deprecated"

    # Second call (same process via 'run' loses env, so we drive it manually).
    log_deprecated "manifest update" "manifest upgrade" 2>/tmp/dep1.txt
    log_deprecated "manifest update" "manifest upgrade" 2>/tmp/dep2.txt
    [ -s /tmp/dep1.txt ]
    [ ! -s /tmp/dep2.txt ]
    rm -f /tmp/dep1.txt /tmp/dep2.txt
}

@test "log_deprecated is suppressed when MANIFEST_CLI_QUIET_DEPRECATIONS=1" {
    export MANIFEST_CLI_QUIET_DEPRECATIONS=1
    run log_deprecated "anything" "anything-else"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "log_deprecated accepts forgiving truthy grammars (true/yes/TRUE/whitespace)" {
    # Regression test for the is_truthy migration.  Before, only the literal
    # string "1" suppressed deprecations; "true", "yes", or " 1 " would all
    # silently leak warnings even though the user clearly meant "yes, quiet".
    for v in "true" "yes" "on" "TRUE" "YES" "  1  " "	true	"; do
        unset _MANIFEST_DEPRECATIONS_WARNED
        export MANIFEST_CLI_QUIET_DEPRECATIONS="$v"
        run log_deprecated "old.$v" "new.$v"
        [ "$status" -eq 0 ]
        [ -z "$output" ] || { echo "value=$v leaked output: $output"; false; }
    done
}

@test "log_deprecated still emits when MANIFEST_CLI_QUIET_DEPRECATIONS is falsy or garbage" {
    # Falsy (0/false/no/empty) and unknown values both fall through to
    # "warn normally" — only explicit truthy suppresses.
    for v in "0" "false" "no" "" "garbage"; do
        unset _MANIFEST_DEPRECATIONS_WARNED
        export MANIFEST_CLI_QUIET_DEPRECATIONS="$v"
        run log_deprecated "old.$v" "new.$v"
        [ "$status" -eq 0 ]
        echo "$output" | grep -q "deprecated" || { echo "value=$v swallowed warning"; false; }
    done
}

@test "log_deprecated includes optional context note when provided" {
    log_deprecated "old.flag" "new.flag" "since v42" 2>/tmp/dep_note.txt
    grep -q "since v42" /tmp/dep_note.txt
    rm -f /tmp/dep_note.txt
}
