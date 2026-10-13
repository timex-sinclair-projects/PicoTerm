"""A headless ZEsarUX TS-2068, driven over its remote protocol (ZRCP).

    with Emulator() as emu:
        emu.load(".../picoterm.tap")
        emu.wait_for_text("PicoTerm")

$ZESARUX names the binary; otherwise the macOS app and the PATH are tried.
$ZESARUX_ROM, if set, is passed as --romfile (for example TSPICO-23.ROM).
"""

import os
import shutil
import socket
import subprocess
import tempfile
import time

PROMPT = b"command> "


def find_zesarux():
    for path in (os.environ.get("ZESARUX"),
                 "/Applications/zesarux.app/Contents/MacOS/zesarux",
                 "/Applications/ZEsarUX TS-Pico.app/Contents/MacOS/zesarux",
                 shutil.which("zesarux")):
        if path and os.path.exists(path):
            return path
    return None


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Emulator:
    def __init__(self, machine="TS2068"):
        self.binary = find_zesarux()
        if not self.binary:
            raise FileNotFoundError("ZEsarUX not found; set $ZESARUX")
        self.machine = machine
        self.port = free_port()
        self.proc = None
        self.sock = None

    def __enter__(self):
        args = [self.binary, "--noconfigfile", "--machine", self.machine,
                "--vo", "null", "--ao", "null",
                "--enable-remoteprotocol", "--remoteprotocol-port", str(self.port)]
        rom = os.environ.get("ZESARUX_ROM")
        if rom:
            args += ["--romfile", rom]
        # Run from a scratch folder: ZEsarUX may write an autosave snapshot
        # beside itself or in the current folder.
        self.cwd = tempfile.mkdtemp(prefix="picoterm-emu-")
        self.proc = subprocess.Popen(args, cwd=self.cwd, stdout=subprocess.DEVNULL,
                                     stderr=subprocess.DEVNULL)
        deadline = time.time() + 15
        while True:
            try:
                self.sock = socket.create_connection(("127.0.0.1", self.port), timeout=1)
                break
            except OSError:
                if time.time() > deadline:
                    self.close()
                    raise TimeoutError("ZEsarUX did not open its ZRCP port")
                time.sleep(0.2)
        self.sock.settimeout(30)
        self._read()
        return self

    def __exit__(self, *exc):
        self.close()

    def close(self):
        if self.sock:
            self.sock.close()
            self.sock = None
        if self.proc:
            self.proc.kill()        # not exit-emulator: that saves a snapshot
            self.proc.wait()
            self.proc = None
        if getattr(self, "cwd", None):
            shutil.rmtree(self.cwd, ignore_errors=True)

    def _read(self):
        buf = b""
        while not buf.endswith(PROMPT):
            chunk = self.sock.recv(65536)
            if not chunk:
                raise ConnectionError("ZRCP closed")
            buf += chunk
        return buf[:-len(PROMPT)].decode(errors="replace")

    def cmd(self, text):
        self.sock.sendall(text.encode() + b"\n")
        return self._read()

    # --- helpers ---------------------------------------------------------

    def load(self, path):
        return self.cmd("smartload " + os.path.abspath(path))

    def screen(self):
        return self.cmd("get-ocr")

    def wait_for_text(self, text, timeout=20):
        deadline = time.time() + timeout
        while time.time() < deadline:
            s = self.screen()
            if text in s:
                return s
            time.sleep(0.25)
        raise TimeoutError(f"{text!r} not on screen:\n{self.screen()}")

    def peek(self, addr, n=1):
        out = b""
        while n > 0:                    # in pieces: ZRCP lines get long
            k = min(n, 1024)
            out += bytes.fromhex(self.cmd(f"read-memory {addr} {k}").strip())
            addr += k
            n -= k
        return out

    # --- PicoTerm's screen, read from memory -------------------------------
    # ZEsarUX's OCR only knows the ROM font; PicoTerm draws in CP437.

    def shadow_rows(self, sym, cols=32):
        data = self.peek(sym["SHADOW_CHR"], cols * 24)
        return [data[r * cols:(r + 1) * cols].decode("latin-1") for r in range(24)]

    def wait_for_shadow(self, sym, text, timeout=30):
        deadline = time.time() + timeout
        while time.time() < deadline:
            rows = self.shadow_rows(sym)
            if any(text in r for r in rows):
                return rows
            time.sleep(0.25)
        raise TimeoutError(f"{text!r} not in PicoTerm's screen")

    def bitmap_rows(self, sym):
        """The 32-column bitmap, decoded through PicoTerm's font. The cell
        under a shown cursor is decoded with its underline undone."""
        font = self.peek(sym["FONT"], 2048)
        glyphs = {}
        for c in range(256):
            glyphs.setdefault(font[c * 8:c * 8 + 8], chr(c) if 32 <= c < 127 else "?")
        glyphs[bytes(8)] = " "
        df = self.peek(0x4000, 6144)
        col, row = self.peek(sym["cur_col"], 2)
        shown = self.peek(sym["vid_cursor_shown"])[0]
        rows = []
        for r in range(24):
            line = ""
            for c in range(32):
                off = (r & 0x18) << 8 | (r & 7) << 5 | c
                cell = bytes(df[off + 256 * i] for i in range(8))
                if shown and (r, c) == (row, col):
                    cell = cell[:7] + bytes([cell[7] ^ 0xFF])
                line += glyphs.get(cell, "#")
            rows.append(line)
        return rows

    def peek16(self, addr):
        lo, hi = self.peek(addr, 2)
        return lo | hi << 8

    # ZEsarUX key codes for send-keys-event (utils.h, enum util_teclas)
    KEY_SPACE = 128
    KEY_ENTER = 129
    KEY_CAPS = 133          # left Shift: CAPS SHIFT
    KEY_SYM = 138           # left Ctrl: SYMBOL SHIFT

    def press(self, key, *mods, hold=0.12):
        """Press one matrix key (a lower-case letter, a digit or a KEY_
        code) with CAPS/SYMBOL SHIFT held, then let everything go."""
        code = key if isinstance(key, int) else ord(key)
        for m in mods:
            self.cmd(f"send-keys-event {m} 1")
        time.sleep(0.04 if mods else 0)
        self.cmd(f"send-keys-event {code} 1")
        time.sleep(hold)
        self.cmd(f"send-keys-event {code} 0")
        for m in mods:
            self.cmd(f"send-keys-event {m} 0")
        time.sleep(0.06)

    def keys(self, text, ms=100):
        return self.cmd(f"send-keys-ascii {ms} " + " ".join(str(ord(c)) for c in text))


def symbols(path):
    """Labels from an sjasmplus --sym file: {name: value}."""
    out = {}
    with open(path) as f:
        for line in f:
            name, _, value = line.partition(": EQU ")
            if value:
                out[name.strip()] = int(value.strip(), 0)
    return out
