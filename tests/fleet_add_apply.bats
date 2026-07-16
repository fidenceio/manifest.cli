#!/usr/bin/env bats

# APPLY coverage for `manifest add fleet` (fleet_add).
#
# fleet_dry_run.bats proves the preview writes nothing. This file proves the
# other half: `add fleet <path> -y` actually lands the generated YAML in
# manifest.fleet.config.yaml (inside the services: map, before the next
# top-level key), preview and apply emit the SAME snippet, URL members get
# url + path keys, and a fleet without a config file degrades to printing
# the manual snippet without creating any file.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    HOME="$SCRATCH/home"
    mkdir -p "$HOME" "$SCRATCH/work"
    export HOME
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

run_manifest() {
    cd "$SCRATCH/work"
    run "$TEST_REPO_ROOT/scripts/manifest-cli.sh" "$@"
}

# A config whose services: map is FOLLOWED by another top-level key, so the
# apply has to insert inside the map rather than blindly appending to EOF.
write_fleet_config_with_trailing_section() {
    cat > "$SCRATCH/work/manifest.fleet.config.yaml" <<'YAML'
fleet:
  name: "test-fleet"
  versioning: "none"
services:
  svc:
    path: "./svc"
    branch: "main"
docs:
  strategy: "both"
YAML
}

write_member_tsv() {
    printf 'true\tsvc\t./svc\ttrue\t\tmain\n' > "$SCRATCH/work/manifest.fleet.tsv"
}

@test "add fleet <path> -y writes the service into the config services: map" {
    mkdir -p "$SCRATCH/work/services/new-api" "$SCRATCH/work/svc"
    write_fleet_config_with_trailing_section
    write_member_tsv
    tsv_before="$(cat "$SCRATCH/work/manifest.fleet.tsv")"

    run_manifest add fleet ./services/new-api --name new-api -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Applying because -y/--yes was provided."* ]]
    [[ "$output" == *"✓ Added 'new-api' to"*"manifest.fleet.config.yaml"* ]]

    config="$SCRATCH/work/manifest.fleet.config.yaml"
    # The exact generated keys landed on disk.
    grep -qx '  new-api:' "$config"
    grep -qx '    path: "./services/new-api"' "$config"
    # ... INSIDE the services: map — after `services:` and before the next
    # top-level key (`docs:`), so the YAML stays structurally valid.
    services_line=$(grep -n '^services:' "$config" | cut -d: -f1)
    newapi_line=$(grep -n '^  new-api:' "$config" | cut -d: -f1)
    docs_line=$(grep -n '^docs:' "$config" | cut -d: -f1)
    [ "$newapi_line" -gt "$services_line" ]
    [ "$newapi_line" -lt "$docs_line" ]
    # Pre-existing entries and sections are preserved verbatim.
    grep -qx '  svc:' "$config"
    grep -qx '  strategy: "both"' "$config"
    # add fleet writes membership into the config only; the TSV is untouched.
    [ "$(cat "$SCRATCH/work/manifest.fleet.tsv")" = "$tsv_before" ]
}

@test "add fleet preview and apply emit the same YAML snippet (parity)" {
    mkdir -p "$SCRATCH/work/services/new-api" "$SCRATCH/work/svc"
    write_fleet_config_with_trailing_section
    write_member_tsv

    run_manifest add fleet ./services/new-api --name new-api --dry-run
    [ "$status" -eq 0 ]
    # The preview promises exactly these two generated lines...
    [[ "$output" == *'  new-api:'* ]]
    [[ "$output" == *'    path: "./services/new-api"'* ]]
    preview_output="$output"

    run_manifest add fleet ./services/new-api --name new-api -y
    [ "$status" -eq 0 ]

    # ... and the apply writes them verbatim: every generated line shown by
    # the preview is present, character for character, in the config.
    config="$SCRATCH/work/manifest.fleet.config.yaml"
    grep -qxF '  new-api:' "$config"
    grep -qxF '    path: "./services/new-api"' "$config"
    # The apply echoes the same service name the preview resolved.
    while IFS= read -r line; do
        case "$line" in
            "Service name: "*)
                [[ "$preview_output" == *"$line"* ]]
                ;;
        esac
    done <<< "$output"
}

@test "add fleet <url> -y auto-names the member and writes url + path keys" {
    mkdir -p "$SCRATCH/work/svc"
    write_fleet_config_with_trailing_section
    write_member_tsv

    run_manifest add fleet https://github.com/org/My_Repo.git -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"Type: Remote URL"* ]]
    # basename minus .git, lowercased, underscores → hyphens.
    [[ "$output" == *"Service name: my-repo"* ]]
    [[ "$output" == *"✓ Added 'my-repo' to"* ]]

    config="$SCRATCH/work/manifest.fleet.config.yaml"
    grep -qx '  my-repo:' "$config"
    grep -qx '    url: "https://github.com/org/My_Repo.git"' "$config"
    grep -qx '    path: "./my-repo"' "$config"
}

@test "add fleet -y without a config file prints the manual snippet and creates nothing" {
    mkdir -p "$SCRATCH/work/services/new-api"

    run_manifest add fleet ./services/new-api --name new-api -y

    [ "$status" -eq 0 ]
    [[ "$output" == *"No manifest.fleet.config.yaml found."* ]]
    [[ "$output" == *'  new-api:'* ]]
    [[ "$output" == *'    path: "./services/new-api"'* ]]
    # Degraded mode never scaffolds a config behind the user's back.
    [ ! -f "$SCRATCH/work/manifest.fleet.config.yaml" ]
}
