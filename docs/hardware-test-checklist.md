# PicoTerm hardware test checklist

PicoTerm has only been tested on a host model of the 2068 with fake devices, and in
ZEsarUX, which has no 8251. This list is for its first runs on a real TS-2068 with the
TS-Pico v3 card.

**How to use it:**
- Work through it in order: the early sections are the ones most likely to fail and the
  ones everything after depends on.
- Check off each box, and write down anything unexpected next to the item.
- An item marked **(Q5)** or **(Q7)** answers an open question in `docs/DESIGN.md`
  section 11. Record what you see even if it "fails".

## 0. Record the setup

| | |
|---|---|
| Date | |
| TS-2068 (model, 50/60 Hz) | |
| TS-Pico ROM (`PRINT PEEK 101`: 35 = 2.3) | |
| TS-Pico firmware (`SAVE "tpi:info"`) | |
| Zimodem version (`ATI`) | |
| `config.ini`: `MODEM_MODE`, `MODEM_BAUD` | |
| PicoVideo version, if fitted | |
| PicoTerm commit (`git log -1 --format=%h`) | |
| Display: TV / composite monitor / PicoVideo VGA | |

## 1. Before you start

- [ ] **Build PicoTerm:** `make` and `make test` pass. Copy `build/picoterm.tap` to the SD
  card's `/TAP` folder.
- [ ] **The card's firmware** is current `main`: the 8251 emulation and the Zimodem
  bridge merged as tspico-firmware-build #264-#273. Hayes mode was tested with a 2068 on
  2026-10-12.
- [ ] **Hayes mode:** nothing to do. PicoTerm sends `tpi:modem hayes` at start-up.
  `tpi:modem` takes exactly `2050`, `hayes` or `off`, and the firmware **saves** the
  mode in `config.ini` (`MODEM_MODE`), so it stays in Hayes mode afterwards (see 10.5).
  Note what `MODEM_MODE` was before you start: _______
- [ ] **Pacing:** for the first runs, leave `MODEM_BAUD` at its default (300). Section 7
  raises it.
- [ ] **Test server:** on a computer on the same network, run
  `python3 tools/test_bbs.py`. It listens on **2323 (raw TCP)** and **2324 (telnet)**,
  and logs every byte both ways in hex. Note the computer's IP address: _______________
  - **The port decides** whether the server speaks raw TCP or telnet, whatever you dial
    it with. `ATD` or `ATDT` only changes what Zimodem does. So use `ATDX` with 2323 and
    `ATDTX` with 2324: dialing 2323 with `ATDT` (or 2324 with `ATD`) gives confusing
    results.
  - **Add the `X`** to a dial you type yourself. With flow control on, Zimodem obeys the
    card's XOFF/XON only on a call dialed with X; without it they reach the server as
    data, and a fast flood can lose text. The phonebook adds the X itself.
- [ ] **Phonebook:** for the later sections, have a `picoterm.cfg` on the SD card with two
  entries for the server:

  ```
  phone=Test raw|<ip>:2323|0|2|0|8|0
  phone=Test telnet|<ip>:2324|1|2|0|8|0
  ```

  Or make them by hand in section 6.

## 2. Loading and start-up

The first things never run on real hardware: the ROM's `CHNG_VID` under the TS-Pico ROM,
the IM2 interrupt with the card on the bus, and the 8251.

- [ ] **2.1 Load:** `LOAD "tpi:picoterm.tap"`, then `LOAD ""`. The loader runs, and
  PicoTerm's banner "PicoTerm 0.6" appears in 32 columns, white on black.
  - If it crashes or hangs before the banner, suspect `CHNG_VID` (EXROM 0E8Eh) on the
    TS-Pico ROM. Note what's on screen.
- [ ] **2.2 Display file moved:** after quitting (section 10) check `PRINT PEEK 23746`:
  128 (VIDMOD). `PRINT PEEK 23631+256*PEEK 23632`: 31488 (CHANS at 7B00h).
