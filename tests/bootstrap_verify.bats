#!/usr/bin/env bats
#
# C3 finding #4 (curl|bash): the documented install path must download and VERIFY
# before executing. bootstrap.sh downloads a pinned release tarball, checks its
# sha256 against an expected value, and only runs the installer from a verified
# tree. These tests prove a bad checksum aborts BEFORE any code runs, and a good
# checksum runs the verified installer.

load 'helpers/setup'

setup() {
    SCRATCH="$(mk_scratch)"
    export SCRATCH
    export TMPDIR="$SCRATCH/tmp"
    mkdir -p "$TMPDIR"

    BOOTSTRAP="$TEST_REPO_ROOT/bootstrap.sh"

    if command -v shasum >/dev/null 2>&1; then
        SHA_CMD="shasum -a 256"
    else
        SHA_CMD="sha256sum"
    fi

    # Build a fake "release tree" tarball whose top dir matches the importer's
    # expected manifest.cli-<tag> layout, containing a marker install-cli.sh that
    # records it ran (and the args it got).
    PKGROOT="$SCRATCH/pkg"
    mkdir -p "$PKGROOT/manifest.cli-1.0.0"
    cat > "$PKGROOT/manifest.cli-1.0.0/install-cli.sh" <<EOF
#!/usr/bin/env bash
echo "INSTALLER_RAN args=[\$*]" > "$SCRATCH/installer.ran"
EOF
    chmod +x "$PKGROOT/manifest.cli-1.0.0/install-cli.sh"
    ( cd "$PKGROOT" && tar -czf "$SCRATCH/release.tar.gz" "manifest.cli-1.0.0" )
    GOOD_SHA="$($SHA_CMD "$SCRATCH/release.tar.gz" | cut -d' ' -f1)"
    export GOOD_SHA

    # Stub curl: the tarball download (-o <file>) copies our release tarball; any
    # other curl (api/formula fetch) returns empty so the test relies on pins.
    # Missing tarball fails loud — a silent cp failure used to look like a
    # checksum miss with no useful diagnostic.
    STUB="$SCRATCH/bin"
    mkdir -p "$STUB"
    cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
out=""
prev=""
for a in "\$@"; do
    if [ "\$prev" = "-o" ]; then out="\$a"; fi
    prev="\$a"
done
if [ -n "\$out" ]; then
    if [ ! -f "$SCRATCH/release.tar.gz" ]; then
        echo "stub curl: missing fixture tarball at $SCRATCH/release.tar.gz" >&2
        exit 1
    fi
    cp "$SCRATCH/release.tar.gz" "\$out" || exit 1
    exit 0
fi
exit 0   # api/formula fetch: empty
EOF
    chmod +x "$STUB/curl"
    export PATH="$STUB:$PATH"
}

# Dump the full captured bootstrap output when a needle is missing so the
# fail-closed path is named in CI logs (not just a silent grep miss).
_assert_output_contains() {
    local needle="$1"
    if ! printf '%s\n' "$output" | grep -q -- "$needle"; then
        echo "expected output to contain: ${needle}" >&2
        echo "----- bootstrap output -----" >&2
        printf '%s\n' "$output" >&2
        echo "----- end output (status=${status}) -----" >&2
        return 1
    fi
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

@test "bootstrap: a MATCHING pinned sha runs the verified installer" {
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" MANIFEST_CLI_INSTALL_SHA256="$GOOD_SHA" run bash "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    _assert_output_contains "Checksum verified"
    [ -f "$SCRATCH/installer.ran" ]
    grep -q "INSTALLER_RAN" "$SCRATCH/installer.ran"
    # --manual is forwarded so a verified source-tree install is performed.
    grep -q -- "--manual" "$SCRATCH/installer.ran"
}

@test "bootstrap: a WRONG pinned sha aborts BEFORE running the installer" {
    local wrong="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" MANIFEST_CLI_INSTALL_SHA256="$wrong" run bash "$BOOTSTRAP"
    [ "$status" -ne 0 ]
    _assert_output_contains "Downloading"
    _assert_output_contains "Checksum mismatch"
    # The installer must NOT have run — verification gates execution.
    [ ! -f "$SCRATCH/installer.ran" ]
}

@test "bootstrap: a malformed pinned sha is rejected up front" {
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" MANIFEST_CLI_INSTALL_SHA256="not-a-real-digest" run bash "$BOOTSTRAP"
    [ "$status" -ne 0 ]
    _assert_output_contains "well-formed digest"
    [ ! -f "$SCRATCH/installer.ran" ]
}

@test "bootstrap: no checksum available (no pin, empty formula) fails closed" {
    # No MANIFEST_CLI_INSTALL_SHA256, and the stubbed formula fetch returns empty -> there is
    # no expected checksum, so the bootstrap must refuse rather than run blind.
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" run bash "$BOOTSTRAP"
    [ "$status" -ne 0 ]
    _assert_output_contains "No published checksum found"
    [ ! -f "$SCRATCH/installer.ran" ]
}
