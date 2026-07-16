#!/usr/bin/env bats
#
# bootstrap.sh formula-derived checksum paths. bootstrap_verify.bats covers the
# env-pin flows (MANIFEST_CLI_INSTALL_SHA256); these tests cover the default
# flow where the expected sha256 comes from the published Homebrew tap formula:
#   - a formula whose url matches the resolved tag and whose sha256 matches the
#     tarball → verification succeeds and the verified installer runs
#   - a formula whose url points at a DIFFERENT tag → fail closed with no
#     download and no execution (the tag-mismatch guard at bootstrap.sh:73-82)
#   - a formula for the right tag whose sha256 does not match the bytes →
#     checksum-mismatch abort before any code runs
#
# Fixture machinery reuses bootstrap_verify.bats: a fake release tarball plus a
# curl stub on PATH; the stub additionally serves $SCRATCH/formula.rb for the
# tap-formula URL, so no file:// support is needed in bootstrap.sh.

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

    # Fake release tree tarball with a marker install-cli.sh that records it ran.
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

    # Stub curl: `-o <file>` (the tarball download) copies the fixture tarball;
    # a bare fetch of the tap formula URL serves $SCRATCH/formula.rb; anything
    # else returns empty.
    STUB="$SCRATCH/bin"
    mkdir -p "$STUB"
    cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
out=""
prev=""
url=""
for a in "\$@"; do
    if [ "\$prev" = "-o" ]; then out="\$a"; fi
    case "\$a" in http://*|https://*) url="\$a" ;; esac
    prev="\$a"
done
if [ -n "\$out" ]; then
    cp "$SCRATCH/release.tar.gz" "\$out"
    exit 0
fi
case "\$url" in
    *homebrew-tap*Formula/manifest.rb) cat "$SCRATCH/formula.rb" 2>/dev/null; exit 0 ;;
esac
exit 0
EOF
    chmod +x "$STUB/curl"
    export PATH="$STUB:$PATH"
}

teardown() {
    cd /tmp || true
    [ -n "$SCRATCH" ] && [ -d "$SCRATCH" ] && rm -rf "$SCRATCH"
}

# Write the fixture tap formula for a given tag + sha256.
_write_formula() {
    local tag="$1" sha="$2"
    cat > "$SCRATCH/formula.rb" <<EOF
class Manifest < Formula
  desc "Fixture formula"
  homepage "https://github.com/fidenceio/manifest.cli"
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/${tag}.tar.gz"
  sha256 "${sha}"
  license "MIT"
end
EOF
}

@test "bootstrap: formula-published checksum verifies the tarball without a pin" {
    _write_formula "1.0.0" "$GOOD_SHA"
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" run bash "$BOOTSTRAP"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "Fetching the published checksum from the Homebrew tap formula"
    echo "$output" | grep -q "Checksum verified"
    # The verified installer ran, with --manual forwarded.
    [ -f "$SCRATCH/installer.ran" ]
    grep -q "INSTALLER_RAN" "$SCRATCH/installer.ran"
    grep -q -- "--manual" "$SCRATCH/installer.ran"
}

@test "bootstrap: formula url for a different tag fails closed before any download" {
    # The sha itself is even correct — the tag mismatch alone must refuse,
    # because a formula for another release can never vouch for this tarball.
    _write_formula "9.9.9" "$GOOD_SHA"
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" run bash "$BOOTSTRAP"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "No published checksum found for 1.0.0"
    # Fail-closed happens before the payload download and before execution.
    ! echo "$output" | grep -q "Downloading"
    [ ! -f "$SCRATCH/installer.ran" ]
}

@test "bootstrap: formula sha for the right tag that mismatches the bytes aborts" {
    _write_formula "1.0.0" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    MANIFEST_CLI_INSTALL_VERSION="1.0.0" run bash "$BOOTSTRAP"
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "Checksum mismatch"
    [ ! -f "$SCRATCH/installer.ran" ]
}
