#!/bin/sh
# Builds the tryst-sdl Docker test image and runs its spec suite under
# Xvfb (see ../Dockerfile), then cleans up the dangling images repeated
# builds leave behind - re-tagging the same name orphans the previous
# image (<none>:<none>) every time, and they pile up fast. Labeled so
# cleanup only ever touches this image, never dangling images belonging
# to the parent project or anything else on the machine.
#
# The build context is the REPO ROOT, not this shard's directory:
# tryst-sdl depends on tryst via `path: ../`, so the parent's src/ and
# shard.yml have to be reachable from the context. Run it from anywhere.
#
# Any arguments are passed straight through to `crystal spec` inside the
# container, so a focused run works here as well as on the host:
#
#   tryst-sdl/scripts/docker-test.sh                                # everything
#   tryst-sdl/scripts/docker-test.sh spec/tryst/sdl/linking_spec.cr  # one file
#   tryst-sdl/scripts/docker-test.sh -e "links SDL3_mixer"          # by name
#
# Paths are relative to /app/tryst-sdl in the container, which is the same
# as being relative to this shard's directory in the repo.
set -eu

IMAGE=tryst-sdl-test
LABEL=project=tryst-sdl

# This script lives in <repo>/tryst-sdl/scripts, so the root is two up.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

docker build --label "$LABEL" -t "$IMAGE" -f "$ROOT/tryst-sdl/Dockerfile" "$ROOT"

status=0
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