- [ ] **2.3 Start-up exchange.** The screen shows, in order:
  - the card's answer to `tpi:modem hayes`, if VERBOSE is on (and no "Use 2050, hayes
    or off": that would mean an old PicoTerm that still sends `tpi:modem on`);
  - `AT`, `OK`, `ATE1V1X1Q0`, `OK`, `AT&S"41=ANSI"`, `OK`;
  - `Modem ready.`
- [ ] **2.4 Timing:** start-up to `Modem ready.` takes about _____ s (expected 2-5 s,
  longer while Zimodem joins WiFi). PicoTerm sends `AT` once a second for about 12 s: the
  card only connects Zimodem 2 s after the first 8251 write, and earlier `AT`s are lost.
  You may see Zimodem's banner before the `AT` that gets an `OK`.
- [ ] **2.5 The cursor** is an underline that blinks about once a second, and shows
  steadily while you type.
- [ ] **2.6 Typing:** type `AT` and press `ENTER`. Zimodem echoes `AT` and answers `OK`.
- [ ] **2.7 Older firmware** (if available): with firmware that has no `tpi:modem`, you
  see "This TS-Pico has no tpi:modem." and start-up carries on.
- [ ] **2.8 No modem:** with the ESP32 not answering (Zimodem not flashed, or the module
  removed): "No modem: the 8251 isn't ready." or "No answer from the modem." after
  about 5 s. `tpi:modem off` before loading doesn't test this: PicoTerm switches the
  modem back to Hayes. Keys don't hang the program, and BREAK, then Q, still quits.
- [ ] **2.9 TS2050 mode** (only with firmware that has no `tpi:modem`, if available): with
  `MODEM_MODE=2050`, "No answer from the modem." after about 3 s. The card hides
  Zimodem's replies in that mode, and PicoTerm can't switch it.
- [ ] **2.10 No card:** on a 2068 without the v3 card, if one is available: "No modem",
  and **no rubbish on screen**. This checks the floating-bus (FFh) handling.

## 3. The keyboard

PicoTerm's key map follows the Spectrum's symbol legends; the 2068's own keyboard has
never been checked against it. Use local echo: Settings (BREAK, S), then L, then BREAK
twice. Then type into the terminal with no connection.

- [ ] **3.1** Letters, digits, `SPACE`, and CAPS SHIFT for capitals.
- [ ] **3.2** SYMBOL SHIFT with each key gives the character in the manual's table
  (section 4). Note any key whose 2068 legend differs from what PicoTerm sends:

  `~ | \ { } ^ [ ] ` : ? / < > ; " - + = * , . ! @ # $ % & ' ( ) _`
- [ ] **3.3** SYM with Q, W, E or I sends nothing.
- [ ] **3.4 CAPS with digits:**
  - CAPS+0 rubs out;
  - CAPS+3 tabs to the next multiple of 8;
  - CAPS+2 locks capitals for letters only.
- [ ] **3.5 Repeat:** holding a key repeats after about half a second. Pressing or
  releasing CAPS while a key is held doesn't type it again.
- [ ] **3.6 Ctrl:** CAPS+SYM together, let go, then L clears the screen (Ctrl-L is FF).
  CAPS+SYM twice cancels it.
- [ ] **3.7 BREAK** (CAPS+SPACE) opens the menu, and BREAK again closes it.
- [ ] **3.8 Ghosting:** typing fast with shifts gives no stray characters.

## 4. A call, raw and telnet

- [ ] **4.1 WiFi** (if Zimodem isn't on your network yet): section 8 first.
- [ ] **4.2 Raw call by hand:** type `ATDX"<ip>:2323"` (`ATD` with the raw port) and press
  ENTER. You get `CONNECT …`
  and the server's welcome and menu. The server's log shows the connection.
- [ ] **4.3 Echo:** press E, type a line, press ENTER. It comes back once, not twice.
  Type `.` and ENTER to leave.
- [ ] **4.4 Backspace:** in echo, CAPS+0. The server's log shows 08h (or 7Fh if you
  chose DEL).
