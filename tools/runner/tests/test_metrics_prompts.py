"""`metrics`' launch prompt size per agent role (#470): the first user message of each workflow agent, from small
synthetic transcripts written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import SESSION, UNTIL, Fixture, assistant, at, usage, write_lines


def prompt(text: str | list) -> dict:
    return {"type": "user", "timestamp": at(0), "message": {"role": "user", "content": text}}


def task(n: int, start: float, pub_chars: int, rev_chars: int | None) -> list[tuple]:
    """A finished run of issue n: an implementer without a prompt line, a code reviewer (a prompt of rev_chars
    characters, none when None) and a publisher whose prompt is pub_chars characters."""
    return [
        ("k-i", f"a-i{n}", f"implement:#{n}", "Implement", {"verify_green": True}, [
            assistant(start, f"msg-i{n}", usage(inp=10, write=1000, out=10)),
        ]),
        ("k-c", f"a-c{n}", f"review:code:#{n}", "Review", {"findings": []}, [
            *([prompt("r" * rev_chars)] if rev_chars else []),
            assistant(start + 1, f"msg-c{n}", usage(inp=2, write=500, out=30)),
        ]),
        ("k-p", f"a-p{n}", f"publish:#{n}", "Publish", {"pr_number": 100 + n, "ci_green": True}, [
            prompt("p" * pub_chars),
            assistant(start + 2, f"msg-p{n}", usage(inp=3, write=800, out=40)),
            prompt("a later message that is not the launch prompt " * 50),
        ]),
    ]  # fmt: skip


class PromptSizeTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.fx = Fixture(Path(self.tmp.name))
        wf = self.fx.dir / SESSION / "subagents" / "workflows"
        Fixture.run(wf / "wf_a", task(11, 50, 1000, 400))
        Fixture.run(wf / "wf_b", task(12, 70, 3000, None))
        Fixture.run(wf / "wf_c", task(13, 90, 2000, 600))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.fx.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, None, metrics.parse_time(UNTIL))

    def test_the_first_user_message_gives_the_size(self) -> None:
        path = Path(self.tmp.name) / "agent.jsonl"
        write_lines(path, [prompt([{"type": "text", "text": "x" * 120}]), assistant(0, "m1", usage(inp=1)), prompt("y" * 9)])
        self.assertEqual(metrics.read_agent(path)["prompt_chars"], 120)
        write_lines(path, [assistant(0, "m1", usage(inp=1))])
        self.assertIsNone(metrics.read_agent(path)["prompt_chars"])

    def test_a_relayed_user_request_before_the_prompt_is_not_counted(self) -> None:
        path = Path(self.tmp.name) / "agent.jsonl"
        relay = prompt("[Workflow harness - user request] " + "u" * 100)
        write_lines(path, [relay, prompt("t" * 700), assistant(0, "m1", usage(inp=1)), prompt("later " * 99)])
        self.assertEqual(metrics.read_agent(path)["prompt_chars"], 700)

    def test_median_and_max_per_role(self) -> None:
        _md, record, _compact = self.build()
        rows = {r["role"]: r for r in record["prompt_sizes"]}
        pub = rows["publisher"]
        self.assertEqual((pub["agents"], pub["median_chars"], pub["max_chars"]), (3, 2000, 3000))
        self.assertAlmostEqual(pub["median_tokens"], 2000 / metrics.CHARS_PER_TOKEN)
        self.assertAlmostEqual(pub["max_tokens"], 3000 / metrics.CHARS_PER_TOKEN)
        rev = rows["code-reviewer"]  # one run has no reviewer prompt: two agents, median of 400 and 600
        self.assertEqual((rev["agents"], rev["median_chars"], rev["max_chars"]), (2, 500, 600))
        self.assertNotIn("implementer", rows)  # no prompt in any implementer transcript: no row
        self.assertEqual([r["role"] for r in record["prompt_sizes"]][:2], ["publisher", "code-reviewer"])

    def test_the_table_is_in_the_report_and_not_in_the_compact_summary(self) -> None:
        md, _record, compact = self.build()
        body = "\n".join(md)
        self.assertIn("## Launch prompt size per agent role (#470)", body)
        self.assertIn("| publisher | 3 | 2,000 / 3,000 | 0.9k / 1.3k |", body)
        self.assertIn("| code-reviewer | 2 | 500 / 600 | 0.2k / 0.3k |", body)
        self.assertNotIn("Launch prompt size", "\n".join(compact))
        self.assertEqual(metrics.prompt_section([]), [])


if __name__ == "__main__":
    unittest.main()
