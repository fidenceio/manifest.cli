#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "pr/manifest-pr-native.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset _MANIFEST_GH_VALIDATED_AT MANIFEST_CLI_GH_VALIDATION_TTL
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT MANIFEST_CLI_GH_STUB_AUTH_EXIT MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR
}

@test "pr create preview does not require gh auth or repo detection" {
    gh_stub_install
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=99
    export MANIFEST_CLI_GH_STUB_EXIT=99
    cd "$SCRATCH"

    run manifest_pr_create --draft --base main

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Preview - no changes written: manifest pr create"
    echo "$output" | grep -q "Would run: gh pr create --draft --fill --base main"
    echo "$output" | grep -q "manifest pr create --draft --base main -y"
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
}

@test "pr create -y requires gh and invokes the exact create command" {
    gh_stub_install
    cd "$SCRATCH"
    git init -q

    run manifest_pr_create -y --draft --base main

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Applying because -y/--yes was provided."
    grep -q $'\tauth\tstatus' "$MANIFEST_CLI_GH_STUB_LOG"
    grep -q $'\trepo\tview\t--json\tname' "$MANIFEST_CLI_GH_STUB_LOG"
    grep -q $'\tpr\tcreate\t--draft\t--fill\t--base\tmain' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "pr ready merge and update previews do not call gh" {
    gh_stub_install
    cd "$SCRATCH"

    run manifest_pr_ready 123
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Would run: gh pr ready 123"
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]

    run manifest_pr_merge 123 --auto
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Would run: gh pr merge 123 --auto --squash"
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]

    run manifest_pr_update 123 --rebase
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Would run: gh pr update-branch 123 --rebase"
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
}

@test "fleet PR mutating dispatch previews before loading cloud implementation" {
    load_modules "core/manifest-core.sh"
    manifest_fleet_pr_dispatch() {
        echo "should-not-call" >> "$SCRATCH/fleet_calls.log"
        return 77
    }

    run _manifest_pr_fleet_dispatch create --method squash

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Would run fleet PR operation: create --method squash"
    echo "$output" | grep -q "manifest pr fleet create --method squash -y"
    [ ! -f "$SCRATCH/fleet_calls.log" ]
}

@test "fleet PR dispatch: bare invocation keeps the implicit queue default" {
    load_modules "core/manifest-core.sh"

    run _manifest_pr_fleet_dispatch

    [ "$status" -eq 0 ]
    [[ "$output" == *"Default fleet PR action: queue"* ]]
    [[ "$output" == *"Would run fleet PR operation: queue"* ]]
}

@test "fleet PR dispatch: option-only invocation still routes to the queue default" {
    load_modules "core/manifest-core.sh"

    run _manifest_pr_fleet_dispatch --dry-run

    [ "$status" -eq 0 ]
    [[ "$output" == *"Default fleet PR action: queue"* ]]
    [[ "$output" == *"Would run fleet PR operation: queue"* ]]
}

@test "fleet PR dispatch: unknown subcommand errors, names the token, calls nothing" {
    # UX-007: `manifest pr fleet quue` used to silently mean `queue`. The
    # rejection must fire before manifest_execution_parse, any gh call, and
    # the fleet PR module.
    load_modules "core/manifest-core.sh"
    gh_stub_install
    manifest_fleet_pr_dispatch() {
        echo "should-not-call" >> "$SCRATCH/fleet_calls.log"
        return 77
    }

    run _manifest_pr_fleet_dispatch quue

    [ "$status" -ne 0 ]
    [[ "$output" == *"quue"* ]]
    [[ "$output" == *"Valid subcommands: queue, create, status, checks, ready, help"* ]]
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
    [ ! -f "$SCRATCH/fleet_calls.log" ]
}

@test "top-level PR help advertises apply and preview flags for mutating commands" {
    run manifest_pr_help

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "manifest pr create \\[-y|--yes\\] \\[--dry-run\\]"
    echo "$output" | grep -q "manifest pr ready \\[-y|--yes\\] \\[--dry-run\\]"
    echo "$output" | grep -q "manifest pr merge \\[-y|--yes\\] \\[--dry-run\\]"
    echo "$output" | grep -q "manifest pr update \\[-y|--yes\\] \\[--dry-run\\]"
}
