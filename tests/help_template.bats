#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
}

@test "_render_help prints Usage line and description" {
    run _render_help "manifest foo bar [--baz]" "Do the foo thing."
    [ "$status" -eq 0 ]
    echo "$output" | grep -qFx "Usage: manifest foo bar [--baz]"
    echo "$output" | grep -qFx "Do the foo thing."
}

@test "_render_help renders named sections in order" {
    run _render_help \
        "manifest x [--y]" \
        "Description line." \
        "Options" "  --y    Toggle y" \
        "Examples" "  manifest x --y"

    [ "$status" -eq 0 ]
    # Section headings present with trailing colon.
    echo "$output" | grep -qFx "Options:"
    echo "$output" | grep -qFx "Examples:"
    # Bodies present verbatim.
    echo "$output" | grep -q -- "--y    Toggle y"
    echo "$output" | grep -q -- "manifest x --y"
}

@test "_render_help description supports multi-line input" {
    run _render_help \
        "manifest x" \
        "Line one.
Line two." \
        "Notes" "  hi"

    [ "$status" -eq 0 ]
    echo "$output" | grep -qFx "Line one."
    echo "$output" | grep -qFx "Line two."
}

@test "_render_help_error returns 1 with usage line" {
    run _render_help_error "Unknown option: --banana" "manifest foo [--baz]"
    [ "$status" -eq 1 ]
    # Error message goes through log_error to stderr; usage line goes to stderr too.
    echo "$output" | grep -qE "Unknown option.*--banana"
    echo "$output" | grep -qFx "Usage: manifest foo [--baz]"
}

@test "ship repo --help uses the new template (renders Examples section)" {
    # Source the ship module on top of the base modules; load_modules already
    # provides shared-utils + shared-functions + yaml.
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"

    run manifest_ship_repo --help
    [ "$status" -eq 0 ]
    echo "$output" | grep -qFx "Usage: manifest ship repo <patch|minor|major|revision> [--local] [-i]"
    echo "$output" | grep -qFx "Options:"
    echo "$output" | grep -qFx "Examples:"
}

@test "ship fleet --help surfaces previously-hidden flags" {
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"

    run manifest_ship_fleet --help
    [ "$status" -eq 0 ]
    # Hidden flags from tracker item #25 must be visible:
    echo "$output" | grep -q -- "--noprep"
    echo "$output" | grep -q -- "--safe"
    echo "$output" | grep -q -- "--method"
    echo "$output" | grep -q -- "--draft"
    echo "$output" | grep -q -- "--force"
    echo "$output" | grep -q -- "--no-delete-branch"
    # Flow section should be present so users see the pipeline.
    echo "$output" | grep -qFx "Flow:"
}
