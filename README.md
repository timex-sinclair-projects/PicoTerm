# PicoTerm

A terminal program for the Timex/Sinclair 2068 and the TS-Pico v3 card, whose ESP32 runs
Zimodem. It talks to the card's 8251 at ports $73/$77 as a Hayes modem over WiFi, with 32-
and 64-column displays, PicoVideo's 80 columns, ANSI-BBS/VT52/TTY emulation and XMODEM
downloads to the TS-Pico's SD card.

The plan is [docs/DESIGN.md](docs/DESIGN.md). Status: **M5**, a terminal on the card's 8251:
- ANSI-BBS emulation (the default), with colour, VT52 or TTY;
- the CP437 character set;
- 32 or 64 columns, or 80 with PicoVideo;
- the bell on the AY;
- **BREAK opens the menu:**
  - a phonebook of 20 hosts, each with its own settings;
  - WiFi: scan, join, and save as the modem's default;
  - settings;
  - hang up, clear the screen, quit to BASIC;
- settings and the phonebook are saved in `picoterm.cfg` on the TS-Pico's SD card;
- at start-up it puts the card's modem in Hayes mode, checks that Zimodem answers, and
  sets the telnet terminal type.

Still to come: XMODEM.

## Building

Needs [sjasmplus](https://github.com/z00m128/sjasmplus) (1.20 or later) and Python 3.

```bash
make
```

The output is `build/picoterm.tap` (a BASIC loader and the code at 8800h), plus
`build/picoterm.bin`, `.sym` and `.lst`.

## Running

Copy `picoterm.tap` to the SD card's `/TAP` folder, then on the 2068:

```basic
LOAD "tpi:picoterm.tap"
LOAD ""
```

Or open the TAP in an emulator set to a TS-2068.

## Tests

```bash
make venv
```

```bash
make test
```

`make venv` installs the [`z80`](https://pypi.org/project/z80/) emulator package into
`.venv` for the host tests. Without it those tests are skipped.

`tests/test_modem.py` runs PicoTerm's binary on a host model of the 2068
(`tests/hostmachine.py`), against fake devices (`tests/fakes.py`):
- a fake 8251, with the ESP32's start-up delay, pacing, injected errors and a missing card;
- a fake Zimodem, with echo, result codes, `ATDT`, the `+++` guard times and a small test
  BBS;
- a fake TS-Pico, with its command protocol.

`tests/test_ansi.py` does the same for the ANSI, VT52 and TTY emulations. It checks the
characters and attributes both in memory and in the bitmap.

All of it runs in about a second.

`tests/test_modes.py` covers the three column modes, switching between them, and the
font.

`tests/test_menus.py` covers the menu, settings, `picoterm.cfg`, the phonebook and
WiFi. In these tests the fake TS-Pico keeps files, and the fake Zimodem scans and joins
networks.

To see what PicoTerm draws, render sample screens. The PNGs go to `build/`: the start-up
screen, an ANSI menu, a box-drawn menu in 32 columns, 64 (SCLD and PicoVideo) and 80, and
PicoTerm's own menu, phonebook, entry, settings and WiFi screens.

```bash
.venv/bin/python tools/demo_screens.py
```

## Credits

The CP437 font (`src/video/cp437.asm`) is the one PicoVideo uses for its 80-column mode:
Bm437_ACM_VGA_8x8 from VileR's [Ultimate Oldschool PC Font
Pack](https://int10h.org/oldschool-pc-fonts/), licensed CC BY-SA 4.0.
