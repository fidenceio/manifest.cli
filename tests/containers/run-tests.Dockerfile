FROM alpine:3.24

# tzdata is required for IANA zone resolution (e.g. America/New_York → EST).
# Without it, GNU date still exits 0 and prints a misleading abbreviation.
RUN apk add --no-cache bash git bats parallel yq coreutils jq tzdata \
    && git config --system --add safe.directory "*"

WORKDIR /work
