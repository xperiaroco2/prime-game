"""`wave --in-flight` (#1355): small synthetic session transcripts written here (never real ones), an art session and a
design session in their own checkouts' folders as the secretary meets them on 2026-10-28: the art session waits on its
own workflow (one run in flight, one finished), the design session only ended its turn (its one run finished)."""

import io
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from runner import cli, metrics, sessions, wave_flight
from runner.tests import test_wave as tw

ART = "0c5fbfbd-5726-4dbb-9659-0dff2db6da32"
DESIGN = "7d1e4b2a-1111-2222-3333-000000000003"
NOW = tw.T0.timestamp() + 2 * 3600  # 10:00


def minutes(m: float) -> float:
    return tw.T0.timestamp() + m * 60


class Session:
    """One transcript in one checkout's folder: its title, its cwd and its Workflow calls."""

    def __init__(self, folder: Path, sid: str, title: str | None, cwd: str) -> None:
        self.folder, self.sid, self.cwd = folder, sid, cwd
        self.lines: list[object] = [{"type": "custom-title", "customTitle": title}] if title else []

    def run_dir(self, run_id: str) -> Path:
        return self.folder / self.sid / "subagents" / "workflows" / run_id

    def launch(self, m: float, tool_id: str, run_id: str, *, done: bool, name: str = "issue-task",
               args: object = None, journal_at: float | None = None, **inp: object) -> None:  # fmt: skip
        """A Workflow call and its result; done: its journal reached the end and its notification came 30 min later.
        Every record carries the session's cwd, as Claude Code writes it."""
        given: dict = {"name": name, **({"args": args} if args is not None else {}), **inp}
        task = f"w{tool_id}"
        self.lines += [tw.assistant(m, f"msg-{tool_id}", [tw.workflow(tool_id, **given)]),
                       tw.launched(m, tool_id, run_id, task, name=name)]  # fmt: skip
        result = tw.PUBLISHED if done else None
        n = args.get("n") if isinstance(args, dict) else None
        labels = (f"implement:#{n}", f"publish:#{n}") if n is not None else ("dress:bodies", "render:bodies")
        tw.journal(self.run_dir(run_id), [("k1", labels[0], "Implement", {"verify_green": True}),
                                          ("k2", labels[1], "Publish", result)],
                   last_write=journal_at if journal_at is not None else minutes(m + 20))  # fmt: skip
        if done:
            note = tw.note_text(tool_id, task, "completed")
            self.lines += [tw.enqueue(m + 30, note), tw.user_note(m + 30, note),
                           tw.assistant(m + 31, f"after-{tool_id}", [{"type": "text", "text": "read it"}])]  # fmt: skip

    def background(self, m: float, tool_id: str, task_id: str, *, agent: bool, done: bool = False) -> None:
        """A background Agent (its result names the agentId) or Bash call (its result names the backgroundTaskId), as
        the art session of 2026-10-28 launched its builders and waits; done: its notification came 20 min later."""
        call, tur, block = bg_call(tool_id, task_id, agent)
        self.lines += [tw.assistant(m, f"msg-{tool_id}", [call]),
                       {"type": "user", "timestamp": tw.at(m), "toolUseResult": tur,
                        "message": {"role": "user", "content": [block]}}]  # fmt: skip
        if done:
            summary = 'Agent "Builder C1" finished' if agent else 'Background command "wait" completed (exit code 0)'
            note = tw.note_text(tool_id, task_id, "completed", summary=summary)
            self.lines += [tw.enqueue(m + 20, note), tw.user_note(m + 20, note)]

    def said(self, m: float, mid: str) -> None:
        self.lines.append(tw.assistant(m, mid, [{"type": "text", "text": "Для вас: нічого."}]))

    def write(self) -> Path:
        path = self.folder / f"{self.sid}.jsonl"
        tw.write_lines(path, [{**x, "cwd": self.cwd} if isinstance(x, dict) and "timestamp" in x else x
                              for x in self.lines])  # fmt: skip
        return path


