#!/bin/bash

# Central dependency and version requirements for Manifest CLI.
# Keep this file Bash 3.2-compatible: wrappers source it before re-execing
# into Bash 5.

MANIFEST_CLI_REQUIRED_BASH_VERSION="${MANIFEST_CLI_REQUIRED_BASH_VERSION:-5.0}"
MANIFEST_CLI_REQUIRED_BASH_MAJOR="${MANIFEST_CLI_REQUIRED_BASH_MAJOR:-5}"

MANIFEST_CLI_REQUIRED_YQ_VERSION="${MANIFEST_CLI_REQUIRED_YQ_VERSION:-4.0}"
MANIFEST_CLI_REQUIRED_YQ_MAJOR="${MANIFEST_CLI_REQUIRED_YQ_MAJOR:-4}"
MANIFEST_CLI_REQUIRED_YQ_VENDOR="${MANIFEST_CLI_REQUIRED_YQ_VENDOR:-github.com/mikefarah/yq}"
MANIFEST_CLI_REQUIRED_YQ_LABEL="${MANIFEST_CLI_REQUIRED_YQ_LABEL:-Mike Farah yq v${MANIFEST_CLI_REQUIRED_YQ_MAJOR}+}"

MANIFEST_CLI_REQUIRED_DOCKER_COMMAND="${MANIFEST_CLI_REQUIRED_DOCKER_COMMAND:-docker}"
MANIFEST_CLI_REQUIRED_DOCKER_LABEL="${MANIFEST_CLI_REQUIRED_DOCKER_LABEL:-Docker CLI with a running Docker engine}"

MANIFEST_CLI_REQUIRED_COREUTILS_LABEL="${MANIFEST_CLI_REQUIRED_COREUTILS_LABEL:-coreutils timeout command}"

manifest_requirement_semver_major() {
    printf '%s\n' "${1:-}" | sed -nE 's/[^0-9]*([0-9]+)(\.[0-9]+){0,2}.*/\1/p' | head -n1
}

manifest_requirement_bash_major_from_command() {
    local bash_cmd="${1:-bash}"
    "$bash_cmd" -c 'echo "${BASH_VERSINFO[0]:-0}"' 2>/dev/null || echo "0"
}

manifest_requirement_bash_is_supported_major() {
    local major="${1:-0}"
    [ -n "$major" ] && [ "$major" -ge "$MANIFEST_CLI_REQUIRED_BASH_MAJOR" ]
}

manifest_requirement_current_bash_is_supported() {
    manifest_requirement_bash_is_supported_major "${BASH_VERSINFO[0]:-0}"
}

manifest_requirement_yq_version_text() {
    local yq_cmd="${1:-yq}"
    "$yq_cmd" --version 2>&1 | head -n1
}

manifest_requirement_yq_text_is_supported() {
    local version_text="${1:-}"
    local major

    printf '%s\n' "$version_text" | grep -qi "$MANIFEST_CLI_REQUIRED_YQ_VENDOR" || return 1
    major="$(manifest_requirement_semver_major "$version_text")"
    [ -n "$major" ] && [ "$major" -ge "$MANIFEST_CLI_REQUIRED_YQ_MAJOR" ]
}

manifest_requirement_yq_is_supported() {
    local yq_cmd="${1:-yq}"
    command -v "$yq_cmd" >/dev/null 2>&1 || return 1
    manifest_requirement_yq_text_is_supported "$(manifest_requirement_yq_version_text "$yq_cmd")"
}

# bats parallelism (run-tests.sh --jobs) is built on GNU parallel. moreutils
# ships an unrelated binary also named `parallel`, so presence alone isn't
# enough — verify the GNU flavor specifically, mirroring the yq vendor check.
manifest_requirement_parallel_is_gnu() {
    local parallel_cmd="${1:-parallel}"
    command -v "$parallel_cmd" >/dev/null 2>&1 || return 1
    "$parallel_cmd" --version 2>/dev/null | grep -qi 'GNU parallel'
}

manifest_requirement_docker_command_exists() {
    local docker_cmd="${1:-$MANIFEST_CLI_REQUIRED_DOCKER_COMMAND}"
    command -v "$docker_cmd" >/dev/null 2>&1
}

manifest_requirement_docker_engine_is_running() {
    local docker_cmd="${1:-$MANIFEST_CLI_REQUIRED_DOCKER_COMMAND}"
    manifest_requirement_docker_command_exists "$docker_cmd" || return 1
    "$docker_cmd" info >/dev/null 2>&1
}

manifest_requirement_coreutils_timeout_command() {
    local os_name
    os_name="$(uname -s 2>/dev/null || echo "")"

    case "$os_name" in
        Darwin)
            command -v gtimeout >/dev/null 2>&1
            ;;
        *)
            command -v timeout >/dev/null 2>&1
            ;;
    esac
}

# Prepend the Homebrew GNU-userland gnubin directories to PATH so `sed`, `date`,
# and `stat` resolve to the GNU coreutils/gnu-sed binaries on macOS — the same
# tools that ship natively on Linux. This lets every call site use one GNU
# codepath (`sed -i`, `date -d`, `stat -c`) instead of branching on BSD vs GNU.
#
# Linux is already GNU, so this is a macOS-only fixup and a no-op elsewhere.
# Both wrappers source this file (and re-source it via manifest-core.sh) before
# any module runs, so this is the single chokepoint for every channel: the brew
# formula bin wrapper, the source-install wrapper, and the dev/test path that
# sources manifest-core.sh directly.
#
# Idempotent: a gnubin dir is prepended only if it exists and is not already on
# PATH. We prepend (not append) so GNU shadows the BSD builtins for the handful
# of commands we branch on — but the gnubin dirs hold ONLY the coreutils/gnu-sed
# tools, so this never shadows unrelated user binaries (e.g. a user's own `git`
# or `python` stays first since those names are not in gnubin).
#
# Kept Bash 3.2-compatible: the wrappers call this before re-execing into Bash 5.
manifest_requirement_prepend_gnu_userland_path() {
    # Linux/other already ship GNU userland natively.
    [ "$(uname -s 2>/dev/null || echo "")" = "Darwin" ] || return 0

    local prefix gnubin
    local prefixes="/opt/homebrew /usr/local"

    # Fall back to an explicit `brew --prefix` when the formula lives somewhere
    # non-standard (e.g. a custom HOMEBREW_PREFIX); harmless if brew is absent.
    if command -v brew >/dev/null 2>&1; then
        local brew_prefix
        brew_prefix="$(brew --prefix 2>/dev/null || true)"
        [ -n "$brew_prefix" ] && prefixes="$brew_prefix $prefixes"
    fi

    for prefix in $prefixes; do
        for gnubin in "$prefix/opt/coreutils/libexec/gnubin" \
                      "$prefix/opt/gnu-sed/libexec/gnubin"; do
            [ -d "$gnubin" ] || continue
            case ":$PATH:" in
                *":$gnubin:"*) ;;                 # already present — leave order alone
                *) PATH="$gnubin:$PATH" ;;
            esac
        done
    done
    export PATH
}
