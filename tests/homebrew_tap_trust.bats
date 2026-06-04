#!/usr/bin/env bats
#
# §7.1: manifest_install_paths_ensure_brew_trust narrowly trusts the Manifest
# formula so Homebrew keeps loading it once HOMEBREW_REQUIRE_TAP_TRUST is the
# default (untrusted formulae are otherwise ignored → silent install/upgrade
# no-op). Version-guarded against older Homebrew that has no `brew trust`.

load 'helpers/setup'

setup() {
    load_modules "system/manifest-install-paths.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "tap-trust: trusts the formula narrowly on a Homebrew that supports it" {
    # Modern Homebrew: `trust --help` succeeds; `trust --formula <f>` records it.
    brew() {
        if [ "$1" = "trust" ] && [ "$2" = "--help" ]; then return 0; fi
        if [ "$1" = "trust" ] && [ "$2" = "--formula" ]; then
            printf '%s\n' "$3" >> "$SCRATCH/trusted"; return 0
        fi
        return 0
    }
    export -f brew

    run manifest_install_paths_ensure_brew_trust
    [ "$status" -eq 0 ]
    # Narrow, formula-qualified target — never the whole tap.
    [ "$(cat "$SCRATCH/trusted")" = "fidenceio/tap/manifest" ]
}

@test "tap-trust: skips cleanly on a Homebrew without the trust subcommand" {
    # Older Homebrew: `brew trust ...` is an unknown command (non-zero).
    brew() { [ "$1" = "trust" ] && return 1; return 0; }
    export -f brew

    run manifest_install_paths_ensure_brew_trust
    [ "$status" -eq 2 ]
}

@test "tap-trust: reports failure when trust is supported but the call fails" {
    brew() {
        [ "$1" = "trust" ] && [ "$2" = "--help" ] && return 0
        [ "$1" = "trust" ] && [ "$2" = "--formula" ] && return 1
        return 0
    }
    export -f brew

    run manifest_install_paths_ensure_brew_trust
    [ "$status" -eq 1 ]
}

@test "tap-trust: skips when brew is absent from PATH" {
    # A PATH with standard tools but no brew (Homebrew lives under /opt/homebrew
    # or /usr/local, not /usr/bin or /bin) → command -v brew fails → rc 2.
    run bash -c "PATH=/usr/bin:/bin; source '$TEST_REPO_ROOT/modules/system/manifest-install-paths.sh'; manifest_install_paths_ensure_brew_trust; echo rc=\$?"
    [[ "$output" == *"rc=2"* ]]
}

# --- §7.6: every brew (re)install/upgrade chokepoint routes through the helper.
# Structural guards: the trust call must precede the executable brew command in
# each site, so a future edit that adds a brew install/upgrade without trusting
# first (→ silent no-op under enforced tap-trust) trips a red test.

# Echo the 1-based line of the first match of $2 in file $1, or empty.
_first_line() { grep -nE "$2" "$1" | head -1 | cut -d: -f1; }

@test "tap-trust: installer trusts before brew install/upgrade" {
    f="$TEST_REPO_ROOT/install-cli.sh"
    t="$(_first_line "$f" 'manifest_install_paths_ensure_brew_trust')"
    b="$(_first_line "$f" 'brew (install|upgrade) "\$brew_formula"')"
    [ -n "$t" ] && [ -n "$b" ]
    [ "$t" -lt "$b" ]
}

@test "tap-trust: reinstall trusts before brew reinstall/install" {
    f="$TEST_REPO_ROOT/modules/core/manifest-core.sh"
    t="$(_first_line "$f" 'manifest_install_paths_ensure_brew_trust')"
    b="$(_first_line "$f" 'brew reinstall fidenceio/tap/manifest')"
    [ -n "$t" ] && [ -n "$b" ]
    [ "$t" -lt "$b" ]
}

@test "tap-trust: ship self-upgrade trusts before brew upgrade" {
    f="$TEST_REPO_ROOT/modules/workflow/manifest-orchestrator.sh"
    t="$(_first_line "$f" 'manifest_install_paths_ensure_brew_trust')"
    b="$(_first_line "$f" '&& brew upgrade manifest 2>&1')"
    [ -n "$t" ] && [ -n "$b" ]
    [ "$t" -lt "$b" ]
}
