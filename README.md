# Sticky Steve

A 2D Jump King-style climber in Godot 4.7. Steve is a stick figure with one goal: reach the top,
in the coolest way possible. Charge the jump, commit, land it (or don't).

**Status:** revamped greybox (2026-10-16). A 2,850 px tower in three zones (32 route steps, 8
gems), forgiving movement, bounce pads and crumble ledges, streaks, saves, bests and ranks.
Greybox blocks, default font.

## Running

    ./play.sh            # imports new art, then starts the game (use this, not bare `godot`)
    ./play.sh --editor   # same, then opens the editor

## After cloning / pulling

New art only loads once Godot has imported it into `.godot/` (not in git). Run once per clone:

    git config core.hooksPath .githooks   # every pull then runs `godot --headless --import`

Without the hook: open the editor (it imports on focus) or run `godot --headless --path . --import`
before playing. Symptom if you skip it: `Unable to open file: res://.godot/imported/...ctex`.

## Controls

| Key                     | Pad          | Action                               |
|-------------------------|--------------|--------------------------------------|
| A / D, Left / Right     | D-pad, stick | move (`move_left`, `move_right`)     |
| Space                   | A            | jump: hold to charge, release to jump (`jump`) |
| F                       | Y            | plant a flag: the checkpoint (`plant_flag`) |
| R                       | Back         | back to the last flag (`respawn`)    |
| Esc                     | Start        | pause menu: resume, restart run, settings, quit to title (`pause`) |
| F11                     |              | fullscreen                           |
| F12                     |              | bug report (see below)               |

## Menus

The game boots to the **title** (`scenes/title.tscn`): Climb, Settings, Reset progress (press
twice), Quit, with your bests underneath. **Climb** asks how: **With flags** or **No flags**, with
an explainer for whichever is focused. Each mode keeps its own bests (time, height, splits);
gems, climbs and best streak are shared. In a no-flag climb F and R say "no flags this climb". **Esc / pad Start** pauses the climb (Resume, Restart
run, Settings, Quit to title). **Settings**: master, sound-effect and music volume (left/right on
a row) and fullscreen, saved in `user://settings.cfg` (`scripts/settings.gd`, autoload
`Settings`; audio buses Master/SFX/Music in `default_bus_layout.tres`). Menus are keyboard and
pad first: focus is always on a button. On the summit card: Enter climbs again, Esc goes to the
title. Pressing F when you can't plant says why ("flag in 12s", "land to plant").

## How it plays (the rules the tests hold)

**Movement**
- **Jump:** hold to charge through three stages (0.3 s each; each stage's animation loops, a meter
  over his head with stage ticks), let go to jump: up to ~129 px. At full charge he holds (hovers)
  until you let go: no auto-release. **C** (pad B) cancels. The direction held at release sets the
  launch; charging stops walking.
- **Perfect release:** the moment the charge fills, the bar flashes cream with a high tick for
  0.12 s. Let go in the flash: full jump + ~12% height, sparkle, "ting". Perfects back to back
  build a **streak** (PERFECT x2, x3, rising pitch); a full charge released late breaks it.
- **Forgiveness:** hold jump while landing and the charge starts on the landing frame; gravity
  halves at the top of the arc (a beat to steer) and is heavier on the way down; clipping a
  ceiling corner by up to 4 px slides him round it.
- **Air control:** an acceleration (nudge yes, reverse ~0.9 s).
- **Walls:** plain walls bounce him back. **Sticky** (studded) walls: hold toward one on contact
  to slap on and hang; once per airtime; charge a jump away, push away to let go, or C to cancel a
  wall charge. A slap that catches a long fall is a **SAVE!**
- **Bounce pads** (zigzag top) fling him ~200 px up and give the slap back. **Crumble** ledges
  (cracked) shake once stood on, drop after 1.2 s and regrow 3 s later.
- **Edge landings** (3 px of foot or less) slow time to 25% for half a second: "close!".

**Progress**
- **Flags:** F on solid ground plants one (pole spins in his hand); it's the checkpoint; landing
  below it sends him back; R goes back any time. Unlimited, 20 s cooldown.
- **Zones:** THE YARD, STICKY HEIGHTS, THE SPIRE. Crossing into one shows its banner and your split
  against your best split.
- **Gems:** 8 off the main route, each asking for something (a perfect jump, a bounce, a crumble
  grab, an edge landing). Found ones draw hollow on later runs.
- **Bests:** a dashed BEST line at your best height (NEW BEST HEIGHT when you pass it), best time,
  best splits, best streak, all gems ever found: saved in `user://profile.json`.
- **Summit card:** rank D to S from four checks (under par, no falls, all gems, a 3-perfect
  streak), so it always says what would rank higher.
- Falls say how far ("-34 m").

Tuning lives in the inspector: `scenes/steve.tscn` (all movement numbers), the Camera node in
`scenes/main.tscn` (zoom), each Block (bounce speed, crumble timing) and Main's `par_seconds`.
The tower is `scenes/tower.tscn`: drag Blocks, Gems and Zones in the editor. Keep `route_step`
in order: `tests/route_checks.gd` proves the climb and every gem with real jumps.

## Bug reports (playtest loop)

1. Press **F12** where it looks wrong. The game saves `screenshot.png`, `log.txt` and `info.json`
   (commit, renderer, scene, Steve's position and state) to `user://reports/<time>/`.
2. Run `tools/send-report.sh` (newest report; `--all` for every unsent one, `--list` to see them).
   It copies to julia over ssh.
3. Tell Claude: `check report <name>` (the script prints the exact line).

On Linux `user://` is `~/.local/share/godot/app_userdata/Sticky Steve/`.

## Art pipeline (Aseprite)

Sources live in `art/source/*.aseprite`; the game draws PNGs. **You only save the .aseprite**:
the tool renders the PNG from it (pixel-identical to Aseprite's own By Rows + Split Tags export)
and builds the SpriteFrames from its **tags** (names, frame order, timing):

    tools/aseprite_frames.py --render art/source/stickysteve.aseprite art/steve/steve.png art/steve/steve_frames.tres

- RGBA files, any number of Normal layers. Hidden layers and layers named `_something` (guides)
  are left out of the render.
- Without `--render` it uses a PNG you exported yourself, and checks it against the .aseprite
  (every claimed cell has pixels, no drawn cell is untagged) instead of guessing.
- A tag loops unless its Repeat is set in Aseprite (tag properties), or it is one of
  `jump`, `jump_stop`, `land`, `raise_pole`, `plant_pole` (played once).
- Re-run the tool after every re-export, then commit the PNG, the .aseprite and the .tres together.

| Sheet | Cell | Tags |
|---|---|---|
| `art/steve/steve.png` | 32x32 | idle 5, jump_charge_1 3, jump_charge_2 3, jump_charge_3 3, jump 4, jump_stop 4, fall 6, land 4, walk_right 3 |
| `art/flag/flag.png` | 32x32 | flag_wave 6 |
| `art/flag/plant_flag.png` | 64x64 | raise_pole 3, spin_pole 5, plant_pole 2 |
| `art/props/pole.png` | 32x32 | single frame |

**Zone tile sheets:** one per zone, `art/world/zone<N>_tiles.png` (128x24: four 24x24 nine-slice
slots for SOLID, STICKY, BOUNCY, CRUMBLE, 8 px tiles). Start from
`art/templates/zone_tiles_template.aseprite`; full spec in the Hub note `sticky-steve-art-spec`.
Render one with `tools/aseprite_frames.py --render art/source/zone1_tiles.aseprite art/world/zone1_tiles.png -`.
The current sheets are placeholders from `tools/make_tile_template.py`; a missing sheet = greybox.

Facing: Steve is drawn facing left (headband trailing right), so facing right flips him.
`walk_right` is drawn facing right and is mirrored for walking left.

Steve's feet are on row 27 of his 32x32 cell, so his sprite uses `offset = (0, -11)`: the node's
origin is then the point between his feet.

**Plant flag.** `pole.png` spins in Steve's hand during `spin_pole`; once planted, `flag.png` takes
over. The hand position per frame is in `art/flag/plant_flag_hand.json` (hand-picked; the boot test
fails if a point stops landing on Steve's arm, so a redrawn frame means re-picking).

## Palette

The whole game is **NYX8** (`art/palette/nyx8.hex`, Aseprite's built-in NYX8). Every PNG pixel and every
colour in a scene must be one of its 8 colours: `tests/palette_checks.gd` fails otherwise. Steve is
**Backgrounds never use Steve's colours** (`#08141e`, `#4e495f`, `#c3a38a`, `#f6d6bd`), so they get
`#0f2a3f`, `#20394f`, `#997577`, `#816271`; behind Steve use `#997577` / `#816271`. Put background and
tile art in `art/world/` and add background nodes to group `background`: the test checks both.

## Layout

| Path | What |
|---|---|
| `scenes/title.tscn` + `scripts/title.gd` | title screen (the project's main scene) |
| `scenes/main.tscn` | the climb: sky, tower, Steve, camera, HUD, dust, pause (`scripts/main.gd` wires the juice) |
| `scripts/pause_menu.gd`, `scripts/settings_panel.gd`, `scripts/ui.gd` | pause, settings panel, shared NYX8 menu theme |
| `scenes/steve.tscn` + `scripts/steve.gd` | Steve: state machine, all movement rules |
| `scenes/tower.tscn` + `scripts/block.gd` | the greybox tower; `Block` = one rectangle (SOLID or STICKY) |
| `scripts/game_camera.gd` | follow + zoom camera |
| `scripts/hud.gd` | timer, height, flag meter, summit card |
| `scripts/sfx.gd` | autoload `Sfx`: sounds from `audio/sfx/` (Kenney, CC0) |
| `scripts/profile.gd` | autoload `Profile`: bests and gems between runs (`user://profile.json`) |
| `scripts/gem.gd`, `scripts/zone.gd` | collectibles; zone start lines (banner + split) |
| `scripts/debug.gd` | autoload `Debug`: F12 report, F11 fullscreen |
| `scripts/nyx8.gd` | `Nyx8`: the palette as constants, for anything drawn in code |
| `art/` | sprites + generated `*_frames.tres`; `art/source/` holds the .aseprite files |
| `tools/` | `aseprite_frames.py`, `send-report.sh` |
| `tests/` | headless suites; each prints `<NAME> pass` |

Physics layers: 1 world, 2 player, 3 sticky, 4 hazard.

## Tests

    godot --headless --path . -s res://tests/boot_checks.gd      # Steve's animations vs tags, input map, main scene, report info
    godot --headless --path . -s res://tests/palette_checks.gd   # every art pixel and scene colour is NYX8
    godot --headless --path . -s res://tests/steve_checks.gd     # every movement rule, frame by frame, plus the camera
    godot --headless --path . -s res://tests/route_checks.gd     # a bot proves the climb and every gem (~20 s)
    godot --headless --path . -s res://tests/profile_checks.gd   # saves, records, bad files
    godot --headless --path . -s res://tests/menu_checks.gd      # title, reset, settings persist, pause, fits 640x360
