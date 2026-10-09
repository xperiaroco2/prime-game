"""`metrics --run ID ...` (#534): one workflow run's spend so far, in flight or finished, for the manager's check after
a large launch's first phase (docs/MANAGERS.md §9), over small synthetic transcripts written here (never real ones) in
the three track checkouts' folders (one not on this machine): the agents and who works now, a retried agent, a journal
cut short, the dedup by message id, the % of the week by phase, the prefix match, the checkouts a failure names and the
command line."""

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from runner import cli, metrics
from runner.common import Failure
from runner.tests.test_metrics import assistant, usage, write_lines

CHECKOUT = Path("D:/prime-game")
ONE = usage(inp=5_750_000)  # $23.00 of input on Opus 5.5: 1% of the week, no cache reads
WRITTEN = 1_000_000.0  # every fixture file's mtime
NOW = WRITTEN + 600  # ten minutes later
# The checkouts read, named when no run matches (#586): the fixture has no -ui checkout's folder.
READ = ("checkouts read: main D--prime-game; ui (prime-game-ui) not on this machine, its spend unknown here; art "
        "D--prime-game-art")  # fmt: skip


def journal(folder: Path, lines: list[dict]) -> None:
    write_lines(folder / "journal.jsonl", [{"type": "launched"}, *lines])


def started(key: str, aid: str, label: str, phase: str) -> dict:
    return {"type": "started", "key": key, "agentId": aid, "label": label, "phase": phase}


def result(key: str, aid: str) -> dict:
    return {"type": "result", "key": key, "agentId": aid, "result": {"ok": True}}


class RunFixture:
    """A config folder with three runs; each API call below is 1% of the week.

    D--prime-game/s-main  wf_abc12345-111, in flight: an implementer that died (1%) and its retry (its message written
                          twice, counted once, and one more: 2%), answered; a code review started (1%), no result; a
                          godot-api review started with no transcript yet: 4% in all, 4 agents.
                          wf_other-333: never matched by "abc".
    D--prime-game-art/s-art wf_abc99999-222, finished: one agent answered (1%) and a synthesis agent the journal does
                          not list (a journal cut short; its .meta.json names it): 2%.
    """

    def __init__(self, root: Path) -> None:
        p = root / "projects"
        self.live = p / "D--prime-game" / "s-main" / "subagents" / "workflows" / "wf_abc12345-111"
        write_lines(self.live / "agent-a-dead.jsonl", [assistant(0, "d1", ONE)])
        write_lines(self.live / "agent-a-impl.jsonl", [assistant(5, "i1", ONE), assistant(5, "i1", ONE),
                                                       assistant(6, "i2", ONE)])  # fmt: skip
        write_lines(self.live / "agent-a-rev.jsonl", [assistant(10, "r1", ONE)])
        journal(self.live, [
            started("k1", "a-dead", "implement:#5", "Implement"),
            started("k1", "a-impl", "implement:#5", "Implement"),
            result("k1", "a-impl"),
            started("k2", "a-rev", "review:code:#5", "Review"),
            started("k3", "a-god", "review:godot-api:#5", "Review"),
        ])
        other = p / "D--prime-game" / "s-main" / "subagents" / "workflows" / "wf_other-333"
        journal(other, [started("k", "a-o", "implement:#6", "Implement")])
        write_lines(other / "agent-a-o.jsonl", [assistant(0, "o1", ONE)])
        self.done = p / "D--prime-game-art" / "s-art" / "subagents" / "workflows" / "wf_abc99999-222"
        write_lines(self.done / "agent-a-art.jsonl", [assistant(0, "x1", ONE)])
        write_lines(self.done / "agent-a-syn.jsonl", [assistant(1, "x2", ONE)])
        (self.done / "agent-a-syn.meta.json").write_text(
            json.dumps({"description": "synthesis", "workflowPhase": "Synthesis"}), encoding="utf-8")
        journal(self.done, [started("k", "a-art", "critic:clay", "Prototypes"), result("k", "a-art")])
        for folder in (self.live, other, self.done):
            for f in folder.iterdir():
                os.utime(f, (WRITTEN, WRITTEN))


class RunsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fx = RunFixture(self.root)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_main(self, *ids: str) -> str:
        buf = io.StringIO()
        with redirect_stdout(buf):
            rc = metrics.runs_main(list(ids), checkout=CHECKOUT, base=self.root, now=NOW)
        self.assertEqual(rc, 0)
        return buf.getvalue()

    def test_a_run_in_flight_so_far(self) -> None:
        self.assertEqual(self.run_main("abc12345").splitlines(), [
            "run wf_abc12345-111 (session s-main, D--prime-game): unfinished (in flight, or stopped); 3 agents started (4 "
            "agent runs: a retry, or one the journal does not list), 1 answered; working now: review:code:#5 (Review), "
            "review:godot-api:#5 (Review); last write 10 min ago",
            "spent so far: 4.0% (4.3 to 3.6%) of the week, list $92 in 4 API calls",
            "by phase: Implement $69 (2 agents), Review $23 (2 agents)",
            "context per API call avg/peak (#584; heavy: average 150k+ or peak 300k+ per call): implement:#5 "
            "5.75M/5.75M x1 heavy, implement:#5 (2) 5.75M/5.75M x2 heavy, review:code:#5 5.75M/5.75M x1 heavy",
        ])

    def test_a_finished_run_of_another_checkout_with_a_journal_cut_short(self) -> None:
        self.assertEqual(self.run_main("wf_abc99999-222").splitlines(), [
            "run wf_abc99999-222 (session s-art, D--prime-game-art): finished; 1 agent started (2 agent runs: a retry, "
            "or one the journal does not list), 1 answered; last write 10 min ago",
            "spent so far: 2.0% (2.1 to 1.8%) of the week, list $46 in 2 API calls",
            "by phase: Prototypes $23 (1 agent), Synthesis $23 (1 agent)",
            "context per API call avg/peak (#584; heavy: average 150k+ or peak 300k+ per call): critic:clay "
            "5.75M/5.75M x1 heavy, synthesis 5.75M/5.75M x1 heavy",
        ])

    def test_a_prefix_names_several_runs_and_their_total(self) -> None:
        lines = self.run_main("wf_abc").splitlines()
        self.assertEqual([line.split(" (")[0] for line in lines if line.startswith("run ")],
                         ["run wf_abc12345-111", "run wf_abc99999-222"])  # fmt: skip
        self.assertEqual(lines[-1], "2 runs: 6.0% (6.4 to 5.4%) of the week, list $138")
        self.assertEqual(len(self.run_main("abc12345", "wf_abc12345-111").splitlines()), 4, "each run once")

    def test_cache_reads_weigh_less(self) -> None:
        # The review's call reads 115M tokens from the cache: $23 list, 0.75% at the central weight (0.75 x $23 / $23);
        # the bracket: ($69 + 0.6 x $23) / $21.5 and $92 / $25.5.
        write_lines(self.fx.live / "agent-a-rev.jsonl", [assistant(10, "r1", usage(read=115_000_000))])
        line = self.run_main("abc12345").splitlines()[1]
        self.assertEqual(line, "spent so far: 3.8% (3.9 to 3.6%) of the week, list $92 in 4 API calls")
        self.assertAlmostEqual(metrics.run_spend(self.fx.live, NOW)["read_usd"], 23.0)

    def test_an_id_that_names_no_run_is_said_so_beside_one_that_does(self) -> None:
        # wf_b may be a run of a checkout not on this machine: its spend is unknown here, not absent (#586).
        lines = self.run_main("abc12345", "wf_b").splitlines()
        self.assertEqual(lines[0], f"wf_b: no run here ({READ})")
        self.assertTrue(lines[1].startswith("run wf_abc12345-111 "), lines[1])
        self.assertTrue(lines[-1].startswith("context per API call"), "#584's line stays last")
        self.assertFalse(any(line.startswith("wf_abc12345") for line in lines), "a run found is not 'no run'")

    def test_mistakes_fail(self) -> None:
        with self.assertRaises(Failure) as caught:
            metrics.runs_main(["wf_nosuch"], checkout=CHECKOUT, base=self.root, now=NOW)
        self.assertIn("no workflow run named wf_nosuch", str(caught.exception))
        self.assertIn(READ, str(caught.exception))
        for extra in ({"since": "2026-10-06T10:00:00Z"}, {"track": ["game"]}, {"compact": True}, {"sessions": ["x"]},
                      {"out": "x"}):
            with self.subTest(extra), self.assertRaises(Failure) as caught:
                metrics.main(run_ids=["abc"], dirs=[], history=[], **extra)
            self.assertIn("--run stands alone", str(caught.exception))

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(["metrics", "--run", "wf_a", "wf_b", "--run", "c"])
        self.assertEqual(args.run, ["wf_a", "wf_b", "c"])
        self.assertEqual(cli.build_parser().parse_args(["metrics"]).run, [])


if __name__ == "__main__":
    unittest.main()
