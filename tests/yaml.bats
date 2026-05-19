#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    YAML="$SCRATCH/test.yaml"
}

teardown() {
    rm -rf "$SCRATCH"
}

@test "yaml: require_yaml_parser succeeds when yq is on PATH" {
    run require_yaml_parser
    [ "$status" -eq 0 ]
}

@test "yaml: detect_yaml_parser rejects yq without required vendor/version signature" {
    mkdir -p "$SCRATCH/bin"
    cat > "$SCRATCH/bin/yq" <<'EOF'
#!/usr/bin/env sh
echo "yq 4.40.5"
EOF
    chmod +x "$SCRATCH/bin/yq"

    PATH="$SCRATCH/bin:$PATH" run detect_yaml_parser
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "$MANIFEST_CLI_REQUIRED_YQ_LABEL"
}

@test "requirements: yq version text requires Mike Farah vendor and minimum major" {
    run manifest_requirement_yq_text_is_supported "yq (https://github.com/mikefarah/yq/) version v4.53.2"
    [ "$status" -eq 0 ]

    run manifest_requirement_yq_text_is_supported "yq (https://example.com/yq/) version v4.53.2"
    [ "$status" -eq 1 ]

    run manifest_requirement_yq_text_is_supported "yq (https://github.com/mikefarah/yq/) version v3.4.1"
    [ "$status" -eq 1 ]
}

@test "yaml: yaml_path_to_env_var maps known YAML paths to MANIFEST_CLI_* envs" {
    run yaml_path_to_env_var "git.tag_prefix"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_GIT_TAG_PREFIX" ]
}

@test "yaml: env_var_to_yaml_path is the inverse of yaml_path_to_env_var" {
    run env_var_to_yaml_path "MANIFEST_CLI_GIT_TAG_PREFIX"
    [ "$status" -eq 0 ]
    [ "$output" = "git.tag_prefix" ]
}

@test "yaml: maps release tag target policy" {
    run yaml_path_to_env_var "release.tag_target"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_RELEASE_TAG_TARGET" ]

    run env_var_to_yaml_path "MANIFEST_CLI_RELEASE_TAG_TARGET"
    [ "$status" -eq 0 ]
    [ "$output" = "release.tag_target" ]
}

@test "yaml: maps GitHub release policy" {
    run yaml_path_to_env_var "github.release.enabled"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_GITHUB_RELEASE_ENABLED" ]

    run env_var_to_yaml_path "MANIFEST_CLI_GITHUB_RELEASE_REQUIRED"
    [ "$status" -eq 0 ]
    [ "$output" = "github.release.required" ]
}

@test "yaml: maps documentation review config" {
    run yaml_path_to_env_var "docs.review.report_dir"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_DOC_REVIEW_REPORT_DIR" ]

    run env_var_to_yaml_path "MANIFEST_CLI_DOC_REVIEW_OUTPUTS"
    [ "$status" -eq 0 ]
    [ "$output" = "docs.review.outputs" ]
}

@test "yaml: maps documentation generation and site config" {
    run yaml_path_to_env_var "docs.generate.enabled"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_DOCS_GENERATE_ENABLED" ]

    run yaml_path_to_env_var "docs.generate.site_workflow"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_DOCS_GENERATE_SITE_WORKFLOW" ]

    run yaml_path_to_env_var "docs.site.palette.primary"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_DOCS_SITE_PALETTE_PRIMARY" ]

    run env_var_to_yaml_path "MANIFEST_CLI_DOCS_SITE_ENABLE_PAGES"
    [ "$status" -eq 0 ]
    [ "$output" = "docs.site.enable_pages" ]
}

@test "yaml: maps config-surface keys lifted from env-only settings" {
    run yaml_path_to_env_var "release.canonical_repo_slugs"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_CANONICAL_REPO_SLUGS" ]

    run yaml_path_to_env_var "ship.interactive"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_INTERACTIVE_MODE" ]

    run yaml_path_to_env_var "fleet.config_filename"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_FLEET_CONFIG_FILENAME" ]

    run yaml_path_to_env_var "automation.auto_confirm"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_AUTO_CONFIRM" ]

    run yaml_path_to_env_var "cloud.api_key_env"
    [ "$status" -eq 0 ]
    [ "$output" = "MANIFEST_CLI_CLOUD_API_KEY_ENV" ]

    run env_var_to_yaml_path "MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES"
    [ "$status" -eq 0 ]
    [ "$output" = "security.private_files" ]
}

@test "yaml: set_yaml_value creates a file and writes a nested key" {
    set_yaml_value "$YAML" "git.tag_prefix" "v"
    [ -f "$YAML" ]
    run yq e ".git.tag_prefix" "$YAML"
    [ "$output" = "v" ]
}

@test "yaml: get_yaml_value reads a value previously written" {
    set_yaml_value "$YAML" "git.default_branch" "main"
    run get_yaml_value "$YAML" ".git.default_branch"
    [ "$status" -eq 0 ]
    [ "$output" = "main" ]
}

