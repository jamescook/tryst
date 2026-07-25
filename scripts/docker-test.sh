#!/bin/sh
# Builds the Docker test image, runs the spec suite under Xvfb (see
# Dockerfile), and always cleans up dangling images left behind by
# previous builds - `docker build -t crystal-teek-test .` re-tagging the
# same name leaves the previous image dangling (<none>:<none>) every
# time, and these pile up fast across repeated runs. Labeled so cleanup
# only ever touches this project's own images, never unrelated dangling
# images from other projects on the same machine. Mirrors ruby-teek's
# `rake docker:test` / `docker:prune` (lib/tasks/docker.rake).
set -eu

IMAGE=crystal-teek-test
LABEL=project=crystal-teek

docker build --label "$LABEL" -t "$IMAGE" .

status=0
docker run --rm --init "$IMAGE" || status=$?

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
