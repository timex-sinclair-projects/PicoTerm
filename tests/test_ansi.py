"""M3: the ANSI-BBS, VT52 and TTY emulations, color and the bell, on the
host machine. Bytes are fed in as if the modem received them; the screen
is checked in the shadow (characters and attributes) and in the bitmap.
"""

import unittest

try:
    import z80  # noqa: F401
    HAVE_Z80 = True
except ImportError:
    HAVE_Z80 = False

if HAVE_Z80:
    from hostmachine import Machine
from fakes import Fake8251, FakePico, FakeZimodem

ESC = b"\x1b"
CSI = b"\x1b["

# Spectrum attributes: FLASH 80h, BRIGHT 40h, PAPER x 8, INK
DEFAULT = 0x07
BLACK, BLUE, RED, MAGENTA, GREEN, CYAN, YELLOW, WHITE = range(8)


def attr(ink, paper=BLACK, bright=False, flash=False):
    return ink | paper << 3 | (0x40 if bright else 0) | (0x80 if flash else 0)


@unittest.skipUnless(HAVE_Z80, "the z80 package isn't installed (make venv)")
class EmulationTest(unittest.TestCase):
    EMUL = 2                                    # ANSI

    def setUp(self):
        self.zm = FakeZimodem()
        self.acia = Fake8251(self.zm)
        self.m = Machine(acia=self.acia, pico=FakePico())
        self.m.mem[self.m.sym["set_emul"]] = self.EMUL
        self.m.run_frames(200)
        self.sent = bytearray()
        self.zm.from_terminal = lambda b, f: self.sent.append(b)
        self.feed(CSI + b"2J")                  # a clean screen, cursor home

    def feed(self, data):
        self.zm.to_terminal.extend(data)
        m = self.m
        m.run_until(lambda: not self.zm.to_terminal and self.acia.rx_hold is None,
                    limit=500)
        self.assertTrue(m.idle())

    def row(self, r):
        return self.m.shadow_text()[r]

    def attrs(self, r):
        return self.m.shadow_attrs()[r]

    def cursor(self):
        return self.m.cursor()

    def assert_bitmap_matches(self):
        self.assertEqual(self.m.screen_text(), self.m.shadow_text())
        self.assertEqual(self.m.screen_attrs(), self.m.shadow_attrs())


