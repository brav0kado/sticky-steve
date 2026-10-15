# Sticky Steve

A 2D Jump King-style climber in Godot 4.7. Steve is a stick figure with one goal: reach the top,
in the coolest way possible. Charge the jump, commit, land it (or don't).

**Status:** greybox prototype. A 1,130 px test tower (16 route steps, two sticky walls, a summit)
with the full core: charged jump, slow air control, wall bounce, the wall slap, flag checkpoints
with the spinning pole, the zoom camera, impact juice and sound. Greybox blocks, default font.

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
| Esc                     | Start        | pause (`pause`)                      |
| F11                     |              | fullscreen                           |
| F12                     |              | bug report (see below)               |

## How it plays (the rules the tests hold)

- **Jump:** hold to charge (three charge animations), release to jump. More charge = higher; a
  full charge releases by itself. The direction held at release sets the launch. Charging stops
  walking.
- **Air control:** slow (an acceleration): you can nudge a jump, not reverse it.
- **Walls:** a plain wall bounces Steve back. A **sticky** wall (studded) can be slapped once
  per airtime: hold toward it when you hit it, he hangs there, then charge a jump away from it.
  Landing restores the slap. Push away without jumping to let go.
- **Flags:** F on solid ground plays the plant (pole spins in his hand, impact on the plant).
  The flag is the checkpoint; landing below it sends him back to it; R goes back any time.
  Unlimited flags, 20 s cooldown (top-right meter).
- **Camera:** locked to the tower's centre, follows vertically; zooms out by the jump's charge,
  never zooms in mid-air, widens on fast falls, eases back to exactly 1.0 after landing.

Tuning lives in the inspector: `scenes/steve.tscn` (jump/air/flag numbers) and the Camera node in
`scenes/main.tscn` (zoom numbers). The tower is `scenes/tower.tscn`: drag Blocks around in the
editor. Keep `route_step` in order: `tests/route_checks.gd` proves every step can be reached.

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
| `scenes/main.tscn` | the world: sky, tower, Steve, camera, HUD, dust (`scripts/main.gd` wires the juice) |
| `scenes/steve.tscn` + `scripts/steve.gd` | Steve: state machine, all movement rules |
| `scenes/tower.tscn` + `scripts/block.gd` | the greybox tower; `Block` = one rectangle (SOLID or STICKY) |
| `scripts/game_camera.gd` | follow + zoom camera |
| `scripts/hud.gd` | timer, height, flag meter, summit card |
| `scripts/sfx.gd` | autoload `Sfx`: sounds from `audio/sfx/` (Kenney, CC0) |
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
    godot --headless --path . -s res://tests/route_checks.gd     # a bot proves each tower step is reachable
