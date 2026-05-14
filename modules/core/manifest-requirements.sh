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
