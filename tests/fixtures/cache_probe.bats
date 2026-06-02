#!/usr/bin/env bats

# A trivial, instant test used only as an explicit target by run_tests_cache.bats.
# It lives under tests/fixtures/ so the top-level `bats tests/` suite run (which is
# non-recursive) never picks it up — it exists purely to make a cache MISS cheap to
# observe (one passing test) instead of re-running a real suite.

@test "cache probe: trivially passes" {
    true
}
