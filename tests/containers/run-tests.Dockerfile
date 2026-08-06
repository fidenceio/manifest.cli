FROM alpine:3.24

# tzdata is required for IANA zone resolution (e.g. America/New_York → EST).
# Without it, GNU date still exits 0 and prints a misleading abbreviation.
# openssh-keygen supplies ssh-keygen, without which both tag SIGNING tests
# skipped — and a skip reads as a pass, so the gate was silently not covering
# signed tags at all. (util-linux is deliberately NOT installed: its script(1)
# takes a different argument form than the BSD one the pty test is written
# against, so shipping it converts a clean skip into a failure.)
RUN apk add --no-cache bash git bats parallel yq coreutils jq tzdata openssh-keygen \
    && git config --system --add safe.directory "*"

WORKDIR /work
