#!/usr/bin/env bats

# TRACKER §2(c) — `security.private_files` written as a YAML list silently
# narrowed the security scan to one bogus filename.
#
# THE DEFECT, in two halves, and both are guarded here.
#
# LOADER HALF. `load_yaml_to_env` handed every list-valued mapped key to its
# consumers as yq's rendering of the SEQUENCE node — "- .env\n- mysecret.txt"
# for a block list, "[\".env\", \"mysecret.txt\"]" for a flow one. Every
# consumer of those keys parses a COMMA STRING with `IFS=',' read -r -a`
# (manifest-security.sh:72, manifest-shared-functions.sh:149 and :360,
# manifest-git.sh:281), and `read` stops at the first newline. A user who wrote
# the key as a YAML list therefore got ONE entry — the literal string "- .env",
# a filename that cannot exist — and `manifest security` printed
# "✅ No private files are being tracked by Git" over tracked secrets, while
# `manifest config get security.private_files` printed the list back correctly,
# so the user's own verification step confirmed a config the scanner was not
# using. tests/config_crud.bats:229-245 blesses the block-list form for exactly
# this key, so the suite endorsed the shape the loader mangled.
#
# CONSUMER HALF. `_manifest_security_private_env_files` now REFUSES a value it
# cannot split and returns 1, and both callers resolve the list into a variable
# and check that status. `done < <(producer)` cannot see a producer's exit
# status, so before the fix a refusal would have arrived as an empty list and
# been reported as a clean repository — the same silent narrowing one layer up.
# This half is not redundant with the loader half: the process environment is
# the highest-precedence config layer (_manifest_config_apply_process_env_over-
# rides re-applies it on top of every YAML file), so an exported
# MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES never passes through the loader at
# all. The exported-env tests below are the ones that isolate it.
#
# TWO MEASUREMENT CHOICES, both deliberate, because each has a failure mode
# that reads as a pass.
#
# 1. Every regression test scans for `mysecret.txt`, which is NOT in the
#    module's built-in default list (manifest-security.sh:12/:46 — `.env`,
#    `.env.development`, `.env.test`, `.env.production`, `.env.staging`,
#    `manifest.config.local.yaml`). If the loader exported nothing at all, the
#    built-in array would still be in force and a scan for `.env` would catch a
#    tracked `.env` for entirely the wrong reason. Measured 2026-08-25: that is
#    not hypothetical — an earlier draft of this fix shipped an invalid yq
#    expression, exported NOTHING for a list-valued key, and every `.env`-based
#    assertion passed anyway off the built-in default. `mysecret.txt` cannot
#    pass that way. The one test that uses the documented `.env,mysecret.txt`
#    pair is the positive control, whose whole job is to pass.
#
# 2. The loader is exercised through BOTH of its paths. `_load_yaml_to_env_batch`
#    (one yq walk for the file) handles the common case; the per-key loop is the
#    fallback. A fix applied to only one of them looks complete against ordinary
#    fixtures, because ordinary fixtures never reach the fallback. A YAML merge
#    key ("<<") forces it, which is how the block-list-survives-the-fallback
#    test gets there without stubbing anything.

load 'helpers/setup'

setup() {
    command -v yq >/dev/null 2>&1 || skip "yq not available"
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
    # HOME must be isolated before sourcing: manifest-config.sh resolves
    # MANIFEST_CLI_GLOBAL_CONFIG from $HOME at source time.
    load_modules "core/manifest-config.sh" "system/manifest-security.sh"
    PROJ="$SCRATCH/proj"
    mkdir -p "$PROJ"
    git -C "$PROJ" init -q
    export MANIFEST_CLI_PROJECT_ROOT="$PROJ"
    cd "$PROJ"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_PROJECT_ROOT MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES
}

