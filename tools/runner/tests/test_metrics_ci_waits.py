"""`metrics` measures the CI roles' CI waits and a poll agent's saving (#1019): which tool uses poll, which API calls
are CI-wait calls, their list $ by kind, the rows per run kind and role, the poll agent's estimate, the section and
the compact clause; from fixture transcripts written here (never real ones)."""

import tempfile
import unittest
from pathlib import Path

from runner import metrics
from runner.common import LINE_CAP
from runner.tests.test_metrics import SESSION, UNTIL, Fixture, assistant, bash, tool_result, usage, write_lines

CHECKS = "cd /d/x && timeout 180 gh pr checks 9 --watch --interval 30; echo rc=$?"
OPUS = (4.0, 5.0, 0.20, 20.0)  # USD per million tokens: input, 5-minute cache write, cache read, output


def price(inp: int = 0, write: int = 0, read: int = 0, out: int = 0) -> float:
    return (inp * OPUS[0] + write * OPUS[1] + read * OPUS[2] + out * OPUS[3]) / 1e6


def two_tools(minutes: float, mid: str, u: dict, *tools: dict) -> dict:
    line = assistant(minutes, mid, u)
    line["message"]["content"] = [{"type": "tool_use", **t} for t in tools]
    return line


def publisher(tag: str, start: float) -> list[dict]:
    """A publisher: publish in the background (no poll), a wait of four CI-wait calls (`wait`, a CI watch, a sleep
    alone, a call with no tool use), a failure read (`gh run view --log-failed`, no poll), a mixed call (a CI watch and
    a Read: no CI-wait call), a wait of one call (`gh run view`, its cache re-written), its last call (no tool use)."""
    t = start
    return [
        assistant(t, f"{tag}1", usage(inp=10, write=50_000, out=100), tool=bash(f"{tag}b1", "tools/run.sh publish > l")),
        tool_result(t + 0.1, f"{tag}b1", "Command running in background"),
        assistant(t + 1, f"{tag}2", usage(inp=10, write=1000, read=50_000, out=100),
                  tool=bash(f"{tag}b2", "cd /d/x && tools/run.sh wait /c/s/a1/publish-1.log")),
        tool_result(t + 4, f"{tag}b2", "wait: publish-1.log finished: exit=0"),
        assistant(t + 4.1, f"{tag}3", usage(inp=10, write=1000, read=51_000, out=100), tool=bash(f"{tag}b3", CHECKS)),
        tool_result(t + 7, f"{tag}b3", "rc=124"),
        assistant(t + 7.1, f"{tag}4", usage(inp=10, write=1000, read=52_000, out=100),
                  tool={**bash(f"{tag}b4", "sleep 120"), "input": {"command": "sleep 120", "run_in_background": True}}),
        tool_result(t + 7.2, f"{tag}b4", "Command running in background"),
        assistant(t + 7.3, f"{tag}5", usage(inp=10, read=53_000, out=50)),
        assistant(t + 10, f"{tag}6", usage(inp=10, read=53_000, out=100),
                  tool=bash(f"{tag}b6", "gh run view 123 --log-failed | grep -n FAIL")),
        tool_result(t + 10.5, f"{tag}b6", "FAIL x"),
        two_tools(t + 11, f"{tag}7", usage(inp=10, read=53_000, out=100), bash(f"{tag}b7", CHECKS),
                  {"id": f"{tag}r7", "name": "Read", "input": {"file_path": "D:/x/a.md"}}),
        tool_result(t + 12, f"{tag}b7", "rc=0"),
        tool_result(t + 12, f"{tag}r7", "text"),
        assistant(t + 30, f"{tag}8", usage(inp=10, write=60_000, out=100), tool=bash(f"{tag}b8", "gh run view 123")),
        tool_result(t + 30.5, f"{tag}b8", "completed success"),
        assistant(t + 31, f"{tag}9", usage(inp=10, read=60_000, out=100)),
    ]


# The publisher's CI-wait calls: 2 to 5 (one wait) and 8 (another).
WAIT_CALLS = [(10, 1000, 50_000, 100), (10, 1000, 51_000, 100), (10, 1000, 52_000, 100), (10, 0, 53_000, 50),
              (10, 60_000, 0, 100)]  # fmt: skip
MEASURED = sum(price(*c) for c in WAIT_CALLS)
# The poll agent: each wait's first call writes its 16k prompt; the others write as measured, read the rest.
POLL = (price(10, 15_990, 0, 100) + price(10, 1000, 14_990, 100) * 2 + price(10, 0, 15_990, 50)
        + price(10, 15_990, 0, 100))  # fmt: skip
