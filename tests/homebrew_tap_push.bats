#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules "core/manifest-core.sh"
    SCRATCH="$(mk_scratch)"
    git config --global init.defaultBranch main >/dev/null 2>&1 || true
}

teardown() {
    cd /tmp
    rm -rf "$SCRATCH"
    unset MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL
    unset MANIFEST_CLI_HOMEBREW_TAP_BRANCH
}

seed_tap_remote() {
    local remote="$SCRATCH/homebrew-tap.git"
    local writer="$SCRATCH/writer"

    git init --bare -q "$remote"
    git clone -q "$remote" "$writer"
    git -C "$writer" checkout -q -b main
    git -C "$writer" config user.email "test@example.com"
    git -C "$writer" config user.name "Test"
    mkdir -p "$writer/Formula"
    echo "v0" > "$writer/Formula/manifest.rb"
    git -C "$writer" add Formula/manifest.rb
    git -C "$writer" commit -qm "Initial formula"
    git -C "$writer" push -q -u origin main
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main

    echo "$remote"
}

@test "tap push targets MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL regardless of checkout origin" {
    local remote tap
    remote="$(seed_tap_remote)"

    # Clone the tap with an HTTPS-looking bogus origin to prove the push does
    # NOT rely on this checkout's `origin` URL.
    tap="$SCRATCH/tap"
    git clone -q "$remote" "$tap"
    git -C "$tap" config user.email "test@example.com"
    git -C "$tap" config user.name "Test"
    git -C "$tap" remote set-url origin "https://example.invalid/nope.git"

    local cli_formula="$SCRATCH/manifest.rb"
    echo "v3-formula" > "$cli_formula"

    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="$remote"

    run manifest_homebrew_tap_push_formula "$tap" "$cli_formula" "v3"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushed to homebrew-tap repo (${remote})"* ]]

    # Verify the bare remote actually received the commit.
    local verify="$SCRATCH/verify"
    git clone -q "$remote" "$verify"
    [ "$(cat "$verify/Formula/manifest.rb")" = "v3-formula" ]
    [[ "$(git -C "$verify" log -1 --format=%s)" == "Update formula to v3" ]]
}

@test "tap push returns non-zero when the remote URL is unreachable" {
    local remote tap
    remote="$(seed_tap_remote)"
    tap="$SCRATCH/tap"
    git clone -q "$remote" "$tap"
    git -C "$tap" config user.email "test@example.com"
    git -C "$tap" config user.name "Test"

    local cli_formula="$SCRATCH/manifest.rb"
    echo "v4-formula" > "$cli_formula"

    export MANIFEST_CLI_HOMEBREW_TAP_REMOTE_URL="$SCRATCH/does-not-exist.git"

    run manifest_homebrew_tap_push_formula "$tap" "$cli_formula" "v4"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Failed to push formula to homebrew-tap repo"* ]]
}

@test "update_homebrew_formula gates out for non-canonical origin (push helper never reached)" {
    # Build a scratch repo with a non-canonical origin and the bare minimum
    # of files. The structural-canonical fallback in manifest_is_canonical_repo
    # only fires if install-cli.sh + scripts/manifest-cli-wrapper.sh + modules/
    # AND formula/manifest.rb all exist — by staging only the formula, the
    # fallback misses and the slug-based check is what decides.
    cd "$SCRATCH"
    git init -q
    git config user.email "test@example.com"
    git config user.name "Test"
    git remote add origin "git@github.com:other-org/other-repo.git"
    mkdir -p formula
    cat > formula/manifest.rb <<'RUBY'
class Manifest < Formula
  url "https://github.com/fidenceio/manifest.cli/archive/refs/tags/v0.0.0.tar.gz"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"
end
RUBY
    echo "0.0.0" > VERSION

    # Sentinel that would prove the push helper was reached. Stub git so a
    # `git push` writes the sentinel and exits non-zero — if the gate works,
    # the sentinel must NOT exist after the run, and update_homebrew_formula
    # must return 0 with the "Skipping" message.
    local sentinel="$SCRATCH/push-helper-reached"
    local real_git
    real_git="$(command -v git)"

    local stub_dir="$SCRATCH/stub-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "push" ]; then
    echo "FAIL: push reached for non-canonical repo" >&2
    touch "$sentinel"
    exit 99
fi
exec "$real_git" "\$@"
STUB
    chmod +x "$stub_dir/git"
    PATH="$stub_dir:$PATH"
    export PATH

    unset MANIFEST_CLI_CANONICAL_REPO_SLUGS
    PROJECT_ROOT="$SCRATCH" run update_homebrew_formula
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping Homebrew formula update for repository"* ]]
    [[ "$output" == *"other-org/other-repo"* ]]
    [ ! -f "$sentinel" ]
}

@test "tap push surfaces the insteadOf hint when HTTPS auth fails" {
    local remote tap
    remote="$(seed_tap_remote)"
    tap="$SCRATCH/tap"
    git clone -q "$remote" "$tap"
    git -C "$tap" config user.email "test@example.com"
    git -C "$tap" config user.name "Test"

    local cli_formula="$SCRATCH/manifest.rb"
    echo "v5-formula" > "$cli_formula"

    # Resolve the real git binary BEFORE prepending the stub dir to PATH so
    # the stub's delegation points at the real binary, not back at itself.
    local real_git
    real_git="$(command -v git)"

    local stub_dir="$SCRATCH/stub-bin"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/git" <<STUB
#!/usr/bin/env bash
if [ "\$1" = "push" ]; then
    echo "fatal: could not read Username for 'https://github.com': Device not configured" >&2
    exit 128
fi
exec "$real_git" "\$@"
STUB
    chmod +x "$stub_dir/git"
    PATH="$stub_dir:$PATH"
    export PATH

    run manifest_homebrew_tap_push_formula "$tap" "$cli_formula" "v5"
    [ "$status" -ne 0 ]
    [[ "$output" == *"insteadOf"* ]]
    [[ "$output" == *'url."git@github.com:fidenceio/"'* ]]
}
