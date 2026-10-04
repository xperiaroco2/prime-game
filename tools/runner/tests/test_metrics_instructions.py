"""`metrics`' instructions and docs per agent role (#337): the instruction-diet ADR's method (#313) over small synthetic
transcripts written here (never real ones): the items each attachment and tool read adds, their first writes, re-writes
and reads, the files loaded twice, the points, ARCHITECTURE and AGENT_WORKFLOW by section, and the merge-check pairs."""

import json
import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.tests.test_metrics import SUMMARY, UNTIL, Fixture, assistant, at, bash, tool_result, usage, write_lines

SID = "77777777-0000-0000-0000-000000000000"
ROOT = metrics.REPO_ROOT
WT = ROOT / ".claude" / "worktrees" / "40"
NAME = ROOT.name

ARCHITECTURE = """# Architecture
The intro line is long enough to map to the top.
## 1. Layers and boundaries
The layers line is long enough to be mapped.
```text
# a fenced comment that is not a heading
```
## 4. Protocol
### 4.7 The game client
The client line is long enough to be mapped, too.
Short.
"""
# A Read of it as the Read tool returns it (cat -n): a line no longer in today's file, then §1 and §4.7.
READ_LINES = [
    "     1\tA line that changed since and maps to no section.",
    "     4\tThe layers line is long enough to be mapped.",
    "     5\tsome short line",
    "    10\tThe client line is long enough to be mapped, too.",
    "    11\tShort.",
]
READ_TEXT = "\n".join(READ_LINES)
OPUS_WRITE, OPUS_READ = 5.0 / 1e6, 0.20 / 1e6  # per token, at the 5-minute write price


def attachment(minutes: float, att: dict) -> dict:
    return {"type": "attachment", "timestamp": at(minutes), "attachment": att}


def instructions(minutes: float, *files: tuple[Path | str, int]) -> dict:
    return attachment(minutes, {"type": "instructions", "files": [{"path": str(p), "type": "Project",
                                                                   "content": "x" * n} for p, n in files]})


def nested(minutes: float, path: Path, chars: int) -> dict:
    return attachment(minutes, {"type": "nested_memory", "path": str(path),
                                "content": {"path": str(path), "content": "r" * chars}})


def read(tool_id: str, path: Path, **extra: object) -> dict:
    return {"id": tool_id, "name": "Read", "input": {"file_path": str(path), **extra}}


def merge_check_output(*rows: str) -> str:
    return "\n".join(["merge-check", "  ok    fetched origin", "", "| check | textual | semantic |", "|---|---|---|",
                      *rows, "", "merge-check: 1 textual conflicts and 0 overlaps in 3 checks."])  # fmt: skip


