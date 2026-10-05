"""`metrics --track` (#409): a track's spend this week against its budget, over small synthetic transcripts written here
(never real ones) in the main checkout's folders and its -ui and -art siblings': the order a session's track comes from,
the window, the dedup by message id, the budget lines and the command line."""

import io
import json
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from runner import cli, metrics
from runner.common import Failure
from runner.tests.test_metrics import assistant, at, tool_result, usage, write_lines

CHECKOUT = Path("D:/prime-game")
SINCE = at(60)  # the reset
DAYS = 3.5
UNTIL = at(60 + DAYS * 1440)
ONE = usage(inp=5_750_000)  # $23.00 of input on Opus 5.5: 1% of the week, no cache reads


def kickoff(minutes: float, text: str) -> dict:
    return {"type": "user", "timestamp": at(minutes), "message": {"role": "user", "content": text}}


def meta_line(minutes: float, text: str) -> dict:
    """A line Claude Code adds as the user (a skill's text): no message of the human's."""
    return {**kickoff(minutes, text), "isMeta": True}


class TrackFixture:
    """A config folder with the transcripts of three checkouts and a worktree; each call below is 1% of the week.

    D--prime-game                     g1: a skill's isMeta line naming meta, a tool result, then a kickoff with
                                      "Track: Game": game; a call before --since and one after --until (left out), one
                                      in the window, a hand-run subagent's and a workflow agent's (its message written
                                      twice, counted once): 4%.
                                      lab: its kickoff says game, `--session lab=meta` wins: meta 1%.
                                      plain: no Track line: untracked 1%.
                                      old: only a call before --since: not listed.
    D--prime-game--claude-worktrees-7 wt: "Track: meta": meta 1%.
    D--prime-game-ui                  ui1: no Track line: ui 1%; and g1's message again (a forked session): once.
                                      ui2: "Track: art" beats the checkout: art 1%.
    D--prime-game-art                 a1: no Track line: art 1%.
    D--prime-game-old                 x: not a track checkout: never read.
    """

    def __init__(self, root: Path) -> None:
        self.base = root
        p = root / "projects"
        main = p / "D--prime-game"
        write_lines(main / "g1.jsonl", [
            meta_line(0, "Track: meta"),
            tool_result(1, "t0", "Track: meta"),
            kickoff(2, "ultracode: orchestrate stage 6\nTrack: Game\nScope: #1"),
            assistant(30, "g1-before", ONE),
            assistant(120, "g1-in", ONE),
            assistant(60 + DAYS * 1440 + 5, "g1-after", ONE),
        ])
        write_lines(main / "g1" / "subagents" / "agent-h.jsonl", [kickoff(130, "Track: meta"), assistant(131, "h1", ONE)])
        wf = main / "g1" / "subagents" / "workflows" / "wf_1"
        write_lines(wf / "agent-w.jsonl", [
            assistant(140, "w1", ONE), assistant(140, "w1", ONE), assistant(150, "w2", ONE),
        ])
        write_lines(main / "lab.jsonl", [kickoff(100, "Track: game"), assistant(101, "lab1", ONE)])
        write_lines(main / "plain.jsonl", [kickoff(100, "ultracode: no track here"), assistant(101, "plain1", ONE)])
        write_lines(main / "old.jsonl", [kickoff(10, "Track: game"), assistant(11, "old1", ONE)])
        write_lines(p / "D--prime-game--claude-worktrees-7" / "wt.jsonl", [
            kickoff(200, "a session in a worktree\n  Track: meta"), assistant(201, "wt1", ONE),
        ])
        write_lines(p / "D--prime-game-ui" / "ui1.jsonl", [
            kickoff(300, "ultracode: the UI track's manager"), assistant(301, "ui1", ONE), assistant(302, "g1-in", ONE),
        ])
        write_lines(p / "D--prime-game-ui" / "ui2.jsonl", [kickoff(300, "Track: art"), assistant(301, "ui2", ONE)])
        write_lines(p / "D--prime-game-art" / "a1.jsonl", [kickoff(400, "art"), assistant(401, "a1", ONE)])
        write_lines(p / "D--prime-game-old" / "x.jsonl", [kickoff(400, "Track: game"), assistant(401, "x1", ONE)])


class TracksTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fx = TrackFixture(self.root)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def spend(self, labels: dict | None = None) -> dict:
        dirs = metrics.track_dirs(CHECKOUT, self.root)
        return metrics.track_spend(dirs, labels or {}, metrics.parse_time(SINCE), metrics.parse_time(UNTIL))

    def run_main(self, *names: str, budgets: tuple = (), labels: tuple = ("lab=meta",), until: str = UNTIL,
                 compact: bool = True) -> str:  # fmt: skip
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = metrics.tracks_main(list(labels), list(names), list(budgets), SINCE, until, str(self.root / "out"),
                                     compact, checkout=CHECKOUT, base=self.root)  # fmt: skip
        self.assertEqual(rc, 0)
        return buf.getvalue()

    def test_the_folders_of_the_three_checkouts_and_their_worktrees(self) -> None:
        names = [(d.name, default) for d, default in metrics.track_dirs(CHECKOUT, self.root)]
        self.assertEqual(names, [("D--prime-game", None), ("D--prime-game--claude-worktrees-7", None),
                                 ("D--prime-game-ui", "ui"), ("D--prime-game-art", "art")])  # fmt: skip

    def test_a_sessions_track_label_then_kickoff_then_checkout(self) -> None:
        spend = self.spend({"lab": "meta"})
        got = {s["id"]: (s["track"], s["source"]) for s in spend["sessions"]}
        self.assertEqual(got, {
            "g1": ("game", "Track: line"),
            "lab": ("meta", "--session"),
            "plain": ("untracked", "none"),
            "wt": ("meta", "Track: line"),
            "ui1": ("ui", "checkout"),
            "ui2": ("art", "Track: line"),
            "a1": ("art", "checkout"),
        })

    def test_a_translated_kickoff_keeps_its_track_by_the_key_not_the_name(self) -> None:
        main = self.root / "projects" / "D--prime-game"
        write_lines(main / "uk.jsonl", [kickoff(100, "Обсяг: #1\nТрек: meta"), assistant(101, "uk1", ONE)])
        write_lines(main / "lower.jsonl", [kickoff(100, "track: UI"), assistant(101, "lower1", ONE)])
        write_lines(main / "name.jsonl", [kickoff(100, "Трек: мета"), assistant(101, "name1", ONE)])
        got = {s["id"]: (s["track"], s["source"]) for s in self.spend()["sessions"]}
        self.assertEqual(got["uk"], ("meta", "Track: line"))
        self.assertEqual(got["lower"], ("ui", "Track: line"))
        self.assertEqual(got["name"], ("untracked", "none"))  # a translated name: no track

    def test_the_ui_folders_session_without_a_track_line_counts_as_ui(self) -> None:
        tracks = self.spend()["tracks"]
        self.assertEqual(tracks["ui"]["sessions"], 1)
        self.assertAlmostEqual(tracks["ui"]["percent"], 1.0)

    def test_the_window_the_runs_the_subagents_and_the_dedup(self) -> None:
        spend = self.spend({"lab": "meta"})
        calls = {s["id"]: s["calls"] for s in spend["sessions"]}
        # g1: its call in the window, the hand-run subagent's, the workflow agent's two (w1 written twice)
        self.assertEqual(calls["g1"], 4)
        self.assertEqual(calls["ui1"], 1)  # g1-in again: counted once, in g1
        pct = {name: round(t["percent"], 6) for name, t in spend["tracks"].items()}
        self.assertEqual(pct, {"game": 4.0, "meta": 2.0, "untracked": 1.0, "ui": 1.0, "art": 2.0})
        self.assertNotIn("old", calls)

    def test_cache_reads_count_at_the_central_weight_with_the_bracket(self) -> None:
        write_lines(self.root / "projects" / "D--prime-game-art" / "a2.jsonl", [
            assistant(500, "a2", usage(inp=1_000_000, read=10_000_000)),
        ])
        art = self.spend()["tracks"]["art"]  # a1 and ui2 at $23 each, a2 at $4 of input and $2 of cache reads
        self.assertAlmostEqual(art["usd"], 46.0 + 4.0 + 2.0)
        self.assertAlmostEqual(art["read_usd"], 2.0)
        self.assertAlmostEqual(art["percent"], (50.0 + 0.75 * 2.0) / 23.0)
        self.assertAlmostEqual(art["bracket"][0], (50.0 + 0.6 * 2.0) / 21.5)
        self.assertAlmostEqual(art["bracket"][1], 52.0 / 25.5)

    def test_the_budget_lines(self) -> None:
        out = self.run_main("game", "meta", "ui", budgets=(26, 12, 20))
        lines = out.splitlines()
        self.assertEqual(lines[0], f"tracks, {SINCE[:19]}Z to {UNTIL[:19]}Z (3.5 days of the week's 7), % of a Max "
                                   "20x week at the central weight (the bracket in brackets)")  # fmt: skip
        self.assertEqual(lines[1], "game: 4.0% (4.3 to 3.6%) of 26% this week; plan to date 13.0%; list $92 in 1 "
                                   "session")  # fmt: skip
        self.assertEqual(lines[2], "meta: 2.0% (2.1 to 1.8%) of 12% this week; plan to date 6.0%; list $46 in 2 "
                                   "sessions")  # fmt: skip
        self.assertEqual(lines[3], "ui: 1.0% (1.1 to 0.9%) of 20% this week; plan to date 10.0%; list $23 in 1 session")
        self.assertEqual(lines[4], "every session: 10.0% (10.7 to 9.0%) (untracked 1.0%), against the weekly counter "
                                   "(get_usage)")  # fmt: skip
        self.assertEqual(len(lines), 5)  # --compact: the lines alone
        record = json.loads((self.root / "out" / "tracks.json").read_text(encoding="utf-8"))
        self.assertEqual(record["budgets"], {"game": 26, "meta": 12, "ui": 20})
        self.assertEqual(record["lines"], lines)
        self.assertEqual(len(record["sessions"]), 7)

    def test_without_a_budget_a_track_with_no_session_and_all(self) -> None:
        lines = self.run_main("Meta", "sound").splitlines()
        self.assertEqual(lines[1], "meta: 2.0% (2.1 to 1.8%) this week; list $46 in 2 sessions")
        self.assertEqual(lines[2], "sound: 0.0% (0.0 to 0.0%) this week; list $0.00 in 0 sessions")
        every = self.run_main("all", labels=()).splitlines()
        self.assertEqual([line.split(":")[0] for line in every[1:-1]], ["game", "ui", "art", "meta", "untracked"])
        self.assertTrue(every[1].startswith("game: 5.0% "), every[1])  # without its label, lab's kickoff names game
        self.assertTrue(every[5].startswith("untracked: 1.0% "), every[5])
        table = self.run_main("all", compact=False)
        self.assertIn("| meta | lab | D--prime-game | --session | 1 | $23 | 1.00% |", table)

    def test_the_plan_to_date_stops_at_the_budget_after_seven_days(self) -> None:
        lines = self.run_main("game", budgets=(26,), until=at(60 + 8 * 1440)).splitlines()
        self.assertIn("(8.0 days of the week's 7)", lines[0])
        self.assertIn("of 26% this week; plan to date 26.0%;", lines[1])

    def test_mistakes_fail(self) -> None:
        cases = [
            ((["game"], [], None), "--track needs --since"),
            ((["game", "meta"], [26.0], SINCE), "one % per --track name"),
            ((["all"], [26.0], SINCE), "not with --track all"),
            ((["all", "game"], [], SINCE), "--track all stands alone"),
            ((["game"], [-1.0], SINCE), "0 or more"),
        ]
        for (names, budgets, since), message in cases:
            with self.subTest(message), self.assertRaises(Failure) as caught:
                metrics.tracks_main([], names, budgets, since, UNTIL, str(self.root / "out"), True,
                                    checkout=CHECKOUT, base=self.root)  # fmt: skip
            self.assertIn(message, str(caught.exception))
        with self.assertRaises(Failure) as caught:
            metrics.main(budget=[26.0], dirs=[], history=[])
        self.assertIn("--budget goes with --track", str(caught.exception))

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(
            ["metrics", "--since", SINCE, "--track", "game", "ui", "--track", "art", "--budget", "26", "20",
             "--budget", "20", "--session", "3e834e50=game"]
        )  # fmt: skip
        self.assertEqual((args.track, args.budget, args.session), (["game", "ui", "art"], [26.0, 20.0, 20.0],
                                                                  ["3e834e50=game"]))  # fmt: skip
        plain = cli.build_parser().parse_args(["metrics"])
        self.assertEqual((plain.track, plain.budget), ([], []))


if __name__ == "__main__":
    unittest.main()
