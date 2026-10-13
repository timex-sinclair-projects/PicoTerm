"""Render the host machine's 32-column screen (bitmap + attributes) to a
PNG, the way a TS-2068 would show it. Standard library only.

    from render import save_png
    save_png(machine, "screen.png", scale=3)
"""

import struct
import zlib

# The 2068's colours, normal and BRIGHT (RGB).
PALETTE = [
    [(0, 0, 0), (0, 0, 0xCD), (0xCD, 0, 0), (0xCD, 0, 0xCD),
     (0, 0xCD, 0), (0, 0xCD, 0xCD), (0xCD, 0xCD, 0), (0xCD, 0xCD, 0xCD)],
    [(0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF),
     (0, 0xFF, 0), (0, 0xFF, 0xFF), (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)],
]


def pixels(mem):
    """192 rows of 256 RGB tuples from DF1 and the attribute file."""
    rows = []
    for y in range(192):
        line = []
        base = 0x4000 | (y & 0xC0) << 5 | (y & 0x07) << 8 | (y & 0x38) << 2
        for col in range(32):
            byte = mem[base + col]
            a = mem[0x5800 + (y >> 3) * 32 + col]
            bright = (a >> 6) & 1
            ink, paper = PALETTE[bright][a & 7], PALETTE[bright][(a >> 3) & 7]
            for bit in range(7, -1, -1):
                line.append(ink if byte >> bit & 1 else paper)
        rows.append(line)
    return rows


def save_png(machine, path, scale=2, border=16):
    rows = pixels(machine.mem)
    bc = PALETTE[0][machine.border]
    w = (256 + 2 * border) * scale
    raw = bytearray()
    full = [bc] * (256 + 2 * border)
    out_rows = [full] * border + [[bc] * border + r + [bc] * border for r in rows] + [full] * border
    for r in out_rows:
        line = bytearray()
        for px in r:
            line += bytes(px) * scale
        for _ in range(scale):
            raw += b"\x00" + line
    h = len(out_rows) * scale

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)
