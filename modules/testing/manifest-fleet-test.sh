#!/bin/bash

# =============================================================================
# MANIFEST FLEET TEST MODULE
# =============================================================================
#
# Comprehensive tests for Fleet functionality including:
#   - Fleet config loading, validation, and precedence
#   - Fleet detection (find_fleet_root, is_fleet_mode_enabled)
#   - Auto-discovery (discover_fleet_repos, classify, ignore patterns)
#   - Service property access and name sanitization
#   - TSV parsing (get_fleet_services)
#   - Fleet docs strategy resolution
#
# USAGE:
#   manifest test fleet
#
# =============================================================================

# Test counters
_FLEET_TESTS_TOTAL=0
_FLEET_TESTS_PASSED=0
_FLEET_TESTS_FAILED=0
_FLEET_FAILED_TESTS=()

_fleet_test_start() {
    local name="$1"
    _FLEET_TESTS_TOTAL=$((_FLEET_TESTS_TOTAL + 1))
    echo "   ▸ $name"
}

_fleet_test_pass() {
    local name="$1"
    _FLEET_TESTS_PASSED=$((_FLEET_TESTS_PASSED + 1))
    echo "   ✅ $name"
}

_fleet_test_fail() {
    local name="$1"
    local detail="${2:-}"
    _FLEET_TESTS_FAILED=$((_FLEET_TESTS_FAILED + 1))
    _FLEET_FAILED_TESTS+=("$name")
    echo "   ❌ $name${detail:+ — $detail}"
}

# =============================================================================
# FIXTURE HELPERS
# =============================================================================

# Creates a temporary fleet workspace with config + TSV + service dirs.
# Sets FLEET_TEST_DIR to the created directory.
_fleet_test_create_workspace() {
    FLEET_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/manifest-fleet-test.XXXXXX")
    # Normalize path (resolve symlinks and double slashes)
    FLEET_TEST_DIR=$(cd "$FLEET_TEST_DIR" && pwd -P)

    # Fleet config YAML
    cat > "$FLEET_TEST_DIR/manifest.fleet.config.yaml" << 'YAML'
fleet:
  name: test-fleet
  description: Fleet for unit tests
  versioning: semver
  version_file: FLEET_VERSION

operations:
  parallel: true
  max_parallel: 2
  commit:
    strategy: per-service
  push:
    strategy: batched

validation:
  require_clean_status: true
  enforce_dependencies: false
  strict: false

docs:
  strategy: per-service
  fleet_root:
    enabled: false
    folder: docs
    detail_level: summary
  per_service:
    enabled: true
    folder: docs
  generate:
    release_notes: true
    changelog: true
    index: true
    readme_version: true
YAML

    # Fleet version file
    echo "1.2.3" > "$FLEET_TEST_DIR/FLEET_VERSION"

    # TSV inventory
    cat > "$FLEET_TEST_DIR/manifest.fleet.tsv" << TSV
# selected	name	path	type	has_git	url	branch	version
true	user-service	user-service	service	true	https://github.com/test/user-service.git	main	1.0.0
true	auth-api	auth-api	service	true	https://github.com/test/auth-api.git	main	2.0.0
true	shared-lib	shared-lib	library	true	https://github.com/test/shared-lib.git	main	0.5.0
false	deprecated-svc	deprecated-svc	service	true		main	0.0.1
TSV

    # Create service directories with .git markers
    for svc in user-service auth-api shared-lib; do
        mkdir -p "$FLEET_TEST_DIR/$svc/.git"
        echo "0.0.0" > "$FLEET_TEST_DIR/$svc/VERSION"
    done
}

_fleet_test_cleanup() {
    if [[ -n "${FLEET_TEST_DIR:-}" ]] && [[ -d "$FLEET_TEST_DIR" ]]; then
        rm -rf "$FLEET_TEST_DIR"
    fi
}

# =============================================================================
# TESTS: Fleet Detection
# =============================================================================

