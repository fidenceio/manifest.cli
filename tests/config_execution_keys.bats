#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# §44 (SEC-002): a cloned repo's COMMITTED config must not choose what runs on
# the shipping machine.
#
# Five keys name a program the CLI executes during a ship — release.gate_command,
# docs.review.command, docs.release_notes.command, and the two provider selectors
# that make the commands reachable. The shell-metacharacter half was closed in
# v55.3.0 (argv, never `bash -c`). The half these tests cover is the one that
# stayed open: the value's ORIGIN. A repo is a thing you clone from someone else,
# and the project layer loads AFTER the user's global layer and overrides it — so
# a user could not defend by configuring safely.
#
# The rule under test is about the LAYER, not the key: the same key is honoured
# from a layer its owner controls and refused from a committed file. Every
# refusal test below is therefore paired with the positive control that proves
# the key still works when it comes from the right place — without those, all of
# this would pass equally against a build that simply broke the feature.

load 'helpers/setup'

setup() {
    load_modules
    # load_modules does not bring in the config loader, and without it every
    # refusal assertion below would pass vacuously against a `load_configuration`
    # that does not exist (status 127 -> every key unset -> "refused"). The
    # positive controls are what exposed that; source it explicitly.
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-execution-policy.sh"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME SCRATCH
    # No global config unless a test writes one.
    export MANIFEST_CLI_GLOBAL_CONFIG="$SCRATCH/home/nonexistent.global.yaml"
    unset MANIFEST_CLI_TRUST_REPO_COMMANDS
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_TRUST_REPO_COMMANDS MANIFEST_CLI_GLOBAL_CONFIG
}

# A repo whose COMMITTED config names programs — the cloned-hostile-repo shape.
mk_repo_with_committed_commands() {
    local root="$1"
    mkdir -p "$root"
    git -C "$root" init -q
    cat > "$root/manifest.config.yaml" <<'YAML'
version:
  separator: "."
release:
  gate_command: "/tmp/attacker-gate.sh"
docs:
  review:
    provider: "command"
    command: "/tmp/attacker-review.sh"
  release_notes:
    provider: "command"
    command: "/tmp/attacker-notes.sh"
YAML
}

# Load the layer chain for $1 in a subshell-free way and report the resolved
# execution keys. Loading is what enforces, so every test drives the real
# load_configuration rather than poking the enforcement helper directly.
load_and_report() {
    load_configuration "$1" true >/dev/null 2>&1
    echo "gate=[${MANIFEST_CLI_RELEASE_GATE_COMMAND:-<unset>}]"
    echo "review=[${MANIFEST_CLI_DOC_REVIEW_COMMAND:-<unset>}]"
    echo "review_provider=[${MANIFEST_CLI_DOC_REVIEW_PROVIDER:-<unset>}]"
    echo "notes=[${MANIFEST_CLI_RELEASE_NOTES_COMMAND:-<unset>}]"
}

# --- the refusal -------------------------------------------------------------

@test "§44: a committed manifest.config.yaml cannot supply any execution key" {
    local repo="$SCRATCH/cloned"
    mk_repo_with_committed_commands "$repo"

    run load_and_report "$repo"
    [ "$status" -eq 0 ]

    # None of the three programs reaches the environment at all. Refusing at
    # load (not at each consumer) is the point: the doc-review provider alone
    # fires twice per ship, from inside commit_changes.
    [[ "$output" == *"gate=[<unset>]"* ]]
    [[ "$output" == *"review=[<unset>]"* ]]
    [[ "$output" == *"notes=[<unset>]"* ]]
    # The provider selector is refused too, so it falls back to the safe default
    # rather than staying on `command` with a refused command behind it.
    [[ "$output" == *"review_provider=[local]"* ]]
}

@test "§44 CONTROL: an ordinary key from the SAME committed file is unaffected" {
    # The most important control in this file. The restriction is on five keys,
    # not on the project layer — a build that refused the whole committed config
    # would pass every refusal test above and be catastrophically wrong.
    local repo="$SCRATCH/cloned"
    mk_repo_with_committed_commands "$repo"

    load_configuration "$repo" true >/dev/null 2>&1
    [ "${MANIFEST_CLI_VERSION_SEPARATOR:-}" = "." ]
}

@test "§44: the refusal is announced, naming the key and the layer" {
    local repo="$SCRATCH/cloned"
    mk_repo_with_committed_commands "$repo"

    run load_configuration "$repo" true
    [ "$status" -eq 0 ]

    # Silence would read as a bug to the user whose committed config stopped
    # taking effect, so the announcement is part of the contract.
    [[ "$output" == *"name a program to execute"* ]]
    [[ "$output" == *"MANIFEST_CLI_RELEASE_GATE_COMMAND"* ]]
    [[ "$output" == *"project-shared"* ]]
    [[ "$output" == *"MANIFEST_CLI_TRUST_REPO_COMMANDS=1"* ]]
}

# --- the positive controls: the same keys, from a layer the user owns --------

@test "§44 CONTROL: a user-owned .local.yaml DOES supply execution keys" {
    local repo="$SCRATCH/mine"
    mkdir -p "$repo"
    git -C "$repo" init -q
    cat > "$repo/manifest.config.local.yaml" <<'YAML'
release:
  gate_command: "/tmp/my-gate.sh"
docs:
  review:
    provider: "command"
    command: "/tmp/my-review.sh"
YAML

    run load_and_report "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate=[/tmp/my-gate.sh]"* ]]
    [[ "$output" == *"review=[/tmp/my-review.sh]"* ]]
    [[ "$output" == *"review_provider=[command]"* ]]
}

