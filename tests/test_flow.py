"""Flow control in Hayes mode (Q5, firmware #301/#303), on the host machine.

The fakes model what board 1 showed on 2026-10-14/15: Zimodem sends at the
UART's rate, the card's line ring holds 16 KB and loses what laps it, the
card sends XOFF at half full and XON below a quarter once `tpi:modem flow
on` is set, and Zimodem obeys them only with ATF1 *and* a call dialled
with X; after an XOFF it still sends up to its 4 KB serial buffer.
"""

import re
import unittest

try:
    import z80  # noqa: F401
    HAVE_Z80 = True
except ImportError:
    HAVE_Z80 = False

if HAVE_Z80:
    from hostmachine import Machine
from fakes import Fake8251, FakePico, FakeZimodem

VM_64 = 1
LINES = 600


def text(m):
    return "\n".join(line.rstrip() for line in m.shadow_text())


@unittest.skipUnless(HAVE_Z80, "the z80 package isn't installed (make venv)")
class FlowTest(unittest.TestCase):
    def start(self, knows_flow=True):
        self.zm = FakeZimodem()
        self.acia = Fake8251(self.zm)
        self.pico = FakePico(knows_flow=knows_flow)
        self.m = Machine(acia=self.acia, pico=self.pico)
        self.m.mem[self.m.sym["set_cols"]] = VM_64     # the slowest screen
        self.m.run_frames(300)
        return self.m

    def flood(self, dial):
        m = self.m
        m.type(dial + "\n")
        m.run_until(lambda: m.var("hayes_online") == 1, limit=300)
        self.assertEqual(m.var("hayes_online"), 1)
        m.type("bigflood\n")
        m.run_until(lambda: "line %03d" % (LINES - 1) in text(m), limit=20000)
        m.idle()
        return [int(g) for l in m.shadow_text()
                for g in re.findall(r"^line (\d{3}) ", l)]

    def test_start_up_turns_flow_on(self):
        m = self.start()
        self.assertIn("ATF1", self.zm.commands)
        self.assertTrue(self.zm.f1)
        self.assertEqual(self.pico.commands[-1], "tpi:modem flow on")
        self.assertTrue(self.pico.flow)
        self.assertEqual(m.var("flow_on"), 1)

    def test_flood_with_flow_control_loses_nothing(self):
        self.start()
        numbers = self.flood('atdtx"bbs.example:23"')
        self.assertTrue(self.zm.conn_x)
        self.assertGreater(self.acia.xoffs, 0)        # the card had to hold it back
        self.assertEqual(self.acia.rx_lost, 0)
        self.assertEqual(numbers, list(range(numbers[0], LINES)))
        self.assertNotIn(0x13, self.zm.remote.received)    # nothing leaked to the host
        self.assertNotIn(0x11, self.zm.remote.received)

    def test_without_flow_control_the_ring_overflows(self):
        # Firmware without #301: board 1's first 7.2 run (Q5).
        m = self.start(knows_flow=False)
        self.assertEqual(m.var("flow_on"), 0)
        self.assertIn("Modem ready.", text(m))
        self.flood('atdt"bbs.example:23"')
        self.assertGreater(self.acia.rx_lost, 0)

    def test_flow_without_x_leaks_to_the_host(self):
        # ATF1 alone isn't enough (board 1, 2026-10-15): without X on the
        # call, Zimodem passes the card's XOFF/XON to the host as data.
        self.start()
        self.flood('atdt"bbs.example:23"')
        self.assertIn(0x13, self.zm.remote.received)
        self.assertGreater(self.acia.rx_lost, 0)

    def test_quit_turns_flow_off(self):
        m = self.start()
        self.assertTrue(m.quit())
        self.assertEqual(self.pico.commands[-1], "tpi:modem flow off")
        self.assertFalse(self.pico.flow)


if __name__ == "__main__":
    unittest.main()
