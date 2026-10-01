"""`verify` runs the headless ENet (#45), freeze (#70), stall (#95) and bots (#102) runs: their place, arguments, port."""

import socket
import unittest
from unittest import mock

from runner import verify
from runner.common import ROOT, Failure


class EnetStepTest(unittest.TestCase):
    def test_the_enet_freeze_and_stall_runs_are_steps_after_the_tests(self) -> None:
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
            mock.patch.object(verify, "freeze", step("freeze")),
            mock.patch.object(verify, "stall", step("stall")),
            mock.patch.object(verify, "bots_one_process", step("bots")),
            mock.patch.object(verify, "bots_enet", step("bots-enet")),
            mock.patch.object(verify, "selftest", step("selftest")),
            mock.patch.object(verify, "git_status", return_value=set()),
            mock.patch.object(verify, "say"),
        ):
            self.assertEqual(verify.main(), 0)
        self.assertEqual(
            names,
            ["doctor", "lint", "check", "test", "enet", "freeze", "stall", "bots", "bots-enet", "selftest"],
        )

    def test_a_failed_enet_freeze_stall_or_bots_run_fails_verify(self) -> None:
        for failing in ("enet", "freeze", "stall", "bots", "bots-enet"):
            with (
                self.subTest(failing=failing),
                mock.patch.object(verify.doctor, "main", return_value=0),
                mock.patch.object(verify.lint, "main", return_value=0),
                mock.patch.object(verify.check, "main", return_value=0),
                mock.patch.object(verify.gdunit, "main", return_value=0),
                mock.patch.object(verify, "enet", return_value=int(failing == "enet")),
                mock.patch.object(verify, "freeze", return_value=int(failing == "freeze")),
                mock.patch.object(verify, "stall", return_value=int(failing == "stall")),
                mock.patch.object(verify, "bots_one_process", return_value=int(failing == "bots")),
                mock.patch.object(verify, "bots_enet", return_value=int(failing == "bots-enet")),
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

    def test_the_freeze_run_is_headless_three_instances_on_its_own_port(self) -> None:
        with (
            mock.patch.object(verify, "free_udp_port", return_value=23457),
            mock.patch.object(verify.launch, "main", return_value=0) as run,
        ):
            self.assertEqual(verify.freeze(), 0)
        run.assert_called_once_with(
            verify.FREEZE_RUN, headless=True, seconds=60, instances=3, user_args=["--port=23457"]
        )
        self.assertTrue((ROOT / verify.FREEZE_RUN).is_file())

    def test_the_stall_run_is_one_headless_process_on_three_free_ports(self) -> None:
        with (
            mock.patch.object(verify, "free_udp_port", return_value=23458) as pick,
            mock.patch.object(verify.launch, "main", return_value=0) as run,
        ):
            self.assertEqual(verify.stall(), 0)
        pick.assert_called_once_with(count=3)
        run.assert_called_once_with(
            verify.STALL_RUN, headless=True, seconds=60, instances=1, user_args=["--port=23458"]
        )
        self.assertTrue((ROOT / verify.STALL_RUN).is_file())


    def test_the_bots_run_every_scenario_in_one_process_then_one_over_enet(self) -> None:
        with mock.patch.object(verify.bots, "main", return_value=0) as run:
            self.assertEqual(verify.bots_one_process(), 0)
            self.assertEqual(verify.bots_enet(), 0)
        self.assertEqual(
            run.call_args_list,
            [mock.call(), mock.call([verify.BOTS_ENET_SCENARIO], instances=verify.BOTS_ENET_INSTANCES)],
        )
        self.assertTrue((ROOT / "content" / "scenarios" / f"{verify.BOTS_ENET_SCENARIO}.tres").is_file())


class FreePortTest(unittest.TestCase):
    def test_a_port_held_by_someone_else_is_skipped(self) -> None:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as held:
            held.bind(("127.0.0.1", 0))
            taken = held.getsockname()[1]
            # A second port the OS just handed out and took back: free, and not `taken` while `held` is open.
            with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as probe:
                probe.bind(("127.0.0.1", 0))
                free = probe.getsockname()[1]
            picks = iter([taken, free])
            self.assertEqual(verify.free_udp_port(lambda _ports: next(picks)), free)

    def test_with_a_count_every_port_of_the_run_must_bind(self) -> None:
        held = {20001}
        picks = iter([20000, 20005])
        with mock.patch.object(verify, "_binds", side_effect=lambda port: port not in held):
            self.assertEqual(verify.free_udp_port(lambda _ports: next(picks), count=2), 20005)

    def test_the_last_port_of_a_run_stays_in_the_range(self) -> None:
        offered: list[range] = []

        def last(ports: range) -> int:
            offered.append(ports)
            return ports[-1]

        with mock.patch.object(verify, "_binds", return_value=True):
            port = verify.free_udp_port(last, count=3)
        self.assertEqual(port + 2, verify.ENET_PORTS[-1])
        self.assertEqual(offered[0].start, verify.ENET_PORTS.start)

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
