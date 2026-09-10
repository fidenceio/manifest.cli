#!/usr/bin/env bats
# §78 — who is driving this CLI, decided by a named detector with an enumerated
# result and an explicit `none`.
#
# THE HAZARD THIS FILE IS BUILT AROUND. These tests are frequently run BY an
# agent (the suite is developed that way), so the CLI's process really is a
# descendant of `claude`. A test that scrubs the environment and asserts `none`
# would then pass in CI and fail on a maintainer's machine — the ancestry walk
# keeps finding a true ancestor after the environment is emptied. Every
# environment-signal test therefore sets MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0
# to isolate the path under test, and the ancestry path gets its own test that
# builds a chain it controls.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    CENSUS="$TEST_REPO_ROOT/tests/fixtures/driver-census.tsv"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# Run detect_driver in a scrubbed child and echo "verdict|hint|evidence".
# $@ = NAME=VALUE pairs to set.
probe_driver() {
    env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 "$@" \
        bash -c '
            source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
            detect_driver
            printf "%s|%s|%s" "$MANIFEST_CLI_DRIVER" "$MANIFEST_CLI_DRIVER_AGENT_HINT" "$MANIFEST_CLI_DRIVER_EVIDENCE"
        '
}

# --- the census drives the positive controls -------------------------------

@test "the census fixture has at least one measured row" {
    # Without this, every census-driven assertion below would pass vacuously
    # against an emptied file — and "no rows" would read as "all rows pass".
    local rows
    rows="$(grep -cvE '^#|^ASSISTANT' "$CENSUS")"
    [ "$rows" -ge 1 ]
}

@test "every census row's environment produces its recorded verdict" {
    local line assistant env_present expected pair name value
    local -a setenv=()
    local checked=0
    while IFS=$'\t' read -r assistant _host _date _os _ps env_present _ancestry _tty expected _by; do
        case "$assistant" in ''|\#*|ASSISTANT) continue ;; esac
        setenv=()
        # ENV_PRESENT is `;`-separated; NAME=VALUE keeps its value, a bare NAME
        # is set to 1 (the variable's presence is the signal).
        local IFS=';'
        for pair in $env_present; do
            [ -n "$pair" ] || continue
            case "$pair" in
                *=*) name="${pair%%=*}"; value="${pair#*=}" ;;
                *)   name="$pair"; value="1" ;;
            esac
            setenv+=("$name=$value")
        done
        unset IFS
        local got
        got="$(probe_driver "${setenv[@]}")"
        [ "${got%%|*}" = "$expected" ] || {
            echo "census row '$assistant': expected $expected, got ${got%%|*} (evidence ${got##*|})" >&2
            return 1
        }
        checked=$((checked + 1))
    done < "$CENSUS"
    [ "$checked" -ge 1 ]
}

# --- the enumeration, each with its control --------------------------------

@test "CONTROL: a scrubbed environment with no ancestry is 'none'" {
    local got; got="$(probe_driver)"
    [ "${got%%|*}" = "none" ]
}

@test "CLAUDECODE alone is claude-code; CONTROL: absent is none" {
    local got; got="$(probe_driver CLAUDECODE=1)"
    [ "${got%%|*}" = "claude-code" ]
    [[ "$got" == *"env:CLAUDECODE"* ]]

    got="$(probe_driver)"
    [ "${got%%|*}" = "none" ]
}

@test "AI_AGENT alone is other-agent, never a named verdict from free text" {
    local got; got="$(probe_driver AI_AGENT=some-vendor-bot_9)"
    [ "${got%%|*}" = "other-agent" ]
    # The value is attacker-shaped free text: it must not become the verdict.
    [[ "$got" != *"some-vendor-bot"* ]]
}

@test "CI outranks an agent for the verdict but keeps it as the hint" {
    local got; got="$(probe_driver CI=true CLAUDECODE=1)"
    [ "${got%%|*}" = "ci" ]
    local hint; hint="$(printf '%s' "$got" | cut -d'|' -f2)"
    [ "$hint" = "claude-code" ]
}

@test "CONTROL: CI without an agent is ci with no hint" {
    local got; got="$(probe_driver CI=true)"
    [ "${got%%|*}" = "ci" ]
    local hint; hint="$(printf '%s' "$got" | cut -d'|' -f2)"
    [ -z "$hint" ]
}

