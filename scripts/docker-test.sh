#!/bin/sh
# Builds the Docker test image, runs the spec suite under Xvfb (see
# Dockerfile), and always cleans up dangling images left behind by
# previous builds - `docker build -t crystal-teek-test .` re-tagging the
# same name leaves the previous image dangling (<none>:<none>) every
# time, and these pile up fast across repeated runs. Labeled so cleanup
# only ever touches this project's own images, never unrelated dangling
# images from other projects on the same machine. Mirrors ruby-teek's
# `rake docker:test` / `docker:prune` (lib/tasks/docker.rake).
#
# Any arguments are passed straight through to `crystal spec` inside the
# container, so a focused run works here as well as on the host:
#
#   ./scripts/docker-test.sh                                  # everything
#   ./scripts/docker-test.sh spec/teek/ui/split_spec.cr       # one file
#   ./scripts/docker-test.sh spec/teek/ui/split_spec.cr:42    # one example
#   ./scripts/docker-test.sh -e "weight:"                     # by name
#
# The image still has to build either way, which is most of the wall time
# on a cold cache - a focused Docker run is for narrowing WHAT fails, not
# for a fast iteration loop. Iterate on the host (see .claude/CLAUDE.md);
# come here for the real-Tk tiers and the pre-commit check.
set -eu

IMAGE=crystal-teek-test
LABEL=project=crystal-teek

docker build --label "$LABEL" -t "$IMAGE" .

status=0
# Overrides the Dockerfile's own CMD when given arguments; with none, the
# whole `xvfb-run -a crystal spec` default runs unchanged.
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
