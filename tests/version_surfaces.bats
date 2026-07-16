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

@test "version surfaces: policy JSON reflects the built-in defaults" {
    unset MANIFEST_CLI_VERSION_SURFACES_ENABLED MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH \
          MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE MANIFEST_CLI_VERSION_SURFACE_NOTIFY \
          MANIFEST_CLI_VERSION_HANDLER_CATALOG

    run manifest_version_surface_policy_json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.enabled == true' >/dev/null
    echo "$output" | jq -e '.notification_mode == "summary"' >/dev/null
    echo "$output" | jq -e '.depth == 5' >/dev/null
    echo "$output" | jq -e '.catalog | endswith("modules/catalog/version-handlers.tsv")' >/dev/null
}

@test "version surfaces: policy JSON reflects configured overrides" {
    export MANIFEST_CLI_VERSION_SURFACES_ENABLED="false"
    export MANIFEST_CLI_VERSION_SURFACE_SCAN_DEPTH="3"
    export MANIFEST_CLI_VERSION_SURFACE_NOTIFICATION_MODE="off"
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="$SCRATCH/handlers.tsv"

    run manifest_version_surface_policy_json
    [ "$status" -eq 0 ]
    echo "$output" | jq -e '.enabled == false' >/dev/null
    echo "$output" | jq -e '.notification_mode == "off"' >/dev/null
    echo "$output" | jq -e '.depth == 3' >/dev/null
    echo "$output" | jq -e --arg c "$SCRATCH/handlers.tsv" '.catalog == $c' >/dev/null
}

@test "version surfaces: catalog entries read the built-in catalog as well-formed TSV" {
    unset MANIFEST_CLI_VERSION_HANDLER_CATALOG
    run manifest_version_catalog_entries
    [ "$status" -eq 0 ]
    echo "$output" | grep -q $'^manifest-version-file\tVERSION\tcanonical\ttext'
    echo "$output" | grep -q $'^npm-package\tpackage.json\tpackage-manifest\tjson'
    # Every emitted row has >= 4 tab-separated columns and no comment rows.
    local bad
    bad=$(manifest_version_catalog_entries | awk -F'\t' 'NF < 4 || $1 ~ /^#/ { c++ } END { print c+0 }')
    [ "$bad" = "0" ]
}

@test "version surfaces: catalog entries skip comments and rows with too few columns" {
    cat > "$SCRATCH/handlers.tsv" <<'TSV'
# comment row
good-json	widget.json	package-manifest	json
short-row	only-three.txt	text
TSV
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="$SCRATCH/handlers.tsv"

    run manifest_version_catalog_entries
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 1 ]
    [ "${lines[0]}" = $'good-json\twidget.json\tpackage-manifest\tjson' ]
}

@test "version surfaces: scan silently ignores malformed catalog rows" {
    cat > "$SCRATCH/handlers.tsv" <<'TSV'
good-yaml	app.yaml	package-manifest	yaml
bad-row	orphan.txt	text
TSV
    export MANIFEST_CLI_VERSION_HANDLER_CATALOG="$SCRATCH/handlers.tsv"
    echo "1.0.0" > "$SCRATCH/VERSION"
    printf 'version: "4.5.6"\n' > "$SCRATCH/app.yaml"
    echo "9.9.9" > "$SCRATCH/orphan.txt"

    run manifest_version_surface_scan "$SCRATCH" 1
    [ "$status" -eq 0 ]
    # Well-formed row is detected; canonical VERSION is still reported.
    echo "$output" | grep -q $'good-yaml\tpackage-manifest\tyaml\tnoncanonical\tapp.yaml\t4.5.6'
    echo "$output" | grep -q $'custom-version-file\tcanonical\ttext\tcanonical\tVERSION\t1.0.0'
    # The malformed (3-column) row is dropped without warning or error, so its
    # file never becomes a scanned surface.
    ! echo "$output" | grep -q "orphan.txt"
}