LAUNCH = price(*WAIT_CALLS[0]) + price(*WAIT_CALLS[4])  # per wait, the agent's call that launches the poll agent


class PollKindTest(unittest.TestCase):
    def test_what_a_shell_command_polls(self) -> None:
        cases = {
            CHECKS: "ci",
            "gh run watch 123 --exit-status": "ci",
            "gh run view 123 --json status": "ci",
            "gh run view 123 --log-failed | grep FAIL": None,
            "cd /d/x && tools/run.sh wait /c/s/verify-1.log": "wait",
            "tools\\run.cmd wait C:/s/publish-1.log": "wait",
            "tools/run.sh wait --verified": None,
            "tools/run.sh wait --help": None,
            "sleep 120": "sleep",
            "cd /d/x && sleep 3000": "sleep",
            "Start-Sleep -Seconds 30": "sleep",
            "sleep 5; cat log": None,
            "gh pr checks 9 || gh run view 123 --log-failed | grep FAIL": None,
            "gh pr checks 9 --watch; gh pr merge 9 --auto": None,
            "timeout 180 gh pr checks 9 --watch | tail -3; echo rc=$?": "ci",
            "sleep 60 && gh pr checks 9": "ci",
            "cd /d/x && timeout 180 gh pr checks 9 --watch > /dev/null 2>&1; rc=$?; echo rc=$rc; "
            "gh pr checks 9 2>&1 | cut -f1,2 | head -10": "ci",
            'cd /d/x && S=/c/s/a1; timeout 175 tools/run.sh wait "$S/publish-1.log" 2>&1 | tail -3': "wait",
            "cd /d/x && git log --oneline -4; tools/run.sh wait /c/s/l": None,
            "tools/run.sh wait /c/s/l; sleep 5": "wait",
            "gh pr view 9 --json state": None,
            "tools/run.sh publish > log 2>&1": None,
            "": None,
        }
        self.assertEqual({cmd: metrics.poll_kind(cmd) for cmd in cases}, cases)


class CiWaitCallsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.path = Path(self.tmp.name) / "agent-p.jsonl"
        write_lines(self.path, publisher("p", 0))

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_the_calls_the_waits_and_their_tokens(self) -> None:
        w = metrics.parse_agent(self.path)[0]["ci_wait"]
        self.assertEqual((w["calls"], w["waits"], w["polls"]), (5, 2, {"wait": 1, "ci": 2, "sleep": 1}))
        sums = [sum(c[i] for c in WAIT_CALLS) for i in range(4)]
        self.assertEqual([w["tokens"][f] for f in metrics.TOKEN_FIELDS], sums)
        self.assertAlmostEqual(w["usd"]["usd_cache_read"], price(read=sums[2]))
        self.assertAlmostEqual(w["usd"]["usd_cache_write"], price(write=sums[1]))
        self.assertAlmostEqual(metrics.usd(w["usd"]), MEASURED)

    def test_the_poll_agents_estimate(self) -> None:
        w = metrics.parse_agent(self.path)[0]["ci_wait"]
        self.assertAlmostEqual(metrics.usd(w["poll_usd"]), POLL)
        self.assertAlmostEqual(metrics.usd(w["launch_usd"]), LAUNCH)

    def test_a_one_hour_write_stays_one_hour_up_to_the_poll_agents_write(self) -> None:
        u = {**usage(inp=10, write=30_000, read=40_000, out=5), "cache_write_1h": 30_000, "model": "claude-opus-5-5"}
        u.pop("cache_creation")
        self.assertEqual(metrics.poll_agent_usage(u, first=False) | {"model": None}, {
            "input_tokens": 10, "cache_creation_input_tokens": 15_990, "cache_read_input_tokens": 0,
            "output_tokens": 5, "cache_write_1h": 15_990, "model": None})  # fmt: skip
        self.assertEqual(metrics.poll_agent_usage(u, first=True)["cache_write_1h"], 0)

    def test_a_poll_agents_first_write_has_the_measured_agents_share_of_one_hour_writes(self) -> None:
        u = usage(inp=10, write=1000, read=40_000, out=5)
        first = metrics.poll_agent_usage(u, True, 0.25)
        self.assertEqual((first["cache_creation_input_tokens"], first["cache_write_1h"]), (15_990, 3998))
        cold = metrics.usd(metrics.usd_of(metrics.poll_agent_usage(u, True)))
        self.assertGreater(metrics.usd(metrics.usd_of(first)), cold)
        # The share is the agent's own: 25 of its 400 written tokens at the 1-hour rate.
        used = {"a": {**u, "cache_creation_input_tokens": 100, "cache_write_1h": 25},
                "b": {**u, "cache_creation_input_tokens": 300, "cache_write_1h": 0}}  # fmt: skip
        w = metrics.ci_wait_calls(["a", "b"], {"a": [{"poll": "ci"}], "b": [{"poll": "ci"}]}, used)
        expect = metrics.usd_of(metrics.poll_agent_usage(used["a"], True, 0.0625))["usd_cache_write"]
        expect += metrics.usd_of(metrics.poll_agent_usage(used["b"], False))["usd_cache_write"]
        self.assertAlmostEqual(w["poll_usd"]["usd_cache_write"], expect)

    def test_a_negative_amount_keeps_its_sign_in_front(self) -> None:
        self.assertEqual([metrics.fmt_usd(v) for v in (-0.312, -1234.56, 1234.56)], ["-$0.31", "-$1,235", "$1,235"])


