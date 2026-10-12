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

## 3. Memory map

| Address | Use |
|---|---|
| 0000-3FFF | ROM (HOME). Not called while PicoTerm runs. |
| 4000-57FF | DF1 bitmap (32/64 col). In 80 col: character codes 4000-477F, attributes 4780-4EFF. |
| 5800-5AFF | DF1 attributes (32 col; 64 col on PicoVideo mode 7, **to verify**) |
| 5B00-5FFF | System variables and TS-Pico ROM variables (TPMODE at 5DDBh). Left alone. |
| 6000-77FF | DF2 bitmap, used **only in 64-column mode**. On the 2068 this is also where BASIC lives: CHANS is at 6840h and PROG at 6856h (measured in M0), so 64-column mode saves 6000h..STKEND (about 2.2 KB) and puts it back before returning to BASIC or leaving 64 columns. |
| 7800-7AFF | DF2 attributes (PicoVideo mode 7, **to verify**) |
| 7B00-7FFF | Free / BASIC's machine stack below RAMTOP |
| 8000- | PicoTerm code, then data (below) |
| FC00-FCFF | Our stack |
| FD00-FE00 | IM2 vector table (257 bytes of FEh) |
| FEFE | IM2 handler entry (`JP isr`) |

The loader is `CLEAR 32767: LOAD "" CODE: RANDOMIZE USR 32768`. PicoTerm never calls the
ROM, so BASIC's data in the DF2 area only has to survive until exit, not be usable while the
program runs.

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

That fits in 8000h-FBFFh with room left for a small scrollback later.

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
    scld.asm        port FFh shadow (screen mode, hi-res colour; bits 6, 7 kept 0)
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
- **Back-pressure works without our own XON/XOFF.** If the display falls behind, the ring
  fills, the ISR stops reading, the card's 4 KB ring fills, and the card XOFFs Zimodem.
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
| Hardware | SCLD mode 0 | SCLD mode 6 (`OUT FF`, 6 + colour in bits 3-5) | PicoVideo mode 5 |
| Glyphs | 8x8 from our font, 8 bytes into DF1 | 8x8, even columns in DF1, odd in DF2 | One byte at 4000h + row x 80 + col |
| Colour | Per cell (Spectrum attributes) | One colour pair for the whole screen; per cell with PicoVideo mode 7 (**to verify** where its attributes live) | Per cell at 4780h (**to verify** the attribute format; assumed to be the Spectrum one) |
| Scroll one line | ~5.9 KB of LDI, about 27 ms | ~11.8 KB, about 54 ms | ~3.7 KB, about 17 ms |
| Cursor | XOR an underline | XOR an underline | Invert the cell's attribute |

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

**VT52**: `ESC A B C D H I J K Y r c Z` (identify, answered with `ESC / K`) and `F G`
(graphics mode), the subset MTERM's table handled plus the rest of the standard set.

**TTY**: printable characters and the C0 controls above, nothing else.

**Width.** In 32 and 64 columns, text wraps at the right edge. Most BBSes ask for the screen
size, or detect it with `6n`. Zimodem's telnet terminal type is set with
`AT&S"41=ANSI"` (or `VT52`); NAWS (telnet window size) is open question Q7.

## 7. Modem

### Start-up

1. If the TS-Pico ROM is 2.3 or later (`PEEK 101` >= 35), send `tpi:modem hayes` and
   `tpi:modem on` through the TS-Pico protocol. A "C" (unknown command) answer means older
   firmware: carry on and hope it's already in Hayes mode, and say so on the status bar.
2. Reset the 8251: `00 00 00 40`, mode `4F`, command `37`.
3. Wait up to 5 s for TxRDY (the ESP32 starts up).
4. Send `AT` CR; expect `OK` within 2 s. If there's no answer, open the terminal anyway in
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

The menu holds:

- Dial (the phonebook);
- Hang up;
- WiFi;
- Download (XMODEM);
- Settings: emulation, columns, PicoVideo, translations, colours, init string;
- Clear screen;
- Send break;
- Exit to BASIC.

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

## 10. Settings file

`picoterm.cfg` lives in the SD card's current folder and is written in text mode. It holds
`key=value` lines plus one `phone=` line per entry. Text mode is safe here because the file is
plain ASCII, with no 17h bytes and no tokens. It's read at start-up and written from the
Settings and phonebook screens. If it's missing, the defaults are 32 columns, ANSI, no
PicoVideo, and an empty phonebook.

## 11. What we need from other projects

| # | From | Request | Why | Until then |
|---|---|---|---|---|
| R1 | firmware | Set the receive pacing at run time: e.g. `tpi:modem baud <n>` (with 0 = unpaced) | 300 baud makes downloads and 80-column BBS screens slow | The user edits `MODEM_BAUD` in `config.ini` |
| R2 | firmware | A binary-safe channel write: e.g. a mode flag that turns off the 17h TAB escape, or a `tpi:chwrb` | XMODEM to a plain file | RAM buffer + `f:` CODE with a +3DOS header |
| R3 | PicoVideo | A way to detect the board (a readable ID register); the mode 5 and mode 7 attribute layouts | Automatic 80/64-column choice; colour | A manual setting |
| R4 | firmware / emulators | The 8251 at $73/$77 in `pico_host` (the plain-C 8251 from firmware step 2) with its UART on a TCP socket or a fake Zimodem | Testing in ZEsarUX/Fuse | Host tests only (section 12) |

**Open questions:**

- **Q1** PicoVideo detection (R3).
- **Q2** Receive pacing (R1). What rate the 64-column scroll can keep up with is measured in
  milestone M4.
- **Q5** In Hayes mode, should the card or the program turn on Zimodem's XON/XOFF (`ATF1`),
  so the card's XOFF is obeyed?
- **Q6** Is `tpi:modem hayes` saved, or only for the session? Should PicoTerm put the
  previous mode back on exit?
- **Q7** Zimodem with `ATDT`:
  - Does it handle telnet IAC both ways in stream mode, so the link is 8-bit clean for
    XMODEM?
  - Does it send NAWS (window size)?

## 12. Testing

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
