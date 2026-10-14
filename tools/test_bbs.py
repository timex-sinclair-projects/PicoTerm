#!/usr/bin/env python3
"""A test server for checking PicoTerm on real hardware
(docs/hardware-test-checklist.md). Run it on a computer on the same network
as the TS-Pico:

    python3 tools/test_bbs.py [--raw 2323] [--telnet 2324]

Dial it from PicoTerm with ATD"<computer>:2323" (raw TCP) or
ATDT"<computer>:2324" (telnet). Every byte both ways is logged in hex.

On the telnet port the server asks for the terminal type (TTYPE) and the
window size (NAWS), doubles FFh in what it sends and undoubles it in what it
receives, so it shows what Zimodem's telnet does. Single-key commands; see
MENU. The XMODEM sender is the one the host tests use (tests/fakes.py).
"""

import argparse
import functools
import asyncio
import os
import sys
import time

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests"))
from fakes import XmodemSender  # noqa: E402

print = functools.partial(print, flush=True)   # the log is read as it happens

IAC, DONT, DO, WONT, WILL, SB, SE = 255, 254, 253, 252, 251, 250, 240
TTYPE, NAWS = 24, 31
E = b"\x1b["

MENU = (b"\r\n" + E + b"1;33mPicoTerm test server" + E + b"0m\r\n"
        b" E  echo (a line with only . ends it)\r\n"
        b" A  ANSI test screen\r\n"
        b" V  VT52 test screen\r\n"
        b" C  CP437 chart (128-255)\r\n"
        b" F  flood: 200 numbered lines\r\n"
        b" P  cursor position report\r\n"
        b" T  telnet: what Zimodem told us\r\n"
        b" 1  XMODEM 3000 bytes, CRC\r\n"
        b" 2  XMODEM 6912 bytes (PicoTerm's limit)\r\n"
        b" 3  XMODEM 8000 bytes (too big)\r\n"
        b" 4  XMODEM 1K blocks, 6144 bytes\r\n"
        b" 5  XMODEM checksum only, 1000 bytes\r\n"
        b" 6  XMODEM 2000 bytes of FFh, 17h, 1Ah, 0Dh\r\n"
        b" Q  hang up\r\n"
        b"Choice: ")


def sample(n, seed=1):
    out = bytearray()
    x = seed
    while len(out) < n:
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out.append((x >> 16) & 0xFF)
    return bytes(out)


def ansi_screen():
    s = E + b"0m" + E + b"2J" + E + b"1;37mANSI test" + E + b"0m\r\n\r\n"
    for c in range(8):
        s += E + b"%dm fg%d " % (30 + c, c)
    s += E + b"0m\r\n"
    for c in range(8):
        s += E + b"1;%dm bold%d " % (30 + c, c)
    s += E + b"0m\r\n"
    for c in range(8):
        s += E + b"%dm  bg%d  " % (40 + c, c)
    s += E + b"0m\r\n" + E + b"7mreverse" + E + b"0m " + E + b"5mblink" + E + b"0m\r\n"
    s += b"\xc9" + b"\xcd" * 20 + b"\xbb\r\n\xba" + b" box drawing CP437  " + b"\xba\r\n\xc8" + b"\xcd" * 20 + b"\xbc\r\n"
    s += E + b"12;10HCUP 12;10" + E + b"14;1H"
    s += b"0123456789" + E + b"5D" + E + b"K" + b" <- EL from col 6\r\n"
    s += b"abcdefgh" + E + b"3D" + E + b"2@" + b"\r\n"     # insert 2 before f
    s += E + b"20;1HScroll region 20-22 next:" + E + b"20;22r" + E + b"22;1H"
    for i in range(5):
        s += b"\r\nregion line %d" % i
    s += E + b"r" + E + b"24;1H" + E + b"1;32mEnd of ANSI test." + E + b"0m"
    return s


def vt52_screen():
    s = b"\x1bH\x1bJVT52 test\r\n"
    s += b"\x1bY" + bytes([32 + 5, 32 + 10]) + b"at row 5 col 10"
    s += b"\x1bY" + bytes([32 + 7, 32]) + b"erase-to-end: XXXXXXXX" + b"\x1bD" * 8 + b"\x1bK"
    s += b"\x1bY" + bytes([32 + 9, 32]) + b"up two: " + b"\x1bA\x1bA" + b"<here"
    s += b"\x1bY" + bytes([32 + 12, 32]) + b"End of VT52 test.\r\n"
    return s


