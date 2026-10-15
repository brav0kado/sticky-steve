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

--tags name:count,...  overrides the .aseprite's tags for a rows-layout PNG that is newer than its
.aseprite (an export whose source wasn't saved). Frame timing still comes from the .aseprite's
first frame. It prints a warning: the fix is to save the .aseprite, then drop the flag.
"""
import argparse
import struct
import sys
import zlib
from pathlib import Path

# Played once and held on the last frame. Repeat in the .aseprite overrides this for new tags.
ONE_SHOT = {"jump", "jump_stop", "land", "raise_pole", "plant"}

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


def png_alpha(path: Path) -> list[bytearray]:
    """Alpha channel rows of an 8-bit RGBA, non-interlaced PNG (what Aseprite exports)."""
    b = path.read_bytes()
    o, idat, w = 8, b"", 0
    while o < len(b):
        n, kind = struct.unpack(">I4s", b[o:o + 8])
        data = b[o + 8:o + 8 + n]
        if kind == b"IHDR":
            w, _h, depth, ctype, _c, _f, interlace = struct.unpack(">IIBBBBB", data)
            if (depth, ctype, interlace) != (8, 6, 0):
                raise SheetError(f"{path}: need 8-bit RGBA non-interlaced PNG (Aseprite default)")
        elif kind == b"IDAT":
            idat += data
        o += 12 + n
    raw, stride, rows, prev = zlib.decompress(idat), w * 4, [], bytearray(w * 4)
    for y in range(len(raw) // (stride + 1)):
        f, line = raw[y * (stride + 1)], bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):  # undo the PNG row filter (spec section 9)
            a = line[i - 4] if i >= 4 else 0
            up, c = prev[i], (prev[i - 4] if i >= 4 else 0)
            if f == 1: line[i] = (line[i] + a) & 255
            elif f == 2: line[i] = (line[i] + up) & 255
            elif f == 3: line[i] = (line[i] + (a + up) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(up - c), abs(a - c), abs(a + up - 2 * c)
                line[i] = (line[i] + (a if pa <= pb and pa <= pc else up if pb <= pc else c)) & 255
        rows.append(line[3::4])
        prev = line
    return rows


def cell_used(alpha: list[bytearray], x: int, y: int, w: int, h: int) -> bool:
    return any(any(row[x:x + w]) for row in alpha[y:y + h])


def check_cells(ase: dict, cells: dict, alpha: list[bytearray]) -> None:
    """Every claimed cell has pixels, and nothing drawn sits right after a tag's last cell."""
    w, h = ase["w"], ase["h"]
    sheet_w = len(alpha[0]) if alpha else 0
    for name, xy in cells.items():
        for x, y in xy:
            if not cell_used(alpha, x, y, w, h):
                raise SheetError(f"tag {name}: cell ({x},{y}) is empty, so the tag claims more frames than the sheet has")
        x, y = xy[-1]
        if x + 2 * w <= sheet_w and cell_used(alpha, x + w, y, w, h) and not any((x + w, y) in v for v in cells.values()):
            raise SheetError(f"tag {name}: cell ({x + w},{y}) after its last frame has pixels that no tag uses")


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


def override_tags(ase: dict, spec: str) -> dict:
    """Replace the tags with name:count rows (timing from the .aseprite's first frame)."""
    tags, start = [], 0
    for item in spec.split(","):
        name, _, count = item.partition(":")
        if not name or not count.isdigit() or int(count) < 1:
            raise SheetError(f"bad --tags entry {item!r}: want name:count")
        tags.append((name, start, start + int(count) - 1, 0))
        start += int(count)
    dur = ase["durations"][0] if ase["durations"] else 100
    return {**ase, "tags": tags, "durations": [dur] * start}


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
    ap.add_argument("--tags", help="name:count,... rows override (PNG newer than its .aseprite)")
    a = ap.parse_args()
    try:
        ase = read_aseprite(a.aseprite)
        if a.tags:
            ase = override_tags(ase, a.tags)
            print(f"WARNING: tags from --tags, not {a.aseprite.name}: save the .aseprite and drop --tags")
        cells = layout(ase, *png_size(a.png))
        check_cells(ase, cells, png_alpha(a.png))
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
