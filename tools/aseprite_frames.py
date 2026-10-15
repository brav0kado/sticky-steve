#!/usr/bin/env python3
"""Build a Godot SpriteFrames .tres from an .aseprite file and its exported PNG sheet.

The .aseprite is the source of truth for animation names (tags), frame order and timing; the PNG
is what the game draws. Godot can't read .aseprite, so this bridges the two without an Aseprite
install. Stdlib only.

    tools/aseprite_frames.py art/source/stickysteve.aseprite art/steve/steve.png art/steve/steve_frames.tres

Sheet layouts it accepts (anything else is an error, never a guess):
  rows    one row per tag, in tag order, each row starting at column 0  (Aseprite: "By Rows" + "Split Tags")
  strip   every frame in order across the sheet, wrapping at the sheet width  ("By Rows", no split)

Looping: a tag loops unless its Aseprite Repeat is set (> 0) or its name is in ONE_SHOT.
Set Repeat = 1 in Aseprite's tag properties to make a one-shot explicit.
"""
import argparse
import struct
import sys
from pathlib import Path

# Played once and held on the last frame. Repeat in the .aseprite overrides this for new tags.
ONE_SHOT = {"jump", "jump_stop", "land", "raise_pole"}

CHUNK_TAGS = 0x2018
ASE_MAGIC = 0xA5E0
FRAME_MAGIC = 0xF1FA


class SheetError(Exception):
    pass


def read_aseprite(path: Path) -> dict:
    """Canvas size, per-frame durations (ms) and tags [(name, from, to, repeat)]."""
    b = path.read_bytes()
    _size, magic, frames, w, h = struct.unpack_from("<IHHHH", b, 0)
    if magic != ASE_MAGIC:
        raise SheetError(f"{path}: not an .aseprite file")
    o, durations, tags = 128, [], []
    for _ in range(frames):
        fsize, fmagic, old_n, dur = struct.unpack_from("<IHHH", b, o)
        if fmagic != FRAME_MAGIC:
            raise SheetError(f"{path}: bad frame header at byte {o}")
        n = struct.unpack_from("<I", b, o + 12)[0] or old_n
        durations.append(dur)
        c = o + 16
        for _ in range(n):
            csize, ctype = struct.unpack_from("<IH", b, c)
            if ctype == CHUNK_TAGS:
                count = struct.unpack_from("<H", b, c + 6)[0]
                q = c + 16
                for _ in range(count):
                    start, end, _direction, repeat = struct.unpack_from("<HHBH", b, q)
                    name_len = struct.unpack_from("<H", b, q + 17)[0]
                    name = b[q + 19:q + 19 + name_len].decode("utf-8")
                    tags.append((name, start, end, repeat))
                    q += 19 + name_len
            c += csize
        o += fsize
    if not tags:
        tags = [("default", 0, frames - 1, 0)]  # untagged file: one animation of every frame
    return {"w": w, "h": h, "durations": durations, "tags": tags}


def png_size(path: Path) -> tuple[int, int]:
    b = path.read_bytes()[:24]
    if b[:8] != b"\x89PNG\r\n\x1a\n":
        raise SheetError(f"{path}: not a PNG")
    return struct.unpack(">II", b[16:24])


def layout(ase: dict, sheet_w: int, sheet_h: int) -> dict[str, list[tuple[int, int]]]:
    """Cell (x, y) of every frame per tag, after checking the sheet really has that layout."""
    w, h, tags = ase["w"], ase["h"], ase["tags"]
    if sheet_w % w or sheet_h % h:
        raise SheetError(f"sheet {sheet_w}x{sheet_h} is not a grid of {w}x{h} cells")
    cols, rows = sheet_w // w, sheet_h // h
    longest = max(end - start + 1 for _, start, end, _ in tags)
    if rows == len(tags) and longest <= cols:
        return {name: [(i * w, r * h) for i in range(end - start + 1)]
                for r, (name, start, end, _) in enumerate(tags)}
    total = len(ase["durations"])
    if (total + cols - 1) // cols == rows:
        return {name: [((f % cols) * w, (f // cols) * h) for f in range(start, end + 1)]
                for name, start, end, _ in tags}
    raise SheetError(
        f"sheet is {cols}x{rows} cells but the .aseprite has {total} frames in {len(tags)} tags: "
        "re-export the PNG from this .aseprite (By Rows, with or without Split Tags)")


def write_tres(ase: dict, cells: dict, png_res: str, out: Path) -> None:
    w, h, durs = ase["w"], ase["h"], ase["durations"]
    subs, anims, n = [], [], 0
    for name, start, end, repeat in ase["tags"]:
        frame_durs = durs[start:end + 1]
        base = min(frame_durs) or 100
        frames = []
        for (x, y), d in zip(cells[name], frame_durs):
            n += 1
            subs.append(f'[sub_resource type="AtlasTexture" id="f{n}"]\n'
                        f'atlas = ExtResource("1")\nregion = Rect2({x}, {y}, {w}, {h})\n')
            frames.append(f'{{"duration": {d / base:g}, "texture": SubResource("f{n}")}}')
        loop = "false" if repeat > 0 or name in ONE_SHOT else "true"
        anims.append(f'{{"frames": [{", ".join(frames)}], "loop": {loop}, '
                     f'"name": &"{name}", "speed": {1000 / base:g}}}')
    text = (f'[gd_resource type="SpriteFrames" load_steps={n + 2} format=3]\n\n'
            f'[ext_resource type="Texture2D" path="{png_res}" id="1"]\n\n'
            + "\n".join(subs)
            + f'\n[resource]\nanimations = [{", ".join(anims)}]\n')
    out.write_text(text)


def res_path(png: Path) -> str:
    """res:// path of the PNG: the project root is the nearest folder with project.godot."""
    p = png.resolve()
    for root in p.parents:
        if (root / "project.godot").exists():
            return "res://" + p.relative_to(root).as_posix()
    raise SheetError(f"{png} is not inside a Godot project")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("aseprite", type=Path)
    ap.add_argument("png", type=Path)
    ap.add_argument("out", type=Path)
    a = ap.parse_args()
    try:
        ase = read_aseprite(a.aseprite)
        cells = layout(ase, *png_size(a.png))
        write_tres(ase, cells, res_path(a.png), a.out)
    except (SheetError, OSError, struct.error) as e:
        print(f"aseprite_frames: {e}", file=sys.stderr)
        return 1
    for name, start, end, repeat in ase["tags"]:
        loop = "once" if repeat > 0 or name in ONE_SHOT else "loop"
        print(f"  {name:<14} {end - start + 1} frames  {loop}")
    print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
