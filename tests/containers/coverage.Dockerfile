# Coverage image: same toolchain contract as run-tests.Dockerfile plus kcov.
# Debian, not Alpine, because kcov is not packaged in Alpine for aarch64;
# Debian ships kcov for both amd64 and arm64. yq must stay the mikefarah
# dialect the modules use (Debian's python yq is CLI-incompatible), so it is
# copied from the official multi-arch image rather than apt.
FROM mikefarah/yq:4 AS yq

FROM debian:trixie-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        kcov bats git jq parallel coreutils ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && git config --system --add safe.directory "*"
COPY --from=yq /usr/bin/yq /usr/local/bin/yq

WORKDIR /work