class Project:
    """One manager session (SID) with one finished issue-task run (#40) and a hand-run subagent.

    implementer  launch: root CLAUDE.md (1000 tokens), the user memory (100), the skill listing (200), the MCP
                 instructions (100); call 0 Reads the worktree's ARCHITECTURE, which loads the worktree's root
                 CLAUDE.md (1000, again) and both copies of rules/tests.md (200 each, the second again); call 1 runs
                 sed on AGENT_WORKFLOW (100); call 2 re-writes most of its context and runs verify (no read); call 3
                 runs `git show` of ARCHITECTURE (no read); a compaction; root CLAUDE.md again (a new context); call 4.
    code review  launch: root CLAUDE.md; reads a merge-check output (a workflow agent's: not counted).
    publisher    launch: root CLAUDE.md; opens PR 41.
    manager      two merge-check outputs naming #41 + #42 in ARCHITECTURE, one across bases naming #44 + #42; a
                 table row in a result that is no merge-check output; its own verify.
    hand-run     launch: root CLAUDE.md.
    """

    def __init__(self, root: Path) -> None:
        self.dir = root / "projects" / "D--prime-game"
        self.docs = root / "checkout"
        (self.docs / "docs").mkdir(parents=True)
        (self.docs / "docs" / "ARCHITECTURE.md").write_bytes(ARCHITECTURE.encode("utf-8"))
        wf = self.dir / SID / "subagents" / "workflows" / "wf_diet"
        impl = [
            instructions(0, (ROOT / "CLAUDE.md", 2350), ("C:/Users/u/.claude/CLAUDE.md", 235)),
            attachment(0, {"type": "skill_listing", "content": "s" * 470}),
            attachment(0, {"type": "mcp_instructions_delta", "addedBlocks": ["b" * 235]}),
            assistant(0, "msg-d0", usage(write=5000), tool=read("r1", WT / "docs" / "ARCHITECTURE.md", offset=1)),
            nested(1, WT / "CLAUDE.md", 2350),
            nested(1, WT / ".claude" / "rules" / "tests.md", 470),
            nested(1, ROOT / ".claude" / "rules" / "tests.md", 470),
            tool_result(1, "r1", READ_TEXT),
            assistant(2, "msg-d1", usage(write=1000, read=5000),
                      tool=bash("b1", f"cd /d/{NAME}/.claude/worktrees/40 && sed -n 1,9p docs/AGENT_WORKFLOW.md")),
            tool_result(3, "b1", "w" * 235),
            assistant(4, "msg-d2", usage(write=9000, read=1000), tool=bash("b2", "tools/run.sh verify")),
            tool_result(9, "b2", SUMMARY),
            assistant(10, "msg-d3", usage(read=10000), tool=bash("b3", "git show HEAD:docs/ARCHITECTURE.md")),
            tool_result(11, "b3", "x" * 4700),
            {"type": "system", "subtype": "compact_boundary", "timestamp": at(12)},
            instructions(12, (ROOT / "CLAUDE.md", 2350)),
            assistant(13, "msg-d4", usage(write=3000)),
        ]
        review = [
            instructions(14, (ROOT / "CLAUDE.md", 2350)),
            assistant(14, "msg-c0", usage(write=2000), tool=bash("c1", "tools/run.sh merge-check")),
            tool_result(15, "c1", merge_check_output("| #50 + #51 | conflict: docs/ARCHITECTURE.md | clean |")),
            assistant(16, "msg-c1", usage(read=2000)),
        ]
        publish = [
            instructions(17, (ROOT / "CLAUDE.md", 2350)),
            assistant(17, "msg-p0", usage(write=2000)),
            assistant(18, "msg-p1", usage(read=2000)),
        ]
        Fixture.run(wf, [
            ("k-i", "d-impl", "implement:#40", "Implement", {"verify_green": True}, impl),
            ("k-c", "d-code", "review:code:#40", "Review", {"findings": []}, review),
            ("k-p", "d-pub", "publish:#40", "Publish", {"pr_number": 41, "ci_green": True}, publish),
        ])  # fmt: skip
        cross = ("| #44 (main) + #42 (release/m9) | docs/ARCHITECTURE.md | conflict: docs/ARCHITECTURE.md | "
                 "clean |")  # fmt: skip
        write_lines(self.dir / f"{SID}.jsonl", [
            assistant(20, "msg-m0", usage(write=1000), tool=bash("m1", "tools\\run.cmd merge-check --base release/m9")),
            tool_result(21, "m1", merge_check_output(
                "| #41 onto release/m9 | conflict: docs/ARCHITECTURE.md | clean |",
                "| #41 + #42 | conflict: client/CLAUDE.md, docs/ARCHITECTURE.md | clean |",
                "| #41 + #43 | conflict: core/x.gd | overlap: f |",
                "| #42 + #43 | clean | clean |", "", "| check | shared files | textual | semantic |",
                "|---|---|---|---|", cross)),
            assistant(22, "msg-m1", usage(read=1000), tool=bash("m2", "tools\\run.cmd merge-check --base release/m9")),
            tool_result(23, "m2", merge_check_output("| #42 + #41 | conflict: docs/ARCHITECTURE.md | clean |")),
            assistant(24, "msg-m2", usage(read=1000), tool=bash("m3", "cat notes.md")),
            tool_result(25, "m3", "Run tools\\run.cmd merge-check before each merge.\n"
                                  "| #45 + #46 | conflict: docs/ARCHITECTURE.md | clean |"),
            assistant(26, "msg-m3", usage(read=1000), tool=bash("m4", "tools/run.sh verify")),
            tool_result(30, "m4", SUMMARY),
            assistant(31, "msg-m4", usage(read=1000)),
        ])  # fmt: skip
        hand = self.dir / SID / "subagents" / "agent-h9.jsonl"
        write_lines(hand, [instructions(40, (ROOT / "CLAUDE.md", 2350)), assistant(40, "msg-h0", usage(write=1000))])
        hand.with_name("agent-h9.meta.json").write_text(json.dumps({"agentType": "test-runner"}), encoding="utf-8")


class InstructionsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.project = Project(Path(self.tmp.name))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def collect(self) -> dict:
        return metrics.collect([self.project.dir], {}, None, metrics.parse_time(UNTIL))

    def build(self, **kwargs: object):
        return metrics.build(self.collect(), kwargs.pop("history", []), kwargs.pop("ci", None), None,
                             metrics.parse_time(UNTIL), docs_root=self.project.docs, **kwargs)  # fmt: skip

    def agent(self, aid: str) -> dict:
        run = next(r for r in self.collect()["runs"] if r["wf"] == "wf_diet")
        return next(x["data"] for x in run["agents"] if x["id"] == aid)

    def test_each_attachment_and_doc_read_is_an_item(self) -> None:
        items = self.agent("d-impl")["instructions"]
        self.assertEqual(
            [(i["what"], i["how"], i["file"]) for i in items],
            [("root CLAUDE.md", "launch", "CLAUDE.md"),
             ("user memory", "launch", "C:/Users/u/.claude/CLAUDE.md"),
             ("the skill listing", "launch", None),
             ("MCP server instructions", "launch", None),
             ("root CLAUDE.md", "by path", "CLAUDE.md"),
             (".claude/rules/", "by path", ".claude/rules/tests.md"),
             (".claude/rules/", "by path", ".claude/rules/tests.md"),
             ("docs/ARCHITECTURE.md", "Read", "docs/ARCHITECTURE.md"),
             ("docs/AGENT_WORKFLOW.md", "shell read", "docs/AGENT_WORKFLOW.md"),
             ("root CLAUDE.md", "launch", "CLAUDE.md")],
            "verify's output and `git show` are no doc reads",
        )  # fmt: skip
        self.assertEqual([round(i["tokens"]) for i in items], [1000, 100, 200, 100, 1000, 200, 200,
                                                                round(len(READ_TEXT) / 2.35), 100, 1000])
        self.assertEqual([i["copy"] for i in items[4:7]], [True, True, False])
        self.assertEqual(items[7]["text"], READ_TEXT, "a sectioned doc keeps its text for the section tables")
        self.assertEqual((items[8]["text"], items[8]["mode"]), ("w" * 235, "plain"))
        self.assertNotIn("text", items[0], "only a tool's read of a sectioned doc keeps it")

    def test_first_writes_rewrites_and_reads(self) -> None:
        # Calls 0 to 3 before the compaction; call 2 re-wrote most of its context (9000 of 10000), the others not.
        items = self.agent("d-impl")["instructions"]
        launch, path_root, aw, again = items[0], items[4], items[8], items[9]
        # Entered at call 0, read by calls 1 to 3: one of them a re-write, two cache reads.
        self.assertAlmostEqual(launch["write"], 1000 * OPUS_WRITE)
        self.assertAlmostEqual(launch["rewrite"], 1000 * OPUS_WRITE)
        self.assertAlmostEqual(launch["read"], 1000 * 2 * OPUS_READ)
        # Loaded by path at call 0's Read, so it entered at call 1: call 2 re-wrote it, call 3 read it.
        self.assertAlmostEqual(path_root["write"], 1000 * OPUS_WRITE)
        self.assertAlmostEqual(path_root["rewrite"], 1000 * OPUS_WRITE)
        self.assertAlmostEqual(path_root["read"], 1000 * OPUS_READ)
        # sed's result entered at call 2 (its own re-write is its first write), read once by call 3.
        self.assertAlmostEqual(aw["write"], 100 * OPUS_WRITE)
        self.assertEqual(aw["rewrite"], 0.0)
        self.assertAlmostEqual(aw["read"], 100 * OPUS_READ)
        # After the compaction: a new context, written at call 4 and never read.
        self.assertEqual((again["segment"], again["read"], again["rewrite"]), (1, 0.0, 0.0))
        self.assertAlmostEqual(again["write"], 1000 * OPUS_WRITE)

    def test_a_one_hour_cache_write_prices_the_items_at_the_agents_mix(self) -> None:
        calls = [{**usage(write=1000, write_1h=250), "cache_write_1h": 250, "model": "claude-opus-5-5"},
                 {**usage(read=1000), "cache_write_1h": 0, "model": "claude-opus-5-5"}]  # fmt: skip
        item = {"chars": 2350, "at": 0}
        metrics.price_items([item], calls, [])
        self.assertAlmostEqual(item["write"], 1000 * (0.25 * 8.0 + 0.75 * 5.0) / 1e6)
        self.assertAlmostEqual(item["read"], 1000 * OPUS_READ)

    def test_an_item_no_api_call_took_in_is_not_priced(self) -> None:
        calls = [{**usage(write=1000), "cache_write_1h": 0, "model": "claude-opus-5-5"}]
        late = {"chars": 2350}  # a tool result after the last API call: the agent was interrupted
        metrics.price_items([late], calls, [])
        self.assertEqual((round(late["tokens"]), late["write"], late["rewrite"], late["read"]), (1000, 0.0, 0.0, 0.0))

    def test_the_role_table_and_points(self) -> None:
        _md, record, _compact = self.build()
        rec = record["instructions"]
        roles = {r["role"]: r for r in rec["roles"]}
        self.assertEqual(set(roles), {"implementer", "code-reviewer", "publisher", "manager sessions",
                                      "hand-run subagents"})  # fmt: skip
        impl = roles["implementer"]
        self.assertEqual(impl["agents"], 1)
        self.assertEqual({k: round(v) for k, v in impl["tokens"].items()},
                         {"launch": 2400, "by path": 1400, "read": round(len(READ_TEXT) / 2.35) + 100})
        items = self.agent("d-impl")["instructions"]
        for key, part in (("write_usd", "write"), ("rewrite_usd", "rewrite"), ("read_usd", "read")):
            self.assertAlmostEqual(impl[key], sum(i[part] for i in items), msg=key)
        self.assertAlmostEqual(impl["usd"], impl["write_usd"] + impl["rewrite_usd"] + impl["read_usd"])
        self.assertAlmostEqual(impl["share"], impl["usd"] / metrics.usd(self.agent("d-impl")["tokens"]))
        non_read = impl["write_usd"] + impl["rewrite_usd"]
        self.assertEqual(metrics.POINT_WEIGHTS, ((0.0, 15.3), (0.5, 20.3)))
        self.assertAlmostEqual(impl["points"][0], non_read / 15.3)
        self.assertAlmostEqual(impl["points"][1], (non_read + 0.5 * impl["read_usd"]) / 20.3)
        # The manager's own lines carry no instruction item (none in its transcript): $0, still a row.
        self.assertEqual(roles["manager sessions"]["usd"], 0.0)
        self.assertEqual(rec["all"]["agents"], 5)
        self.assertAlmostEqual(rec["all"]["usd"], sum(r["usd"] for r in rec["roles"]))
        text = "\n".join(_md)
        self.assertIn("## Instructions and docs per agent role (#337)", text)
        self.assertIn("| role | agents | launch-loaded | loaded by path | read | first writes | re-writes | reads | "
                      "list $ | of the role's $ | points (w = 0 / 0.5) | loaded twice (loads, $) |", text)  # fmt: skip
        self.assertIn("k(0) = 15.3, k(0.5) = 20.3", text)

    def test_files_loaded_twice_in_one_agent(self) -> None:
        _md, record, _compact = self.build()
        rec = record["instructions"]
        # The worktree's root CLAUDE.md beside the launched one, and main's rules/tests.md beside the worktree's
        # copy; root CLAUDE.md after the compaction is a new context, not twice.
        items = self.agent("d-impl")["instructions"]
        metrics.mark_twice(items)
        self.assertEqual([i.get("twice") for i in items if i["how"] in ("launch", "by path") and i["file"]],
                         [False, False, True, False, True, False])  # fmt: skip
        self.assertEqual([(t["file"], t["agents"], t["loads"]) for t in rec["twice"]],
                         [("CLAUDE.md", 1, 1), (".claude/rules/tests.md", 1, 1)])  # fmt: skip
        roles = {r["role"]: r for r in rec["roles"]}
        self.assertEqual(roles["implementer"]["twice"], 2)
        self.assertAlmostEqual(roles["implementer"]["twice_usd"], sum(t["usd"] for t in rec["twice"]))
        self.assertEqual(roles["code-reviewer"]["twice"], 0)
        self.assertIn("| `CLAUDE.md` | 1 | 1 | $0.01 | implementer |", "\n".join(_md))

    def test_the_by_file_table(self) -> None:
        _md, record, _compact = self.build()
        files = {(f["what"], f["how"]): f for f in record["instructions"]["files"]}
        root = files[("root CLAUDE.md", "launch")]
        self.assertEqual(root["loads"], 5, "the implementer twice (a compaction between), 3 other agents once")
        self.assertEqual(files[("root CLAUDE.md", "by path")]["loads"], 1)
        self.assertEqual(files[(".claude/rules/", "by path")]["loads"], 2)
        self.assertEqual(files[("docs/ARCHITECTURE.md", "read")]["loads"], 1)
        self.assertEqual(files[("docs/AGENT_WORKFLOW.md", "read")]["loads"], 1)
        self.assertEqual(files[("the skill listing", "launch")]["roles"], ["implementer 100%"])
        for f in files.values():
            self.assertLessEqual(f["non_read"], f["usd"])

    def test_architecture_by_section_of_todays_file(self) -> None:
        smap = metrics.section_map(self.project.docs / "docs" / "ARCHITECTURE.md")
        self.assertEqual(list(smap["size"]), ["Architecture", "§1", "§4", "§4.7"], "no heading in fenced code")
        self.assertEqual(smap["titles"]["§4.7"], "4.7 The game client")
        _md, record, _compact = self.build()
        sections = record["instructions"]["sections"]
        self.assertEqual(list(sections), ["docs/ARCHITECTURE.md"], "no AGENT_WORKFLOW in the fixture's checkout")
        arch = sections["docs/ARCHITECTURE.md"]
        item = self.agent("d-impl")["instructions"][7]
        cost = item["write"] + item["rewrite"] + item["read"]
        chars = len(READ_TEXT) + 1
        first = len(READ_LINES[0]) + 1
        layers = len(READ_LINES[1]) + len(READ_LINES[2]) + 2
        client = len(READ_LINES[3]) + len(READ_LINES[4]) + 2
        self.assertEqual(first + layers + client, chars)
        rows = {r["section"]: r for r in arch["rows"]}
        self.assertEqual(set(rows), {"§1", "§4.7"})
        self.assertAlmostEqual(rows["§1"]["usd"], cost * layers / chars)
        self.assertAlmostEqual(rows["§4.7"]["usd"], cost * client / chars)
        self.assertAlmostEqual(arch["unmapped_usd"], cost * first / chars, msg="a line no longer in today's file")
        self.assertAlmostEqual(arch["usd"], cost)
        self.assertEqual((rows["§4.7"]["agents"], rows["§4.7"]["roles"]), (1, ["implementer 100%"]))
        self.assertAlmostEqual(rows["§4.7"]["tokens"], client / 2.35)
        self.assertIn("`docs/ARCHITECTURE.md` by section of today's file", "\n".join(_md))
        self.assertIn("| 4.7 The game client |", "\n".join(_md))

    def test_merge_check_pairs_with_an_architecture_conflict(self) -> None:
        _md, record, _compact = self.build()
        self.assertEqual(record["instructions"]["merge_check"], [{
            "session": SID, "label": SID[:8], "outputs": 2,
            "pairs": [{"prs": [41, 42], "seen": 2}, {"prs": [42, 44], "seen": 1}],
        }], "a PR onto its base, another file's conflict, a workflow agent's run and a row outside a merge-check "
            "output are no pair")  # fmt: skip
        self.assertIn("| 77777777 | 2 | 2 | #41 + #42 (2x), #42 + #44 |", "\n".join(_md))

    def test_the_compact_line(self) -> None:
        history = [{"steps": {"lint": ("passed", 20.0)}, "total": 300.0, "status": "passed", "via": "history",
                    "t": metrics.parse_time("2026-10-02T09:00:00Z"), "wait": None, "over": False}]  # fmt: skip
        ci = {"runs": 3, "by_outcome": {"push success": 3}, "reruns": 0, "queue_s": 0.0, "green": 2,
              "job_s": [360.0, 420.0], "steps": {"verify total": [380.0, 390.0]}}  # fmt: skip
        _md, record, compact = self.build(history=history, ci=ci, github={"skipped": "--no-gh"})
        # Every line present: the instructions' line is the eleventh, and CI still ends the summary.
        self.assertEqual(len(compact), 11)
        self.assertTrue(compact[-1].startswith("CI: 3 runs"))
        line = next(c for c in compact if c.startswith("instructions and docs: "))
        self.assertEqual(compact.index(line), compact.index(record["quality"]["compact"]) + 1)
        a = record["instructions"]["all"]
        self.assertTrue(line.startswith(f"instructions and docs: {metrics.fmt_usd(a['usd'])} ({a['share']:.0%} of "))
        self.assertIn(f"points {a['points'][0]:.2f} / {a['points'][1]:.2f} (w = 0 / 0.5); loaded twice 2 (", line)
        self.assertIn("; ARCHITECTURE $0.00, AGENT_WORKFLOW $0.00; 2 merge-check pairs with an ARCHITECTURE "
                      "conflict", line)  # fmt: skip

    def test_a_window_without_items_has_no_compact_line(self) -> None:
        rec = metrics.instruction_record([], [], self.project.docs)
        self.assertIsNone(metrics.instruction_compact(rec))
        self.assertIn("No instruction or doc item in the window's transcripts.", metrics.instruction_section(rec))


