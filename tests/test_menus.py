"""M5: the menu, settings, picoterm.cfg, the phonebook and WiFi, on the
host machine with the fake Zimodem and TS-Pico (which keeps files)."""

import unittest

try:
    import z80  # noqa: F401
    HAVE_Z80 = True
except ImportError:
    HAVE_Z80 = False

if HAVE_Z80:
    from hostmachine import Machine
from fakes import Fake8251, FakePico, FakeZimodem

VM_32, VM_64, VM_80 = 0, 1, 2
EMU_TTY, EMU_VT52, EMU_ANSI = 0, 1, 2


@unittest.skipUnless(HAVE_Z80, "the z80 package isn't installed (make venv)")
class MenuTest(unittest.TestCase):
    def start(self, files=None, picovideo=False, **zm_args):
        self.zm = FakeZimodem(**zm_args)
        self.acia = Fake8251(self.zm)
        self.pico = FakePico(files=files)
        self.m = Machine(acia=self.acia, pico=self.pico)
        if picovideo:
            self.m.mem[self.m.sym["set_picovideo"]] = 1
        self.m.run_frames(200)
        self.m.idle()
        return self.m

    def key(self, k, *mods):
        self.m.press(k, *mods)
        self.assertTrue(self.m.settle())

    def type(self, text):
        self.m.type(text)
        self.assertTrue(self.m.settle())

    def menu(self):
        self.key("SPACE", "CAPS")

    def back(self):
        self.key("SPACE", "CAPS")

    def screen(self):
        return "\n".join(self.m.screen_text())

    def setting(self, name):
        return self.m.var(name)

    # --- the menu ------------------------------------------------------------

    def test_menu_opens_and_closes_over_the_terminal(self):
        m = self.start()
        before = m.shadow_text()
        self.menu()
        self.assertIn("Dial (phonebook)", self.screen())
        self.assertIn("Offline ANSI 32 columns", self.screen())
        self.assertEqual(m.shadow_text(), before)     # the terminal is untouched
        self.back()
        m.idle()
        self.assertEqual(m.screen_text(), m.shadow_text())

    def test_received_text_waits_while_the_menu_is_open(self):
        m = self.start()
        self.menu()
        self.zm.to_terminal.extend(b"while you were out\r\n")
        m.run_frames(30)
        self.assertNotIn("while you were out", "\n".join(m.shadow_text()))
        self.back()
        m.run_frames(30)
        m.idle()
        self.assertIn("while you were out", "\n".join(m.shadow_text()))

    def test_clear_screen(self):
        m = self.start()
        self.menu()
        self.key("c")
        m.idle()
        self.assertTrue(all(not r.strip() for r in m.shadow_text()))

    def test_hang_up_from_the_menu(self):
        m = self.start()
        m.type('atdt"bbs.example:23"\n')
        m.run_frames(20)
        self.assertEqual(m.var("hayes_online"), 1)
        self.menu()
        self.assertIn("Online", self.screen())
        self.key("h")
        m.run_until(lambda: m.var("hayes_online") == 0, limit=600)
        self.assertEqual(self.zm.commands[-1], "ATH")
        self.assertFalse(m.exited)

    # --- settings and picoterm.cfg -----------------------------------------------

    def test_settings_change_and_save(self):
        m = self.start(picovideo=True)
        self.menu()
        self.key("s")
        self.assertIn("Settings", self.screen())
        self.key("e")                                  # ANSI -> TTY
        self.key("b")                                  # BS -> DEL
        self.key("l")                                  # local echo on
        self.key("n")                                  # ENTER: CR LF
        self.key("g")                                  # bell off
        self.key("c")                                  # 32 -> 64
        self.assertEqual(self.setting("set_emul"), EMU_TTY)
        self.assertEqual(self.setting("set_backspace"), 0x7F)
        self.assertEqual(self.setting("set_echo"), 1)
        self.assertEqual(self.setting("set_enter"), 1)
        self.assertEqual(self.setting("set_bell"), 0)
        self.key("s")                                  # save
        self.assertIn("Saved to picoterm.cfg.", self.screen())
        self.key("ENTER")
        cfg = self.pico.files["picoterm.cfg"].decode()
        for line in ("emul=0", "cols=1", "picovideo=1", "bs=127", "echo=1",
                     "enter=1", "bell=0", "init=ATE1V1X1Q0"):
            self.assertIn(line + "\n", cfg)
        self.back()                                    # out of settings
        m.idle()
        self.assertEqual(m.cols(), 64)                 # the mode was applied
        self.assertIn('AT&S"41=DUMB"', self.zm.commands)

    def test_edit_init_string(self):
        m = self.start()
        self.menu()
        self.key("s")
        self.key("m")
        for _ in range(10):
            self.key("0", "CAPS")                      # DELETE it all
        self.type("ATE0")
        self.key("ENTER")
        self.assertEqual(m.peek(m.sym["set_init"], 5), b"ATE0\x00")

    def test_config_loaded_at_start_up(self):
        cfg = (b"emul=1\ncols=1\nbs=127\necho=1\nbell=0\ninit=ATE0V1\n"
               b"phone=Test BBS|bbs.example:23|1|2|0|8|0\n"
               b"phone=Raw|10.0.0.5:6400|0|0|1|127|1\n")
        m = self.start(files={"picoterm.cfg": cfg})
        self.assertEqual(self.setting("set_emul"), EMU_VT52)
        self.assertEqual(m.cols(), 64)
        self.assertEqual(self.setting("set_backspace"), 0x7F)
        self.assertEqual(self.setting("set_bell"), 0)
        self.assertEqual(self.zm.commands[1], "ATE0V1")   # the loaded init
        self.menu()
        self.key("d")
        self.assertIn("Test BBS", self.screen())
        self.assertIn("Raw", self.screen())

    def test_bad_config_lines_are_skipped(self):
        cfg = (b"emul=9\ncols=x\nnonsense\nunknown=3\nbs=200\n"
               b"phone=No host||1|2|0|8|0\nphone=Short|h:1|1|2\n"
               b"phone=Fine|ok.example:23|1|2|0|8|0\nbell=0")    # no last newline
        m = self.start(files={"picoterm.cfg": cfg})
        self.assertEqual(self.setting("set_emul"), EMU_ANSI)  # defaults stand
        self.assertEqual(m.cols(), 32)
        self.assertEqual(self.setting("set_backspace"), 0x08)
        self.assertEqual(self.setting("set_bell"), 0)
        used = [m.mem[m.sym["PHONEBOOK"] + i * 64 + 63] for i in range(20)]
        self.assertEqual(sum(used), 1)

    def test_save_then_load_round_trip(self):
        m = self.start()
        self.menu()
        self.key("d")
        self.new_entry("Round", "trip.example:2323")
        self.back()                                    # out of the phonebook
        self.key("s")
        self.key("v" if False else "e")               # ANSI -> TTY
        self.key("s")
        self.key("ENTER")
        files = dict(self.pico.files)
        m2 = self.start(files=files)
        self.assertEqual(self.setting("set_emul"), EMU_TTY)
        self.menu()
        self.key("d")
        self.assertIn("Round", self.screen())

    # --- the phonebook -------------------------------------------------------------

    def new_entry(self, name, host):
        self.key("n")
        self.type(name)
        self.key("ENTER")
        self.type(host)
        self.key("ENTER")
        self.key("ENTER")                              # save the form

    def test_new_entry_and_dial(self):
        m = self.start()
        self.menu()
        self.key("d")
        self.assertIn("Phonebook", self.screen())
        self.new_entry("Test BBS", "bbs.example:23")
        self.assertIn("Test BBS", self.screen())
        self.key("ENTER")                              # dial it
        m.run_until(lambda: m.var("hayes_online") == 1, limit=300)
        self.assertEqual(self.zm.commands[-1], 'ATDT"bbs.example:23"')
        self.assertIn('AT&S"41=ANSI"', self.zm.commands[-2])
        m.run_frames(20)
        m.idle()
        self.assertIn("Dialling Test BBS", "\n".join(m.shadow_text()))
        self.assertIn("Welcome to the test BBS", "\n".join(m.shadow_text()))

    def test_arrows_move_the_selection(self):
        m = self.start()
        self.menu()
        self.key("d")
        self.new_entry("One", "one.example:23")
        self.new_entry("Two", "two.example:23")      # selected, row 2
        rows = m.screen_text()
        self.assertTrue(rows[2].startswith("\xba > Two") or "> Two" in rows[2])
        self.key("7", "CAPS")                          # up
        rows = m.screen_text()
        self.assertIn("> One", rows[1])
        self.assertNotIn(">", rows[2])
        self.key("7", "CAPS")                          # already at the top
        self.assertIn("> One", m.screen_text()[1])
        self.key("6", "CAPS")
        self.key("6", "CAPS")
        self.assertIn(">", m.screen_text()[3])         # empty slots can be chosen

    def test_entry_settings_apply_when_dialled(self):
        m = self.start()
        self.menu()
        self.key("d")
        self.new_entry("Raw", "bbs.example:23")
        self.key("e")                                  # edit it
        self.key("t")                                  # telnet off
        self.key("e")                                  # ANSI -> TTY
        self.key("c")                                  # 32 -> 64
        self.key("b")                                  # DEL
        self.key("ENTER")
        self.key("ENTER")                              # dial
        m.run_until(lambda: m.var("hayes_online") == 1, limit=300)
        self.assertEqual(self.zm.commands[-1], 'ATD"bbs.example:23"')
        self.assertEqual(self.setting("set_emul"), EMU_TTY)
        self.assertEqual(self.setting("set_backspace"), 0x7F)
        self.assertEqual(m.cols(), 64)

    def test_cancel_and_delete(self):
        m = self.start()
        self.menu()
        self.key("d")
        self.key("n")
        self.type("Nope")
        self.key("SPACE", "CAPS")                      # BREAK: cancel
        self.assertNotIn("Nope", self.screen())
        self.new_entry("Keep", "k.example:23")
        self.key("x")
        self.key("n")                                  # not deleted
        self.assertIn("Keep", self.screen())
        self.key("x")
        self.key("y")
        self.assertNotIn("Keep", self.screen())

    def test_dial_while_online_is_refused(self):
        m = self.start()
        m.type('atdt"bbs.example:23"\n')
        m.run_frames(20)
        self.menu()
        self.key("d")
        self.new_entry("Other", "bbs.example:23")
        self.key("ENTER")
        self.assertIn("Hang up first.", self.screen())

    # --- WiFi ------------------------------------------------------------------------

    def test_wifi_scan_join_and_save(self):
        m = self.start()
        self.menu()
        self.key("w")
        m.run_frames(20)
        self.assertIn("HomeNet", self.screen())
        self.assertIn("Cafe Free", self.screen())       # a space in the name
        self.key("ENTER")                              # the first: HomeNet
        self.type("secret12")
        self.assertNotIn("secret12", self.screen())     # masked
        self.key("ENTER")
        m.run_frames(20)
        self.assertEqual(self.zm.joined, "HomeNet")
        self.assertIn("Make it default", self.screen())
        self.key("y")
        m.run_frames(20)
        self.assertTrue(self.zm.saved)
        self.assertIn("Saved in the modem.", self.screen())
        self.key("ENTER")
        self.back()
        self.back()
        m.idle()
        self.assertEqual(m.screen_text(), m.shadow_text())
        self.assertNotIn("ATW", "\n".join(m.shadow_text()))   # replies stayed hidden

    def test_wifi_wrong_password(self):
        m = self.start()
        self.menu()
        self.key("w")
        m.run_frames(20)
        self.key("ENTER")
        self.type("wrong")
        self.key("ENTER")
        m.run_frames(20)
        self.assertIsNone(self.zm.joined)
        self.assertIn("Couldn't join", self.screen())

    def test_wifi_manual_ssid(self):
        m = self.start(networks={"Hidden": (-50, "pw")})
        self.menu()
        self.key("w")
        m.run_frames(20)
        self.key("m")
        self.type("Hidden")
        self.key("ENTER")
        self.type("pw")
        self.key("ENTER")
        m.run_frames(20)
        self.assertEqual(self.zm.joined, "Hidden")

    def test_wifi_refused_while_online(self):
        m = self.start()
        m.type('atdt"bbs.example:23"\n')
        m.run_frames(20)
        self.menu()
        self.key("w")
        self.assertIn("Hang up first.", self.screen())

    # --- wider modes ------------------------------------------------------------------

    def test_menu_centred_in_80_columns(self):
        m = self.start(picovideo=True)
        m.mem[m.sym["set_cols"]] = VM_80
        self.key("9", "CAPS")
        self.key("9", "CAPS")                          # 32 -> 64 -> 80
        self.assertEqual(m.cols(), 80)
        self.menu()
        row = m.screen_text()[6]
        self.assertEqual(row.index("D  Dial"), 24 + 2)  # (80 - 32) / 2 + 2
        self.back()
        m.idle()
        self.assertEqual(m.screen_text(), m.shadow_text())


if __name__ == "__main__":
    unittest.main()
