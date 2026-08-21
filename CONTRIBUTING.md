# Contributing

Tryst is pre-release and the API is still settling, so for anything
bigger than a small fix it's worth opening an issue first — the shape
of a feature may already be in flux.

## Setup

```
shards install
git config core.hooksPath .githooks   # once per clone
```

The second line activates the repo's pre-commit hook: ameba lint over
every shard, a compile check of all examples, and a guard against
accidentally committing built binaries. The hook expects `crystal` on
your PATH.

The hook also has an optional, opt-in step that asks Claude (Haiku) to
review comment verbosity in staged files. It only runs if you create a
`.enable-claude-comment-review` sentinel file at the repo root — skip
it if you don't use Claude Code; nothing else depends on it.

## Running tests

```
crystal spec                     # host, auto-detects Tcl/Tk (prefers 9.x)
TCL_VERSION=8 crystal spec       # host, forces 8.6
TCL_VERSION=9 crystal spec       # host, forces 9.x
scripts/docker-test.sh           # Ubuntu + Xvfb, headless, Tcl/Tk 8.6
scripts/docker-test-tcl9.sh      # Debian trixie + Xvfb, headless, 9.x
```

Each `tryst-*` shard has its own specs and its own Docker script; run
them from that shard's directory.

## Repo layout

This is a monorepo: `tryst` at the root, plus `tryst-vector`,
`tryst-sdl`, and the widget shards (`tryst-switch`, `tryst-spinner`,
...) each as their own shard with `path:` dependencies between them.
How releases are cut from it — and why `shard.override.yml` files are
committed here on purpose — is covered in [RELEASING.md](RELEASING.md).

## Style

`crystal tool format` before committing; ameba enforces the rest via
the pre-commit hook. Match the surrounding code and comment style —
comments here explain *why*, not *what*.
