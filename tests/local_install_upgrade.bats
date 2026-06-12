#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules \
        "system/manifest-os.sh" \
        "system/manifest-install-paths.sh" \
        "git/manifest-git.sh" \
        "workflow/manifest-orchestrator.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$PROJECT_ROOT/formula"
    cd "$PROJECT_ROOT"
    git init -q .
    git checkout -q -b main
    git config user.email "test@example.com"
    git config user.name "Test"
    echo "1.2.3" > VERSION
    echo "stub formula" > formula/manifest.rb
    git add VERSION formula/manifest.rb
    git commit -qm "Bump version to 1.2.3"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="main"

    # Drive the first block to "success" without touching the tap or network:
    # treat fixture as the canonical CLI repo, and make the formula update
    # return 0 without modifying formula/manifest.rb so the commit branch is skipped.
    should_update_homebrew_for_repo() { return 0; }
    update_homebrew_formula() { return 0; }
    manifest_create_github_release_for_tag() { return 2; }

    # The upgrade paths stamp/clear the auto-upgrade cooldown — keep every
    # state write inside the scratch dir, never the developer's real HOME.
    manifest_install_paths_global_state_dir() { echo "$SCRATCH/state"; }
    # The bottle-wait loop sleeps between polls; never block the suite.
    sleep() { :; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "local upgrade surfaces install command when brew has no manifest installed" {
    # brew is on PATH (as a function), but no manifest formula is installed:
    # every `brew list` form fails, matching manifest_install_paths_is_brew_managed's
    # probe (the canonical provenance predicate the orchestrator now calls).
    brew() {
        [[ "$1" == "list" ]] && return 1
        return 0
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    echo "$output" | grep -q "brew install fidenceio/tap/manifest"
    # The new probe must replace the legacy generic warning, not run alongside it.
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
    ! echo "$output" | grep -q "Local installation upgraded"
}

@test "local upgrade reports success when brew upgrade manifest succeeds" {
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list "*) return 0 ;;  # any `brew list <formula>` → manifest is brew-managed
            "update "*|"update") return 0 ;;
            "upgrade manifest"*) return 0 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Local installation upgraded to v1.2.3 via Homebrew"
    ! echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
    # A completed ship upgrade stamps the cooldown: the next ambient
    # auto-upgrade check would be a no-op, so don't burn a brew update on it.
    [ -f "$SCRATCH/state/.auto_upgrade_last_check" ]
}

@test "successful brew upgrade invokes the SSH-restore helper" {
    # Integration check: confirm post-push wires the SSH-restore step in after
    # a successful upgrade. The helper's own behavior is covered exhaustively
    # in homebrew_tap_ssh_restore.bats — this test only proves the call site
    # exists. No tap-dir paths or SSH URLs are hardcoded; we stub the helper
    # to drop a sentinel and assert the sentinel appears.
    local sentinel="$SCRATCH/ssh-restore-fired"
    manifest_ship_restore_tap_ssh_origin() { touch "$sentinel"; }

    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list "*) return 0 ;;  # any `brew list <formula>` → manifest is brew-managed
            "update "*|"update") return 0 ;;
            "upgrade manifest"*) return 0 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Local installation upgraded to v1.2.3 via Homebrew"
    [ -f "$sentinel" ]
}

@test "failed brew upgrade does NOT invoke the SSH-restore helper" {
    # Drift guard: the restore helper must only fire after a successful
    # upgrade, not unconditionally — otherwise we'd be writing origin URLs
    # against a tap brew may not even have touched.
    local sentinel="$SCRATCH/ssh-restore-fired"
    manifest_ship_restore_tap_ssh_origin() { touch "$sentinel"; }

    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list "*) return 0 ;;  # any `brew list <formula>` → manifest is brew-managed
            "update "*|"update") return 0 ;;
            "upgrade manifest"*) return 1 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Homebrew upgrade did not complete"
    [ ! -f "$sentinel" ]
}

@test "local upgrade warns when brew has manifest installed but upgrade fails" {
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list "*) return 0 ;;  # any `brew list <formula>` → manifest is brew-managed
            "update "*|"update") return 0 ;;
            "upgrade manifest"*) return 1 ;;
            *) return 0 ;;
        esac
    }
    # A failed ship upgrade must hand off to the invocation-time auto-upgrade
    # immediately — the cooldown paces ambient checks, not a ship that just
    # published a formula this machine still needs.
    mkdir -p "$SCRATCH/state"
    date +%s > "$SCRATCH/state/.auto_upgrade_last_check"

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Homebrew upgrade did not complete"
    echo "$output" | grep -q "brew update && brew upgrade manifest"
    ! echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    ! echo "$output" | grep -q "Local installation upgraded"
    [ ! -f "$SCRATCH/state/.auto_upgrade_last_check" ]
}

