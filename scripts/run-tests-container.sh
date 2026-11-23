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

# Expected skips. A skipped test reports as a TAP pass, so coverage can shrink
# without the gate noticing — a lost `yq` or a probe that stops matching reads
# exactly like a green run. This image is the one environment whose tooling we
# control, so every test that may skip here is named, with its reason and
# where it runs instead, in tests/containers/expected-skips.tsv. A skip that
# is not on that list, or carries another reason, fails the leg.
#
# This replaced a count on 2026-11-22 (MANIFEST_CLI_TEST_MAX_SKIPS, raised
# 6 -> 7 -> 10 -> 11 as tests arrived; a twelfth skip was what prompted the
# change, and 12 was never committed). A count could
# not tell which tests it was counting: one expected skip stopping while a
# different test started skipping left the number unchanged, and at --jobs 1,
# where the SIGINT test runs instead of skipping, it had one skip of slack a
# real loss could hide in (TRACKER §115). Its last overage sat unread for a
# day behind a failing test. The reasons that lived in this comment are now
# the third column of the list, one per test.
#
# The path is relative to the repository, which is /work in the container. A
# caller may still set MANIFEST_CLI_TEST_MAX_SKIPS as well; it is passed on.
MANIFEST_CLI_TEST_EXPECTED_SKIPS="${MANIFEST_CLI_TEST_EXPECTED_SKIPS:-tests/containers/expected-skips.tsv}"
export MANIFEST_CLI_TEST_EXPECTED_SKIPS
ENV_ARGS="$ENV_ARGS -e MANIFEST_CLI_TEST_EXPECTED_SKIPS"
if [[ "${MANIFEST_CLI_TEST_MAX_SKIPS+x}" = "x" ]]; then
    ENV_ARGS="$ENV_ARGS -e MANIFEST_CLI_TEST_MAX_SKIPS"
fi

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
