# PicoTerm design

PicoTerm is a terminal program for the TS-2068 with the TS-Pico v3 card. The card's 8251 at
$73/$77 bridges to Zimodem on an ESP32-C3, and the program uses it as a Hayes modem over WiFi.
This document is the plan the code is written against. Where something depends on hardware or
firmware that isn't finished, it says so.

Background is in [reference/](reference/):

- [ts2050-software-notes.md](reference/ts2050-software-notes.md): the 8251, MTERM, the
  BASIC dialers and Zimodem (tspico-firmware-build PR #265).
- [v3-modem-proposal.md](reference/v3-modem-proposal.md): what the card does (PR #264).
- [programmers-manual.md](reference/programmers-manual.md) and
  [ports-and-status.md](reference/ports-and-status.md): the TS-Pico command protocol on
  ports 14/15, which we use for files.
- [picovideo-howto.md](reference/picovideo-howto.md): PicoVideo modes 5 and 7.
- [emulators.md](reference/emulators.md): ZEsarUX/Fuse with `pico_host`.
- The TS2068 reference library (David's local repo, `TS2068 Ref Library`): the Technical
  Manual in Markdown, the memory map, `CHNG_VID`, and the annotated Zebra OS-64
  disassembly.

Statements marked **(to verify)** need a test on the card or an answer from another project.

## 1. Decisions

| | Decision |
|---|---|
| Modem | The card in **Hayes mode** only. The 8251 driver is a separate module, so a real-2050 back end (pulse dialing, DSR carrier) could be added later. |
| Display | **32 columns** (standard screen), **64 columns** (SCLD hi-res, mode 6), **80 columns** (PicoVideo mode 5). Selectable at run time. |
| Emulation | **ANSI-BBS** (a VT100 subset with colour, CP437), **VT52**, **TTY**. |
| Character set | CP437 in all three modes: a built-in 2 KB 8x8 font for 32/64 columns, PicoVideo's own font for 80. |
| File transfer | **XMODEM-CRC and XMODEM-1K download** to the TS-Pico's SD card. |
| Files | Through the TS-Pico command protocol on ports 14/15 (raw ports, the programmer's manual's way), never through the ROM. |
| Assembler | **sjasmplus**. Output: a `.tap` (BASIC loader + CODE) and a plain `.bin`. |
| Requires | TS-Pico firmware and ROM 2.3 or later (the SYNC protocol), with the v3 modem firmware. |

## 2. Lessons from MTERM

Kept:

- The 8251 setup: `00 00 00 40`, the mode byte, the command byte. We use mode **4Fh (8N1 x64)**
  for an 8-bit link, and command **37h** (TxEN, DTR, RxE, ER, RTS).
- TxRDY (status bit 0) before every data write, RxRDY (bit 1) before every data read. A
  PE/OE/FE error is cleared by rewriting the command (ER set), and the byte is still read.
- Receiving is decoupled from displaying: characters go into a ring buffer, and the display
  takes them out. MTERM did this by draining the receiver in every delay loop; we do it in
  the interrupt routine (section 4).

Dropped or changed:

- Pulse dialing, DSR as carrier, ring counting and auto-answer. In Hayes mode the card holds
  DSR at 1, so the connection state comes from Zimodem's result codes.
- "No TX or RX while on-hook": we talk to the modem in command mode.
- The TxRDY wait with no timeout. The ESP32 is powered on demand and takes about a second to
  start, during which TxRDY stays 0. Every wait has a timeout.
- Exact status compares like `IN 119=133`. We mask the bits we mean.
- A status of FFh means "no 8251". With no card the bus floats high, and the emulators read
  FFh too. Taken at face value it means "ready, a byte waiting, every error". PicoTerm would
  read a stream of FFh bytes.

## 3. Memory map

PicoTerm opens the second display file with the ROM's **Video Mode Change Service**
(`CHNG_VID`, EXROM 0E8Eh; Technical Manual 3.2.2.3), the same way Zebra's OS-64 does. On a
2068 the area 6000h-7AFFh normally holds the ROM's machine stack (6000h-61FFh), its RAM
dispatcher (6200h-682Fh), the channel data (CHANS, 6840h) and the start of BASIC (PROG,
6856h). `CHNG_VID` moves all of these out of the way:
- CHANS and PROG move up 12C0h, to 7B00h and 7B16h.
- The stack and the dispatcher move to F7C0h-FFFFh, and MSTBOT becomes F9C0h.
- The UDGs move down to F718h.

PicoTerm calls it once at start-up with mode **80h** (both display files available, DF1
shown), and leaves the file open, for these reasons:
- BASIC works normally while the file is open.
- CLOSE-DFILE has a bad reputation.
- Leaving it open makes 64 columns a single DECR write at any time.
- It frees 6000h-7AFFh as scratch RAM in the 32- and 80-column modes.

Measured in ZEsarUX on the stock ROM: after the call, CHANS = 7B00h, PROG = 7B16h,
MSTBOT = F9C0h and VIDMOD = 80h, and BASIC runs (`PRINT 7`, 0 OK).

| Address | Use |
|---|---|
| 0000-3FFF | ROM (HOME). Not called while PicoTerm runs. |
| 4000-57FF | DF1 bitmap (32/64 col). In 80 col: character codes 4000-477F, attributes 4780-4EFF. |
| 5800-5AFF | DF1 attributes (32 col; 64 col on PicoVideo mode 7, **to verify**) |
| 5B00-5FFF | System variables and TS-Pico ROM variables (TPMODE at 5DDBh). Left alone. |
| 6000-77FF | DF2 bitmap: the odd columns in 64-column mode, scratch RAM otherwise |
| 7800-7AFF | DF2 attributes (PicoVideo mode 7, **to verify**); scratch otherwise |
| 7B00-87FF | BASIC after the move: CHANS, the loader, its variables, workspace |
| 8800-F3FF | PicoTerm code, then data (below): 27 KB |
| F400-F4FF | Our stack |
| F500-F600 | IM2 vector table (257 bytes of F6h) |
| F6F6 | IM2 handler entry (`JP isr`) |
| F718-F7BF | UDGs (moved by `CHNG_VID`) |
| F7C0-FFFF | The ROM's machine stack and dispatcher (moved by `CHNG_VID`) |

The loader is `CLEAR 34815: LOAD "" CODE: RANDOMIZE USR 34816`. The code starts at 8800h
rather than 8000h because `CHNG_VID` needs RAMTOP above STKEND + 12C0h + 840h, which is
about 8380h with the loader in memory. Without that room it stops with
"4 Out of memory", before PicoTerm has changed anything.

**On the TS-Pico ROM 2.3:**
- Its EXROM has `CHNG_VID` and OPEN/CLOSE-DFILE byte-identical to the genuine ROM.
- Its relocation table at 1D00h has the community fix for the four entries that were one
  byte off. Those are the only four bytes that differ in the table.
- PicoTerm enters the EXROM as the Technical Manual does: HSR = 1, DECR bit 7 set. The
  TS-Pico's EXROM is 16 KB (HSR mask 3), but `CHNG_VID` is in its first 8 KB.

**To verify on the card:** stock ZEsarUX doesn't finish booting the TS-Pico ROM, so the call
hasn't run on that ROM yet.

DECR (port FFh) is always written as the ROMs do it: read the port, keep bit 7 (EXROM
select), OR in the mode. Bit 6 stays 0 so the frame interrupt keeps running.

Data, roughly:

| Item | Size |
|---|---|
| Code | 14-18 KB (estimate) |
| CP437 font, 256 x 8 | 2 KB |
| Screen shadow: character + attribute per cell, 80x24 max | 3,840 |
| Receive ring | 2 KB |
| XMODEM block buffer (1K + header + CRC) | 1,030 |
| Phonebook, 20 entries x 64 | 1,280 |
| TS-Pico command buffer (hex `chwr` text) | 300 |
| Settings, parser state, line buffers | < 1 KB |

That fits in 8800h-F3FFh. DF2 (6.9 KB) is spare in 32- and 80-column modes, for a scrollback later.

## 4. Structure

```
src/
  main.asm          entry, init, main loop, exit to BASIC
  mem.inc           addresses from section 3
  hw/
    isr.asm         IM2 setup/teardown, 50/60 Hz tick, calls kbd_scan and acia_drain
    acia.asm        8251: reset, tx with timeout, drain to ring, error reset
    pico.asm        TS-Pico protocol (adapted from the firmware repo's picolib.asm)
    picovideo.asm   PicoVideo register writes, mode select
    scld.asm        CHNG_VID (open DF2), DECR mode writes keeping bit 7
    kbd.asm         matrix scan, debounce, repeat, key map (section 8)
    sound.asm       bell on the AY (ports F5h/F6h)
  video/
    vid.asm         driver table + shared code (cursor, shadow, redraw)
    vid32.asm  vid64.asm  vid80.asm
    font.asm        incbin the CP437 font
  term/
    term.asm        byte dispatcher: current emulation, translations, wrap
    ansi.asm  vt52.asm  tty.asm
  modem/
    hayes.asm       command/response, line parser, dial, hang-up, the +++ guard times
  xfer/
    xmodem.asm  crc16.asm
  files/
    sdfile.asm      open/write/close on the SD card through pico.asm
    config.asm      read/write picoterm.cfg
  ui/
    menu.asm  status.asm  phonebook.asm  wifi.asm  setup.asm  input.asm (line editor)
tools/
  mktap.py          loader + CODE into picoterm.tap (no dependencies)
tests/
  ...               host tests (section 12)
Makefile
```

### Main loop and interrupts

- **IM2, our own handler.** The ROM's IM1 routine is not used while PicoTerm runs; IM1 and EI
  are restored on exit. The handler:
  1. increments a 16-bit tick counter (timeouts, cursor blink, guard times). The rate is
     the machine's frame rate: **60 Hz on a US TS-2068**, 50 Hz in a European setup or an
     emulator set to 50 Hz. Timeouts are written in ticks from a `TICKS_PER_SEC` setting,
     which can be measured at start-up against a known delay loop;
  2. scans the keyboard into a small key queue;
  3. **drains the 8251**: while RxRDY and the ring has room, read a byte into the ring
     (at most 64 per tick).
- **The main loop:** take a key and send it (or act on it, if it's a PicoTerm key); take a
  byte from the ring and pass it to the emulator. Several ring bytes are handled per key check.
- **Only the ISR reads $73.** The main loop writes $73 (with TxRDY checks) and writes command
  bytes to $77 with interrupts off.
- **Back-pressure: wrong, as built (found on hardware, 2026-10-14).** The plan was: if the
  display falls behind, the ring fills, the ISR stops reading, the card's 4 KB ring fills,
  and the card XOFFs Zimodem. But the card only sends XOFF in 2050 mode. In Hayes mode
  it leaves Zimodem's settings alone, so at `MODEM_BAUD=0` a fast host overflows the
  card's ring and data is lost (Q5).
  (In Hayes mode, who turns on Zimodem's XON/XOFF is open question Q5.)
- During long operations (SD writes, full-screen redraws) the ISR keeps receiving, so nothing
  waits on the main loop.

## 5. Display

Every driver provides the same entry points, through a jump table that is swapped when the
mode changes: `init`, `putc` (character + attribute at row, column), `clear_rows`,
`scroll_up`/`scroll_down` (within a region, for ANSI's DECSTBM and IL/DL), `cursor_on`/`off`,
`redraw` (from the shadow).

**The screen shadow** keeps a character and an attribute for every cell. Menus and the
status bar are drawn over the screen, and closing them redraws from the shadow. The shadow also
makes it possible to change column mode in the middle of a session.

| | 32 col | 64 col | 80 col |
|---|---|---|---|
| Hardware | SCLD mode 0 | SCLD mode 6 (DECR 6 + ink in bits 3-5) | PicoVideo mode 5 |
| Glyphs | 8x8 from our font, 8 bytes into DF1 | 8x8, even columns in DF1, odd in DF2 | One byte at 4000h + row x 80 + col |
| Colour | Per cell (Spectrum attributes) | One colour pair for the whole screen; per cell with PicoVideo mode 7 (**to verify** where its attributes live) | Per cell at 4780h (**to verify** the attribute format; assumed to be the Spectrum one) |
| Scroll one line | ~5.9 KB of LDI, about 27 ms | ~11.8 KB, about 54 ms | ~3.7 KB, about 17 ms |
| Cursor | XOR an underline | XOR an underline | Invert the cell's attribute |

**As built in M4:**
- **Driver table:** `vid_set_mode` rewrites five jumps (draw, clear rows, scroll up, scroll
  down, cursor), sets the column count and writes DECR, keeping bit 7.
- **Mode changes:** the shadow is re-laid out for the new width, keeping what fits, then
  the screen is redrawn from it. Rows stay exactly as wide as the mode, which keeps
  scrolling cheap. A fixed 80-cell row cost 25% more on every 32-column scroll.
- **64 columns:** this is the 32-column code run twice. A `vid_plane` of 0 or 20h is ORed
  into the screen addresses, so the same routine works on display file 1 or 2.
- **80 columns:** text memory is laid out like the shadow, so a scroll copies the moved rows
  back from the shadow.
- **Font:** the CP437 font is built in (2 KB). It's the same font PicoVideo uses
  (`src/video/cp437.asm`; CC BY-SA 4.0, see README).
- **Switching key:** CAPS + 9 (GRAPHICS) cycles the modes until the menu arrives in M5.
  It skips 80 columns unless `set_picovideo` is on.

From the PicoVideo v4.2 source (`displayProc.c`, `displayProc80.c`, `busMain.c`), answering
part of R3:
- **Mode 5** is the 80-column text mode: codes at 4000h, attributes at 4780h, 80 to a row,
  in the Spectrum attribute format, drawn from the CP437 font.
- **Mode 7** is the SCLD's 64-column mode, but with attributes: 5800h for the even
  columns and 7800h for the odd ones, the same places as in 32 columns.
- **Mode 6** uses one colour pair, taken from DECR bits 3-5.

Measured on the host machine at 3.5 MHz:

| | 32 col | 64 col | 80 col |
|---|---|---|---|
| Scroll one line (shadow + screen) | ~140,000 T, 40 ms | ~380,000 T, about 100 ms | ~200,000 T, 40-55 ms |
| Change into this mode from 32 (relayout + redraw) | - | about 0.7 s | about 0.3 s |

At 64 columns PicoTerm can show about 10 new lines a second. That's ample for text at
2400 baud; anything faster is held back by the card's flow control. Two ways to speed up
the 64-column scroll later: one pass over both display files, and unrolled copies.

**64 columns, in detail** (Technical Manual 5.2.1 and 5.2.3; Zebra OS-64):

- DECR mode field 6. Bits 3-5 pick the ink, and the paper is its complement: 06h is black on
  white, and 3Eh is white on black. BRIGHT and FLASH are fixed at 0, the border follows the
  paper, and the attribute areas aren't read.
- A cell's address: the row's start from a 24-entry table (as in the manual), then
  `SET 5,H` for an odd column (DF2), and the column shifted right by one as the offset. Then
  eight bytes go in, `INC H` between them, as in 32 columns.
- Scrolling and clearing do every move twice, once in each file. OS-64 wraps the ROM's
  `LDIR` as: `LDIR`, `SET 5,D`, `SET 5,H`, `LDIR`, then reset both.
- Each dot is half a standard pixel wide, so an 8-dot glyph is as wide as 4 pixels.

**A possible fourth mode: 80 columns without PicoVideo.** The Technical Manual (5.2.3)
describes an 80-column screen built on the 64-column hardware with a 6x8 font: 512 dots
make room for 85 characters. A character can span both display files, so drawing it means
masking and shifting, which is slower than the byte-aligned modes. This would give an
80-column ANSI screen on any 2068, in one colour, at the cost of very narrow glyphs. It's a
candidate for after M4. Appendix C of the manual has the original package, but its listing
isn't in the Markdown copy.

Rows: the terminal is **24 rows** in every mode; ANSI BBSes expect 24. The status bar is an
overlay, shown while a PicoTerm menu or prompt is open, and briefly on events (CONNECT,
NO CARRIER, transfer progress).

On a TV, 64 columns needs a sharp display, and 80 columns needs PicoVideo's HDMI output. The
SCLD itself has no mode 5, so the 2068's own video output shows garbage in 80-column mode.

**Colour mapping.** ANSI colour n maps to Spectrum colour `[0,2,4,6,1,3,5,7][n]`. Bold sets
BRIGHT, blink sets FLASH (switchable off), and reverse swaps INK and PAPER. The 2068's BRIGHT
applies to both INK and PAPER of a cell, so ANSI's "bright background" can't be shown on its
own.

**PicoVideo detection** is open question Q1. Until it's answered, 80 columns is a setting
("PicoVideo: yes/no"), off by default, saved in `picoterm.cfg`.

## 6. Terminal emulation

One byte dispatcher, with the emulation's state machine behind it. Translations applied to
every emulation, all settings: receive LF as CR LF; send CR, CR LF or LF for ENTER;
backspace sends 08h or 7Fh; local echo on/off; strip bit 7.

**ANSI-BBS** (the default):

- C0: BEL, BS, HT (stops every 8), LF, FF (clear screen, as BBSes use it), CR.
- `ESC [` sequences: cursor `A B C D H f`, `J` (0/1/2), `K` (0/1/2), `m` (0, 1, 5, 7, 22,
  25, 27, 30-37, 39, 40-47, 49), `s u` and `ESC 7 8`, `r` (scrolling region), `L M` (insert
  and delete lines), `@ P X` (insert, delete and erase characters), `?25 h/l` (cursor), `?7 h/l`
  (wrap), `6n` (**answered with a cursor position report**, which many BBSes use to detect
  ANSI and the screen size), `c` (device attributes, answered as a VT100).
- Unknown sequences are parsed to their end and ignored.
- ANSI music (`ESC [ M`) is ignored in the first version; the AY could play it later.

As built in M3:
- **Parameters:** a CSI sequence keeps up to 8 parameters, each held at 255 at most. A
  private marker (`<`, `=`, `>`, `?`) and intermediate bytes are recognised. Only `?`
  sequences ending `h` or `l` are acted on; the rest are parsed and dropped.
- **Controls inside a sequence** (C0) act at once. ESC starts a new sequence, and CAN or SUB
  abandons it.
- **Strings:** OSC strings are skipped up to BEL or ST.
- **Following ANSI.SYS, which BBS screens are drawn for:** `ESC [ 2 J` homes the cursor, and
  FF clears the screen and homes, keeping the colours.
- **Cursor:** IL and DL put the cursor in column 0. CUU and CUD stop at the margins of the
  scrolling region when they start inside it.
- **Extended colours:** SGR 38/48 with `5;n` use the first 16 colours; `2;r;g;b` is
  skipped.
- **Replies** go to the modem: CPR (`ESC [ row ; col R`), DA (`ESC [ ? 1 ; 0 c`), and DSR 5
  (`ESC [ 0 n`).

**VT52**: `ESC A B C D H I J K Y r c Z` (identify, answered with `ESC / K`) and `F G`
(graphics mode), the subset MTERM's table handled plus the rest of the standard set.

**TTY**: printable characters and the C0 controls above, nothing else.

**Width.** In 32 and 64 columns, text wraps at the right edge. Most BBSes ask for the screen
size, or detect it with `6n`. Zimodem's telnet terminal type is set with
`AT&S"41=ANSI"` (or `VT52`); NAWS (telnet window size) is open question Q7.

## 7. Modem

### Start-up

1. If the TS-Pico ROM is 2.3 or later (`PEEK 101` >= 35), send `tpi:modem hayes` through
   the TS-Pico protocol. A "C" (unknown command) answer means older firmware: carry on and
   hope it's already in Hayes mode, and say so. `tpi:modem` takes exactly `2050`, `hayes`
   or `off` (anything else is Report A). There is no `on`: resetting the 8251 powers the
   ESP32 up.
2. Reset the 8251: `00 00 00 40`, mode `4F`, command `37`.
3. Wait up to 5 s for TxRDY. On the card, TxRDY comes at once: the card holds what's sent
   in its own buffer.
4. Send `AT` CR and wait 1 s for `OK`; try 12 times (about 12 s). The card lets bytes
   through to Zimodem only 2 s after the first 8251 write (`board_v3` `modem_service`,
   `MODEM_BOOT_MS`). Zimodem can take longer than that to start, especially while it
   joins WiFi. Found on hardware, 2026-10-14: a single `AT` with a 3 s wait gave
   "No answer", then Zimodem's banner.
   - **The card queues** what's sent before the line is up, and delivers it all at once.
     So several `AT`s can reach Zimodem together. After the first `OK`, PicoTerm drains
     for half a second with the replies captured, out of sight, so they don't show and
     don't answer for the init string.
   - **While a command waits for its result,** `pump_rx` stops at the LF ending the
     result line, so later bytes stay in the ring. If there's no answer, open the terminal anyway in
   "no modem" state, so the user can still type.
5. Send the init string (a setting): by default `ATE1V1X1Q0` and `AT&S"41=ANSI"`. Echo stays
   on so the user can type AT commands themselves.

### Two ways to use it

- **Directly.** The terminal is always live. The user can type `ATDT"host:23"`, `ATI` or any
  other command, as with a real Hayes modem.
- **Through PicoTerm's menus.** The phonebook, the WiFi setup and hang-up send commands and
  read the answers. Each automated command:
  1. sends the text and CR;
  2. reads lines;
  3. skips the echo of what it sent;
  4. stops at `OK`, `ERROR`, `CONNECT…`, `NO ANSWER`, `NO CARRIER` or a timeout.

### Connection state

The state is OFFLINE, DIALING or ONLINE. A line parser watches the received bytes at line
starts: `CONNECT` means ONLINE, and `NO CARRIER` means OFFLINE. The bytes still go to the
screen, so the user sees the messages. A remote host could send "NO CARRIER" as text; we accept
that, as every Hayes terminal did. In Hayes mode the card holds DSR at 1, so we never look at
DSR.

### Hang-up

1. Wait 1.1 s with no TX.
2. Send `+++`, one character every 100 ms.
3. Wait 1.1 s.
4. Wait up to 3 s for `OK`.
5. Send `ATH`.

### Phonebook

Up to 20 entries, kept in `picoterm.cfg`. Each entry holds:

- a name;
- `host:port`;
- telnet on/off (`ATDT` or `ATD`);
- the emulation;
- the column mode;
- the backspace and ENTER settings;
- local echo.

Dialing an entry applies its settings, then sends `ATDT"host:port"`.

### WiFi

The WiFi screen:

1. Lists networks with `ATW` (SSID, RSSI, `*` = encrypted).
2. Lets the user pick one and type the password.
3. Sends `ATW"ssid,password"`.
4. On success, offers to save it as Zimodem's default with `AT&W`.

`ATI` shows the current state.

## 8. Keyboard

The 2068 has no Ctrl, Esc, arrow keys or several ASCII symbols, so PicoTerm reads the matrix
itself and maps keys. This first assignment follows the 2068's own key legends where it can:

| Keys | Sends |
|---|---|
| letters, digits, SPACE | as typed; CAPS SHIFT for capitals |
| ENTER | CR (or CR LF / LF, per setting) |
| CAPS + 0 (DELETE) | BS (08h) or DEL (7Fh), per setting |
| CAPS + 5 6 7 8 | arrows: `ESC [ D B A C` (ANSI) or `ESC D B A C` (VT52) |
| CAPS + 1 (EDIT) | ESC (1Bh) |
| CAPS + 3 | TAB |
| CAPS + 2 | caps lock |
| CAPS + SYMBOL SHIFT, then a key | **Ctrl** + that key (one-shot; "CTRL" on the status bar) |
| SYMBOL SHIFT + key | the key's ASCII symbol, with the BASIC keywords replaced: SS+A `~`, SS+S `\|`, SS+D `\`, SS+F `{`, SS+G `}`, SS+Y `[`, SS+U `]`, SS+H `^`, SS+X `` ` `` (instead of `£`), SS+Q/W/E unused |
| CAPS + SPACE (BREAK) | **PicoTerm menu** |
| CAPS + 9 (GRAPHICS) | next column mode (32, 64, 80 with PicoVideo) |

How the scan behaves (M1):
- One key is read per frame, and the shifts count only as modifiers.
- A held key repeats after 30 frames, then every 3.
- Pressing or releasing a shift while a key is held doesn't type that key again. Without
  this, letting go of CAPS SHIFT after a capital typed an extra lower-case letter.
- The Ctrl prefix is a toggle: pressing CAPS SHIFT + SYMBOL SHIFT twice cancels it.
- Showing CTRL and CAPS LOCK on screen waits for the status bar (M5).

The menu holds:

- Dial (the phonebook);
- Hang up;
- WiFi;
- Download (XMODEM);
- Settings: emulation, columns, PicoVideo, translations, colours, init string;
- Clear screen;
- Send break;
- Exit to BASIC.

### The menu, as built in M5

BREAK opens the menu:
- D: the phonebook;
- H: hang up;
- W: WiFi;
- S: settings;
- C: clear the screen;
- Q: quit to BASIC, hanging up first if connected.

BREAK or EDIT (Esc) goes back a level from every screen.

**Windows:**
- **Drawing:** windows are 32 cells wide and centred in wider modes. They're drawn
  straight through the driver, so the shadow keeps the terminal. Closing a window
  redraws from the shadow, and so does coming back to the menu from a screen under it.
- **Received bytes:** while a window is open they wait in the ring (`RX_HOLD`). When a
  screen asks Zimodem something (WiFi, the terminal type), they go to a 1 KB capture
  buffer instead (`RX_CAPTURE`). `hayes_watch` sees them in both cases, so result codes
  still arrive.
- **Selection:** in the SCLD's mono 64-column mode a highlight can't show, so the selected
  line also has a `>`. Moving the selection redraws only the two rows involved.

**Phonebook:**
- **Entries:** 20, each with a name (16 characters), `host:port` (40), and its own
  settings: telnet (ATDT or ATD), emulation, columns, backspace and local echo.
- **Dialling** applies the entry's settings, switches column mode if needed (64 without
  PicoVideo instead of 80), returns to the terminal, sends the terminal type, then
  `ATDT"host:port"`. CONNECT or NO ANSWER then shows in the terminal.
- **While connected**, dialling is refused with "Hang up first."

**WiFi:**
- **Scanning:** `ATW` lists networks as `SSID (RSSI)*` (Zimodem's `doWiFiCommand`), and
  the SSID is the text before the last ` (`. M lets you type an SSID that wasn't found.
- **Joining:** the password is masked, then `ATW"ssid,password"` is sent. On OK,
  PicoTerm offers to save the network as Zimodem's default with `AT&W`.
- **Limit:** Zimodem can't quote a comma or `"` in either field.

**Settings:**
- emulation, columns, PicoVideo, the 64-column ink, backspace, local echo, ENTER (CR or
  CR LF), blink as FLASH, the bell, and the modem init string;
- S saves everything to `picoterm.cfg`;
- on leaving Settings, the column mode is set again, and a changed emulation is sent to
  Zimodem as the terminal type.

**`picoterm.cfg`** is a text file in the SD card's current folder:

```
emul=2
cols=1
picovideo=1
ink64=7
bs=8
echo=0
enter=0
blink=1
bell=1
init=ATE1V1X1Q0
phone=Test BBS|bbs.example:23|1|2|0|8|0
```

- **Phone fields:** name, host, telnet, emulation, columns, backspace, echo.
- **Writing:** text-mode channel commands on stream 200, with `tpi:chwr` in hex chunks of
  at most 100 bytes.
- **Reading:** at start-up with `tpi:chrd`, before anything is drawn, with the TS-Pico's
  messages silenced.
- **Bad lines:** unknown keys, out-of-range numbers and malformed phone lines are skipped.

**Memory after M5:** code and data are 12.8 KB (8800h-B9FFh). Uninitialised data runs to
DF69h: the ring, the shadow, the phonebook, the capture buffer, and the command and WiFi
buffers. That leaves about 5 KB below the stack for M6.

## 9. XMODEM download

**Protocol.** The receiver sends `C` for CRC mode, up to 3 tries 3 s apart, then falls back to
NAK and checksum. It takes both SOH (128-byte) and STX (1 KB) blocks. It NAKs on a bad
CRC or a timeout (10 s, 10 tries), ACKs and ignores a duplicate block, and ends at EOT, which is
ACKed. CAN CAN from the sender, or BREAK from the user, aborts; on BREAK we send CAN x 5. The
CRC is CRC-16/XMODEM, table-driven (512-byte table).

**Writing to the SD card.** The file is written as it arrives, so its size isn't limited by
RAM:

1. Ask for a filename (default folder: `downloads/`).
2. Check whether the file exists (open it `r`). If it does, ask before replacing it.
3. `tpi:chopen wb <path>` on a private stream number (200).
4. After each good block, and before its ACK, `tpi:chwr <hex>`. Each command carries at most
   120 bytes (240 hex digits), keeping commands under 256 bytes as the programmer's manual
   advises. A 1 KB block takes 9 commands, about 120 ms plus the card's SD write, well inside
   the sender's 10 s.
5. At the end, `tpi:chclose`. On an abort, close the file and offer to erase it
   (`tpi:erase`).

**Blocker: byte 17h.** In a channel write, byte 17h always starts a TAB (a seek), even in binary
mode. Binary downloads contain 17h, so the TS-Pico firmware needs a binary-safe write
(firmware request **R2**, section 11).

Until it has one, the fallback is to collect the file in RAM (up to about 20 KB) and save it
with the SAVE-block protocol as an `f:` CODE file. That file gets a 128-byte +3DOS header, so
it loads back on the 2068 with `LOAD "f:name" CODE`, but on a PC it needs the header stripped.

**Padding.** XMODEM pads the last block with 1Ah. A setting, "Strip trailing ^Z", is on for
text files and off for binaries.

**Speed.** The card delivers received bytes no faster than `MODEM_BAUD`, which is 300 baud by
default. At that rate a 1 KB block takes 34 s, so useful downloads need a higher rate (Q2).

Later: YMODEM batch (it carries the name and the exact size, so there's no padding), XMODEM
upload, and capturing a session to a file. Uploads have a catch: with Zimodem's XON/XOFF on,
11h and 13h in the data would be swallowed, so a transfer has to turn flow control off first.
Zimodem's `AT&G` (fetch a file over HTTP) is another way to get files that may be worth a
look.

### As built in M6 (the RAM fallback)

**Flow:** BREAK, X, a file name (default `download.bin`), then "Replace?" if the file
exists. Start the download on the BBS first; PicoTerm then asks for it.

**Receiving** (`xfer/xmodem.asm`):
- **Start:** `C` three times, 3 s apart, then NAK for checksums.
- **Blocks:** SOH or STX. A bad block gets a NAK once the line has been quiet for 1 s. It's
  NAK, not `C`, even before the first good block: a sender that has started ignores `C`.
- **Repeats:** a repeat of the last block is ACKed and dropped.
- **Giving up:** ten errors in a row, a block out of sequence, BREAK, or a file too big
  for memory sends CAN x 5. CAN CAN from the sender ends it too.
- **Timeouts:** 1 s for a byte within a block, 10 s for a block to begin.
- **The receive path:** bytes come straight from the ring (`RX_HOLD`).
- **The buffer** is display file 2's area, 6000h-7AFFh, 6,912 bytes. In the SCLD's
  64-column mode, which shows that area, PicoTerm drops to 32 columns for the transfer and
  goes back afterwards.

**Saving** (`files/sdsave.asm`) does what `SAVE "f:path" CODE` does, without the ROM:
1. `tpi:fopen path`, with op 0 and the CODE token in the first CODE number and a session
   id in the second. If the file exists, the Pico's 88h "Replace?" is answered with
   `pico_auto_key`, after PicoTerm has asked the user itself.
2. SYNC, then the SAVE pre-header: 00h, 0, FFh, the session, the header's address, 17,
   XOR. Then the pre-load.
3. The header block (17 bytes: CODE, a 10-character stand-in name, length, 32768, 32768)
   and the mid status.
4. A pause of about a second.
5. The data block and the final status, read after the card write (with up to about 25 s
   allowed).

Interrupts are off while a block goes out, as in the ROM. The file gets the firmware's
128-byte +3DOS header, so `LOAD "f:name" CODE` loads it back on the 2068; on a PC the
header has to be cut off.

**Measured:** PicoTerm can receive about 1.5 KB/s with 128-byte blocks and 1.8 KB/s with
1K blocks (the bit-by-bit CRC is the limit). The card's pacing is far slower: 300 baud is
30 bytes a second, about 4 minutes for 6.9 KB, so `MODEM_BAUD` (R1) matters more than
anything here.

**Checked on the card** (board 1, 2026-10-14, `MODEM_BAUD=0`): every download saved
exactly. That covers CRC, the largest that fits, too big, checksum only, replace, and an
FFh-heavy file on both the raw and the telnet port. Zimodem undoubles IAC in stream mode,
so XMODEM over `ATDT` is fine (Q7). Times: 3,000 bytes in 8.8 s, 6,912 bytes in 12.3 s,
including the save.

## 10. Settings file

`picoterm.cfg` lives in the SD card's current folder and is written in text mode. It holds
`key=value` lines plus one `phone=` line per entry. Text mode is safe here because the file is
plain ASCII, with no 17h bytes and no tokens. It's read at start-up and written from the
Settings and phonebook screens. If it's missing, the defaults are 32 columns, ANSI, no
PicoVideo, and an empty phonebook.

## 11. What we need from other projects

R1 and R2 are written up in [firmware-requests.md](firmware-requests.md) and filed as
timex-sinclair-projects/tspico-firmware-build#298 and #299.


| # | From | Request | Why | Until then |
|---|---|---|---|---|
| R1 | firmware | Set the receive pacing at run time: e.g. `tpi:modem baud <n>` (with 0 = unpaced) | 300 baud makes downloads and 80-column BBS screens slow | The user edits `MODEM_BAUD` in `config.ini` |
| R2 | firmware | A binary-safe channel write: e.g. a mode flag that turns off the 17h TAB escape, or a `tpi:chwrb` | XMODEM to a plain file | RAM buffer + `f:` CODE with a +3DOS header |
| R3 | PicoVideo | A way to detect the board (a readable ID register). The mode 5 and 7 attribute layouts are now known from the source (section 5). | Choosing 80 columns and 64-column colour automatically | A manual setting (`set_picovideo`) |
| R4 | firmware / emulators | The 8251 at $73/$77 in `pico_host` (the plain-C 8251 from firmware step 2) with its UART on a TCP socket or a fake Zimodem | Testing in ZEsarUX/Fuse | Host tests only (section 12) |

**Open questions:**

- **Q1** PicoVideo detection (R3).
- **Q2** Receive pacing (R1). What rate the 64-column scroll can keep up with is measured in
  milestone M4.
- **Q5** In Hayes mode, should the card or the program turn on Zimodem's XON/XOFF (`ATF1`),
  so the card's XOFF is obeyed?
- **Q6** *(answered by the firmware session, 2026-10-14)*: `tpi:modem hayes` is saved, in
  `config.ini` (`MODEM_MODE`), so Hayes mode stays after PicoTerm quits. MTERM, which
  needs 2050 mode, then needs `SAVE "tpi:modem 2050"`. PicoTerm can't put the old mode
  back, because no command reports it. The manual tells the user. The 8251 emulation and
  the Zimodem bridge are on main (PRs #264-#273); Hayes mode was tested with a 2068 on
  2026-10-12.
- **Q7** Zimodem with `ATDT`:
  - Does it handle telnet IAC both ways in stream mode, so the link is 8-bit clean for
    XMODEM? *Answered on hardware, 2026-10-14:* yes. An FFh-heavy XMODEM download over
    `ATDT` arrived exact, with no NAKs.
  - Does it send NAWS (window size)? *Answered on hardware, 2026-10-14:* no. It answers
    DO NAWS with WONT, so a telnet host never learns the width. TTYPE works: it answers
    WILL, and its SB is the `AT&S"41=..."` string.

## 12. Testing

What exists after M2:

- **Host machine** (`tests/hostmachine.py`): PicoTerm's real binary on the `z80` package
  (kosarev, MIT).
  - It models RAM, the system variables PicoTerm reads, the keyboard matrix, the frame
    interrupt (IM2, bus FFh), DECR, and the 8251 and TS-Pico ports.
  - A made-up ROM font with a different glyph for every character lets the tests read the
    screen back from the bitmap.
- **Fakes** (`tests/fakes.py`):
  - the card's 8251 in Hayes mode: boot delay, pacing, injected errors, floating bus;
  - Zimodem: echo, verbose results, `ATDT` to a host table, stream mode, `+++` with its
    guard times, `ATH`;
  - a test BBS: greeting, echo, `bye`, `flood`;
  - the TS-Pico command protocol.
- **ZEsarUX** for the real keyboard scan and the bitmap, with local echo turned on.

The plan before M2:

- **Host tests (Python):** run assembled routines in a Python Z80 emulator, with a fake 8251
  and a fake TS-Pico (the firmware repo's `test_examples.py` simulates the Pico the same way).
  Covered:
  - the ANSI and VT52 parsers, by feeding byte streams and comparing the screen shadow;
  - CRC-16;
  - the XMODEM state machine against a scripted sender (good blocks, bad CRCs, duplicates,
    timeouts, CAN);
  - the line parser for result codes.
- **Emulator:** ZEsarUX-tspico with `pico_host`, for the display drivers, the keyboard, the
  menus and the SD files. Modem traffic needs R4.
- **Hardware:** the card with Zimodem, against a local Python telnet server (repeatable) and
  public BBSes. Checks:
  - scroll speed at each column mode and pacing rate;
  - XMODEM with `sz` / `lrzsz` on a Mac or Linux host;
  - PicoVideo on HDMI.

## 13. Milestones

1. **M0 Toolchain.** sjasmplus build, `mktap.py`, loader, "hello" in ZEsarUX.
2. **M1 Screen and keys.** ISR, keyboard map, 32-column driver with the shadow, TTY
   emulation, a local "typewriter".
3. **M2 Modem.** 8251 driver, ring buffer, a dumb terminal to Zimodem (`AT`, `ATI`,
   `ATDT"host:port"` by hand). Needs the firmware's step 2 on the card.
4. **M3 ANSI and VT52.** Parsers with host tests; colour.
5. **M4 64 and 80 columns.** The two drivers, the CP437 font, switching modes from the shadow,
   scroll timing.
6. **M5 Menus.** Phonebook, WiFi, dial and hang-up, status bar, settings, `picoterm.cfg`.
7. **M6 XMODEM download** to the SD card (R2, or the RAM fallback).
8. **Later:** YMODEM, upload, capture, scrollback, ANSI music.