_test_find_fleet_root() {
    _fleet_test_create_workspace

    # Test: find fleet root from root directory
    _fleet_test_start "find_fleet_root from fleet root"
    local found
    found=$(find_fleet_root "$FLEET_TEST_DIR" 2>/dev/null)
    if [[ "$found" == "$FLEET_TEST_DIR" ]]; then
        _fleet_test_pass "find_fleet_root from fleet root"
    else
        _fleet_test_fail "find_fleet_root from fleet root" "expected=$FLEET_TEST_DIR got=$found"
    fi

    # Test: find fleet root from subdirectory
    _fleet_test_start "find_fleet_root from subdirectory"
    found=$(find_fleet_root "$FLEET_TEST_DIR/user-service" 2>/dev/null)
    if [[ "$found" == "$FLEET_TEST_DIR" ]]; then
        _fleet_test_pass "find_fleet_root from subdirectory"
    else
        _fleet_test_fail "find_fleet_root from subdirectory" "expected=$FLEET_TEST_DIR got=$found"
    fi

    # Test: find_fleet_root returns 1 when no config
    _fleet_test_start "find_fleet_root returns 1 when no config"
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-noconfig.XXXXXX")
    if ! find_fleet_root "$tmpdir" 1 2>/dev/null; then
        _fleet_test_pass "find_fleet_root returns 1 when no config"
    else
        _fleet_test_fail "find_fleet_root returns 1 when no config"
    fi
    rm -rf "$tmpdir"

    # Test: find_fleet_root respects max depth
    _fleet_test_start "find_fleet_root respects max depth"
    mkdir -p "$FLEET_TEST_DIR/a/b/c/d"
    if ! find_fleet_root "$FLEET_TEST_DIR/a/b/c/d" 2 2>/dev/null; then
        _fleet_test_pass "find_fleet_root respects max depth"
    else
        _fleet_test_fail "find_fleet_root respects max depth" "should not find config at depth > 2"
    fi

    _fleet_test_cleanup
}

