"""`bots` (#102): its arguments, the folder it empties, and the run it starts in one process or over ENet."""

import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import bots, cli, verify
from runner.common import ROOT, Failure


class BotsArgsTest(unittest.TestCase):
    def test_the_entry_script_exists(self) -> None:
        self.assertTrue((ROOT / bots.TARGET).is_file())

    def test_scenario_names_are_file_names(self) -> None:
        bots.check_args(["refusals", "late_join_cancels_the_countdown"], 1)
        for wrong in ("../core/x", "content/scenarios/refusals", "Refusals", "a b"):
            with self.subTest(name=wrong), self.assertRaises(Failure):
                bots.check_args([wrong], 1)

    def test_instances_need_exactly_one_scenario_and_stay_in_range(self) -> None:
        bots.check_args(["refusals"], 3)
        for names, instances in (([], 3), (["a", "b"], 2), (["a"], 0), (["a"], 99)):
            with self.subTest(names=names, instances=instances), self.assertRaises(Failure):
                bots.check_args(names, instances)

    def test_user_args_put_the_port_and_count_before_the_names(self) -> None:
        self.assertEqual(bots.user_args(["a", "b"]), ["a", "b"])
        self.assertEqual(bots.user_args(["a"], 24000, 3), ["--port=24000", "--instances=3", "a"])

    def test_the_command_line_reaches_main(self) -> None:
        args = cli.build_parser().parse_args(["bots", "refusals", "--instances", "2", "--seconds", "40"])
        self.assertEqual((args.scenarios, args.instances, args.seconds), (["refusals"], 2, 40))
        args = cli.build_parser().parse_args(["bots"])
        self.assertEqual((args.scenarios, args.instances, args.seconds), ([], 1, None))


class BotsRunTest(unittest.TestCase):
    def test_one_process_runs_every_scenario_headless(self) -> None:
        with (
            mock.patch.object(bots, "clear_out") as clear,
            mock.patch.object(bots.launch, "main", return_value=0) as run,
            mock.patch.object(bots, "say"),
        ):
            self.assertEqual(bots.main(), 0)
            self.assertEqual(bots.main(["refusals.tres"]), 0)
        self.assertEqual(clear.call_args_list, [mock.call([]), mock.call(["refusals"])])
        self.assertEqual(
            run.call_args_list,
            [
                mock.call(bots.TARGET, headless=True, seconds=bots.ONE_PROCESS_SECONDS, user_args=[]),
                mock.call(bots.TARGET, headless=True, seconds=bots.ONE_PROCESS_SECONDS, user_args=["refusals"]),
            ],
        )

    def test_enet_runs_one_instance_per_bot_on_a_free_port(self) -> None:
        with (
            mock.patch.object(bots, "clear_out"),
            mock.patch.object(verify, "free_udp_port", return_value=24242),
            mock.patch.object(bots.launch, "main", return_value=1) as run,
            mock.patch.object(bots, "say"),
        ):
            self.assertEqual(bots.main(["refusals"], instances=2, seconds=50), 1)
        run.assert_called_once_with(
            bots.TARGET,
            headless=True,
            seconds=50,
            instances=2,
            user_args=["--port=24242", "--instances=2", "refusals"],
        )

    def test_a_failed_enet_run_prints_each_instances_failure_report(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            logs = Path(tmp)
            first = [
                "BOTS refusals: instance 1 of 2 on port 1",
                "BOTS refusals: FAILED (seed 7) instance 1",
                "  bot 2 (peer 2), step 1 (WalkTo): cannot know",
                "  command log (Match.replay with ReplayFiles.read): x.replay",
                "after",
            ]
            (logs / "bots_main-1.log").write_text("".join(f"{line}\n" for line in first), encoding="utf-8")
            (logs / "bots_main-2.log").write_text("BOTS refusals: instance 2 of 2 on port 1\n", encoding="utf-8")
            with (
                mock.patch.object(bots, "RUN_LOGS", logs),
                mock.patch.object(bots, "clear_out"),
                mock.patch.object(verify, "free_udp_port", return_value=24242),
                mock.patch.object(bots.launch, "main", return_value=1),
                mock.patch.object(bots, "say") as said,
            ):
                self.assertEqual(bots.main(["refusals"], instances=2), 1)
        printed = [call.args[0] for call in said.call_args_list]
        self.assertEqual(
            printed[1:],
            [
                "  #1 BOTS refusals: FAILED (seed 7) instance 1",
                "  #1   bot 2 (peer 2), step 1 (WalkTo): cannot know",
                "  #1   command log (Match.replay with ReplayFiles.read): x.replay",
            ],
        )

    def test_a_run_starts_with_empty_scenario_folders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = Path(tmp) / "bots"
            for name in ("refusals", "other"):
                (out / name).mkdir(parents=True)
                (out / name / "bot-1.bin").write_bytes(b"old")
            with mock.patch.object(bots, "BOTS_OUT", out):
                bots.clear_out(["refusals"])
                self.assertFalse((out / "refusals").exists())
                self.assertTrue((out / "other" / "bot-1.bin").is_file())
                bots.clear_out([])
                self.assertFalse(out.exists())


if __name__ == "__main__":
    unittest.main()
