#!/usr/bin/env bats
# bats file_tags=smoke

# The scaffolded .gitignore describes THIS repo, not every repo.
#
# Before this landed, create_default_gitignore took no project argument: it wrote
# the same 184 rules into every repository, of which 70 were ecosystem-specific.
# A Go repo received node_modules/, __pycache__/, .terraform/, .next/ and *.jar
# while the same `manifest init` run wrote a correctly Go-shaped run-tests.sh —
# the gate was project-aware and the ignore file was not.
#
# Two contracts are pinned here, and the second is the one that regresses quietly:
#
#   1. Generation: universal rules always; ecosystem rules only when the repo's
#      marker file says so; the whole superset when the project cannot be
#      classified (which is what keeps every single-argument caller unchanged).
#   2. The advice path renders for the SAME project. manifest_gitignore_missing_rules
#      feeds manifest_gitignore_upgrade, so if it rendered the superset instead, an
#      existing .gitignore would have every ecosystem's rules appended to it — the
#      exact bloat this change removes, restored through a different door, on the
#      one repo shape that already has a .gitignore.

load 'helpers/setup'

setup() {
    load_modules
    SCRATCH="$(mk_scratch)"
    # shellcheck disable=SC1091
    source "$TEST_REPO_ROOT/modules/core/manifest-init.sh"

    GO_PROJ="$SCRATCH/goproj"
    NODE_PROJ="$SCRATCH/nodeproj"
    BARE_PROJ="$SCRATCH/bareproj"
    mkdir -p "$GO_PROJ" "$NODE_PROJ" "$BARE_PROJ"
    printf 'module example.com/x\n\ngo 1.24\n' > "$GO_PROJ/go.mod"
    printf '{"name":"x","version":"1.0.0"}\n' > "$NODE_PROJ/package.json"

    rules() { grep -cvE '^\s*$|^\s*#' "$1"; }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
}

# --- the detector, asserted directly -----------------------------------------
# Without this, the superset test below would pass vacuously against a detector
# that always returned nothing: "classified as nothing" and "detector broken"
# produce identical output there.

@test "detector: a go.mod repo is classified go, and only go" {
    run manifest_detect_project_ecosystems "$GO_PROJ"
    [ "$status" -eq 0 ]
    [ "$output" = "go" ]
}

@test "detector: a package.json repo is classified node" {
    run manifest_detect_project_ecosystems "$NODE_PROJ"
    [ "$status" -eq 0 ]
    [ "$output" = "node" ]
}

