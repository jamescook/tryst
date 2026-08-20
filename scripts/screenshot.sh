#!/bin/sh
# Captures a live Tk window's own content - no OS chrome (title bar,
# traffic lights, drop shadow) - to a PNG. macOS only for now; nothing
# here has been verified on Linux/Windows, and screencapture is a macOS
# CLI tool with no direct equivalent on either.
#
# Content-only capture needs the window's rect in SCREEN coordinates,
# which App#screenshot_rect(window = ".") already computes for you (it's
# just winfo rootx/rooty/width/height - see its own doc comment in
# src/tryst/app.cr for why that's chrome-free by construction). Add a
# line like this to whatever you're debugging or screenshotting, run it,
# and copy the string it prints:
#
#   puts app.screenshot_rect(".")   # => "34,100,300,180"
#
# Then, while the window is still on screen:
#
#   ./scripts/screenshot.sh 34,100,300,180 output.png
#
# set -eu deliberately omitted: this is an interactive debugging tool run
# by hand, not a pre-commit/CI gate - a plain, readable error from
# screencapture itself is more useful here than a bare shell abort.

set -e

rect=$1
output=$2

if [ -z "${rect:-}" ] || [ -z "${output:-}" ]; then
  echo "usage: $0 x,y,w,h output.png" >&2
  echo "  x,y,w,h comes from App#screenshot_rect(window) in the running app - see this script's own header comment." >&2
  exit 1
fi

if ! command -v screencapture >/dev/null 2>&1; then
  echo "$0: 'screencapture' not found - this script only works on macOS." >&2
  exit 1
fi

screencapture -R"$rect" -x "$output"
echo "Saved $output"
