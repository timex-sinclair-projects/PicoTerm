"""Check build/picoterm.tap: block structure, checksums and the loader."""

import os
import struct
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAP = os.path.join(ROOT, "build", "picoterm.tap")
BIN = os.path.join(ROOT, "build", "picoterm.bin")
ORG = 0x8800


def blocks(data):
    out, i = [], 0
    while i < len(data):
        (n,) = struct.unpack_from("<H", data, i)
        out.append(data[i + 2:i + 2 + n])
        i += 2 + n
    return out


class TapTest(unittest.TestCase):
    def setUp(self):
        with open(TAP, "rb") as f:
            self.blocks = blocks(f.read())

    def test_four_blocks_with_good_checksums(self):
        self.assertEqual(len(self.blocks), 4)
        for b in self.blocks:
            x = 0
            for byte in b:
                x ^= byte
            self.assertEqual(x, 0, "XOR over flag, data and checksum must be 0")

    def test_loader(self):
        hdr, prog = self.blocks[0], self.blocks[1]
        self.assertEqual(hdr[0], 0x00)            # header flag
        self.assertEqual(hdr[1], 0)               # program
        length, autostart, prog_len = struct.unpack_from("<HHH", hdr, 12)
        self.assertEqual(autostart, 10)
        self.assertEqual(length, prog_len)
        body = prog[1:-1]
        self.assertEqual(len(body), length)
        self.assertEqual(body[:2], b"\x00\x0a")  # line 10
        self.assertIn(b"\xfd34815\x0e\x00\x00\xff\x87\x00", body)       # CLEAR 34815
        self.assertIn(b"\xf9\xc034816\x0e\x00\x00\x00\x88\x00", body)   # RANDOMIZE USR 34816
        self.assertEqual(body[-1], 0x0D)

    def test_code(self):
        hdr, code = self.blocks[2], self.blocks[3]
        self.assertEqual(hdr[1], 3)               # CODE
        length, start, _ = struct.unpack_from("<HHH", hdr, 12)
        self.assertEqual(start, ORG)
        with open(BIN, "rb") as f:
            self.assertEqual(code[1:-1], f.read())
        self.assertEqual(length, len(code) - 2)


if __name__ == "__main__":
    unittest.main()