@test "local upgrade is skipped entirely when tap push did not succeed" {
    # Force the homebrew block to self-skip → workflow_homebrew_status stays "skipped".
    # The local upgrade gate must then prevent any upgrade output, even with a
    # fully functional brew on PATH.
    rm -f "$PROJECT_ROOT/formula/manifest.rb"
    git add -A
    git commit -qm "drop formula"

    brew() { return 0; }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Upgrading local Manifest CLI installation"
    ! echo "$output" | grep -q "Local installation upgraded"
    ! echo "$output" | grep -q "Local manifest is not installed via Homebrew"
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
}

@test "is_brew_managed: Cellar keg is authoritative even when brew list transiently fails (§8.13)" {
    # Regression: provenance must come from the install location, not `brew list`
    # exit status — which can transiently fail right after the same ship refreshes
    # the tap checkout. A present Cellar keg with a failing `brew list` must still
    # report brew-managed.
    local cellar="$SCRATCH/cellar"
    mkdir -p "$cellar/manifest/1.2.3"
    brew() {
        case "$1" in
            --cellar) echo "$cellar"; return 0 ;;
            list)     return 1 ;;   # transient failure, both tap-qualified and bare forms
            *)        return 0 ;;
        esac
    }

    run manifest_install_paths_is_brew_managed
    [ "$status" -eq 0 ]
}

@test "is_brew_managed: not managed when no Cellar keg and brew list fails (§8.13 boundary)" {
    # Boundary: a Cellar exists but holds no manifest keg, and `brew list` fails →
    # genuinely not brew-managed. Guards against the filesystem check matching too
    # eagerly.
    local cellar="$SCRATCH/cellar"
    mkdir -p "$cellar"
    brew() {
        case "$1" in
            --cellar) echo "$cellar"; return 0 ;;
            list)     return 1 ;;
            *)        return 0 ;;
        esac
    }

    run manifest_install_paths_is_brew_managed
    [ "$status" -eq 1 ]
}

@test "brew_error_is_toolchain_gate: Xcode-too-outdated output is a toolchain gate" {
    run manifest_install_paths_brew_error_is_toolchain_gate \
        "Error: Your Xcode (26.5) at /Applications/Xcode.app is too outdated."
    [ "$status" -eq 0 ]
}

@test "brew_error_is_toolchain_gate: CLT-too-outdated output is a toolchain gate" {
    run manifest_install_paths_brew_error_is_toolchain_gate \
        "Error: Your Command Line Tools are too outdated."
    [ "$status" -eq 0 ]
}

@test "brew_error_is_toolchain_gate: an unrelated brew failure is NOT a toolchain gate" {
    run manifest_install_paths_brew_error_is_toolchain_gate \
        "Error: manifest 53.0.3 is already installed and up-to-date."
    [ "$status" -eq 1 ]
}

@test "build_id_is_prerelease: seed build (trailing lowercase) is a pre-release" {
    run manifest_os_build_id_is_prerelease "26A5353q"
    [ "$status" -eq 0 ]
}

@test "build_id_is_prerelease: shipping build (ends in digit) is not a pre-release" {
    run manifest_os_build_id_is_prerelease "23A344"
    [ "$status" -eq 1 ]
}

@test "build_id_is_prerelease: empty build id is not a pre-release" {
    run manifest_os_build_id_is_prerelease ""
    [ "$status" -eq 1 ]
}

@test "local upgrade: toolchain gate waits for the bottle and pours it when CI publishes" {
    # brew can't source-build (host Xcode/CLT gate), so the ship waits for tap
    # CI's :all bottle and pours it with --force-bottle. Here the bottle "lands"
    # on the first poll: the upgrade must complete, fire the SSH-restore step,
    # and stamp the auto-upgrade cooldown (the next ambient check is a no-op).
    manifest_os_macos_is_prerelease() { return 1; }   # deterministic: suppress beta line
    export MANIFEST_CLI_SHIP_BOTTLE_WAIT_MINUTES=1
    local sentinel="$SCRATCH/ssh-restore-fired"
    manifest_ship_restore_tap_ssh_origin() { touch "$sentinel"; }
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list --versions manifest")
                if [ -f "$SCRATCH/bottle-poured" ]; then echo "manifest 1.2.3"; else echo "manifest 1.2.2"; fi
                return 0 ;;
            "list "*) return 0 ;;
            "update "*|"update") return 0 ;;
            "upgrade --force-bottle"*) touch "$SCRATCH/bottle-poured"; return 0 ;;
            "upgrade manifest"*)
                echo "Error: Your Xcode (26.5) at /Applications/Xcode.app is too outdated."
                return 1 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "can't source-build"
    echo "$output" | grep -q "Waiting for tap CI"
    echo "$output" | grep -q "Local installation upgraded to v1.2.3 via Homebrew bottle"
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
    [ -f "$sentinel" ]
    [ -f "$SCRATCH/state/.auto_upgrade_last_check" ]
}

