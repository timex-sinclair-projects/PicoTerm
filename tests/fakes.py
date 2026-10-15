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

    BANNER = b"\r\nZimodem Firmware v4.0.3\r\nREADY.\r\n"

    def __init__(self, hosts=None, networks=None, deaf_frames=0, queue_early=False):
        """deaf_frames: until this frame the line isn't up (the card holds
        the ESP32's line down while Zimodem boots: board_v3 modem_service);
        bytes sent before then are lost. Then Zimodem's banner arrives."""
        self.deaf_frames = deaf_frames
        self.queue_early = queue_early      # the card holds bytes until line-up
        self.early = bytearray()
        self.hosts = hosts if hosts is not None else {"bbs.example:23": EchoBBS}
        # WiFi networks in range: ssid -> (rssi, password or None if open)
        self.networks = networks if networks is not None else {
            "HomeNet": (-48, "secret12"), "Cafe Free": (-71, None),
            "Neighbour": (-80, "x")}
        self.joined = None
        self.saved = False
        self.lost = bytearray()
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
        if frame < self.deaf_frames:
            (self.early if self.queue_early else self.lost).append(b)
            return
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
        if self.deaf_frames and frame == self.deaf_frames:
            self.send(self.BANNER)
            early, self.early = bytes(self.early), bytearray()
            for b in early:                     # delivered at line-up, all at once
                self.from_terminal(b, frame)
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
                m = re.match(r'D[TPX]*"([^"]+)"', rest, re.I)       # modifiers: T telnet, X XON/XOFF
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

    def __init__(self, knows_modem=True, knows_flow=True, verbose=False, files=None):
        self.knows_modem = knows_modem
        self.knows_flow = knows_flow    # tpi:modem flow on/off (firmware #301)
        self.flow = False
        self.verbose = verbose
        self.files = files if files is not None else {}   # name -> bytes
        self.channels = {}
        self.native = None              # the arm tpi:fopen sets for a SAVE
        self.modem_mode = "2050"        # config.ini MODEM_MODE
        self.keys_seen = []
        self.saves = []                 # (path, data) for each SAVE written
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
                if self.buf[0] == 0x00:                 # a SAVE's header block
                    self.save_pre = self.buf
                    self.need = 21
                    self.state = "save_header"
                else:
                    self.need = self.buf[7] + 256 * self.buf[8] + 4
                    self.state = "body"
                self.buf = []
                self.y = self.MID
        elif self.state == "save_header":
            self.buf.append(v)
            if len(self.buf) == self.need:
                self.save_header(self.buf)
        elif self.state == "save_data":
            self.buf.append(v)
            if len(self.buf) == self.need:
                self.save_data(self.buf)
        elif self.state == "prompt":
            self.keys_seen.append(v)
            self.tx.extend([v, 0x0D, 0x03])
            if self.native is not None and chr(v) not in "Yy":
                self.native["refuse"] = True
            self.y = self.IDLE
            self.tail = True
            self.state = "tail"
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
                # tspico.py MODEM(): 2050, hayes or off, saved in config.ini
                # and turning flow off; flow on/off, not saved
                arg = text[10:].strip().lower()
                if arg in ("2050", "hayes", "off"):
                    self.modem_mode = arg
                    self.flow = False
                    status, msg = 1, "Modem: %s mode" % arg
                elif arg in ("flow on", "flow off") and self.knows_flow:
                    self.flow = arg == "flow on"
                    status, msg = 1, "Modem: " + arg
                elif self.knows_flow:
                    status, msg = 8, "2050, hayes, off or flow on/off"
                else:
                    status, msg = 8, "Use 2050, hayes or off"
            elif word == "tpi:fopen":
                pre = self.prehead[-1]
                path = text.split(" ", 1)[1]
                self.native = {"path": path, "op": pre[3], "mod": pre[4],
                               "session": pre[5] | pre[6] << 8, "refuse": False}
                if path in self.files:                  # 88h: Replace? (Y/N)
                    self.tx.extend([0x88, 1, *b"Replace %s? (Y/N)" % path.encode(), 0])
                    self.y = self.IDLE
                    self.state = "prompt"
                    return
                status, msg = 1, "Saving to " + path
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

    # --- SAVE: the header block, the mid status, the data block -----------

    @staticmethod
    def _xor(data):
        x = 0
        for b in data:
            x ^= b
        return x

    def save_header(self, blk):
        pre = self.save_pre
        session = pre[3] | pre[4] << 8
        hdr = blk[3:20]
        ok = (blk[0] == 0 and (blk[1] | blk[2] << 8) == session
              and self._xor([blk[0], *hdr]) == blk[20])
        native = self.native
        if not ok:
            status = 2                                  # R
        elif native is None or native["session"] != session:
            status = 3                                  # (a TAP SAVE: not modelled)
        elif native["refuse"]:
            status = 9                                  # D
        elif hdr[0] != 3 or native["mod"] != 0xAF:
            status = 8                                  # A: only CODE modelled
        else:
            status = 1
        self.tx.append(status)
        self.y = self.MID
        self.buf = []
        if status != 1:
            self.native = None
            self.tail = True
            self.state = "tail"
            return
        self.save_len = hdr[11] | hdr[12] << 8
        self.save_start = hdr[13] | hdr[14] << 8
        self.save_session = session
        self.need = self.save_len + 4
        self.state = "save_data"

    def save_data(self, blk):
        data = bytes(blk[3:-1])
        ok = (blk[0] == 0xFF and (blk[1] | blk[2] << 8) == self.save_session
              and self._xor([0xFF, *data]) == blk[-1])
        if ok:
            path = self.native["path"]
            self.files[path] = plus3dos_code(data, self.save_start)
            self.saves.append((path, data))
        self.native = None
        self.buf = []
        self.tx.append(1 if ok else 2)
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


