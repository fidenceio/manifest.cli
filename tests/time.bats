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