# Create $1 in the fixture repo and commit it, so `git ls-files
# --error-unmatch` reports it tracked.
track_file() {
    printf 'SECRET=1\n' > "$PROJ/$1"
    git -C "$PROJ" add -- "$1"
    git -C "$PROJ" -c user.name=t -c user.email=t@t commit -qm "add $1"
}

write_project_config() {
    printf '%s' "$1" > "$PROJ/manifest.config.yaml"
}

# Put a SCALAR value in MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES.
#
# The unset is load-bearing, not tidiness. manifest-security.sh:12 declares the
# variable as a bash ARRAY at source time, and `export VAR=x` on an
# array-declared name assigns element 0 and leaves the name array-typed — so a
# bare export would take the splitter's `declare -a` branch and never reach the
# comma path at all. Production does exactly this unset:
# _manifest_config_apply_process_env_overrides (manifest-config.sh:79-83) tests
# `declare -p` and unsets an array before exporting the process-env value.
set_private_files_env() {
    unset MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES
    export MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES="$1"
}

# Load a project config in a clean child process and print the resolved
# private-file list, one per line. A child rather than this process because
# load_configuration exports into whatever shell runs it, and comparing three
# spellings needs three independent resolutions.
private_files_after_load() {
    local body="$1" name="$2"
    local proj="$SCRATCH/load-$name"
    mkdir -p "$proj"
    printf '%s' "$body" > "$proj/manifest.config.yaml"
    env HOME="$SCRATCH/home" MANIFEST_CLI_PROJECT_ROOT="$proj" \
        bash -c 'source "$1/tests/helpers/setup.bash"
                 load_modules "core/manifest-config.sh" "system/manifest-security.sh"
                 load_configuration "$MANIFEST_CLI_PROJECT_ROOT" "true" >/dev/null 2>&1
                 _manifest_security_private_env_files' _ "$TEST_REPO_ROOT"
}

# ---------------------------------------------------------------------------
# Positive controls. These MUST pass on the unfixed code — without them,
# "no leak observed" below is indistinguishable from a fixture that never
# fired (TRACKER §5's protocol, step 2).
# ---------------------------------------------------------------------------

@test "positive control: the documented comma form catches two tracked private files" {
    track_file ".env"
    track_file "mysecret.txt"
    set_private_files_env ".env,mysecret.txt"

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "is tracked by Git"
}

@test "positive control: the CONFIGURED list, not the built-in default, is what gets scanned" {
    # mysecret.txt is absent from the built-in default list, so catching it
    # proves the configured value reached the scan. Without this, every
    # assertion below could be satisfied by the default array alone.
    track_file "mysecret.txt"
    set_private_files_env "mysecret.txt"

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mysecret.txt is tracked by Git"
}

