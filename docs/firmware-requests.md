# Requests for the TS-Pico firmware

PicoTerm is a terminal program for the TS-2068 with the v3 card's modem. It needs two
small additions to the firmware. Each section below is written to stand on its own as an
issue for `tspico-firmware-build`.

Both are needed for the same thing: downloading files. PicoTerm receives XMODEM today, but
each change removes a limit. Neither changes what existing programs see.

---

## R1: let a program set the modem's receive pacing (`tpi:modem baud`)

Filed as timex-sinclair-projects/tspico-firmware-build#298.

### The problem

The v3 modem delivers received bytes to the 2068 no faster than `MODEM_BAUD`, as the v3
modem proposal (PR #264) sets out: RxRDY comes up no sooner than one character time after
the last. That's right for MTERM, which expects a 300-baud TS2050. It's wrong for a
program that can go faster, and the only way to change it today is to edit `config.ini`.

PicoTerm can take about 1,500-1,800 bytes a second with XMODEM, measured in its host
tests at 3.5 MHz. At the default 300 baud it gets 30. A 6.9 KB download takes about
4 minutes instead of about 5 seconds. Text is slow too: an 80-column BBS screen is about
2 KB, which takes over a minute.

### The request

A command that sets the pacing for the current session:

```
SAVE "tpi:modem baud 2400"
SAVE "tpi:modem baud 0"
```

- **The argument** is a rate in baud: the same values `MODEM_BAUD` takes, or `0` for "as
  fast as the 2068 reads". Anything else gets Report Q (status 4).
- **Its effect** is on how fast RxRDY comes up, and nothing else. The link to Zimodem, its
  ring and DMA don't change.
- **It lasts** until the card is reset or the modem is powered off, and then `MODEM_BAUD`
  applies again. It doesn't write `config.ini`. A program that changes it shouldn't change
  the user's saved choice for MTERM. If you'd rather it persisted, a separate `tpi:modem
  baud save` would cover that.
- **The answer** is a bare status 1, or a message with VERBOSE on, like the other
  `tpi:modem` commands. `SAVE "tpi:modem"` should show the rate in force.

From machine code it's an ordinary command (Programmer's Manual chapter 4), so nothing new
is needed on the 2068 side.

### The flow control it depends on (Q5)

Unpaced, the 2068 may read more slowly than Zimodem sends. The card's 4 KB ring and its
XOFF to Zimodem then carry the load, as the proposal says. In Hayes mode, though, the card
only sends `ATE1V1` on switching. Zimodem acts on XON/XOFF only with `ATF1` (or `AT&K4`),
and the factory default is off. Two possible answers:

- The card sends `ATF1` when it switches to Hayes mode, as it does in 2050 mode, or when the
  rate is set above 300. PicoTerm would prefer this, because the card owns the XOFF.
- Or the program sends `ATF1` itself. Then the documentation should say so, because
  without it the ring overflows silently.

### How PicoTerm will use it

At start-up, after `tpi:modem hayes`, PicoTerm will send `tpi:modem baud 0`, or a rate
from its settings. Older firmware answers "Unrecognized command" (C).
PicoTerm then carries on at the configured rate and says so, as it already does for
`tpi:modem` itself.

### Tests

These can go with the 8251 host test from the proposal's step 2:
- **Pacing:** at 300, RxRDY comes up no sooner than 33 ms after the last read. At 0,
  RxRDY is up whenever the ring has a byte. Changing the rate in the middle of a stream
  takes effect from the next byte.
- **Reset:** after a modem power-off or a card reset, the rate is `MODEM_BAUD` again.
- **Bad values:** `tpi:modem baud x` and an unsupported rate give Q, and leave the rate
  unchanged.

---

## R2: a binary-safe channel write (`tpi:chwrb`)

Filed as timex-sinclair-projects/tspico-firmware-build#299.

### The problem

A program can't write a binary file to the SD card through the channel commands. In a
`tpi:chwr`, byte 17h always starts a TAB: `17h, n lo, n hi` is a seek, in text mode and
in binary (`b`) mode alike (Programmer's Manual 5.3 and 6.3). Any binary file containing
17h is changed on the way to the card. Most binary files contain 17h.

The manual's advice is to use `SAVE "f:..." CODE` instead, and that's what PicoTerm does
for now: it speaks the SAVE protocol itself, with `tpi:fopen`, the header block, and then
the data block. That has three costs:

- **Size:** the whole file has to be in the 2068's memory first. For PicoTerm that's
  6,912 bytes at most.
- **The header:** the file gets a 128-byte +3DOS header. That's right for a 2068 CODE
  file, but wrong for a download (a `.zip`, a `.tap`, a text file), which has to be cut
  on a PC first.
- **Format:** the file can't be written as it arrives.

### The request

A new command, `tpi:chwrb`, that writes its bytes exactly as given:

| Text | PMR1 | PMR2 | Answer |
|---|---|---|---|
| `tpi:chwrb <hex>` | stream | 0 | a bare status, as `tpi:chwr` |

- **It's `tpi:chwr` without the escapes.** The same hex body and the same stream, but no
  TAB escape, no text-mode translation of CR, and no keyword spelling. Every byte is
  written as it is, at the channel's current position.
- **Errors** are as for `tpi:chwr`: a stream that isn't open, or isn't open for writing,
  gets the same status `tpi:chwr` gives.
- **Seeking** still works through `tpi:chwr 17xxxx`, so a program can mix the two.
- **`tpi:chwr` is unchanged.** `PRINT #` and `LIST #` keep their behavior, and nothing
  that works today changes. A mode letter (say `tpi:chopen wx`) would also do. A separate
  command seems simpler to add and to document, and it can't change `PRINT #` by
  accident.

**Optional, but it helps throughput:** state the largest command body this command
(and `tpi:chwr`) is tested with. The manual advises staying under 256 bytes, which is 120
data bytes as hex. That's nine transactions for each 1 KB XMODEM block. If 1 KB or 2 KB
bodies are fine, PicoTerm can write a block in one or two.

### How PicoTerm will use it

1. `tpi:chopen wb <path>`.
2. One `tpi:chwrb` for each XMODEM block, sent after the block's CRC has checked out and
   before it's ACKed, so the sender waits while the card writes.
3. `tpi:chclose`.

On the card that gives a plain file, byte for byte what the BBS sent, of any size. On
older firmware the first `tpi:chwrb` answers "Unrecognized command" (C), and PicoTerm uses
the RAM-and-SAVE method it has now.

### Tests

These can go with the channel tests in `disk_cmds_hosttest.py`:
- **Every byte value:** `tpi:chopen wb`, then `tpi:chwrb` of all 256 byte values (17h,
  0Dh, 0Ah and 80h-FFh included), then `tpi:chclose`. The file is exactly those 256 bytes.
- **Text mode:** `tpi:chwrb` on a stream opened `w` (text) still writes bytes unchanged.
- **Mixed with seeks:** a `tpi:chwr 17xxxx` seek, then a `tpi:chwrb`, writes at the seek
  position.
- **Errors:** a stream that isn't open, or is open `r`, gets the same status as
  `tpi:chwr`.
- **Odd input:** an odd number of hex digits, or a non-hex character, gets the same status
  as `tpi:chwr` gives for the same body.
