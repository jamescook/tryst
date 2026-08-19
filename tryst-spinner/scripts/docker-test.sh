#!/bin/sh
# Builds the tryst-spinner Docker test image and runs its spec suite
# (see ../Dockerfile), then cleans up the dangling images repeated
# builds leave behind. Labeled so cleanup only ever touches this image.
#
# The build context is the REPO ROOT, not this shard's directory: this
# shard depends on both tryst (path: ../) and tryst-vector
# (path: ../tryst-vector), so both have to be reachable from the
# context. Run it from anywhere.
#
# Any arguments are passed straight through to `crystal spec` inside the
# container, so a focused run works here as well as on the host:
#
#   tryst-spinner/scripts/docker-test.sh                          # everything
#   tryst-spinner/scripts/docker-test.sh spec/tryst/spinner_spec.cr  # one file
set -eu

IMAGE=tryst-spinner-test
LABEL=project=tryst-spinner

# This script lives in <repo>/tryst-spinner/scripts, so the root is two up.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

docker build --label "$LABEL" -t "$IMAGE" -f "$ROOT/tryst-spinner/Dockerfile" "$ROOT"

status=0
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
