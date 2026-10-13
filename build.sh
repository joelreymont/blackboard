#!/bin/sh
set -eu
project=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
habu_root=${HABU_ROOT:-"$HOME/.local/lib/habu/c53b4d2c"}
actual_hash=$(shasum -a 256 "$habu_root/bin/hb" | cut -d ' ' -f 1)
expected_hash=ccf0798dd4e11a3ea4308386704bd09a5f183750d18b802b9b2d9c28d6af2b96
if [ "$actual_hash" != "$expected_hash" ]; then
  echo "expected pinned Habu compiler $expected_hash, got $actual_hash" >&2
  exit 1
fi
mkdir -p "$project/bin" "$project/.build/cache" "$project/.build/tmp"
cd "$habu_root"
HABU_BUILD_CACHE="$project/.build/cache" HB_TMP="$project/.build/tmp" \
  bin/hb --load tools/hb-build.f -- --size-report "$project/main.f" -o "$project/bin/bb"
