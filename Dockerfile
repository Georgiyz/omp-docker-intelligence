# syntax=docker/dockerfile:1
ARG update-token
FROM golang:1.27.3 AS go-toolchain

ARG update-token
RUN go install golang.org/x/tools/gopls@latest

FROM oven/bun:latest

LABEL maintainer="Oh My Pi" \
      description="Docker harness for Oh My Pi coding agent" \
      version="0.1"

RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl git iptables openssh-client \
      python3 python3-pip python3-venv ripgrep fd-find \
 && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
 && rm -rf /var/lib/apt/lists/*

# Keep Go available for gopls to analyze and build Go projects. Build gopls in
# the official Go stage so the final image does not need a second compiler setup.
COPY --from=go-toolchain /usr/local/go /usr/local/go
COPY --from=go-toolchain /go/bin/gopls /usr/local/bin/gopls
ENV GOROOT="/usr/local/go"
ENV PATH="/usr/local/go/bin:/usr/local/bin:$PATH"

RUN python3 -m venv /opt/omp-venv \
 && /opt/omp-venv/bin/pip install --no-cache-dir ipykernel
ENV PATH="/opt/omp-venv/bin:$PATH"

RUN bun install -g @oh-my-pi/pi-coding-agent @oh-my-pi/pi-natives

COPY --chmod=0755 entrypoint.sh /usr/local/bin/entrypoint

ARG update-token
RUN bun update -g @oh-my-pi/pi-coding-agent @oh-my-pi/pi-natives

WORKDIR /work

HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD ["omp", "--version"]

ENTRYPOINT ["/usr/local/bin/entrypoint"]

CMD ["omp"]
