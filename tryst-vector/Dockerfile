# Dev/test image for tryst-vector. Built from the REPO ROOT as context,
# not from this directory - tryst-vector depends on tryst through a
# `path: ../` shard dependency, so the parent's src/ and shard.yml have
# to be inside the build context, same as tryst-sdl/Dockerfile.
#
# Debian forky rather than the crystallang/crystal image the parent
# project uses (Ubuntu 24.04, no ThorVG package at all), and rather than
# trixie (Debian's current stable, which also has none yet) - forky is
# the first Debian release to carry libthorvg-dev (1.0.6, satisfying this
# shard's >= 1.0 pin - ThorVG had intentional API/ABI breaks at the 1.0
# transition, so anything older isn't safe to link against).
# Already this repo's own precedent: tryst-sdl/Dockerfile uses the same
# base for the same "not in Ubuntu/trixie yet" reason.
#
# tcl-dev/tk-dev are here for the SAME reason tryst-sdl/Dockerfile
# installs them - not because this shard touches Tk yet, but because its
# `path: ../` dependency on tryst pulls in interp.cr, which links Tcl/Tk
# to compile at all, whether or not this shard's own specs exercise it.
#
# Crystal is not in Debian apt, hence the official release tarball below
# - same approach tryst-sdl/Dockerfile already uses for the same reason.
#
# Must be run as `docker run --rm --init <image>` - same requirement as
# the root Dockerfile and tryst-sdl's. Without --init, xvfb-run hangs
# forever as PID 1 (its Xvfb-readiness SIGUSR1 trap doesn't fire there).
FROM debian:forky

ARG CRYSTAL_VERSION=1.21.0
ARG CRYSTAL_RELEASE=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    tcl-dev tk-dev \
    libthorvg-dev \
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
# Copied file by file rather than as a whole directory - same reasoning
# as tryst-sdl/Dockerfile's own copy of the parent shard.
WORKDIR /app
COPY shard.yml ./
COPY src/ src/

WORKDIR /app/tryst-vector
COPY tryst-vector/shard.yml ./
COPY tryst-vector/src/ src/
COPY tryst-vector/spec/ spec/

RUN shards install

CMD ["xvfb-run", "-a", "crystal", "spec"]
