#!/usr/bin/env bash
# Run the bats suite in a disposable container so test dependencies never need
# to be installed on the host.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The repo is bind-mounted at /work but owned by the host user, while the
# container runs as root. git 2.35.2+ rejects that mismatch as "dubious
# ownership", so every repo-scoped command (and any test that shells out to git
# in the mount) fails inside the container. Mark the mount safe before the suite
# runs. Harmless in a disposable container; the host's git config is untouched.
docker run --rm \
    -v "$REPO_ROOT:/work" \
    -w /work \
    alpine:3.20 \
    sh -lc 'apk add --no-cache bash git bats parallel yq coreutils >/dev/null && git config --global --add safe.directory "*" && bash scripts/run-tests.sh "$@"' \
    sh "$@"
