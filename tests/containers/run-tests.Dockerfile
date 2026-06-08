FROM alpine:3.20

RUN apk add --no-cache bash git bats parallel yq coreutils jq \
    && git config --system --add safe.directory "*"

WORKDIR /work
