#!/usr/bin/env bats

# Fleet-root versioning: _fleet_next_version + _fleet_root_release.
# Security focus: the fleet-root commit stages ONLY coordination files — never
# member repos, source, or secrets — even when junk is present/staged at the root.

load 'helpers/setup'

setup() {
    load_modules
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-shared-utils.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-yaml.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-discovery.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/fleet/manifest-fleet.sh"
    # Real cross-platform formatter (manifest-os.sh) + time API (manifest-time.sh).
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-os.sh"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/system/manifest-time.sh"

    # Stub the trusted-time service with a fixed epoch so the date scheme is
    # hermetic (no NTP/HTTPS network call) and deterministic. Defined AFTER the
    # source above so it overrides the real fetch; `format_timestamp` stays real.
    get_time_timestamp() { MANIFEST_CLI_TIME_TIMESTAMP=1700000000; return 0; }

    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH-home"; mkdir -p "$HOME"
    export HOME SCRATCH
    cd "$SCRATCH"
}

teardown() { rm -rf "$SCRATCH" "$SCRATCH-home" "$SCRATCH-remote.git"; }

# Build a fleet root: git repo + allowlist + config; export the fleet env vars.
mk_fleet_root() {
    local scheme="${1:-date}" current="${2:-}"
    git init -q -b main "$SCRATCH"
    git -C "$SCRATCH" config user.email test@example.com
    git -C "$SCRATCH" config user.name "Test"
    create_fleet_gitignore "$SCRATCH" >/dev/null
    cat > "$SCRATCH/manifest.fleet.config.yaml" <<YAML
fleet:
  name: "test"
  versioning: "$scheme"
  version_file: "FLEET_VERSION"
YAML
    export MANIFEST_CLI_FLEET_ROOT="$SCRATCH"
    export MANIFEST_CLI_FLEET_CONFIG_FILE="$SCRATCH/manifest.fleet.config.yaml"
    export MANIFEST_CLI_FLEET_VERSIONING="$scheme"
    # MANIFEST_CLI_FLEET_DEFAULT_VERSION_FILE is a readonly constant (= "FLEET_VERSION"); don't reassign.
    export MANIFEST_CLI_FLEET_VERSION="$current"
}

@test "_fleet_next_version date: emits a full trusted-time UTC timestamp; ignores current" {
    local expected; expected="$(format_timestamp 1700000000 '+%Y.%m.%d.%H%M%S')"
    [ "$(_fleet_next_version date "")" = "$expected" ]
    # `current` is ignored — each bump is a fresh stamp, not derived from the prior value.
    [ "$(_fleet_next_version date "2026.06.21")" = "$expected" ]
    [ "$(_fleet_next_version date "2020.01.01.000000")" = "$expected" ]
    # Shape: YYYY.MM.DD.HHMMSS — tag-safe (digits and dots only).
    [[ "$expected" =~ ^[0-9]{4}\.[0-9]{2}\.[0-9]{2}\.[0-9]{6}$ ]]
    # A fresh timestamp still sorts lexically above a legacy date-only FLEET_VERSION.
    [[ "2026.06.22.000000" > "2026.06.21" ]]
}

@test "_fleet_next_version semver: patch/minor/major/empty" {
    [ "$(_fleet_next_version semver 1.2.3 patch)" = "1.2.4" ]
    [ "$(_fleet_next_version semver 1.2.3 minor)" = "1.3.0" ]
    [ "$(_fleet_next_version semver 1.2.3 major)" = "2.0.0" ]
    [ "$(_fleet_next_version semver "" patch)" = "0.0.1" ]
}

@test "_fleet_next_version increment and none" {
    [ "$(_fleet_next_version increment 4)" = "5" ]
    [ "$(_fleet_next_version increment "")" = "1" ]
    [ -z "$(_fleet_next_version none 1.0.0 patch)" ]
}

@test "_fleet_root_release (date, apply) commits ONLY coordination files — never secrets" {
    mk_fleet_root date ""
    mkdir -p "$SCRATCH/secure" "$SCRATCH/apps/member"
    echo 'Password=hunter2' > "$SCRATCH/secure/appsettings.production.json"
    echo 'src' > "$SCRATCH/apps/member/code.cs"

    run _fleet_root_release patch apply false 1
    [ "$status" -eq 0 ]

    local expected; expected="$(format_timestamp 1700000000 '+%Y.%m.%d.%H%M%S')"
    [ "$(cat "$SCRATCH/FLEET_VERSION")" = "$expected" ]

    run git -C "$SCRATCH" ls-tree -r --name-only HEAD
    [[ "$output" == *"FLEET_VERSION"* ]]
    [[ "$output" == *".gitignore"* ]]
    [[ "$output" != *"secure/"* ]]      # SECURITY: secret never committed
    [[ "$output" != *"apps/member"* ]]  # member source never committed
}

@test "_fleet_root_release ABORTS if a non-coordination file is staged (defense-in-depth guard)" {
    mk_fleet_root date ""
    mkdir -p "$SCRATCH/secure"
    echo 'Password=x' > "$SCRATCH/secure/leak.json"
    git -C "$SCRATCH" add -f -- secure/leak.json   # simulate a stray staged secret

    run _fleet_root_release patch apply false 1
    [ "$status" -ne 0 ]
    [[ "$output" == *"ABORTED"* ]]
    # the index was reset and nothing was committed
    run git -C "$SCRATCH" rev-parse -q --verify HEAD
    [ "$status" -ne 0 ]
}

@test "_fleet_root_release preview writes nothing" {
    mk_fleet_root date ""
    run _fleet_root_release patch preview false 1
    [ "$status" -eq 0 ]
    [[ "$output" == *"would bump fleet version"* ]]
    [ ! -f "$SCRATCH/FLEET_VERSION" ]
    run git -C "$SCRATCH" rev-parse -q --verify HEAD
    [ "$status" -ne 0 ]                 # no commit
}

@test "_fleet_root_release no-op when no member shipped (completed=0)" {
    mk_fleet_root date ""
    run _fleet_root_release patch apply false 0
    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/FLEET_VERSION" ]
    run git -C "$SCRATCH" rev-parse -q --verify HEAD
    [ "$status" -ne 0 ]
}

@test "_fleet_root_release no-op for versioning=none" {
    mk_fleet_root none ""
    run _fleet_root_release patch apply false 1
    [ "$status" -eq 0 ]
    [ ! -f "$SCRATCH/FLEET_VERSION" ]
}

@test "_fleet_root_release --local commits but does not push" {
    mk_fleet_root date ""
    git init -q --bare "$SCRATCH-remote.git"
    git -C "$SCRATCH" remote add origin "$SCRATCH-remote.git"

    run _fleet_root_release patch apply true 1
    [ "$status" -eq 0 ]
    run git -C "$SCRATCH" rev-list --count HEAD
    [ "$output" = "1" ]                 # local commit exists
    run git -C "$SCRATCH-remote.git" rev-list --count --all
    [ "$output" = "0" ]                 # remote received nothing
}
