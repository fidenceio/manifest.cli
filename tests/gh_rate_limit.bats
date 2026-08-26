#!/usr/bin/env bats
# gh mutation rate-limit controller (tracker §9.2).
#
# Contract under test:
#   - manifest_gh_rate_required_wait is a PURE decision function of
#     (timestamps file, now, hourly cap): no sleeps, no env reads, so every
#     window shape is testable with synthetic time.
#   - the gate (manifest_gh_rate_limit_gate) paces only when a window is full,
#     is NEVER silent about a wait, records every mutation, and 0 disables it.
#   - wiring: `gh repo create`, `gh repo edit --add-topic`, and `gh release
#     create` all pass through the gate immediately before the mutation; read
#     calls (repo view / repo list) and preview runs never do.
#
# MANIFEST_CLI_GH_RATE_NOW_EPOCH is the test-only injected clock: with it set,
# the gate advances the synthetic clock instead of sleeping for real, so
# pacing decisions are asserted without slow tests.

load 'helpers/setup'

setup() {
    load_modules \
        "fleet/manifest-fleet-detect.sh" \
        "fleet/manifest-fleet-topics.sh"
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
    STATE="$SCRATCH/epochs"
}

teardown() {
    unset MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR MANIFEST_CLI_GH_RATE_NOW_EPOCH
    unset MANIFEST_CLI_GH_STUB_LOG MANIFEST_CLI_GH_STUB_EXIT MANIFEST_CLI_GH_STUB_AUTH_EXIT \
        MANIFEST_CLI_GH_STUB_STDOUT MANIFEST_CLI_GH_STUB_STDERR MANIFEST_CLI_GH_STUB_ADD_REMOTE
    unset _MANIFEST_GH_VALIDATED_AT _MANIFEST_CLI_GH_RATE_NOTICE_SHOWN
    cd /tmp
    rm -rf "$SCRATCH"
}

# Append $1 copies of epoch $2 to $STATE.
write_epochs() {
    local n="$1" ts="$2" i
    for (( i = 0; i < n; i++ )); do
        printf '%s\n' "$ts" >> "$STATE"
    done
}

# The gate's state file under the (redirected) per-user state root.
gate_state_file() { echo "$HOME/.manifest-cli/gh-rate/mutation-epochs"; }

# --- pure decision function ---------------------------------------------------

@test "rate: missing state file needs no wait" {
    run manifest_gh_rate_required_wait "$STATE" 1000000 150
    [ "$status" -eq 0 ]
    [ "$output" = "0" ]
}

@test "rate: under both windows needs no wait" {
    write_epochs 10 999970    # 10 calls 30s ago
    run manifest_gh_rate_required_wait "$STATE" 1000000 150
    [ "$output" = "0" ]
}

@test "rate: 60 calls inside the rolling minute hits the fixed floor" {
    write_epochs 60 999990    # 60 calls 10s ago
    run manifest_gh_rate_required_wait "$STATE" 1000000 150
    # Oldest relevant entry ages out of the 60s window at 999990+60.
    [ "$output" = "50" ]
}

@test "rate: minute-floor wait is set by the entry whose expiry admits one more" {
    write_epochs 1 999941     # one call 59s ago (expires in 1s)
    write_epochs 59 999990    # 59 calls 10s ago
    run manifest_gh_rate_required_wait "$STATE" 1000000 150
    [ "$output" = "1" ]
}

@test "rate: hourly cap engages at the configured N" {
    write_epochs 5 999900     # 5 calls 100s ago
    run manifest_gh_rate_required_wait "$STATE" 1000000 5
    # Admitting a 6th requires the oldest to age out: 999900+3600-1000000.
    [ "$output" = "3500" ]
    # One call of headroom left -> no wait.
    : > "$STATE"
    write_epochs 4 999900
    run manifest_gh_rate_required_wait "$STATE" 1000000 5
    [ "$output" = "0" ]
}

@test "rate: the larger of the two window waits wins" {
    write_epochs 60 999990    # fills the minute (wait 50) AND the hour at cap 60
    run manifest_gh_rate_required_wait "$STATE" 1000000 60
    # Hourly: 999990+3600-1000000 = 3590 > minute's 50.
    [ "$output" = "3590" ]
}

@test "rate: hourly cap 0 means no hourly cap, but the minute floor still holds" {
    write_epochs 60 999990
    run manifest_gh_rate_required_wait "$STATE" 1000000 0
    [ "$output" = "50" ]
}

