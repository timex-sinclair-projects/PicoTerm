"""Render the host machine's screen to a PNG, the way the display would
show it, in any of PicoTerm's column modes. Standard library only.

    from render import save_png
    save_png(machine, "screen.png", scale=3)
"""

import struct
import zlib

# The 2068's colors, normal and BRIGHT (RGB).
PALETTE = [
    [(0, 0, 0), (0, 0, 0xCD), (0xCD, 0, 0), (0xCD, 0, 0xCD),
     (0, 0xCD, 0), (0, 0xCD, 0xCD), (0xCD, 0xCD, 0), (0xCD, 0xCD, 0xCD)],
    [(0, 0, 0), (0, 0, 0xFF), (0xFF, 0, 0), (0xFF, 0, 0xFF),
     (0, 0xFF, 0), (0, 0xFF, 0xFF), (0xFF, 0xFF, 0), (0xFF, 0xFF, 0xFF)],
]


def _color(a, ink):
    bright = (a >> 6) & 1
    return PALETTE[bright][a & 7] if ink else PALETTE[bright][(a >> 3) & 7]


def pixels(machine):
    """192 rows of RGB tuples as the display would show them: 256 wide in
    32 columns, 512 in 64, 640 in 80 (PicoVideo's text mode, drawn with
    PicoTerm's font, which is the same CP437 font PicoVideo uses)."""
    mem = machine.mem
    mode = machine.mode()
    decr = machine.decr
    rows = []
    font = machine.sym["FONT"]
    for y in range(192):
        line = []
        if mode == 2:
            r = y >> 3
            for col in range(80):
                code = mem[0x4000 + r * 80 + col]
                a = mem[0x4780 + r * 80 + col]
                bits = mem[font + code * 8 + (y & 7)]
                for bit in range(7, -1, -1):
                    line.append(_color(a, bits >> bit & 1))
        else:
            base = 0x4000 | (y & 0xC0) << 5 | (y & 0x07) << 8 | (y & 0x38) << 2
            cells = []
            for col in range(32):
                a1 = mem[0x5800 + (y >> 3) * 32 + col]
                cells.append((mem[base + col], a1))
                if mode == 1:
                    a2 = mem[0x7800 + (y >> 3) * 32 + col]
                    cells.append((mem[base + 0x2000 + col], a2))
            for byte, a in cells:
                if mode == 1 and decr & 7 == 6:           # SCLD: one color pair
                    ink = (decr >> 3) & 7
                    a = ink | (7 - ink) << 3
                for bit in range(7, -1, -1):
                    line.append(_color(a, byte >> bit & 1))
        rows.append(line)
    return rows


def save_png(machine, path, scale=2, border=16):
    """Scaled to keep the TV's shape: 32 columns scale x scale; 64 and 80
    columns, whose dots are narrower, half as much across."""
    rows = pixels(machine)
    width = len(rows[0])
    sx = scale if width == 256 else max(1, scale // 2)
    sy = scale
    bx = border * scale // sx
    bc = PALETTE[0][machine.border]
    full = [bc] * (width + 2 * bx)
    out_rows = ([full] * border + [[bc] * bx + r + [bc] * bx for r in rows]
                + [full] * border)
    raw = bytearray()
    for r in out_rows:
        line = bytearray()
        for px in r:
            line += bytes(px) * sx
        for _ in range(sy):
            raw += b"\x00" + line
    w = len(full) * sx
    h = len(out_rows) * sy

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    png = (b"\x89PNG\r\n\x1a\n"
           + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
           + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
           + chunk(b"IEND", b""))
    with open(path, "wb") as f:
        f.write(png)


def save_shot(machine, path):
    """A manual screenshot: no border, square pixels as the display shows
    them: 256 x 192 doubled to 512 x 384 in 32 columns; 512 x 192 (64) and
    640 x 192 (80) doubled vertically only, since their dots are half as
    wide."""
    rows = pixels(machine)
    sx = 2 if len(rows[0]) == 256 else 1
    raw = bytearray()
    for r in rows:
        line = bytearray()
        for px in r:
            line += bytes(px) * sx
        raw += (b"\x00" + line) * 2
    w, h = len(rows[0]) * sx, len(rows) * 2

    def chunk(kind, data):
        return (struct.pack(">I", len(data)) + kind + data
                + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF))

    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n"
                + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
                + chunk(b"IEND", b""))
