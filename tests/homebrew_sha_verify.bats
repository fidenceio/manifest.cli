#!/usr/bin/env bats
#
# C3 finding #3 (tautological sha256): the generated Homebrew formula must be
# verified against an INDEPENDENT recompute of the real tarball, not against the
# value the generator just wrote into the file. These tests prove the check can
# actually fail — a formula whose sha256 does not match the artifact a user would
# download is refused.

load 'helpers/setup'

setup() {
    load_modules "core/manifest-core.sh"
    SCRATCH="$(mk_scratch)"
    export PROJECT_ROOT="$SCRATCH/repo"
    mkdir -p "$PROJECT_ROOT/formula"
    cd "$PROJECT_ROOT"
    git init -q .
    git config user.email "test@example.com"
    git config user.name "Test"
    git remote add origin "git@github.com:fidenceio/manifest.cli.git"
    echo "1.2.3" > VERSION
    cat > formula/manifest.rb <<'RUBY'
class Manifest < Formula
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
RUBY

    export MANIFEST_CLI_TARBALL_SHA_RETRY_DELAY=0

    # Resolve the sha tool the same way the production code does.
    if command -v shasum >/dev/null 2>&1; then
        SHA_CMD="shasum -a 256"
    else
        SHA_CMD="sha256sum"
    fi

    # Short-circuit the publish steps after generation so the test isolates the
    # verification path.
    PUSHED_FORMULA="$SCRATCH/pushed-formula.rb"
    manifest_homebrew_tap_push_formula() { cp "$2" "$PUSHED_FORMULA"; return 0; }
    manifest_refresh_homebrew_tap_checkouts() { return 0; }
    brew() { case "$1" in --prefix) echo "$SCRATCH/brewprefix" ;; *) return 0 ;; esac; }
    mkdir -p "$SCRATCH/brewprefix/Library/Taps/fidenceio/homebrew-tap/Formula"
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_TARBALL_SHA_RETRY_DELAY MANIFEST_CLI_TARBALL_SHA_RETRIES
    unset MANIFEST_CLI_SKIP_FORMULA_SHA_VERIFY
}

_sha_of() {
    printf '%s' "$1" | $SHA_CMD | cut -d' ' -f1
}

# Install a curl stub that emits BYTES_1 for the first N invocations (the
# generator's hashing fetch) and BYTES_2 thereafter (the independent verify
# fetch). When BYTES_1 != BYTES_2 the embedded sha cannot match the verify hash.
_install_split_curl() {
    local first_n="$1" bytes1="$2" bytes2="$3"
    local stub_dir="$SCRATCH/stub-bin"
    local count_file="$SCRATCH/curl-count"
    echo 0 > "$count_file"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/curl" <<STUB
#!/usr/bin/env bash
count_file="$count_file"
n="\$(cat "\$count_file" 2>/dev/null || echo 0)"
echo "\$((n + 1))" > "\$count_file"
if [ "\$n" -lt "$first_n" ]; then
    printf '%s' "$bytes1"
else
    printf '%s' "$bytes2"
fi
exit 0
STUB
    chmod +x "$stub_dir/curl"
    PATH="$stub_dir:$PATH"
    export PATH
}

# --- unit: the verifier itself ----------------------------------------------

@test "verify: matching sha against tarball returns success" {
    _install_split_curl 0 "payload" "payload"
    local expected; expected="$(_sha_of "payload")"
    run manifest_formula_verify_sha256_against_tarball "$expected" \
        "https://example.invalid/t.tar.gz" "$SHA_CMD"
    [ "$status" -eq 0 ]
}

@test "verify: WRONG sha against tarball fails closed (not tautological)" {
    _install_split_curl 0 "payload" "payload"
    local wrong="deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    run manifest_formula_verify_sha256_against_tarball "$wrong" \
        "https://example.invalid/t.tar.gz" "$SHA_CMD"
    [ "$status" -eq 1 ]
    echo "$output" | grep -q "sha256 mismatch"
}

@test "verify: explicit opt-out skips verification loudly" {
    export MANIFEST_CLI_SKIP_FORMULA_SHA_VERIFY=true
    run manifest_formula_verify_sha256_against_tarball "anything" \
        "https://example.invalid/t.tar.gz" "$SHA_CMD"
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "independent verification skipped"
}

# --- the extractor reads the file, not a variable ---------------------------

@test "extract: reads the sha256 actually written in the formula file" {
    local f="$SCRATCH/f.rb"
    cat > "$f" <<'RUBY'
class Manifest < Formula
  url "https://example.invalid/x.tar.gz"
  sha256 "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd"
end
RUBY
    run manifest_formula_extract_sha256 "$f"
    [ "$status" -eq 0 ]
    [ "$output" = "abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd" ]
}

# --- end-to-end: a tampered tarball between generate and verify is rejected ---

@test "publish: refuses when the tarball changes between generation and verification" {
    # Invocation 1 (generation) hashes "good-bytes"; invocation 2 (verify) sees
    # "tampered-bytes". The embedded sha is of good-bytes, the verify hash is of
    # tampered-bytes — they differ, so publish must abort and push nothing.
    _install_split_curl 1 "good-bytes" "tampered-bytes"
    run update_homebrew_formula
    [ "$status" -ne 0 ]
    echo "$output" | grep -q "does not independently verify"
    [ ! -f "$PUSHED_FORMULA" ]
}

@test "publish: succeeds when the independent verification matches" {
    # Same bytes on every fetch -> embedded sha == verify hash -> publish ok.
    _install_split_curl 0 "stable-bytes" "stable-bytes"
    run update_homebrew_formula
    [ "$status" -eq 0 ]
    echo "$output" | grep -q "independently verified"
    [ -f "$PUSHED_FORMULA" ]
    local expected; expected="$(_sha_of "stable-bytes")"
    grep -q "sha256 \"${expected}\"" "$PUSHED_FORMULA"
}