@test "rate: non-numeric lines are ignored, entries outside the window age out" {
    {
        echo "garbage"
        echo ""
        echo "12x34"
    } >> "$STATE"
    write_epochs 60 999930    # 70s ago: outside the minute window, inside the hour
    run manifest_gh_rate_required_wait "$STATE" 1000000 150
    [ "$output" = "0" ]
}

# --- the gate (wrapper) --------------------------------------------------------

@test "rate: gate records each mutation into the per-user state file (0600/0700)" {
    export MANIFEST_CLI_GH_RATE_NOW_EPOCH=1000000
    local out
    out="$(manifest_gh_rate_limit_gate)"
    [ -z "$out" ]                       # under the limits: silent
    local f; f="$(gate_state_file)"
    [ -f "$f" ]
    [ "$(cat "$f")" = "1000000" ]
    # Tight modes: dir 0700, file 0600 (SEC-011: never group/world readable).
    # GNU/busybox stat first (-c), BSD/macOS fallback (-f %Lp).
    local dir_mode file_mode
    dir_mode="$(stat -c '%a' "${f%/*}" 2>/dev/null || stat -f '%Lp' "${f%/*}")"
    file_mode="$(stat -c '%a' "$f" 2>/dev/null || stat -f '%Lp' "$f")"
    [ "$dir_mode" = "700" ]
    [ "$file_mode" = "600" ]
}

@test "rate: github.rate_limit_per_hour=0 disables pacing entirely" {
    export MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR=0
    export MANIFEST_CLI_GH_RATE_NOW_EPOCH=1000000
    run manifest_gh_rate_limit_gate
    [ "$status" -eq 0 ]
    [ -z "$output" ]
    [ ! -e "$(gate_state_file)" ]       # disabled: no state either
}

@test "rate: a full minute window paces LOUDLY and advances the clock instead of skipping" {
    export MANIFEST_CLI_GH_RATE_NOW_EPOCH=1000000
    local f; f="$(gate_state_file)"
    mkdir -p "${f%/*}"
    local i
    for (( i = 0; i < 60; i++ )); do printf '999990\n' >> "$f"; done

    local start end out
    start="$(date +%s)"
    out="$(manifest_gh_rate_limit_gate)"
    end="$(date +%s)"

    # Injected time: the 50s wait is announced but not slept for real.
    [ $(( end - start )) -lt 10 ]
    local first_line
    first_line="$(grep -m1 "Pacing GitHub mutation calls" <<<"$out")"
    [ -n "$first_line" ]
    grep -q "waiting 50s" <<<"$out"
    # The call was recorded at the post-wait instant (1000000+50), never dropped.
    grep -qx "1000050" "$f"
}

@test "rate: subsequent waits in one process print the compact line, not the full notice" {
    export MANIFEST_CLI_GH_RATE_NOW_EPOCH=1000000
    local f; f="$(gate_state_file)"
    mkdir -p "${f%/*}"
    local i
    for (( i = 0; i < 60; i++ )); do printf '999990\n' >> "$f"; done

    # Direct calls with file redirection (not command substitution): production
    # call sites invoke the gate in the caller's shell, where the once-per-run
    # notice flag persists; a $(...) subshell would discard it and re-print the
    # full notice every time.
    manifest_gh_rate_limit_gate > "$SCRATCH/out1"
    manifest_gh_rate_limit_gate > "$SCRATCH/out2"
    grep -q "Pacing GitHub mutation calls" "$SCRATCH/out1"
    grep -q "pacing: waiting" "$SCRATCH/out2"
    refute grep -q "Pacing GitHub mutation calls" "$SCRATCH/out2"
}

@test "rate: without injected time the gate really sleeps out a 1s wait" {
    local f now
    f="$(gate_state_file)"
    mkdir -p "${f%/*}"
    now="$(date +%s)"
    # Seed at now-58, not now-59, and write once rather than appending 60 times.
    # The gate admits a timestamp only while `now - ts < 60`, and it reads its
    # OWN clock after this seeding runs — so at now-59 the margin is exactly one
    # second, and a single tick between the two `date` calls ages the entries out
    # of the window. The gate then correctly does not sleep and the assertion
    # below fails: measured ~33% (2 of 6 isolated runs). Two seconds of margin
    # plus a single write makes the race unreachable without weakening the
    # assertion — a 1s floor is still what is being proven. (TRACKER §64)
    local i seeded=""
    for (( i = 0; i < 60; i++ )); do seeded+="$(( now - 58 ))"$'\n'; done
    printf '%s' "$seeded" >> "$f"

    local start end out
    start="$(date +%s)"
    out="$(manifest_gh_rate_limit_gate)"
    end="$(date +%s)"
    grep -q "Pacing GitHub mutation calls" <<<"$out"
    [ $(( end - start )) -ge 1 ]
}

@test "rate: default hourly cap is 150 and it is the mapped config key's env var" {
    # The gate consumes MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR (the mapping for
    # github.rate_limit_per_hour). Cap it at 1 via the env var, fill the hour
    # window with one entry, and the second call must wait — proving the env
    # var is the live knob, not a dead key.
    export MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR=1
    export MANIFEST_CLI_GH_RATE_NOW_EPOCH=1000000
    local out1 out2
    out1="$(manifest_gh_rate_limit_gate)"
    [ -z "$out1" ]
    out2="$(manifest_gh_rate_limit_gate)"
    grep -q "1/hr configured" <<<"$out2"
    grep -q "waiting 3600s" <<<"$out2"
}

@test "rate: set_default_configuration exports the 150/hr default" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-config.sh"
    unset MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN
    set_default_configuration >/dev/null 2>&1
    [ "$MANIFEST_CLI_GITHUB_RATE_LIMIT_PER_HOUR" = "150" ]
    [ "$MANIFEST_CLI_RELEASE_REQUIRE_CI_GREEN" = "true" ]
}

# --- wiring: mutations pace, reads never --------------------------------------

@test "rate: gh repo create routes through the gate immediately before the mutation" {
    # Marker override proves the CALL SITE: without the wiring in
    # _manifest_gh_repo_create, this marker is never touched.
    manifest_gh_rate_limit_gate() { touch "$SCRATCH/gate-invoked"; }
    gh_stub_install "$SCRATCH/.gh-stub"
    export MANIFEST_CLI_GH_STUB_ADD_REMOTE=true

    local repo="$SCRATCH/work/svc-a"
    mkdir -p "$repo"
    git -C "$repo" init -q

    run _manifest_gh_repo_create "$repo" "private"
    [ "$status" -eq 0 ]
    [ -e "$SCRATCH/gate-invoked" ]
    local calls
    calls="$(cat "$MANIFEST_CLI_GH_STUB_LOG")"
    grep -q $'\trepo\tcreate' <<<"$calls"
}

@test "rate: topics APPLY paces gh repo edit; topics PREVIEW (reads only) never paces" {
    manifest_gh_rate_limit_gate() { touch "$SCRATCH/gate-invoked"; }
    gh_stub_install "$SCRATCH/.gh-stub"

    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
topics:
  from_name: inner
YAML
    local member="$SCRATCH/work/fidence.service.accounting.avalara"
    mkdir -p "$member"
    git -C "$member" init -q
    git -C "$member" remote add origin "git@github.com:acme/fidence.service.accounting.avalara.git"
    printf '%s\n' $'true\tavalara\t./fidence.service.accounting.avalara\ttrue\tgit@github.com:acme/fidence.service.accounting.avalara.git\tmain' \
        > "$SCRATCH/work/manifest.fleet.tsv"

    # Preview: gh reads happen (repo view), the gate must NOT engage.
    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/manifest.fleet.config.yaml" "true"
    [ "$status" -eq 0 ]
    [ ! -e "$SCRATCH/gate-invoked" ]

    # Apply: the repo edit mutation must pass through the gate.
    run manifest_fleet_topics_run "$SCRATCH/work" "$SCRATCH/work/manifest.fleet.config.yaml" "false"
    [ "$status" -eq 0 ]
    [ -e "$SCRATCH/gate-invoked" ]
    local calls
    calls="$(cat "$MANIFEST_CLI_GH_STUB_LOG")"
    grep -q $'\trepo\tedit' <<<"$calls"
}

@test "rate: gh release create routes through the gate" {
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    manifest_gh_rate_limit_gate() { touch "$SCRATCH/gate-invoked"; }

    local repo="$SCRATCH/work/relrepo"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" remote add origin "git@github.com:acme/relrepo.git"
    export MANIFEST_CLI_PROJECT_ROOT="$repo"

    gh() {
        case "${1:-} ${2:-}" in
            "auth status") return 0 ;;
            "release view") return 1 ;;   # missing -> create is attempted
            "release create") return 0 ;;
            *) return 1 ;;
        esac
    }

    run manifest_create_github_release_for_tag "1.2.3" "v1.2.3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GitHub Release: created (v1.2.3)"* ]]
    [ -e "$SCRATCH/gate-invoked" ]
}
