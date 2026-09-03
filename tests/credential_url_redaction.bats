#!/usr/bin/env bats
# §5.10 smoke tier (safety-contract suite)
# bats file_tags=smoke
#
# Coverage for SEC-007 (owned by tracker §2): a remote URL carrying inline
# credentials (`scheme://user:pass@host`) must never print verbatim.
#
# manifest_redact grew a userinfo clause, and the output sites that print a
# remote URL through a BARE echo/printf — i.e. sites the log_* redaction wiring
# never reaches — were routed through it. Those sites are enumerated here
# one-per-test so a regression names which one broke.
#
# Every case also carries a positive control: a NON-credentialed URL must pass
# through byte-identical. Without it a test that "passes" cannot distinguish
# redaction from the output site simply having stopped printing the URL.
#
# NOTE: the credentialed fixture is assembled at runtime from harmless parts
# (same convention as output_redaction.bats) so no literal `user:pass@host`
# shape is committed for the repo's secret scanner / CI gitleaks to trip on.

load 'helpers/setup'

setup() {
    load_modules \
        "core/manifest-discovery.sh" \
        "core/manifest-version-surfaces.sh" \
        "core/manifest-status.sh" \
        "core/manifest-core.sh"
    SCRATCH="$(mk_scratch)"
    # Isolate HOME: the apply gate writes an audit log under $HOME/.manifest-cli.
    HOME="$SCRATCH/home"
    mkdir -p "$HOME"
    export HOME
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
    unset MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL MANIFEST_CLI_HOMEBREW_TAP_BRANCH
}

# --- fixtures ---------------------------------------------------------------

# https://user:secret@example.com/x/y.git — assembled, never committed literally.
cred_url()  { printf 'https://%s:%s@example.com/x/y.git' "user" "secret"; }
# The userinfo needle. Asserting on the whole `user:secret@` triple (not just
# the word "secret") keeps the negative assertion unambiguous.
cred_needle() { printf '%s:%s@' "user" "secret"; }
# What the redacted form must look like: scheme + host survive, userinfo does not.
cred_redacted() { printf 'https://[REDACTED]@example.com/x/y.git'; }
# Positive control: same host, no credentials. Must survive byte-identical.
plain_url() { printf 'https://example.com/x/y.git'; }

# --- unit: manifest_redact --------------------------------------------------

@test "redact: credentialed URL loses its userinfo but keeps scheme and host" {
    local u; u="$(cred_url)"
    run manifest_redact "Origin:   $u"
    [ "$status" -eq 0 ]
    [ "$output" = "Origin:   $(cred_redacted)" ]
    refute grep -Fq "$(cred_needle)" <<<"$output"
}

@test "redact: non-credentialed URL is returned unchanged (positive control)" {
    local u; u="$(plain_url)"
    run manifest_redact "Origin:   $u"
    [ "$status" -eq 0 ]
    [ "$output" = "Origin:   $u" ]
    refute grep -Fq "REDACTED" <<<"$output"
}

@test "redact: scp-style SSH remote (git@host:path) is left alone" {
    run manifest_redact "Origin:   git@github.com:fidenceio/manifest.cli.git"
    [ "$status" -eq 0 ]
    [ "$output" = "Origin:   git@github.com:fidenceio/manifest.cli.git" ]
}

@test "redact: an @ later in the path is not mistaken for userinfo" {
    # Guards the over-redaction direction: excluding '/' from the password class
    # is what keeps `host:port/path@ref` intact (RFC 3986 forbids a raw '/' in
    # userinfo anyway, and git's parser ends the authority at the first '/').
    run manifest_redact "http://host:8443/deploy@v1 and https://example.com:8443/p"
    [ "$status" -eq 0 ]
    [ "$output" = "http://host:8443/deploy@v1 and https://example.com:8443/p" ]
}

# --- site 1: the apply-target banner (bare echo in the repo-scope gate) -----

