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
    # manifest-fleet.sh self-sources detect + topics (sentinel-guarded) and
    # carries _fleet_ship_topics_pass, the post-ship quiet hook under test.
    load_modules "fleet/manifest-fleet-detect.sh" "fleet/manifest-fleet-topics.sh" "fleet/manifest-fleet.sh"
}

teardown() {
    unset MANIFEST_CLI_FLEET_TOPICS_FROM_NAME MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT \
        MANIFEST_CLI_GH_STUB_AUTH_EXIT MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR \
        MANIFEST_CLI_FLEET_TOPICS_ROSTER_LIMIT \
        MANIFEST_CLI_GH_VIEW_STDOUT MANIFEST_CLI_GH_VIEW_EXIT MANIFEST_CLI_GH_LIST_STDOUT MANIFEST_CLI_GH_LIST_EXIT MANIFEST_CLI_GH_EDIT_EXIT
    cd /tmp
    rm -rf "$SCRATCH"
}

# Routing gh stub: unlike the shared gh_stub.sh (one stdout for every call),
# this one answers `repo view` and `repo list` from separate env vars so a
# single run can see member topics AND an org roster.
gh_router_install() {
    mkdir -p "$SCRATCH/.gh-router"
    cat > "$SCRATCH/.gh-router/gh" <<'SH'
#!/usr/bin/env bash
{ printf 'gh'; for a in "$@"; do printf '\t%s' "$a"; done; printf '\n'; } >> "${MANIFEST_CLI_GH_STUB_LOG:-/dev/null}"
case "${1:-} ${2:-}" in
    "auth status") exit 0 ;;
    "repo view") [[ -n "${MANIFEST_CLI_GH_VIEW_STDOUT:-}" ]] && printf '%s\n' "$MANIFEST_CLI_GH_VIEW_STDOUT"; exit "${MANIFEST_CLI_GH_VIEW_EXIT:-0}" ;;
    "repo list") [[ -n "${MANIFEST_CLI_GH_LIST_STDOUT:-}" ]] && printf '%s\n' "$MANIFEST_CLI_GH_LIST_STDOUT"; exit "${MANIFEST_CLI_GH_LIST_EXIT:-0}" ;;
    "repo edit") exit "${MANIFEST_CLI_GH_EDIT_EXIT:-0}" ;;
    *) exit 0 ;;
esac
SH
    chmod +x "$SCRATCH/.gh-router/gh"
    export PATH="$SCRATCH/.gh-router:$PATH"
    export MANIFEST_CLI_GH_STUB_LOG="$SCRATCH/.gh-router/calls.log"
    : > "$MANIFEST_CLI_GH_STUB_LOG"
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
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
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
    ! grep -q "edit" "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "run: apply pushes only topics GitHub does not already have" {
    gh_stub_install "$SCRATCH/.gh-stub"
    # Repo already carries 'service' and the fleet topic — only 'accounting'
    # is missing and may be pushed.
    export MANIFEST_CLI_GH_STUB_STDOUT=$'service\nfleet-test-fleet'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 updated"* ]]
    grep -q -e $'--add-topic\taccounting' "$MANIFEST_CLI_GH_STUB_LOG"
    ! grep -q -e $'--add-topic\tservice' "$MANIFEST_CLI_GH_STUB_LOG"
    ! grep -q -e $'--add-topic\tfleet-test-fleet' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "run: fully up-to-date repo gets zero writes" {
    gh_stub_install "$SCRATCH/.gh-stub"
    export MANIFEST_CLI_GH_STUB_STDOUT=$'service\naccounting\nfleet-test-fleet'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 up to date"* ]]
    ! grep -q "edit" "$MANIFEST_CLI_GH_STUB_LOG"
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
    ! grep -q "edit" "$MANIFEST_CLI_GH_STUB_LOG"
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
    export MANIFEST_CLI_GH_STUB_AUTH_EXIT=1
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false"
    [ "$status" -eq 0 ]
    [[ "$output" == *"not authenticated"* ]]
    ! grep -q "repo" "$MANIFEST_CLI_GH_STUB_LOG"
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
    ! grep -q "edit" "$MANIFEST_CLI_GH_STUB_LOG"
}

