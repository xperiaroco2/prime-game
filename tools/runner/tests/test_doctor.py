"""doctor's UDP backlog check (#159): a kernel that drops part of the stall step's backlog is warned about early."""

import contextlib
import io
import re
import unittest
from unittest import mock

from runner import doctor
from runner.common import ROOT


class UdpBacklogTest(unittest.TestCase):
    def output(self, held: int | OSError, linux: bool = True) -> str:
        buffer = io.StringIO()
        probe = {"side_effect": held} if isinstance(held, OSError) else {"return_value": held}
        with (
            mock.patch.object(doctor, "loopback_datagrams_held", **probe),
            mock.patch.object(doctor, "IS_LINUX", linux),
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
        self.assertEqual(self.output(0, linux=False), "")

    def test_a_probe_that_cannot_open_a_socket_only_warns(self) -> None:
        out = self.output(OSError("no loopback"))
        self.assertIn("warn  could not probe UDP on 127.0.0.1 for the stall step's backlog: no loopback", out)

    def test_the_probe_counts_what_a_real_socket_holds(self) -> None:
        self.assertEqual(doctor.loopback_datagrams_held(8), 8)

    def test_the_probe_counts_what_a_small_buffer_drops(self) -> None:
        held = doctor.loopback_datagrams_held(doctor.STALL_BACKLOG_DATAGRAMS, rcvbuf=4096)
        self.assertGreater(held, 0)
        self.assertLess(held, doctor.STALL_BACKLOG_DATAGRAMS)

    def test_the_backlog_matches_enet_stall_gd(self) -> None:
        """BACKLOG_POSES in enet_stall.gd is ENET_RECEIVES_PER_SERVICE (enet_transport.gd) + a margin."""
        transport = (ROOT / "net" / "transport" / "enet_transport.gd").read_text(encoding="utf-8")
        stall = (ROOT / "tests" / "integration" / "net" / "enet_stall.gd").read_text(encoding="utf-8")
        per_service = re.search(r"^const ENET_RECEIVES_PER_SERVICE := (\d+)$", transport, re.M)
        margin = re.search(r"^const BACKLOG_POSES := EnetTransport\.ENET_RECEIVES_PER_SERVICE \+ (\d+)$", stall, re.M)
        if per_service is None or margin is None:
            self.fail("ENET_RECEIVES_PER_SERVICE or BACKLOG_POSES changed form; update this test and doctor")
        self.assertEqual(int(per_service[1]) + int(margin[1]), doctor.STALL_BACKLOG_DATAGRAMS)
