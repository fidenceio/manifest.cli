#!/usr/bin/env bats
# bats file_tags=smoke
# Fabricated TAP below exercises the reporter only; actual safety evidence is
# taken from the real suite by run-tests.sh after Bats completes.
load 'helpers/setup'
setup() {
    SCRATCH="$(mk_scratch)"
    mkdir -p "$SCRATCH/tests"
    cp "$TEST_REPO_ROOT/tests/safety-contracts.tsv" "$SCRATCH/tests/"
    while IFS= read -r file; do cp "$TEST_REPO_ROOT/$file" "$SCRATCH/$file"; done < <(
        awk -F '\t' '!/^#/ && NF {print $2; print $4}' "$SCRATCH/tests/safety-contracts.tsv" | sort -u)
    registry="$SCRATCH/tests/safety-contracts.tsv"
    tap="$SCRATCH/results.tap"
    awk -F '\t' '!/^#/ && NF {print $3; print $5}' "$registry" | awk '!seen[$0]++ {print "ok " ++n " " $0}' > "$tap"
}
teardown() { rm -rf "$SCRATCH"; }
check_contracts() { run bash "$TEST_REPO_ROOT/scripts/check-safety-contracts.sh" "$registry" "$SCRATCH" "$@"; }

@test "safety contracts: the live registry references two distinct smoke proofs per contract" {
    run bash "$TEST_REPO_ROOT/scripts/check-safety-contracts.sh" "$TEST_REPO_ROOT/tests/safety-contracts.tsv" "$TEST_REPO_ROOT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"24 contracts"* ]]
    [[ "$output" == *"execution not yet verified"* ]]
}
@test "safety contracts: complete passing TAP satisfies the registered proofs" {
    check_contracts "$tap"
    [ "$status" -eq 0 ]
    [[ "$output" == *"24/24 verified"* ]]
}
@test "safety contracts: removing a required contract cannot shrink the denominator" {
    sed '/^init-origin\t/d' "$registry" > "$registry.tmp"; mv "$registry.tmp" "$registry"
    check_contracts "$tap"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Required safety contract was removed"* ]]
}
@test "safety contracts: renamed missing and non-smoke proofs are refused" {
    sed 's/@test /@renamed /' "$SCRATCH/tests/time.bats" > "$SCRATCH/renamed"
    cp "$SCRATCH/tests/time.bats" "$SCRATCH/original"
    cp "$SCRATCH/renamed" "$SCRATCH/tests/time.bats"
    check_contracts
    [ "$status" -ne 0 ]
    sed '/# bats file_tags=smoke/d' "$SCRATCH/original" > "$SCRATCH/tests/time.bats"
    check_contracts
    [ "$status" -ne 0 ]
    rm "$SCRATCH/tests/time.bats"
    check_contracts
    [ "$status" -ne 0 ]
}
@test "safety contracts: failed skipped absent and duplicate results all fail closed" {
    cp "$tap" "$SCRATCH/original.tap"
    sed '1s/^ok /not ok /' "$SCRATCH/original.tap" > "$tap"
    check_contracts "$tap"
    [ "$status" -ne 0 ]
    sed '1s/$/ # skip unavailable/' "$SCRATCH/original.tap" > "$tap"
    check_contracts "$tap"
    [ "$status" -ne 0 ]
    tail -n +2 "$SCRATCH/original.tap" > "$tap"
    check_contracts "$tap"
    [ "$status" -ne 0 ]
    cat "$SCRATCH/original.tap" "$SCRATCH/original.tap" > "$tap"
    check_contracts "$tap"
    [ "$status" -ne 0 ]
}
@test "safety contracts: a lookalike passing description cannot replace the actual proof" {
    sed '1s/$/ lookalike/' "$tap" > "$tap.tmp"; mv "$tap.tmp" "$tap"
    check_contracts "$tap"
    [ "$status" -ne 0 ]
}
@test "safety contracts: duplicate contracts and reusing the same proof twice are refused" {
    cp "$registry" "$SCRATCH/original.tsv"
    awk -F '\t' '!/^#/ {print; exit}' "$registry" >> "$registry"
    check_contracts
    [ "$status" -ne 0 ]
    awk -F '\t' 'BEGIN {OFS="\t"} /^init-origin\t/ {$4=$2; $5=$3} {print}' "$SCRATCH/original.tsv" > "$registry"
    check_contracts
    [ "$status" -ne 0 ]
}

@test "safety contracts: the runner rejects a green exit that omitted the required proofs" {
    mkdir -p "$SCRATCH/bin"
    printf '#!/bin/sh\nprintf "1..0\\n"\nexit 0\n' > "$SCRATCH/bin/bats"
    chmod +x "$SCRATCH/bin/bats"
    run env PATH="$SCRATCH/bin:$PATH" bash "$TEST_REPO_ROOT/scripts/run-tests.sh" --jobs 1 --no-cache
    [ "$status" -ne 0 ]
    [[ "$output" == *"Safety proof did not pass exactly once without a skip"* ]]
}
