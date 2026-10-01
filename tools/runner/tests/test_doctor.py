"""doctor's UDP backlog check (#159): a kernel that drops part of the stall step's backlog is warned about early."""

import contextlib
import io
import unittest
from unittest import mock

from runner import doctor


class UdpBacklogTest(unittest.TestCase):
    def output(self, held: int, platform: str = "linux") -> str:
        buffer = io.StringIO()
        with (
            mock.patch.object(doctor, "loopback_datagrams_held", return_value=held),
            mock.patch.object(doctor.sys, "platform", platform),
            contextlib.redirect_stdout(buffer),
        ):
            doc = doctor.Doctor()
            doc.udp_backlog()
        self.assertEqual(doc.failures, 0)
        return buffer.getvalue()

    def test_a_socket_that_holds_the_backlog(self) -> None:
        out = self.output(doctor.STALL_BACKLOG_DATAGRAMS)
        self.assertIn("ok    a default UDP socket holds the stall backlog (320 datagrams)", out)

    def test_a_socket_that_drops_part_of_it_warns_with_the_fix(self) -> None:
        out = self.output(255)
        self.assertIn("warn  a default UDP socket on 127.0.0.1 holds only 255 of the stall step's 320", out)
        self.assertIn("sysctl -w net.core.rmem_default=425984", out)

    def test_only_linux_is_probed(self) -> None:
        self.assertEqual(self.output(0, platform="win32"), "")

    def test_the_probe_counts_what_a_real_socket_holds(self) -> None:
        held = doctor.loopback_datagrams_held(8)
        self.assertEqual(held, 8)
