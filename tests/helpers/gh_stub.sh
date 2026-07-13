#!/usr/bin/env bash
# Test stub for the `gh` CLI. Drop into a directory and PATH-prepend it.
#
# Behaviour is driven by env vars so each test can set its own contract:
#   MANIFEST_CLI_GH_STUB_LOG       - file to append invocations to (TSV: epoch \t argv...)
#   MANIFEST_CLI_GH_STUB_EXIT      - exit code for non-`auth status` calls (default 0)
#   MANIFEST_CLI_GH_STUB_AUTH_EXIT - exit code for `gh auth status` (default $MANIFEST_CLI_GH_STUB_EXIT)
#   MANIFEST_CLI_GH_STUB_STDOUT    - text echoed to stdout before exit
#   MANIFEST_CLI_GH_STUB_STDERR    - text echoed to stderr before exit
#   MANIFEST_CLI_GH_STUB_ADD_REMOTE - when true, successful `repo create`
#                                     simulates --remote by adding an origin
#
# The stub never touches the network. Each invocation is recorded so tests
# can assert exactly what was called.

set -u

if [[ -n "${MANIFEST_CLI_GH_STUB_LOG:-}" ]]; then
    printf '%s' "$(date +%s)" >> "$MANIFEST_CLI_GH_STUB_LOG"
    for arg in "$@"; do
        printf '\t%s' "$arg" >> "$MANIFEST_CLI_GH_STUB_LOG"
    done
    printf '\n' >> "$MANIFEST_CLI_GH_STUB_LOG"
fi

if [[ -n "${MANIFEST_CLI_GH_STUB_STDOUT:-}" ]]; then
    printf '%s\n' "$MANIFEST_CLI_GH_STUB_STDOUT"
fi
if [[ -n "${MANIFEST_CLI_GH_STUB_STDERR:-}" ]]; then
    printf '%s\n' "$MANIFEST_CLI_GH_STUB_STDERR" >&2
fi

# `gh auth status` gets its own exit hook so we can simulate "installed
# but not authenticated" without forcing every other call to fail.
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit "${MANIFEST_CLI_GH_STUB_AUTH_EXIT:-${MANIFEST_CLI_GH_STUB_EXIT:-0}}"
fi

if [[ "${1:-}" == "repo" && "${2:-}" == "create" \
    && "${MANIFEST_CLI_GH_STUB_ADD_REMOTE:-false}" == "true" \
    && "${MANIFEST_CLI_GH_STUB_EXIT:-0}" -eq 0 ]]; then
    target="${3:-}"
    source_dir=""
    remote_name="origin"
    for arg in "$@"; do
        case "$arg" in
            --source=*) source_dir="${arg#--source=}" ;;
            --remote=*) remote_name="${arg#--remote=}" ;;
        esac
    done
    if [[ -n "$source_dir" ]]; then
        [[ "$target" == */* ]] || target="authenticated-user/$target"
        git -C "$source_dir" remote add "$remote_name" "git@github.com:${target}.git"
    fi
fi

exit "${MANIFEST_CLI_GH_STUB_EXIT:-0}"