@test "detector: a repo with no markers is classified as nothing, and does not fail" {
    run manifest_detect_project_ecosystems "$BARE_PROJ"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "detector: several markers yield several labels" {
    printf 'module example.com/x\n' > "$BARE_PROJ/go.mod"
    printf '{}\n' > "$BARE_PROJ/package.json"
    printf 'resource "null_resource" "x" {}\n' > "$BARE_PROJ/main.tf"

    run manifest_detect_project_ecosystems "$BARE_PROJ"
    [ "$status" -eq 0 ]
    grep -qx 'go' <<<"$output"
    grep -qx 'node' <<<"$output"
    grep -qx 'terraform' <<<"$output"
}

# --- generation ---------------------------------------------------------------

@test "gitignore: a Go repo gets Go rules and none of the other ecosystems'" {
    local gi="$GO_PROJ/.gitignore"
    create_default_gitignore "$gi" "$GO_PROJ"

    grep -qxF '*.test' "$gi"
    grep -qxF 'go.work' "$gi"

    local leaked=""
    local pattern
    for pattern in 'node_modules/' '__pycache__/' '.terraform/' '.next/' '*.jar' 'target/' '.bundle/'; do
        if grep -qxF -- "$pattern" "$gi"; then
            leaked+="  $pattern"$'\n'
        fi
    done
    if [ -n "$leaked" ]; then
        printf 'rules from other ecosystems leaked into a Go repo:\n%s' "$leaked" >&2
        return 1
    fi
}

@test "gitignore: the universal security core survives project-aware trimming" {
    local gi="$GO_PROJ/.gitignore"
    create_default_gitignore "$gi" "$GO_PROJ"

    # Trimming must never reach the blocks that exist to stop a secret reaching a
    # remote: KEY MATERIAL, the .env denials, and the agent-workspace rules.
    local pattern
    for pattern in '*.key' '*.pem' '*.p12' 'id_rsa' 'secring.*' \
                   '.env' '.env.*' '*.secret.*' \
                   '.claude/*' '.manifest-cli/'; do
        grep -qxF -- "$pattern" "$gi" || {
            echo "universal rule lost from a classified repo: $pattern" >&2
            return 1
        }
    done
}

@test "gitignore: key-material exceptions still sit after their rules when trimmed" {
    local gi="$GO_PROJ/.gitignore"
    create_default_gitignore "$gi" "$GO_PROJ"

    # .gitignore is last-match-wins, so a re-inclusion above its rule does nothing.
    local rule_line exception_line
    # -m1 rather than `| head -1`: a pipeline into head SIGPIPEs its producer,
    # which the suite forbids outright (tests/suite_shell_options.bats).
    rule_line="$(grep -nxF -m1 -- '*.pem' "$gi" | cut -d: -f1)"
    exception_line="$(grep -nxF -m1 -- '!*public*.pem' "$gi" | cut -d: -f1)"
    [ -n "$rule_line" ]
    [ -n "$exception_line" ]
    [ "$exception_line" -gt "$rule_line" ]
}

@test "gitignore: an unclassifiable repo gets the whole superset" {
    local gi="$BARE_PROJ/.gitignore"
    create_default_gitignore "$gi" "$BARE_PROJ"

    # Safe direction: an unrecognised stack gets more advice, never less.
    local pattern
    for pattern in 'node_modules/' '__pycache__/' '.terraform/' '*.jar' '*.test' 'target/'; do
        grep -qxF -- "$pattern" "$gi" || {
            echo "superset is incomplete, missing: $pattern" >&2
            return 1
        }
    done
}

@test "gitignore: omitting the project root renders exactly the superset" {
    # The compatibility contract every existing single-argument caller relies on.
    local with_bare="$SCRATCH/bare.rendered" without_arg="$SCRATCH/noarg.rendered"
    create_default_gitignore "$with_bare" "$BARE_PROJ"
    create_default_gitignore "$without_arg"

    diff "$with_bare" "$without_arg"
}

@test "gitignore: a classified repo gets strictly fewer rules than the superset" {
    local go_gi="$SCRATCH/go.rendered" all_gi="$SCRATCH/all.rendered"
    create_default_gitignore "$go_gi" "$GO_PROJ"
    create_default_gitignore "$all_gi"

    local go_n all_n
    go_n="$(rules "$go_gi")"
    all_n="$(rules "$all_gi")"
    [ "$go_n" -gt 0 ]
    [ "$all_n" -gt "$go_n" ]
}

# --- the advice path, which feeds the upgrade path ----------------------------

@test "advice: a Go repo carrying its own advised set reports nothing missing" {
    local gi="$GO_PROJ/.gitignore"
    create_default_gitignore "$gi" "$GO_PROJ"

    run manifest_gitignore_missing_rules "$gi"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "advice: a Go repo is never advised to ignore another ecosystem's paths" {
    # The regression this guards: rendering the superset here would have upgrade
    # append node/python/terraform rules to a Go repo's existing .gitignore.
    printf 'go.work\n' > "$GO_PROJ/.gitignore"

    run manifest_gitignore_missing_rules "$GO_PROJ/.gitignore"
    [ "$status" -eq 0 ]

    # Control: a minimal file IS missing most of the advice, so the emptiness of
    # the checks below means "not advised", not "nothing was computed".
    [ -n "$output" ]
    grep -qxF -- '*.key' <<<"$output"

    refute grep -qxF -- 'node_modules/' <<<"$output"
    refute grep -qxF -- '__pycache__/' <<<"$output"
    refute grep -qxF -- '.terraform/' <<<"$output"
}

@test "advice: upgrade appends only this repo's ecosystem, and stays idempotent" {
    printf 'go.work\n' > "$GO_PROJ/.gitignore"

    run manifest_gitignore_upgrade "$GO_PROJ/.gitignore"
    [ "$status" -eq 0 ]
    [[ "$output" == *":upgraded:"* ]]

    grep -qxF -- '*.key' "$GO_PROJ/.gitignore"
    refute grep -qxF -- 'node_modules/' "$GO_PROJ/.gitignore"

    run manifest_gitignore_upgrade "$GO_PROJ/.gitignore"
    [ "$status" -eq 0 ]
    [[ "$output" == *":current"* ]]
}
