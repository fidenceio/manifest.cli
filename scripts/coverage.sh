#!/usr/bin/env bash
# Container-only executable-line measurement. A zero-hit static inventory keeps
# never-loaded runtime files in the denominator. The safety gate is separate.
# Usage: ./scripts/coverage.sh [test files...]
# MIN_PERCENT defaults to 0 (measurement); set MANIFEST_CLI_COVERAGE_MIN_PERCENT
# explicitly to enforce a line target. check-coverage.sh itself defaults to 100.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/tests/containers/coverage.Dockerfile"
_manifest_coverage_image_hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$DOCKERFILE" | awk '{print substr($1,1,12)}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$DOCKERFILE" | awk '{print substr($1,1,12)}'
    else
        echo latest
    fi
}
IMAGE_TAG="${MANIFEST_CLI_COVERAGE_IMAGE:-manifest-cli-coverage}:$(_manifest_coverage_image_hash)"
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1 || [[ "${MANIFEST_CLI_COVERAGE_IMAGE_REBUILD:-false}" == true ]]; then
    docker build -q -f "$DOCKERFILE" -t "$IMAGE_TAG" "$REPO_ROOT" >/dev/null
fi
if [[ $# -eq 0 ]]; then
    echo 'coverage: full suite under kcov; this takes longer than the normal test run.' >&2
fi
rm -rf "$REPO_ROOT/coverage"
mkdir -p "$REPO_ROOT/coverage"
# Tests may write only their disposable fixtures and reports. In particular, a
# fixture bug must never bump the checkout's VERSION or change its Git index.
docker run --rm -i \
    -e MANIFEST_CLI_COVERAGE_MIN_PERCENT="${MANIFEST_CLI_COVERAGE_MIN_PERCENT:-0}" \
    -e MANIFEST_CLI_TEST_MAX_SKIPS=7 \
    -v "$REPO_ROOT:/work:ro" -v "$REPO_ROOT/coverage:/work/coverage" -w /work \
    "$IMAGE_TAG" bash -s -- "$@" <<'CONTAINER'
set -euo pipefail
scope=/work/modules,/work/scripts/manifest-cli.sh,/work/scripts/manifest-cli-wrapper.sh,/work/scripts/migrate-user-config.sh
printf '#!/bin/bash\n:\n' > /tmp/manifest-coverage-inventory.sh
kcov --bash-dont-parse-binary-dir \
    --bash-parse-files-in-dir=/work/modules,/work/scripts \
    --include-path="$scope" --output-interval=0 \
    /work/coverage/inventory /tmp/manifest-coverage-inventory.sh
# Keep the suite's status while still writing the report after a red run.
# Running through the normal runner also enforces its skip and safety contracts.
# kcov's Bash tracer does not drain the top-level stdout pipe while tracing.
# A full TAP stream exceeds the pipe buffer and deadlocks, even though small
# focused runs pass. Redirect in the traced wrapper BEFORE starting the runner.
cat > /tmp/manifest-coverage-suite.sh <<'SUITE'
#!/bin/bash
exec /work/scripts/run-tests.sh --jobs 1 --no-cache "$@" > /work/coverage/tests.tap
SUITE
test_status=0
kcov --bash-dont-parse-binary-dir --include-path="$scope" \
    --exclude-pattern=/work/tests/,/work/coverage/ --output-interval=0 \
    /work/coverage/traces /tmp/manifest-coverage-suite.sh "$@" || test_status=$?
cat /work/coverage/tests.tap
kcov --merge /work/coverage/report /work/coverage/traces /work/coverage/inventory
report=/work/coverage/report/kcov-merged/coverage.json
check_status=0
MANIFEST_CLI_COVERAGE_GAPS_FILE=/work/coverage/uncovered-lines.tsv \
    bash scripts/check-coverage.sh "$report" /work "$MANIFEST_CLI_COVERAGE_MIN_PERCENT" || check_status=$?
printf 'Test run exit: %s. Coverage check exit: %s.\n' "$test_status" "$check_status"
echo 'HTML report: coverage/report/index.html; gaps: coverage/uncovered-lines.tsv'
[[ "$test_status" -eq 0 ]] || exit "$test_status"
exit "$check_status"
CONTAINER
