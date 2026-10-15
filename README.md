# Sticky Steve

A 2D Jump King-style climber in Godot 4.7. Steve is a stick figure with one goal: reach the top,
in the coolest way possible. Charge the jump, commit, land it (or don't).

**Status:** project setup only. The main scene is a placeholder (Steve idling on a strip of ground)
that proves the art pipeline, the F12 report and the verify gate work. No gameplay code yet.

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
| Space                   | A            | jump: hold to charge (`jump`)        |
| Esc                     | Start        | pause (`pause`)                      |
| F11                     |              | fullscreen                           |
| F12                     |              | bug report (see below)               |

## Bug reports (playtest loop)

1. Press **F12** where it looks wrong. The game saves `screenshot.png`, `log.txt` and `info.json`
   (commit, renderer, scene, Steve's position and state) to `user://reports/<time>/`.
2. Run `tools/send-report.sh` (newest report; `--all` for every unsent one, `--list` to see them).
   It copies to julia over ssh.
3. Tell Claude: `check report <name>` (the script prints the exact line).

On Linux `user://` is `~/.local/share/godot/app_userdata/Sticky Steve/`.

## Art pipeline (Aseprite)

Sources live in `art/source/*.aseprite`; the game draws the exported PNGs. Animation names,
frame order and timing come from the **tags** in the .aseprite:

    tools/aseprite_frames.py art/source/stickysteve.aseprite art/steve/steve.png art/steve/steve_frames.tres

- Export the PNG **By Rows**, either with **Split Tags** (one row per tag) or as a plain strip.
  The tool checks the PNG against the .aseprite and refuses a mismatch instead of guessing.
- A tag loops unless its Repeat is set in Aseprite (tag properties), or it is one of
  `jump`, `jump_stop`, `land`, `raise_pole` (played once).
- Re-run the tool after every re-export, then commit the PNG, the .aseprite and the .tres together.

| Sheet | Cell | Tags |
|---|---|---|
| `art/steve/steve.png` | 32x32 | idle 5, jump_charge_1 3, jump_charge_2 3, jump_charge_3 3, jump 4, jump_stop 4, fall 6, land 4 |
| `art/flag/flag.png` | 32x32 | flag_wave 6 |
| `art/flag/plant_flag.png` | 64x64 | raise_pole 3, spin_pole 5, plant 2 (built with `--tags`, see below) |
| `art/props/pole.png` | 32x32 | single frame |

Steve's feet are on row 27 of his 32x32 cell, so his sprite uses `offset = (0, -11)`: the node's
origin is then the point between his feet.

**Plant flag.** `pole.png` spins in Steve's hand during `spin_pole`; once planted, `flag.png` takes
over. The hand position per frame is in `art/flag/plant_flag_hand.json` (hand-picked; the boot test
fails if a point stops landing on Steve's arm, so a redrawn frame means re-picking). The PNG has a
third row (`plant`) that `plant_flag.aseprite` doesn't, so it's built with an override until the
.aseprite is saved with that tag:

    tools/aseprite_frames.py art/source/plant_flag.aseprite art/flag/plant_flag.png art/flag/plant_flag_frames.tres --tags raise_pole:3,spin_pole:5,plant:2

The tool checks every claimed cell holds pixels and no drawn cell is left untagged, so a wrong
`--tags` is refused.

## Palette

The whole game is **NYX8** (`art/palette/nyx8.hex`, Aseprite's built-in NYX8). Every PNG pixel and every
colour in a scene must be one of its 8 colours: `tests/palette_checks.gd` fails otherwise. Steve is
**Backgrounds never use Steve's colours** (`#08141e`, `#4e495f`, `#c3a38a`, `#f6d6bd`), so they get
`#0f2a3f`, `#20394f`, `#997577`, `#816271`; behind Steve use `#997577` / `#816271`. Put background and
tile art in `art/world/` and add background nodes to group `background`: the test checks both.

## Layout

| Path | What |
|---|---|
| `scenes/main.tscn` | main scene (placeholder) |
| `scripts/debug.gd` | autoload `Debug`: F12 report, F11 fullscreen |
| `scripts/nyx8.gd` | `Nyx8`: the palette as constants, for anything drawn in code |
| `art/` | sprites + generated `*_frames.tres`; `art/source/` holds the .aseprite files |
| `tools/` | `aseprite_frames.py`, `send-report.sh` |
| `tests/` | headless suites; each prints `<NAME> pass` |

Physics layers: 1 world, 2 player, 3 sticky, 4 hazard.

## Tests

    godot --headless --path . -s res://tests/boot_checks.gd      # Steve's animations vs tags, input map, main scene, report info
    godot --headless --path . -s res://tests/palette_checks.gd   # every art pixel and scene colour is NYX8