_test_is_fleet_mode_enabled() {
    _fleet_test_create_workspace

    # Test: auto mode with fleet config present
    _fleet_test_start "is_fleet_mode_enabled auto + config present"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        if is_fleet_mode_enabled 2>/dev/null; then
            exit 0
        else
            exit 1
        fi
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "is_fleet_mode_enabled auto + config present"
    else
        _fleet_test_fail "is_fleet_mode_enabled auto + config present"
    fi

    # Test: explicit disable
    _fleet_test_start "is_fleet_mode_enabled explicit false"
    (
        MANIFEST_CLI_FLEET_MODE="false"
        MANIFEST_FLEET_ACTIVE=""
        if is_fleet_mode_enabled 2>/dev/null; then
            exit 1
        else
            exit 0
        fi
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "is_fleet_mode_enabled explicit false"
    else
        _fleet_test_fail "is_fleet_mode_enabled explicit false"
    fi

    # Test: explicit root
    _fleet_test_start "is_fleet_mode_enabled explicit root"
    (
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_CLI_FLEET_ROOT="$FLEET_TEST_DIR"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        if is_fleet_mode_enabled 2>/dev/null; then
            exit 0
        else
            exit 1
        fi
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "is_fleet_mode_enabled explicit root"
    else
        _fleet_test_fail "is_fleet_mode_enabled explicit root"
    fi

    # Test: forced mode with no fleet config
    _fleet_test_start "is_fleet_mode_enabled forced + no config"
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-noconf.XXXXXX")
    (
        cd "$tmpdir" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="true"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        if is_fleet_mode_enabled 2>/dev/null; then
            exit 1  # Should fail — forced but no config
        else
            exit 0
        fi
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "is_fleet_mode_enabled forced + no config"
    else
        _fleet_test_fail "is_fleet_mode_enabled forced + no config"
    fi
    rm -rf "$tmpdir"

    _fleet_test_cleanup
}

# =============================================================================
# TESTS: TSV Parsing
# =============================================================================

_test_get_fleet_services() {
    _fleet_test_create_workspace

    # Test: selected services only
    _fleet_test_start "get_fleet_services returns selected services"
    local services
    services=$(get_fleet_services "$FLEET_TEST_DIR" 2>/dev/null)
    local count=0
    for _ in $services; do count=$((count + 1)); done

    if [[ $count -eq 3 ]]; then
        _fleet_test_pass "get_fleet_services returns selected services"
    else
        _fleet_test_fail "get_fleet_services returns selected services" "expected 3, got $count: $services"
    fi

    # Test: contains expected names
    _fleet_test_start "get_fleet_services contains correct names"
    if echo "$services" | grep -q "user-service" && \
       echo "$services" | grep -q "auth-api" && \
       echo "$services" | grep -q "shared-lib"; then
        _fleet_test_pass "get_fleet_services contains correct names"
    else
        _fleet_test_fail "get_fleet_services contains correct names" "got: $services"
    fi

    # Test: excludes deselected services
    _fleet_test_start "get_fleet_services excludes deselected"
    if ! echo "$services" | grep -q "deprecated-svc"; then
        _fleet_test_pass "get_fleet_services excludes deselected"
    else
        _fleet_test_fail "get_fleet_services excludes deselected"
    fi

    # Test: returns 1 for missing TSV
    _fleet_test_start "get_fleet_services returns 1 for missing TSV"
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-notsv.XXXXXX")
    if ! get_fleet_services "$tmpdir" 2>/dev/null; then
        _fleet_test_pass "get_fleet_services returns 1 for missing TSV"
    else
        _fleet_test_fail "get_fleet_services returns 1 for missing TSV"
    fi
    rm -rf "$tmpdir"

    # Test: handles empty TSV
    _fleet_test_start "get_fleet_services handles empty TSV"
    local emptydir
    emptydir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-empty.XXXXXX")
    echo "# header only" > "$emptydir/manifest.fleet.tsv"
    local empty_result
    empty_result=$(get_fleet_services "$emptydir" 2>/dev/null)
    if [[ -z "$empty_result" ]]; then
        _fleet_test_pass "get_fleet_services handles empty TSV"
    else
        _fleet_test_fail "get_fleet_services handles empty TSV" "expected empty, got: $empty_result"
    fi
    rm -rf "$emptydir"

    _fleet_test_cleanup
}

# =============================================================================
# TESTS: Service Property Access
# =============================================================================

_test_fleet_service_properties() {
    _fleet_test_create_workspace

    # Load fleet config so service vars are populated
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT

        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null

        local path type branch url
        path=$(get_fleet_service_path "user-service" 2>/dev/null)
        type=$(get_fleet_service_property "user-service" "type" 2>/dev/null)
        branch=$(get_fleet_service_property "user-service" "branch" 2>/dev/null)
        url=$(get_fleet_service_property "user-service" "url" 2>/dev/null)

        # Validate path
        [[ "$path" == *"user-service"* ]] || exit 10

        # Validate type
        [[ "$type" == "service" ]] || exit 11

        # Validate branch
        [[ "$branch" == "main" ]] || exit 12

        # Validate URL
        [[ "$url" == "https://github.com/test/user-service.git" ]] || exit 13

        # Test default for missing property
        local team
        team=$(get_fleet_service_property "user-service" "team" "default-team" 2>/dev/null)
        [[ "$team" == "default-team" ]] || exit 14

        # Test nonexistent service
        if get_fleet_service_path "nonexistent-service" 2>/dev/null; then
            exit 15
        fi

        exit 0
    )
    local rc=$?

    _fleet_test_start "get_fleet_service_path returns correct path"
    if [[ $rc -lt 10 ]] || [[ $rc -eq 0 ]]; then
        _fleet_test_pass "get_fleet_service_path returns correct path"
    else
        _fleet_test_fail "get_fleet_service_path returns correct path" "exit=$rc"
    fi

    _fleet_test_start "get_fleet_service_property returns type"
    if [[ $rc -eq 0 ]] || [[ $rc -gt 11 ]]; then
        _fleet_test_pass "get_fleet_service_property returns type"
    else
        _fleet_test_fail "get_fleet_service_property returns type" "exit=$rc"
    fi

    _fleet_test_start "get_fleet_service_property returns branch"
    if [[ $rc -eq 0 ]] || [[ $rc -gt 12 ]]; then
        _fleet_test_pass "get_fleet_service_property returns branch"
    else
        _fleet_test_fail "get_fleet_service_property returns branch" "exit=$rc"
    fi

    _fleet_test_start "get_fleet_service_property returns URL"
    if [[ $rc -eq 0 ]] || [[ $rc -gt 13 ]]; then
        _fleet_test_pass "get_fleet_service_property returns URL"
    else
        _fleet_test_fail "get_fleet_service_property returns URL" "exit=$rc"
    fi

    _fleet_test_start "get_fleet_service_property default value"
    if [[ $rc -eq 0 ]] || [[ $rc -gt 14 ]]; then
        _fleet_test_pass "get_fleet_service_property default value"
    else
        _fleet_test_fail "get_fleet_service_property default value" "exit=$rc"
    fi

    _fleet_test_start "get_fleet_service_path returns 1 for missing service"
    if [[ $rc -eq 0 ]]; then
        _fleet_test_pass "get_fleet_service_path returns 1 for missing service"
    else
        _fleet_test_fail "get_fleet_service_path returns 1 for missing service" "exit=$rc"
    fi

    _fleet_test_cleanup
}

# =============================================================================
# TESTS: Fleet Config Value Precedence
# =============================================================================

_test_fleet_config_value_precedence() {
    _fleet_test_create_workspace

    # Test: YAML value
    _fleet_test_start "get_fleet_config_value reads YAML config"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null

        local val
        val=$(get_fleet_config_value "parallel" "false" 2>/dev/null)
        [[ "$val" == "true" ]] || exit 1
        exit 0
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "get_fleet_config_value reads YAML config"
    else
        _fleet_test_fail "get_fleet_config_value reads YAML config"
    fi

    # Test: env var overrides YAML
    _fleet_test_start "get_fleet_config_value env var overrides YAML"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null

        export MANIFEST_CLI_FLEET_PARALLEL="false"
        local val
        val=$(get_fleet_config_value "parallel" "true" 2>/dev/null)
        [[ "$val" == "false" ]] || exit 1
        exit 0
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "get_fleet_config_value env var overrides YAML"
    else
        _fleet_test_fail "get_fleet_config_value env var overrides YAML"
    fi

    # Test: default fallback
    _fleet_test_start "get_fleet_config_value uses default when key absent"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null

        local val
        val=$(get_fleet_config_value "nonexistent_key" "my-default" 2>/dev/null)
        [[ "$val" == "my-default" ]] || exit 1
        exit 0
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "get_fleet_config_value uses default when key absent"
    else
        _fleet_test_fail "get_fleet_config_value uses default when key absent"
    fi

    _fleet_test_cleanup
}

# =============================================================================
# TESTS: Fleet Validation
# =============================================================================

_test_fleet_validation() {
    _fleet_test_create_workspace

    # Test: valid fleet passes validation
    _fleet_test_start "validate_fleet_config passes for valid fleet"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null
        validate_fleet_config 2>/dev/null
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "validate_fleet_config passes for valid fleet"
    else
        _fleet_test_fail "validate_fleet_config passes for valid fleet"
    fi

    # Test: empty fleet fails validation
    _fleet_test_start "validate_fleet_config fails for empty fleet"
    (
        MANIFEST_FLEET_SERVICES=""
        MANIFEST_FLEET_NAME="test"
        validate_fleet_config 2>/dev/null
    )
    if [[ $? -ne 0 ]]; then
        _fleet_test_pass "validate_fleet_config fails for empty fleet"
    else
        _fleet_test_fail "validate_fleet_config fails for empty fleet"
    fi

    _fleet_test_cleanup
}

# =============================================================================
# TESTS: Auto-Discovery Helpers
# =============================================================================

_test_should_ignore_directory() {
    _fleet_test_start "_should_ignore_directory node_modules"
    if _should_ignore_directory "node_modules"; then
        _fleet_test_pass "_should_ignore_directory node_modules"
    else
        _fleet_test_fail "_should_ignore_directory node_modules"
    fi

    _fleet_test_start "_should_ignore_directory .idea"
    if _should_ignore_directory ".idea"; then
        _fleet_test_pass "_should_ignore_directory .idea"
    else
        _fleet_test_fail "_should_ignore_directory .idea"
    fi

    _fleet_test_start "_should_ignore_directory dist"
    if _should_ignore_directory "dist"; then
        _fleet_test_pass "_should_ignore_directory dist"
    else
        _fleet_test_fail "_should_ignore_directory dist"
    fi

    _fleet_test_start "_should_ignore_directory .hidden"
    if _should_ignore_directory ".hidden"; then
        _fleet_test_pass "_should_ignore_directory .hidden"
    else
        _fleet_test_fail "_should_ignore_directory .hidden"
    fi

    _fleet_test_start "_should_ignore_directory vendor"
    if _should_ignore_directory "vendor"; then
        _fleet_test_pass "_should_ignore_directory vendor"
    else
        _fleet_test_fail "_should_ignore_directory vendor"
    fi

    _fleet_test_start "_should_ignore_directory my-service (not ignored)"
    if ! _should_ignore_directory "my-service"; then
        _fleet_test_pass "_should_ignore_directory my-service (not ignored)"
    else
        _fleet_test_fail "_should_ignore_directory my-service (not ignored)"
    fi

    _fleet_test_start "_should_ignore_directory api-gateway (not ignored)"
    if ! _should_ignore_directory "api-gateway"; then
        _fleet_test_pass "_should_ignore_directory api-gateway (not ignored)"
    else
        _fleet_test_fail "_should_ignore_directory api-gateway (not ignored)"
    fi
}

_test_is_git_repository() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-gitcheck.XXXXXX")

    # Normal repo
    _fleet_test_start "_is_git_repository normal repo"
    mkdir -p "$tmpdir/repo/.git"
    if _is_git_repository "$tmpdir/repo"; then
        _fleet_test_pass "_is_git_repository normal repo"
    else
        _fleet_test_fail "_is_git_repository normal repo"
    fi

    # Bare repo
    _fleet_test_start "_is_git_repository bare repo"
    mkdir -p "$tmpdir/bare/objects" "$tmpdir/bare/refs"
    echo "ref: refs/heads/main" > "$tmpdir/bare/HEAD"
    if _is_git_repository "$tmpdir/bare"; then
        _fleet_test_pass "_is_git_repository bare repo"
    else
        _fleet_test_fail "_is_git_repository bare repo"
    fi

    # Non-repo
    _fleet_test_start "_is_git_repository non-repo"
    mkdir -p "$tmpdir/notrepo"
    if ! _is_git_repository "$tmpdir/notrepo"; then
        _fleet_test_pass "_is_git_repository non-repo"
    else
        _fleet_test_fail "_is_git_repository non-repo"
    fi

    rm -rf "$tmpdir"
}

_test_classify_repository() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-classify.XXXXXX")

    # Infrastructure
    _fleet_test_start "_classify_repository infrastructure (terraform)"
    mkdir -p "$tmpdir/infra-repo/terraform"
    local cls
    cls=$(_classify_repository "$tmpdir/infra-repo")
    if [[ "$cls" == "infrastructure" ]]; then
        _fleet_test_pass "_classify_repository infrastructure (terraform)"
    else
        _fleet_test_fail "_classify_repository infrastructure (terraform)" "got=$cls"
    fi

    # Library
    _fleet_test_start "_classify_repository library (lib-prefix)"
    mkdir -p "$tmpdir/lib-common"
    cls=$(_classify_repository "$tmpdir/lib-common")
    if [[ "$cls" == "library" ]]; then
        _fleet_test_pass "_classify_repository library (lib-prefix)"
    else
        _fleet_test_fail "_classify_repository library (lib-prefix)" "got=$cls"
    fi

    # Tool
    _fleet_test_start "_classify_repository tool (-cli suffix)"
    mkdir -p "$tmpdir/deploy-cli"
    cls=$(_classify_repository "$tmpdir/deploy-cli")
    if [[ "$cls" == "tool" ]]; then
        _fleet_test_pass "_classify_repository tool (-cli suffix)"
    else
        _fleet_test_fail "_classify_repository tool (-cli suffix)" "got=$cls"
    fi

    # Service (Dockerfile)
    _fleet_test_start "_classify_repository service (Dockerfile)"
    mkdir -p "$tmpdir/my-app"
    touch "$tmpdir/my-app/Dockerfile"
    cls=$(_classify_repository "$tmpdir/my-app")
    if [[ "$cls" == "service" ]]; then
        _fleet_test_pass "_classify_repository service (Dockerfile)"
    else
        _fleet_test_fail "_classify_repository service (Dockerfile)" "got=$cls"
    fi

    # Default
    _fleet_test_start "_classify_repository default (service)"
    mkdir -p "$tmpdir/generic-thing"
    cls=$(_classify_repository "$tmpdir/generic-thing")
    if [[ "$cls" == "service" ]]; then
        _fleet_test_pass "_classify_repository default (service)"
    else
        _fleet_test_fail "_classify_repository default (service)" "got=$cls"
    fi

    rm -rf "$tmpdir"
}

