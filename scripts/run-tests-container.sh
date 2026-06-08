#!/usr/bin/env bash
# Run the bats suite in a disposable container so test dependencies never need
# to be installed on the host.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/tests/containers/run-tests.Dockerfile"

_manifest_test_image_hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$DOCKERFILE" | awk '{print substr($1,1,12)}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$DOCKERFILE" | awk '{print substr($1,1,12)}'
    else
        echo "latest"
    fi
}

IMAGE_BASE="${MANIFEST_CLI_TEST_IMAGE:-manifest-cli-tests}"
IMAGE_TAG="${IMAGE_BASE}:$(_manifest_test_image_hash)"

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1 || [[ "${MANIFEST_CLI_TEST_IMAGE_REBUILD:-false}" == "true" ]]; then
    docker build -q -f "$DOCKERFILE" -t "$IMAGE_TAG" "$REPO_ROOT" >/dev/null
fi

if [[ "${1:-}" == "--print-image" ]]; then
    echo "$IMAGE_TAG"
    exit 0
fi

ENV_ARGS=""
for var in \
    MANIFEST_CLI_TEST_CHANGED_PATHS \
    MANIFEST_CLI_TEST_SKIP_UNCHANGED_WITHIN \
    MANIFEST_CLI_TEST_CACHE_DIR; do
    if [[ "${!var+x}" = "x" ]]; then
        ENV_ARGS="$ENV_ARGS -e $var"
    fi
done

# The repo is bind-mounted at /work but owned by the host user, while the
# container runs as root. git 2.35.2+ rejects that mismatch as "dubious
# ownership", so every repo-scoped command (and any test that shells out to git
# in the mount) fails inside the container. Mark the mount safe at SYSTEM scope:
# the suite overrides $HOME per test for sandbox isolation, so a --global entry
# (keyed to $HOME/.gitconfig) is never read — only --system (/etc/gitconfig),
# which git reads regardless of $HOME, survives. Harmless in a disposable
# container; the host's git config is untouched. Test dependencies are baked
# into tests/containers/run-tests.Dockerfile and keyed by Dockerfile hash, so
# repeated local and CI runs do not pay apk install cost on every invocation.
docker run --rm \
    $ENV_ARGS \
    -v "$REPO_ROOT:/work" \
    -w /work \
    "$IMAGE_TAG" \
    bash scripts/run-tests.sh "$@"
