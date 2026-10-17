"""A TS-2068 model for host tests: PicoTerm's binary on the `z80` package.

Only what PicoTerm touches is modeled: RAM, the system variables it reads,
the keyboard matrix, the frame interrupt (IM2, data bus FFh), DECR and the
HSR, and devices on the 8251 ports ($73/$77) and the TS-Pico ports (14/15).
There's no ROM code: VIDMOD is preset to 80h, as if CHNG_VID had run, so
dfile_open returns at once, and CHARS points at a made-up font whose glyphs
are all different, so the screen can be read back from the bitmap.

    m = Machine(acia=Fake8251(FakeZimodem()))
    m.run_frames(100)
    m.type("ati\\n")
    print(m.screen_text())
"""

import os

import z80

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BIN = os.path.join(ROOT, "build", "picoterm.bin")
SYM = os.path.join(ROOT, "build", "picoterm.sym")

ORG = 0x8800
FRAME_T = 70000                 # 3.5 MHz / 50 Hz
EXIT_TRAP = 0x5B00              # PicoTerm's final RET lands here
FONT_SRC = 0x3D00               # the made-up ROM font

# Keyboard matrix: half-row n is read with bit n of the high address byte
# low; bit 0 is the outermost key.
MATRIX = [
    ["CAPS", "z", "x", "c", "v"],
    ["a", "s", "d", "f", "g"],
    ["q", "w", "e", "r", "t"],
    ["1", "2", "3", "4", "5"],
    ["0", "9", "8", "7", "6"],
    ["p", "o", "i", "u", "y"],
    ["ENTER", "l", "k", "j", "h"],
    ["SPACE", "SYM", "m", "n", "b"],
]
KEYPOS = {k: (r, b) for r, row in enumerate(MATRIX) for b, k in enumerate(row)}

# SYMBOL SHIFT + key, as PicoTerm's key map has them (src/hw/kbd.asm)
SYMKEYS = dict(zip(":`?/~|\\{}<>!@#$%_)('&\";][=+-^.,*",
                   "zxcvasdfgrt1234509876pouylkjhmnb"))


def symbols(path=SYM):
    out = {}
    with open(path) as f:
        for line in f:
            name, _, value = line.partition(": EQU ")
            if value:
                out[name.strip()] = int(value.strip(), 0)
    return out


def made_up_glyph(code):
    """Eight bytes that differ for every code 32-127."""
    return bytes([code, code ^ 0xFF, 0x18, code, 0x81, code ^ 0x55, 0x24, code])