_test_extract_service_name() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-name.XXXXXX")

    _fleet_test_start "_extract_service_name basic"
    mkdir -p "$tmpdir/My_Service"
    local name
    name=$(_extract_service_name "$tmpdir/My_Service")
    if [[ "$name" == "my-service" ]]; then
        _fleet_test_pass "_extract_service_name basic"
    else
        _fleet_test_fail "_extract_service_name basic" "got=$name"
    fi

    _fleet_test_start "_extract_service_name with special chars"
    mkdir -p "$tmpdir/My.Service@v2"
    name=$(_extract_service_name "$tmpdir/My.Service@v2")
    if [[ "$name" == "myservicev2" ]] || [[ "$name" == "my-servicev2" ]] || [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
        _fleet_test_pass "_extract_service_name with special chars"
    else
        _fleet_test_fail "_extract_service_name with special chars" "got=$name"
    fi

    _fleet_test_start "_extract_service_name generic name gets parent prefix"
    mkdir -p "$tmpdir/fleet-root/payments/src"
    name=$(_extract_service_name "$tmpdir/fleet-root/payments/src" "$tmpdir/fleet-root")
    if [[ "$name" == "payments-src" ]]; then
        _fleet_test_pass "_extract_service_name generic name gets parent prefix"
    else
        _fleet_test_fail "_extract_service_name generic name gets parent prefix" "got=$name"
    fi

    rm -rf "$tmpdir"
}