@test "local upgrade: unpublished bottle defers to auto-upgrade and clears the cooldown" {
    # The gate fires and the bottle never lands inside the wait window. The ship
    # must not print the misleading generic warning, must not touch the tap SSH
    # origin (that only follows a real upgrade), and must clear the cooldown
    # stamp so the very next invocation pours the bottle instead of waiting out
    # the window — the cooldown paces ambient checks, not a post-ship catch-up.
    manifest_os_macos_is_prerelease() { return 1; }   # deterministic: suppress beta line
    export MANIFEST_CLI_SHIP_BOTTLE_WAIT_MINUTES=1
    local sentinel="$SCRATCH/ssh-restore-fired"
    manifest_ship_restore_tap_ssh_origin() { touch "$sentinel"; }
    mkdir -p "$SCRATCH/state"
    date +%s > "$SCRATCH/state/.auto_upgrade_last_check"
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list --versions manifest") echo "manifest 1.2.2"; return 0 ;;
            "list "*) return 0 ;;
            "update "*|"update") return 0 ;;
            "upgrade --force-bottle"*) return 1 ;;   # no bottle to pour yet
            "upgrade manifest"*)
                echo "Error: Your Command Line Tools are too outdated."
                return 1 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "can't source-build"
    echo "$output" | grep -q "is not published yet"
    echo "$output" | grep -q "shipped"
    echo "$output" | grep -q "cooldown has been cleared"
    ! echo "$output" | grep -q "Homebrew upgrade did not complete"
    ! echo "$output" | grep -q "Local installation upgraded"
    [ ! -f "$sentinel" ]
    [ ! -f "$SCRATCH/state/.auto_upgrade_last_check" ]
}

@test "local upgrade: bottle wait window of 0 defers immediately without polling" {
    export MANIFEST_CLI_SHIP_BOTTLE_WAIT_MINUTES=0
    manifest_os_macos_is_prerelease() { return 1; }
    local brewlog="$SCRATCH/brewcmds"
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list "*) return 0 ;;
            "update "*|"update") return 0 ;;
            "upgrade --force-bottle"*) echo "$*" >> "$brewlog"; return 0 ;;
            "upgrade manifest"*)
                echo "Error: Your Xcode (26.5) is too outdated."
                return 1 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    ! echo "$output" | grep -q "Waiting for tap CI"
    echo "$output" | grep -q "is not published yet"
    [ ! -f "$brewlog" ]
}

@test "local upgrade: toolchain-gate message gains a pre-release note on a macOS beta" {
    manifest_os_macos_is_prerelease() { return 0; }   # force the beta branch
    export MANIFEST_CLI_SHIP_BOTTLE_WAIT_MINUTES=0    # skip the wait; the note prints first
    brew() {
        case "$1 ${2:-} ${3:-}" in
            "list "*) return 0 ;;
            "update "*|"update") return 0 ;;
            "upgrade manifest"*)
                echo "Error: Your Xcode (26.5) is too outdated."
                return 1 ;;
            *) return 0 ;;
        esac
    }

    run manifest_ship_post_push_steps "1.2.3" "$(git rev-parse HEAD)" "v1.2.3" "success"

    [ "$status" -eq 0 ]
    echo "$output" | grep -q "can't source-build"
    echo "$output" | grep -q "macOS pre-release"
}

@test "auto-upgrade: opt-out via MANIFEST_CLI_AUTO_UPDATE=false does nothing" {
    export MANIFEST_CLI_AUTO_UPDATE=false
    local sd="$SCRATCH/state"; mkdir -p "$sd"
    manifest_install_paths_global_state_dir() { echo "$sd"; }
    manifest_install_paths_is_brew_managed() { return 0; }
    manifest_install_paths_home_looks_sandboxed() { return 1; }  # opt out of the sandbox gate to test the logic
    brew() { return 0; }
    local spawned="$SCRATCH/spawned"
    manifest_install_paths_auto_upgrade_spawn() { touch "$spawned"; }

    run manifest_install_paths_auto_upgrade
    [ "$status" -eq 0 ]
    [ ! -f "$spawned" ]
    [ ! -f "$sd/.auto_upgrade_last_check" ]
}

