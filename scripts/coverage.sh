#!/usr/bin/env bash
# Measured line coverage for the bats suite via kcov, run in a disposable
# container (tests/containers/coverage.Dockerfile) so kcov never needs to be
# installed on the host. Reports coverage of modules/ + scripts/ only — test
# code itself is excluded from the metric.
#
# Usage:
#   ./scripts/coverage.sh                      # full suite (SLOW: kcov's bash
#                                              #   tracer multiplies runtime)
#   ./scripts/coverage.sh tests/version.bats   # one or more specific files
#
# Output: coverage/ (gitignored) — HTML report at coverage/index.html, merged
# machine-readable summary printed at the end. Advisory only: no gate consumes
# this number; the release gate remains pass/fail on the suite itself.
#
# Metric caveat: kcov counts lines only in files the run actually sourced — a
# module no test ever loads contributes nothing to the denominator, so the
# percentage overstates coverage of the full module surface. Treat the HTML
# per-file view (which files appear at all, and their line hits) as the real
# signal, not the single headline number.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOCKERFILE="$REPO_ROOT/tests/containers/coverage.Dockerfile"

_manifest_coverage_image_hash() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$DOCKERFILE" | awk '{print substr($1,1,12)}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$DOCKERFILE" | awk '{print substr($1,1,12)}'
    else
        echo "latest"
    fi
}

IMAGE_BASE="${MANIFEST_CLI_COVERAGE_IMAGE:-manifest-cli-coverage}"
IMAGE_TAG="${IMAGE_BASE}:$(_manifest_coverage_image_hash)"

if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1 || [[ "${MANIFEST_CLI_COVERAGE_IMAGE_REBUILD:-false}" == "true" ]]; then
    docker build -q -f "$DOCKERFILE" -t "$IMAGE_TAG" "$REPO_ROOT" >/dev/null
fi

TARGETS=("$@")
if [[ ${#TARGETS[@]} -eq 0 ]]; then
    TARGETS=(tests/)
    echo "coverage: full suite under kcov — expect a multiple of the normal runtime." >&2
fi

rm -rf "$REPO_ROOT/coverage"
mkdir -p "$REPO_ROOT/coverage"

# Serial bats (no --jobs) keeps kcov's per-process traces race-free; kcov
# merges every traced bash descendant into coverage/kcov-merged. Same
# safe.directory + bind-mount conventions as scripts/run-tests-container.sh.
docker run --rm \
    -v "$REPO_ROOT:/work" \
    -w /work \
    "$IMAGE_TAG" \
    kcov \
        --include-path=/work/modules,/work/scripts/manifest-cli.sh,/work/scripts/manifest-cli-wrapper.sh,/work/scripts/migrate-user-config.sh \
        --exclude-pattern=/work/tests/,/work/coverage/ \
        /work/coverage \
        bats "${TARGETS[@]}"

# kcov leaves per-run dirs plus a kcov-merged rollup; surface the headline.
MERGED_JSON="$REPO_ROOT/coverage/kcov-merged/coverage.json"
[[ -f "$MERGED_JSON" ]] || MERGED_JSON="$(find "$REPO_ROOT/coverage" -name coverage.json | head -1)"
if [[ -n "$MERGED_JSON" && -f "$MERGED_JSON" ]]; then
    echo ""
    echo "Coverage summary ($MERGED_JSON):"
    jq -r '"  covered: \(.percent_covered)% (\(.covered_lines)/\(.total_lines) lines)"' "$MERGED_JSON" 2>/dev/null \
        || grep -o '"percent_covered": *"[^"]*"' "$MERGED_JSON" | head -1
    echo "  HTML report: coverage/index.html"
else
    echo "coverage: no coverage.json produced — inspect coverage/ output." >&2
    exit 1
fi