class Machine:
    def __init__(self, acia=None, pico=None, rom_version=0x23, font=None):
        self.sym = symbols()
        self.acia = acia
        self.pico = pico
        if acia is not None and pico is not None:
            acia.pico = pico                # the card reads its flow setting
        self.m = m = z80.Z80Machine()
        self.mem = m.memory
        with open(BIN, "rb") as f:
            m.set_memory_block(ORG, f.read())
        if font is None:
            font = b"".join(made_up_glyph(c) for c in range(32, 128))
        m.set_memory_block(FONT_SRC, font[:768])
        self.poke16(0x5C36, FONT_SRC - 256)     # CHARS
        self.mem[0x0065] = rom_version          # ROM version byte
        self.mem[0x5CC2] = 0x80                 # VIDMOD: DF2 already open
        self.mem[0x5C8D] = 0x38                 # ATTR_P
        self.mem[0x5C48] = 0x38                 # BORDCR
        self.mem[EXIT_TRAP] = 0x76              # HALT, never reached
        m.set_breakpoint(EXIT_TRAP)
        m.sp = 0x7F00
        m.sp -= 2
        self.poke16(m.sp, EXIT_TRAP)            # the USR call's return address
        m.pc = ORG
        m.set_input_callback(self._in)
        m.set_output_callback(self._out)
        m.set_get_int_vector_callback(lambda: 0xFF)
        self.decr = 0
        self.hsr = 0
        self.border = 0
        self.keys = set()
        self.frame = 0
        self.exited = False
        self.decr_writes = []
        self.ay = [0] * 16
        self.ay_reg = 0
        self.ay_log = []

    # --- memory ------------------------------------------------------------

    def peek(self, addr, n=1):
        return bytes(self.mem[addr:addr + n])

    def peek16(self, addr):
        return self.mem[addr] | self.mem[addr + 1] << 8

    def poke16(self, addr, v):
        self.mem[addr] = v & 0xFF
        self.mem[addr + 1] = v >> 8

    def var(self, name, n=1):
        b = self.peek(self.sym[name], n)
        return b[0] if n == 1 else b

    # --- running -----------------------------------------------------------

    def run_frames(self, n):
        for _ in range(n):
            if self.exited:
                return
            self.m.ticks_to_stop = FRAME_T
            self.m.run()
            if self.m.pc == EXIT_TRAP:
                self.exited = True
                return
            self.frame += 1
            for dev in (self.acia, self.pico):
                if dev is not None and hasattr(dev, "tick"):
                    dev.tick()
            self.m.on_handle_active_int()

    def run_to(self, addr, limit=500):
        """Run, frame interrupts and all, until the CPU reaches addr."""
        self.m.set_breakpoint(addr)
        try:
            for _ in range(limit):
                self.m.ticks_to_stop = FRAME_T
                self.m.run()
                if self.m.pc == addr:
                    return True
                if self.m.pc == EXIT_TRAP:
                    self.exited = True
                    return False
                self.frame += 1
                for dev in (self.acia, self.pico):
                    if dev is not None and hasattr(dev, "tick"):
                        dev.tick()
                self.m.on_handle_active_int()
            return False
        finally:
            self.m.clear_breakpoint(addr)

    def idle(self):
        """Run until every received byte has been handled: PicoTerm only
        blinks the cursor when its ring is empty and the screen is done."""
        return self.run_to(self.sym["cursor_blink"])

    def settle(self, limit=50):
        """Run until PicoTerm asks for a key with none waiting: whatever the
        last key started (a window, a redraw) has finished."""
        for _ in range(limit):
            if not self.run_to(self.sym["kbd_get"]):
                return False
            if self.var("kbq_head") == self.var("kbq_tail"):
                return True
            self.m.ticks_to_stop = 10
            self.m.step_over_breakpoint()
        return False

    def stop_at(self, addr):
        """Run (without frame interrupts) until the CPU reaches addr."""
        self.m.set_breakpoint(addr)
        self.m.ticks_to_stop = FRAME_T
        self.m.run()
        self.m.clear_breakpoint(addr)
        assert self.m.pc == addr, f"stopped at {self.m.pc:04X}, not {addr:04X}"

    def run_until(self, cond, limit=1000):
        for _ in range(limit):
            if cond():
                return True
            self.run_frames(1)
        return cond()

    # --- ports -------------------------------------------------------------

    def _in(self, port):
        lo, hi = port & 0xFF, port >> 8
        if lo == 0xFE:
            v = 0xFF
            for k in self.keys:
                r, b = KEYPOS[k]
                if not hi & (1 << r):
                    v &= ~(1 << b)
            return v
        if lo in (0x73, 0x77) and self.acia is not None:
            return self.acia.data_read() if lo == 0x73 else self.acia.status()
        if lo in (0x0E, 0x0F) and self.pico is not None:
            return self.pico.port_in(lo)
        if lo == 0xFF:
            return self.decr
        return 0xFF

    def _out(self, port, v):
        lo = port & 0xFF
        if lo == 0xFE:
            self.border = v & 7
        elif lo in (0x73, 0x77):
            if self.acia is not None:
                if lo == 0x73:
                    self.acia.data_write(v)
                else:
                    self.acia.ctrl_write(v)
        elif lo in (0x0E, 0x0F):
            if self.pico is not None:
                self.pico.port_out(lo, v)
        elif lo == 0xFF:
            self.decr = v
            self.decr_writes.append(v)
        elif lo == 0xF4:
            self.hsr = v
        elif lo == 0xF5:
            self.ay_reg = v & 0x0F
        elif lo == 0xF6:
            self.ay[self.ay_reg] = v
            self.ay_log.append((self.ay_reg, v))

    # --- keyboard ----------------------------------------------------------

    def press(self, key, *mods, frames=3):
        self.keys |= {key, *mods}
        self.run_frames(frames)
        self.keys.clear()
        self.run_frames(frames)

    def quit(self, limit=600):
        """BREAK for the menu, then Q: back to BASIC."""
        self.press("SPACE", "CAPS")
        self.press("q")
        self.run_until(lambda: self.exited, limit=limit)
        return self.exited

    def type(self, text):
        for ch in text:
            if ch == "\n":
                self.press("ENTER")
            elif ch == " ":
                self.press("SPACE")
            elif ch.isupper():
                self.press(ch.lower(), "CAPS")
            elif ch in SYMKEYS:
                self.press(SYMKEYS[ch], "SYM")
            else:
                self.press(ch)

    # --- screen ------------------------------------------------------------

    def mode(self):
        return self.var("vid_mode")

    def cols(self):
        return self.var("vid_cols")

    def shadow_text(self, cols=None, rows=24):
        cols = cols or self.cols()
        base = self.sym["SHADOW_CHR"]
        stride = self.cols()
        return [self.peek(base + r * stride, cols).decode("latin-1")
                for r in range(rows)]

    def shadow_attrs(self, cols=None, rows=24):
        cols = cols or self.cols()
        base = self.sym["SHADOW_ATR"]
        stride = self.cols()
        return [list(self.peek(base + r * stride, cols)) for r in range(rows)]

    def glyph_table(self):
        """PicoTerm's font, glyph -> character ('?' outside ASCII)."""
        font = self.sym["FONT"]
        glyphs = {}
        for c in range(256):
            glyphs.setdefault(self.peek(font + c * 8, 8),
                              chr(c) if 32 <= c < 127 else "?")
        glyphs[bytes(8)] = " "
        return glyphs

    @staticmethod
    def swap_ink_paper(a):
        return (a & 0xC0) | (a & 7) << 3 | (a >> 3) & 7

    @staticmethod
    def cell_addr(row, col):
        """Display-file address of a 32-column cell's top line."""
        return 0x4000 | (row & 0x18) << 8 | (row & 7) << 5 | col

    def screen_text(self):
        """Read the screen back as the hardware would show it: the bitmap
        through PicoTerm's font in 32 and 64 columns, PicoVideo's text
        memory in 80. The cursor's flipped cell reads as itself."""
        mode = self.mode()
        if mode == 2:
            return [self.peek(0x4000 + r * 80, 80).decode("latin-1")
                    for r in range(24)]
        glyphs = self.glyph_table()
        crow, ccol = self.cursor()
        cursor_on = self.var("vid_cursor_shown")
        lines = []
        for r in range(24):
            line = ""
            for col in range(64 if mode == 1 else 32):
                if mode == 1:
                    addr = self.cell_addr(r, col >> 1) | (0x2000 if col & 1 else 0)
                else:
                    addr = self.cell_addr(r, col)
                cell = bytes(self.mem[addr + 256 * i] for i in range(8))
                if cursor_on and (r, col) == (crow, ccol):
                    cell = cell[:7] + bytes([cell[7] ^ 0xFF])   # undo the cursor
                line += glyphs.get(cell, "#")
            lines.append(line)
        return lines

    def screen_attrs(self):
        """The attributes the display shows: the attribute file in 32
        columns, both files in PicoVideo's 64 (mode 7), the text
        attributes in 80."""
        mode = self.mode()
        if mode == 2:
            rows = [list(self.peek(0x4780 + r * 80, 80)) for r in range(24)]
            if self.var("vid_cursor_shown"):           # undo the cursor
                r, c = self.cursor()
                rows[r][c] = self.swap_ink_paper(rows[r][c])
            return rows
        if mode == 1:
            return [[self.mem[(0x7800 if c & 1 else 0x5800) + r * 32 + (c >> 1)]
                     for c in range(64)] for r in range(24)]
        return [list(self.peek(0x5800 + r * 32, 32)) for r in range(24)]

    def cursor(self):
        col, row = self.peek(self.sym["cur_col"], 2)
        return row, col