@test "auto-upgrade: skipped when the install is not brew-managed" {
    local sd="$SCRATCH/state"; mkdir -p "$sd"
    manifest_install_paths_global_state_dir() { echo "$sd"; }
    manifest_install_paths_is_brew_managed() { return 1; }   # source/manual install
    manifest_install_paths_home_looks_sandboxed() { return 1; }  # opt out of the sandbox gate to test the logic
    brew() { return 0; }
    local spawned="$SCRATCH/spawned"
    manifest_install_paths_auto_upgrade_spawn() { touch "$spawned"; }

    run manifest_install_paths_auto_upgrade
    [ "$status" -eq 0 ]
    [ ! -f "$spawned" ]
}

@test "auto-upgrade: within the cooldown window it does not spawn" {
    local sd="$SCRATCH/state"; mkdir -p "$sd"
    manifest_install_paths_global_state_dir() { echo "$sd"; }
    manifest_install_paths_is_brew_managed() { return 0; }
    manifest_install_paths_home_looks_sandboxed() { return 1; }  # opt out of the sandbox gate to test the logic
    brew() { return 0; }
    local spawned="$SCRATCH/spawned"
    manifest_install_paths_auto_upgrade_spawn() { touch "$spawned"; }
    date +%s > "$sd/.auto_upgrade_last_check"   # last check = now → diff 0 < cooldown

    run manifest_install_paths_auto_upgrade
    [ "$status" -eq 0 ]
    [ ! -f "$spawned" ]
}

@test "auto-upgrade: past the cooldown it spawns and re-stamps the check time" {
    local sd="$SCRATCH/state"; mkdir -p "$sd"
    manifest_install_paths_global_state_dir() { echo "$sd"; }
    manifest_install_paths_is_brew_managed() { return 0; }
    manifest_install_paths_home_looks_sandboxed() { return 1; }  # opt out of the sandbox gate to test the logic
    brew() { return 0; }
    local spawned="$SCRATCH/spawned"
    manifest_install_paths_auto_upgrade_spawn() { touch "$spawned"; }
    echo 0 > "$sd/.auto_upgrade_last_check"   # epoch 0 → far past any cooldown

    run manifest_install_paths_auto_upgrade
    [ "$status" -eq 0 ]
    [ -f "$spawned" ]
    local stamped; stamped="$(cat "$sd/.auto_upgrade_last_check")"
    [ "$stamped" -gt 0 ]
}

@test "auto-upgrade: surfaces a completed background upgrade once, then clears it" {
    local sd="$SCRATCH/state"; mkdir -p "$sd"
    manifest_install_paths_global_state_dir() { echo "$sd"; }
    manifest_install_paths_is_brew_managed() { return 0; }
    manifest_install_paths_home_looks_sandboxed() { return 1; }  # opt out of the sandbox gate to test the logic
    brew() { return 0; }
    manifest_install_paths_auto_upgrade_spawn() { :; }   # no-op
    echo "53.1.0" > "$sd/.auto_upgrade_result"
    date +%s > "$sd/.auto_upgrade_last_check"            # within cooldown → isolate the notice

    run manifest_install_paths_auto_upgrade
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "auto-upgraded to v53.1.0"
    [ ! -f "$sd/.auto_upgrade_result" ]
}

@test "auto-upgrade worker: pours a bottle with --force-bottle and records the new version" {
    # The detached worker must use --force-bottle (pour-or-fail-fast; never a
    # source build → never the Xcode gate) and record the new version on change.
    local sd="$SCRATCH/state"; mkdir -p "$sd"
    local result="$sd/.auto_upgrade_result"
    local brewlog="$SCRATCH/brewcmds"; local upgraded="$SCRATCH/upgraded"
    brew() {
        case "$1 ${2:-}" in
            "list --versions") if [ -f "$upgraded" ]; then echo "manifest 53.1.0"; else echo "manifest 53.0.5"; fi ;;
            "upgrade --force-bottle") echo "$*" >> "$brewlog"; touch "$upgraded"; return 0 ;;
            *) return 0 ;;
        esac
    }

    run manifest_install_paths_auto_upgrade_bg "$result" "fidenceio/tap/manifest"
    [ "$status" -eq 0 ]
    [ -f "$result" ]
    [ "$(cat "$result")" = "53.1.0" ]
    grep -q -- "--force-bottle" "$brewlog"
}
