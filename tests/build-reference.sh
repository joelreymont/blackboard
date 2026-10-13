#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project/.build/zig-cache" "$project/.build/zig-global"
zig build-exe "$project/tests/reference/main.zig" -lc -framework CoreServices -j1 -O small -fstrip \
  --cache-dir "$project/.build/zig-cache" --global-cache-dir "$project/.build/zig-global" \
  -femit-bin="$project/.build/bb-zig-reference"
