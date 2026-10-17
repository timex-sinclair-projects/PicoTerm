#!/usr/bin/env python3
"""Screenshots for the user manual, taken from PicoTerm's real binary on
the host machine (tests/hostmachine.py) with the fake modem, TS-Pico and
BBS. Writes manual/images/*.png.

    .venv/bin/python tools/manual_shots.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "tests"))

from fakes import EchoBBS, Fake8251, FakePico, FakeZimodem, XmodemSender  # noqa: E402
from hostmachine import Machine                                           # noqa: E402
from render import save_shot                                              # noqa: E402

OUT = os.path.join(HERE, "..", "manual", "images")
E = b"\x1b["

PHONEBOOK = (b"phone=Test BBS|bbs.example:23|1|2|0|8|0\n"
             b"phone=Level 29|bbs.example:2323|1|2|1|8|0\n"
             b"phone=Raw port|files.example:6400|0|2|0|8|0\n")


def bbs_menu(width):
    """A BBS main menu, the kind a telnet BBS sends, centered for the width."""
    inner = 30
    left = (width - inner - 2) // 2 + 1

    def at(row, text):
        return E + b"%d;%dH" % (row, left) + text
    out = E + b"0m" + E + b"2J" + E + b"1;36m"
    out += at(2, b"\xc9" + b"\xcd" * inner + b"\xbb")
    out += at(3, b"\xba" + E + b"1;33m" + b" THE TEST BBS".center(inner) + E + b"1;36m\xba")
    out += at(4, b"\xcc" + b"\xcd" * inner + b"\xb9")
    for i, (key, label, color) in enumerate([
            (b"M", b"Message areas", b"32"), (b"F", b"File library", b"32"),
            (b"W", b"Who's online", b"33"), (b"G", b"Goodbye", b"31")]):
        line = (E + b"1;37m [" + E + b"1;" + color + b"m" + key + E + b"1;37m] "
                + E + b"0;" + color + b"m" + label.ljust(inner - 5))
        out += at(5 + i, E + b"1;36m\xba" + line + E + b"1;36m\xba")
    out += at(9, b"\xc8" + b"\xcd" * inner + b"\xbc")
    out += E + b"0;44;37m" + E + b"12;1H" + E + b"K Users: 3   New mail: 12"
    out += E + b"0m" + E + b"14;1H" + b"Last caller: TIMEX FAN from Ohio"
    out += E + b"0m" + E + b"22;1H" + E + b"1;37mYour choice: " + E + b"0m"
    return out


class Scene:
    def __init__(self, cols=0, picovideo=False, files=None, hosts=None):
        hosts = hosts or {"bbs.example:23": EchoBBS}
        self.zm = FakeZimodem(hosts=hosts)
        self.m = Machine(acia=Fake8251(self.zm), pico=FakePico(files=files))
        self.m.mem[self.m.sym["set_cols"]] = cols
        self.m.mem[self.m.sym["set_picovideo"]] = int(picovideo)
        self.m.run_frames(200)
        self.m.settle()

    def feed(self, data):
        self.zm.to_terminal.extend(data)
        self.m.run_until(lambda: not self.zm.to_terminal, limit=2000)
        self.m.idle()

    def key(self, k, *mods):
        self.m.press(k, *mods)
        self.m.settle(limit=300)

    def type(self, text):
        self.m.type(text)
        self.m.settle(limit=300)

    def shot(self, name, cursor=True):
        if not cursor and self.m.var("vid_cursor_shown"):
            self.m.run_frames(32)          # half a blink: the cursor off
        save_shot(self.m, os.path.join(OUT, name + ".png"))
        print("images/" + name + ".png")


def main():
    os.makedirs(OUT, exist_ok=True)

    s = Scene()                                       # start-up
    s.shot("startup")

    s = Scene()                                       # a call
    s.type('atdtx"bbs.example:23"\n')
    s.m.run_frames(30)
    s.m.idle()
    s.shot("connect")

    for cols, pv, name in ((0, False, "bbs_32"), (1, False, "bbs_64"),
                           (1, True, "bbs_64_picovideo"), (2, True, "bbs_80")):
        s = Scene(cols=cols, picovideo=pv)
        s.feed(bbs_menu(s.m.cols()))
        s.shot(name, cursor=False)

    s = Scene(files={"picoterm.cfg": PHONEBOOK})      # the menus
    s.key("SPACE", "CAPS")
    s.shot("menu")
    s.key("d")
    s.key("6", "CAPS")
    s.shot("phonebook")
    s.key("e")
    s.shot("entry")
    s.key("SPACE", "CAPS")
    s.key("SPACE", "CAPS")
    s.key("s")
    s.shot("settings")
    s.key("SPACE", "CAPS")
    s.key("w")
    s.m.run_frames(20)
    s.m.settle()
    s.shot("wifi")
    s.key("ENTER")
    s.type("secret12")
    s.shot("wifi_password")

    data = bytes((i * 37 + 11) & 0xFF for i in range(3000))   # a download
    sender = XmodemSender(data)
    s = Scene(hosts={"files.example:23": lambda: sender})
    s.type('atdtx"files.example:23"\n')
    s.m.run_frames(20)
    s.key("SPACE", "CAPS")
    s.key("x")
    s.shot("download_name")
    s.m.press("ENTER")
    s.m.run_until(lambda: s.m.var("xm_blocks") >= 12, limit=2000)
    s.shot("download_progress")
    s.m.run_until(lambda: "Strip" in "".join(s.m.screen_text()), limit=4000)
    s.m.settle()
    s.key("n")
    s.m.run_until(lambda: "Saved" in "".join(s.m.screen_text()), limit=2000)
    s.m.settle()
    s.shot("download_saved")


if __name__ == "__main__":
    main()
