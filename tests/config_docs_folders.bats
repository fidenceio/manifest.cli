#!/usr/bin/env bats

# Coverage for get_docs_folder / get_docs_archive_folder (manifest-config.sh):
# default values, configured overrides, and the project-root fallback chain
# (explicit arg -> MANIFEST_CLI_PROJECT_ROOT -> ".").

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    # Wipe inherited values so we exercise the defaults, not the host config.
    unset MANIFEST_CLI_DOCS_FOLDER MANIFEST_CLI_DOCS_ARCHIVE_FOLDER MANIFEST_CLI_PROJECT_ROOT
    load_modules "core/manifest-config.sh"
}

teardown() {
    rm -rf "$SCRATCH"
}

@test "config: docs folders default to <root>/docs and <root>/docs/zArchive" {
    set_default_configuration
    run get_docs_folder "/proj/root"
    [ "$status" -eq 0 ]
    [ "$output" = "/proj/root/docs" ]
    run get_docs_archive_folder "/proj/root"
    [ "$status" -eq 0 ]
    [ "$output" = "/proj/root/docs/zArchive" ]
}

@test "config: configured docs folders are honored over the defaults" {
    export MANIFEST_CLI_DOCS_FOLDER="documentation"
    export MANIFEST_CLI_DOCS_ARCHIVE_FOLDER="documentation/attic"
    set_default_configuration
    run get_docs_folder "/proj/root"
    [ "$output" = "/proj/root/documentation" ]
    run get_docs_archive_folder "/proj/root"
    [ "$output" = "/proj/root/documentation/attic" ]
}

@test "config: docs folders fall back to MANIFEST_CLI_PROJECT_ROOT, then to ." {
    set_default_configuration
    export MANIFEST_CLI_PROJECT_ROOT="/opt/projx"
    run get_docs_folder
    [ "$output" = "/opt/projx/docs" ]
    run get_docs_archive_folder
    [ "$output" = "/opt/projx/docs/zArchive" ]

    export MANIFEST_CLI_PROJECT_ROOT=""
    run get_docs_folder
    [ "$output" = "./docs" ]
    run get_docs_archive_folder
    [ "$output" = "./docs/zArchive" ]
}