@test "positive control: a clean repo passes the same scan" {
    # The discriminator for every refusal test: this fixture proves a pass is
    # reachable, so a non-zero status elsewhere means something was detected
    # rather than that the check can only ever fail.
    set_private_files_env "mysecret.txt"

    run check_git_tracking "$PROJ"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# The three YAML spellings, end to end: config file -> loader -> scan.
# ---------------------------------------------------------------------------

@test "block-list config: a tracked private file is still caught" {
    track_file "mysecret.txt"
    write_project_config 'security:
  private_files:
    - mysecret.txt
    - other.txt
'
    load_configuration "$PROJ" "true" >/dev/null 2>&1

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mysecret.txt is tracked by Git"
}

@test "flow-list config: a tracked private file is still caught" {
    track_file "mysecret.txt"
    write_project_config 'security:
  private_files: ["mysecret.txt", "other.txt"]
'
    load_configuration "$PROJ" "true" >/dev/null 2>&1

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mysecret.txt is tracked by Git"
}

# ---------------------------------------------------------------------------
# Loader level: the three spellings must MEAN the same thing.
# ---------------------------------------------------------------------------

@test "loader: comma, block and flow spellings all resolve to the identical two entries" {
    local expected=$'.env\nmysecret.txt'
    local comma block flow

    comma="$(private_files_after_load 'security:
  private_files: ".env,mysecret.txt"
' comma)"
    block="$(private_files_after_load 'security:
  private_files:
    - .env
    - mysecret.txt
' block)"
    flow="$(private_files_after_load 'security:
  private_files: [".env", "mysecret.txt"]
' flow)"

    [ "$comma" = "$expected" ]
    [ "$block" = "$expected" ]
    [ "$flow" = "$expected" ]
}

@test "loader: the per-key fallback applies the same join as the batch walk" {
    # A YAML merge key disqualifies the one-walk fast path
    # (_load_yaml_to_env_batch returns 1 on a "<<" path component), so this
    # fixture reaches the per-key loop for real rather than by stubbing.
    write_project_config '_anchor: &base
  keep: 1
_merged:
  <<: *base
security:
  private_files:
    - .env
    - mysecret.txt
'
    run bash -c 'source "$1/tests/helpers/setup.bash"
                 load_modules >/dev/null 2>&1
                 set +e
                 _load_yaml_to_env_batch "$2" >/dev/null 2>&1
                 echo "batch=$?"' _ "$TEST_REPO_ROOT" "$PROJ/manifest.config.yaml"
    [ "$status" -eq 0 ]
    # Control on the control: if the merge key ever stops disqualifying the
    # batch walk, this test would silently stop testing the fallback.
    [ "$output" = "batch=1" ]

    unset MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES
    load_yaml_to_env "$PROJ/manifest.config.yaml" >/dev/null 2>&1
    [ "$MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES" = ".env,mysecret.txt" ]
}

# ---------------------------------------------------------------------------
# The unrepresentable case: a list with no comma encoding at all.
# ---------------------------------------------------------------------------

@test "loader: a list of maps is refused loudly, naming the key and the file" {
    write_project_config 'security:
  private_files:
    - name: .env
      why: secret
'
    run load_yaml_to_env "$PROJ/manifest.config.yaml"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "security.private_files"
    echo "$output" | grep -q "$PROJ/manifest.config.yaml"
    echo "$output" | grep -q "list containing maps or nested lists"
}

@test "loader: a nested list is refused too, and nothing is exported" {
    write_project_config 'security:
  private_files:
    - [".env", "mysecret.txt"]
'
    unset MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES
    run load_yaml_to_env "$PROJ/manifest.config.yaml"
    [ "$status" -eq 2 ]
    # The refusal must not be a refusal-plus-partial-export.
    [ -z "${MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES:-}" ]
}

@test "loader: the per-key fallback refuses an unrepresentable list as well" {
    # Isolates the fallback branch. There is no YAML that reaches it naturally
    # for this case: the batch walk emits every !!seq record before any scalar
    # record, so its own sentinel check always fires before it can notice a
    # merge key and bail. Stubbing the batch away is the only honest route.
    write_project_config 'security:
  private_files:
    - name: .env
'
    _load_yaml_to_env_batch() { return 1; }

    run load_yaml_to_env "$PROJ/manifest.config.yaml"
    [ "$status" -eq 2 ]
    echo "$output" | grep -q "security.private_files"
}

@test "loader: load_configuration propagates the refusal instead of loading defaults" {
    write_project_config 'security:
  private_files:
    - name: .env
'
    run load_configuration "$PROJ" "true"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "security.private_files"
}

@test "loader: an UNMAPPED list of maps is not refused" {
    # Guard against over-refusal. Fleet repo tables and similar structures are
    # lists of maps by design; they are not mapped keys, so this loader has no
    # opinion about them and must not turn a working config into a hard failure.
    write_project_config 'repositories:
  - name: alpha
    path: ../alpha
  - name: beta
    path: ../beta
git:
  tag_prefix: v
'
    run load_yaml_to_env "$PROJ/manifest.config.yaml"
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# The exported-env route. This bypasses the loader entirely and is the reason
# the consumer keeps a guard of its own.
# ---------------------------------------------------------------------------

@test "exported env: a multi-line value makes the scan REFUSE, not report clean" {
    track_file "mysecret.txt"
    set_private_files_env $'- .env\n- mysecret.txt'

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "scan NOT performed"
    # The exact failure mode this exists to prevent: a refusal that reads as a
    # clean repository. Nothing may claim the tracked file was checked and fine.
    refute grep -q "No private files" <<<"$output"
}

@test "exported env: a flow-sequence residue value makes the scan REFUSE" {
    track_file "mysecret.txt"
    set_private_files_env '[".env", "mysecret.txt"]'

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "scan NOT performed"
}

@test "exported env: a single-line block-marker value makes the scan REFUSE" {
    track_file "mysecret.txt"
    set_private_files_env '- mysecret.txt'

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "scan NOT performed"
}

@test "exported env: a legitimate comma value with whitespace is still accepted" {
    # The guard must reject YAML residue without rejecting the documented form.
    # Without this, tightening the refusal into "refuse everything" would pass
    # every test above.
    track_file "mysecret.txt"
    set_private_files_env ".env , mysecret.txt"

    run _manifest_security_private_env_files
    [ "$status" -eq 0 ]
    [ "$output" = $'.env\nmysecret.txt' ]

    run check_git_tracking "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mysecret.txt is tracked by Git"
}

@test "exported env: the real process-env route reaches the refusal, outranking good YAML" {
    # The three tests above set the variable inside this process, which isolates
    # the consumer guard but assumes the shape can actually get there. This one
    # proves the route: a malformed value present in the process environment
    # BEFORE any module is sourced, a project config carrying a perfectly good
    # list, and load_configuration in between. The env layer is the
    # highest-precedence source, so the refusal — not the YAML — is what the
    # scan must see. This is the case the loader half cannot cover, because the
    # value never passes through the loader at all.
    track_file "mysecret.txt"
    write_project_config 'security:
  private_files:
    - mysecret.txt
'
    run env HOME="$SCRATCH/home" MANIFEST_CLI_PROJECT_ROOT="$PROJ" \
        MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES=$'- .env\n- mysecret.txt' \
        bash -c 'source "$1/tests/helpers/setup.bash"
                 load_modules "core/manifest-config.sh" "system/manifest-security.sh"
                 load_configuration "$MANIFEST_CLI_PROJECT_ROOT" "true" >/dev/null 2>&1
                 set +e
                 check_git_tracking "$MANIFEST_CLI_PROJECT_ROOT"
                 echo "rc=$?"' _ "$TEST_REPO_ROOT"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "rc=1"
    echo "$output" | grep -q "scan NOT performed"
}

# ---------------------------------------------------------------------------
# The second consumer. Same producer, same failure mode, separate call site.
# ---------------------------------------------------------------------------

@test "check_environment_file_security: a malformed exported list makes it REFUSE" {
    printf 'SECRET=1\n' > "$PROJ/mysecret.txt"
    set_private_files_env $'- .env\n- mysecret.txt'

    run check_environment_file_security "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "scan NOT performed"
}

@test "check_environment_file_security: a block-list config still flags an unignored private file" {
    printf 'SECRET=1\n' > "$PROJ/mysecret.txt"
    write_project_config 'security:
  private_files:
    - mysecret.txt
'
    load_configuration "$PROJ" "true" >/dev/null 2>&1

    run check_environment_file_security "$PROJ"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "mysecret.txt exists but is NOT ignored by Git"
}

@test "positive control: check_environment_file_security passes when the file IS ignored" {
    printf 'SECRET=1\n' > "$PROJ/mysecret.txt"
    printf 'mysecret.txt\n' > "$PROJ/.gitignore"
    write_project_config 'security:
  private_files:
    - mysecret.txt
'
    load_configuration "$PROJ" "true" >/dev/null 2>&1

    run check_environment_file_security "$PROJ"
    [ "$status" -eq 0 ]
}
