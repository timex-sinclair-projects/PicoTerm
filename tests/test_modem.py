"""M2: the 8251 driver, start-up, the plain terminal and hang-up, run on the
host machine (tests/hostmachine.py) against fake devices (tests/fakes.py).

Skipped if the `z80` package isn't installed (make venv).
"""

import unittest

try:
    import z80  # noqa: F401
    HAVE_Z80 = True
except ImportError:
    HAVE_Z80 = False

if HAVE_Z80:
    from hostmachine import Machine
from fakes import EchoBBS, Fake8251, FakePico, FakeZimodem

RESET = [0x00, 0x00, 0x00, 0x40, 0x4F, 0x37]


def text(m):
    return "\n".join(line.rstrip() for line in m.shadow_text())


@unittest.skipUnless(HAVE_Z80, "the z80 package isn't installed (make venv)")
class ModemTest(unittest.TestCase):
    def start(self, rom_version=0x23, frames=200, **acia_args):
        self.zm = FakeZimodem()
        self.acia = Fake8251(self.zm, **acia_args)
        self.pico = FakePico()
        self.m = Machine(acia=self.acia, pico=self.pico, rom_version=rom_version)
        self.m.run_frames(frames)
        return self.m

    def assert_screen_is_shadow(self):
        self.assertEqual(self.m.screen_text(), self.m.shadow_text())

    # --- start-up ----------------------------------------------------------

    def test_startup_on_the_tspico(self):
        m = self.start()
        self.assertEqual(self.pico.commands,
                         ["tpi:chopen r picoterm.cfg", "tpi:modem hayes", "tpi:modem flow on"])
        self.assertEqual(self.pico.modem_mode, "hayes")
        self.assertTrue(self.pico.flow)
        self.assertEqual(self.acia.ctrl_log[:6], RESET)
        self.assertEqual(self.zm.commands, ["AT", "ATE1V1X1Q0", 'AT&S"41=ANSI"', "ATF1"])
        self.assertIn("Modem ready.", text(m))
        self.assert_screen_is_shadow()

    def test_flow_control_zimodem_first(self):
        # Zimodem's ATF1 before the card's XOFF can reach it: with F0 Zimodem
        # would pass the card's XOFF and XON on to the host as data.
        self.start()
        self.assertEqual(self.zm.commands[-1], "ATF1")
        self.assertEqual(self.pico.commands[-1], "tpi:modem flow on")

    def test_firmware_without_flow(self):
        # A card from before firmware #301 refuses flow on: Modem ready. still
        # gets a line of its own.
        self.zm = FakeZimodem()
        self.acia = Fake8251(self.zm)
        self.pico = FakePico(knows_flow=False, verbose=True)
        m = self.m = Machine(acia=self.acia, pico=self.pico)
        m.run_frames(200)
        self.assertEqual(self.pico.commands[-1], "tpi:modem flow on")
        self.assertFalse(self.pico.flow)
        self.assertIn("\nModem ready.", text(m))

    def test_pico_preheader_carries_rom_version(self):
        self.start()
        pre = self.pico.prehead[0]
        self.assertEqual(pre[:3], [ord("B"), 0, 0x23])
        x = 0
        for b in pre[:9]:
            x ^= b
        self.assertEqual(pre[9], x)

    def test_startup_on_a_stock_rom_skips_the_pico(self):
        m = self.start(rom_version=0xFF)
        self.assertEqual(self.pico.commands, [])
        self.assertIn("Modem ready.", text(m))

    def test_firmware_without_tpi_modem(self):
        self.zm = FakeZimodem()
        self.acia = Fake8251(self.zm)
        self.pico = FakePico(knows_modem=False)
        m = self.m = Machine(acia=self.acia, pico=self.pico)
        m.run_frames(200)
        self.assertEqual(self.pico.commands, ["tpi:chopen r picoterm.cfg", "tpi:modem hayes"])
        self.assertNotIn("ATF1", self.zm.commands)          # no flow control asked for
        self.assertIn("Unrecognized command", text(m))
        self.assertIn("This TS-Pico has no tpi:modem.", text(m))
        self.assertIn("Modem ready.", text(m))

    def test_waits_for_the_esp32_to_start(self):
        m = self.start(boot_frames=150, frames=400)   # 3 s
        self.assertIn("Modem ready.", text(m))

    def test_no_modem_at_all(self):
        m = self.start(never_ready=True, frames=400)
        self.assertIn("No modem", text(m))
        # Keys still work, and a send gives up rather than hanging.
        before = m.frame
        m.type("x")
        m.type("y")
        self.assertLess(m.frame - before, 100)
        self.assertTrue(m.quit())

    def slow_zimodem(self, deaf_frames, frames):
        self.zm = FakeZimodem(deaf_frames=deaf_frames)
        self.acia = Fake8251(self.zm)
        self.pico = FakePico()
        self.m = Machine(acia=self.acia, pico=self.pico)
        self.m.run_frames(frames)
        return self.m

    def test_zimodem_slower_than_the_line(self):
        # Hardware, 2026-10-14: the card lets bytes through 2 s after the
        # first 8251 write, and Zimodem (joining WiFi) can take longer.
        # PicoTerm keeps asking, once a second, for about 12 s.
        for seconds in (2.5, 5, 10):
            m = self.slow_zimodem(int(seconds * 50), 800)
            self.assertIn("Modem ready.", text(m), f"Zimodem ready after {seconds} s")
            self.assertIn(b"AT\r", bytes(self.zm.lost))     # the early tries were lost
            self.assertIn("ATE1V1X1Q0", self.zm.commands)

    def test_queued_ats_are_drained_out_of_sight(self):
        # Hardware, cold start: the card queues what's sent before line-up and
        # delivers it after, so several ATs reach Zimodem at once. PicoTerm
        # goes on at the first OK and keeps the rest of the replies off screen.
        self.zm = FakeZimodem(deaf_frames=250, queue_early=True)
        self.acia = Fake8251(self.zm)
        self.m = Machine(acia=self.acia, pico=FakePico())
        self.m.run_frames(500)
        t = text(self.m)
        self.assertIn("Modem ready.", t)
        self.assertGreater(self.zm.commands.count("AT"), 1)    # several got through
        self.assertEqual(t.count("\nAT\n"), 1)                 # one shown
        self.assertEqual(t.count("OK"), 4)                     # AT, init, termtype, ATF1
        cmds = self.zm.commands
        self.assertEqual(cmds[cmds.index("ATE1V1X1Q0") - 1], "AT")

    def test_zimodem_never_answers(self):
        m = self.slow_zimodem(10 ** 6, 900)
        self.assertIn("No answer from the modem.", text(m))
        tries = bytes(self.zm.lost).count(b"AT\r")
        self.assertGreaterEqual(tries, 11)
        self.assertLessEqual(tries, 13)

    def test_no_card_floating_bus(self):
        m = self.start(floating=True, frames=400)
        self.assertIn("No modem", text(m))
        self.assertEqual(m.peek16(m.sym["rx_head"]), 0)  # nothing taken in
        self.assertNotIn("?", "".join(m.screen_text()))   # no FFh boxes

    def test_local_echo(self):
        m = self.start()
        m.mem[m.sym["set_echo"]] = 1
        self.zm.echo = False
        m.type("ab")
        m.press("0", "CAPS")                         # DELETE
        m.type("c\n")
        m.run_frames(10)
        self.assertEqual(self.zm.commands[-1], "ac")
        self.assertIn("\nac\n", text(m))

    def test_no_answer_from_zimodem(self):
        self.zm = FakeZimodem()
        self.zm.process = lambda text: None          # deaf
        self.acia = Fake8251(self.zm)
        m = self.m = Machine(acia=self.acia, pico=FakePico())
        m.run_frames(900)                            # 12 tries, about 14 s
        self.assertIn("No answer from the modem.", text(m))

    # --- the terminal --------------------------------------------------------

    def test_typing_goes_to_the_modem_and_its_echo_comes_back(self):
        m = self.start()
        m.type("ati\n")
        m.run_frames(20)
        self.assertEqual(self.zm.commands[-1], "ati")
        self.assertIn("ati\nZimodem (fake)\nOK", text(m))
        self.assert_screen_is_shadow()

    def test_special_keys(self):
        m = self.start()
        sent = []
        self.zm.from_terminal = lambda b, f: sent.append(b)
        m.press("7", "CAPS")                         # up
        m.press("6", "CAPS")                         # down
        m.press("5", "CAPS")                         # left
        m.press("8", "CAPS")                         # right
        m.press("0", "CAPS")                         # DELETE
        m.press("1", "CAPS")                         # EDIT: Esc
        m.press("ENTER")
        self.assertEqual(bytes(sent), b"\x1b[A\x1b[B\x1b[D\x1b[C\x08\x1b\r")

    def test_dial_session_and_remote_hang_up(self):
        m = self.start()
        m.type('atdt"bbs.example:23"\n')
        m.run_frames(20)
        self.assertEqual(m.var("hayes_online"), 1)
        self.assertIn("CONNECT 1", text(m))
        self.assertIn("Welcome to the test BBS", text(m))
        m.type("hello\n")
        m.run_frames(20)
        self.assertEqual(bytes(self.zm.remote.received), b"hello\r")
        self.assertIn("hello", text(m).split("Welcome to the test BBS")[1])
        m.type("bye\n")
        m.run_frames(20)
        self.assertEqual(m.var("hayes_online"), 0)
        self.assertIn("NO CARRIER", text(m))

    def test_no_answer_result(self):
        m = self.start()
        m.type('atdt"nowhere:23"\n')
        m.run_frames(20)
        self.assertIn("NO ANSWER", text(m))
        self.assertEqual(m.var("hayes_online"), 0)

    def test_quit_while_online_hangs_up_then_exits(self):
        m = self.start()
        m.type('atdt"bbs.example:23"\n')
        m.run_frames(20)
        self.assertEqual(m.var("hayes_online"), 1)
        self.assertTrue(m.quit())
        self.assertEqual(self.zm.escapes, 1)         # the guard times held
        self.assertEqual(self.zm.commands[-1], "ATH")
        self.assertIsNone(self.zm.remote)
        self.assertEqual(self.acia.ctrl_log[-1], 0x15)   # left idle, DTR off

    def test_quit_offline_exits_at_once(self):
        m = self.start()
        self.assertTrue(m.quit(limit=20))
        self.assertEqual(self.zm.escapes, 0)
        self.assertEqual(self.pico.commands[-1], "tpi:modem flow off")   # the card's side
        self.assertFalse(self.pico.flow)

    # --- receiving -----------------------------------------------------------

    def test_receive_error_is_reset_and_the_byte_kept(self):
        m = self.start()
        self.acia.inject_errors.extend([0x10])      # OE on the next byte
        m.type("x")
        m.run_frames(5)
        self.assertIn(0x37, self.acia.ctrl_log[6:])  # ER command after the reset
        self.assertEqual(m.var("acia_errors"), 1)
        self.assertTrue(text(m).rstrip().endswith("x"))

    def test_flood_arrives_whole_and_in_order(self):
        m = self.start()
        m.type('atdt"bbs.example:23"\n')
        m.run_frames(20)
        m.type("flood\n")
        m.run_until(lambda: "line 99" in text(m), limit=2000)
        m.run_frames(50)                # let the last line finish
        lines = [l for l in m.shadow_text() if l.startswith("line ")]
        numbers = [int(l[5:7]) for l in lines]
        self.assertEqual(numbers, list(range(numbers[0], 100)))
        self.assertGreater(len(numbers), 10)
        self.assertTrue(all(l.rstrip() == "line %02d " % n + "x" * 24
                            for l, n in zip(lines, numbers)))
        self.assert_screen_is_shadow()

    def test_full_ring_holds_back_and_loses_nothing(self):
        m = self.start()
        get = m.sym["rx_get"]
        saved = m.peek(get, 2)
        m.stop_at(m.sym["main_loop"])               # not inside rx_get
        m.mem[get:get + 2] = b"\xb7\xc9"           # OR A / RET: never a byte
        data = b"".join(b"%04d\r\n" % n for n in range(500))   # 3000 bytes
        self.zm.to_terminal.extend(data)
        m.run_frames(100)
        head, tail = m.peek16(m.sym["rx_head"]), m.peek16(m.sym["rx_tail"])
        self.assertEqual((head - tail) & 2047, 2047)                # full
        held = len(self.zm.to_terminal) + (self.acia.rx_hold is not None)
        self.assertEqual(held, 3000 - 2047)                          # still waiting
        m.mem[get:get + 2] = saved
        m.run_until(lambda: "0499" in text(m), limit=2000)
        m.run_frames(20)
        lines = [l.strip() for l in m.shadow_text() if l.strip()]
        self.assertEqual(lines, ["%04d" % n for n in range(500 - len(lines), 500)])

    def test_paced_at_300_baud(self):
        m = self.start(cps=30)
        m.type('atdt"bbs.example:23"\n')
        m.run_until(lambda: "Welcome" in text(m), limit=500)
        start = m.frame
        m.run_until(lambda: "test BBS" in text(m), limit=500)
        # 25 characters of greeting at 30 a second: most of a second
        self.assertGreater(m.frame - start, 10)


if __name__ == "__main__":
    unittest.main()
