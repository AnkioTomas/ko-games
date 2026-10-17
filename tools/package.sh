#!/bin/bash
# 打包 games.koplugin：tools/package.sh [版本] [输出 zip]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="${2:-dist/games.koplugin-$VERSION.zip}"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
zip -rq "$OUT" games.koplugin -x '*.DS_Store'
echo "$OUT"
