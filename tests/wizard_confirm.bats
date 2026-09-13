#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Call the helper with stable test values; the destination path is the only
# thing we care about for visual verification.
_call_review() {
    _manifest_config_review_and_confirm \
        "$SCRATCH/manifest.config.local.yaml" \
        "demo-project" "demo description" "demo-org" \
        "main" "feature/" "hotfix/" "release/" "bugfix/" \
        "https://t1" "https://t2" "https://t3" "" \
        5 3 true UTC \
        docs docs/zArchive 20 \
        true 30 \
        solo true
}

@test "review-and-confirm: prints all section headings and destination" {
    # Auto-confirm so the function returns 0 without consuming stdin.
    MANIFEST_CLI_AUTO_CONFIRM=1 run _call_review
    [ "$status" -eq 0 ]
    grep -qFx "Review your settings" <<<"$output"
    grep -qFx "====================" <<<"$output"
    grep -qF "Destination: $SCRATCH/manifest.config.local.yaml" <<<"$output"
    grep -qFx "Project:" <<<"$output"
    grep -qFx "Git:" <<<"$output"
    grep -qFx "Time:" <<<"$output"
    grep -qFx "Docs / automation / PR:" <<<"$output"
    # Some of the actual values, to prove they're the ones being shown.
    grep -q "demo-project" <<<"$output"
    grep -q "main" <<<"$output"
    grep -q "https://t1" <<<"$output"
}

@test "review-and-confirm: returns 0 without prompting when MANIFEST_CLI_AUTO_CONFIRM=1" {
    # Don't pipe any input — the auto-confirm path must not call read.
    MANIFEST_CLI_AUTO_CONFIRM=1 run _call_review
    [ "$status" -eq 0 ]
    grep -q "MANIFEST_CLI_AUTO_CONFIRM=1" <<<"$output"
}

@test "review-and-confirm: returns 0 on 'y' answer" {
    run bash -c "
        source '$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh'
        source '$TEST_REPO_ROOT/modules/core/manifest-config.sh'
        echo y | _manifest_config_review_and_confirm \
            '$SCRATCH/cfg.yaml' \
            n d o b f h r bf \
            t1 t2 t3 t4 \
            5 3 true UTC \
            docs arch 20 \
            true 30 \
            solo true
    "
    [ "$status" -eq 0 ]
}

@test "review-and-confirm: returns 1 on 'n' answer" {
    run bash -c "
        source '$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh'
        source '$TEST_REPO_ROOT/modules/core/manifest-config.sh'
        echo n | _manifest_config_review_and_confirm \
            '$SCRATCH/cfg.yaml' \
            n d o b f h r bf \
            t1 t2 t3 t4 \
            5 3 true UTC \
            docs arch 20 \
            true 30 \
            solo true
    "
    [ "$status" -eq 1 ]
}

@test "review-and-confirm: empty answer (just Enter) is treated as 'no'" {
    run bash -c "
        source '$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh'
        source '$TEST_REPO_ROOT/modules/core/manifest-config.sh'
        printf '\n' | _manifest_config_review_and_confirm \
            '$SCRATCH/cfg.yaml' \
            n d o b f h r bf \
            t1 t2 t3 t4 \
            5 3 true UTC \
            docs arch 20 \
            true 30 \
            solo true
    "
    [ "$status" -eq 1 ]
}
