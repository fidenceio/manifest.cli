#!/usr/bin/env bash

# Unit-test transport for the generated gate. Native macOS CI has no Docker;
# execute the generated inner payload with the fixture's existing tools. This
# never provisions packages and is not a claim of native container integration.
scaffold_gate_docker_stub_install() {
    local bin_dir="$1"
    mkdir -p "$bin_dir"
    SCAFFOLD_GATE_DOCKER_LOG="$bin_dir/docker.log"
    cat > "$bin_dir/docker" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
# Ship deliberately scrubs environment variables at the release boundary.
# Derive this fixture-owned path instead of relying on an inherited variable.
log_file="$(dirname "$0")/docker.log"
printf '%s\t' "$@" >> "$log_file"
printf '\n' >> "$log_file"
if [[ "${1:-}" == image && "${2:-}" == inspect && "${3:-}" == manifest-project-checks:* ]]; then
    exit 0
fi
[[ "${1:-}" == run && "${2:-}" == --rm ]] || exit 96
while [[ $# -gt 0 && "$1" != bash ]]; do shift; done
[[ "${1:-}" == bash && "${2:-}" == scripts/run-tests.sh ]] || exit 97
shift
gate="$1"; shift
# The generated wrapper and inner payload each have a Bash shebang. Preserve
# the real script as $0 so its project-root calculation and inventory still run.
payload="$(awk '/^#!\/usr\/bin\/env bash$/ {headers++} headers >= 2' "$gate")"
[[ "$payload" == '#!/usr/bin/env bash'* ]] || exit 98
exec bash -c "$payload" "$gate" "$@"
STUB
    chmod +x "$bin_dir/docker"
    export PATH="$bin_dir:$PATH"
}

# Exercise the host wrapper even when this test itself runs in Linux Docker.
# Only the disposable in-memory test copy changes; the generated file is intact.
scaffold_gate_run_as_host() {
    local gate="$1" body
    shift
    body="$(sed 's/^if \[\[ ! -f \/.dockerenv && ! -f \/run\/.containerenv \]\]; then$/if true; then/' "$gate")"
    [[ "$body" == *'if true; then'* ]] || return 99
    bash -c "$body" "$gate" "$@"
}
