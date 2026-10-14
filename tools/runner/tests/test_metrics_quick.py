"""`metrics` reads quick-task runs as their own kind (#1012): by the workflow's name (the session's saved script, else
its saved run record) or its Quick phase; their own rows, medians and quality summary, out of the issue-task tables,
the other runs and the issue-task relaunch reading; from fixture journals written here (never real transcripts)."""

import json
import tempfile
import unittest
from pathlib import Path

from runner import metrics, wave
from runner.tests.test_metrics import REPO, UNTIL, Fixture, assistant, ci_run, gh_stub, pull, usage

SID = "77777777-0000-0000-0000-000000000000"
PUB = {"pr_number": 61, "pr_url": f"{REPO}61", "ci_green": True, "changed_paths": ["docs/a.md"], "summary": "s"}


def lines(tag: str, start: float, end: float) -> list[dict]:
    return [assistant(start, f"{tag}-1", usage(inp=1000, out=10)), assistant(end, f"{tag}-2", usage(inp=1000, out=10))]


def quick(n: int, start: float, end: float, result: dict | None, phase: str = "Quick") -> tuple:
    return (f"k-q{n}{start:g}", f"a-q{n}{start:g}", f"publish:#{n}", phase, result, lines(f"q{n}{start:g}", start, end))


def review(n: int, start: float, findings: list[dict]) -> tuple:
    return (f"k-r{n}", f"a-r{n}", f"review:code:#{n}", "Review", {"findings": findings}, lines(f"r{n}", start, start + 2))


