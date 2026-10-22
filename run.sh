#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
if command -v godot4 >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot4)"
elif command -v godot >/dev/null 2>&1; then
  GODOT_BIN="$(command -v godot)"
elif [[ -x "$HOME/.local/bin/godot4" ]]; then
  GODOT_BIN="$HOME/.local/bin/godot4"
else
  echo "Godot 4 is required. Install it from https://godotengine.org/download/linux/" >&2
  exit 1
fi
exec "$GODOT_BIN" --path . "$@"
