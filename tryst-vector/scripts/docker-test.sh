#!/bin/sh
# Builds the tryst-vector Docker test image and runs its spec suite (see
# ../Dockerfile), then cleans up the dangling images repeated builds
# leave behind - re-tagging the same name orphans the previous image
# (<none>:<none>) every time, and they pile up fast. Labeled so cleanup
# only ever touches this image, never dangling images belonging to the
# parent project or anything else on the machine.
#
# The build context is the REPO ROOT, not this shard's directory:
# tryst-vector depends on tryst via `path: ../`, so the parent's src/ and
# shard.yml have to be reachable from the context. Run it from anywhere.
#
# Any arguments are passed straight through to `crystal spec` inside the
# container, so a focused run works here as well as on the host:
#
#   tryst-vector/scripts/docker-test.sh                             # everything
#   tryst-vector/scripts/docker-test.sh spec/tryst/vector_spec.cr    # one file
set -eu

IMAGE=tryst-vector-test
LABEL=project=tryst-vector

# This script lives in <repo>/tryst-vector/scripts, so the root is two up.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

docker build --label "$LABEL" -t "$IMAGE" -f "$ROOT/tryst-vector/Dockerfile" "$ROOT"

status=0
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
