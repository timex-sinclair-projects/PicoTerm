# PicoTerm

A terminal program for the Timex/Sinclair 2068 and the TS-Pico v3 card, whose ESP32 runs
Zimodem. It talks to the card's 8251 at ports $73/$77 as a Hayes modem over WiFi, with 32-
and 64-column displays, PicoVideo's 80 columns, ANSI-BBS/VT52/TTY emulation and XMODEM
downloads to the TS-Pico's SD card.

The plan is [docs/DESIGN.md](docs/DESIGN.md). Status: **M2**, a plain terminal:
- at start-up it puts the card's modem in Hayes mode and checks that Zimodem answers;
- keys go to the 8251, and received text goes to the TTY emulation on the 32-column
  screen;
- BREAK hangs up if connected, then returns to BASIC.

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

It runs in under a second.

`tests/test_tap.py` checks the TAP. The emulator tests run PicoTerm in a headless ZEsarUX
TS-2068 over ZRCP, and are skipped if ZEsarUX isn't installed:
- `test_startup.py` covers start-up and the return to BASIC.
- `test_typewriter.py` covers the keyboard, the TTY emulation and the screen. It presses keys
  on the emulated matrix, and checks the screen both in memory and through ZEsarUX's OCR. Set `$ZESARUX` to the binary,
and `$ZESARUX_ROM` to use another ROM such as `TSPICO-23.ROM`.
