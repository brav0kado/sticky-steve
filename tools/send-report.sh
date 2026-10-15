#!/usr/bin/env bash
# Send the newest in-game bug report (F12) to julia, where Claude reads it.
#   tools/send-report.sh            newest report
#   tools/send-report.sh --all      every report not yet sent
#   tools/send-report.sh --list     just show where reports are
# Env overrides: REPORTS=<dir with report folders>, JULIA=user@host, DEST=<dir on julia>
set -euo pipefail

JULIA="${JULIA:-bravokado@192.168.1.98}"
DEST="${DEST:-agent/outputs/coding/sticky-steve/reports}"

find_reports() {
	if [[ -n "${REPORTS:-}" ]]; then echo "$REPORTS"; return; fi
	local d
	# Godot names the folder after config/name (sanitised: ":" -> "-"). Rename the project = update this.
	for d in "${XDG_DATA_HOME:-$HOME/.local/share}"/godot/app_userdata/Sticky\ Steve/reports \
	         "$HOME"/.var/app/org.godotengine.Godot/data/godot/app_userdata/Sticky\ Steve/reports; do
		[[ -d "$d" ]] && { echo "$d"; return; }
	done
	return 1
}

reports="$(find_reports)" || { echo "No reports yet: press F12 in the game first (or set REPORTS=...)." >&2; exit 1; }
[[ "${1:-}" == "--list" ]] && { echo "$reports"; ls -1 "$reports"; exit 0; }

mapfile -t all < <(ls -1 "$reports" | sort)
(( ${#all[@]} )) || { echo "No reports in $reports" >&2; exit 1; }
if [[ "${1:-}" == "--all" ]]; then
	todo=()
	for r in "${all[@]}"; do [[ -e "$reports/$r/.sent" ]] || todo+=("$r"); done
else
	todo=("${all[-1]}")
fi
(( ${#todo[@]} )) || { echo "Nothing new to send."; exit 0; }

for r in "${todo[@]}"; do
	scp -q -r "$reports/$r" "$JULIA:$DEST/"
	touch "$reports/$r/.sent"
	echo "sent $r -> $JULIA:$DEST/$r"
done
echo "Tell Claude: \"check report ${todo[-1]}\""
