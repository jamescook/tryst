# Dev/test image for tryst-dnd - the X11/XDND path (the Linux native
# drag-and-drop implementation this shard can actually build AND test
# for real under Xvfb, unlike the macOS path which needs a real AppKit
# drag no automated harness can synthesize).
#
# Built from the REPO ROOT as context, not from this directory - this
# shard depends on tryst via `path: ../` (see shard.yml).
#
# libx11-dev is the one new native-build prerequisite this shard adds
# over every other Dockerfile in this repo: real Xlib.h/Xatom.h headers
# for compiling native/tkdrop_x11.c, which nothing else here has ever
# needed to compile against before.
#
# Must be run as `docker run --rm --init <image>` - same requirement as
# every other Dockerfile in this repo. Without --init, xvfb-run hangs
# forever as PID 1.
FROM debian:forky

ARG CRYSTAL_VERSION=1.21.0
ARG CRYSTAL_RELEASE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    tcl-dev tk-dev \
    libx11-dev \
    xvfb xauth \
    ca-certificates curl gcc make pkg-config \
    libpcre2-dev libgc-dev libevent-dev libssl-dev zlib1g-dev libyaml-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="$(uname -m)"; \
    curl -fsSL -o /tmp/crystal.tar.gz \
      "https://github.com/crystal-lang/crystal/releases/download/${CRYSTAL_VERSION}/crystal-${CRYSTAL_VERSION}-${CRYSTAL_RELEASE}-linux-${arch}.tar.gz"; \
    mkdir -p /opt/crystal; \
    tar -xzf /tmp/crystal.tar.gz -C /opt/crystal --strip-components=1; \
    rm /tmp/crystal.tar.gz; \
    ln -s /opt/crystal/bin/crystal /usr/local/bin/crystal; \
    ln -s /opt/crystal/bin/shards /usr/local/bin/shards; \
    crystal --version

WORKDIR /app
COPY shard.yml ./
COPY src/ src/

WORKDIR /app/tryst-dnd
COPY tryst-dnd/shard.yml ./
COPY tryst-dnd/Makefile ./
COPY tryst-dnd/native/ native/
COPY tryst-dnd/src/ src/
COPY tryst-dnd/spec/ spec/

# `make` has to run BEFORE `shards install`/`crystal build` - see the
# Makefile's own header comment for why (Crystal never compiles C
# itself).
RUN make
RUN shards install

CMD ["xvfb-run", "-a", "crystal", "spec"]
