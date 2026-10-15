#!/usr/bin/env bash
# Validate named safety proofs and, when supplied, their actual TAP results.
# Metadata alone never establishes a passing safety contract.
set -euo pipefail
[[ $# -ge 2 && $# -le 3 ]] || { echo 'Usage: check-safety-contracts.sh REGISTRY SOURCE_ROOT [TAP_RESULTS]' >&2; exit 2; }
registry="$1" root="$2" tap="${3:-}"
[[ -s "$registry" ]] || { echo 'Safety contract registry is missing or empty.' >&2; exit 1; }
required=(init-preview init-first-ship init-verification init-origin repo-consent config-consent release-check release-check-required commit-preservation release-branch single-flight push-recovery manager-inclusion manager-allowlist fleet-snapshot-ownership repo-revert fleet-revert fleet-revert-partial resume-no-double-bump doc-handoff credential-redaction destructive-target timestamp-provenance coverage-inventory)
declare -A seen=()
count=0
while IFS=$'\t' read -r id control_file control_test challenge_file challenge_test extra; do
    [[ -n "$id" && "$id" != \#* ]] || continue
    if [[ -n "$extra" || -z "$control_test" || -z "$challenge_test" || -n "${seen[$id]:-}" ]]; then
        echo "Malformed or duplicate safety contract: $id" >&2; exit 1
    fi
    seen[$id]=1
    if [[ "$control_file:$control_test" == "$challenge_file:$challenge_test" ]]; then
        echo "Safety contract needs two distinct proofs: $id" >&2; exit 1
    fi
    for side in control challenge; do
        file_var="${side}_file" test_var="${side}_test"
        file="${!file_var}" name="${!test_var}"
        if [[ ! "$file" =~ ^tests/[a-zA-Z0-9_]+[.]bats$ ]] \
            || ! grep -Fxq -- "@test \"$name\" {" "$root/$file" \
            || ! grep -Fxq '# bats file_tags=smoke' "$root/$file"; then
            echo "Missing or non-smoke safety proof: $id ($file: $name)" >&2; exit 1
        fi
        if [[ -n "$tap" ]]; then
            # Match the entire TAP description. A skipped proof, duplicate, or
            # lookalike name must never satisfy the required passing result.
            if ! awk -v expected="$name" '
                /^(not )?ok [0-9]+ / {
                    line=$0; sub(/^(not )?ok [0-9]+ /, "", line)
                    if (line == expected || index(line, expected " # skip") == 1) {
                        found++; if ($0 ~ /^ok / && line == expected) passed++
                    }
                }
                END {exit !(found == 1 && passed == 1)}' "$tap"; then
                echo "Safety proof did not pass exactly once without a skip: $id ($name)" >&2; exit 1
            fi
        fi
    done
    count=$((count + 1))
done < "$registry"
for id in "${required[@]}"; do
    [[ -n "${seen[$id]:-}" ]] || { echo "Required safety contract was removed: $id" >&2; exit 1; }
done
if [[ -n "$tap" ]]; then
    echo "Safety contracts: $count/$count verified (100% of registered contracts; both proofs passed, none skipped)."
else
    echo "Safety contract registry: $count contracts with two live smoke proofs each (execution not yet verified)."
fi
