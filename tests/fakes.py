"""Fake devices for the host machine: the card's 8251, Zimodem, the TS-Pico.

They model what the 2068 sees, as described in docs/reference/
(ts2050-software-notes.md, v3-modem-proposal.md, programmers-manual.md),
not how the firmware is written.
"""

import re
from collections import deque

FPS = 50
GUARD_FRAMES = 45               # Zimodem's 900 ms


class Fake8251:
    """The v3 card's 8251 in Hayes mode: DSR held at 1, the link 8N1.

    boot_frames: TxRDY stays 0 this long after the first reset (the ESP32
    starting). cps: received characters per second, None = unpaced.
    never_ready: TxRDY never comes (no modem at all).
    floating: no 8251 at all: every read is FFh, writes go nowhere.
    """

    def __init__(self, line, boot_frames=0, cps=None, never_ready=False,
                 floating=False):
        self.floating = floating
        self.line = line
        self.boot_frames = boot_frames
        self.cps = cps
        self.never_ready = never_ready
        self.state = "mode"
        self.mode = None
        self.cmd = 0
        self.ctrl_log = []
        self.powered_at = None
        self.frame = 0
        self.rx_hold = None
        self.err_bits = 0
        self.inject_errors = deque()    # error bits for the next bytes
        self.budget = 0.0
        self.dropped = 0

    def tick(self):
        self.frame += 1
        if self.cps:
            self.budget = min(self.budget + self.cps / FPS, 2.0)
        self.line.tick(self.frame)

    # --- the ports ---------------------------------------------------------

    def ctrl_write(self, v):
        self.ctrl_log.append(v)
        if self.powered_at is None:
            self.powered_at = self.frame
        if self.state == "mode":
            if v in (0x00, 0x40):
                return                  # the reset preamble
            self.mode = v
            self.state = "cmd"
        elif v & 0x40:
            self.state = "mode"         # internal reset
        else:
            self.cmd = v
            if v & 0x10:
                self.err_bits = 0       # ER

    def tx_ready(self):
        return (not self.never_ready and self.state == "cmd"
                and self.powered_at is not None
                and self.frame >= self.powered_at + self.boot_frames)

    def _present(self):
        if self.rx_hold is None and self.line.to_terminal and self.cmd & 0x04:
            if self.cps is None or self.budget >= 1:
                self.rx_hold = self.line.to_terminal.popleft()
                if self.cps:
                    self.budget -= 1
                if self.inject_errors:
                    self.err_bits |= self.inject_errors.popleft()

    def status(self):
        if self.floating:
            return 0xFF
        self._present()
        s = 0x80                        # DSR
        if self.tx_ready():
            s |= 0x05                   # TxRDY, TxEMPTY
        if self.rx_hold is not None:
            s |= 0x02 | self.err_bits
        return s

    def data_read(self):
        if self.floating:
            return 0xFF
        self._present()
        v = 0 if self.rx_hold is None else self.rx_hold
        self.rx_hold = None
        return v

    def data_write(self, v):
        if self.tx_ready() and self.cmd & 0x01:
            self.line.from_terminal(v, self.frame)
        else:
            self.dropped += 1


class EchoBBS:
    """A remote host: a greeting, then echo. "bye" closes the connection;
    "flood" sends 4000 numbered characters."""

    GREETING = b"Welcome to the test BBS\r\n"

    def __init__(self):
        self.out = deque(self.GREETING)
        self.line = b""
        self.closed = False
        self.received = bytearray()

    def receive(self, b):
        self.received.append(b)
        self.out.append(b)
        if b == 13:
            word = self.line.strip().lower()
            self.out.append(10)
            if word == b"bye":
                self.closed = True
            elif word == b"flood":
                for i in range(100):
                    self.out.extend(b"line %02d " % i + b"x" * 30 + b"\r\n")
            self.line = b""
        else:
            self.line += bytes([b])


