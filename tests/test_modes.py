"""M4: the 32-, 64- and 80-column drivers, switching between them, and the
CP437 font, on the host machine."""

import unittest

try:
    import z80  # noqa: F401
    HAVE_Z80 = True
except ImportError:
    HAVE_Z80 = False

if HAVE_Z80:
    from hostmachine import Machine
from fakes import Fake8251, FakePico, FakeZimodem

CSI = b"\x1b["
VM_32, VM_64, VM_80 = 0, 1, 2


@unittest.skipUnless(HAVE_Z80, "the z80 package isn't installed (make venv)")
class ModesTest(unittest.TestCase):
    def start(self, picovideo=False, cols=VM_32):
        self.zm = FakeZimodem()
        self.acia = Fake8251(self.zm)
        self.m = Machine(acia=self.acia, pico=FakePico())
        self.m.mem[self.m.sym["set_picovideo"]] = int(picovideo)
        self.m.mem[self.m.sym["set_cols"]] = cols
        self.m.run_frames(200)
        self.sent = bytearray()
        self.zm.from_terminal = lambda b, f: self.sent.append(b)
        self.feed(CSI + b"2J")
        return self.m

    def feed(self, data):
        self.zm.to_terminal.extend(data)
        self.m.run_until(lambda: not self.zm.to_terminal and self.acia.rx_hold is None,
                         limit=500)
        self.assertTrue(self.m.idle())

    def next_mode(self):
        self.m.press("9", "CAPS")
        self.assertTrue(self.m.idle())

    def assert_screen_matches(self):
        self.assertEqual(self.m.screen_text(), self.m.shadow_text())

    # --- switching -------------------------------------------------------

    def test_cycle_without_picovideo(self):
        m = self.start()
        self.assertEqual(m.mode(), VM_32)
        self.next_mode()
        self.assertEqual((m.mode(), m.cols()), (VM_64, 64))
        self.assertEqual(m.decr & 0x3F, 0x3E)         # mode 6, white ink
        self.next_mode()
        self.assertEqual((m.mode(), m.cols()), (VM_32, 32))
        self.assertEqual(m.decr & 0x3F, 0x00)

    def test_cycle_with_picovideo(self):
        m = self.start(picovideo=True)
        self.next_mode()
        self.assertEqual(m.decr & 0x3F, 0x07)         # PicoVideo 64 with color
        self.next_mode()
        self.assertEqual((m.mode(), m.cols()), (VM_80, 80))
        self.assertEqual(m.decr & 0x3F, 0x05)
        self.next_mode()
        self.assertEqual(m.mode(), VM_32)

    def test_decr_keeps_bit_7(self):
        m = self.start()
        m.decr = 0x80                                  # as if EXROM were selected
        self.next_mode()
        self.assertEqual(m.decr, 0x80 | 0x3E)

    def test_text_survives_switching(self):
        m = self.start(picovideo=True)
        self.feed(b"first line\r\n" + CSI + b"31msecond" + CSI + b"0m")
        self.next_mode()                               # 64
        self.assertEqual(m.shadow_text()[0].rstrip(), "first line")
        self.assertEqual(m.shadow_text()[1].rstrip(), "second")
        self.assert_screen_matches()
        self.assertEqual(m.screen_attrs()[1][:6], [0x02] * 6)   # red, in mode 7
        self.feed(CSI + b"3;40Hfar right")
        self.next_mode()                               # 80
        self.assertEqual(m.shadow_text()[2][39:48], "far right")
        self.assert_screen_matches()
        self.assertEqual(m.screen_attrs()[1][:6], [0x02] * 6)
        self.next_mode()                               # back to 32: cut at 32
        self.assertEqual(m.shadow_text()[2].rstrip(), "")
        self.assertEqual(m.shadow_text()[0].rstrip(), "first line")
        self.assert_screen_matches()
        self.assertEqual(m.screen_attrs(), m.shadow_attrs())

    def test_cursor_pulled_in_when_narrower(self):
        m = self.start()
        self.next_mode()
        self.feed(CSI + b"5;60H")
        self.next_mode()
        self.assertEqual(m.cursor(), (4, 31))

    def test_switch_time(self):
        m = self.start(picovideo=True)
        for mode in range(3):
            before = m.frame
            self.next_mode()
            self.assertLess(m.frame - before, 40, f"to mode {m.mode()}")

    def test_start_up_in_64(self):
        m = self.start(cols=VM_64)
        self.assertEqual(m.cols(), 64)
        self.assertEqual(m.decr & 0x3F, 0x3E)

    # --- drawing in each mode ----------------------------------------------

    def exercise(self):
        """Full-width text, scrolling, erasing and editing in this mode."""
        m = self.m
        w = m.cols()
        for r in range(30):                            # 6 rows scroll off
            self.feed(bytes([65 + r % 26]) * w)
        self.feed(CSI + b"1;1H" + CSI + b"2@" + CSI + b"2;5H" + CSI + b"3P"
                  + CSI + b"4;10H" + CSI + b"K" + CSI + b"10;1H" + CSI + b"L"
                  + CSI + b"20;1H" + CSI + b"M")
        self.assert_screen_matches()
        rows = m.shadow_text()
        self.assertEqual(rows[0], "  " + "G" * (w - 2))
        self.assertEqual(rows[1], "HHHH" + "H" * (w - 7) + "   ")
        self.assertEqual(rows[3], "J" * 9 + " " * (w - 9))
        self.assertEqual(rows[9].strip(), "")
        self.feed(CSI + b"255;255H" + CSI + b"6n")
        self.assertEqual(bytes(self.sent), b"\x1b[24;%dR" % w)

    def test_drawing_in_32(self):
        self.start()
        self.exercise()

    def test_drawing_in_64(self):
        self.start(cols=VM_64)
        self.exercise()

    def test_drawing_in_64_color(self):
        m = self.start(picovideo=True, cols=VM_64)
        self.exercise()
        self.feed(CSI + b"1;1H" + CSI + b"1;33;44mXY")
        self.assertEqual(m.screen_attrs(), m.shadow_attrs())

    def test_drawing_in_80(self):
        m = self.start(picovideo=True, cols=VM_80)
        self.exercise()
        self.feed(CSI + b"1;1H" + CSI + b"1;33;44mXY")
        self.assertEqual(m.screen_attrs(), m.shadow_attrs())

    def test_cursor_in_80_swaps_ink_and_paper(self):
        m = self.start(picovideo=True, cols=VM_80)
        self.feed(CSI + b"0;31;44m" + b"Q")
        m.run_to(m.sym["vid_cursor_on"])
        m.run_frames(2)
        self.assertEqual(m.var("vid_cursor_shown"), 0xFF)
        r, c = m.cursor()
        shown = m.mem[0x4780 + r * 80 + c]
        stored = m.shadow_attrs()[r][c]
        self.assertEqual(shown, Machine.swap_ink_paper(stored))
        self.assertNotEqual(shown, stored)

    # --- the font ------------------------------------------------------------

    def test_cp437_box_drawing(self):
        m = self.start()
        self.feed(bytes([0xC9, 0xCD, 0xBB]) + b"\r\n" + bytes([0xC8, 0xCD, 0xBC]))
        self.assertEqual(m.shadow_text()[0][:3], "\xc9\xcd\xbb")
        font = m.sym["FONT"]
        cell = bytes(m.mem[Machine.cell_addr(0, 0) + 256 * i] for i in range(8))
        self.assertEqual(cell, m.peek(font + 0xC9 * 8, 8))
        self.assertNotEqual(cell, bytes(8))

    # --- leaving ---------------------------------------------------------------

    def test_exit_from_64_and_80_restores_the_standard_screen(self):
        for cols in (VM_64, VM_80):
            m = self.start(picovideo=True, cols=cols)
            self.assertTrue(m.quit())
            self.assertEqual(m.decr & 0x07, 0)


if __name__ == "__main__":
    unittest.main()