@test "§44 CONTROL: the user's global config DOES supply execution keys" {
    local repo="$SCRATCH/plain"
    mkdir -p "$repo"
    git -C "$repo" init -q
    mkdir -p "$SCRATCH/home/.manifest-cli"
    MANIFEST_CLI_GLOBAL_CONFIG="$SCRATCH/home/.manifest-cli/manifest.config.global.yaml"
    export MANIFEST_CLI_GLOBAL_CONFIG
    cat > "$MANIFEST_CLI_GLOBAL_CONFIG" <<'YAML'
release:
  gate_command: "/tmp/global-gate.sh"
YAML

    run load_and_report "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate=[/tmp/global-gate.sh]"* ]]
}

@test "§44: a committed repo value cannot override the user's global value" {
    # The specific escalation that made this worse than an accepted boundary:
    # the project layer loads after global and wins, so before this fix a safe
    # global gate_command LOST to a cloned repo's committed one.
    local repo="$SCRATCH/cloned"
    mk_repo_with_committed_commands "$repo"
    mkdir -p "$SCRATCH/home/.manifest-cli"
    MANIFEST_CLI_GLOBAL_CONFIG="$SCRATCH/home/.manifest-cli/manifest.config.global.yaml"
    export MANIFEST_CLI_GLOBAL_CONFIG
    cat > "$MANIFEST_CLI_GLOBAL_CONFIG" <<'YAML'
release:
  gate_command: "/tmp/global-gate.sh"
YAML

    run load_and_report "$repo"
    [ "$status" -eq 0 ]
    # The user's own value survives; the repo's is refused rather than winning.
    [[ "$output" == *"gate=[/tmp/global-gate.sh]"* ]]
    refute grep -q "attacker-gate" <<<"$output"
}

# --- the escape hatch --------------------------------------------------------

@test "§44: MANIFEST_CLI_TRUST_REPO_COMMANDS=1 restores the committed value" {
    local repo="$SCRATCH/cloned"
    mk_repo_with_committed_commands "$repo"
    export MANIFEST_CLI_TRUST_REPO_COMMANDS=1

    run load_and_report "$repo"
    [ "$status" -eq 0 ]
    [[ "$output" == *"gate=[/tmp/attacker-gate.sh]"* ]]
    [[ "$output" == *"review=[/tmp/attacker-review.sh]"* ]]
}

@test "§44: trust cannot be granted BY the committed file it would trust" {
    # The escape hatch is an environment variable on purpose. If the repo's own
    # config could set it, the restriction would be self-defeating — so this
    # asserts the key is not YAML-mappable at all.
    refute grep -q "TRUST_REPO_COMMANDS" "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh.map" 2>/dev/null
    # The real assertion: no YAML key maps to it anywhere in the loader's table.
    refute grep -qE '\]="MANIFEST_CLI_TRUST_REPO_COMMANDS"' "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"

    # Positive control: the table DOES map other keys, so the refutation above
    # is about this key and not about the pattern never matching anything.
    grep -qE '\]="MANIFEST_CLI_RELEASE_GATE_COMMAND"' "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
}

# --- disclosure --------------------------------------------------------------

@test "§44: disclosure names each reachable program and the layer that supplied it" {
    local repo="$SCRATCH/mine"
    mkdir -p "$repo"
    git -C "$repo" init -q
    cat > "$repo/manifest.config.local.yaml" <<'YAML'
docs:
  review:
    provider: "command"
    command: "/tmp/my-review.sh"
YAML
    load_configuration "$repo" true >/dev/null 2>&1

    run manifest_execution_preview_header "manifest ship repo patch"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Programs this run may execute"* ]]
    [[ "$output" == *"/tmp/my-review.sh"* ]]
    [[ "$output" == *"project-local layer"* ]]
}

@test "§44: disclosure excludes a command whose provider does not select it" {
    # Configured but unreachable. Disclosing it would over-report, which erodes
    # the disclosure exactly as much as under-reporting does.
    local repo="$SCRATCH/mine"
    mkdir -p "$repo"
    git -C "$repo" init -q
    cat > "$repo/manifest.config.local.yaml" <<'YAML'
docs:
  release_notes:
    command: "/tmp/unreachable-notes.sh"
YAML
    load_configuration "$repo" true >/dev/null 2>&1

    run manifest_execution_preview_header "manifest ship repo patch"
    [ "$status" -eq 0 ]
    refute grep -q "unreachable-notes" <<<"$output"

    # Positive control: the same helper DOES report a reachable program, so the
    # absence above is the pairing rule and not a disclosure that never emits.
    export MANIFEST_CLI_RELEASE_NOTES_PROVIDER="command"
    run manifest_execution_preview_header "manifest ship repo patch"
    [[ "$output" == *"unreachable-notes"* ]]
}

@test "§44: a preview with no config-named program discloses nothing" {
    local repo="$SCRATCH/plain"
    mkdir -p "$repo"
    git -C "$repo" init -q
    load_configuration "$repo" true >/dev/null 2>&1

    run manifest_execution_preview_header "manifest ship repo patch"
    [ "$status" -eq 0 ]
    # No noise on the overwhelmingly common path — a disclosure that prints on
    # every run is one users learn to skip.
    refute grep -q "Programs this run may execute" <<<"$output"
}