class FakeZimodem:
    """Enough of Zimodem: AT commands with echo and verbose results, ATDT to
    a host table, stream mode, the +++ escape with guard times, ATH."""

    def __init__(self, hosts=None, networks=None):
        self.hosts = hosts if hosts is not None else {"bbs.example:23": EchoBBS}
        # WiFi networks in range: ssid -> (rssi, password or None if open)
        self.networks = networks if networks is not None else {
            "HomeNet": (-48, "secret12"), "Cafe Free": (-71, None),
            "Neighbour": (-80, "x")}
        self.joined = None
        self.saved = False
        self.to_terminal = deque()
        self.mode = "cmd"
        self.echo = True
        self.cmdline = b""
        self.commands = []
        self.remote = None
        self.frame = 0
        self.last_byte_frame = -1000
        self.plus = 0
        self.plus_frame = None
        self.escapes = 0

    def send(self, data):
        self.to_terminal.extend(data)

    def result(self, word):
        self.send(b"\r\n" + word + b"\r\n")

    def from_terminal(self, b, frame):
        if self.mode == "cmd":
            if self.echo:
                self.send(bytes([b]))
            if b == 13:
                self.process(self.cmdline.decode("latin-1"))
                self.cmdline = b""
            elif b in (8, 127):
                self.cmdline = self.cmdline[:-1]
            else:
                self.cmdline += bytes([b])
            return
        # stream mode: watch for the escape
        if b == ord("+") and (self.plus or frame - self.last_byte_frame > GUARD_FRAMES):
            self.plus += 1
            self.plus_frame = frame
        else:
            self.plus = 0
        self.last_byte_frame = frame
        if self.remote is not None:
            self.remote.receive(b)

    def tick(self, frame):
        self.frame = frame
        if self.mode == "stream":
            if self.plus == 3 and frame - self.plus_frame > GUARD_FRAMES:
                self.plus = 0
                self.mode = "cmd"
                self.escapes += 1
                self.result(b"OK")
                return
            if self.remote is not None:
                while self.remote.out:
                    self.to_terminal.append(self.remote.out.popleft())
                if self.remote.closed:
                    self.remote = None
                    self.mode = "cmd"
                    self.result(b"NO CARRIER")

    def process(self, text):
        text = text.strip()
        self.commands.append(text)
        if not text.upper().startswith("AT"):
            return
        rest = text[2:]
        while rest:
            c = rest[0].upper()
            if c == "W" and not rest[1:2].isdigit():
                m = re.match(r'W"([^,"]*),([^"]*)"', rest, re.I)
                if m:                               # ATW"ssid,password": join
                    ssid, pw = m.group(1), m.group(2)
                    net = self.networks.get(ssid)
                    if net is None or (net[1] is not None and net[1] != pw):
                        self.result(b"ERROR")
                        return
                    self.joined = ssid
                    rest = rest[m.end():]
                    continue
                for ssid, (rssi, pw) in self.networks.items():   # ATW: scan
                    self.send(b"%s (%d)%s\r\n" % (ssid.encode(), rssi,
                                                   b" " if pw is None else b"*"))
                rest = rest[1:]
                continue
            if rest[:2].upper() == "&W":
                self.saved = True
                rest = rest[2:]
                continue
            if c == "D":
                m = re.match(r'D[TX]?"([^"]+)"', rest, re.I)
                if not m:
                    self.result(b"ERROR")
                    return
                host = m.group(1)
                if host in self.hosts:
                    self.remote = self.hosts[host]()
                    self.mode = "stream"
                    self.last_byte_frame = self.frame
                    self.result(b"CONNECT 1")
                else:
                    self.result(b"NO ANSWER")
                return
            m = re.match(r"([EVXQRFHZI])(\d?)|(&[WK]\d?)|(&S\"[^\"]*\")", rest, re.I)
            if not m:
                self.result(b"ERROR")
                return
            if m.group(1):
                letter, digit = m.group(1).upper(), m.group(2)
                if letter == "E":
                    self.echo = digit != "0"
                elif letter == "H":
                    self.remote = None
                elif letter == "I":
                    self.send(b"\r\nZimodem (fake)")
            rest = rest[m.end():]
        self.result(b"OK")


