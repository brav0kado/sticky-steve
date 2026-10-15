class_name Nyx8
## The game's only palette (Aseprite's NYX8). Anything drawn in code (dust, flashes, UI, debug
## lines) takes its colour from here so it matches Martin's art. tests/palette_checks.gd fails on
## any PNG pixel or .tscn/.tres Color outside it. Source of truth: art/palette/nyx8.hex.
##
## Backgrounds never use Steve's colours (Martin, 2026-10-15), so he can never blend into the
## world. That leaves BACKGROUND. Behind Steve use DUSK/MAUVE; NAVY/SLATE are close to his INK
## body, so keep them for distant layers. tests/palette_checks.gd derives Steve's colours from his
## sheet and fails if STEVE drifts from it or a background uses one.

const INK := Color("08141e")
const NAVY := Color("0f2a3f")
const SLATE := Color("20394f")
const CREAM := Color("f6d6bd")
const SAND := Color("c3a38a")
const DUSK := Color("997577")
const MAUVE := Color("816271")
const SHADOW := Color("4e495f")

const ALL: Array[Color] = [INK, NAVY, SLATE, CREAM, SAND, DUSK, MAUVE, SHADOW]
const STEVE: Array[Color] = [INK, SHADOW, SAND, CREAM]  ## what art/steve/steve.png is drawn in
const BACKGROUND: Array[Color] = [NAVY, SLATE, DUSK, MAUVE]  ## everything else


## True if c is a palette colour (alpha ignored, 1/255 tolerance for float round-trips).
static func has(c: Color) -> bool:
	for p in ALL:
		if absf(p.r - c.r) < 0.005 and absf(p.g - c.g) < 0.005 and absf(p.b - c.b) < 0.005:
			return true
	return false
