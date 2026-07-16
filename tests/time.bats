#!/usr/bin/env bats

load 'helpers/setup'

setup() {
    load_modules system/manifest-os.sh system/manifest-time.sh
    SCRATCH="$(mk_scratch)"
    export MANIFEST_CLI_CACHE_DIR="$SCRATCH/cache"
    # Make sure no real env-customized servers leak in.
    unset MANIFEST_CLI_TIME_SERVER1 MANIFEST_CLI_TIME_SERVER2 \
          MANIFEST_CLI_TIME_SERVER3 MANIFEST_CLI_TIME_SERVER4
}

teardown() {
    rm -rf "$SCRATCH"
}

# Install a curl stub onto PATH so query_time_server can be exercised without
# any network. mode "ok" answers both the Cloudflare-trace and HEAD-fallback
# shapes; mode "fail" simulates a hard curl failure (exit 7).
install_curl_stub() {
    local mode="$1"
    mkdir -p "$SCRATCH/bin"
    if [ "$mode" = "ok" ]; then
        cat > "$SCRATCH/bin/curl" <<'EOF'
#!/usr/bin/env bash
url=""
for a in "$@"; do url="$a"; done
if [[ "$url" == *"/cdn-cgi/trace"* ]]; then
    printf 'fl=999f99\nh=www.cloudflare.com\nts=%s.123456\n__META__|200|1.2.3.4\n' "$(date -u +%s)"
else
    printf '200|%s|5.6.7.8' "$(date -u '+%a, %d %b %Y %H:%M:%S GMT')"
fi
EOF
    else
        cat > "$SCRATCH/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "curl: (7) stubbed failure" >&2
exit 7
EOF
    fi
    chmod +x "$SCRATCH/bin/curl"
    export PATH="$SCRATCH/bin:$PATH"
}

@test "time: format_timestamp delegates to format_timestamp_cross_platform" {
    run format_timestamp 1700000000 '+%Y-%m-%d'
    [ "$status" -eq 0 ]
    [[ "$output" == 2023-* ]]
}

@test "time: _parse_http_date parses standard RFC 7231 date string" {
    # Build a date string from a known epoch so the weekday is guaranteed
    # to be self-consistent on both BSD and GNU date.
    local epoch=1700000000 date_str expected
    if date_str=$(date -u -r "$epoch" "+%a, %d %b %Y %H:%M:%S GMT" 2>/dev/null); then :
    else date_str=$(date -u -d "@$epoch" "+%a, %d %b %Y %H:%M:%S GMT"); fi
    run _parse_http_date "$date_str"
    [ "$status" -eq 0 ]
    [ "$output" = "$epoch" ]
}

@test "time: _parse_http_date returns non-zero on malformed input" {
    run _parse_http_date "not a real date"
    [ "$status" -ne 0 ]
}

@test "time: _manifest_time_apply_offset subtracts positive offset (system ahead)" {
    local sys
    sys=$(date -u +%s)
    run _manifest_time_apply_offset "+10.000000"
    [ "$status" -eq 0 ]
    # Offset is integer seconds; result should be sys-10 ± 1 (in case the clock ticked).
    [ "$output" -ge $((sys - 12)) ]
    [ "$output" -le $((sys - 8)) ]
}

@test "time: _manifest_time_apply_offset adds when offset is negative (system behind)" {
    local sys
    sys=$(date -u +%s)
    run _manifest_time_apply_offset "-5.000000"
    [ "$status" -eq 0 ]
    [ "$output" -ge $((sys + 3)) ]
    [ "$output" -le $((sys + 7)) ]
}

@test "time: _manifest_time_apply_offset falls back to system time on malformed offset" {
    local sys
    sys=$(date -u +%s)
    run _manifest_time_apply_offset "garbage"
    [ "$status" -eq 0 ]
    [ "$output" -ge $((sys - 2)) ]
    [ "$output" -le $((sys + 2)) ]
}

@test "time: cache write+read round-trips within TTL" {
    _manifest_time_write_cache_data "1700000000" "+1.000000" "0.500000" "https://example/x" "1.2.3.4"
    run _manifest_time_read_cache_data "fresh"
    [ "$status" -eq 0 ]
    # ts gets aged by (now - saved_at), but server/ip/method/offset are exact.
    [[ "$output" == *"|+1.000000|0.500000|https://example/x|1.2.3.4|cache" ]]
}

@test "time: cache miss when fresh TTL has expired" {
    MANIFEST_CLI_TIME_CACHE_TTL=0
    _manifest_time_write_cache_data "1700000000" "+0.000000" "0.000000" "x" "127.0.0.1"
    # Force the saved_at to be 5 seconds in the past so age > 0.
    local cache_file
    cache_file=$(_manifest_time_cache_file)
    local past=$(($(date -u +%s) - 5))
    sed -i.bak "s/MANIFEST_CLI_TIME_CACHE_SAVED_AT=.*/MANIFEST_CLI_TIME_CACHE_SAVED_AT=${past}/" "$cache_file"
    run _manifest_time_read_cache_data "fresh"
    [ "$status" -ne 0 ]
}