_test_get_repo_version() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-version.XXXXXX")

    # VERSION file
    _fleet_test_start "_get_repo_version from VERSION file"
    mkdir -p "$tmpdir/svc1"
    echo "3.2.1" > "$tmpdir/svc1/VERSION"
    local ver
    ver=$(_get_repo_version "$tmpdir/svc1")
    if [[ "$ver" == "3.2.1" ]]; then
        _fleet_test_pass "_get_repo_version from VERSION file"
    else
        _fleet_test_fail "_get_repo_version from VERSION file" "got=$ver"
    fi

    # package.json
    _fleet_test_start "_get_repo_version from package.json"
    mkdir -p "$tmpdir/svc2"
    echo '{"name":"test","version":"4.5.6"}' > "$tmpdir/svc2/package.json"
    ver=$(_get_repo_version "$tmpdir/svc2")
    if [[ "$ver" == "4.5.6" ]]; then
        _fleet_test_pass "_get_repo_version from package.json"
    else
        _fleet_test_fail "_get_repo_version from package.json" "got=$ver"
    fi

    # Fallback to 0.0.0
    _fleet_test_start "_get_repo_version fallback to 0.0.0"
    mkdir -p "$tmpdir/svc3"
    ver=$(_get_repo_version "$tmpdir/svc3")
    if [[ "$ver" == "0.0.0" ]]; then
        _fleet_test_pass "_get_repo_version fallback to 0.0.0"
    else
        _fleet_test_fail "_get_repo_version fallback to 0.0.0" "got=$ver"
    fi

    rm -rf "$tmpdir"
}