@test "each CI marker is recognised on its own" {
    local var
    for var in CI GITHUB_ACTIONS GITLAB_CI BUILDKITE CIRCLECI JENKINS_URL TF_BUILD; do
        local got; got="$(probe_driver "$var=1")"
        [ "${got%%|*}" = "ci" ] || {
            echo "$var did not produce a ci verdict: $got" >&2
            return 1
        }
    done
}

# --- the override ----------------------------------------------------------

@test "a valid override beats the environment; CONTROL: without it the env wins" {
    local got; got="$(probe_driver CLAUDECODE=1 MANIFEST_CLI_DRIVER=none)"
    [ "${got%%|*}" = "none" ]
    [[ "$got" == *"override"* ]]

    got="$(probe_driver CLAUDECODE=1)"
    [ "${got%%|*}" = "claude-code" ]
}

@test "an invalid override is ignored, not coerced into a verdict" {
    local got; got="$(probe_driver CLAUDECODE=1 MANIFEST_CLI_DRIVER=bogus)"
    # §6: an unrecognised value is not a value. Detection continues.
    [ "${got%%|*}" = "claude-code" ]
    [[ "$got" != *"override"* ]]
}

# --- ancestry, on a chain the test controls --------------------------------

@test "ancestry: a parent process named 'claude' is detected with the env empty" {
    cp "$(command -v bash)" "$SCRATCH/claude"
    chmod +x "$SCRATCH/claude"
    run env -i PATH="$PATH" HOME="$SCRATCH" "$SCRATCH/claude" -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        detect_driver
        printf "%s|%s" "$MANIFEST_CLI_DRIVER" "$MANIFEST_CLI_DRIVER_EVIDENCE"
    '
    [ "$status" -eq 0 ]
    [[ "$output" == "claude-code|"* ]]
    [[ "$output" == *"ancestry:claude"* ]]
}

@test "CONTROL: an ordinary shell ancestry with the env empty is not an agent" {
    cp "$(command -v bash)" "$SCRATCH/ordinary-shell"
    chmod +x "$SCRATCH/ordinary-shell"
    # One hop is enough to see the renamed parent and nothing beyond it, which
    # keeps the real (possibly agent-driven) chain above out of the answer.
    run env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=1 \
        "$SCRATCH/ordinary-shell" -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        detect_driver
        printf "%s" "$MANIFEST_CLI_DRIVER"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "none" ]
}

# --- shape -----------------------------------------------------------------

@test "detection is idempotent and does not re-fork" {
    run env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 CLAUDECODE=1 bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        detect_driver
        first="$MANIFEST_CLI_DRIVER"
        MANIFEST_CLI_DRIVER="tampered"
        detect_driver          # guarded: must NOT re-detect
        printf "%s,%s" "$first" "$MANIFEST_CLI_DRIVER"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "claude-code,tampered" ]
}

@test "the module does not detect at source time" {
    # detect_os runs at source; this one must not, because it may fork ps.
    run env -i PATH="$PATH" HOME="$SCRATCH" CLAUDECODE=1 bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        printf "[%s]" "${MANIFEST_CLI_DRIVER_DETECTED:-unset}"
    '
    [ "$status" -eq 0 ]
    [ "$output" = "[unset]" ]
}

@test "manifest_driver_is_agent is true for agents and false for ci and none" {
    run env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 CLAUDECODE=1 bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        manifest_driver_is_agent && echo yes || echo no'
    [ "$output" = "yes" ]

    run env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 CI=true CLAUDECODE=1 bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        manifest_driver_is_agent && echo yes || echo no'
    [ "$output" = "no" ]

    run env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        manifest_driver_is_agent && echo yes || echo no'
    [ "$output" = "no" ]
}

@test "the describe line names the verdict and its evidence, never a raw value" {
    run env -i PATH="$PATH" HOME="$SCRATCH" MANIFEST_CLI_DRIVER_ANCESTRY_MAX_HOPS=0 \
        AI_AGENT=vendor-bot_secret_looking_value bash -c '
        source "'"$TEST_REPO_ROOT"'/modules/system/manifest-driver.sh"
        manifest_driver_describe'
    [ "$status" -eq 0 ]
    [[ "$output" == *"other-agent"* ]]
    [[ "$output" == *"env:AI_AGENT"* ]]
    # The line is printed, logged and pasted into issues: it carries variable
    # NAMES, never their contents.
    [[ "$output" != *"secret_looking_value"* ]]
}
