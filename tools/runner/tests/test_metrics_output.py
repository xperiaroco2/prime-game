"""`metrics`' tool output per implementer (#572: what each tool call's output adds to every later call's context, and
the part of the runner's commands, compared between a wave before a change and one after it) and its quiet
`--compact`, from small synthetic transcripts written here (never real ones)."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, metrics
from runner.tests.test_metrics import SUMMARY, UNTIL, Fixture, assistant, bash, tool_result, usage, write_lines


class ToolOutputTest(unittest.TestCase):
    def test_read_agent_counts_each_tool_outputs_characters_and_the_runner_commands_part(self) -> None:
        lines = [
            assistant(0, "m0", usage(inp=1, write=100), tool=bash("t1", "cd /c/w && tools/run.sh wait /c/s/v.log")),
            tool_result(0.5, "t1", "w" * 470),
            assistant(1, "m1", usage(inp=1, read=100), tool=bash("t2", "git status")),
            tool_result(1.5, "t2", "g" * 100),
            assistant(2, "m2", usage(inp=1, read=100), tool=bash("t3", "tools\\run.cmd lint")),
            tool_result(2.5, "t3", "l" * 30),
            assistant(3, "m3", usage(inp=1, read=100), tool=bash("t4", "tools/run.sh merge-check")),  # not a loop's
            tool_result(3.5, "t4", "m" * 7),
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "agent.jsonl"
            write_lines(path, lines)
            data = metrics.read_agent(path)
        self.assertEqual(data["tool_output"], 470 + 100 + 30 + 7)
        self.assertEqual(data["runner_output"], 470 + 30)

    def test_each_task_keeps_its_implementers_outputs_and_the_compact_line_gives_their_medians(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fx = Fixture(Path(tmp))
            data = metrics.collect([fx.dir], {}, None, metrics.parse_time(UNTIL))
            _md, record, compact = metrics.build(data, [], None, None, metrics.parse_time(UNTIL))
        task = next(t for t in record["tasks"] if t["issue"] == 5)
        chars = len("lint ok\n" + SUMMARY) + len(SUMMARY)  # its verify's and its publish's outputs, both the runner's
        self.assertEqual(len(task["impl_outputs"]), 1, "the attempt that died before any tool call is left out")
        tokens, runner = task["impl_outputs"][0]
        self.assertAlmostEqual(tokens, chars / metrics.CHARS_PER_TOKEN)
        self.assertAlmostEqual(runner, chars / metrics.CHARS_PER_TOKEN)
        medians = next(line for line in compact if line.startswith("task medians"))
        k = metrics.fmt_k(chars / metrics.CHARS_PER_TOKEN)
        self.assertTrue(medians.endswith(f"; tool output per implementer median {k} tokens, runner commands {k} (#572)"))

    def test_no_clause_without_an_implementer(self) -> None:
        tasks = [{"issue": 1, "wall": 60.0, "usd": 1.0, "ctx": 10, "calls": 3}]
        week = {"percent": 1.0, "bracket": (0.9, 1.1)}
        lines = metrics.compact_lines(tasks, [], {}, [], None, [], week, "w")
        medians = next(line for line in lines if line.startswith("task medians"))
        self.assertNotIn("tool output per implementer", medians)


LONG = "local verify (agents): " + ", ".join(f"step{n} {n}" for n in range(80))


class QuietCompactTest(unittest.TestCase):
    """--compact prints the summary lines cut at LINE_CAP unless --verbose (#572); metrics.md keeps them whole."""

    def compact(self, verbose: bool) -> tuple[str, str]:
        with tempfile.TemporaryDirectory() as tmp:
            out = io.StringIO()
            with (
                mock.patch.object(metrics, "collect", return_value={"sessions": [1], "other_sessions": 0}),
                mock.patch.object(metrics, "read_history", return_value=[]),
                mock.patch.object(metrics, "build", return_value=(["## A section"], {}, ["metrics, w: 1 run", LONG])),
                contextlib.redirect_stdout(out),
            ):
                rc = metrics.main(compact=True, until=UNTIL, out=tmp, dirs=[Path(tmp)], history=[], no_gh=True,
                                  verbose=verbose)  # fmt: skip
            self.assertEqual(rc, 0)
            return out.getvalue(), (Path(tmp) / "metrics.md").read_text(encoding="utf-8")

    def test_a_line_over_the_cap_is_cut_and_the_footer_names_metrics_md(self) -> None:
        printed, md = self.compact(verbose=False)
        lines = printed.splitlines()
        self.assertEqual(lines[0], "metrics, w: 1 run")
        self.assertEqual(lines[1], LONG[: metrics.LINE_CAP] + " ...")
        self.assertRegex(lines[2], r"^\(lines over 400 characters cut; whole: .*metrics\.md, or --verbose\)$")
        self.assertEqual(len(lines), 3)
        self.assertIn(LONG, md)

    def test_verbose_prints_each_line_whole(self) -> None:
        printed, _md = self.compact(verbose=True)
        self.assertEqual(printed.splitlines(), ["metrics, w: 1 run", LONG])

    def test_the_cli_passes_verbose_on(self) -> None:
        with mock.patch.object(metrics, "main", return_value=0) as main:
            cli.main(["metrics", "--compact"])
            cli.main(["metrics", "--compact", "--verbose"])
        self.assertEqual([c.kwargs["verbose"] for c in main.call_args_list], [False, True])


if __name__ == "__main__":
    unittest.main()
