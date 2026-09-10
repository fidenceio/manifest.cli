#!/usr/bin/env bash
#
# EXAMPLE release-notes provider: hand the request to an AI coding agent's CLI.
#
# Manifest never selects this, or any other program, on its own. You configure
# it, from a layer you own, and the ship then discloses it by name and layer in
# both the preview and the apply. That boundary is deliberate: a committed
# config travels with a clone, so honouring a program named there would let a
# repository you cloned choose what runs on your machine (TRACKER §44).
#
# INSTALL — in a layer you own, never in a committed manifest.config.yaml:
#
#   # ~/.manifest-cli/manifest.config.global.yaml   (or ./manifest.config.local.yaml)
#   docs:
#     release_notes:
#       provider: "command"
#       command: "/absolute/path/to/claude-code-provider.sh"
#
# A committed manifest.config.yaml naming either key is refused, loudly, with
# the key and the layer it came from.
#
# CONTRACT — Manifest calls:   <this script> <request_file> <output_file>
#   request_file  markdown: an Instructions section, release metadata, the
#                 commit subjects, and the changed-file list.
#   output_file   you write a markdown bullet list here, and nothing else.
# Manifest then validates what you wrote: non-bullet preamble is stripped, the
# list is capped at 15 bullets, and assistant boilerplate ("As an AI",
# "Sure, here", ...) is rejected outright. On any failure it falls back to its
# own generator unless docs.release_notes.required is true.
#
# CONSIDER THE ALTERNATIVE FIRST. This runs a HEADLESS agent that sees only the
# request file. If an agent is already driving your ship, it has the session
# context this one lacks — what you asked for, what you rejected, why. For that
# case `docs.handoff` (§78) is the better tool: Manifest pauses before the
# release commit, hands the driver a brief, and verifies the result. No program
# is run, and it works for a human too.
#
set -euo pipefail

request_file="${1:?usage: $0 <request_file> <output_file>}"
output_file="${2:?usage: $0 <request_file> <output_file>}"

# Pick your agent's non-interactive entry point. Each of these reads a prompt
# on stdin and writes the answer to stdout; adjust to whatever you have.
AGENT_CMD="${MANIFEST_EXAMPLE_AGENT_CMD:-claude}"
AGENT_ARGS="${MANIFEST_EXAMPLE_AGENT_ARGS:--p}"

command -v "$AGENT_CMD" >/dev/null 2>&1 || {
    echo "release-notes provider: '$AGENT_CMD' is not on PATH" >&2
    exit 1
}

# The request file already contains the instructions Manifest wants followed;
# pass it through unchanged rather than writing a second, competing prompt.
# shellcheck disable=SC2086
"$AGENT_CMD" $AGENT_ARGS < "$request_file" > "$output_file" || {
    echo "release-notes provider: '$AGENT_CMD' exited non-zero" >&2
    exit 1
}

[ -s "$output_file" ] || {
    echo "release-notes provider: '$AGENT_CMD' produced no output" >&2
    exit 1
}
