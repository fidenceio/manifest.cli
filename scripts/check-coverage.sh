#!/usr/bin/env bash
# Run inside the coverage container. Validate the runtime denominator as well
# as the measured line count; a rounded headline is never sufficient evidence.
set -euo pipefail

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "Usage: check-coverage.sh REPORT_JSON SOURCE_ROOT [MIN_PERCENT=100]" >&2
    exit 2
fi
report="$1"
root="$(cd "$2" && pwd)"
minimum="${3:-100}"
if [[ ! "$minimum" =~ ^[0-9]+([.][0-9]+)?$ ]] \
    || ! jq -en --arg value "$minimum" '$value | tonumber | . >= 0 and . <= 100' >/dev/null; then
    echo "Coverage threshold must be between 0 and 100." >&2
    exit 2
fi

if ! jq -e '
    def count: if type == "string" then tonumber else . end;
    def valid_count: count | type == "number" and . >= 0 and floor == .;
    (.files | type == "array" and length > 0) and
    (.covered_lines | valid_count) and (.total_lines | valid_count) and
    (.total_lines | count) > 0 and
    all(.files[];
        (.file | type == "string" and length > 0) and
        (.covered_lines | valid_count) and (.total_lines | valid_count) and
        ((.covered_lines | count) <= (.total_lines | count))) and
    (([.files[].file] | length) == ([.files[].file] | unique | length)) and
    (([.files[].covered_lines | count] | add) == (.covered_lines | count)) and
    (([.files[].total_lines | count] | add) == (.total_lines | count))
' "$report" >/dev/null 2>&1; then
    echo "Coverage report is missing, malformed, empty, or internally inconsistent: $report" >&2
    exit 1
fi

expected=()
if [[ ! -d "$root/modules" ]]; then
    echo "Coverage scope input is missing: modules/" >&2
    exit 1
fi
while IFS= read -r path; do expected+=("$path"); done \
    < <(find "$root/modules" -type f -name '*.sh' | sort)
for entry in manifest-cli.sh manifest-cli-wrapper.sh migrate-user-config.sh; do
    if [[ ! -f "$root/scripts/$entry" ]]; then
        echo "Coverage scope input is missing: scripts/$entry" >&2
        exit 1
    fi
    expected+=("$root/scripts/$entry")
done
expected_json="$(printf '%s\n' "${expected[@]}" | jq -Rsc 'split("\n") | map(select(length > 0)) | sort')"
missing="$(jq -r --argjson expected "$expected_json" '$expected - [.files[].file] | .[]' "$report")"
unexpected="$(jq -r --argjson expected "$expected_json" '[.files[].file] - $expected | .[]' "$report")"
if [[ -n "$missing" || -n "$unexpected" ]]; then
    echo "Coverage file inventory does not match the CLI runtime scope." >&2
    [[ -z "$missing" ]] || printf 'Missing runtime files (not measured):\n%s\n' "$missing" >&2
    [[ -z "$unexpected" ]] || printf 'Unexpected files in the denominator:\n%s\n' "$unexpected" >&2
    exit 1
fi

read -r covered total percent < <(jq -r '
    (.covered_lines | tonumber) as $covered |
    (.total_lines | tonumber) as $total |
    [$covered, $total, ($covered * 100 / $total)] | @tsv' "$report")
LC_ALL=C printf 'Runtime coverage: %.2f%% (%s/%s executable lines; %s/%s files). Target: %s%%.\n' \
    "$percent" "$covered" "$total" "${#expected[@]}" "${#expected[@]}" "$minimum"

if [[ -n "${MANIFEST_CLI_COVERAGE_GAPS_FILE:-}" ]]; then
    jq -r '.files | map(. + {uncovered: ((.total_lines|tonumber) - (.covered_lines|tonumber))}) |
        sort_by(-.uncovered, .file)[] | select(.uncovered > 0) |
        [.file, .covered_lines, .total_lines, .uncovered] | @tsv' "$report" > "$MANIFEST_CLI_COVERAGE_GAPS_FILE"
fi
if ! jq -e --arg threshold "$minimum" \
    '(.covered_lines | tonumber) * 100 >= (.total_lines | tonumber) * ($threshold | tonumber)' \
    "$report" >/dev/null; then
    echo "Coverage target not met: $((total - covered)) executable lines remain uncovered." >&2
    exit 1
fi
