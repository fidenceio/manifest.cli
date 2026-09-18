#!/usr/bin/env bats
#
# The process-environment config layer must be captured EXACTLY (TRACKER §12c).
#
# This layer outranks every file, so a value corrupted on the way in silently
# beats config the user can actually open and read. It used to be captured by
# parsing `env` output line by line, which corrupts two value shapes:
#
#   * a value containing a SPACE — GNU coreutils `env` shell-quotes it when
#     listing (measured, coreutils 9.12: `VAR='has space'`), and the parser
#     kept the quotes. BSD `env` does not quote, so this was invisible on a
#     stock macOS dev box and live for every Linux user AND every Homebrew
#     macOS user (the formula depends on coreutils and the wrapper puts gnubin
#     first). Manifest's own defaults include `docs.retain: "10 versions"`.
#   * a value containing a NEWLINE — corrupted under either env. BSD prints it
#     across lines, so the remainder parsed as a separate entry (dropped, or
#     captured as a phantom key); GNU keeps it on one line as a quoted ANSI-C
#     literal, captured verbatim.
#
# The guard does NOT require GNU coreutils to be installed: it puts an `env` on
# PATH that always shell-quotes. That is the positive control. The current
# implementation uses bash prefix expansion and never execs `env`, so the stub
# is inert — but if the implementation ever goes back to parsing `env`, the stub
# corrupts the value and these tests go red on macOS and Linux alike.
#
# Found when the release gate failed twice on two tests while the same suite was
# green five times in a row for the developer: the gate prepends Homebrew's
# gnubin to PATH, so it alone ran against GNU `env`.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# An `env` that shell-quotes every value containing a space, the way GNU
# coreutils does. Installed on PATH ahead of the real one.
#
# The stub enumerates its OWN exported set (`compgen -e`) rather than
# re-parsing `/usr/bin/env`'s listing. The first draft did the latter, and it
# carried the very assumption this file exists to test: that the `env`
# underneath does not quote. Measured: coreutils 9.11 (alpine 3.24) lists
# `PROBE=has space`; 9.12 (this host's Homebrew) lists `PROBE='has space'`. On
# a 9.12 `/usr/bin/env` the old stub emitted `PROBE=''has space''`, its own
# control failed, and the test went red for a reason unrelated to the code
# under test — a precondition supplied by the platform (the two-userlands gap
# TRACKER §74 records).
_install_quoting_env_stub() {
    local d="$SCRATCH/bin"
    mkdir -p "$d"
    cat > "$d/env" <<'STUB'
#!/bin/bash
# Listing form only; delegate every other use to the real env.
if [ "$#" -gt 0 ]; then exec /usr/bin/env "$@"; fi
for name in $(compgen -e); do
    value="${!name}"
    case "$value" in
        *" "*) printf "%s='%s'\n" "$name" "$value" ;;
        *)     printf '%s=%s\n' "$name" "$value" ;;
    esac
done
STUB
    chmod +x "$d/env"
    printf '%s' "$d"
}

# Run the capture in a child shell with a given MANIFEST_CLI_* value exported,
# and print exactly what landed in _MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES.
_capture_value() {
    local var="$1" value="$2" extra_path="${3:-}"
    local path="$PATH"
    [ -n "$extra_path" ] && path="$extra_path:$PATH"
    # The repo root travels as the positional $1, not as an env var:
    # helpers/setup.bash recomputes TEST_REPO_ROOT from BASH_SOURCE
    # unconditionally, so an exported one would be dead weight.
    env -i \
        PATH="$path" HOME="$SCRATCH/home" TMPDIR="${TMPDIR:-/tmp}" \
        "$var=$value" \
        bash -c '
            source "$1/tests/helpers/setup.bash"
            load_modules "core/manifest-config.sh" >/dev/null 2>&1
            printf "%s" "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[$2]-<ABSENT>}"
        ' _ "$TEST_REPO_ROOT" "$var"
}

