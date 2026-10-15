#!/usr/bin/env bats
# Explicit transport probe, excluded from the ordinary top-level suite.
# Enough valid TAP diagnostics to exceed Linux's pipe buffer many times over.
@test "coverage stdout transport handles a large TAP stream" {
    local i
    for ((i=0; i<4096; i++)); do
        printf '# coverage output transport probe: %080d\n' "$i" >&3
    done
}
