#!/bin/sh
# Publishes one shard's own history to its mirror repo, via
# `git subtree split` - the mechanism that lets this stay ONE monorepo
# for local development (path: dependencies, no publish step needed to
# keep working on two shards together) while each shard is still a
# real, independently `shards install`-able git repo for anyone who
# doesn't want the whole monorepo. See RELEASING.md at the repo root
# for the full story and the one-time shard.yml/shard.override.yml
# setup this assumes is already in place.
#
# What this does NOT do: create the destination repo (has to exist and
# be empty, or already be a prior release of this same shard, before
# the first run - `gh repo create <owner>/<name> --public` or the
# GitHub UI, once per shard, never repeated), or touch any shard.yml.
# Pure git history extraction and a push, nothing Crystal-specific.
#
# Usage:
#   scripts/release-shard.sh <shard-dir> <remote-url> [<version-tag>]
#   scripts/release-shard.sh tryst-vector git@github.com:jamescook/tryst-vector.git v0.1.0
#
#   --dry-run   split locally, print the resulting commit, push nothing.
#
# <shard-dir> is relative to the repo root (e.g. "tryst-vector", or
# "." for the root tryst shard itself). <version-tag> is optional - if
# given, the pushed commit is also tagged with it and the tag is pushed
# too; omit it to push main/master only (e.g. for a between-releases
# sync).
set -eu

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=1
  shift
fi

SHARD_DIR="${1:?usage: $0 [--dry-run] <shard-dir> <remote-url> [<version-tag>]}"
REMOTE_URL="${2:?usage: $0 [--dry-run] <shard-dir> <remote-url> [<version-tag>]}"
VERSION_TAG="${3:-}"

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

if [ "$SHARD_DIR" != "." ] && [ ! -f "$SHARD_DIR/shard.yml" ]; then
  echo "error: $SHARD_DIR/shard.yml not found - is <shard-dir> right, and relative to the repo root?" >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "error: working tree has uncommitted changes - commit or stash first." >&2
  echo "       git subtree split works off committed history only; uncommitted" >&2
  echo "       changes here would silently be left out of the release." >&2
  exit 1
fi

if [ "$SHARD_DIR" = "." ]; then
  # The root shard (tryst itself) has no --prefix to split on - its own
  # history at HEAD (minus every OTHER shard's subdirectory, which a
  # consumer's `shards install` never looks at anyway since it only
  # ever reads shard.yml + src/) is already what a consumer needs.
  # subtree split doesn't apply; publish HEAD directly.
  SPLIT_REF=$(git rev-parse HEAD)
  echo "Root shard - publishing HEAD ($SPLIT_REF) directly, no subtree split needed."
else
  echo "Splitting $SHARD_DIR out of this repo's history..."
  SPLIT_REF=$(git subtree split --prefix="$SHARD_DIR")
  echo "Split complete: $SPLIT_REF"
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "--dry-run: stopping here. Would push $SPLIT_REF to $REMOTE_URL (branch main)${VERSION_TAG:+, tag $VERSION_TAG}."
  exit 0
fi

echo "Pushing to $REMOTE_URL..."
git push "$REMOTE_URL" "$SPLIT_REF:refs/heads/main"

if [ -n "$VERSION_TAG" ]; then
  echo "Tagging $VERSION_TAG..."
  git push "$REMOTE_URL" "$SPLIT_REF:refs/tags/$VERSION_TAG"
fi

echo "Done: $SHARD_DIR published to $REMOTE_URL${VERSION_TAG:+ as $VERSION_TAG}."
