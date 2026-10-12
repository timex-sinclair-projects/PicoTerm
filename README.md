# PicoTerm

A terminal program for the Timex/Sinclair 2068 and the TS-Pico v3 card, whose ESP32 runs
Zimodem. It talks to the card's 8251 at ports $73/$77 as a Hayes modem over WiFi, with 32-
and 64-column displays, PicoVideo's 80 columns, ANSI-BBS/VT52/TTY emulation and XMODEM
downloads to the TS-Pico's SD card.

The plan is [docs/DESIGN.md](docs/DESIGN.md). Status: **M0** (toolchain and a start-up
test program).

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
make test
```

`tests/test_tap.py` checks the TAP. `tests/test_emulator.py` runs it in a headless ZEsarUX
TS-2068 over ZRCP and is skipped if ZEsarUX isn't installed. Set `$ZESARUX` to the binary,
and `$ZESARUX_ROM` to use another ROM such as `TSPICO-23.ROM`.