def cp437_chart():
    s = b"\r\nCP437 128-255:\r\n"
    for row in range(8):
        base = 128 + row * 16
        s += b"%02X " % base + bytes(range(base, base + 16)) + b"\r\n"
    return s


class Session:
    IDLE_LIMIT = 60         # s with nothing from the receiver: give up
    MAX_TIME = 900          # s for a whole transfer

    def __init__(self, reader, writer, telnet):
        self.r, self.w, self.telnet = reader, writer, telnet
        self.peer = writer.get_extra_info("peername")
        self.ttype = None
        self.naws = None
        self.inbuf = bytearray()
        self.iac_state = None
        self.sb = bytearray()

    def log(self, tag, data):
        print(f"{time.strftime('%H:%M:%S')} {self.peer[0]} {tag} {data.hex(' ')}", flush=True)

    async def send(self, data):
        if self.telnet:
            data = data.replace(b"\xff", b"\xff\xff")
        self.log(">>", data[:64] + (b"..." if len(data) > 64 else b""))
        self.w.write(data)
        await self.w.drain()

    async def send_raw(self, data):
        self.log(">>", data)
        self.w.write(data)
        await self.w.drain()

    def feed(self, data):
        """Telnet decoding: returns the data bytes, answers options."""
        if not self.telnet:
            return bytes(data)
        out = bytearray()
        for b in data:
            st = self.iac_state
            if st is None:
                if b == IAC:
                    self.iac_state = "iac"
                else:
                    out.append(b)
            elif st == "iac":
                if b == IAC:
                    out.append(IAC)
                    self.iac_state = None
                elif b in (DO, DONT, WILL, WONT):
                    self.iac_state = b
                elif b == SB:
                    self.sb = bytearray()
                    self.iac_state = "sb"
                else:
                    self.iac_state = None
            elif st in (DO, DONT, WILL, WONT):
                self.iac_state = None
                self.option(st, b)
            elif st == "sb":
                if b == IAC:
                    self.iac_state = "sbiac"
                else:
                    self.sb.append(b)
            elif st == "sbiac":
                if b == SE:
                    self.subneg(bytes(self.sb))
                    self.iac_state = None
                else:
                    self.sb.append(b)
                    self.iac_state = "sb"
        return bytes(out)

    def option(self, verb, opt):
        if verb == WILL and opt == TTYPE:
            self.pending.append(bytes([IAC, SB, TTYPE, 1, IAC, SE]))
        elif verb == WILL and opt == NAWS:
            pass
        elif verb == DO:
            self.pending.append(bytes([IAC, WONT, opt]))
        elif verb == WILL:
            self.pending.append(bytes([IAC, DONT, opt]))

    def subneg(self, sb):
        if sb[:2] == bytes([TTYPE, 0]):
            self.ttype = sb[2:].decode("latin-1")
        elif sb[:1] == bytes([NAWS]) and len(sb) >= 5:
            self.naws = (sb[1] << 8 | sb[2], sb[3] << 8 | sb[4])

    async def read(self, timeout=None):
        """One data byte, or None on timeout/close."""
        while not self.inbuf:
            try:
                data = await asyncio.wait_for(self.r.read(256), timeout)
            except asyncio.TimeoutError:
                return None
            if not data:
                raise ConnectionError
            self.log("<<", data)
            self.pending = []
            self.inbuf += self.feed(data)
            for p in self.pending:
                await self.send_raw(p)
        b = self.inbuf[0]
        del self.inbuf[0]
        return b

    async def run(self):
        self.pending = []
        if self.telnet:
            await self.send_raw(bytes([IAC, DO, TTYPE, IAC, DO, NAWS]))
        await self.send(b"\r\nWelcome to the PicoTerm test server (%s).\r\n"
                        % (b"telnet" if self.telnet else b"raw TCP"))
        await self.send(MENU)
        while True:
            b = await self.read()
            if b < 32 or b >= 127:
                continue        # control bytes (a late NAK or ACK, CR) aren't commands
            c = chr(b).upper()
            await self.send(c.encode() + b"\r\n")
            if c == "Q":
                await self.send(b"Goodbye.\r\n")
                return
            await self.command(c)
            await self.send(MENU)

    async def command(self, c):
        if c == "E":
            await self.send(b"Echo. Type; a line with only . ends it.\r\n")
            line = b""
            while True:
                b = await self.read()
                await self.send(bytes([b]) + (b"\n" if b == 13 else b""))
                if b == 13:
                    if line == b".":
                        return
                    line = b""
                elif b in (8, 127):
                    line = line[:-1]
                else:
                    line += bytes([b])
        elif c == "A":
            await self.send(ansi_screen())
        elif c == "V":
            await self.send(vt52_screen())
        elif c == "C":
            await self.send(cp437_chart())
        elif c == "F":
            # 200 lines, then a cursor-position query: PicoTerm answers it
            # only once it has drawn everything before it, so the time to
            # the answer is the time to display the flood.
            start = time.time()
            for i in range(200):
                await self.send(b"line %03d " % i + b"x" * 40 + b"\r\n")
            await self.send(E + b"6n")
            reply = bytearray()
            while not reply.endswith(b"R"):
                b = await self.read(300)
                if b is None:
                    break
                reply.append(b)
            took = time.time() - start
            print(f"FLOOD: 10200 bytes displayed in {took:.1f} s "
                  f"= {10200 / took:.0f} characters a second", flush=True)
            await self.send(b"\r\nFlood displayed in %.1f s (%d characters a second).\r\n"
                            % (took, 10200 / took))
        elif c == "P":
            await self.send(E + b"255;255H" + E + b"6n")
            reply = bytearray()
            while True:
                b = await self.read(5)
                if b is None:
                    break
                reply.append(b)
                if b == ord("R"):
                    break
            await self.send(E + b"H\r\nCursor report: %r\r\n" % bytes(reply))
        elif c == "T":
            await self.send(b"Terminal type: %r\r\nWindow size: %r\r\n"
                            % (self.ttype, self.naws))
        elif c in "123456":
            args = {"1": (sample(3000), {}), "2": (sample(6912), {}),
                    "3": (sample(8000), {}), "4": (sample(6144), {"block": 1024}),
                    "5": (sample(1000), {"checksum_only": True}),
                    "6": ((b"\xff\x17\x1a\x0d" * 500), {})}[c]
            await self.xmodem(*args)

    async def xmodem(self, data, opts):
        await self.send(b"XMODEM: %d bytes. Start your receive (BREAK, X).\r\n" % len(data))
        sender = XmodemSender(data, **opts)
        # Give up only when the receiver has been silent for IDLE_LIMIT: at
        # the card's default 300 baud a block takes over 4 s to arrive, so
        # 6912 bytes take about 4 minutes. MAX_TIME is a backstop.
        start = last = time.time()
        while (sender.state not in ("done", "cancelled", "ended")
               and time.time() - last < self.IDLE_LIMIT
               and time.time() - start < self.MAX_TIME):
            b = await self.read(1)
            if b is not None:
                last = time.time()
                before = len(sender.sent_blocks)
                sender.receive(b)
                if len(sender.sent_blocks) != before:
                    print(f"XMODEM: block {sender.sent_blocks[-1]} sent, "
                          f"{time.time() - start:.1f} s")
            if sender.out:
                await self.send(bytes(sender.out))
                sender.out.clear()
        print(f"XMODEM: {sender.state}, {len(sender.sent_blocks)} blocks sent, "
              f"{sender.naks} NAKs, {time.time() - start:.1f} s")
        await asyncio.sleep(1)
        await self.send(b"\r\nXMODEM %s.\r\n" % sender.state.encode())


async def serve(port, telnet):
    async def handle(reader, writer):
        s = Session(reader, writer, telnet)
        print(f"connect {s.peer} ({'telnet' if telnet else 'raw'})")
        try:
            await s.run()
        except (ConnectionError, asyncio.IncompleteReadError):
            pass
        print(f"closed {s.peer}")
        writer.close()
    server = await asyncio.start_server(handle, "0.0.0.0", port)
    print(f"listening on {port} ({'telnet' if telnet else 'raw TCP'})")
    async with server:
        await server.serve_forever()


def main():
    ap = argparse.ArgumentParser(description="PicoTerm hardware test server")
    ap.add_argument("--raw", type=int, default=2323)
    ap.add_argument("--telnet", type=int, default=2324)
    a = ap.parse_args()

    async def both():
        await asyncio.gather(serve(a.raw, False), serve(a.telnet, True))
    try:
        asyncio.run(both())
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