@test "capture: a value containing a SPACE is captured verbatim, with no added quotes" {
    run _capture_value MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES ".env-secret, manifest.config.local.yaml"
    [ "$status" -eq 0 ]
    [ "$output" = ".env-secret, manifest.config.local.yaml" ]
    # The specific corruption: literal quotes wrapped around the value.
    case "$output" in "'"*"'") echo "value arrived shell-quoted: $output" >&2; return 1 ;; esac
}

@test "capture: a space-containing value survives an 'env' that shell-quotes (GNU behaviour)" {
    local stub_dir
    stub_dir="$(_install_quoting_env_stub)"
    # Control: the stub really does quote, so a parser that shells out to `env`
    # WOULD be corrupted here. Without this, the test could pass because the
    # stub silently failed to install.
    run env -i PATH="$stub_dir:$PATH" HOME="$SCRATCH/home" PROBE="has space" \
        bash -c 'env | grep "^PROBE="'
    [ "$status" -eq 0 ]
    [ "$output" = "PROBE='has space'" ]

    run _capture_value MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES ".env-secret, manifest.config.local.yaml" "$stub_dir"
    [ "$status" -eq 0 ]
    [ "$output" = ".env-secret, manifest.config.local.yaml" ]
}

@test "capture: a value containing a NEWLINE is not truncated at the newline" {
    run _capture_value MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES "$(printf -- '- .env\n- mysecret.txt')"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf -- '- .env\n- mysecret.txt')" ]
    # The specific corruption: everything after the newline dropped.
    [ "$output" != "- .env" ]
}

@test "capture: docs.retain's own shipped default shape round-trips" {
    # Manifest ships `docs.retain: "10 versions"`. A space in a DEFAULT means
    # this class is reachable without the user doing anything unusual.
    run _capture_value MANIFEST_CLI_DOCS_RETAIN "10 versions"
    [ "$status" -eq 0 ]
    [ "$output" = "10 versions" ]
}

@test "capture: a plain value with no space is captured (control — the mechanism works at all)" {
    run _capture_value MANIFEST_CLI_DOCS_FOLDER "documentation"
    [ "$status" -eq 0 ]
    [ "$output" = "documentation" ]
}

@test "capture: a MANIFEST_CLI_ variable that is NOT exported is not part of this layer" {
    # The layer is the process environment. A shell-local set by a module
    # before the capture ran is not in it, and must not be captured as though
    # the user had exported it.
    #
    # PRESENCE CONTROL, and it is the whole test. An absence assertion is
    # satisfied just as well by a child that never ran: with the positional
    # repo root ($1 below) pointing nowhere the module is never sourced, the
    # array is empty, and a bare `[ "$output" = "<ABSENT>" ]` PASSES. (Measured
    # — and it is the same shape §12b already books from
    # cleanup_command_scope.bats.) So this child exports a second mapped
    # variable and prints BOTH: the absence only means something because the
    # presence beside it proves the capture ran.
    run env -i PATH="$PATH" HOME="$SCRATCH/home" TMPDIR="${TMPDIR:-/tmp}" \
        MANIFEST_CLI_DOCS_RETAIN="7 versions" \
        bash -c '
            MANIFEST_CLI_DOCS_FOLDER="shell-local-only"   # deliberately not exported
            source "$1/tests/helpers/setup.bash"
            load_modules "core/manifest-config.sh" >/dev/null 2>&1
            printf "local=%s|exported=%s" \
                "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[MANIFEST_CLI_DOCS_FOLDER]-<ABSENT>}" \
                "${_MANIFEST_CONFIG_PROCESS_ENV_OVERRIDES[MANIFEST_CLI_DOCS_RETAIN]-<ABSENT>}"
        ' _ "$TEST_REPO_ROOT"
    [ "$status" -eq 0 ]
    [ "$output" = "local=<ABSENT>|exported=7 versions" ]
}
