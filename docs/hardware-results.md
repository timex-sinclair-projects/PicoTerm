# Hardware results

Runs of `docs/hardware-test-checklist.md` on real hardware. The newest are first.

## Board 1, 2026-10-14

- **Hardware:** TS-2068 with the TS-Pico v3 card, proto1 board 1.
- **Firmware:** tspico-firmware-build `fd7bc5d`.
- **PicoTerm:** `ca723dc`, then `fd42ce7` for the start-up fix.
- **Test server:** `tools/test_bbs.py`, then `cdeaf98`.
- **Run by:** David, with the firmware session.

| Item | Result |
|---|---|
| 2.2 Display file moved | Pass: VIDMOD 128, CHANS 31488 |
| 2.3/2.4 Start-up | **Failed, then fixed.** "No answer from the modem", then Zimodem's banner. The card connects the line 2 s after the first 8251 write and drops what comes before, and Zimodem took longer (joining WiFi), so the one `AT` was lost. `fd42ce7` asks once a second for about 12 s. Pass on a cold start, showing several `AT`/`OK` pairs, then the init strings. |
| 4.2 Raw call | Pass |
| 4.3 Echo | Pass: once only |
| 4.4 Backspace | Pass: 08h |
| 4.5 Arrows | Pass: `1b 5b 44`, `42`, `41`, `43` |
| 4.6 Remote hang-up | Pass |
| 4.7 Local hang-up | Pass. The `+++` reaches the host as data first (normal Hayes behaviour), then OK, ATH, OK, and the connection closes |
| 4.8 Telnet | Pass. TTYPE: WILL, SB is "ANSI". NAWS: Zimodem answers WONT, so a host never gets the window size (Q7) |
| 4.9 Quit while online | Pass: hangs up, then 0 OK |
| 5.1 ANSI screen | Pass |
| 5.3 CP437 chart | Pass |
| 5.4 Cursor report | Pass |
| 7.1 Flood at 300 baud | Pass: all 200 lines, in order |
| 7.2 Flood at MODEM_BAUD=0 (Q5) | **Fail: data lost.** In 32 columns one run looked complete. In 64 columns characters went missing around line 86 on one run and line 60 on the next (one run took 21 s). The card's counters: `m_rx_lost` 9798 of `m_rx` 32623, because the DMA lapped its 4 KB `line_rx` ring. In Hayes mode the card never sends XOFF: `modem2050.c` does XOFF/XON only `if (!hayes && state == CONNECTED)`, because in Hayes mode Zimodem's settings are the user's. So at `MODEM_BAUD=0` nothing paces Zimodem. XMODEM is unaffected, since the receiver paces it. |
| 7.3 Display rate | "Under 2 minutes" in 32 columns (an estimate: about 90 characters a second). The host model takes about 35 s (290 characters a second). To be timed with the server's new flood timer. |
| Start-up drain (`5cf5987`) | Pass: one `AT`/`OK` on a cold start |
| 9.1 XMODEM 3,000 bytes, CRC | Pass. 24 blocks, 8.8 s, 0 NAKs. 3,200-byte file: PLUS3DOS header (CODE, 3,072 bytes, 32768, checksum good), then the data and 72 x 1Ah, exact |
| 9.2 Load it back | Pass: `LOAD "f:download.bin" CODE 40000`, 0 OK |
| 9.3 Replace | Pass. PicoTerm asked, Y saved it, and the TS-Pico didn't ask a second time (the 88h prompt was answered). 13.4 s |
| 9.4 6,912 bytes | Pass: 54 blocks, 12.3 s |
| 9.5 Too big | Pass: cancelled at block 55 |
| 9.6 1K blocks | Not run yet |
| 9.7 Checksum only | Pass: 8 blocks |
| 9.8 FFh-heavy, raw | Pass: exact |
| 9.9 FFh-heavy, telnet | Pass: 16 blocks, 7.2 s, 0 NAKs, exact. Zimodem undoubles IAC (Q7) |
| 9.10 Cancel | Pass. Retried with BREAK after block 8: CAN x 5, and the server cancelled after 8 blocks and went back to its menu. First try: PicoTerm said "Cancelled." BREAK came at the very end, so the last ACK and CAN x 5 arrived together. The test server's sender then stuck after EOT, a server bug (sender fixed: CAN in any state) |

**Found on the way, in the test server rather than PicoTerm:**
- **The XMODEM deadline:** a flat 90 s was too short at 300 baud, where each block takes
  about 4.5 s. It's now 60 s of silence (`cdeaf98`).
- **CAN after EOT:** the sender ignored CAN once it had sent EOT, and typing kept its
  silence timer from running out. It now cancels on CAN in any state, and ends on any
  other byte after EOT.
- **The menu after a deadline:** it took late NAKs as commands and redrew itself. At
  300 baud that kept restarting PicoTerm's block wait, so NAKs came every 25 s.

**Open questions settled:**
- **Q6:** the modem mode is saved in `config.ini`.
- **Q7:** NAWS isn't sent; telnet passes FFh cleanly.

**Still open:**
- **Q5: answered, and a problem.** In Hayes mode nothing slows Zimodem except
  `MODEM_BAUD`, so a fast flood overflows the card's ring. The fix is still to be chosen:
  PicoTerm's own XON/XOFF, the card's XON/XOFF behind an option, or a pace (#298).
- **Not yet run:** section 3 (key legends), 5.5-5.8, section 6, section 8 and section 10.
