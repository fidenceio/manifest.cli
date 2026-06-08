#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-discovery.sh" "core/manifest-version-surfaces.sh"
    SCRATCH="$(mk_scratch)"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

@test "version surfaces: scan reports canonical VERSION and noncanonical package surfaces" {
    echo "1.2.3" > "$SCRATCH/VERSION"
    cat > "$SCRATCH/package.json" <<'JSON'
{
  "name": "demo",
  "version": "0.1.0"
}
JSON
    cat > "$SCRATCH/package-lock.json" <<'JSON'
{
  "name": "demo",
  "version": "0.1.0",
  "lockfileVersion": 3
}
JSON

    run manifest_version_surface_scan "$SCRATCH" 2
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'manifest-version-file\tcanonical\ttext\tcanonical\tVERSION\t1.2.3'
    echo "$output" | grep -q $'npm-package\tpackage-manifest\tjson\tnoncanonical\tpackage.json\t0.1.0'
    echo "$output" | grep -q $'npm-lock\tlockfile\tjson\tnoncanonical\tpackage-lock.json\t0.1.0'
}

@test "version surfaces: scan uses non-fleet exploration so package workspaces are visible" {
    mkdir -p "$SCRATCH/packages/app" "$SCRATCH/node_modules/pkg"
    echo "2.0.0" > "$SCRATCH/VERSION"
    printf '{"version":"2.0.0"}\n' > "$SCRATCH/packages/app/package.json"
    printf '{"version":"9.9.9"}\n' > "$SCRATCH/node_modules/pkg/package.json"

    run manifest_version_surface_scan "$SCRATCH" 3
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'npm-package\tpackage-manifest\tjson\tnoncanonical\tpackages/app/package.json\t2.0.0'
    ! echo "$output" | grep -q "node_modules/pkg/package.json"
}

@test "version surfaces: custom canonical version file is canonical without mutating VERSION" {
    export MANIFEST_CLI_VERSION_FILE="APP_VERSION"
    echo "3.4.5" > "$SCRATCH/APP_VERSION"
    echo "0.0.1" > "$SCRATCH/VERSION"

    run manifest_version_surface_scan "$SCRATCH" 1
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'custom-version-file\tcanonical\ttext\tcanonical\tAPP_VERSION\t3.4.5'
    echo "$output" | grep -q $'manifest-version-file\tcanonical\ttext\tnoncanonical\tVERSION\t0.0.1'
}

@test "version surfaces: policy helpers normalize enabled, depth, and notification mode" {
    unset MANIFEST_CLI_VERSION_SURFACES_ENABLED MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE
    run manifest_version_surfaces_enabled
    [ "$status" -eq 0 ]

    export MANIFEST_CLI_VERSION_SURFACES_ENABLED="false"
    run manifest_version_surfaces_enabled
    [ "$status" -eq 1 ]

    export MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH="99"
    run manifest_version_surface_scan_depth
    [ "$status" -eq 0 ]
    [ "$output" = "$MANIFEST_CLI_DISCOVERY_MAX_DEPTH_CAP" ]

    export MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE="detail"
    run manifest_version_surface_notification_mode
    [ "$status" -eq 0 ]
    [ "$output" = "list" ]
}

@test "version surfaces: custom catalog detects configured handlers" {
    cat > "$SCRATCH/handlers.tsv" <<'TSV'
custom-yaml	app.yaml	package-manifest	yaml
TSV
    cat > "$SCRATCH/app.yaml" <<'YAML'
version: "7.8.9"
YAML
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="$SCRATCH/handlers.tsv"

    run manifest_version_surface_scan "$SCRATCH" 1
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'custom-yaml\tpackage-manifest\tyaml\tnoncanonical\tapp.yaml\t7.8.9'
}

@test "version surfaces: policy warnings report bad catalog, bad depth, and bad notification mode" {
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="$SCRATCH/missing.tsv"
    export MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH="too-deep"
    export MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE="chatty"

    run manifest_version_surface_policy_warnings
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "catalog not found"
    echo "$output" | grep -q "scan_depth 'too-deep' is invalid"
    echo "$output" | grep -q "notification_mode 'chatty' is invalid"
}