# --- Phase 2 roster: pure candidate matching ---------------------------------

@test "roster: candidates share a family prefix, exclude enrolled and unrelated" {
    local known=$'acme/fidence.service.accounting.avalara'
    local prefixes=$'fidence'
    local org=$'fidence.service.accounting.avalara\nfidence.service.billing.stripe\nunrelated-repo\nFidence.Tools.cli'
    run _fleet_topics_org_candidates "acme" "$known" "$prefixes" "$org"
    [ "$status" -eq 0 ]
    [ "$output" = "acme/fidence.service.billing.stripe
acme/Fidence.Tools.cli" ]
}

@test "roster: empty org list yields no candidates" {
    run _fleet_topics_org_candidates "acme" $'acme/fidence.x' $'fidence' ""
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- Phase 2 roster: end-to-end through the run ------------------------------

@test "roster: reports unenrolled family repos with a clone-to-enroll hint" {
    gh_router_install
    export MANIFEST_CLI_GH_LIST_STDOUT=$'fidence.service.accounting.avalara\nfidence.service.billing.stripe\nunrelated-repo'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Roster: 1 family repo(s) exist on GitHub but are not in this fleet:"* ]]
    [[ "$output" == *"- acme/fidence.service.billing.stripe"* ]]
    [[ "$output" == *"Clone into the fleet root"* ]]
    [[ "$output" != *"unrelated-repo"* ]]
    grep -q -e $'repo\tlist\tacme\t--no-archived' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "roster: failed org listing degrades to a notice, rc 0" {
    gh_router_install
    export MANIFEST_CLI_GH_LIST_EXIT=1
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Roster check skipped for acme (gh repo list failed)"* ]]
}

@test "roster: hitting the listing cap is reported, never silent" {
    gh_router_install
    export MANIFEST_CLI_FLEET_TOPICS_ROSTER_LIMIT=2
    export MANIFEST_CLI_GH_LIST_STDOUT=$'fidence.alpha\nfidence.beta'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"covered only the first 2 repos of acme"* ]]
}

@test "roster: no GitHub members means no org listing at all" {
    gh_router_install
    write_config 'topics:
  from_name: inner'
    write_tsv $'true\tsvc\t./svc\tservice\tfalse\t\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "true"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Roster"* ]]
    ! grep -q -e $'repo\tlist' "$MANIFEST_CLI_GH_STUB_LOG"
}

# --- wiring smoke for no-topics path (unchanged by Phase 2) ------------------

@test "update fleet: no topics config means no topics output at all" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config ""
    write_tsv $'true\tsvc\t./svc\tservice\tfalse\t\tmain'

    run_manifest update fleet
    [ "$status" -eq 0 ]
    [[ "$output" != *"Topics"* ]]
}

# --- quiet mode (the post-ship pass) ------------------------------------------

@test "run quiet: apply with changes prints exactly one summary line" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false" "true"
    [ "$status" -eq 0 ]
    [ "$output" = "🏷️  GitHub topics: 1 repo(s) updated" ]
    grep -q "edit" "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "run quiet: nothing to update prints nothing at all" {
    gh_stub_install "$SCRATCH/.gh-stub"
    export MANIFEST_CLI_GH_STUB_STDOUT=$'service\naccounting\nfleet-test-fleet'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false" "true"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "run quiet: degraded gh (missing) is fully silent, rc 0" {
    # Mode comes from the env (not YAML): with PATH gutted there is no yq for
    # the config read — same shape as the non-quiet gh-missing test above.
    mkdir -p "$SCRATCH/no-gh"
    write_config ""
    write_tsv $'true\tsvc\t./svc\tservice\ttrue\t\tmain'

    MANIFEST_CLI_FLEET_TOPICS_FROM_NAME=inner PATH="$SCRATCH/no-gh" \
        run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false" "true"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "run quiet: failed pushes surface one line with a re-run hint" {
    gh_router_install
    export MANIFEST_CLI_GH_EDIT_EXIT=1
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false" "true"
    [ "$status" -eq 0 ]
    [[ "$output" == *"0 updated, 1 failed"* ]]
    [[ "$output" == *"manifest topics fleet -y"* ]]
}

