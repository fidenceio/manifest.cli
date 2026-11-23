#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
}

@test "_render_help prints Usage line and description" {
    run _render_help "manifest foo bar [--baz]" "Do the foo thing."
    [ "$status" -eq 0 ]
    grep -qFx "Usage: manifest foo bar [--baz]" <<<"$output"
    grep -qFx "Do the foo thing." <<<"$output"
}

@test "_render_help renders named sections in order" {
    run _render_help \
        "manifest x [--y]" \
        "Description line." \
        "Options" "  --y    Toggle y" \
        "Examples" "  manifest x --y"

    [ "$status" -eq 0 ]
    # Section headings present with trailing colon.
    grep -qFx "Options:" <<<"$output"
    grep -qFx "Examples:" <<<"$output"
    # Bodies present verbatim.
    grep -q -- "--y    Toggle y" <<<"$output"
    grep -q -- "manifest x --y" <<<"$output"
}

@test "_render_help description supports multi-line input" {
    run _render_help \
        "manifest x" \
        "Line one.
Line two." \
        "Notes" "  hi"

    [ "$status" -eq 0 ]
    grep -qFx "Line one." <<<"$output"
    grep -qFx "Line two." <<<"$output"
}

@test "_render_help_error returns 1 with usage line" {
    run _render_help_error "Unknown option: --banana" "manifest foo [--baz]"
    [ "$status" -eq 1 ]
    # Error message goes through log_error to stderr; usage line goes to stderr too.
    grep -qE "Unknown option.*--banana" <<<"$output"
    grep -qFx "Usage: manifest foo [--baz]" <<<"$output"
}

@test "ship repo --help uses the new template (renders Examples section)" {
    # Source the ship module on top of the base modules; load_modules already
    # provides shared-utils + shared-functions + yaml.
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"

    run manifest_ship_repo --help
    [ "$status" -eq 0 ]
    grep -qFx "Usage: manifest ship repo <patch|minor|major|revision> [-y|--yes] [--dry-run] [--local] [--force-bump] [--interactive]" <<<"$output"
    grep -qFx "Options:" <<<"$output"
    grep -qFx "Examples:" <<<"$output"
}

@test "ship fleet --help surfaces previously-hidden flags" {
    source "$TEST_REPO_ROOT/modules/core/manifest-ship.sh"

    run manifest_ship_fleet --help
    [ "$status" -eq 0 ]
    # Fleet ship is release-only. PR flags live under manifest pr fleet.
    grep -q -- "--require-clean" <<<"$output"
    grep -q -- "--dry-run" <<<"$output"
    grep -q -- "-y, --yes" <<<"$output"
    refute grep -q -- "--method" <<<"$output"
    refute grep -q -- "--draft" <<<"$output"
    # Flow section should be present so users see the pipeline.
    grep -qFx "Flow:" <<<"$output"
}
