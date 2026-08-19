# Releasing a shard

This repo is a monorepo on purpose: `tryst`, `tryst-vector`, `tryst-sdl`,
and every `tryst-*` widget shard develop together, with `path:`
dependencies between them (see each `shard.yml`) so a change touching
two shards at once is one commit, no publish step needed in between.

But `path:` dependencies only resolve on THIS filesystem, relative to
wherever each `shard.yml` happens to sit - they mean nothing to someone
outside this repo. `shards` (Crystal's package manager) has no concept
of "depend on this subdirectory of that git repo" either: a `github:`/
`git:` dependency clones a whole repository and expects `shard.yml` at
its ROOT. So a shard that wants to be `shards install`-able on its own
needs to actually exist as a separate git repo with its own root - not
because monorepos are wrong, but because that's the only shape `shards`
itself understands.

The reconciliation: keep developing in this one repo, and mirror each
publishable shard's own history out to its own repo via
`git subtree split` whenever it's released. `scripts/release-shard.sh`
does the split-and-push; this file is the rest of the process around
it.

## One-time setup, per shard, before its first release

1. Create an empty destination repo - `gh repo create <owner>/<shard-name> --public`,
   or the GitHub UI. Don't let it auto-init a README/license/.gitignore;
   the first push needs to be a fast-forward onto nothing.

2. In every OTHER shard that depends on it, change the dependency from
   `path:` to the real source, and add a `shard.override.yml` that
   points it right back at `path:` for local development in this repo.
   Concretely, once `tryst-vector` has been published to
   `github.com/jamescook/tryst-vector`, every shard depending on it
   (`tryst-value-slider/shard.yml`, say) changes:

   ```yaml
   # tryst-value-slider/shard.yml (committed - what an external
   # consumer's `shards install` actually reads)
   dependencies:
     tryst-vector:
       github: jamescook/tryst-vector
       version: "~> 0.1"
   ```

   ```yaml
   # tryst-value-slider/shard.override.yml (also committed - shards
   # prefers this over shard.yml's own dependencies whenever it's
   # present, which is always true inside a checkout of THIS repo)
   dependencies:
     tryst-vector:
       path: ../tryst-vector
   ```

   Both files are committed here - every contributor to this monorepo
   gets `path:` behavior for free via the override, and nothing has to
   remember to add it locally. `.gitignore` does NOT exclude
   `shard.override.yml` for this reason; that's the opposite of most
   projects' advice for this file, and deliberately so.

   A shard not yet published (no repo exists for it yet) keeps a plain
   `path:` dependency in its real `shard.yml` - there is nothing to
   override yet, and pointing `github:` at a repo that doesn't exist
   breaks `shards install` for everyone, override or not.

## Cutting a release

```
scripts/release-shard.sh <shard-dir> <remote-url> [<version-tag>]

# e.g.
scripts/release-shard.sh tryst-vector git@github.com:jamescook/tryst-vector.git v0.2.0
scripts/release-shard.sh tryst-value-slider git@github.com:jamescook/tryst-value-slider.git
```

`<shard-dir>` is relative to the repo root (`.` for the root `tryst`
shard itself - it has no subdirectory to split, so this pushes HEAD
directly instead of running `git subtree split`). `<version-tag>` is
optional; give it a `vX.Y.Z` matching whatever `shard.yml`s that depend
on this shard should pin against, or omit it to push a between-releases
sync with no tag.

Requires a clean working tree (git subtree split works off committed
history only - anything uncommitted would silently be left out) and
`git subtree` itself, which ships with git but isn't always on `PATH`
directly; `git subtree ...` (not `git-subtree ...`) finds it via git's
own exec-path regardless. `--dry-run` runs the split and prints the
resulting commit without pushing anything, to sanity-check before a
real push.

After a release, bump the `version:` constraint in whichever
`shard.yml`s depend on it, if the new release needs one.

## What's published today

Nothing yet - every shard here is still `path:`-only, monorepo-internal.
This file and the script exist so that changes prompted by
`shards install` reliability, and any future decision to make a
specific shard externally installable, doesn't reinvent the mechanism.