@test "yaml: get_yaml_value returns the supplied default when key is missing" {
    : > "$YAML"
    run get_yaml_value "$YAML" ".does.not.exist" "fallback-val"
    [ "$status" -eq 0 ]
    [ "$output" = "fallback-val" ]
}

@test "yaml: get_yaml_value treats an explicit empty default as a default" {
    : > "$YAML"
    run get_yaml_value "$YAML" ".does.not.exist" ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "yaml: load_yaml_to_env exports mapped keys into MANIFEST_CLI_* envs" {
    set_yaml_value "$YAML" "git.tag_prefix" "release-"
    set_yaml_value "$YAML" "git.default_branch" "trunk"
    set_yaml_value "$YAML" "release.tag_target" "release_head"
    set_yaml_value "$YAML" "github.release.enabled" "false"
    set_yaml_value "$YAML" "docs.review.outputs" "commit_body,report"
    set_yaml_value "$YAML" "docs.review.report_dir" "docs/reviews"
    set_yaml_value "$YAML" "docs.generate.enabled" "false"
    set_yaml_value "$YAML" "docs.site.source_dir" "site-docs"
    set_yaml_value "$YAML" "docs.site.theme" "minimal"
    unset MANIFEST_CLI_GIT_TAG_PREFIX MANIFEST_CLI_GIT_DEFAULT_BRANCH MANIFEST_CLI_RELEASE_TAG_TARGET MANIFEST_CLI_GITHUB_RELEASE_ENABLED MANIFEST_CLI_DOC_REVIEW_OUTPUTS MANIFEST_CLI_DOC_REVIEW_REPORT_DIR
    unset MANIFEST_CLI_DOCS_GENERATE_ENABLED MANIFEST_CLI_DOCS_SITE_SOURCE_DIR MANIFEST_CLI_DOCS_SITE_THEME
    load_yaml_to_env "$YAML"
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "release-" ]
    [ "$MANIFEST_CLI_GIT_DEFAULT_BRANCH" = "trunk" ]
    [ "$MANIFEST_CLI_RELEASE_TAG_TARGET" = "release_head" ]
    [ "$MANIFEST_CLI_GITHUB_RELEASE_ENABLED" = "false" ]
    [ "$MANIFEST_CLI_DOC_REVIEW_OUTPUTS" = "commit_body,report" ]
    [ "$MANIFEST_CLI_DOC_REVIEW_REPORT_DIR" = "docs/reviews" ]
    [ "$MANIFEST_CLI_DOCS_GENERATE_ENABLED" = "false" ]
    [ "$MANIFEST_CLI_DOCS_SITE_SOURCE_DIR" = "site-docs" ]
    [ "$MANIFEST_CLI_DOCS_SITE_THEME" = "minimal" ]
}

@test "yaml: load_yaml_to_env exports lifted config-surface keys" {
    set_yaml_value "$YAML" "release.canonical_repo_slugs" "example/cli"
    set_yaml_value "$YAML" "ship.interactive" "true"
    set_yaml_value "$YAML" "fleet.mode" "false"
    set_yaml_value "$YAML" "fleet.root" "../fleet"
    set_yaml_value "$YAML" "fleet.config_filename" "fleet.yaml"
    set_yaml_value "$YAML" "automation.auto_confirm" "true"
    set_yaml_value "$YAML" "deprecations.quiet" "true"
    set_yaml_value "$YAML" "network.offline" "true"
    set_yaml_value "$YAML" "cloud.skip" "true"
    set_yaml_value "$YAML" "cloud.api_key_env" "TEST_MANIFEST_CLOUD_KEY"
    set_yaml_value "$YAML" "security.private_files" ".secret,manifest.config.local.yaml"
    unset MANIFEST_CLI_CANONICAL_REPO_SLUGS MANIFEST_CLI_INTERACTIVE_MODE MANIFEST_CLI_FLEET_MODE MANIFEST_CLI_FLEET_ROOT MANIFEST_CLI_FLEET_CONFIG_FILENAME
    unset MANIFEST_CLI_AUTO_CONFIRM MANIFEST_CLI_QUIET_DEPRECATIONS MANIFEST_CLI_OFFLINE_MODE MANIFEST_CLI_CLOUD_SKIP MANIFEST_CLI_CLOUD_API_KEY_ENV MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES

    load_yaml_to_env "$YAML"

    [ "$MANIFEST_CLI_CANONICAL_REPO_SLUGS" = "example/cli" ]
    [ "$MANIFEST_CLI_INTERACTIVE_MODE" = "true" ]
    [ "$MANIFEST_CLI_FLEET_MODE" = "false" ]
    [ "$MANIFEST_CLI_FLEET_ROOT" = "../fleet" ]
    [ "$MANIFEST_CLI_FLEET_CONFIG_FILENAME" = "fleet.yaml" ]
    [ "$MANIFEST_CLI_AUTO_CONFIRM" = "true" ]
    [ "$MANIFEST_CLI_QUIET_DEPRECATIONS" = "true" ]
    [ "$MANIFEST_CLI_OFFLINE_MODE" = "true" ]
    [ "$MANIFEST_CLI_CLOUD_SKIP" = "true" ]
    [ "$MANIFEST_CLI_CLOUD_API_KEY_ENV" = "TEST_MANIFEST_CLOUD_KEY" ]
    [ "$MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES" = ".secret,manifest.config.local.yaml" ]
}

