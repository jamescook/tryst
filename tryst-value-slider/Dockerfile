# Dev/test image for tryst-value-slider - filled in from
# /Dockerfile.widget-template (see that file before copying this
# pattern to another widget shard rather than copying this file
# directly). Built from the REPO ROOT as context, not from this
# directory - this shard depends on both tryst and tryst-vector through
# `path:` dependencies (see shard.yml, and its own comment on why this
# shard lives at the repo root rather than nested under a widgets/
# directory - a real `shards install` limitation, confirmed directly,
# not a style choice), so the repo root and tryst-vector/ both have to
# be inside the build context.
#
# Debian forky for the same reason tryst-vector/Dockerfile is: it's the
# first Debian release carrying libthorvg-dev, which this shard also
# links (it renders through tryst-vector's Surface).
#
# Must be run as `docker run --rm --init <image>` - same requirement as
# every other Dockerfile in this repo. Without --init, xvfb-run hangs
# forever as PID 1.
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

# Both path-dependency shards, laid out exactly as they are in the repo
# so `path:` resolves the same way it does on a developer's machine.
# Copied file by file rather than as whole directories - same reasoning
# as tryst-vector/Dockerfile's own copy of the parent shard.
WORKDIR /app
COPY shard.yml ./
COPY src/ src/

WORKDIR /app/tryst-vector
COPY tryst-vector/shard.yml ./
COPY tryst-vector/src/ src/

WORKDIR /app/tryst-value-slider
COPY tryst-value-slider/shard.yml ./
COPY tryst-value-slider/src/ src/
COPY tryst-value-slider/spec/ spec/

RUN shards install

CMD ["xvfb-run", "-a", "crystal", "spec"]
