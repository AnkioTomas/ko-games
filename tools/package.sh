#!/bin/bash
# 打包 games.koplugin：tools/package.sh [版本] [输出 zip]
set -e
cd "$(dirname "$0")/.."
VERSION="${1:-dev}"
OUT="${2:-dist/games.koplugin-$VERSION.zip}"
mkdir -p "$(dirname "$OUT")"
OUT="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
rm -f "$OUT"
# 在临时副本里把版本号写进 kogames/version.lua，源码保持占位符
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R games.koplugin "$STAGE/games.koplugin"
sed -i.bak "s/@VERSION@/${VERSION}/g" "$STAGE/games.koplugin/kogames/version.lua"
rm -f "$STAGE/games.koplugin/kogames/version.lua.bak"
(cd "$STAGE" && zip -rq "$OUT" games.koplugin -x '*.DS_Store')
echo "$OUT"