class AnsiTest(EmulationTest):
    # --- cursor ----------------------------------------------------------

    def test_cup_and_print(self):
        self.feed(CSI + b"5;10Hhi")
        self.assertEqual(self.row(4)[9:11], "hi")
        self.assertEqual(self.cursor(), (4, 11))
        self.feed(CSI + b"H")
        self.assertEqual(self.cursor(), (0, 0))
        self.feed(CSI + b";5f")
        self.assertEqual(self.cursor(), (0, 4))

    def test_cup_clamps(self):
        self.feed(CSI + b"99;99H")
        self.assertEqual(self.cursor(), (23, 31))
        self.feed(CSI + b"300;300H")             # parameters saturate at 255
        self.assertEqual(self.cursor(), (23, 31))

    def test_relative_moves(self):
        self.feed(CSI + b"10;10H" + CSI + b"A")
        self.assertEqual(self.cursor(), (8, 9))
        self.feed(CSI + b"3B")
        self.assertEqual(self.cursor(), (11, 9))
        self.feed(CSI + b"4C")
        self.assertEqual(self.cursor(), (11, 13))
        self.feed(CSI + b"20D")
        self.assertEqual(self.cursor(), (11, 0))
        self.feed(CSI + b"99A")
        self.assertEqual(self.cursor(), (0, 0))
        self.feed(CSI + b"300C")
        self.assertEqual(self.cursor(), (0, 31))
        self.feed(CSI + b"5G")
        self.assertEqual(self.cursor(), (0, 4))
        self.feed(CSI + b"7d")
        self.assertEqual(self.cursor(), (6, 4))
        self.feed(CSI + b"2E")
        self.assertEqual(self.cursor(), (8, 0))
        self.feed(CSI + b"5;5H" + CSI + b"F")
        self.assertEqual(self.cursor(), (3, 0))

    def test_save_and_restore(self):
        self.feed(CSI + b"3;4H" + CSI + b"31m" + ESC + b"7")
        self.feed(CSI + b"0m" + CSI + b"20;20H" + ESC + b"8X")
        self.assertEqual(self.cursor(), (2, 4))
        self.assertEqual(self.attrs(2)[3], attr(RED))
        self.feed(CSI + b"0m" + CSI + b"10;2H" + CSI + b"s" + CSI + b"H" + CSI + b"uY")
        self.assertEqual(self.row(9)[1], "Y")

    # --- erasing -----------------------------------------------------------

    def fill(self):
        for r in range(24):
            self.feed(CSI + b"%d;1H" % (r + 1) + bytes([65 + r]) * 32)

    def test_ed_below_above_all(self):
        self.fill()
        self.feed(CSI + b"5;5H" + CSI + b"J")
        self.assertEqual(self.row(4), "EEEE" + " " * 28)
        self.assertEqual(self.row(5).strip(), "")
        self.assertEqual(self.row(3), "D" * 32)
        self.fill()
        self.feed(CSI + b"5;5H" + CSI + b"1J")
        self.assertEqual(self.row(4), " " * 5 + "E" * 27)
        self.assertEqual(self.row(3).strip(), "")
        self.assertEqual(self.row(5), "F" * 32)
        self.fill()
        self.feed(CSI + b"5;5H" + CSI + b"2J")
        self.assertTrue(all(not r.strip() for r in self.m.shadow_text()))
        self.assertEqual(self.cursor(), (0, 0))      # ANSI.SYS: home
        self.assert_bitmap_matches()

    def test_el(self):
        self.fill()
        self.feed(CSI + b"3;10H" + CSI + b"K")
        self.assertEqual(self.row(2), "C" * 9 + " " * 23)
        self.feed(CSI + b"4;10H" + CSI + b"1K")
        self.assertEqual(self.row(3), " " * 10 + "D" * 22)
        self.feed(CSI + b"5;10H" + CSI + b"2K")
        self.assertEqual(self.row(4), " " * 32)
        self.assertEqual(self.cursor(), (4, 9))

    def test_erase_uses_the_background(self):
        self.feed(CSI + b"44m" + CSI + b"2J")
        self.assertTrue(all(a == attr(WHITE, BLUE) for r in self.m.shadow_attrs() for a in r))
        self.assert_bitmap_matches()

    # --- editing -----------------------------------------------------------

    def test_insert_and_delete_characters(self):
        self.feed(CSI + b"1;1Habcdefgh" + CSI + b"1;3H" + CSI + b"2@")
        self.assertEqual(self.row(0)[:10], "ab  cdefgh")
        self.feed(CSI + b"1;3H" + CSI + b"3P")
        self.assertEqual(self.row(0)[:10], "abdefgh   ")
        self.feed(CSI + b"1;2H" + CSI + b"2X")
        self.assertEqual(self.row(0)[:10], "a  efgh   ")
        self.assertEqual(self.cursor(), (0, 1))
        self.feed(CSI + b"2;1H" + b"x" * 32 + CSI + b"2;30H" + CSI + b"9@")
        self.assertEqual(self.row(1), "x" * 29 + "   ")
        self.assert_bitmap_matches()

    def test_insert_and_delete_lines(self):
        self.fill()
        self.feed(CSI + b"3;5H" + CSI + b"2L")
        self.assertEqual([self.row(r)[0] for r in range(6)], ["A", "B", " ", " ", "C", "D"])
        self.assertEqual(self.row(23)[0], "V")       # W and X pushed off
        self.assertEqual(self.cursor(), (2, 0))
        self.feed(CSI + b"1;1H" + CSI + b"M")
        self.assertEqual([self.row(r)[0] for r in range(4)], ["B", " ", " ", "C"])
        self.assertEqual(self.row(23).strip(), "")
        self.assert_bitmap_matches()

    def test_scrolling_region(self):
        self.fill()
        self.feed(CSI + b"5;10r")                 # rows 5-10 (4-9 here)
        self.assertEqual(self.cursor(), (0, 0))
        self.feed(CSI + b"10;1H\n")              # LF at the bottom margin
        self.assertEqual([self.row(r)[0] for r in range(3, 11)],
                         ["D", "F", "G", "H", "I", "J", " ", "K"])
        self.feed(CSI + b"5;1H" + ESC + b"M")    # RI at the top margin
        self.assertEqual([self.row(r)[0] for r in range(3, 11)],
                         ["D", " ", "F", "G", "H", "I", "J", "K"])
        self.feed(CSI + b"2S")
        self.assertEqual([self.row(r)[0] for r in range(4, 10)],
                         ["G", "H", "I", "J", " ", " "])
        self.feed(CSI + b"T")
        self.assertEqual([self.row(r)[0] for r in range(4, 10)],
                         [" ", "G", "H", "I", "J", " "])
        self.feed(CSI + b"r" + CSI + b"24;1H\n")  # whole screen again
        self.assertEqual(self.row(0)[0], "B")
        self.assert_bitmap_matches()

    def test_cursor_stops_at_margins(self):
        self.feed(CSI + b"5;10r" + CSI + b"7;1H" + CSI + b"20A")
        self.assertEqual(self.cursor(), (4, 0))
        self.feed(CSI + b"20B")
        self.assertEqual(self.cursor(), (9, 0))

    # --- color --------------------------------------------------------------

    def test_sgr(self):
        self.feed(CSI + b"1;31;44mA" + CSI + b"0mB" + CSI + b"7mC" + CSI + b"27;32mD"
                  + CSI + b"mE" + CSI + b"5mF" + CSI + b"25;93mG" + CSI + b"22;39mH"
                  + CSI + b"103mI" + CSI + b"49mJ")
        self.assertEqual(self.row(0)[:10], "ABCDEFGHIJ")
        self.assertEqual(self.attrs(0)[:10], [
            attr(RED, BLUE, bright=True),
            DEFAULT,
            attr(BLACK, WHITE),
            attr(GREEN),
            DEFAULT,
            attr(WHITE, flash=True),
            attr(YELLOW, bright=True),
            attr(WHITE),
            attr(WHITE, YELLOW),
            attr(WHITE),
        ])
        self.assert_bitmap_matches()

    def test_sgr_extended_colors(self):
        self.feed(CSI + b"38;5;1mA" + CSI + b"38;5;12mB" + CSI + b"0;48;5;2mC"
                  + CSI + b"0;38;2;10;20;30;35mD" + CSI + b"0;38;5;200mE")
        self.assertEqual(self.attrs(0)[:5], [
            attr(RED), attr(BLUE, bright=True), attr(WHITE, GREEN),
            attr(MAGENTA), DEFAULT])

    def test_blink_setting(self):
        self.m.mem[self.m.sym["set_blink"]] = 0
        self.feed(CSI + b"5mX")
        self.assertEqual(self.attrs(0)[0], DEFAULT)

    # --- modes and replies ---------------------------------------------------

    def test_cursor_position_report(self):
        self.feed(CSI + b"12;20H" + CSI + b"6n")
        self.assertEqual(bytes(self.sent), b"\x1b[12;20R")
        self.sent.clear()
        self.feed(CSI + b"255;255H" + CSI + b"6n")
        self.assertEqual(bytes(self.sent), b"\x1b[24;32R")   # the screen size
        self.sent.clear()
        self.feed(CSI + b"5n")
        self.assertEqual(bytes(self.sent), b"\x1b[0n")

    def test_device_attributes(self):
        self.feed(CSI + b"c")
        self.assertEqual(bytes(self.sent), b"\x1b[?1;0c")
        self.sent.clear()
        self.feed(CSI + b">c")                   # secondary DA: not answered
        self.assertEqual(bytes(self.sent), b"")

    def test_cursor_visibility(self):
        self.feed(CSI + b"?25l")
        self.assertEqual(self.m.var("term_cursor"), 0)
        self.m.run_frames(80)
        self.assertEqual(self.m.var("vid_cursor_shown"), 0)
        self.feed(CSI + b"?25h")
        self.assertEqual(self.m.var("term_cursor"), 1)

    def test_autowrap_off(self):
        self.feed(CSI + b"?7l" + b"x" * 31 + b"yz")
        self.assertEqual(self.row(0), "x" * 31 + "z")
        self.assertEqual(self.row(1).strip(), "")
        self.feed(CSI + b"?7h" + CSI + b"3;1H" + b"x" * 32 + b"y")
        self.assertEqual(self.row(3)[0], "y")

    def test_deferred_wrap_then_cr(self):
        self.feed(b"x" * 32 + b"\r\n")
        self.assertEqual(self.cursor(), (1, 0))  # one line, not two

    # --- things to ignore ----------------------------------------------------

    def test_unknown_sequences_are_swallowed(self):
        self.feed(CSI + b"?1049h" + CSI + b">0c" + CSI + b"1$p"
                  + ESC + b"]0;a title\x07" + ESC + b"]2;other" + ESC + b"\\"
                  + ESC + b"(B" + ESC + b")0" + CSI + b"4;1;2:3m"
                  + CSI + b"1;2;3;4;5;6;7;8;9;10;11;12m" + b"ok")
        self.assertEqual(self.row(0).rstrip(), "ok")
        self.assertEqual(bytes(self.sent), b"")

    def test_can_aborts_and_controls_act_inside(self):
        self.feed(CSI + b"31\x18X")
        self.assertEqual(self.row(0)[0], "X")
        self.assertEqual(self.attrs(0)[0], DEFAULT)
        self.feed(CSI + b"3;5H" + CSI + b"2\rC")   # CR acts, then CUF 2
        self.assertEqual(self.cursor(), (2, 2))

    def test_reset(self):
        self.feed(CSI + b"5;10r" + CSI + b"31mabc" + ESC + b"c")
        self.assertEqual(self.cursor(), (0, 0))
        self.assertEqual(self.m.var("term_top"), 0)
        self.assertEqual(self.m.var("term_bot"), 23)
        self.assertEqual(self.m.var("cur_attr"), DEFAULT)
        self.assertTrue(all(not r.strip() for r in self.m.shadow_text()))

    def test_form_feed_clears_and_homes(self):
        self.feed(b"abc\x0cX")
        self.assertEqual(self.row(0)[:2], "X ")
        self.assertEqual(self.cursor(), (0, 1))

    # --- the bell and the keyboard -------------------------------------------

    def test_bell(self):
        self.m.ay_log.clear()
        self.feed(b"\x07")
        self.assertIn((8, 0x0F), self.m.ay_log)     # on
        self.assertEqual(self.m.ay[0], 110)         # 1 kHz
        self.assertEqual(self.m.ay[7] & 0xC0, 0)    # AY ports stay inputs
        self.m.run_frames(10)
        self.assertEqual(self.m.ay[8], 0)           # and off again

    def test_bell_setting(self):
        self.m.mem[self.m.sym["set_bell"]] = 0
        self.m.ay_log.clear()
        self.feed(b"\x07")
        self.assertEqual(self.m.ay_log, [])

    def test_arrow_keys_send_ansi(self):
        self.m.press("7", "CAPS")
        self.assertEqual(bytes(self.sent), b"\x1b[A")

    def test_termtype_set_at_start_up(self):
        self.assertIn('AT&S"41=ANSI"', self.zm.commands)


