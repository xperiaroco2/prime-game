"""`verify` runs the headless ENet run (#45): its place in the steps, its arguments and its port."""

import socket
import unittest
from unittest import mock

from runner import verify
from runner.common import ROOT, Failure


class EnetStepTest(unittest.TestCase):
    def test_the_enet_run_is_a_step_after_the_tests(self) -> None:
        names: list[str] = []

        def step(name: str) -> mock.MagicMock:
            def called(*_args: object, **_kwargs: object) -> int:
                names.append(name)
                return 0

            return mock.MagicMock(side_effect=called)

        with (
            mock.patch.object(verify.doctor, "main", step("doctor")),
            mock.patch.object(verify.lint, "main", step("lint")),
            mock.patch.object(verify.check, "main", step("check")),
            mock.patch.object(verify.gdunit, "main", step("test")),
            mock.patch.object(verify, "enet", step("enet")),
            mock.patch.object(verify, "selftest", step("selftest")),
            mock.patch.object(verify, "git_status", return_value=set()),
            mock.patch.object(verify, "say"),
        ):
            self.assertEqual(verify.main(), 0)
        self.assertEqual(names, ["doctor", "lint", "check", "test", "enet", "selftest"])

    def test_a_failed_enet_run_fails_verify(self) -> None:
        with (
            mock.patch.object(verify.doctor, "main", return_value=0),
            mock.patch.object(verify.lint, "main", return_value=0),
            mock.patch.object(verify.check, "main", return_value=0),
            mock.patch.object(verify.gdunit, "main", return_value=0),
            mock.patch.object(verify, "enet", return_value=1),
            mock.patch.object(verify, "selftest", return_value=0),
            mock.patch.object(verify, "git_status", return_value=set()),
            mock.patch.object(verify, "say"),
        ):
            self.assertEqual(verify.main(), 1)

    def test_the_run_is_headless_three_instances_on_its_own_port(self) -> None:
        with (
            mock.patch.object(verify, "free_udp_port", return_value=23456),
            mock.patch.object(verify.launch, "main", return_value=0) as run,
        ):
            self.assertEqual(verify.enet(), 0)
        run.assert_called_once_with(
            verify.ENET_RUN, headless=True, seconds=90, instances=3, user_args=["--port=23456"]
        )
        self.assertTrue((ROOT / verify.ENET_RUN).is_file())


class FreePortTest(unittest.TestCase):
    def test_a_port_held_by_someone_else_is_skipped(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as held:
            held.bind(("127.0.0.1", 0))
            taken = held.getsockname()[1]
            picks = iter([taken, 24001])
            self.assertEqual(verify.free_udp_port(lambda _ports: next(picks)), 24001)

    def test_the_port_is_outside_the_ephemeral_ranges(self) -> None:
        port = verify.free_udp_port()
        self.assertIn(port, verify.ENET_PORTS)
        self.assertLess(max(verify.ENET_PORTS), 32768)

    def test_no_free_port_fails_by_saying_so(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as held:
            held.bind(("127.0.0.1", 0))
            taken = held.getsockname()[1]
            with self.assertRaises(Failure) as caught:
                verify.free_udp_port(lambda _ports: taken)
        self.assertIn("no free UDP port", str(caught.exception))


if __name__ == "__main__":
    unittest.main()