- [ ] **4.5 Arrows:** CAPS+5 to 8 show in the server's log as `1b 5b 44`, `42`, `41`, `43`.
- [ ] **4.6 Remote hang-up:** press Q at the server's menu. `NO CARRIER` appears, and
  PicoTerm's menu (BREAK) says "Offline".
- [ ] **4.7 Local hang-up:** reconnect, then BREAK, then H. About a second of silence,
  `+++` in the server's log, another second, then `OK`, then `ATH` and `OK`. The server
  sees the connection close. The `+++` reaches the host as data before Zimodem acts on it:
  the test server redraws its menu once for each `+`. That's normal Hayes behavior.
  - **(timing)** If Zimodem misses the escape, note whether the machine is 50 or 60 Hz:
    the guard is 66 ticks.
- [ ] **4.8 Telnet call:** type `ATDTX"<ip>:2324"` (`ATDT` with the telnet port) and press
  ENTER, then press T at the menu.
  - [ ] **Terminal type** shown: _______ (expected `ANSI`; this checks `AT&S"41=ANSI"`).
  - [ ] **(Q7) Window size** shown: _______. `None` means Zimodem doesn't send NAWS: board
    1, 2026-10-14, answered DO NAWS with WONT.
- [ ] **4.9 Quit while online:** BREAK, then Q, hangs up first (as 4.7), then returns
  to BASIC with `0 OK`.

## 5. Emulation and display

Use the test server's screens. Then try one or two real BBSes.

- [ ] **5.1 ANSI (A):**
  - [ ] colors for foreground, bold and background;
  - [ ] reverse;
  - [ ] blink (FLASH);
  - [ ] the CP437 box;
  - [ ] "CUP 12;10" at row 12, column 10;
  - [ ] the line cut by EL (`01234 <- EL from col 6`);
  - [ ] "abcde  fgh" (two spaces inserted before the f);
  - [ ] the scroll region confined to rows 20-22;
  - [ ] "End of ANSI test" on the bottom row.
- [ ] **5.2 VT52 (V):** set VT52 first (Settings, E, until VT52, then reconnect).
  - [ ] the text at row 5, column 10;
  - [ ] the line erased after the cursor;
  - [ ] "<here" two rows up.
- [ ] **5.3 CP437 (C):** rows 80h to F0h show the PC graphics characters, the same in 32
  and 64 columns as in PicoVideo's 80.
- [ ] **5.4 Cursor report (P):** shows `ESC[24;32R` in 32 columns, `;64R` in 64, and
  `;80R` in 80.
- [ ] **5.5 Bell:** a BEL from the host (e.g. Ctrl-G echoed back in E) gives a short
  1 kHz beep from the AY. Off when Settings G is No.
- [ ] **5.6 64 columns (CAPS+9):** the screen keeps its text, in the 64-column ink from
  Settings I.
  - [ ] Readable on your display? _____
  - [ ] Settings I changes the color pair.
- [ ] **5.7 PicoVideo** (if fitted): Settings, P, Yes.
  - [ ] **64 columns in color:** CAPS+9 gives DECR mode 7, and ANSI colors show per
    character.
  - [ ] **80 columns:** CAPS+9 again gives PicoVideo's text mode on VGA. The colors
    match 32 columns, and the cursor is a reversed cell.
  - [ ] **Back to 32:** CAPS+9 returns to 32 with the text intact.
- [ ] **5.8 A real BBS** in ANSI, 32 and 64 columns. Name: _______________. Note anything
  drawn wrong.

## 6. Menu, phonebook and settings

- [ ] **6.1** The menu draws without leftovers, and closing it restores the screen
  exactly.
- [ ] **6.2 Text waits while the menu is open:** in the server's F (flood), open the menu
  at once, wait 5 s, and close it. The flood carries on from where it was, with no lines
  missing.