@test "time: stale cache read succeeds within STALE_MAX_AGE even after TTL" {
    MANIFEST_CLI_TIME_CACHE_TTL=0
    MANIFEST_CLI_TIME_CACHE_STALE_MAX_AGE=86400
    _manifest_time_write_cache_data "1700000000" "+2.000000" "0.000000" "stale-srv" "127.0.0.1"
    local cache_file past
    cache_file=$(_manifest_time_cache_file)
    past=$(($(date -u +%s) - 60))
    sed -i.bak "s/MANIFEST_CLI_TIME_CACHE_SAVED_AT=.*/MANIFEST_CLI_TIME_CACHE_SAVED_AT=${past}/" "$cache_file"
    run _manifest_time_read_cache_data "stale"
    [ "$status" -eq 0 ]
    [[ "$output" == *"|cache-stale" ]]
}

@test "time: _manifest_time_effective_servers returns defaults when no env override" {
    run _manifest_time_effective_servers
    [ "$status" -eq 0 ]
    [[ "$output" == *"cloudflare.com/cdn-cgi/trace"* ]]
    [[ "$output" == *"google.com/generate_204"* ]]
    [[ "$output" == *"apple.com"* ]]
}

@test "time: _manifest_time_effective_servers honors SERVER1..4 env overrides" {
    export MANIFEST_CLI_TIME_SERVER1="https://a.example/trace"
    export MANIFEST_CLI_TIME_SERVER2="https://b.example/trace"
    run _manifest_time_effective_servers
    [ "$status" -eq 0 ]
    [[ "$output" == *"a.example"* ]]
    [[ "$output" == *"b.example"* ]]
    [[ "$output" != *"cloudflare.com"* ]]
}

@test "time: get_time_timestamp uses fresh cache and exports MANIFEST_CLI_TIME_* vars" {
    _manifest_time_write_cache_data "1700000000" "+0.500000" "0.250000" "https://ex/t" "9.9.9.9"
    run get_time_timestamp
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚡ Using cached trusted timestamp"* ]]
    [[ "$output" == *"Method: cache"* ]]
}

@test "time: query_time_server parses Cloudflare trace body via stubbed curl" {
    install_curl_stub ok
    run query_time_server "https://www.cloudflare.com/cdn-cgi/trace" 2
    [ "$status" -eq 0 ]
    local off unc ip
    IFS='|' read -r off unc ip <<< "$output"
    # Offset is ~0 (stub answers with "now"); fractional part comes from ts=.
    [[ "$off" =~ ^[+-][0-9]+\.123456$ ]]
    [ "$unc" = "0.123456" ]
    [ "$ip" = "1.2.3.4" ]
}

@test "time: query_time_server parses HTTP Date header fallback via stubbed curl" {
    install_curl_stub ok
    run query_time_server "https://www.example.com" 2
    [ "$status" -eq 0 ]
    local off unc ip
    IFS='|' read -r off unc ip <<< "$output"
    [[ "$off" =~ ^[+-][0-9]+\.000000$ ]]
    [ "$unc" = "1.000000" ]
    [ "$ip" = "5.6.7.8" ]
}

@test "time: query_time_server fails cleanly on both paths when curl fails" {
    install_curl_stub fail
    run query_time_server "https://www.cloudflare.com/cdn-cgi/trace" 2
    [ "$status" -ne 0 ]
    [ -z "$output" ]
    run query_time_server "https://www.example.com" 2
    [ "$status" -ne 0 ]
    [ -z "$output" ]
}

@test "time: get_time_timestamp queries stubbed HTTPS server and writes the cache" {
    install_curl_stub ok
    export MANIFEST_CLI_TIME_RETRIES=1
    run get_time_timestamp
    [ "$status" -eq 0 ]
    [[ "$output" == *"✅ Trusted timestamp from https://www.cloudflare.com/cdn-cgi/trace"* ]]
    [[ "$output" == *"Method: https"* ]]
    local cache_file
    cache_file=$(_manifest_time_cache_file)
    [ -f "$cache_file" ]
    grep -q "MANIFEST_CLI_TIME_CACHE_SERVER=https://www.cloudflare.com/cdn-cgi/trace" "$cache_file"
    grep -q "MANIFEST_CLI_TIME_CACHE_SERVER_IP=1.2.3.4" "$cache_file"
}

