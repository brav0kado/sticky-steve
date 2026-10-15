#!/usr/bin/env bash
# Launch the game with an up-to-date import cache. Running `godot` in the project folder starts
# the game but never imports, so freshly pulled art fails to load ("Unable to open file:
# res://.godot/imported/..."). The import pass only does work for new/changed files.
#   ./play.sh [godot args]   import, then play      ./play.sh --editor   import, then open the editor
# Env: GODOT=/path/to/godot if it's not on PATH.
set -euo pipefail
cd "$(dirname "$0")"
godot_bin="${GODOT:-$(command -v godot || command -v godot4 || true)}"
[[ -n "$godot_bin" ]] || { echo "godot not found: set GODOT=/path/to/godot" >&2; exit 1; }
log="${TMPDIR:-/tmp}/sticky-steve-import.log"
echo "importing assets..."
# Some Godot builds crash while shutting down AFTER a finished import ("corrupted size vs.
# prev_size", seen on Martin's laptop 2026-10-15). That import is fine: only stop when the import
# itself didn't finish or logged an error.
if ! "$godot_bin" --headless --path . --import >"$log" 2>&1; then
	if grep -q 'DONE.*loading_editor_layout' "$log" && ! grep -qE '^(ERROR|SCRIPT ERROR)' "$log"; then
		echo "warning: Godot crashed on exit after a finished import ($("$godot_bin" --version)); playing anyway" >&2
	else
		echo "import failed, see $log" >&2
		tail -20 "$log" >&2
		exit 1
	fi
fi
if [[ "${1:-}" == "--editor" ]]; then
	exec "$godot_bin" --path . --editor
fi
exec "$godot_bin" --path . "$@"  # extra args go to Godot
