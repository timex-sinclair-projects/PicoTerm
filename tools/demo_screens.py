#!/usr/bin/env python3
"""Render sample screens to build/*.png on the host machine, with the real
2068 ROM font, for a look at what PicoTerm draws.

    .venv/bin/python tools/demo_screens.py [path/to/2068-home.rom]

The ROM (16 KB HOME ROM; the font is at 3D00h) defaults to $PICOTERM_ROM.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tests"))

from fakes import Fake8251, FakePico, FakeZimodem   # noqa: E402
from hostmachine import Machine                      # noqa: E402
from render import save_png                          # noqa: E402

E = b"\x1b["

BBS_MENU = (
    E + b"0;44m" + E + b"2J" + E + b"1;33m" + E + b"2;7H== THE TEST BBS =="
    + E + b"0;44;36m" + E + b"3;4HTimex/Sinclair since 1983"
    + E + b"0;40m" + E + b"5;1H" + E + b"J"
    + E + b"1;37m" + E + b"6;3H[" + E + b"1;32mM" + E + b"1;37m] " + E + b"0;32mMessage areas"
    + E + b"1;37m" + E + b"7;3H[" + E + b"1;32mF" + E + b"1;37m] " + E + b"0;32mFile library"
    + E + b"1;37m" + E + b"8;3H[" + E + b"1;32mC" + E + b"1;37m] " + E + b"0;32mChat with sysop"
    + E + b"1;37m" + E + b"9;3H[" + E + b"1;31mG" + E + b"1;37m] " + E + b"0;31mGoodbye"
    + E + b"0;7m" + E + b"11;3H Reverse " + E + b"0;1;35m bold magenta"
    + E + b"0;30;46m" + E + b"13;1H" + E + b"K Black on cyan, whole line"
    + E + b"0m" + E + b"15;3H" + b"".join(E + b"%dm#" % c for c in range(30, 38))
    + E + b"1m" + b"".join(E + b"%dm#" % c for c in range(30, 38))
    + E + b"0m" + E + b"16;3H" + b"".join(E + b"%dm  " % c for c in range(40, 48))
    + E + b"0m" + E + b"23;1H" + E + b"1;37mYour choice: " + E + b"0m"
)


def main():
    rom_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PICOTERM_ROM")
    if not rom_path:
        sys.exit(__doc__)
    with open(rom_path, "rb") as f:
        font = f.read()[0x3D00:0x4000]
    zm = FakeZimodem()
    acia = Fake8251(zm)
    m = Machine(acia=acia, pico=FakePico(), font=font)
    m.run_frames(200)
    out = os.path.join(HERE, "..", "build")
    save_png(m, os.path.join(out, "startup.png"), scale=3)
    zm.to_terminal.extend(BBS_MENU)
    m.run_until(lambda: not zm.to_terminal, limit=500)
    m.idle()
    m.run_frames(40)                 # cursor visible
    save_png(m, os.path.join(out, "ansi-menu.png"), scale=3)
    print("build/startup.png, build/ansi-menu.png")


if __name__ == "__main__":
    main()
