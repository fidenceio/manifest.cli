#!/usr/bin/env bash
# Manifest CLI bootstrap — download, VERIFY, then run the installer.
#
# This replaces the unsafe `curl … | bash` pattern, where remote code executes
# before it is ever verified. Here, the release tarball is downloaded, its
# sha256 is checked against an independently published checksum (or a pin you
# supply), and only a verified tree is executed. Nothing runs until the bytes
# are proven.
#
# Usage (download to disk, read it, then run):
#   curl -fsSLO https://raw.githubusercontent.com/fidenceio/manifest.cli/main/bootstrap.sh
#   # inspect bootstrap.sh, then:
#   bash bootstrap.sh                       # installs the latest published tag
#   MANIFEST_CLI_INSTALL_VERSION=v55.2.1 bash bootstrap.sh   # pin an exact version
#   MANIFEST_CLI_INSTALL_SHA256=<digest> MANIFEST_CLI_INSTALL_VERSION=v55.2.1 bash bootstrap.sh  # strict pin
#
# Environment:
#   MANIFEST_CLI_INSTALL_VERSION   release tag to install (default: latest published tag)
#   MANIFEST_CLI_INSTALL_SHA256    expected sha256 of the source tarball — strict pin. When
#                      set, the download must match it exactly or the install
#                      aborts. When unset, the checksum published in the tap
#                      formula for the resolved tag is used as the expected value.
#   MANIFEST_CLI_INSTALL_ARGS  extra args passed through to install-cli.sh.

set -euo pipefail

REPO="fidenceio/manifest.cli"
TAP_RAW="https://raw.githubusercontent.com/fidenceio/homebrew-tap/main/Formula/manifest.rb"

err() { printf '❌ %s\n' "$*" >&2; }
info() { printf '➜  %s\n' "$*"; }

require() {
    command -v "$1" >/dev/null 2>&1 || { err "Required tool not found: $1"; exit 1; }
}
require curl
require tar

# Resolve the sha256 tool the way the rest of the CLI does (macOS shasum,
# Linux/alpine sha256sum).
sha_cmd=""
if command -v shasum >/dev/null 2>&1; then
    sha_cmd="shasum -a 256"
elif command -v sha256sum >/dev/null 2>&1; then
    sha_cmd="sha256sum"
else
    err "No sha256 tool available (need shasum or sha256sum)."
    exit 1
fi

# Resolve the version: an explicit pin, or the latest published GitHub release
# tag. Resolving via the API (not the mutable archive of HEAD) means the install
# is reproducible and the checksum is well-defined.
version="${MANIFEST_CLI_INSTALL_VERSION:-}"
if [ -z "$version" ]; then
    info "Resolving the latest published release tag..."
    version="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
        | sed -n -E 's/.*"tag_name":[[:space:]]*"([^"]+)".*/\1/p' | head -n1)"
    if [ -z "$version" ]; then
        err "Could not resolve the latest release tag. Set MANIFEST_CLI_INSTALL_VERSION=<tag> explicitly."
        exit 1
    fi
fi
info "Installing Manifest CLI ${version}"

tarball_url="https://github.com/${REPO}/archive/refs/tags/${version}.tar.gz"

# Determine the EXPECTED checksum before downloading the payload to run.
expected_sha="${MANIFEST_CLI_INSTALL_SHA256:-}"
if [ -n "$expected_sha" ]; then
    info "Using pinned sha256 from MANIFEST_CLI_INSTALL_SHA256."
else
    info "Fetching the published checksum from the Homebrew tap formula..."
    formula="$(curl -fsSL "$TAP_RAW" 2>/dev/null || true)"
    # Only trust the published checksum if the formula's url matches the tag we
    # are about to download — otherwise the tap points at a different release and
    # its sha would never match (fail closed instead of installing unverified).
    if printf '%s' "$formula" | grep -qF "archive/refs/tags/${version}.tar.gz"; then
        expected_sha="$(printf '%s' "$formula" \
            | sed -n -E 's/^[[:space:]]*sha256 "([a-f0-9]+)".*/\1/p' | head -n1)"
    fi
    if [ -z "$expected_sha" ]; then
        err "No published checksum found for ${version}."
        err "Pin it explicitly:  MANIFEST_CLI_INSTALL_SHA256=<digest> MANIFEST_CLI_INSTALL_VERSION=${version} bash bootstrap.sh"
        exit 1
    fi
fi

if ! [[ "$expected_sha" =~ ^[a-f0-9]{64}$ ]]; then
    err "Expected sha256 is not a well-formed digest: '${expected_sha}'"
    exit 1
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/manifest-bootstrap.XXXXXXXX")"
trap 'rm -rf "$workdir"' EXIT

info "Downloading ${tarball_url}"
if ! curl -fsSL "$tarball_url" -o "$workdir/src.tar.gz"; then
    err "Download failed: ${tarball_url}"
    exit 1
fi

actual_sha="$($sha_cmd "$workdir/src.tar.gz" | cut -d' ' -f1)"
if [ "$actual_sha" != "$expected_sha" ]; then
    err "Checksum mismatch — refusing to run unverified code."
    err "  expected: ${expected_sha}"
    err "  actual:   ${actual_sha}"
    exit 1
fi
info "Checksum verified (${actual_sha})."

tar -xzf "$workdir/src.tar.gz" -C "$workdir"
src_dir="$(find "$workdir" -maxdepth 1 -type d -name 'manifest.cli-*' | head -n1)"
if [ -z "$src_dir" ] || [ ! -x "$src_dir/install-cli.sh" ]; then
    err "Verified tree does not contain an executable install-cli.sh."
    exit 1
fi

info "Running the verified installer from ${src_dir}"
# shellcheck disable=SC2086
exec bash "$src_dir/install-cli.sh" --manual ${MANIFEST_CLI_INSTALL_ARGS:-}