@test "time: get_time_timestamp falls back to system time when every server fails" {
    install_curl_stub fail
    export MANIFEST_CLI_TIME_RETRIES=1
    run get_time_timestamp
    [ "$status" -eq 0 ]
    # All three default servers are tried once and reported as failed.
    local fails
    fails=$(echo "$output" | grep -c "⚠️  Failed to query")
    [ "$fails" -eq 3 ]
    [[ "$output" == *"🔄 No time servers responded, using system time"* ]]
    [[ "$output" == *"Method: system"* ]]
}

@test "time: _manifest_time_maybe_cleanup_cache removes stale cache files and stamps the marker" {
    local cache_dir now marker
    cache_dir=$(_manifest_time_cache_dir)
    mkdir -p "$cache_dir"
    echo "old" > "$cache_dir/timestamp.cache"
    touch -m -t 202001010000 "$cache_dir/timestamp.cache"
    # No cleanup marker yet -> cleanup runs immediately.
    _manifest_time_maybe_cleanup_cache
    [ ! -f "$cache_dir/timestamp.cache" ]
    now=$(date -u +%s)
    marker=$(cat "$cache_dir/cleanup.last")
    [ "$marker" -ge $((now - 5)) ]
    [ "$marker" -le "$now" ]
}

@test "time: _manifest_time_maybe_cleanup_cache keeps cache files younger than the period" {
    local cache_dir
    cache_dir=$(_manifest_time_cache_dir)
    mkdir -p "$cache_dir"
    echo "fresh" > "$cache_dir/timestamp.cache"
    _manifest_time_maybe_cleanup_cache
    [ -f "$cache_dir/timestamp.cache" ]
    [ "$(cat "$cache_dir/timestamp.cache")" = "fresh" ]
    [ -f "$cache_dir/cleanup.last" ]
}

@test "time: _manifest_time_maybe_cleanup_cache short-circuits when the marker is recent" {
    local cache_dir stamped
    cache_dir=$(_manifest_time_cache_dir)
    mkdir -p "$cache_dir"
    echo "old" > "$cache_dir/timestamp.cache"
    touch -m -t 202001010000 "$cache_dir/timestamp.cache"
    stamped=$(($(date -u +%s) - 10))
    printf '%s\n' "$stamped" > "$cache_dir/cleanup.last"
    _manifest_time_maybe_cleanup_cache
    # Recent marker (< period) means no sweep: the stale file survives and the
    # marker is left untouched.
    [ -f "$cache_dir/timestamp.cache" ]
    [ "$(tr -d '[:space:]' < "$cache_dir/cleanup.last")" = "$stamped" ]
}

@test "time: display_time_info renders timestamp details from the cache" {
    unset MANIFEST_CLI_TIMEZONE
    _manifest_time_write_cache_data "1700000000" "+0.500000" "0.250000" "https://ex/t" "9.9.9.9"
    run display_time_info
    [ "$status" -eq 0 ]
    [[ "$output" == *"🕐 Manifest Timestamp Service"* ]]
    [[ "$output" == *"📊 Timestamp Details:"* ]]
    [[ "$output" == *"🕐 Time: "*" UTC"* ]]
    [[ "$output" == *"📊 Offset: +0.500000 seconds"* ]]
    [[ "$output" == *"🎯 Uncertainty: ±0.250000 seconds"* ]]
    [[ "$output" == *"🌐 Source: https://ex/t (9.9.9.9)"* ]]
    [[ "$output" == *"🔧 Method: cache"* ]]
    [[ "$output" == *"💡 This timestamp is ready for manifest operations"* ]]
}

@test "time: display_time_config renders defaults with labeled servers" {
    run display_time_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"⚙️  Manifest Timestamp Configuration"* ]]
    [[ "$output" == *"🖥️  OS: $MANIFEST_CLI_OS_OS"* ]]
    [[ "$output" == *"⏱️  Timeout: ${MANIFEST_CLI_TIME_TIMEOUT}s"* ]]
    [[ "$output" == *"🔄 Retries: ${MANIFEST_CLI_TIME_RETRIES}"* ]]
    [[ "$output" == *"• https://www.cloudflare.com/cdn-cgi/trace (Cloudflare)"* ]]
    [[ "$output" == *"• https://www.google.com/generate_204 (Google)"* ]]
    [[ "$output" == *"• https://www.apple.com (Apple)"* ]]
    [[ "$output" == *"💡 Customize with environment variables:"* ]]
}

@test "time: display_time_config lists overridden servers without a vendor label" {
    export MANIFEST_CLI_TIME_SERVER1="https://time.example/x"
    run display_time_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"• https://time.example/x"* ]]
    # Defaults are fully replaced: no Cloudflare/Google/Apple bullets.
    ! echo "$output" | grep -q "• https://www.cloudflare.com"
}