- [ ] **6.3 Phonebook:**
  - [ ] N makes a new entry, with the name and host typed in.
  - [ ] E edits it, and T/E/C/B/L change its settings.
  - [ ] ENTER dials it: `AT&S"41=…"`, then `ATDT"…"` (or `ATD`), then CONNECT.
  - [ ] The entry's column mode and emulation take effect.
- [ ] **6.4 Dialing while online** says "Hang up first."
- [ ] **6.5 Save** (Settings, S): "Saved to picoterm.cfg." Check the file on a PC: plain
  text, the keys as in the manual, one `phone=` line per entry.
- [ ] **6.6 Reload:** reset, load PicoTerm again. The settings and phonebook come back,
  and it starts in the saved column mode.
- [ ] **6.7 A bad line:** add a nonsense line to `picoterm.cfg` on a PC. PicoTerm still
  starts, and the other settings load.
- [ ] **6.8 Init string:** Settings M, change it to `ATE1V1X1Q0S0=0`, save, and reload.
  The new string is sent at start-up.

## 7. Receiving at speed (Q5)

- [ ] **7.1 At 300 baud:** the flood (F) arrives at about 30 characters a second. Every
  line is there, in order.
- [ ] **7.2 Faster:** set `MODEM_BAUD=2400` in `config.ini` (or `0`, as fast as it's
  read) and restart the card. Dial with the X (`ATDX`/`ATDTX`, or the phonebook). Run the
  flood again:
  - [ ] all 200 lines arrive, numbered 000-199, none missing or doubled, in 32 columns;
  - [ ] the same in 64 columns (the slowest scroll).
  - **(Q5)** Needs firmware with `tpi:modem flow` (#301): PicoTerm turns it on at
    start-up. `SAVE "tpi:modem"` after quitting says `Flow off` (quit turns it off); during
    the run, `tsbus.stats()`'s `m_rx_lost` should stay 0 and `m_xoff` shows the card
    pausing Zimodem. Without #301, lines go missing at `0` in 64 columns (board 1,
    2026-10-14: 9,798 bytes lost).
- [ ] **7.3 Rate:** the server times the flood: after the last line it asks for the cursor
  position, and PicoTerm answers only once everything before it is on screen. It shows
  "Flood displayed in _ s" and logs `FLOOD: …`. At `MODEM_BAUD=0`: 32 columns _____ s,
  64 columns _____ s, 80 columns _____ s. The host model, at 3.5 MHz with no contention, takes
  about 35 s in 32 columns, 35 s in 64 and 19 s in 80 (290, 295 and 525 characters a
  second). A much slower result on hardware is worth noting.

## 8. WiFi

- [ ] **8.1 Scan:** BREAK, then W, offline. Networks are listed, and names with spaces
  are shown in full.
- [ ] **8.2 Join:** choose your network, type the password (shown as stars), and press
  ENTER. You're asked "Joined. Make it default? Y/N".
- [ ] **8.3 Save:** Y. "Saved in the modem." After a card reset, Zimodem rejoins by
  itself (`ATI`).
- [ ] **8.4 Wrong password:** "Couldn't join that network."
- [ ] **8.5 Hidden network:** M, type the name, then the password.
- [ ] **8.6 While online:** "Hang up first."
- [ ] **8.7 Zimodem's scan format:** if the list looks wrong, note one raw `ATW` line,
  typed by hand: _______________

## 9. XMODEM downloads

On the raw port first (2323), then telnet (2324). For each, press the digit at the
server's menu, then BREAK, then X, then ENTER.

**Run this section with `MODEM_BAUD=0`** (section 7.2). At the default 300 baud a
128-byte block takes over 4 s to reach the 2068, so the transfers take a long time:
- 9.1, 3,000 bytes: about 2 minutes;
- 9.4, 6,912 bytes: about 4 minutes;
- 9.6, 6,144 bytes in 1K blocks: about 3.5 minutes.