@test "apply banner: Origin line redacts a credentialed origin remote" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@example.com
    git config user.name "Test User"
    git remote add origin "$(cred_url)"
    echo "1.2.3" > VERSION

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" \
        run manifest_repo_scope_confirm_apply "$SCRATCH" "manifest ship repo patch -y" < /dev/null

    [ "$status" -eq 0 ]
    grep -q "Apply target repository" <<<"$output"
    grep -Fq "Origin:   $(cred_redacted)" <<<"$output"
    refute grep -Fq "$(cred_needle)" <<<"$output"
}

@test "apply banner: a plain origin remote prints verbatim (positive control)" {
    cd "$SCRATCH"
    git init -q
    git config user.email t@example.com
    git config user.name "Test User"
    git remote add origin "$(plain_url)"
    echo "1.2.3" > VERSION

    MANIFEST_CLI_PROJECT_ROOT="$SCRATCH" \
        run manifest_repo_scope_confirm_apply "$SCRATCH" "manifest ship repo patch -y" < /dev/null

    [ "$status" -eq 0 ]
    grep -Fq "Origin:   $(plain_url)" <<<"$output"
    refute grep -Fq "REDACTED" <<<"$output"
}

# --- sites 2 + 4: the fleet roster remote (status --json, bootstrap preview) -

# Member `plain` carries an ordinary remote (positive control), member `creds`
# the credentialed one. `creds` is deliberately absent on disk so the SAME member
# also drives the bootstrap preview site.
#
# The URLs live in the two places a remote can now be DERIVED from, because §45
# removed the roster's REMOTE_URL column: `plain` is cloned, so its own `origin`
# answers; `creds` is not, so the fleet config answers. A credential can still
# reach the config by hand — which is exactly what this fixture does, and why
# display redaction is still the contract under test.
_mk_cred_fleet() {
    local root="$1"
    mkdir -p "$root/svc/plain"
    git -C "$root/svc/plain" init -q
    git -C "$root/svc/plain" config user.email t@example.com
    git -C "$root/svc/plain" config user.name t
    git -C "$root/svc/plain" remote add origin "$(plain_url)"
    echo "1.0.0" > "$root/svc/plain/VERSION"
    git -C "$root/svc/plain" add VERSION
    git -C "$root/svc/plain" commit -qm "init plain"
    {
        echo "# MANIFEST FLEET — Directory Inventory"
        echo "# Root: $root"
        echo "# Depth: 2"
        printf "# SELECT\tNAME\tPATH\tHAS_GIT\tBRANCH\n"
        printf "true\tplain\tsvc/plain\ttrue\tmain\n"
        printf "true\tcreds\tsvc/creds\ttrue\tmain\n"
    } > "$root/manifest.fleet.tsv"
    {
        echo "fleet:"
        echo "  name: cred-fleet"
        echo "services:"
        echo "  creds:"
        echo "    path: \"./svc/creds\""
        printf '    url: "%s"\n' "$(cred_url)"
    } > "$root/manifest.fleet.config.yaml"
}

# §45: the roster must carry no remote URL, so a credential cannot be persisted
# into the one fleet file that is committed and pushed by design.
@test "fleet roster: no writer can put a credentialed URL in manifest.fleet.tsv" {
    load_modules "fleet/manifest-fleet-detect.sh"
    run _manifest_fleet_tsv_write_row "true" "creds" "svc/creds" "true" "$(cred_url)"
    [ "$status" -ne 0 ]
    refute grep -Fq "$(cred_needle)" <<<"$output"

    # Positive control: the same writer accepts an ordinary row, so the refusal
    # above is the credential and not the writer simply always failing.
    run _manifest_fleet_tsv_write_row "true" "plain" "svc/plain" "true" "main"
    [ "$status" -eq 0 ]
    [ "$output" = "$(printf 'true\tplain\tsvc/plain\ttrue\tmain')" ]
}

