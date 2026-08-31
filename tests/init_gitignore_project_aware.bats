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
    DOTNET_PROJ="$SCRATCH/dotnetproj"
    mkdir -p "$GO_PROJ" "$NODE_PROJ" "$BARE_PROJ" "$DOTNET_PROJ/src"
    printf 'module example.com/x\n\ngo 1.24\n' > "$GO_PROJ/go.mod"
    printf '{"name":"x","version":"1.0.0"}\n' > "$NODE_PROJ/package.json"
    # Nested under src/, which is where .NET project files conventionally live
    # and why the detector searches to -maxdepth 3 for this one label.
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$DOTNET_PROJ/src/App.csproj"

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

# --- .NET: a label that rendered nothing, and the rules that are NOT bare ------
#
# Two separate protections are pinned below, and conflating them is how one of
# them gets removed:
#
#   1. `*.user` and `TestResults/` are withheld from the unclassified SUPERSET,
#      because a repo Manifest cannot classify would otherwise be advised to
#      ignore paths it may be committing on purpose.
#   2. `bin/` and `obj/` are never emitted BARE at all — they are anchored to the
#      directory holding each project file. Withholding from the superset is not
#      enough for these two, because .NET is the only label found BELOW the root
#      (-maxdepth 3), so one stray `tools/helper/x.csproj` classifies an
#      otherwise-bash repo as dotnet and a bare `bin/` would then reach it
#      through classification rather than through the superset.

@test "gitignore: a .NET repo actually receives .NET rules" {
    # The regression: `dotnet` was emitted by the detector and consumed by
    # create_default_run_tests, but had NO block in the renderer, so a .NET repo
    # measured 129 rules — the universal core exactly, ecosystem contribution
    # zero. TRACKER §69(a).
    local gi="$DOTNET_PROJ/.gitignore"
    create_default_gitignore "$gi" "$DOTNET_PROJ"

    local pattern
    for pattern in '*.user' '*.suo' '.vs/' 'TestResults/' '*.nupkg' \
                   '/src/bin/' '/src/obj/'; do
        grep -qxF -- "$pattern" "$gi" || {
            echo ".NET repo did not receive: $pattern" >&2
            return 1
        }
    done
}

@test "gitignore: the .NET block contributes rules, counted in its own section" {
    # Counts the ECOSYSTEM section directly rather than comparing two whole
    # renders. The earlier form of this test was named "exceeds the universal
    # core" but actually compared .NET against a GO render, so a .NET block
    # shrunk to four rules would still have passed a test promising > 129.
    local gi="$SCRATCH/dotnet.rendered"
    create_default_gitignore "$gi" "$DOTNET_PROJ"

    local eco
    eco="$(sed -n '/^# ECOSYSTEM — chosen for this repository$/,$p' "$gi" \
           | grep -cvE '^[[:space:]]*$|^[[:space:]]*#')"

    # Control: prove the extractor found the section at all, so a zero below
    # means "no rules" rather than "no section matched".
    [ -n "$eco" ]
    [ "$eco" -ge 8 ]
}

@test "gitignore: the ambiguous .NET rules are withheld from the superset" {
    # The upgrade path APPENDS advised rules to a user's existing file, and a
    # repo Manifest cannot classify receives the superset. `TestResults/` is a
    # plain directory name and `*.user` a bare glob; neither is self-evidently
    # .NET, so neither belongs in advice given to an unrecognised stack.
    local gi="$BARE_PROJ/.gitignore"
    create_default_gitignore "$gi" "$BARE_PROJ"

    # Control FIRST: prove the superset really rendered, or the refutes below
    # pass against an empty file and assert nothing.
    grep -qxF -- 'node_modules/' "$gi"
    grep -qxF -- '.terraform/' "$gi"
    # The unambiguous half of the .NET block IS in the superset.
    grep -qxF -- '*.suo' "$gi"
    grep -qxF -- '.vs/' "$gi"

    refute grep -qxF -- 'bin/' "$gi"
    refute grep -qxF -- 'obj/' "$gi"
    refute grep -qxF -- 'TestResults/' "$gi"
    refute grep -qxF -- '*.user' "$gi"
}