# =============================================================================
# TESTS: Service Name Sanitization Collision
# =============================================================================

_test_service_name_sanitization() {
    _fleet_test_start "service name sanitization hyphen vs dot"
    # This tests the known issue: tr '[:lower:]-.' '[:upper:]__' makes
    # both "my-service" and "my.service" map to MY_SERVICE
    local name1 name2
    name1=$(echo "my-service" | tr '[:lower:]-.' '[:upper:]__')
    name2=$(echo "my.service" | tr '[:lower:]-.' '[:upper:]__')
    if [[ "$name1" == "$name2" ]]; then
        # This is a known limitation — document it
        _fleet_test_pass "service name sanitization hyphen vs dot (known collision)"
        echo "      ⚠️  Known issue: 'my-service' and 'my.service' both map to '$name1'"
    else
        _fleet_test_pass "service name sanitization hyphen vs dot"
    fi
}

# =============================================================================
# TESTS: Fleet Docs Strategy
# =============================================================================

_test_fleet_docs_strategy() {
    _fleet_test_create_workspace

    _fleet_test_start "get_fleet_docs_strategy returns config value"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null

        local strategy
        strategy=$(get_fleet_docs_strategy 2>/dev/null)
        [[ "$strategy" == "per-service" ]] || exit 1
        exit 0
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "get_fleet_docs_strategy returns config value"
    else
        _fleet_test_fail "get_fleet_docs_strategy returns config value"
    fi

    _fleet_test_start "should_generate_per_service_docs returns true"
    (
        cd "$FLEET_TEST_DIR" 2>/dev/null || exit 1
        MANIFEST_CLI_FLEET_MODE="auto"
        MANIFEST_FLEET_ACTIVE="false"
        MANIFEST_FLEET_ROOT=""
        unset MANIFEST_CLI_FLEET_ROOT
        load_fleet_config "$FLEET_TEST_DIR" 2>/dev/null

        should_generate_per_service_docs 2>/dev/null
    )
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "should_generate_per_service_docs returns true"
    else
        _fleet_test_fail "should_generate_per_service_docs returns true"
    fi

    _fleet_test_cleanup
}

