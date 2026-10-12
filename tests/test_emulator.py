"""Run picoterm.tap in a headless ZEsarUX TS-2068. Skipped without ZEsarUX."""

import os
import time
import unittest

from zrcp import Emulator, find_zesarux, symbols

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAP = os.path.join(ROOT, "build", "picoterm.tap")
SYM = os.path.join(ROOT, "build", "picoterm.sym")


@unittest.skipUnless(find_zesarux(), "ZEsarUX not installed")
class EmulatorTest(unittest.TestCase):
    def test_m0_start_tick_and_exit(self):
        sym = symbols(SYM)
        with Emulator() as emu:
            emu.wait_for_text("Sinclair")           # the 2068 has started
            emu.load(TAP)
            screen = emu.wait_for_text("PicoTerm M0")
            self.assertIn("Press a key", screen)

            # IM2 tick: 50 or 60 a second, depending on the machine.
            a = emu.peek16(sym["ticks"])
            time.sleep(1.0)
            b = emu.peek16(sym["ticks"])
            self.assertGreater((b - a) & 0xFFFF, 30)

            # A key returns to BASIC cleanly.
            emu.keys(" ")
            screen = emu.wait_for_text("0 OK")
            regs = emu.cmd("get-registers")
            self.assertIn("IM1", regs)
            self.assertIn("IY=5c3a", regs)


if __name__ == "__main__":
    unittest.main()
