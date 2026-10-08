"""`metrics` by agent type (#557): which agents of the task workflows ran as the general type (workflow-subagent)
instead of a lean type, per run, in the report, the JSON record, the compact summary and `--run`, over small
synthetic transcripts written here (never real ones)."""

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import SESSION, UNTIL, assistant, usage, write_lines

CHECKOUT = Path("D:/prime-game")


def run(folder: Path, agents: list[tuple[str, str, str, int]]) -> None:
    """A finished run: (agent id, label, agentType, first-call context) each, two API calls per agent."""
    journal: list[dict] = [{"type": "launched"}]
    for i, (aid, label, agent_type, first) in enumerate(agents):
        write_lines(folder / f"agent-{aid}.jsonl", [
            assistant(i, f"{aid}-1", usage(inp=first // 2, write=first - first // 2, out=10)),
            assistant(i + 0.5, f"{aid}-2", usage(inp=1, read=first, out=10)),
        ])  # fmt: skip
        meta = {"agentType": agent_type, "description": label, "workflowPhase": "P"}
        (folder / f"agent-{aid}.meta.json").write_text(json.dumps(meta), encoding="utf-8")
        journal += [
            {"type": "started", "key": aid, "agentId": aid, "label": label, "phase": "P"},
            {"type": "result", "key": aid, "agentId": aid, "result": {"ok": True}},
        ]
    write_lines(folder / "journal.jsonl", journal)


class AgentTypeTest(unittest.TestCase):
    """wf_general: #5, an implementer on the general type, a code reviewer and a lean publisher.
    wf_lean:    #6, a lean implementer and publisher.
    wf_rebase:  PR 7, a lean rebase agent."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.dir = Path(self.tmp.name) / "projects" / "D--prime-game"
        wf = self.dir / SESSION / "subagents" / "workflows"
        run(wf / "wf_general", [
            ("g-impl", "implement:#5", "workflow-subagent", 58_000),
            ("g-rev", "review:code:#5", "code-reviewer", 30_000),
            ("g-pub", "publish:#5", "task-publisher", 30_000),
        ])  # fmt: skip
        run(wf / "wf_lean", [("l-impl", "implement:#6", "task-implementer", 24_000), ("l-pub", "publish:#6", "task-publisher", 30_000)])
        run(wf / "wf_rebase", [("r-reb", "rebase:#7", "task-publisher", 30_000)])

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, None, metrics.parse_time(UNTIL))

    def test_the_first_call_is_read(self) -> None:
        data = metrics.read_agent(self.dir / SESSION / "subagents" / "workflows" / "wf_general" / "agent-g-impl.jsonl")
        self.assertEqual(data["first_ctx"], 58_000)

    def test_the_report_counts_agents_and_dollars_per_role_and_type(self) -> None:
        md, record, compact = self.build()
        types = record["agent_types"]
        self.assertEqual(types["writers"], {"general": 1, "all": 5})
        rows = {(r["role"], r["type"]): r for r in types["rows"]}
        self.assertEqual(set(rows), {
            ("implementer", "workflow-subagent"), ("implementer", "task-implementer"), ("code-reviewer", "code-reviewer"),
            ("publisher", "task-publisher"), ("pr-rebase", "task-publisher"),
        })  # fmt: skip
        self.assertEqual(rows[("publisher", "task-publisher")]["agents"], 2)
        self.assertEqual(rows[("implementer", "workflow-subagent")]["first_ctx"], 58_000)
        self.assertGreater(rows[("implementer", "workflow-subagent")]["usd"], rows[("implementer", "task-implementer")]["usd"])
        text = "\n".join(md)
        self.assertIn("## Per agent type (#557)", text)
        self.assertIn("Implementers, planners, test reviewers, publishers and pr-rebase agents on the general type "
                      "(workflow-subagent): 1 of 5", text)
        # Each run of the record names its agent types.
        by_wf = {r["wf"]: r for r in record["runs"]}
        self.assertEqual(by_wf["wf_general"]["types"], {"workflow-subagent": 1, "code-reviewer": 1, "task-publisher": 1})
        self.assertEqual(by_wf["wf_lean"]["types"], {"task-implementer": 1, "task-publisher": 1})
        # The compact summary keeps its line count: the count goes on its first line.
        self.assertIn("; general-type writers 1 of 5 (#557)", compact[0])

    def test_no_general_writer_reads_zero(self) -> None:
        general = self.dir / SESSION / "subagents" / "workflows" / "wf_general"
        for f in general.iterdir():
            f.unlink()
        general.rmdir()
        md, record, compact = self.build()
        self.assertEqual(record["agent_types"]["writers"], {"general": 0, "all": 3})
        self.assertIn("; general-type writers 0 of 3 (#557)", compact[0])

    def test_run_names_its_agent_types(self) -> None:
        base = Path(self.tmp.name)
        for f in self.dir.rglob("*"):
            if f.is_file():
                os.utime(f, (1_000_000.0, 1_000_000.0))
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertEqual(metrics.runs_main(["wf_general"], checkout=CHECKOUT, base=base, now=1_000_600.0), 0)
        lines = buf.getvalue().splitlines()
        self.assertEqual(len(lines), 3, lines)
        self.assertTrue(lines[2].startswith("by phase: P "), lines[2])
        self.assertTrue(lines[2].endswith("; agent types: workflow-subagent 1, code-reviewer 1, task-publisher 1"), lines[2])


if __name__ == "__main__":
    unittest.main()
