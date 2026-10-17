#!/usr/bin/env python3
"""Render sample screens to build/*.png on the host machine, for a look at
what PicoTerm draws in each column mode.

    .venv/bin/python tools/demo_screens.py
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


def box_menu(width):
    """A CP437 box-drawn BBS menu, centered for this width."""
    inner = 30
    left = (width - inner - 2) // 2 + 1
    def at(row, text):
        return E + b"%d;%dH" % (row, left) + text
    out = E + b"0m" + E + b"2J" + E + b"1;36m"
    out += at(2, b"\xc9" + b"\xcd" * inner + b"\xbb")
    for i, (key, label, color) in enumerate([
            (b"M", b"Message areas", b"32"), (b"F", b"File library", b"32"),
            (b"W", b"Who's online", b"33"), (b"G", b"Goodbye", b"31")]):
        line = (E + b"1;37m [" + E + b"1;" + color + b"m" + key + E + b"1;37m] "
                + E + b"0;" + color + b"m" + label.ljust(inner - 5))
        out += at(3 + i, E + b"1;36m\xba" + line + E + b"1;36m\xba")
    out += at(7, b"\xc8" + b"\xcd" * inner + b"\xbc")
    out += E + b"0;44;33m" + E + b"10;1H" + E + b"K"
    out += b"  PicoTerm in %d columns: \xb0\xb1\xb2\xdb  \x03 \x04 \x05 \x06  " % width
    out += E + b"0m" + E + b"12;1H" + b"The quick brown fox jumps over the lazy dog. " * 2
    out += E + b"0m" + E + b"23;1H" + E + b"1;37mYour choice: " + E + b"0m"
    return out


def run(font, picovideo, cols, name, data):
    zm = FakeZimodem()
    acia = Fake8251(zm)
    m = Machine(acia=acia, pico=FakePico(), font=font)
    m.mem[m.sym["set_picovideo"]] = int(picovideo)
    m.mem[m.sym["set_cols"]] = cols
    m.run_frames(200)
    if data:
        zm.to_terminal.extend(data(m.cols()) if callable(data) else data)
        m.run_until(lambda: not zm.to_terminal, limit=500)
        m.idle()
    path = os.path.join(HERE, "..", "build", name)
    save_png(m, path, scale=3)
    return "build/" + name


def main():
    rom_path = sys.argv[1] if len(sys.argv) > 1 else os.environ.get("PICOTERM_ROM")
    font = None
    if rom_path:
        with open(rom_path, "rb") as f:
            font = f.read()[0x3D00:0x4000]
    made = [
        run(font, False, 0, "startup.png", None),
        run(font, False, 0, "ansi-menu.png", BBS_MENU),
        run(font, False, 0, "box-32.png", box_menu),
        run(font, False, 1, "box-64-scld.png", box_menu),
        run(font, True, 1, "box-64-picovideo.png", box_menu),
        run(font, True, 2, "box-80-picovideo.png", box_menu),
    ]
    made += menu_screens()
    print("\n".join(made))


def menu_screens():
    """The menu, phonebook, an entry, settings and WiFi, in 32 columns."""
    files = {"picoterm.cfg": b"phone=Test BBS|bbs.example:23|1|2|0|8|0\n"
                             b"phone=Level 29|bbs.fozztexx.com:23|1|2|1|8|0\n"
                             b"phone=Particles|particlesbbs.dyndns.org:6400|1|2|0|8|0\n"}
    zm = FakeZimodem()
    m = Machine(acia=Fake8251(zm), pico=FakePico(files=files))
    m.run_frames(200)
    m.idle()
    out = os.path.join(HERE, "..", "build")
    made = []

    def shot(name):
        m.settle()
        save_png(m, os.path.join(out, name), scale=3)
        made.append("build/" + name)

    m.press("SPACE", "CAPS")
    shot("menu.png")
    m.press("d")
    m.press("6", "CAPS")
    shot("phonebook.png")
    m.press("e")
    shot("entry.png")
    m.press("SPACE", "CAPS")
    m.press("SPACE", "CAPS")
    m.press("s")
    shot("settings.png")
    m.press("SPACE", "CAPS")
    m.press("w")
    m.run_frames(20)
    shot("wifi.png")
    return made


if __name__ == "__main__":
    main()
