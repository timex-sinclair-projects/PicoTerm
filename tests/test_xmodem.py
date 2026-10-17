"""M6: XMODEM downloads into memory, saved to the TS-Pico as an f: CODE
file, on the host machine. The BBS is fakes.XmodemSender behind the fake
Zimodem; the fake TS-Pico checks the SAVE blocks and keeps the file."""

import os
import unittest

try:
    import z80  # noqa: F401
    HAVE_Z80 = True
except ImportError:
    HAVE_Z80 = False

if HAVE_Z80:
    from hostmachine import Machine
from fakes import Fake8251, FakePico, FakeZimodem, XmodemSender

VM_32, VM_64 = 0, 1


def sample(n, seed=1):
    """n bytes of every value, 17h (TAB in a channel) and 1Ah included."""
    out = bytearray()
    x = seed
    while len(out) < n:
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out.append((x >> 16) & 0xFF)
    return bytes(out)


@unittest.skipUnless(HAVE_Z80, "the z80 package isn't installed (make venv)")
class XmodemTest(unittest.TestCase):
    def start(self, sender=None, files=None, rom_version=0x23, cols=VM_32, connect=True):
        self.sender = sender
        hosts = {"files.example:23": (lambda: self.sender)}
        self.zm = FakeZimodem(hosts=hosts)
        self.acia = Fake8251(self.zm)
        self.pico = FakePico(files=files)
        self.m = Machine(acia=self.acia, pico=self.pico, rom_version=rom_version)
        self.m.mem[self.m.sym["set_cols"]] = cols
        self.m.run_frames(200)
        if connect:
            self.m.type('atdt"files.example:23"\n')
            self.m.run_until(lambda: self.m.var("hayes_online") == 1, limit=200)
        self.m.settle()
        return self.m

    def key(self, k, *mods):
        self.m.press(k, *mods)
        self.assertTrue(self.m.settle(limit=200))

    def screen(self):
        return "\n".join(self.m.screen_text())

    def download(self, name=None, strip=False, replace=None):
        """BREAK, X, the name, ENTER; then answer the questions."""
        m = self.m
        self.key("SPACE", "CAPS")
        self.key("x")
        if name is not None:
            for _ in range(20):
                self.key("0", "CAPS")
            m.type(name)
        self.key("ENTER")
        if replace is not None:
            self.assertIn("Replace that file?", self.screen())
            self.key("y" if replace else "n")
            if not replace:
                return
        # the transfer runs until a question or a message
        m.run_until(lambda: "Strip" in self.screen() or "." in self.screen().split("Download")[-1]
                    and self.m.var("rx_mode") != 0, limit=4000)
        m.run_until(lambda: any(w in self.screen() for w in
                                ("Strip", "canceled", "Canceled", "Too big", "didn't start")),
                    limit=4000)
        if "Strip" in self.screen():
            self.key("y" if strip else "n")
            m.run_until(lambda: "Saved" in self.screen() or "Couldn't" in self.screen(),
                        limit=2000)

    def saved(self, name="download.bin"):
        data = self.pico.files[name]
        self.assertEqual(data[:8], b"PLUS3DOS")
        self.assertEqual(data[15], 3)                  # CODE
        return data[128:]

    # --- good transfers ------------------------------------------------------

    def test_crc_128(self):
        data = sample(3000)
        self.start(XmodemSender(data))
        self.download()
        self.assertIn("Saved: 3072 bytes.", self.screen())
        self.assertEqual(self.saved(), data + b"\x1a" * 72)
        self.assertEqual(self.sender.state, "done")
        self.assertTrue(self.sender.crc)

    def test_strip_padding(self):
        data = sample(1000).rstrip(b"\x1a") + b"end"
        self.start(XmodemSender(data))
        self.download(strip=True)
        self.assertEqual(self.saved(), data)

    def test_1k_blocks(self):
        data = sample(5000)
        self.start(XmodemSender(data, block=1024))
        self.download()
        self.assertEqual(self.saved()[:5000], data)
        self.assertEqual(len(self.saved()), 5120)

    def test_checksum_fallback(self):
        data = sample(700)
        self.start(XmodemSender(data, checksum_only=True))
        self.download()
        self.assertFalse(self.sender.crc)
        self.assertEqual(self.saved()[:700], data)

    def test_faults_are_recovered(self):
        data = sample(2000)
        sender = XmodemSender(data, corrupt={2}, cut={5}, repeat={7})
        self.start(sender)
        self.download()
        self.assertEqual(self.saved()[:2000], data)
        self.assertEqual(sender.naks, 2)              # the damaged and the cut block
        self.assertEqual(sender.sent_blocks.count(7), 2)   # sent twice, kept once
        self.assertEqual(len(self.saved()), 2048)

    def test_largest_that_fits(self):
        data = sample(6912)
        self.start(XmodemSender(data, block=1024))    # 6 x 1K + ... = 7168: too big
        self.download()
        self.assertIn("Too big for memory", self.screen())
        self.start(XmodemSender(data))                 # 54 x 128 = 6912 exactly
        self.download()
        self.assertEqual(self.saved(), data)

    def test_the_tspico_gets_a_named_file_and_replace_asks(self):
        files = {"old.bin": b"x"}
        data = sample(300)
        self.start(XmodemSender(data), files=files)
        self.download(name="old.bin", replace=False)
        self.assertEqual(self.pico.files["old.bin"], b"x")
        self.start(XmodemSender(data), files={"old.bin": b"x"})
        self.download(name="old.bin", replace=True)
        self.assertEqual(self.saved("old.bin")[:300], data)
        self.assertEqual(self.pico.keys_seen, [ord("Y")])   # the Pico's own question

    def test_64_columns_drops_to_32_and_back(self):
        data = sample(500)
        m = self.start(XmodemSender(data), cols=VM_64)
        self.download()
        self.assertEqual(self.saved()[:500], data)
        self.key("ENTER")                              # the message
        self.assertEqual(m.cols(), 64)

    # --- failures ------------------------------------------------------------

    def test_sender_cancels(self):
        self.start(XmodemSender(sample(2000), cancel_at=3))
        self.download()
        self.assertIn("The sender canceled.", self.screen())
        self.assertNotIn("download.bin", self.pico.files)

    def test_break_cancels(self):
        m = self.start(XmodemSender(sample(6000)))
        self.key("SPACE", "CAPS")
        self.key("x")
        self.key("ENTER")
        m.run_frames(3)
        m.press("SPACE", "CAPS")
        m.run_until(lambda: "Canceled." in self.screen(), limit=500)
        self.assertIn("Canceled.", self.screen())
        self.assertTrue(self.sender.received.endswith(b"\x18" * 5))

    def test_too_many_errors(self):
        sender = XmodemSender(sample(500), corrupt=set())
        # always a bad CRC (128 zeros have a CRC of 0000h, not 1234h)
        sender.frame = lambda i: bytearray(b"\x01\x01\xfe" + b"\x00" * 128 + b"\x12\x34")
        self.start(sender)
        self.download()
        self.assertIn("Too many errors", self.screen())
        self.assertTrue(sender.received.endswith(b"\x18" * 5))

    def test_sender_never_starts(self):
        self.start(XmodemSender(b"x", silent=True))
        self.download()
        self.assertIn("didn't start", self.screen())
        r = bytes(self.sender.received)
        self.assertEqual(r.count(b"C"), 3)             # three Cs, then NAKs
        self.assertEqual(r.count(b"\x15"), 7)

    def test_offline_and_no_tspico(self):
        self.start(connect=False)
        self.key("SPACE", "CAPS")
        self.key("x")
        self.assertIn("Connect to a BBS first.", self.screen())
        self.start(XmodemSender(b"x"), rom_version=0xFF)
        self.key("SPACE", "CAPS")
        self.key("x")
        self.assertIn("No TS-Pico", self.screen())


if __name__ == "__main__":
    unittest.main()
