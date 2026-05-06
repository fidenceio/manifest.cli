#!/usr/bin/env bash
# Run the bats suite in a disposable container so test dependencies never need
# to be installed on the host.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

docker run --rm \
    -v "$REPO_ROOT:/work" \
    -w /work \
    alpine:3.20 \
    sh -lc 'apk add --no-cache bash git bats yq coreutils >/dev/null && bash scripts/run-tests.sh "$@"' \
    sh "$@"
