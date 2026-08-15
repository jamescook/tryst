# Dev/test image for teek-sdl. Built from the REPO ROOT as context, not
# from this directory - teek-sdl depends on teek through a `path: ../`
# shard dependency, so the parent's src/ and shard.yml have to be inside
# the build context. scripts/docker-test.sh does that for you.
#
# Debian forky rather than the crystallang/crystal image the parent
# project uses, purely for SDL3 packaging: that image is Ubuntu 24.04 and
# has no sdl3 packages at all. Ubuntu 26.04 and Debian trixie carry core,
# image and ttf but not mixer; Alpine edge lacks image and mixer. Debian
# forky (testing) and sid are the only bases with all four, and forky is
# the more stable of the two. Forky still defaults tcl-dev/tk-dev to
# 8.6.18 with no Tcl 9 anywhere in the image, so the project's 8.6-only
# scoping survives the newer base.
#
# Crystal is not in Debian apt, hence the official release tarball below.
#
# Must be run as `docker run --rm --init <image>` - same requirement as
# the parent project's image. Without --init, xvfb-run hangs forever: it
# runs as the container's PID 1, and its Xvfb-readiness handshake relies
# on a SIGUSR1 trap that doesn't fire reliably for PID 1.
FROM debian:forky

# Kept in step with the `crystal:` constraint in both shard.yml files.
ARG CRYSTAL_VERSION=1.21.0
ARG CRYSTAL_RELEASE=1

# The libsdl3-*-dev four are what the @[Link] line in src/teek/sdl/
# lib_sdl.cr resolves through pkg-config, so pkg-config is a build
# requirement and not just a convenience. The lib*-dev tail is what the
# non-bundled Crystal tarball expects to find on the system.
RUN apt-get update && apt-get install -y --no-install-recommends \
    tcl-dev tk-dev \
    libsdl3-dev libsdl3-mixer-dev libsdl3-image-dev libsdl3-ttf-dev \
    xvfb xauth \
    ca-certificates curl gcc pkg-config \
    libpcre2-dev libgc-dev libevent-dev libssl-dev zlib1g-dev libyaml-dev libxml2-dev \
    && rm -rf /var/lib/apt/lists/*

# uname -m already spells the architectures the way the release assets do
# (aarch64 / x86_64), so no translation table is needed.
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

# The parent shard, laid out exactly as it is in the repo so that
# `path: ../` resolves the same way it does on a developer's machine.
# Copied file by file rather than as a whole directory: a local checkout
# has lib/ symlinks and build artifacts in both trees that must not come
# along, and being explicit here beats maintaining a .dockerignore at the
# repo root that the parent project's own image would also inherit.
WORKDIR /app
COPY shard.yml ./
COPY src/ src/

# SDL's audio backends probe XDG_RUNTIME_DIR on the way to finding a
# driver, and the PulseAudio client prints `error: XDG_RUNTIME_DIR is
# invalid or not set in the environment.` to stderr when it is unset -
# which it is in a container. Audio init succeeds regardless, SDL simply
# moves on to another driver, but the word "error" landing in the middle
# of the spec output reads exactly like a failing test. Pointing it at a
# real directory keeps the run quiet without swapping in the dummy audio
# driver, which would make the mixer example prove rather less.
ENV XDG_RUNTIME_DIR=/tmp/xdg-runtime
RUN mkdir -p "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

WORKDIR /app/teek-sdl
COPY teek-sdl/shard.yml ./
COPY teek-sdl/src/ src/
COPY teek-sdl/spec/ spec/

RUN shards install

CMD ["xvfb-run", "-a", "crystal", "spec"]
