"""The XMODEM sender that both the host tests and tools/test_bbs.py use."""

import unittest

from fakes import XmodemSender

ACK, NAK, CAN, EOT = 6, 0x15, 0x18, 4


def run_to_eot(sender):
    sender.receive(ord("C"))
    for _ in range(len(sender.blocks)):
        sender.receive(ACK)
    assert sender.state == "eot" and sender.out[-1] == EOT


class XmodemSenderTest(unittest.TestCase):
    def test_ack_after_eot_is_done(self):
        s = XmodemSender(b"x" * 300)
        run_to_eot(s)
        s.receive(ACK)
        self.assertEqual(s.state, "done")

    def test_cancel_after_eot(self):
        # Board 1, checklist 9.10: BREAK at the very end. The last ACK and
        # CAN x 5 arrive together; the sender must not stick at EOT.
        s = XmodemSender(b"x" * 300)
        s.receive(ord("C"))
        for _ in range(len(s.blocks) - 1):
            s.receive(ACK)
        for b in (ACK, CAN, CAN, CAN, CAN, CAN):
            s.receive(b)
        self.assertEqual(s.state, "cancelled")

    def test_cancel_in_every_state(self):
        for steps in (0, 1, 2):
            s = XmodemSender(b"x" * 300)
            if steps >= 1:
                s.receive(ord("C"))
            if steps >= 2:
                s.receive(ACK)
            s.receive(CAN)
            self.assertEqual(s.state, "cancelled", f"after {steps} steps")

    def test_typing_after_eot_ends_it(self):
        s = XmodemSender(b"x" * 300)
        run_to_eot(s)
        s.receive(ord("f"))
        self.assertEqual(s.state, "ended")

    def test_nak_after_eot_resends_eot(self):
        s = XmodemSender(b"x" * 300)
        run_to_eot(s)
        s.out.clear()
        s.receive(NAK)
        self.assertEqual(bytes(s.out), bytes([EOT]))
        self.assertEqual(s.state, "eot")


if __name__ == "__main__":
    unittest.main()
