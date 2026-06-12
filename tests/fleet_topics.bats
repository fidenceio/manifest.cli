#!/usr/bin/env bats
# Fleet GitHub topics projection (tracker §9.1).
#
# Contract under test:
#   - topics.from_name absent / empty / null = OFF: silent no-op, zero gh calls
#   - present-but-invalid value fails loud (never silently disables)
#   - derivation: dot-split repo name, mode picks slugs, GitHub-legal normalize
#   - read-then-diff: existing topics are never re-pushed; additive-only
#   - gh missing/unauthenticated = per-run skip notice, rc 0, never fatal

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    load_modules "fleet/manifest-fleet-detect.sh" "fleet/manifest-fleet-topics.sh"
}

teardown() {
    unset MANIFEST_CLI_FLEET_TOPICS_FROM_NAME GH_STUB_LOG GH_STUB_EXIT \
        GH_STUB_AUTH_EXIT GH_STUB_STDOUT GH_STUB_STDERR
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- helpers -----------------------------------------------------------------

write_config() {
    # $1 = extra YAML appended after the fleet block (e.g. the topics block)
    {
        printf 'fleet:\n  name: "test-fleet"\n  versioning: "none"\n'
        if [[ -n "${1:-}" ]]; then printf '%s\n' "$1"; fi
    } > "$SCRATCH/work/manifest.fleet.config.yaml"
}

make_member() {
    # $1 = dir name, $2 = remote url ("" = no remote)
    local dir="$SCRATCH/work/$1"
    mkdir -p "$dir"
    git -C "$dir" init -q
    [[ -n "${2:-}" ]] && git -C "$dir" remote add origin "$2"
}

write_tsv() {
    # one row per "name<TAB>path<TAB>url" argument triple, joined from $@
    : > "$SCRATCH/work/manifest.fleet.tsv"
    local row
    for row in "$@"; do
        printf '%s\n' "$row" >> "$SCRATCH/work/manifest.fleet.tsv"
    done
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

CONFIG="manifest.fleet.config.yaml"

# --- derivation + normalization ----------------------------------------------

@test "derive: inner picks the middle slugs" {
    run _fleet_topics_derive "fidence.service.accounting.avalara" "inner"
    [ "$status" -eq 0 ]
    [ "$output" = "service
accounting" ]
}

@test "derive: inner with two slugs derives nothing (no-op, not an error)" {
    run _fleet_topics_derive "manifest.cli" "inner"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "derive: all-but-first drops only the org slug" {
    run _fleet_topics_derive "fidence.service.accounting.avalara" "all-but-first"
    [ "$output" = "service
accounting
avalara" ]
}

@test "derive: all keeps every slug, normalized and deduplicated" {
    run _fleet_topics_derive "Fidence.SERVICE.Acco_unting.service" "all"
    [ "$output" = "fidence
service
accounting" ]
}

@test "normalize: strips illegal chars, leading hyphens, caps at 50" {
    run _fleet_topics_normalize_slug "--Web+API"
    [ "$output" = "webapi" ]
    local long="abcdefghij-abcdefghij-abcdefghij-abcdefghij-abcdefghij"
    run _fleet_topics_normalize_slug "$long"
    [ "${#output}" -eq 50 ]
}

# --- mode reading: empty/null contract + fail-loud ---------------------------

@test "mode: absent topics key reads as off" {
    write_config ""
    run manifest_fleet_topics_mode "$SCRATCH/work/$CONFIG"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "mode: explicit null and empty string both read as off" {
    write_config 'topics:
  from_name:'
    run manifest_fleet_topics_mode "$SCRATCH/work/$CONFIG"
    [ "$status" -eq 0 ]
    [ -z "$output" ]

    write_config 'topics:
  from_name: ""'
    run manifest_fleet_topics_mode "$SCRATCH/work/$CONFIG"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "mode: valid values pass through" {
    write_config 'topics:
  from_name: inner'
    run manifest_fleet_topics_mode "$SCRATCH/work/$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "inner" ]
}

@test "mode: invalid value fails loud and names the valid set" {
    write_config 'topics:
  from_name: midle'
    run manifest_fleet_topics_mode "$SCRATCH/work/$CONFIG"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid topics.from_name"* ]]
    [[ "$output" == *"inner | all | all-but-first"* ]]
}

# --- run: off-by-default, zero gh calls --------------------------------------

@test "run: unset topics is a silent no-op with zero gh calls" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config ""
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "true"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -s "$GH_STUB_LOG" ]
}

# --- run: preview and apply --------------------------------------------------

@test "run: preview lists the delta and never calls gh repo edit" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Topics (topics.from_name: inner)"* ]]
    [[ "$output" == *"+service"* ]]
    [[ "$output" == *"+accounting"* ]]
    [[ "$output" == *"+fleet-test-fleet"* ]]
    [[ "$output" == *"manifest update fleet -y"* ]]
    ! grep -q "edit" "$GH_STUB_LOG"
}

@test "run: apply pushes only topics GitHub does not already have" {
    gh_stub_install "$SCRATCH/.gh-stub"
    # Repo already carries 'service' and the fleet topic — only 'accounting'
    # is missing and may be pushed.
    export GH_STUB_STDOUT=$'service\nfleet-test-fleet'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 updated"* ]]
    grep -q -e $'--add-topic\taccounting' "$GH_STUB_LOG"
    ! grep -q -e $'--add-topic\tservice' "$GH_STUB_LOG"
    ! grep -q -e $'--add-topic\tfleet-test-fleet' "$GH_STUB_LOG"
}

@test "run: fully up-to-date repo gets zero writes" {
    gh_stub_install "$SCRATCH/.gh-stub"
    export GH_STUB_STDOUT=$'service\naccounting\nfleet-test-fleet'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 up to date"* ]]
    ! grep -q "edit" "$GH_STUB_LOG"
}

@test "run: non-GitHub origin is skipped, never written" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@gitlab.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@gitlab.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 skipped"* ]]
    ! grep -q "edit" "$GH_STUB_LOG"
}

# --- run: degraded gh, never fatal -------------------------------------------

@test "run: gh missing yields a skip notice, rc 0" {
    mkdir -p "$SCRATCH/no-gh"
    write_config ""
    write_tsv $'true\tsvc\t./svc\tservice\ttrue\t\tmain'

    MANIFEST_CLI_FLEET_TOPICS_FROM_NAME=inner PATH="$SCRATCH/no-gh" \
        run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped — 'gh' (GitHub CLI) is not installed"* ]]
}

@test "run: gh unauthenticated yields a skip notice, rc 0, no further calls" {
    gh_stub_install "$SCRATCH/.gh-stub"
    export GH_STUB_AUTH_EXIT=1
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not authenticated"* ]]
    ! grep -q "repo" "$GH_STUB_LOG"
}

# --- wiring: manifest update fleet -------------------------------------------

@test "update fleet: invalid topics.from_name fails loud before any work" {
    write_config 'topics:
  from_name: midle'
    write_tsv $'true\tsvc\t./svc\tservice\tfalse\t\tmain'

    run_manifest update fleet
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid topics.from_name"* ]]
}

@test "update fleet: preview includes the topics block when configured" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run_manifest update fleet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Topics (topics.from_name: inner)"* ]]
    [[ "$output" == *"+service"* ]]
    ! grep -q "edit" "$GH_STUB_LOG"
}

@test "update fleet: no topics config means no topics output at all" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config ""
    write_tsv $'true\tsvc\t./svc\tservice\tfalse\t\tmain'

    run_manifest update fleet
    [ "$status" -eq 0 ]
    [[ "$output" != *"Topics"* ]]
}
