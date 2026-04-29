#!/usr/bin/env bash
# Test stub for the `gh` CLI. Drop into a directory and PATH-prepend it.
#
# Behaviour is driven by env vars so each test can set its own contract:
#   GH_STUB_LOG       - file to append invocations to (TSV: epoch \t argv...)
#   GH_STUB_EXIT      - exit code for non-`auth status` calls (default 0)
#   GH_STUB_AUTH_EXIT - exit code for `gh auth status` (default $GH_STUB_EXIT)
#   GH_STUB_STDOUT    - text echoed to stdout before exit
#   GH_STUB_STDERR    - text echoed to stderr before exit
#
# The stub never touches the network. Each invocation is recorded so tests
# can assert exactly what was called.

set -u

if [[ -n "${GH_STUB_LOG:-}" ]]; then
    printf '%s' "$(date +%s)" >> "$GH_STUB_LOG"
    for arg in "$@"; do
        printf '\t%s' "$arg" >> "$GH_STUB_LOG"
    done
    printf '\n' >> "$GH_STUB_LOG"
fi

if [[ -n "${GH_STUB_STDOUT:-}" ]]; then
    printf '%s\n' "$GH_STUB_STDOUT"
fi
if [[ -n "${GH_STUB_STDERR:-}" ]]; then
    printf '%s\n' "$GH_STUB_STDERR" >&2
fi

# `gh auth status` gets its own exit hook so we can simulate "installed
# but not authenticated" without forcing every other call to fail.
if [[ "${1:-}" == "auth" && "${2:-}" == "status" ]]; then
    exit "${GH_STUB_AUTH_EXIT:-${GH_STUB_EXIT:-0}}"
fi

exit "${GH_STUB_EXIT:-0}"