class Vt52Test(EmulationTest):
    EMUL = 1

    def setUp(self):
        super().setUp()
        self.feed(ESC + b"H" + ESC + b"J")

    def test_direct_cursor_address(self):
        self.feed(ESC + b"Y" + bytes([32 + 5, 32 + 10]) + b"hi")
        self.assertEqual(self.row(5)[10:12], "hi")

    def test_moves_and_home(self):
        self.feed(ESC + b"Y" + bytes([32 + 5, 32 + 5]))
        self.feed(ESC + b"A" + ESC + b"A" + ESC + b"C" + ESC + b"B" + ESC + b"D" + ESC + b"D")
        self.assertEqual(self.cursor(), (4, 4))
        self.feed(ESC + b"H")
        self.assertEqual(self.cursor(), (0, 0))

    def test_erase(self):
        for r in range(3):
            self.feed(ESC + b"Y" + bytes([32 + r, 32]) + b"z" * 32)
        self.feed(ESC + b"Y" + bytes([32 + 1, 32 + 4]) + ESC + b"K")
        self.assertEqual(self.row(1), "zzzz" + " " * 28)
        self.assertEqual(self.row(2), "z" * 32)
        self.feed(ESC + b"J")
        self.assertEqual(self.row(2).strip(), "")
        self.assertEqual(self.row(0), "z" * 32)

    def test_reverse_line_feed_scrolls_at_the_top(self):
        self.feed(b"top" + ESC + b"H" + ESC + b"I")
        self.assertEqual(self.row(1)[:3], "top")
        self.assertEqual(self.row(0).strip(), "")

    def test_identify(self):
        self.feed(ESC + b"Z")
        self.assertEqual(bytes(self.sent), b"\x1b/Z")

    def test_ignored_and_ansi_not_understood(self):
        self.feed(ESC + b"F" + ESC + b"G" + ESC + b"=" + ESC + b">" + b"ok")
        self.assertEqual(self.row(0)[:2], "ok")
        self.feed(ESC + b"H" + CSI + b"2J")      # ANSI is just text here
        self.assertEqual(self.row(0)[:2], "2J")

    def test_arrow_keys_send_vt52(self):
        self.m.press("7", "CAPS")
        self.m.press("8", "CAPS")
        self.assertEqual(bytes(self.sent), b"\x1bA\x1bC")

    def test_termtype(self):
        self.assertIn('AT&S"41=VT52"', self.zm.commands)


class TtyTest(EmulationTest):
    EMUL = 0

    def setUp(self):
        super().setUp()
        self.feed(b"\x0c")

    def test_escape_is_ignored(self):
        self.feed(b"a" + CSI + b"31mb")
        self.assertEqual(self.row(0).rstrip(), "a[31mb")
        self.assertEqual(self.attrs(0)[0], DEFAULT)

    def test_termtype(self):
        self.assertIn('AT&S"41=DUMB"', self.zm.commands)


del EmulationTest

if __name__ == "__main__":
    unittest.main()