@test "yaml: load_yaml_to_env replaces array-backed vars cleanly" {
    MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES=(".env" ".env.test" "manifest.config.local.yaml")
    set_yaml_value "$YAML" "security.private_files" ".secret,local.yaml"

    load_yaml_to_env "$YAML"

    run bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "system/manifest-security.sh"; unset MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES; MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES="$2"; _manifest_security_private_env_files' _ "$TEST_REPO_ROOT" "$MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES"
    [ "$status" -eq 0 ]
    [ "$output" = $'.secret\nlocal.yaml' ]
}

@test "yaml: load_yaml_to_env preserves unrelated env values when key absent (layered precedence)" {
    set_yaml_value "$YAML" "git.tag_prefix" "v"
    export MANIFEST_CLI_GIT_DEFAULT_BRANCH="preserved"
    load_yaml_to_env "$YAML"
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "v" ]
    [ "$MANIFEST_CLI_GIT_DEFAULT_BRANCH" = "preserved" ]
}

@test "yaml: load_yaml_to_env trims surrounding whitespace from values" {
    # YAML preserves leading/trailing whitespace inside quoted strings.  Without
    # normalization, " release_head " (typo on copy/paste) would silently break
    # every downstream string comparison.  load_yaml_to_env must trim.
    set_yaml_value "$YAML" "release.tag_target" "  release_head  "
    set_yaml_value "$YAML" "git.tag_prefix" "   release-   "
    unset MANIFEST_CLI_RELEASE_TAG_TARGET MANIFEST_CLI_GIT_TAG_PREFIX
    load_yaml_to_env "$YAML"
    [ "$MANIFEST_CLI_RELEASE_TAG_TARGET" = "release_head" ]
    [ "$MANIFEST_CLI_GIT_TAG_PREFIX" = "release-" ]
}

@test "yaml: load_yaml_to_env preserves internal whitespace (only trims edges)" {
    # Trim must be edge-only.  A commit_template legitimately contains spaces;
    # we should not collapse or modify them, only strip leading/trailing.
    set_yaml_value "$YAML" "git.commit_template" "  Release v{version} - {timestamp}  "
    unset MANIFEST_CLI_GIT_COMMIT_TEMPLATE
    load_yaml_to_env "$YAML"
    [ "$MANIFEST_CLI_GIT_COMMIT_TEMPLATE" = "Release v{version} - {timestamp}" ]
}

@test "yaml: set_yaml_value followed by get_yaml_value round-trips multi-level paths" {
    set_yaml_value "$YAML" "time.cache_ttl" "120"
    set_yaml_value "$YAML" "time.cache_cleanup_period" "3600"
    run get_yaml_value "$YAML" ".time.cache_ttl"
    [ "$output" = "120" ]
    run get_yaml_value "$YAML" ".time.cache_cleanup_period"
    [ "$output" = "3600" ]
}

@test "config: process env overrides YAML layers and cloud api key refs hydrate secrets" {
    mkdir -p "$SCRATCH/project" "$SCRATCH/home"
    cat > "$SCRATCH/project/manifest.config.yaml" <<'YAML'
ship:
  interactive: false
cloud:
  api_key_env: "TEST_MANIFEST_CLOUD_KEY"
YAML

    run env \
        HOME="$SCRATCH/home" \
        PROJECT_ROOT="$SCRATCH/project" \
        MANIFEST_CLI_INTERACTIVE_MODE=true \
        TEST_MANIFEST_CLOUD_KEY=secret-from-env \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh"; load_configuration "$PROJECT_ROOT" "false" >/dev/null; printf "%s|%s|%s" "$MANIFEST_CLI_INTERACTIVE_MODE" "$MANIFEST_CLI_CLOUD_API_KEY_ENV" "$MANIFEST_CLI_CLOUD_API_KEY"' _ "$TEST_REPO_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = "true|TEST_MANIFEST_CLOUD_KEY|secret-from-env" ]
}

@test "config: process env override replaces array-backed security private files" {
    mkdir -p "$SCRATCH/project" "$SCRATCH/home"
    cat > "$SCRATCH/project/manifest.config.yaml" <<'YAML'
security:
  private_files: ".yaml-secret"
YAML

    run env \
        HOME="$SCRATCH/home" \
        PROJECT_ROOT="$SCRATCH/project" \
        MANIFEST_CLI_SECURITY_PRIVATE_ENV_FILES=".env-secret, manifest.config.local.yaml" \
        bash -c 'source "$1/tests/helpers/setup.bash"; load_modules "core/manifest-config.sh" "system/manifest-security.sh"; load_configuration "$PROJECT_ROOT" "false" >/dev/null; _manifest_security_private_env_files' _ "$TEST_REPO_ROOT"

    [ "$status" -eq 0 ]
    [ "$output" = $'.env-secret\nmanifest.config.local.yaml' ]
}