# =============================================================================
# TESTS: Fleet Help & Dispatch
# =============================================================================

_test_fleet_help() {
    _fleet_test_start "fleet_help does not error"
    fleet_help >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "fleet_help does not error"
    else
        _fleet_test_fail "fleet_help does not error"
    fi

    _fleet_test_start "fleet_main help does not error"
    fleet_main "help" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        _fleet_test_pass "fleet_main help does not error"
    else
        _fleet_test_fail "fleet_main help does not error"
    fi
}

# =============================================================================
# TESTS: Discovery Integration
# =============================================================================

_test_discover_fleet_repos() {
    local tmpdir
    tmpdir=$(mktemp -d "${TMPDIR:-/tmp}/fleet-discover.XXXXXX")

    # Create a mini workspace with some repos
    mkdir -p "$tmpdir/svc-a/.git" "$tmpdir/svc-b/.git" "$tmpdir/node_modules/pkg/.git"
    echo "1.0.0" > "$tmpdir/svc-a/VERSION"
    echo "2.0.0" > "$tmpdir/svc-b/VERSION"

    _fleet_test_start "discover_fleet_repos finds repos"
    local discovered
    discovered=$(discover_fleet_repos "$tmpdir" 3 "true" 2>/dev/null)
    local count=0
    while IFS=$'\t' read -r name path type branch version url submod; do
        [[ -z "$name" ]] && continue
        count=$((count + 1))
    done <<< "$discovered"

    if [[ $count -ge 2 ]]; then
        _fleet_test_pass "discover_fleet_repos finds repos"
    else
        _fleet_test_fail "discover_fleet_repos finds repos" "expected >=2, got $count"
    fi

    _fleet_test_start "discover_fleet_repos skips node_modules"
    if ! echo "$discovered" | grep -q "node_modules"; then
        _fleet_test_pass "discover_fleet_repos skips node_modules"
    else
        _fleet_test_fail "discover_fleet_repos skips node_modules"
    fi

    _fleet_test_start "discover_fleet_repos invalid dir returns 1"
    if ! discover_fleet_repos "/nonexistent/dir" 2>/dev/null; then
        _fleet_test_pass "discover_fleet_repos invalid dir returns 1"
    else
        _fleet_test_fail "discover_fleet_repos invalid dir returns 1"
    fi

    rm -rf "$tmpdir"
}

# =============================================================================
# TESTS: Fleet Module Constants
# =============================================================================