The test server waits as long as PicoTerm keeps answering, and gives up after 60 s of
silence.

- [ ] **9.1 (1) 3000 bytes, CRC:** completes with Blk 24, and you're asked about
  padding.
  - [ ] N: "Saved: 3072 bytes."
  - [ ] The file on the SD card is 3,200 bytes: a 128-byte `PLUS3DOS` header, then the
    data.
  - [ ] **Its data matches:** with the server's `sample(3000)` and 72 bytes of 1Ah after
    it.
- [ ] **9.2 Load it back:** `LOAD "f:download.bin" CODE 40000` on the 2068 gives `0 OK`.
- [ ] **9.3 Replace:** download again to the same name. PicoTerm asks "Replace that
  file?". Y replaces it **without a second question from the TS-Pico**: this checks that
  PicoTerm answers the card's 88h prompt.
- [ ] **9.4 (2) 6912 bytes:** the largest that fits. Saved.
- [ ] **9.5 (3) 8000 bytes:** "Too big for memory (6912)." The server's log shows CAN x 5.
- [ ] **9.6 (4) 1K blocks:** saved, 6144 bytes.
- [ ] **9.7 (5) Checksum only:** PicoTerm falls back after three C's. Saved.
- [ ] **9.8 (6) FFh-heavy, raw port:** saved, and the data is exact.
- [ ] **9.9 (6) FFh-heavy, telnet port (Q7):** saved and exact? _____ Board 1 (2026-10-14):
  exact, 0 NAKs, so Zimodem undoubles IAC in stream mode. If a later Zimodem fails here,
  the errors count up and it ends "Too many errors".
- [ ] **9.10 Cancel:** press BREAK early in a transfer, within the first few blocks (at the
  very end, PicoTerm's last ACK can arrive with the CANs). BREAK gives "Canceled.", the server's log shows
  CAN x 5, and the server says "XMODEM canceled".
- [ ] **9.11 In 64 columns:** start in 64 columns. PicoTerm drops to 32 during the
  transfer and returns to 64 after.
- [ ] **9.12 The SAVE itself:** note how long "Saving..." takes: _____ s.
  - If it fails with "Couldn't save the file", note the TS-Pico's message with VERBOSE
    on. The SAVE protocol (pre-header, header block, mid status, data block) has only
    been checked against a model of the firmware.
- [ ] **9.13 Speed at MODEM_BAUD=0:** 6912 bytes take _____ s (the host model managed
  about 4.4 s).

## 10. Back to BASIC

- [ ] **10.1** BREAK, then Q, gives `0 OK`, the normal screen in BASIC's colors, and the
  border restored.
- [ ] **10.2 BASIC works:** `PRINT 2+2`, enter and `LIST` a short program, `SAVE` and
  `LOAD` it through the TS-Pico.
- [ ] **10.3 Run PicoTerm again** with `RANDOMIZE USR 34816`: it starts without opening
  the display file a second time (VIDMOD is already 128), and works.
- [ ] **10.4 After a quit from 64 or 80 columns,** the 2068's screen is back to normal
  (DECR mode 0).
- [ ] **10.5 The modem stays in Hayes mode:** `config.ini` now has `MODEM_MODE=hayes`.
  MTERM needs `SAVE "tpi:modem 2050"` first. Put back the mode you noted in section 1.

## 11. Results

| Section | Pass | Notes |
|---|---|---|
| 2 Start-up | | |
| 3 Keyboard | | |
| 4 Calls | | |
| 5 Display | | |
| 6 Menus | | |
| 7 Speed | | |
| 8 WiFi | | |
| 9 XMODEM | | |
| 10 BASIC | | |

**Open questions answered:**
- **Q5:** flood at `MODEM_BAUD=0` with flow control (#301), 64 columns: __________
- **Q7:** NAWS __________; telnet FFh in XMODEM __________
- **Key legends that differ:** __________

When something fails, keep the test server's log: it has every byte both ways.
