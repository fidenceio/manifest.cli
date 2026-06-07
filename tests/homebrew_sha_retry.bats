#!/usr/bin/env bats
#
# §8.1b-2: the release-tarball SHA256 fetch in update_homebrew_formula must
# retry with a bounded backoff (GitHub's tag tarball can lag the tag push),
# succeed once the tarball appears, and fail loud after exhausting retries
# without writing a bad/empty sha into the formula. Tests run with delay 0
# via MANIFEST_CLI_TARBALL_SHA_RETRY_DELAY=0 so there is no real sleep.

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
    # Canonical origin so should_update_homebrew_for_repo passes.
    git remote add origin "git@github.com:fidenceio/manifest.cli.git"
    echo "1.2.3" > VERSION
    cat > formula/manifest.rb <<'RUBY'
class Manifest < Formula
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
RUBY

    # No real network/sleep: stub curl, and zero the backoff delay.
    export MANIFEST_CLI_TARBALL_SHA_RETRY_DELAY=0

    # Counter file so the curl stub can fail a fixed number of times.
    CURL_FAILS_FILE="$SCRATCH/curl-fails"

    # Short-circuit everything AFTER the sha fetch so the test isolates the
    # retry loop: the sha is written via sed (real GNU sed on PATH via wrapper),
    # then the tap sync / refresh are stubbed to no-ops.
    manifest_homebrew_tap_push_formula() { return 0; }
    manifest_refresh_homebrew_tap_checkouts() { return 0; }
    # Provide a fake tap dir with a Formula/ so the `[ -d ]` branch is taken.
    brew() {
        case "$1" in
            --prefix) echo "$SCRATCH/brewprefix" ;;
            *) return 0 ;;
        esac
    }
    mkdir -p "$SCRATCH/brewprefix/Library/Taps/fidenceio/homebrew-tap/Formula"

    install_curl_stub() {
        local fails="$1"
        echo "$fails" > "$CURL_FAILS_FILE"
        local stub_dir="$SCRATCH/stub-bin"
        mkdir -p "$stub_dir"
        cat > "$stub_dir/curl" <<STUB
#!/usr/bin/env bash
# Fail the first N invocations (transient 404/empty), then emit tarball bytes.
fails_file="$CURL_FAILS_FILE"
remaining="\$(cat "\$fails_file" 2>/dev/null || echo 0)"
if [ "\$remaining" -gt 0 ]; then
    echo "\$((remaining - 1))" > "\$fails_file"
    exit 22   # curl: HTTP error (e.g. 404) under -f
fi
printf 'tarball-bytes-for-tag\n'
exit 0
STUB
        chmod +x "$stub_dir/curl"
        PATH="$stub_dir:$PATH"
        export PATH
    }
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_TARBALL_SHA_RETRY_DELAY MANIFEST_CLI_TARBALL_SHA_RETRIES
}

@test "SHA256 fetch retries on transient failure then succeeds" {
    # Fail twice, succeed on the third attempt (within the default 5 retries).
    install_curl_stub 2

    run update_homebrew_formula
    [ "$status" -eq 0 ]
    [[ "$output" == *"retrying in 0s"* ]]
    [[ "$output" == *"SHA256:"* ]]
    [[ "$output" == *"Homebrew formula update complete"* ]]

    # The formula's sha256 was rewritten to the real digest of the stub bytes
    # — not left as the all-zero placeholder.
    local expected
    if command -v shasum >/dev/null 2>&1; then
        expected="$(printf 'tarball-bytes-for-tag\n' | shasum -a 256 | cut -d' ' -f1)"
    else
        expected="$(printf 'tarball-bytes-for-tag\n' | sha256sum | cut -d' ' -f1)"
    fi
    grep -q "sha256 \"${expected}\"" "$PROJECT_ROOT/formula/manifest.rb"
    ! grep -q 'sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$PROJECT_ROOT/formula/manifest.rb"
}

@test "SHA256 fetch fails loud after exhausting retries and writes no bad sha" {
    # Fail more times than the retry budget allows.
    export MANIFEST_CLI_TARBALL_SHA_RETRIES=3
    install_curl_stub 99

    run update_homebrew_formula
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to fetch tarball SHA256"* ]]
    [[ "$output" == *"after 3 attempt(s)"* ]]

    # The formula must be untouched: still the all-zero placeholder, never an
    # empty or partial sha.
    grep -q 'sha256 "0000000000000000000000000000000000000000000000000000000000000000"' "$PROJECT_ROOT/formula/manifest.rb"
    ! grep -q 'sha256 ""' "$PROJECT_ROOT/formula/manifest.rb"
}

@test "SHA256 fetch succeeds on first attempt with no retry message" {
    install_curl_stub 0

    run update_homebrew_formula
    [ "$status" -eq 0 ]
    [[ "$output" == *"SHA256:"* ]]
    [[ "$output" != *"retrying in"* ]]
}