def bg_call(tool_id: str, task_id: str, agent: bool) -> tuple[dict, dict, dict]:
    """A background call, its toolUseResult and its tool_result block, with the texts of Claude Code 2.1.308."""
    if agent:
        call = {"type": "tool_use", "id": tool_id, "name": "Agent",
                "input": {"description": "Builder C1: dungarees on both bodies", "run_in_background": True}}
        tur = {"isAsync": True, "status": "async_launched", "agentId": task_id, "description": "Builder C1"}
        text = ("Async agent launched successfully. (This tool result is internal metadata.)\nagentId: "
                f"{task_id} (internal ID - do not mention to user.)\nThe agent is working in the background.")
        return call, tur, {"type": "tool_result", "tool_use_id": tool_id, "content": [{"type": "text", "text": text}]}
    call = {"type": "tool_use", "id": tool_id, "name": "Bash",
            "input": {"command": "tools/run.sh wait tools/out/verify.log", "run_in_background": True}}
    tur = {"stdout": "", "stderr": "", "interrupted": False, "backgroundTaskId": task_id}
    text = f"Command running in background with ID: {task_id}. Output is being written to: C:\\tmp\\{task_id}.output."
    return call, tur, {"type": "tool_result", "tool_use_id": tool_id, "content": text}


def bare_note(task_id: str = "", tool_id: str = "") -> str:
    """A notification naming only a task id or only a call."""
    ids = (f"<task-id>{task_id}</task-id>\n" if task_id else "") + (f"<tool-use-id>{tool_id}</tool-use-id>\n" if tool_id else "")
    return f"<task-notification>\n{ids}<status>completed</status>\n<summary>done</summary>\n</task-notification>"


class InFlightTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        projects = self.root / "projects"
        self.art = Session(projects / "D--prime-game-art", ART, "Анімації прибульців (art #196)", "D:\\prime-game-art")
        self.design = Session(projects / "D--prime-game-design", DESIGN, "Console hologram spin-up states",
                              "D:\\prime-game-design")  # fmt: skip
        (projects / "D--prime-game").mkdir(parents=True)
        env = mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "the-caller", "CLAUDE_CONFIG_DIR": str(self.root)})
        env.start()
        self.addCleanup(env.stop)
        checkout = mock.patch.object(metrics, "main_checkout", return_value=Path("D:/prime-game"))
        checkout.start()
        self.addCleanup(checkout.stop)

    def shape(self) -> None:
        """The art session launched C1 at 08:10 (finished at 08:40) and C2 at 09:28 (in flight); the design session's
        one run finished at 08:50 and it ended its turn at 09:41."""
        self.art.launch(10, "t1", "wf_c1-done", done=True, args=tw.issue_args(196))
        self.art.launch(88, "t2", "wf_c2-flight", done=False, name="clothes-step", journal_at=minutes(110))
        self.art.said(89, "m-art-end")
        self.design.launch(20, "t3", "wf_d1-done", done=True)
        self.design.said(101, "m-design-end")
        self.art.write()
        self.design.write()

    def main(self, alive: object = lambda sid: True, started: float | None = None,
             host: str | None = None) -> tuple[int, str]:  # fmt: skip
        out = io.StringIO()
        with redirect_stdout(out):
            rc = wave_flight.main(now=NOW, live=lambda sid: wave_flight.Live(alive(sid), started, host))  # type: ignore[operator]
        return rc, out.getvalue()

    def test_only_the_run_in_flight_is_listed_with_what_matches_list_sessions(self) -> None:
        self.shape()
        rc, out = self.main()
        self.assertEqual(rc, 0)
        lines = [x for x in out.splitlines() if x.startswith("in flight: ")]
        self.assertEqual(len(lines), 1, out)
        line = lines[0]
        for want in ("'Анімації прибульців (art #196)'", "checkout prime-game-art", "cwd D:\\prime-game-art",
                     "last record 2026-10-03 09:29Z", f"transcript {ART}",
                     "wf_c2-flight (clothes-step) started 2026-10-03 09:28Z, its journal last written 09:50Z"):  # fmt: skip
            self.assertIn(want, line)
        self.assertNotIn("wf_c1-done", out)
        self.assertNotIn(DESIGN, out)
        self.assertNotIn("Console hologram", out)
        self.assertIn("wave: 1 session with work in flight (1 workflow run, 0 agents, 0 commands) of 2 session "
                      "transcripts written in the last 24 h", out)  # fmt: skip

    def test_nothing_in_flight_exits_0_too(self) -> None:
        self.design.launch(20, "t3", "wf_d1-done", done=True)
        self.design.write()
        rc, out = self.main()
        self.assertEqual(rc, 0)
        self.assertNotIn("in flight: ", out)
        self.assertIn("wave: 0 sessions with work in flight of 1 session transcript", out)

    def test_an_issue_run_names_its_issue(self) -> None:
        self.art.launch(88, "t2", "wf_c2-flight", done=False, args=tw.issue_args(1355))
        self.art.write()
        _rc, out = self.main()
        self.assertIn("wf_c2-flight (issue-task #1355) started", out)

    def test_a_closed_session_and_the_callers_own_are_passed_over(self) -> None:
        self.shape()
        rc, out = self.main(alive=lambda sid: False)
        self.assertEqual(rc, 0)
        self.assertNotIn("in flight: ", out)
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": ART}):
            _rc, out = self.main()
        self.assertNotIn("in flight: ", out)
        # Unknown liveness (no session files at all): listed, saying so.
        _rc, out = self.main(alive=lambda sid: None)
        self.assertIn("whether its process lives is unknown", out)

    def test_a_session_with_no_title_is_named_by_its_cwd(self) -> None:
        untitled = Session(self.art.folder, ART, None, "D:\\prime-game-art")
        untitled.launch(88, "t2", "wf_c2-flight", done=False)
        untitled.write()
        _rc, out = self.main()
        self.assertIn("in flight: (no title) (checkout prime-game-art, cwd D:\\prime-game-art", out)

    def test_a_run_resumed_under_a_new_id_is_listed_once(self) -> None:
        self.art.launch(60, "t1", "wf_old", done=False, args=tw.issue_args(7))
        self.art.launch(70, "t2", "wf_new", done=False, args=tw.issue_args(7), resumeFromRunId="wf_old")
        self.art.write()
        _rc, out = self.main()
        self.assertIn("wf_new", out)
        self.assertNotIn("wf_old", out)

    def test_background_agents_and_commands_in_flight(self) -> None:
        # The art session of 2026-10-28 waited on its builder, a background Agent, and on a background command; the
        # ones whose notification came are done.
        self.art.background(60, "t5", "a17001b9c38ea4d51", agent=True, done=True)
        self.art.background(85, "t6", "a1151b23daa05c484", agent=True)
        self.art.background(86, "t7", "bhuyzix3c", agent=False)
        self.art.background(87, "t8", "bsmtgczza", agent=False, done=True)
        sub = self.art.folder / ART / "subagents" / "agent-a1151b23daa05c484.jsonl"
        tw.write_lines(sub, [{"type": "user"}])
        os.utime(sub, (minutes(112), minutes(112)))
        self.art.said(89, "m-art-end")
        self.art.write()
        rc, out = self.main()
        self.assertEqual(rc, 0)
        line = next(x for x in out.splitlines() if x.startswith("in flight: "))
        self.assertIn("agent a1151b23daa05c484 'Builder C1: dungarees on both bodies' started 2026-10-03 09:25Z, its "
                      "transcript last written 09:52Z", line)  # fmt: skip
        self.assertIn("command bhuyzix3c `tools/run.sh wait tools/out/verify.log` started 2026-10-03 09:26Z", line)
        self.assertNotIn("a17001b9c38ea4d51", out)
        self.assertNotIn("bsmtgczza", out)
        self.assertIn("1 session with work in flight (0 workflow runs, 1 agent, 1 command)", out)

    def test_a_task_stopped_by_taskstop_is_done(self) -> None:
        # A stopped task sends no notification, only TaskStop's result: on 2026-10-27 the art session stopped its
        # keep-alive `sleep 3000` timers so. Its parallel call shares the record, which then has no toolUseResult; a
        # failed stop leaves the task in flight.
        self.art.background(60, "t5", "b2dalx23v", agent=False)
        self.art.background(61, "t6", "blvhy8ak3", agent=False)
        self.art.background(62, "t7", "bkeep0000", agent=False)
        stop = {"type": "tool_use", "id": "s1", "name": "TaskStop", "input": {"task_id": "b2dalx23v"}}
        stop2 = {"type": "tool_use", "id": "s2", "name": "TaskStop", "input": {"task_id": "blvhy8ak3"}}
        stop3 = {"type": "tool_use", "id": "s3", "name": "TaskStop", "input": {"task_id": "bkeep0000"}}
        ok = '{"message":"Successfully stopped task: %s (sleep 3000)","task_id":"%s","task_type":"local_bash"}'
        self.art.lines += [
            tw.assistant(70, "m-stop", [stop, stop2, stop3]),
            {"type": "user", "timestamp": tw.at(70), "message": {"role": "user", "content": [
                {"type": "tool_result", "tool_use_id": "s1", "content": ok % ("b2dalx23v", "b2dalx23v")},
                {"type": "tool_result", "tool_use_id": "s2", "content": ok % ("blvhy8ak3", "blvhy8ak3")},
                {"type": "tool_result", "tool_use_id": "s3", "is_error": True, "content": "No task found"}]}},
        ]  # fmt: skip
        self.art.write()
        _rc, out = self.main()
        self.assertNotIn("b2dalx23v", out)
        self.assertNotIn("blvhy8ak3", out)
        self.assertIn("command bkeep0000 `tools/run.sh wait tools/out/verify.log`", out)

    def test_parallel_background_launches_share_one_record(self) -> None:
        # Two builders launched in one message: their results share one user record, which then has no toolUseResult;
        # the texts name them. A Bash call moved to the background after its timeout names its id too.
        a, _tur, ra = bg_call("t5", "a09349bc181adc576", agent=True)
        b, _tur, rb = bg_call("t6", "a1151b23daa05c484", agent=True)
        c = {"type": "tool_use", "id": "t7", "name": "Bash", "input": {"command": "tools/run.sh verify"}}
        rc_ = {"type": "tool_result", "tool_use_id": "t7", "content": "Command did not complete within its 120s "
               "timeout and was moved to the background (ID: beaidszb8). Output is being written to: C:\\tmp\\x"}
        self.art.lines += [tw.assistant(85, "m-par", [a, b]),
                           {"type": "user", "timestamp": tw.at(85), "message": {"role": "user", "content": [ra, rb]}},
                           tw.assistant(86, "m-slow", [c]),
                           {"type": "user", "timestamp": tw.at(88), "message": {"role": "user", "content": [rc_]}}]  # fmt: skip
        self.art.write()
        _rc, out = self.main()
        for want in ("agent a09349bc181adc576", "agent a1151b23daa05c484", "command beaidszb8 `tools/run.sh verify`"):
            self.assertIn(want, out)

    def test_a_notification_only_queued_or_naming_only_its_call_ends_the_task(self) -> None:
        # Queued while the session was busy (never delivered yet), or naming only the call: either ends the task.
        self.art.background(60, "t5", "bqueued00", agent=False)
        self.art.background(61, "t6", "bcallonly", agent=False)
        self.art.background(62, "t7", "bstill000", agent=False)
        self.art.lines += [tw.enqueue(70, bare_note(task_id="bqueued00")), tw.user_note(71, bare_note(tool_id="t6"))]
        self.art.write()
        _rc, out = self.main()
        self.assertNotIn("bqueued00", out)
        self.assertNotIn("bcallonly", out)
        self.assertIn("command bstill000", out)

    def test_killshell_stops_a_command_too(self) -> None:
        self.art.background(60, "t5", "bkilled00", agent=False)
        kill = {"type": "tool_use", "id": "k1", "name": "KillShell", "input": {"shell_id": "bkilled00"}}
        self.art.lines += [tw.assistant(70, "m-kill", [kill]),
                           {"type": "user", "timestamp": tw.at(70), "message": {"role": "user", "content": [
                               {"type": "tool_result", "tool_use_id": "k1", "content": "Shell bkilled00 killed"}]}}]  # fmt: skip
        self.art.write()
        _rc, out = self.main()
        self.assertNotIn("bkilled00", out)

    def test_a_stopped_workflow_with_no_notification_is_done(self) -> None:
        self.art.launch(60, "t2", "wf_stopped", done=False)
        stop = {"type": "tool_use", "id": "s1", "name": "TaskStop", "input": {"task_id": "wt2"}}
        self.art.lines += [tw.assistant(70, "m-stop", [stop]),
                           {"type": "user", "timestamp": tw.at(70), "message": {"role": "user", "content": [
                               {"type": "tool_result", "tool_use_id": "s1", "content": "Successfully stopped task: wt2"}]}}]  # fmt: skip
        self.art.write()
        _rc, out = self.main()
        self.assertNotIn("wf_stopped", out)

    def test_work_launched_before_the_live_process_started_died_with_it(self) -> None:
        # The Desktop app restarted at 09:20 under the same session: what the earlier process launched sent nothing.
        self.art.launch(60, "t1", "wf_before", done=False)
        self.art.background(70, "t5", "a0before0", agent=True)
        self.art.background(85, "t6", "a1after00", agent=True)
        self.art.write()
        _rc, out = self.main(started=minutes(80), host="local_21526497-c313-4642-ac4b-b8faef877a92")
        self.assertNotIn("wf_before", out)
        self.assertNotIn("a0before0", out)
        self.assertIn("in flight: 'Анімації прибульців (art #196)' (desktop local_21526497-c313-4642-ac4b-b8faef877a92, "
                      "checkout prime-game-art", out)  # fmt: skip
        self.assertIn("agent a1after00", out)

    def test_liveness_names_the_live_process_start_and_desktop_id(self) -> None:
        def file(pid: int, sid: str, started: float, host: str = "") -> sessions.Session:
            return sessions.Session(pid=pid, session_id=sid, cwd="D:/prime-game-art", status="idle", updated=0,
                                    name="x", started=started, host_session=host)  # fmt: skip

        files = [file(1, ART, 100.0, "local_old"), file(2, ART, 200.0, "local_new"), file(3, DESIGN, 50.0)]
        check = wave_flight.liveness(read=lambda: files, alive=lambda pid, start: pid != 3)
        self.assertEqual(check(ART), wave_flight.Live(True, 200.0, "local_new"))
        self.assertEqual(check(DESIGN), wave_flight.Live(False))
        self.assertEqual(check("unnamed"), wave_flight.Live(False))
        self.assertEqual(wave_flight.liveness(read=lambda: [])("any"), wave_flight.Live(None))

    def test_a_workflow_is_no_background_task(self) -> None:
        # Even a Workflow result that carried an agentId is read by wave.build_runs, never as an agent.
        self.art.launch(88, "t2", "wf_c2-flight", done=False, name="clothes-step")
        self.art.lines[-1]["toolUseResult"]["agentId"] = "a-not-an-agent"
        self.art.write()
        _rc, out = self.main()
        self.assertNotIn("a-not-an-agent", out)
        self.assertIn("(1 workflow run, 0 agents, 0 commands)", out)

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(["wave", "--in-flight"])
        self.assertEqual((args.in_flight, args.stalled, args.since, args.args), (True, False, None, None))
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["wave", "--in-flight", "--stalled"])
        with mock.patch.object(wave_flight, "main", return_value=0) as run, redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["wave", "--in-flight"]), 0)
            run.assert_called_once_with()
            for bad in (["--session", "x"], ["--minutes", "5"], ["--no-merge-check"]):
                self.assertEqual(cli.main(["wave", "--in-flight", *bad]), 1, bad)
            self.assertEqual(run.call_count, 1)


if __name__ == "__main__":
    unittest.main()