class QuickTaskTest(unittest.TestCase):
    """A session with:
    wf_q1 #51 (minutes 0-12): quick-task by its saved script; a docs-only change, PR 61, CI green, no reviewer.
    wf_q2 #52 (20-50): quick-task by its saved run record (no script file); a code review with a major, a fix agent
          that fixed it (open 0) and turned CI green; PR 62.
    wf_q3 #53 (60-70): quick-task by its Quick phase alone (no saved script or record); PR 63.
    wf_r  #54 (80-90): a resumed issue-task run (a publisher alone, its script issue-task's): unchanged.
    wf_i  #51 (100-130): an issue-task run on #51 after its quick-task run.
    """

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "projects" / "D--prime-game"
        wf = self.dir / SID / "subagents" / "workflows"
        saved = self.dir / SID / "workflows"
        (saved / "scripts").mkdir(parents=True)
        (saved / "scripts" / "quick-task-wf_q1.js").write_text("export const meta = { name: 'quick-task' }\n")
        (saved / "scripts" / "issue-task-wf_r.js").write_text("export const meta = { name: 'issue-task' }\n")
        script = "export const meta = {\n  name: 'quick-task',\n  description: 'x',\n}\n"
        (saved / "wf_q2.json").write_text(json.dumps({"runId": "wf_q2", "script": script}), encoding="utf-8")
        Fixture.run(wf / "wf_q1", [quick(51, 0, 12, PUB)])
        Fixture.run(wf / "wf_q2", [
            quick(52, 20, 30, {**PUB, "pr_number": 62, "pr_url": f"{REPO}62", "ci_green": False}, phase="Quick"),
            review(52, 31, [{"severity": "major", "problem": "p"}, {"severity": "nit", "problem": "q"}]),
            ("k-f52", "a-f52", "fix:#52", "Review", {"fixed": ["the major"], "open": 0, "ci_green": True},
             lines("f52", 34, 50)),
        ])  # fmt: skip
        Fixture.run(wf / "wf_q3", [quick(53, 60, 70, {**PUB, "pr_number": 63, "pr_url": f"{REPO}63"})])
        Fixture.run(wf / "wf_r", [quick(54, 80, 90, {"pr_number": 64, "ci_green": True}, phase="Publish")])
        Fixture.run(wf / "wf_i", [
            ("k-i51", "a-i51", "implement:#51", "Implement", {"verify_green": True}, lines("i51", 100, 110)),
            ("k-p51", "a-p51", "publish:#51", "Publish", {"pr_number": 65, "ci_green": True}, lines("p51", 111, 130)),
        ])  # fmt: skip

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def collect(self) -> dict:
        return metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))

    def runs(self) -> dict[str, dict]:
        return {r["wf"]: r for r in self.collect()["runs"]}

    def build(self, github: dict | None = None, ci: dict | None = None) -> tuple[list[str], dict, list[str]]:
        until = metrics.parse_time(UNTIL)
        return metrics.build(self.collect(), [], ci, None, until, github=github)

    def test_kind_by_script_saved_run_or_quick_phase(self) -> None:
        runs = self.runs()
        got = {wf: (r["kind"], r["workflow"]) for wf, r in runs.items()}
        self.assertEqual(got, {
            "wf_q1": ("quick-task", "quick-task"), "wf_q2": ("quick-task", "quick-task"), "wf_q3": ("quick-task", None),
            "wf_r": ("issue-task (resumed)", "issue-task"), "wf_i": ("issue-task", None),
        })  # fmt: skip

    def test_a_named_workflow_is_not_read_by_its_phase(self) -> None:
        script = self.dir / SID / "workflows" / "scripts" / "night-audit-wf_q3.js"
        script.write_text("export const meta = { name: 'night-audit' }\n")
        self.assertEqual(self.runs()["wf_q3"]["kind"], "issue-task (resumed)")

    def test_quick_runs_have_their_own_rows_and_medians(self) -> None:
        md, record, _compact = self.build()
        quick = record["quick_tasks"]
        rows = {q["wf"]: q for q in quick["tasks"]}
        self.assertEqual(sorted(rows), ["wf_q1", "wf_q2", "wf_q3"])
        self.assertEqual([p["wf"] for p in record["tasks"]], ["wf_i"])
        self.assertEqual([q["wf"] for q in record["quality"]["tasks"]], ["wf_i"])
        q1, q2 = rows["wf_q1"], rows["wf_q2"]
        self.assertEqual((q1["wall"], q1["pr"], q1["ci_green"], q1["fix_agent"]), (720.0, 61, True, False))
        self.assertIsNone(q1["serious"], "no reviewer: unknown, never 0")
        self.assertEqual((q2["serious"], q2["open"], q2["clean"], q2["fixed"]), (1, 0, True, 1))
        self.assertTrue(q2["fix_agent"])
        self.assertTrue(q2["ci_green"], "the fix agent's CI, not the quick agent's red")
        self.assertIsNone(q2["fix_rounds"], "no publisher fix round in a quick-task run")
        m = quick["medians"]
        self.assertEqual((m["runs"], m["wall"], m["fix_agents"]), (3, 720.0, 1))
        self.assertEqual(m["ci_rounds"]["known"], 0, "CI rounds come from gh")
        text = "\n".join(md)
        section = text[text.index("## Per finished quick-task run (#1012, minutes)"):]
        self.assertIn("| #52 | 30 | 10 | 19 |", section)
        self.assertIn("quick-task: 3 runs, medians 12 min", section)

    def test_quick_runs_are_not_other_runs_or_resumed_issue_tasks(self) -> None:
        md, _record, _compact = self.build()
        text = "\n".join(md)
        other = text[text.index("## Other runs"):].split("\n\n")[1]
        self.assertIn("wf_r", other)
        for wf in ("wf_q1", "wf_q2", "wf_q3"):
            self.assertNotIn(wf, other)
        self.assertEqual(text.count("issue-task (resumed)"), 1, "wf_r alone")

    def test_relaunch_table_names_the_quick_task_run(self) -> None:
        _md, record, _compact = self.build()
        rows = {x["issue"]: x for x in record["relaunches"]}
        self.assertEqual(list(rows), [51])
        self.assertEqual(rows[51]["kinds"], {"quick-task": 1, "issue-task": 1})

    def test_quality_summary_from_github(self) -> None:
        github = metrics.read_github(gh_stub({
            "prs": [pull(61, "docs/51-a", 5, state="MERGED"), pull(62, "tooling/52-b", 25)],
            "runs": [ci_run("docs/51-a", "s1", "success", 6), ci_run("tooling/52-b", "s2", "failure", 26),
                     ci_run("tooling/52-b", "s3", "success", 45)],
            "issues": [],
        }))  # fmt: skip
        md, record, compact = self.build(github)
        rows = {q["wf"]: q for q in record["quick_tasks"]["tasks"]}
        self.assertEqual((rows["wf_q1"]["ci_rounds"], rows["wf_q1"]["merged"]), (1, True))
        self.assertEqual((rows["wf_q2"]["ci_rounds"], rows["wf_q2"]["ci_red_rounds"]), (2, 1))
        self.assertEqual(record["quick_tasks"]["medians"]["ci_rounds"]["median"], 1.5)
        summary = record["quality"]["quick"]
        self.assertEqual((summary["session"], summary["tasks"], summary["prs"], summary["merged"]), ("quick-task", 3, 3, 1))
        text = "\n".join(md)
        self.assertIn("| quick-task | 3 | 3 (1 merged) |", text[text.index("## Quality per finished issue-task run"):])
        line = next(x for x in compact if x.startswith("quality: "))
        self.assertTrue(line.startswith("quality: 1 tasks"), "the issue-task scorecard keeps its own runs")
        self.assertIn("| quick-task (#1012): 3 runs, medians 12 min", line)
        self.assertIn("CI rounds 1.5 (2/3); a fix agent in 1; 3 PRs (1 merged); blockers+majors 1 (0 open)", line)

    def test_compact_keeps_its_line_count(self) -> None:
        ci = {"runs": 1, "by_outcome": {}, "reruns": 0, "queue_s": 0.0, "green": 1, "job_s": [60.0],
              "steps": {"verify total": [50.0]}}  # fmt: skip
        history = [{"steps": {"lint": ("passed", 20.0)}, "total": 20.0, "status": "passed", "via": "history",
                    "t": metrics.parse_time(UNTIL) - 60, "wait": None, "over": False}]  # fmt: skip
        until = metrics.parse_time(UNTIL)
        _md, _record, compact = metrics.build(self.collect(), history, ci, None, until, github={"skipped": "--no-gh"})
        self.assertLessEqual(len(compact), 11)
        self.assertIn("1 finished issue-task runs, 3 finished quick-task runs, 1 other runs (0 unfinished)", compact[0])
        self.assertTrue(compact[1].endswith("| quick-task: #51 12 min $0.01, #52 30 min $0.03, #53 10 min $0.01"))
        total = next(x for x in compact if x.startswith("total API list $"))
        self.assertIn("+ quick tasks $0.04 + other runs", total)
        self.assertTrue(compact[-1].startswith("CI: 1 runs"))

    def test_compact_without_a_finished_issue_task_run_gives_quick_tasks_a_line(self) -> None:
        for wf in ("wf_i", "wf_r"):
            for p in (self.dir / SID / "subagents" / "workflows" / wf).iterdir():
                p.unlink()
        _md, _record, compact = self.build()
        self.assertIn(": 0 finished issue-task runs, 3 finished quick-task runs, 0 other runs", compact[0])
        line = next(x for x in compact if x.startswith("quick-task (#1012): 3 runs"))
        self.assertTrue(line.endswith("; per run (wall min, API list $): #51 12 min $0.01, #52 30 min $0.03, "
                                      "#53 10 min $0.01"))  # fmt: skip

    def test_no_quick_run_leaves_the_compact_summary_as_before(self) -> None:
        for wf in ("wf_q1", "wf_q2", "wf_q3"):
            for p in (self.dir / SID / "subagents" / "workflows" / wf).iterdir():
                p.unlink()
        md, record, compact = self.build()
        self.assertEqual(record["quick_tasks"]["tasks"], [])
        self.assertIsNone(record["quality"]["quick"])
        self.assertIn(": 1 finished issue-task runs, 1 other runs", compact[0])
        self.assertNotIn("quick", "\n".join(compact))
        self.assertNotIn("## Per finished quick-task run", "\n".join(md))


class WaveQuickTaskTest(unittest.TestCase):
    """wave reads a run's kind through metrics.read_run: a quick-task run is done when every started agent answered,
    not at its quick agent's result while its reviewers still work (the issue-task rule)."""

    @staticmethod
    def agent(role: str, result: dict | None) -> dict:
        return {"role": role, "label": f"{role}:#1", "phase": "Review", "result": result}

    def test_quick_task_waits_for_its_reviewers(self) -> None:
        agents = [self.agent("publisher", PUB), self.agent("code-reviewer", None)]
        self.assertFalse(wave.journal_done({"kind": "quick-task", "agents": agents, "finished": False}))
        self.assertTrue(wave.journal_done({"kind": "issue-task (resumed)", "agents": agents, "finished": False}))
        done = [self.agent("publisher", PUB), self.agent("code-reviewer", {"findings": []})]
        self.assertTrue(wave.journal_done({"kind": "quick-task", "agents": done, "finished": True}))


if __name__ == "__main__":
    unittest.main()
