#!/usr/bin/env bash
# Package tmmaps plugin and install to OpenPlanet Plugins folder.
# Run from repo root: ./package-and-install.sh
# WSL: Windows path is /mnt/c/Users/fanto/OpenplanetNext/Plugins

set -e
REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
OUTPUT_NAME="tmmaps.op"
# WSL path to Windows OpenPlanet Plugins
PLUGINS_DIR="/mnt/c/Users/fanto/OpenplanetNext/Plugins"

cd "$REPO_ROOT"
rm -f "$OUTPUT_NAME"

# Build zip with flat structure (info.toml + all .as, including v3/ and v4/)
FILES="info.toml ./*.as"
[ -d v3 ] && FILES="$FILES v3/*.as"
[ -d v4 ] && FILES="$FILES v4/*.as"
zip -j "$OUTPUT_NAME" $FILES

# Copy to Plugins, overwriting
if [[ ! -d "$PLUGINS_DIR" ]]; then
  echo "Plugins folder not found: $PLUGINS_DIR" >&2
  exit 1
fi
cp -f "$OUTPUT_NAME" "$PLUGINS_DIR/"

echo "Done: $OUTPUT_NAME -> $PLUGINS_DIR/$OUTPUT_NAME"
