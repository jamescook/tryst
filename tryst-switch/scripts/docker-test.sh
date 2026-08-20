#!/bin/sh
# Builds the tryst-switch Docker test image and runs its spec suite
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
#   tryst-switch/scripts/docker-test.sh                    # everything
#   tryst-switch/scripts/docker-test.sh spec/tryst/switch_spec.cr  # one file
set -eu

IMAGE=tryst-switch-test
LABEL=project=tryst-switch

# This script lives in <repo>/tryst-switch/scripts, so the root is two
# up.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

docker build --label "$LABEL" -t "$IMAGE" -f "$ROOT/tryst-switch/Dockerfile" "$ROOT"

status=0
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