@test "status fleet --json: remote_url is redacted, plain remote untouched" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_cred_fleet "$SCRATCH"

    run _manifest_status_fleet "$SCRATCH" "true" "off"
    [ "$status" -eq 0 ]
    refute grep -Fq "$(cred_needle)" <<<"$output"

    local plain_remote cred_remote
    plain_remote="$(yq e '.repositories[] | select(.name == "plain") | .remote_url' - <<<"$output")"
    cred_remote="$(yq e '.repositories[] | select(.name == "creds") | .remote_url' - <<<"$output")"
    # Positive control first: proves the field is still populated at all.
    [ "$plain_remote" = "$(plain_url)" ]
    [ "$cred_remote" = "$(cred_redacted)" ]
}

@test "status fleet --bootstrap: preview redacts a credentialed remote" {
    if ! command -v yq >/dev/null 2>&1; then
        skip "yq not installed"
    fi
    _mk_cred_fleet "$SCRATCH"
    [ ! -d "$SCRATCH/svc/creds" ]

    run _manifest_status_fleet "$SCRATCH" "false" "preview"
    [ "$status" -eq 0 ]
    grep -q "Bootstrap preview" <<<"$output"
    grep -Fq "would clone from $(cred_redacted)" <<<"$output"
    refute grep -Fq "$(cred_needle)" <<<"$output"
}

# --- site 3: the tap-push SUCCESS line (the failure sibling already redacts) -

@test "tap push: SUCCESS line redacts a credentialed push remote" {
    local tap="$SCRATCH/tap"
    mkdir -p "$tap/Formula"
    git -C "$tap" init -q
    git -C "$tap" config user.email t@example.com
    git -C "$tap" config user.name t
    echo "v0" > "$tap/Formula/manifest.rb"
    git -C "$tap" add Formula/manifest.rb
    git -C "$tap" commit -qm "seed"

    local cli_formula="$SCRATCH/manifest.rb"
    echo "v9-formula" > "$cli_formula"

    # Resolve the real git BEFORE prepending the stub dir, so the stub delegates
    # to the real binary and not back to itself. The stub makes `git push`
    # succeed without a reachable remote, which is the only way to reach the
    # SUCCESS branch while the configured URL carries credentials.
    local real_git stub_dir
    real_git="$(command -v git)"
    stub_dir="$SCRATCH/stub-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "push" ]; then
    echo "Everything up-to-date"
    exit 0
fi
exec "$real_git" "\$@"
STUB
    chmod +x "$stub_dir/git"
    PATH="$stub_dir:$PATH"
    export PATH

    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="$(cred_url)"

    run manifest_homebrew_tap_push_formula "$tap" "$cli_formula" "v9"
    [ "$status" -eq 0 ]
    grep -Fq "Pushed to homebrew-tap repo ($(cred_redacted))" <<<"$output"
    refute grep -Fq "$(cred_needle)" <<<"$output"
}

@test "tap push: SUCCESS line prints a plain push remote verbatim (control)" {
    local tap="$SCRATCH/tap"
    mkdir -p "$tap/Formula"
    git -C "$tap" init -q
    git -C "$tap" config user.email t@example.com
    git -C "$tap" config user.name t
    echo "v0" > "$tap/Formula/manifest.rb"
    git -C "$tap" add Formula/manifest.rb
    git -C "$tap" commit -qm "seed"

    local cli_formula="$SCRATCH/manifest.rb"
    echo "v9-formula" > "$cli_formula"

    local real_git stub_dir
    real_git="$(command -v git)"
    stub_dir="$SCRATCH/stub-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "push" ]; then
    echo "Everything up-to-date"
    exit 0
fi
exec "$real_git" "\$@"
STUB
    chmod +x "$stub_dir/git"
    PATH="$stub_dir:$PATH"
    export PATH

    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="$(plain_url)"

    run manifest_homebrew_tap_push_formula "$tap" "$cli_formula" "v9"
    [ "$status" -eq 0 ]
    grep -Fq "Pushed to homebrew-tap repo ($(plain_url))" <<<"$output"
    refute grep -Fq "REDACTED" <<<"$output"
}
