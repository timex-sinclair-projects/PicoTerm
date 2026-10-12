"""The keyboard map, TTY emulation and the 32-column screen, in ZEsarUX.

Keys are pressed on the emulated matrix (send-keys-event), so these tests go
through PicoTerm's own scanner. The screen is checked two ways: the shadow
in memory, and ZEsarUX's OCR of the real bitmap.
"""

import os
import time
import unittest

from zrcp import Emulator, find_zesarux, symbols

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAP = os.path.join(ROOT, "build", "picoterm.tap")
SYM = os.path.join(ROOT, "build", "picoterm.sym")
COLS, ROWS = 32, 24


@unittest.skipUnless(find_zesarux(), "ZEsarUX not installed")
class TypewriterTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.sym = symbols(SYM)
        cls.emu = Emulator().__enter__()
        cls.emu.wait_for_text("Sinclair")
        cls.emu.load(TAP)
        # ZEsarUX has no 8251, so PicoTerm reports no modem. With local
        # echo on, it's a typewriter: keys go through the key map and the
        # TTY emulation, which is what these tests are about.
        cls.emu.wait_for_text("No modem", timeout=30)
        cls.emu.cmd(f"write-memory {cls.sym['set_echo']} 1")

    @classmethod
    def tearDownClass(cls):
        cls.emu.close()

    # --- helpers -----------------------------------------------------------

    def shadow_row(self, r):
        data = self.emu.peek(self.sym["SHADOW_CHR"] + r * COLS, COLS)
        return data.decode("latin-1")

    def cursor(self):
        col, row = self.emu.peek(self.sym["cur_col"], 2)
        return row, col

    def settle(self):
        time.sleep(0.3)

    def new_line(self):
        self.emu.press(self.emu.KEY_ENTER)
        self.settle()
        return self.cursor()[0]

    def type(self, text):
        for ch in text:
            if ch.isupper():
                self.emu.press(ch.lower(), self.emu.KEY_CAPS)
            else:
                self.emu.press(ch)
        self.settle()

    def ctrl(self, key):
        self.emu.cmd(f"send-keys-event {self.emu.KEY_CAPS} 1")
        self.emu.cmd(f"send-keys-event {self.emu.KEY_SYM} 1")
        time.sleep(0.12)
        self.emu.cmd(f"send-keys-event {self.emu.KEY_SYM} 0")
        self.emu.cmd(f"send-keys-event {self.emu.KEY_CAPS} 0")
        time.sleep(0.08)
        self.emu.press(key)
        self.settle()

    def assert_screen_matches_shadow(self):
        """The bitmap (as OCR reads it) agrees with the shadow, row by row.
        The cursor's row is skipped: its underline reads as '_'."""
        lines = self.emu.screen().split("\n")
        cur_row = self.cursor()[0]
        for r in range(ROWS):
            if r == cur_row:
                continue
            self.assertEqual(lines[r].rstrip(), self.shadow_row(r).rstrip(),
                             f"row {r}")

    # --- tests -------------------------------------------------------------

    def test_letters_and_caps(self):
        r = self.new_line()
        self.type("abc XYZ 123")
        self.assertEqual(self.shadow_row(r).rstrip(), "abc XYZ 123")

    def test_symbol_shift_map(self):
        r = self.new_line()
        expected = ""
        for key, ch in zip("zxcvasdfgrt1234509876pouylkjhmnb",
                           ":`?/~|\\{}<>!@#$%_)('&\";][=+-^.,*"):
            self.emu.press(key, self.emu.KEY_SYM)
            expected += ch
        self.settle()
        self.assertEqual(self.shadow_row(r).rstrip(), expected)

    def test_unmapped_symbols_send_nothing(self):
        r = self.new_line()
        for key in "qwei":                  # <= <> >= AT
            self.emu.press(key, self.emu.KEY_SYM)
        self.settle()
        self.assertEqual(self.shadow_row(r).rstrip(), "")
        self.assertEqual(self.cursor(), (r, 0))

    def test_tab_and_backspace(self):
        r = self.new_line()
        self.type("ab")
        self.emu.press("3", self.emu.KEY_CAPS)      # TAB
        self.type("c")
        self.assertEqual(self.shadow_row(r)[:9], "ab      c")
        self.emu.press("0", self.emu.KEY_CAPS)      # DELETE
        self.settle()
        self.assertEqual(self.shadow_row(r).rstrip(), "ab")
        self.assertEqual(self.cursor(), (r, 8))

    def test_caps_lock(self):
        r = self.new_line()
        self.emu.press("2", self.emu.KEY_CAPS)
        self.type("ab1")
        self.emu.press("2", self.emu.KEY_CAPS)
        self.type("c")
        self.assertEqual(self.shadow_row(r).rstrip(), "AB1c")

    def test_wrap_is_deferred(self):
        r = self.new_line()
        if r > ROWS - 3:
            self.ctrl("l")
            r = 0
        self.type("x" * COLS)
        self.assertEqual(self.cursor(), (r, COLS - 1))  # held at the edge
        self.type("y")
        self.assertEqual(self.shadow_row(r), "x" * COLS)
        self.assertEqual(self.shadow_row(r + 1).rstrip(), "y")
        self.assertEqual(self.cursor(), (r + 1, 1))

    def test_scroll(self):
        self.ctrl("l")                       # Ctrl-L: form feed, clear
        self.assertEqual(self.cursor(), (0, 0))
        for i in range(ROWS + 4):
            self.type(chr(ord("a") + i % 26))
            self.emu.press(self.emu.KEY_ENTER)
        self.settle()
        # 28 lines on 24 rows: the first 5 have scrolled off ("a" to "e"),
        # and the cursor sits on an empty bottom row.
        self.assertEqual(self.cursor(), (ROWS - 1, 0))
        self.assertEqual(self.shadow_row(0).rstrip(), "f")
        self.assertEqual(self.shadow_row(ROWS - 2).rstrip(), "b")   # 28th: 'b'
        self.assertEqual(self.shadow_row(ROWS - 1).rstrip(), "")
        self.assert_screen_matches_shadow()

    def test_form_feed_clears(self):
        self.type("junk")
        self.ctrl("l")
        self.assertEqual(self.cursor(), (0, 0))
        for r in range(ROWS):
            self.assertEqual(self.shadow_row(r).strip(), "", f"row {r}")
        self.assert_screen_matches_shadow()

    def test_repeat(self):
        r = self.new_line()
        self.emu.press("x", hold=1.5)
        self.settle()
        n = self.shadow_row(r).count("x")
        self.assertGreater(n, 5)             # held well past the delay
        self.assertLess(n, 32)


if __name__ == "__main__":
    unittest.main()
