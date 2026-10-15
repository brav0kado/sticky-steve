#!/usr/bin/env python3
"""Make the zone tile-sheet template (.aseprite + .png) and the placeholder sheets for each zone.

    tools/make_tile_template.py            writes art/templates/zone_tiles_template.{aseprite,png}
                                           and art/world/zone{1,2,3}_tiles.png (placeholders)

Sheet layout (what Block._draw_skin reads): 128x24 px, four 24x24 slots at x = 0, 32, 64, 96 for
SOLID, STICKY, BOUNCY, CRUMBLE. Each slot is a 3x3 grid of 8 px tiles: corners stay put, the
edge and centre tiles repeat, so middle tiles must tile seamlessly every 8 px.
Colours: backgrounds never use Steve's colours, so tiles use NAVY, SLATE, DUSK, MAUVE only
(tests/palette_checks.gd enforces it for art/world/).

The .aseprite is written by hand (Aseprite isn't installed here): RGBA, NYX8 palette, 8x8 grid,
a "_guide" layer (half opacity; the importer skips "_" layers) and a "tiles" layer holding the
placeholder to paint over. Stdlib only.
"""
import struct
import sys
import zlib
from pathlib import Path

W, H = 128, 24
SLOT = 24
SLOT_X = [0, 32, 64, 96]  # SOLID, STICKY, BOUNCY, CRUMBLE
NYX8 = ["08141e", "0f2a3f", "20394f", "f6d6bd", "c3a38a", "997577", "816271", "4e495f"]
INK, NAVY, SLATE, CREAM, SAND, DUSK, MAUVE, SHADOW = (tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in NYX8)
CLEAR = (0, 0, 0, 0)

# Per zone: (solid fill, solid edge) so each zone reads a little different on the same sky.
ZONES = {1: (SLATE, NAVY), 2: (NAVY, SLATE), 3: (SLATE, MAUVE)}


def slot_pixel(surface: int, zone: int, x: int, y: int) -> tuple:
    """Colour at (x, y) of a 24x24 slot. Middle rows/cols repeat with period 8 (tileable)."""
    fill, edge = ZONES[zone]
    border = x == 0 or x == SLOT - 1 or y == SLOT - 1
    my = y % 8  # position inside a tile: patterns repeat on it
    if surface == 0:  # SOLID: lit top band, outline, a subtle brick seam
        if y < 2:
            return edge
        if border:
            return NAVY if edge != NAVY else SLATE
        return edge if (my == 5 and (x // 4) % 2 == 0) else fill
    if surface == 1:  # STICKY: mauve, studs down both faces
        if y < 2 or border:
            return SLATE
        if (x in (2, 3) or x in (SLOT - 4, SLOT - 3)) and my in (3, 4):
            return SLATE
        return MAUVE
    if surface == 2:  # BOUNCY: navy with a mauve zigzag spring on top
        if y < 2:
            return MAUVE
        if y in (2, 3) and (x // 2) % 2 == 0:
            return MAUVE
        if y in (4, 5) and (x // 2) % 2 == 1:
            return MAUVE
        return SLATE if border else NAVY
    # CRUMBLE: slate with dusk cracks
    if y < 2:
        return DUSK
    if border:
        return NAVY
    if (x % 8, my) in ((2, 3), (3, 4), (4, 5), (6, 6)):
        return DUSK
    return SLATE


def sheet(zone: int) -> list:
    rows = [[CLEAR] * W for _ in range(H)]
    for s, ox in enumerate(SLOT_X):
        for y in range(SLOT):
            for x in range(SLOT):
                rows[y][ox + x] = slot_pixel(s, zone, x, y) + (255,)
    return rows


def guide() -> list:
    """Cell outlines (every 8 px) and a dot in each slot's corner tiles: where corners go."""
    rows = [[CLEAR] * W for _ in range(H)]
    for ox in SLOT_X:
        for y in range(SLOT):
            for x in range(SLOT):
                if x % 8 == 0 or y % 8 == 0 or x == SLOT - 1 or y == SLOT - 1:
                    rows[y][ox + x] = CREAM + (255,)
    return rows


def png(path: Path, rows: list) -> None:
    raw = b"".join(b"\x00" + bytes(c for px in r for c in px) for r in rows)

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", len(rows[0]), len(rows), 8, 6, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def aseprite(path: Path, layers: list) -> None:
    """layers: [(name, opacity, rows)] bottom to top. One frame, RGBA, NYX8 palette, 8x8 grid."""
    def chunk(ctype: int, body: bytes) -> bytes:
        return struct.pack("<IH", len(body) + 6, ctype) + body

    def string(s: str) -> bytes:
        b = s.encode("utf-8")
        return struct.pack("<H", len(b)) + b

    chunks = [chunk(0x2007, struct.pack("<HHI8x", 1, 0, 0))]  # colour profile: sRGB
    pal = struct.pack("<III8x", len(NYX8), 0, len(NYX8) - 1)
    for h in NYX8:
        pal += struct.pack("<H4B", 0, int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)
    chunks.append(chunk(0x2019, pal))
    for name, opacity, _rows in layers:
        # flags 1 visible | 2 editable; normal layer, normal blend
        chunks.append(chunk(0x2004, struct.pack("<HHHHHHB3x", 3, 0, 0, 0, 0, 0, opacity) + string(name)))
    for i, (_name, _op, rows) in enumerate(layers):
        pixels = zlib.compress(bytes(c for r in rows for px in r for c in px), 9)
        chunks.append(chunk(0x2005, struct.pack("<HhhBHh5xHH", i, 0, 0, 255, 2, 0, W, H) + pixels))
    body = b"".join(chunks)
    frame = struct.pack("<IHHH2xI", 16 + len(body), 0xF1FA, min(len(chunks), 0xFFFF), 100, len(chunks)) + body
    header = struct.pack("<IHHHHHIH8xB3xHBBhhHH84x", 128 + len(frame), 0xA5E0, 1, W, H, 32, 1, 100,
                         0, len(NYX8), 1, 1, 0, 0, 8, 8)
    assert len(header) == 128
    path.write_bytes(header + frame)


def main() -> int:
    root = Path(__file__).resolve().parent.parent
    (root / "art/templates").mkdir(parents=True, exist_ok=True)
    (root / "art/world").mkdir(parents=True, exist_ok=True)
    tiles = sheet(1)
    aseprite(root / "art/templates/zone_tiles_template.aseprite", [("tiles", 255, tiles), ("_guide", 96, guide())])
    # A reference PNG: the placeholder with the guide over it.
    ref = [[g if g[3] else t for t, g in zip(tr, gr)] for tr, gr in zip(tiles, guide())]
    png(root / "art/templates/zone_tiles_template.png", ref)
    for z in ZONES:
        png(root / f"art/world/zone{z}_tiles.png", sheet(z))
    print("wrote art/templates/zone_tiles_template.{aseprite,png} and art/world/zone{1,2,3}_tiles.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