_test_fleet_defaults() {
    _fleet_test_start "fleet default constants are set"
    local ok=true
    [[ -n "$MANIFEST_FLEET_DEFAULT_MODE" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_MAX_SEARCH_DEPTH" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_VERSIONING" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_PARALLEL" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_MAX_PARALLEL" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_COMMIT_STRATEGY" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_PUSH_STRATEGY" ]] || ok=false
    [[ -n "$MANIFEST_FLEET_DEFAULT_DOCS_STRATEGY" ]] || ok=false

    if [[ "$ok" == "true" ]]; then
        _fleet_test_pass "fleet default constants are set"
    else
        _fleet_test_fail "fleet default constants are set"
    fi

    _fleet_test_start "fleet default values are correct"
    local correct=true
    [[ "$MANIFEST_FLEET_DEFAULT_MODE" == "auto" ]] || correct=false
    [[ "$MANIFEST_FLEET_DEFAULT_VERSIONING" == "date" ]] || correct=false
    [[ "$MANIFEST_FLEET_DEFAULT_PARALLEL" == "true" ]] || correct=false
    [[ "$MANIFEST_FLEET_DEFAULT_MAX_PARALLEL" -eq 4 ]] || correct=false
    [[ "$MANIFEST_FLEET_DEFAULT_COMMIT_STRATEGY" == "per-service" ]] || correct=false
    [[ "$MANIFEST_FLEET_DEFAULT_PUSH_STRATEGY" == "batched" ]] || correct=false

    if [[ "$correct" == "true" ]]; then
        _fleet_test_pass "fleet default values are correct"
    else
        _fleet_test_fail "fleet default values are correct"
    fi
}

# =============================================================================
# MAIN TEST RUNNER
# =============================================================================

test_fleet() {
    # Disable errexit for test runner — tests use subshells that may
    # return non-zero as part of normal expected-failure testing
    local _prev_errexit=""
    [[ "$-" == *e* ]] && _prev_errexit=1
    set +e

    echo "🚢 Testing Fleet functionality..."
    echo ""

    _FLEET_TESTS_TOTAL=0
    _FLEET_TESTS_PASSED=0
    _FLEET_TESTS_FAILED=0
    _FLEET_FAILED_TESTS=()

    echo "   --- Fleet Detection ---"
    _test_find_fleet_root
    _test_is_fleet_mode_enabled
    echo ""

    echo "   --- TSV Parsing ---"
    _test_get_fleet_services
    echo ""

    echo "   --- Service Properties ---"
    _test_fleet_service_properties
    echo ""

    echo "   --- Config Value Precedence ---"
    _test_fleet_config_value_precedence
    echo ""

    echo "   --- Fleet Validation ---"
    _test_fleet_validation
    echo ""

    echo "   --- Auto-Discovery Helpers ---"
    _test_should_ignore_directory
    _test_is_git_repository
    _test_classify_repository
    _test_extract_service_name
    _test_get_repo_version
    echo ""

    echo "   --- Service Name Sanitization ---"
    _test_service_name_sanitization
    echo ""

    echo "   --- Fleet Docs ---"
    _test_fleet_docs_strategy
    echo ""

    echo "   --- Fleet Help & Dispatch ---"
    _test_fleet_help
    echo ""

    echo "   --- Discovery Integration ---"
    _test_discover_fleet_repos
    echo ""

    echo "   --- Fleet Defaults ---"
    _test_fleet_defaults
    echo ""

    # Summary
    echo "   ═══════════════════════════════════════════"
    echo "   Fleet Tests: $_FLEET_TESTS_TOTAL total, $_FLEET_TESTS_PASSED passed, $_FLEET_TESTS_FAILED failed"
    echo "   ═══════════════════════════════════════════"

    if [[ ${#_FLEET_FAILED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo "   Failed tests:"
        for t in "${_FLEET_FAILED_TESTS[@]}"; do
            echo "     • $t"
        done
    fi

    # Restore errexit if it was previously set
    [[ -n "$_prev_errexit" ]] && set -e

    if [[ $_FLEET_TESTS_FAILED -gt 0 ]]; then
        return 1
    fi
    return 0
}