@test "run quiet: roster is never printed" {
    gh_router_install
    export MANIFEST_CLI_GH_LIST_STDOUT=$'fidence.service.newrepo'
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/$CONFIG" "false" "true"
    [ "$status" -eq 0 ]
    [[ "$output" != *"Roster"* ]]
    ! grep -q -e $'repo\tlist' "$MANIFEST_CLI_GH_STUB_LOG"
}

# --- wiring: manifest topics fleet ---------------------------------------------

@test "topics fleet: preview lists the delta with its own apply hint, no writes" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run_manifest topics fleet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Topics (topics.from_name: inner)"* ]]
    [[ "$output" == *"+service"* ]]
    [[ "$output" == *"To apply, run: manifest topics fleet -y"* ]]
    ! grep -q "edit" "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "topics fleet: -y pushes the missing topics" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config 'topics:
  from_name: inner'
    make_member "fidence.service.accounting.avalara" "git@github.com:acme/fidence.service.accounting.avalara.git"
    write_tsv $'true\tavalara\t./fidence.service.accounting.avalara\tservice\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain'

    run_manifest topics fleet -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 updated"* ]]
    grep -q -e $'--add-topic\tservice' "$MANIFEST_CLI_GH_STUB_LOG"
}

@test "topics fleet: off prints an enable hint and makes zero gh calls" {
    gh_stub_install "$SCRATCH/.gh-stub"
    write_config ""
    write_tsv $'true\tsvc\t./svc\tservice\tfalse\t\tmain'

    run_manifest topics fleet
    [ "$status" -eq 0 ]
    [[ "$output" == *"Topics are off"* ]]
    [[ "$output" == *"topics.from_name"* ]]
    [ ! -s "$MANIFEST_CLI_GH_STUB_LOG" ]
}

@test "topics fleet: invalid topics.from_name fails loud" {
    write_config 'topics:
  from_name: midle'
    write_tsv $'true\tsvc\t./svc\tservice\tfalse\t\tmain'

    run_manifest topics fleet
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid topics.from_name"* ]]
}

# --- wiring: post-ship quiet pass ----------------------------------------------

@test "ship topics pass: enabled topics run quietly with apply semantics" {
    local calls="$SCRATCH/topics-pass-calls"
    _fleet_resolve_config() { echo "$SCRATCH/work/$CONFIG"; }
    manifest_fleet_topics_run() { printf '%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" > "$calls"; return 0; }
    MANIFEST_CLI_FLEET_ROOT="$SCRATCH/work"

    run _fleet_ship_topics_pass "false"
    [ "$status" -eq 0 ]
    [ -f "$calls" ]
    [ "$(cat "$calls")" = "$SCRATCH/work|$SCRATCH/work/$CONFIG|false|true" ]
}

@test "ship topics pass: --local ship never touches topics" {
    local calls="$SCRATCH/topics-pass-calls"
    _fleet_resolve_config() { echo "$SCRATCH/work/$CONFIG"; }
    manifest_fleet_topics_run() { touch "$calls"; }
    MANIFEST_CLI_FLEET_ROOT="$SCRATCH/work"

    run _fleet_ship_topics_pass "true"
    [ "$status" -eq 0 ]
    [ ! -f "$calls" ]
}

@test "ship topics pass: a failing topics run never fails the ship" {
    _fleet_resolve_config() { echo "$SCRATCH/work/$CONFIG"; }
    manifest_fleet_topics_run() { return 1; }
    MANIFEST_CLI_FLEET_ROOT="$SCRATCH/work"

    run _fleet_ship_topics_pass "false"
    [ "$status" -eq 0 ]
}

@test "ship topics pass: no resolvable fleet config is a silent no-op" {
    local calls="$SCRATCH/topics-pass-calls"
    _fleet_resolve_config() { return 1; }
    manifest_fleet_topics_run() { touch "$calls"; }
    MANIFEST_CLI_FLEET_ROOT="$SCRATCH/work"

    run _fleet_ship_topics_pass "false"
    [ "$status" -eq 0 ]
    [ ! -f "$calls" ]
}