class CiWaitRecordTest(unittest.TestCase):
    """A session with an issue-task run (an implementer whose `wait` is no CI role's, a publisher), a quick-task run
    (its quick agent with one CI watch, a fixer with none) and a pr-rebase run (a rebase agent with one CI watch)."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name) / "projects" / "D--prime-game"
        wf = self.dir / SESSION / "subagents" / "workflows"
        scripts = self.dir / SESSION / "workflows" / "scripts"
        scripts.mkdir(parents=True)
        (scripts / "quick-task-wf_q.js").write_text("export const meta = { name: 'quick-task' }\n")
        Fixture.run(wf / "wf_i", [
            ("k-i", "a-i", "implement:#5", "Implement", {"verify_green": True}, [
                assistant(0, "i1", usage(inp=10, write=20_000, out=10), tool=bash("ib1", "tools/run.sh wait l")),
                tool_result(3, "ib1", "done"),
                assistant(4, "i2", usage(inp=10, read=20_000, out=10)),
            ]),
            ("k-p", "a-p", "publish:#5", "Publish", {"pr_number": 9, "ci_green": True}, publisher("p", 5)),
        ])  # fmt: skip
        Fixture.run(wf / "wf_q", [
            ("k-q", "a-q", "publish:#6", "Quick", {"pr_number": 10, "ci_green": True}, [
                assistant(50, "q1", usage(inp=10, write=30_000, out=100), tool=bash("qb1", CHECKS)),
                tool_result(53, "qb1", "rc=0"),
                assistant(54, "q2", usage(inp=10, read=30_000, out=100)),
            ]),
            ("k-f", "a-f", "fix:#6", "Review", {"fixed": [], "open": 0, "ci_green": True}, [
                assistant(55, "f1", usage(inp=10, write=10_000, out=10)),
                assistant(56, "f2", usage(inp=10, read=10_000, out=10)),
            ]),
        ])  # fmt: skip
        Fixture.run(wf / "wf_r", [
            ("k-r", "a-r", "rebase:#7", "Rebase", {"pr": 11}, [
                assistant(60, "r1", usage(inp=10, write=40_000, out=100), tool=bash("rb1", CHECKS)),
                tool_result(63, "rb1", "rc=0"),
                assistant(64, "r2", usage(inp=10, read=40_000, out=100)),
            ]),
        ])  # fmt: skip

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def build(self) -> tuple[list[str], dict, list[str]]:
        data = metrics.collect([self.dir], {}, None, metrics.parse_time(UNTIL))
        return metrics.build(data, [], None, metrics.parse_time(UNTIL) - 86_400, metrics.parse_time(UNTIL))

    def test_a_row_per_run_kind_and_ci_role(self) -> None:
        _md, record, _compact = self.build()
        rows = {(r["kind"], r["name"]): r for r in record["ci_waits"]["rows"]}
        self.assertEqual(sorted(rows), [("issue-task", "publisher"), ("pr-rebase", "rebase agent"),
                                        ("quick-task", "fixer"), ("quick-task", "quick agent")])  # fmt: skip
        pub = rows[("issue-task", "publisher")]
        self.assertEqual((pub["agents"], pub["api_calls"], pub["calls"], pub["waits"]), (1, 9, 5, 2))
        self.assertEqual(pub["polls"], {"ci": 2, "wait": 1, "sleep": 1})
        self.assertAlmostEqual(pub["usd"], MEASURED)
        self.assertAlmostEqual(pub["estimate_usd"], POLL + LAUNCH)
        self.assertAlmostEqual(pub["saving_usd"], MEASURED - POLL - LAUNCH)
        self.assertAlmostEqual(pub["ceiling_usd"], MEASURED - LAUNCH, msg="a free poll agent: the launches alone")
        self.assertAlmostEqual(pub["share"], MEASURED / pub["role_usd"])
        read = price(read=206_000)
        self.assertAlmostEqual(pub["week"], (MEASURED - read + 0.75 * read) / 23.0)
        fixer = rows[("quick-task", "fixer")]
        self.assertEqual((fixer["calls"], fixer["usd"], fixer["share"]), (0, 0.0, 0.0))
        quick = rows[("quick-task", "quick agent")]
        self.assertEqual((quick["calls"], quick["waits"], quick["polls"]["ci"]), (1, 1, 1))
        self.assertAlmostEqual(quick["usd"], price(10, 30_000, 0, 100))

    def test_over_all_and_per_week(self) -> None:
        _md, record, _compact = self.build()
        ci = record["ci_waits"]
        every = ci["all"]
        self.assertEqual((every["agents"], every["calls"], every["waits"]), (4, 7, 4))
        self.assertAlmostEqual(every["usd"], sum(r["usd"] for r in ci["rows"]))
        self.assertAlmostEqual(every["estimate_usd"], every["poll_usd"] + every["launch_usd"])
        self.assertLess(every["saving_week"], every["ceiling_week"])
        self.assertEqual(ci["span_s"], 86_400)
        self.assertAlmostEqual(ci["per_week"], every["saving_week"] * 7)
        self.assertAlmostEqual(ci["ceiling_per_week"], every["ceiling_week"] * 7)
        self.assertFalse(ci["over"])

    def test_the_verdict_against_the_bar(self) -> None:
        record = {"all": {"saving_week": 0.2, "ceiling_week": 0.3}, "per_week": 1.4, "ceiling_per_week": 2.1,
                  "over": True}  # fmt: skip
        self.assertEqual(metrics.ci_wait_verdict(record),
                         "saving 0.20% (1.40%/7 days), a free one 0.30% (2.10%/7 days): over the 1% bar")
        record |= {"per_week": None, "ceiling_per_week": None, "over": False}
        self.assertEqual(metrics.ci_wait_verdict(record), "saving 0.20%, a free one 0.30%: not over the 1% bar")

    def test_the_section_and_the_compact_clause(self) -> None:
        md, _record, compact = self.build()
        text = "\n".join(md)
        self.assertIn("## CI waits per CI role and a poll agent's saving (#1019)", text)
        self.assertIn("| pr-rebase | rebase agent | 1 | 2 | 1 | 1 | 1/0/0 |", text)
        self.assertLessEqual(len(compact), 11)
        week = next(x for x in compact if x.startswith("% of a Max 20x week"))
        self.assertTrue(week.endswith(
            " | CI waits (#1019): 7 of 15 CI-role calls, $0.72 (in $0.00, write $0.67, read $0.04, out $0.01), 67% of "
            "their $, 0.03% of the week; a 16k poll agent $1.03: saving -0.01% (-0.09%/7 days), a free one 0.00% "
            "(0.01%/7 days): not over the 1% bar"), week)  # fmt: skip
        self.assertIn("In the window (1.0 days), a poll agent's saving -0.01% (-0.09%/7 days)", text)
        self.assertLessEqual(len(week), LINE_CAP)

    def test_a_clause_over_the_cap_keeps_the_verdict(self) -> None:
        _md, record, _compact = self.build()
        verdict = metrics.ci_wait_verdict(record["ci_waits"])
        week = "% of a Max 20x week: " + "x" * 180
        total = "total API list $: " + "y" * 100
        lines = [total, week]
        metrics.attach_ci_wait(lines, record["ci_waits"])
        self.assertTrue(lines[0].endswith(verdict), lines[0])  # the total line had room for the whole clause
        self.assertEqual(lines[1], week)
        lines = [total + "z" * (LINE_CAP - 130), week]
        metrics.attach_ci_wait(lines, record["ci_waits"])
        self.assertTrue(lines[1].endswith(f" of the week; {verdict}"), lines[1])  # neither: the short clause
        self.assertLessEqual(len(lines[1]), LINE_CAP)

    def test_without_a_ci_role_nothing_is_added(self) -> None:
        wf = self.dir / SESSION / "subagents" / "workflows"
        for p in [*(wf / "wf_q").iterdir(), *(wf / "wf_r").iterdir(), *(wf / "wf_i").glob("agent-a-p.*")]:
            p.unlink()  # the implementer's `wait` alone is left: no CI role's
        md, record, compact = self.build()
        self.assertEqual(record["ci_waits"]["rows"], [])
        self.assertNotIn("CI waits", "\n".join(md + compact))


if __name__ == "__main__":
    unittest.main()