class FakePico:
    """The TS-Pico's command protocol as the 2068 sees it (Programmer's
    Manual chapters 2-3), with tpi:modem answered or unknown."""

    IDLE, MID = 0xFF, 0xF7

    def __init__(self, knows_modem=True, verbose=False, files=None):
        self.knows_modem = knows_modem
        self.verbose = verbose
        self.files = files if files is not None else {}   # name -> bytes
        self.channels = {}
        self.tx = deque([1])
        self.y = self.IDLE
        self.state = "idle"
        self.buf = []
        self.commands = []
        self.prehead = []
        self.tail = False

    def port_in(self, port):
        if port == 0x0F:
            return self.y
        v = self.tx.popleft() if self.tx else 0
        if self.tail and not self.tx:
            self.tx.append(1)
            self.y = self.IDLE
            self.tail = False
            self.state = "idle"
        return v

    def port_out(self, port, v):
        self.y = 0
        if port == 0x0F:
            self.tx.clear()
            self.tx.append(1)
            self.buf, self.tail = [], False
            self.state = "pre"
            self.y = self.IDLE
            return
        if self.state == "pre":
            self.buf.append(v)
            if len(self.buf) == 10:
                self.prehead.append(self.buf)
                self.need = self.buf[7] + 256 * self.buf[8] + 4
                self.buf = []
                self.state = "body"
                self.y = self.MID
        elif self.state == "body":
            self.buf.append(v)
            if len(self.buf) == self.need:
                self.process(self.buf)

    def process(self, body):
        x = 0
        for b in body[:-1]:
            x ^= b
        if x != body[-1] or body[0] != 0x44:
            status, msg = 2, None
        else:
            text = bytes(body[3:-1]).decode()
            self.commands.append(text)
            word = text.split(" ")[0].lower()
            if word == "tpi:modem" and self.knows_modem:
                status, msg = 1, "Modem: " + text[10:]
            elif word in ("tpi:chopen", "tpi:chwr", "tpi:chrd", "tpi:chclose"):
                pre = self.prehead[-1]
                if self.channel(word, text, pre[3] | pre[4] << 8, pre[5] | pre[6] << 8):
                    return                      # a data answer is queued
                status, msg = self.ch_status, None
            else:
                status, msg = 5, "Unrecognized command: " + text.split(" ")[0][4:]
        self.answer(status, msg)

    def answer(self, status, msg=None):
        if msg and (self.verbose or status != 1):
            self.tx.extend([0x81, status, 0x0D, *msg.encode(), 0])
        else:
            self.tx.append(status)
        self.y = self.IDLE
        self.tail = True
        self.state = "tail"

    # --- the channel commands (Programmer's Manual chapter 6), text mode:
    # CR <-> newline. Binary mode and TAB seeks aren't modelled.

    def channel(self, word, text, stream, n):
        """Run a channel command. True if it queued a data answer itself;
        otherwise ch_status is the status to send."""
        self.ch_status = 1
        if word == "tpi:chopen":
            _, mode, name = text.split(" ", 2)
            if mode.startswith("r"):
                if name not in self.files:
                    self.ch_status = 3                  # F
                    return False
                data = self.files[name].replace(b"\n", b"\r")
                self.channels[stream] = {"name": name, "data": data, "pos": 0}
            else:
                self.files[name] = b""
                self.channels[stream] = {"name": name, "write": True}
        elif word == "tpi:chwr":
            ch = self.channels.get(stream)
            if not ch or not ch.get("write"):
                self.ch_status = 10                     # J
                return False
            data = bytes.fromhex(text.split(" ", 1)[1])
            if 0x17 in data:
                self.ch_status = 4                      # a TAB we don't model
                return False
            self.files[ch["name"]] += data.replace(b"\r", b"\n")
        elif word == "tpi:chrd":
            ch = self.channels.get(stream)
            if not ch or "data" not in ch:
                self.ch_status = 10
                return False
            n = n or 255
            chunk = ch["data"][ch["pos"]:ch["pos"] + n]
            ch["pos"] += len(chunk)
            if not chunk:
                self.ch_status = 7                      # end of file
                return False
            x = 0
            for b in chunk:
                x ^= b
            self.tx.extend([1, len(chunk), *chunk, x])
            self.y = self.IDLE
            self.tail = True
            self.state = "tail"
            return True
        elif word == "tpi:chclose":
            self.channels.pop(stream, None)
        return False
