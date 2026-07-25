# Dev/test image for crystal-teek. Mirrors the Tcl/Tk 8.6 apt packages
# ruby-teek already validated in its own Dockerfile.ci-test (tcl-dev/tk-dev
# -> /usr/include/tcl8.6, default multiarch lib dir). Runs under Xvfb so Tk
# init (which opens a main window) never pops a real window on the host -
# same concern noted in ruby-teek about local test runs.
#
# Uses the official Crystal image as a base rather than installing Crystal
# via apt on plain ubuntu:25.04 - the third-party OBS apt repo for Crystal
# didn't have an installable arm64 package for this Ubuntu release.
#
# Must be run as `docker run --rm --init <image>` - same requirement as
# ruby-teek's docker.rake. Without --init, xvfb-run hangs forever: it runs
# as the container's PID 1, and its Xvfb-readiness handshake relies on a
# SIGUSR1 trap that doesn't fire reliably for PID 1. --init gives the
# container a real init process (tini) so xvfb-run runs as a normal child.
FROM crystallang/crystal:1.21.0

RUN apt-get update && apt-get install -y --no-install-recommends \
    tcl-dev tk-dev \
    xvfb xauth \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY shard.yml ./
COPY src/ src/
COPY spec/ spec/

# The worker (spec/support/tk_worker.cr) is spawned via a path relative
# to the CWD `crystal spec` itself runs from - this WORKDIR is that CWD.
CMD ["xvfb-run", "-a", "crystal", "spec"]
