#!/bin/sh
# Builds the teek-sdl Docker test image and runs its spec suite under
# Xvfb (see ../Dockerfile), then cleans up the dangling images repeated
# builds leave behind - re-tagging the same name orphans the previous
# image (<none>:<none>) every time, and they pile up fast. Labeled so
# cleanup only ever touches this image, never dangling images belonging
# to the parent project or anything else on the machine.
#
# The build context is the REPO ROOT, not this shard's directory:
# teek-sdl depends on teek via `path: ../`, so the parent's src/ and
# shard.yml have to be reachable from the context. Run it from anywhere.
#
# Any arguments are passed straight through to `crystal spec` inside the
# container, so a focused run works here as well as on the host:
#
#   teek-sdl/scripts/docker-test.sh                                # everything
#   teek-sdl/scripts/docker-test.sh spec/teek/sdl/linking_spec.cr  # one file
#   teek-sdl/scripts/docker-test.sh -e "links SDL3_mixer"          # by name
#
# Paths are relative to /app/teek-sdl in the container, which is the same
# as being relative to this shard's directory in the repo.
set -eu

IMAGE=teek-sdl-test
LABEL=project=teek-sdl

# This script lives in <repo>/teek-sdl/scripts, so the root is two up.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)

docker build --label "$LABEL" -t "$IMAGE" -f "$ROOT/teek-sdl/Dockerfile" "$ROOT"

status=0
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