@test "gitignore: bin/ and obj/ are anchored, never bare, even for a .NET repo" {
    # Withholding from the superset does not cover this: the repo below IS
    # classified dotnet. Only anchoring keeps a bare `bin/` out.
    local gi="$DOTNET_PROJ/.gitignore"
    create_default_gitignore "$gi" "$DOTNET_PROJ"

    grep -qxF -- '/src/bin/' "$gi"      # control: the anchored form is present
    refute grep -qxF -- 'bin/' "$gi"
    refute grep -qxF -- 'obj/' "$gi"
}

@test "gitignore: a project file at the repo ROOT anchors to /bin/ and /obj/" {
    # dirname yields an absolute path, so stripping the project root leaves the
    # EMPTY string for a root-level .csproj. Skipping empty as though it were
    # "no match" gave a root-level project no bin/obj rules at all — which this
    # catches and the src/-nested fixture above cannot.
    local root_proj="$SCRATCH/rootdotnet"
    mkdir -p "$root_proj"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$root_proj/App.csproj"

    create_default_gitignore "$root_proj/.gitignore" "$root_proj"

    grep -qxF -- '/bin/' "$root_proj/.gitignore"
    grep -qxF -- '/obj/' "$root_proj/.gitignore"
}

@test "gitignore: a polyglot repo's committed bin/ survives an incidental .csproj" {
    # The shape the anchoring exists for, stated as a user meets it: a bash repo
    # with scripts in bin/ and one stray project file three levels down. It
    # classifies as dotnet — that is not the bug — but its bin/ must not be
    # ignored. Already-tracked files survive a new ignore rule, so the loss
    # would be NEW files only, which is what makes it quiet rather than loud.
    local poly="$SCRATCH/polyglot"
    mkdir -p "$poly/bin" "$poly/tools/helper"
    printf '#!/usr/bin/env bash\necho deploy\n' > "$poly/bin/deploy.sh"
    printf '<Project Sdk="Microsoft.NET.Sdk"></Project>\n' > "$poly/tools/helper/x.csproj"

    # Control: it really is classified dotnet, so the refute below is about
    # anchoring and not about the detector quietly returning nothing.
    run manifest_detect_project_ecosystems "$poly"
    [ "$output" = "dotnet" ]

    create_default_gitignore "$poly/.gitignore" "$poly"

    grep -qxF -- '/tools/helper/bin/' "$poly/.gitignore"
    refute grep -qxF -- 'bin/' "$poly/.gitignore"
}

@test "advice: an unclassifiable repo is never advised to ignore bin/" {
    # The hazard stated as the user experiences it: upgrade appends, and a repo
    # with a committed bin/ of scripts must not be told to ignore it.
    printf '.DS_Store\n' > "$BARE_PROJ/.gitignore"

    run manifest_gitignore_missing_rules "$BARE_PROJ/.gitignore"
    [ "$status" -eq 0 ]

    # Control: this minimal file IS missing most of the advice, so an empty
    # refute below means "not advised", not "nothing was computed".
    [ -n "$output" ]
    grep -qxF -- 'node_modules/' <<<"$output"

    refute grep -qxF -- 'bin/' <<<"$output"
    refute grep -qxF -- 'obj/' <<<"$output"
}

@test "advice: a .NET repo IS advised to ignore its anchored bin/" {
    # The other direction of the same asymmetry. Without this, the anchoring
    # could be tightened all the way to "never emitted" and every refute above
    # would still pass.
    printf '.DS_Store\n' > "$DOTNET_PROJ/.gitignore"

    run manifest_gitignore_missing_rules "$DOTNET_PROJ/.gitignore"
    [ "$status" -eq 0 ]

    grep -qxF -- '/src/bin/' <<<"$output"
    grep -qxF -- '/src/obj/' <<<"$output"
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