def plus3dos_code(data, start):
    """A +3DOS file of CODE: the 128-byte header, then the data."""
    total = 128 + len(data)
    h = bytearray(128)
    h[0:8] = b"PLUS3DOS"
    h[8] = 0x1A
    h[9], h[10] = 1, 0
    h[11:15] = total.to_bytes(4, "little")
    h[15] = 3
    h[16:18] = len(data).to_bytes(2, "little")
    h[18:20] = start.to_bytes(2, "little")
    h[20:22] = (32768).to_bytes(2, "little")
    h[127] = sum(h[:127]) & 0xFF
    return bytes(h) + data


def crc16_xmodem(data):
    crc = 0
    for b in data:
        crc ^= b << 8
        for _ in range(8):
            crc = (crc << 1) ^ 0x1021 if crc & 0x8000 else crc << 1
            crc &= 0xFFFF
    return crc


class XmodemSender:
    """A BBS sending a file by XMODEM, once the terminal asks with C (CRC)
    or NAK (checksum). block: 128 or 1024. Faults, each once:
      corrupt: block numbers (1-based) sent with a damaged byte
      cut: block numbers sent only half-way (the receiver times out)
      repeat: block numbers sent twice (the receiver must drop the second)
      cancel_at: send CAN CAN instead of this block
      checksum_only: ignore C (an old sender)
      silent: never start"""

    SOH, STX, EOT, ACK, NAK, CAN = 1, 2, 4, 6, 0x15, 0x18

    def __init__(self, data, block=128, corrupt=(), cut=(), repeat=(),
                 cancel_at=None, checksum_only=False, silent=False):
        self.data = data
        self.size = block
        self.blocks = [data[i:i + block].ljust(block, b"\x1a")
                       for i in range(0, len(data), block)] or [b"\x1a" * block]
        self.corrupt, self.cut, self.repeat = set(corrupt), set(cut), set(repeat)
        self.cancel_at = cancel_at
        self.checksum_only = checksum_only
        self.silent = silent
        self.out = deque()
        self.closed = False
        self.received = bytearray()
        self.state = "wait"
        self.crc = True
        self.i = 0
        self.sent_blocks = []
        self.naks = 0
        self.repeat_pending = False

    def frame(self, i):
        n = i + 1
        body = self.blocks[i]
        if self.crc:
            c = crc16_xmodem(body)
            check = bytes([c >> 8, c & 0xFF])
        else:
            check = bytes([sum(body) & 0xFF])
        head = bytes([self.SOH if self.size == 128 else self.STX, n & 0xFF, 0xFF - (n & 0xFF)])
        return bytearray(head + body + check)

    def send_block(self):
        n = self.i + 1
        if self.cancel_at == n:
            self.out.extend([self.CAN, self.CAN])
            self.state = "cancelled"
            return
        f = self.frame(self.i)
        if n in self.corrupt:
            self.corrupt.discard(n)
            f[3 + 5] ^= 0x40
        if n in self.cut:
            self.cut.discard(n)
            f = f[:len(f) // 2]
        self.sent_blocks.append(n)
        self.out.extend(f)

    def receive(self, b):
        self.received.append(b)
        if self.silent or self.state in ("done", "cancelled", "ended"):
            return
        if b == self.CAN:                   # the receiver gives up: in any state
            self.state = "cancelled"
            return
        if self.state == "wait":
            if b == ord("C") and not self.checksum_only:
                self.crc = True
            elif b == self.NAK:
                self.crc = False
            else:
                return
            self.state = "send"
            self.send_block()
        elif self.state == "send":
            if b == self.ACK:
                n = self.i + 1
                if n in self.repeat and not self.repeat_pending:
                    self.repeat.discard(n)
                    self.repeat_pending = True
                    self.sent_blocks.append(n)
                    self.out.extend(self.frame(self.i))   # the same again
                    return
                self.repeat_pending = False
                self.i += 1
                if self.i == len(self.blocks):
                    self.out.append(self.EOT)
                    self.state = "eot"
                else:
                    self.send_block()
            elif b == self.NAK:
                self.naks += 1
                self.send_block()
            elif b == self.CAN:
                self.state = "cancelled"
        elif self.state == "eot":
            if b == self.ACK:
                self.state = "done"
            elif b == self.NAK:
                self.out.append(self.EOT)
            else:
                self.state = "ended"        # the receiver has moved on (typing)