class DocTargetsTest(unittest.TestCase):
    def test_reads_greps_and_shell_commands(self) -> None:
        cases = [
            ("Read", {"file_path": str(ROOT / "docs" / "decisions" / "x.md")},
             [("docs/decisions/x.md", "Read", "read")]),
            ("Read", {"file_path": str(WT / "core" / "match" / "vote.gd")}, []),
            ("Read", {"file_path": "C:/Users/u/notes.md"}, []),
            ("Grep", {"path": str(WT / "docs" / "ARCHITECTURE.md")}, [("docs/ARCHITECTURE.md", "Grep", "grep")]),
            ("Grep", {"path": str(ROOT / "docs")}, [("docs", "Grep", "folder")]),
            ("Grep", {"path": "docs/decisions/"}, [("docs/decisions", "Grep", "folder")]),
            ("Grep", {"path": str(WT / "core")}, [("core", "Grep", "folder")]),
            ("Grep", {"pattern": "x", "glob": "docs/**/*.md"}, [("", "Grep", "folder")]),
            ("Grep", {"path": str(WT)}, [("", "Grep", "folder")]),
            ("Grep", {"path": str(WT / "core" / "x.gd")}, []),
            ("Grep", {"path": "C:/Users/u/elsewhere"}, []),
            ("Bash", {"command": f'grep -n "4.7" D:\\{NAME}\\docs\\ARCHITECTURE.md docs/AGENT_WORKFLOW.md'},
             [("docs/ARCHITECTURE.md", "shell search", "grep"), ("docs/AGENT_WORKFLOW.md", "shell search", "grep")]),
            ("Bash", {"command": "sed -n '/x/p' docs/ARCHITECTURE.md | grep y"},
             [("docs/ARCHITECTURE.md", "shell read", "plain")]),
            ("PowerShell", {"command": f"Get-Content D:/{NAME}/.claude/worktrees/7/server/CLAUDE.md"},
             [("server/CLAUDE.md", "shell read", "plain")]),
            ("Bash", {"command": "cat .claude/skills/start-task/SKILL.md"},
             [(".claude/skills/start-task/SKILL.md", "shell read", "plain")]),
            ("Bash", {"command": "tools/run.sh lint docs/ARCHITECTURE.md"}, []),
            ("Bash", {"command": "git log -p -- docs/ARCHITECTURE.md"}, []),
            ("Bash", {"command": f"git -C /d/{NAME}/.claude/worktrees/7 diff origin/main -- docs/ARCHITECTURE.md"}, []),
            ("Bash", {"command": "git --no-pager show HEAD:docs/ARCHITECTURE.md"}, []),
            ("Bash", {"command": "git -c core.pager=cat log -p -- docs/ARCHITECTURE.md"}, []),
            ("Bash", {"command": "cat ~/.claude/CLAUDE.md"}, []),
            ("Edit", {"file_path": str(ROOT / "docs" / "ARCHITECTURE.md")}, []),
        ]  # fmt: skip
        for name, inp, expected in cases:
            with self.subTest(name=name, inp=inp):
                self.assertEqual(metrics.doc_targets(name, inp), expected)

    def test_a_result_naming_two_docs_is_split_and_keeps_no_text(self) -> None:
        targets = [("docs/ARCHITECTURE.md", "shell search", "grep"), ("docs/GDD.md", "shell search", "grep")]
        items = metrics.read_items(targets, "y" * 10)
        self.assertEqual([(i["what"], i["chars"]) for i in items], [("docs/ARCHITECTURE.md", 5), ("docs/GDD.md", 5)])
        self.assertTrue(all("text" not in i for i in items))

    def test_a_grep_over_a_folder_is_split_by_the_docs_its_output_names(self) -> None:
        text = "\n".join([
            f"{WT}/docs/ARCHITECTURE.md:4:The layers line is long enough to be mapped.",
            f"{WT}/docs/ARCHITECTURE.md-5-context line",
            "--",
            "docs/decisions/2026-10-04-x.md:7:an ADR line",
            "docs/GDD.md:2",
            "core/match/vote.gd:9:code is none",
            "continues the code file",
            "docs/notes.txt",
        ])  # fmt: skip
        items = metrics.folder_items("", text)
        self.assertEqual([(i["what"], i["file"]) for i in items],
                         [("docs/ARCHITECTURE.md", "docs/ARCHITECTURE.md"), ("ADRs", "docs/decisions/2026-10-04-x.md"),
                          ("docs/GDD.md", "docs/GDD.md"), ("other docs", "docs/notes.txt")])  # fmt: skip
        arch = text.splitlines()[:2]
        self.assertEqual(items[0]["chars"], sum(len(x) + 1 for x in arch))
        self.assertEqual((items[0]["text"], items[0]["mode"]), ("\n".join(arch), "grep"))
        self.assertNotIn("text", items[1])
        # A docs folder whose output names no file keeps one item; no match, or a code folder, none.
        self.assertEqual([(i["what"], i["chars"]) for i in metrics.folder_items("docs", "some opaque output")],
                         [("other docs", 18)])  # fmt: skip
        self.assertEqual(metrics.folder_items("docs", "No matches found"), [])
        self.assertEqual(metrics.folder_items("core", "some opaque output"), [])
        self.assertEqual(metrics.read_items([("docs", "Grep", "folder")], "docs/GDD.md")[0]["what"], "docs/GDD.md")

    def test_the_section_of_a_grep_line(self) -> None:
        index = {"The layers line is long enough to be mapped.": {"§1"}}
        found, unmapped = metrics.sections_of(index, "D:/x/docs/ARCHITECTURE.md:4:The layers line is long enough to "
                                                     "be mapped.\n5-next", "grep")  # fmt: skip
        self.assertEqual((dict(found), unmapped), ({"§1": len("D:/x/docs/ARCHITECTURE.md:4:") + 44 + 1 + 7}, 0))


if __name__ == "__main__":
    unittest.main()
