#!/usr/bin/env bash
# Example release-notes provider for Manifest CLI.
#
# Manifest invokes this script as:
#
#     example-provider.sh REQUEST_FILE OUTPUT_FILE
#
# REQUEST_FILE is a markdown file Manifest writes for you. It contains:
#   - `## Instructions` — the prompt Manifest wants the LLM to follow
#   - `## Metadata`     — version, release_type, date, project
#   - `## Commit subjects` — cleaned, deduplicated commit subjects
#   - `## Changed files`   — paths affected by this release
#
# Your job is to send the entire REQUEST_FILE to whatever LLM you use
# (Claude, GPT, a local model, whatever) and write the LLM's response
# back to OUTPUT_FILE. Manifest validates the response — bullets only,
# no preamble, max 15 bullets — before splicing it into CHANGELOG.md.
#
# Manifest owns the prompt and the output schema. Your provider is just
# the network/transport layer. Don't add wrapper text, don't reformat,
# don't call out a specific model in the output. Pass the request in,
# write the bullets out.
#
# Configure with:
#
#     # ~/.manifest.config.yaml or project-local manifest.config.yaml
#     docs:
#       release_notes:
#         provider: command
#         command: /absolute/path/to/example-provider.sh
#         required: false        # set true to abort ship on provider failure

set -euo pipefail

request_file="${1:?usage: $0 REQUEST_FILE OUTPUT_FILE}"
output_file="${2:?usage: $0 REQUEST_FILE OUTPUT_FILE}"

# ---- Replace this block with a real LLM call ------------------------------
#
# Example shape (pseudocode):
#
#     curl -sS https://api.example.com/v1/messages \
#         -H "Authorization: Bearer ${YOUR_API_KEY}" \
#         -H "Content-Type: application/json" \
#         -d "$(jq -Rs --arg model 'your-model' '{model:$model, prompt:.}' \
#             < "$request_file")" \
#         | jq -r '.completion' \
#         > "$output_file"
#
# Notes:
#   - Send the FULL request file as the prompt; Manifest controls phrasing.
#   - Write the model's text response verbatim to $output_file. Don't strip
#     whitespace, don't add headings, don't add commentary. Manifest's
#     validation handles preamble/trailing-prose cleanup.
#   - Exit non-zero on transport errors (network, auth, rate-limit). With
#     `required: false`, Manifest falls back to its local generator and
#     warns; with `required: true`, the ship aborts.
#
# This stub writes a fixed placeholder so the contract is testable end-to-end
# without an API key.
{
    printf '%s\n' '- Replace example-provider.sh with a real LLM call'
    printf '%s\n' '- See header comment for the request/output contract'
} > "$output_file"
