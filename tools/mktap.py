#!/usr/bin/env python3
"""Build picoterm.tap: a BASIC loader and the CODE block.

The loader is one line:

    10 CLEAR <org-1>: LOAD "" CODE : RANDOMIZE USR <org>

It autostarts at line 10. The TS-2068 uses the Spectrum's tape format and the
same tokens for these keywords, so the TAP works on both a 2068 and in
emulators.

Usage: mktap.py --org 0x8000 --name PicoTerm picoterm.bin picoterm.tap
"""

import argparse
import struct
import sys

TOK_CLEAR = 0xFD
TOK_LOAD = 0xEF
TOK_CODE = 0xAF
TOK_RANDOMIZE = 0xF9
TOK_USR = 0xC0

HEADER_PROGRAM = 0
HEADER_CODE = 3


def number(n):
    """A BASIC number: its digits, then 0Eh and the 5-byte small-integer form."""
    if not 0 <= n <= 65535:
        raise ValueError(f"{n} is not a small integer")
    return str(n).encode("ascii") + bytes([0x0E, 0, 0, n & 0xFF, n >> 8, 0])


def basic_line(line_no, body):
    body = body + b"\x0d"
    return struct.pack(">H", line_no) + struct.pack("<H", len(body)) + body


def loader(org):
    body = (
        bytes([TOK_CLEAR]) + number(org - 1)
        + b":" + bytes([TOK_LOAD]) + b'""' + bytes([TOK_CODE])
        + b":" + bytes([TOK_RANDOMIZE, TOK_USR]) + number(org)
    )
    return basic_line(10, body)


def block(flag, data):
    """A TAP block: length, flag, data, XOR checksum."""
    check = flag
    for b in data:
        check ^= b
    return struct.pack("<H", len(data) + 2) + bytes([flag]) + data + bytes([check])


def header(kind, name, length, param1, param2):
    name = name.encode("ascii")[:10].ljust(10, b" ")
    return block(0x00, bytes([kind]) + name + struct.pack("<HHH", length, param1, param2))


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--org", type=lambda s: int(s, 0), required=True)
    ap.add_argument("--name", default="PicoTerm")
    ap.add_argument("bin")
    ap.add_argument("tap")
    args = ap.parse_args()

    code = open(args.bin, "rb").read()
    if not code:
        sys.exit(f"{args.bin} is empty")
    if args.org + len(code) > 0x10000:
        sys.exit(f"{len(code)} bytes at {args.org:#06x} run past FFFFh")

    prog = loader(args.org)
    tap = (
        header(HEADER_PROGRAM, args.name, len(prog), 10, len(prog))
        + block(0xFF, prog)
        + header(HEADER_CODE, args.name, len(code), args.org, 32768)
        + block(0xFF, code)
    )
    with open(args.tap, "wb") as f:
        f.write(tap)
    print(f"{args.tap}: loader {len(prog)} bytes, code {len(code)} bytes "
          f"at {args.org:#06x}-{args.org + len(code) - 1:#06x}")


if __name__ == "__main__":
    main()
