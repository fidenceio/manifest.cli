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
