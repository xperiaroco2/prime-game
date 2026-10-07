"""`metrics`' plan phase (#469): the files each agent read, and per run with a planner its $, the planner files the
implementer read too and the critique's findings, from small synthetic transcripts written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import assistant, bash, tool_result, usage, write_lines
from runner.tests.test_metrics_instructions import read

WT = "/d/prime-game/.claude/worktrees/469"


class FilesReadTest(unittest.TestCase):
    def test_every_file_an_agent_reads_and_no_search(self) -> None:
        root = metrics.REPO_ROOT
        calls = [
            (read("r1", root / ".claude" / "worktrees" / "469" / "core" / "match" / "vote.gd", offset=1, limit=20), "x"),
            (read("r2", root / "docs" / "ARCHITECTURE.md"), "x"),  # a doc
            (read("r3", root / ".claude" / "skills" / "start-task" / "SKILL.md"), "x"),  # any file
            (bash("b1", f"cd {WT} && sed -n '1,40p' tools/runner/metrics.py"), "x"),  # a code read
            (bash("b2", f"cd {WT} && cat docs/AGENT_WORKFLOW.md"), "x"),  # a shell read of a doc
            ({"id": "g1", "name": "Grep", "input": {"pattern": "x", "path": str(root / "docs" / "GDD.md")}}, "x"),
            (bash("b3", f"cd {WT} && grep -n plan tools/runner/start.py"), "x"),  # a search
            (read("r4", Path("C:/elsewhere/notes.txt")), "x"),  # outside the repository
        ]
        lines: list[dict] = []
        for index, (tool, text) in enumerate(calls):
            lines.append(assistant(index, f"m{index}", usage(inp=10, out=5), tool=tool))
            lines.append(tool_result(index + 0.5, tool["id"], text))
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "agent.jsonl"
            write_lines(path, lines)
            got = metrics.read_agent(path)["files_read"]
        self.assertEqual(
            got,
            [".claude/skills/start-task/SKILL.md", "core/match/vote.gd", "docs/AGENT_WORKFLOW.md", "docs/ARCHITECTURE.md",
             "tools/runner/metrics.py"],
        )  # fmt: skip


def agent(role: str, usd: float, files: list[str], result: dict | None = None, model: str = "claude-opus-5-5") -> dict:
    tokens = {"usd_input": usd, "usd_cache_write": 0.0, "usd_cache_read": 0.0, "usd_output": 0.0}
    return {"role": role, "result": result, "data": {"start": 1.0, "tokens": tokens, "files_read": files, "model": model}}


MAJOR = {"severity": "major"}
MINOR = {"severity": "minor"}


class PlanPhaseTest(unittest.TestCase):
    def test_the_plan_rows_and_their_table(self) -> None:
        counted = [
            {"session": "s", "issue": 312, "wf": "wf1", "agents": [
                agent("planner", 3.0, ["a.gd", "b.gd", "c.md", "d.py"], model="claude-sonnet-5-5"),
                agent("plan-reviewer", 1.5, ["a.gd"], {"findings": [MAJOR, MINOR, MINOR]}),
                agent("implementer", 6.0, ["a.gd", "b.gd", "e.gd"]),
                agent("code-reviewer", 1.0, ["a.gd", "b.gd", "c.md", "d.py"], {"findings": [MAJOR]}),
            ]},
            # A planner retried after its first attempt died: both attempts spent and read; the critique was cut off.
            {"session": "s", "issue": 332, "wf": "wf2", "agents": [
                agent("planner", 1.0, ["a.gd"]),
                agent("planner", 2.0, ["b.gd"]),
                {"role": "plan-reviewer", "result": None, "data": None},
                agent("implementer", 4.0, ["b.gd"]),
            ]},
            {"session": "s", "issue": 400, "wf": "wf3", "agents": [agent("implementer", 5.0, ["a.gd"])]},  # no plan
        ]  # fmt: skip
        rows = metrics.plan_rows(counted)
        self.assertEqual([r["issue"] for r in rows], [312, 332])
        first, second = rows
        self.assertEqual(
            {k: first[k] for k in ("model", "plan_usd", "critique_usd", "planner_files", "reread", "findings", "serious")},
            {"model": "claude-sonnet-5-5", "plan_usd": 3.0, "critique_usd": 1.5, "planner_files": 4, "reread": 2,
             "findings": 3, "serious": 1},
        )  # fmt: skip
        self.assertEqual((second["plan_usd"], second["critique_usd"], second["planner_files"]), (3.0, 0.0, 2))
        self.assertEqual((second["reread"], second["findings"], second["serious"]), (1, None, 0))
        md = metrics.plan_section(rows)
        self.assertEqual(md[0], "## Plan phase (#469)")
        body = "\n".join(md)
        self.assertIn("| #312 | claude-sonnet-5-5 | $3.00 | $1.50 | $4.50 | 4 | 2 (50%) | 3 / 1 |", body)
        self.assertIn("| #332 | claude-opus-5-5 | $3.00 | $0.00 | $3.00 | 2 | 1 (50%) | - |", body)
        self.assertIn("Plan + critique: mean $3.75 over 2 runs; the implementers re-read 3 of 6 planner files (50%).", body)
        # A run with no implementer yet: its re-reads are unknown and out of the total.
        rows = metrics.plan_rows([{"session": "s", "issue": 9, "wf": "w", "agents": [agent("planner", 1.0, ["a.gd"])]}])
        self.assertIsNone(rows[0]["reread"])
        self.assertIn("| #9 | claude-opus-5-5 | $1.00 | $0.00 | $1.00 | 1 | - | - |", "\n".join(metrics.plan_section(rows)))
        self.assertEqual(metrics.plan_section([]), [])


if __name__ == "__main__":
    unittest.main()
