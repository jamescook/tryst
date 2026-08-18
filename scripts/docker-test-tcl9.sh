#!/bin/sh
# Same as docker-test.sh, but builds Dockerfile.tcl9 (Debian trixie,
# real tcl9.0/tk9.0) instead of the root Dockerfile (Ubuntu Noble,
# 8.6) - the TCL_VERSION=9 CI lane. Must be run with `-f Dockerfile.tcl9`
# since this project has two Dockerfiles at the repo root; a bare
# `docker build .` would pick up the 8.6 one instead.
#
# Any arguments are passed straight through to `crystal spec` inside the
# container, exactly like docker-test.sh:
#
#   ./scripts/docker-test-tcl9.sh                                  # everything
#   ./scripts/docker-test-tcl9.sh spec/tryst/ui/split_spec.cr       # one file
#   ./scripts/docker-test-tcl9.sh -e "weight:"                     # by name
set -eu

IMAGE=crystal-tryst-tcl9-test
LABEL=project=crystal-tryst-tcl9

docker build --label "$LABEL" -f Dockerfile.tcl9 -t "$IMAGE" .

status=0
if [ "$#" -eq 0 ]; then
  docker run --rm --init "$IMAGE" || status=$?
else
  docker run --rm --init "$IMAGE" xvfb-run -a crystal spec "$@" || status=$?
fi

docker image prune -f --filter "label=$LABEL" >/dev/null

exit "$status"
