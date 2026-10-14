"""`wave --stalled` (#731): small synthetic session transcripts written here (never real ones) in the shape of the night
of 2026-10-09/10: a guard `ask` on a call, the finished runs' notifications queued behind it, and the cases that are
not a stall (a turn after them, a stopped run, a closed session, a call left over from an interrupted turn); and, from
trimmed copies of the art manager's lines of 2026-10-13/14 (#1044), a dropped artifact watch and a handed-over session."""

import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

from runner import cli, wave_stall
from runner.common import Failure
from runner.tests import test_wave as tw

SID = tw.SID
OTHER = "0be7a1d0-aaaa-bbbb-cccc-000000000002"
GUARD = ("git that discards work or rewrites history: git branch -d chore/1-sync (deletes another branch "
         "(chore/1-sync)). (docs/AGENT_WORKFLOW.md §8.2)")  # fmt: skip
CLEANUP = "git worktree remove D:/prime-game/.claude/worktrees/m7-sync && git branch -d chore/1-sync"
# #1044: trimmed copies of the art manager session c0f5845a's lines of 2026-10-13/14 (D--prime-game-art). Its watch on
# the day's review page dropped at 11:43Z and queued this notification; nothing needed a turn.
ARTIFACT_WATCH = ("<task-notification>\n<task-type>artifact-watch-lifecycle</task-type>\n<summary>Stopped watching "
                  "Artifact: \"Дім: огляд 13 жовтня\" (connection lost)</summary>\n<event>Watch on "
                  "https://claude.ai/artifact/LajiPbZchyc8wCwp5ZTwR2 ended — the live connection kept failing and "
                  "reconnecting has stopped.</event>\n</task-notification>")  # fmt: skip
AUTO_REACT = ("<task-notification>\n<task-type>artifact-auto-react</task-type>\n<summary>1 artifact auto-reply "
              "subscription paused by the interrupt (comments sent to Claude meanwhile are answered then)</summary>\n"
              "The user's interrupt paused it and the watch is kept.\n</task-notification>")  # fmt: skip
# Its handover: the comment posted by hand (art and UI; game and meta post it with `wave --title`) in one turn, then
# the last turn's For-you (the engineer's chat language) asking to close the session and paste the kickoff.
HANDOVER_POST = ("S=/c/Users/xperi/AppData/Local/Temp/claude/D--prime-game-art/c0f5845a/scratchpad; cat > "
                 "$S/handover.md <<'EOF'\n## Handover to a fresh manager session\n\nThe desktop art manager session "
                 "`c0f5845a` hands over at the engineer's request. **Nothing is running and nothing was stopped.**\n"
                 "EOF\ngh issue comment 34 --body-file $S/handover.md")  # fmt: skip
HANDOVER_WAVE = ('tools/run.sh wave --since 2026-10-13T08:30:00Z --plan 302 --title "Handover to a fresh manager '
                 'session" --notes "$S/notes.md"')  # fmt: skip
FOR_YOU = ("Згоден, стіни справді «ніякі». Додав обидві ідеї в нічну задачу вітальні.\n\nДля вас:\n1. Закрийте цю "
           "сесію. Відкрийте нову в `D:\\prime-game-art`, поставте режим bypass і effort high та вставте kickoff із "
           "мого попереднього повідомлення.")  # fmt: skip
WALLS = "Також знаєш, що я помітив, можливо, нам варто додати якісь картини на стіни."


def minutes(m: float) -> float:
    return tw.T0.timestamp() + m * 60


def bash(tool_id: str, command: str) -> dict:
    return {"type": "tool_use", "id": tool_id, "name": "Bash", "input": {"command": command, "description": "x"}}


def result(m: float, tool_id: str, text: str = "done") -> dict:
    block = {"type": "tool_result", "tool_use_id": tool_id, "content": text}
    return {"type": "user", "timestamp": tw.at(m), "message": {"role": "user", "content": [block]}}


def hook(m: float, tool_id: str, decision: str = "ask", reason: str = GUARD) -> dict:
    out = {"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": decision,
                                  "permissionDecisionReason": reason}}  # fmt: skip
    return {"type": "attachment", "timestamp": tw.at(m),
            "attachment": {"type": "hook_success", "hookName": "PreToolUse:Bash", "toolUseID": tool_id,
                           "hookEvent": "PreToolUse", "stdout": json.dumps(out) + "\r\n", "exitCode": 0}}  # fmt: skip


def queued_command(m: float, text: str) -> dict:
    return {"type": "attachment", "timestamp": tw.at(m), "attachment": {"type": "queued_command", "prompt": text}}


def queue(m: float, op: str, text: str = "") -> dict:
    return {"type": "queue-operation", "operation": op, "timestamp": tw.at(m), "content": text}


def timer_note(task_id: str) -> str:
    return tw.note_text("toolu-timer", task_id, summary='Background command "Keep-alive timer" completed (exit code 0)')


def prompt(m: float, text: str, origin: str | None = "human") -> dict:
    """A human's message as Claude Code writes it since `origin` (an older one has no origin)."""
    record = {"type": "user", "timestamp": tw.at(m), "promptId": f"p-{m}", "message": {"role": "user", "content": text}}
    if origin:
        record["origin"] = {"kind": origin}
    return record


def said(m: float, mid: str, words: str) -> dict:
    return tw.assistant(m, mid, [{"type": "text", "text": words}])


class StallTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.p = tw.Project(self.root)
        env = mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": "the-caller"})
        env.start()
        self.addCleanup(env.stop)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def night(self) -> None:
        """The night's shape at minute 0: a run in flight, then a guarded call that never got its result; the run's
        notification and the keep-alive timer's queued behind it (enqueue and queued_command, never dequeued)."""
        self.p.launch(-60, "t1", "wf_00bf975a-2bd", tw.issue_args(603))
        tw.journal(self.p.run_dir("wf_00bf975a-2bd"), [("p", "publish:#603", "Publish", tw.PUBLISHED)],
                   last_write=minutes(2))  # fmt: skip
        done = tw.note_text("t1", "wt1", "completed", '{"n":603,"pr":699}')
        self.p.add(tw.assistant(-1, "m-merge", [bash("b0", "tools/run.sh merge 690")]), result(-1, "b0"),
                   tw.assistant(0, "m-clean", [bash("b1", CLEANUP)]), hook(0, "b1"),
                   tw.enqueue(2, done), queued_command(2, done),
                   tw.enqueue(10, timer_note("btimer")), queued_command(10, timer_note("btimer")))  # fmt: skip

    def stall(self, now_min: float, sid: str = SID, alive: bool | None = True) -> wave_stall.Stall | None:
        return wave_stall.stall_of(self.p.write(), sid, minutes(now_min), alive)

    def main(self, now_min: float, alive: object = lambda sid: True, **kw: object) -> tuple[int, str]:
        self.p.write()
        out = io.StringIO()
        with redirect_stdout(out):
            rc = wave_stall.main(dirs=[self.p.dir], now=minutes(now_min), alive=alive, **kw)  # type: ignore[arg-type]
        return rc, out.getvalue()

    def test_the_night_is_flagged_with_the_card_it_waits_on(self) -> None:
        self.night()
        rc, out = self.main(40)
        self.assertEqual(rc, wave_stall.STALLED_EXIT)
        line = next(x for x in out.splitlines() if x.startswith("stalled: "))
        self.assertIn("'AI productivity трек: хвиля 2' (5ef6e325, D--prime-game)", line)
        self.assertIn("no turn since 08:00Z (40 min)", line)
        self.assertIn("1 run finished after it (#603 wf_00bf975a-2bd at 08:02Z)", line)
        self.assertIn("2 notifications queued, the oldest since 08:02Z", line)
        self.assertIn(f"waits on a permission card since 08:00Z: Bash `{CLEANUP}` (the guard asked: {GUARD})", line)
        self.assertIn("The engineer: answer its card.", line)
        self.assertTrue(out.rstrip().endswith("(a run finished or a notification queued over 30 min ago with no turn "
                                              "after it)"))  # fmt: skip
        self.assertIn("wave: 1 stalled of 1 session transcript written in the last 24 h", out)

    def test_not_before_the_minutes_pass(self) -> None:
        self.night()
        self.assertIsNone(self.stall(31))  # the run ended at 08:02: 29 min ago
        self.assertIsNotNone(self.stall(33))
        rc, out = self.main(19, minutes=10)  # the timer's notification at 08:10 is 9 min old
        self.assertEqual(rc, wave_stall.STALLED_EXIT)
        self.assertIn("1 run finished after it", out)
        self.assertIn("1 notification queued, the oldest since 08:02Z", out)
        with self.assertRaises(Failure):
            self.main(40, minutes=0)

    def test_the_timer_alone_is_flagged(self) -> None:
        # The keep-alive's notification queued behind the card shows the stall before any run ends.
        self.p.add(tw.assistant(0, "m-clean", [bash("b1", CLEANUP)]), hook(0, "b1"),
                   tw.enqueue(5, timer_note("btimer")))  # fmt: skip
        st = self.stall(40)
        assert st is not None
        self.assertEqual((st.runs, [n.task_id for n in st.queued]), ([], ["btimer"]))
        self.assertIn("1 notification queued, the oldest since 08:05Z", wave_stall.line_of(st, minutes(40)))

    def test_a_turn_after_the_notifications_is_no_stall(self) -> None:
        self.night()
        self.p.add(result(400, "b1", "Deleted branch chore/1-sync"), queue(400, "remove", timer_note("btimer")),
                   tw.assistant(401, "m-next"))  # fmt: skip
        self.assertIsNone(self.stall(500))
        rc, out = self.main(500)
        self.assertEqual(rc, 0)
        self.assertIn("wave: 0 stalled of 1 session transcript", out)

    def test_the_queue_operations(self) -> None:
        # enqueue A, enqueue B, dequeue (A, the head), remove of B by its text, a user record delivering C.
        a, b, c = (tw.note_text("toolu-x", x) for x in ("ba", "bb", "bc"))
        self.p.add(tw.assistant(0, "m-0", [bash("b1", "sleep 1")]),
                   tw.enqueue(1, a), tw.enqueue(2, b), queue(3, "dequeue"), queue(4, "remove", b),
                   tw.enqueue(5, c), tw.user_note(6, c), tw.enqueue(7, tw.note_text("toolu-x", "bd")),
                   tw.enqueue(8, "a message the human typed"))  # fmt: skip
        act = wave_stall.read_activity(self.p.write())
        self.assertEqual([n.task_id for n in act.queued], ["bd"])
        self.assertEqual(act.last_turn, minutes(0))
        # A remove names its item by text; a different text with the same task id still takes it out.
        self.p.add(queue(9, "remove", "<task-notification><task-id>bd</task-id></task-notification>"))
        self.assertEqual(wave_stall.read_activity(self.p.write()).queued, [])

    def test_a_stopped_run_starts_no_turn(self) -> None:
        # Two handed-over sessions got their runs' `stopped` notifications at 20:25Z on 2026-10-09 and stayed idle.
        self.p.add(tw.assistant(0, "m-0"))
        self.p.launch(1, "t1", "wf_a", tw.issue_args(5), notice="stopped", notice_at=10)
        self.p.launch(2, "t2", "wf_b", tw.issue_args(6), notice="killed", notice_at=10)
        self.assertIsNone(self.stall(120))
        self.p.launch(3, "t3", "wf_c", tw.issue_args(7), notice="failed", notice_at=10)
        st = self.stall(120)
        assert st is not None
        self.assertEqual([r.run_id for r in st.runs], ["wf_c"])

    def test_a_run_whose_journal_ended_without_a_notification(self) -> None:
        self.p.launch(0, "t1", "wf_a", tw.issue_args(5))
        tw.journal(self.p.run_dir("wf_a"), [("p", "publish:#5", "Publish", tw.PUBLISHED)], last_write=minutes(20))
        st = self.stall(60)
        assert st is not None
        self.assertEqual([(r.run_id, r.status) for r in st.runs], [("wf_a", "finished (no notification)")])
        self.assertIsNone(st.waiting)
        self.assertIn("The engineer: open it and see what it waits on.", wave_stall.line_of(st, minutes(60)))

    def test_a_call_without_a_guard_ask(self) -> None:
        self.p.add(tw.assistant(0, "m-0", [bash("b1", "tools/run.sh verify")]), hook(0, "b1", decision="allow"),
                   tw.enqueue(5, timer_note("btimer")))  # fmt: skip
        st = self.stall(40)
        assert st is not None and st.waiting is not None
        self.assertIsNone(st.waiting.ask)
        self.assertIn("waits on a Bash call since 08:00Z (a permission card or a long call): `tools/run.sh verify`",
                      wave_stall.line_of(st, minutes(40)))  # fmt: skip

    def test_a_call_left_from_an_interrupted_turn_is_not_named(self) -> None:
        self.p.add(tw.assistant(0, "m-0", [bash("old", "git branch -D x")]), hook(0, "old"),
                   tw.assistant(5, "m-1", [bash("b1", "echo hi")]), result(6, "b1"), tw.assistant(7, "m-2"),
                   tw.enqueue(8, timer_note("btimer")))  # fmt: skip
        st = self.stall(60)
        assert st is not None
        self.assertIsNone(st.waiting)

    def test_the_newest_asked_call_of_a_turn(self) -> None:
        long = "x" * 300
        self.p.add(tw.assistant(0, "m-0", [bash("b1", "git status"), bash("b2", long)]), hook(0, "b2"),
                   tw.enqueue(5, timer_note("btimer")))  # fmt: skip
        st = self.stall(40)
        assert st is not None and st.waiting is not None
        self.assertEqual(st.waiting.tool_use_id, "b2")
        self.assertEqual(len(st.waiting.what), wave_stall.WHAT_LIMIT)
        self.assertTrue(st.waiting.what.endswith("..."))

    def test_which_sessions_are_read(self) -> None:
        self.night()
        path = self.p.write()
        other = self.p.dir / f"{OTHER}.jsonl"
        tw.write_lines(other, [tw.assistant(0, "o-0", [bash("c1", CLEANUP)]), hook(0, "c1"),
                               tw.enqueue(5, timer_note("bo"))])  # fmt: skip
        # A closed session (its process gone) and the caller's own are passed over; an unknown one is flagged, saying
        # so.
        rc, out = self.main(40, alive=lambda sid: {SID: False}.get(sid))
        self.assertEqual(rc, wave_stall.STALLED_EXIT)
        self.assertNotIn("5ef6e325", out)
        self.assertIn("0be7a1d0 (D--prime-game)", out)
        self.assertIn("whether its process lives is unknown", out)
        with mock.patch.dict(os.environ, {"CLAUDE_CODE_SESSION_ID": OTHER}):
            rc, out = self.main(40, alive=lambda sid: False if sid == SID else None)
        self.assertEqual(rc, 0)
        self.assertIn("wave: 0 stalled of 2 session transcripts", out)
        # A transcript not written in the last day is not read at all.
        old = minutes(40) - 25 * 3600
        os.utime(path, (old, old))
        with redirect_stdout(io.StringIO()) as buf:
            wave_stall.main(dirs=[self.p.dir], now=minutes(40), alive=lambda sid: True)
        out = buf.getvalue()
        self.assertIn("of 1 session transcript written", out)
        self.assertNotIn("5ef6e325", out)

    def test_liveness_from_the_session_files(self) -> None:
        from runner import sessions

        files = [sessions.Session(pid=1, session_id=SID, cwd="D:/prime-game", status="idle", updated=0, name="m"),
                 sessions.Session(pid=2, session_id=OTHER, cwd="D:/prime-game", status="busy", updated=0, name="o")]
        check = wave_stall.liveness(lambda: files, lambda pid, start: pid == 2)
        self.assertEqual((check(SID), check(OTHER), check("nobody")), (False, True, False))  # a closed session
        self.assertIsNone(wave_stall.liveness(lambda: [], lambda pid, start: True)("nobody"))  # no file at all

    def test_a_card_call_next_to_a_call_that_got_its_result(self) -> None:
        # One assistant message issues both calls; the first gets its result later than the second was issued.
        self.p.add(tw.assistant(0, "m-0", [bash("b1", "git status"), bash("b2", CLEANUP)]), hook(0, "b2"),
                   result(1, "b1"), tw.enqueue(5, timer_note("btimer")))  # fmt: skip
        st = self.stall(40)
        assert st is not None and st.waiting is not None
        self.assertEqual((st.waiting.tool_use_id, bool(st.waiting.ask)), ("b2", True))
        self.assertIn("waits on a permission card", wave_stall.line_of(st, minutes(40)))

    def test_a_notification_queued_before_the_cards_call(self) -> None:
        done = tw.note_text("t1", "wt1", "completed", '{"n":603,"pr":699}')
        busy = [tw.assistant(-10, "m-a"), tw.enqueue(-5, done), tw.assistant(0, "m-clean", [bash("b1", CLEANUP)])]
        self.p.add(*busy, hook(0, "b1"))
        st = self.stall(40)
        assert st is not None
        self.assertEqual([n.task_id for n in st.queued], ["wt1"])
        # Without a card, a notification older than the last turn is not counted.
        self.p.add(result(41, "b1"), tw.assistant(42, "m-b"))
        self.assertIsNone(self.stall(100))
        self.p.add(tw.assistant(43, "m-c", [bash("b3", "sleep 1")]))
        self.assertIsNone(self.stall(100))

    def handed_over(self) -> None:
        """The art session's evening of 2026-10-13 (#1044), ending at minute 0: the human's prompt, the handover
        comment posted, his next prompt (an idea for the night) and the last turn's For-you."""
        self.p.add(prompt(-10, "давай продовжувати з арт-треком, в нового менеджера це вкинути"),
                   tw.assistant(-9, "m-post", [bash("h1", HANDOVER_POST)]), result(-9, "h1", "issuecomment-6154435850"),
                   said(-8, "m-told", "Передачу для нового менеджера опубліковано."), prompt(-2, WALLS),
                   said(0, "m-last", FOR_YOU))  # fmt: skip

    def test_an_artifact_watch_event_needs_no_turn(self) -> None:
        # #1044: c0f5845a was flagged from 12:13Z for its watch's lifecycle notification alone.
        self.p.add(tw.assistant(0, "m-0"), tw.enqueue(5, ARTIFACT_WATCH), tw.enqueue(6, AUTO_REACT))
        act = wave_stall.read_activity(self.p.write())
        self.assertEqual([n.kind for n in act.queued], ["artifact-watch-lifecycle", "artifact-auto-react"])
        self.assertIsNone(self.stall(60))
        rc, out = self.main(60)
        self.assertEqual(rc, 0)
        self.assertIn("wave: 0 stalled of 1 session transcript", out)
        # Next to a notification that needs a turn, only that one is counted.
        self.p.add(tw.enqueue(7, timer_note("btimer")))
        st = self.stall(60)
        assert st is not None
        self.assertEqual([n.task_id for n in st.queued], ["btimer"])
        self.assertIn("1 notification queued, the oldest since 08:07Z", wave_stall.line_of(st, minutes(60)))

    def test_a_handed_over_session_with_only_such_events_is_no_stall(self) -> None:
        self.handed_over()
        act = wave_stall.read_activity(self.p.write())
        self.assertEqual(act.handed_over, minutes(0))
        # The watch dropped the next day at 11:43Z; a timer or a monitor left behind ends unread too.
        monitor = tw.note_text("toolu-m", "bmon", summary='Monitor "CI checks" stream ended')
        self.p.add(tw.enqueue(15 * 60 + 43, ARTIFACT_WATCH), tw.enqueue(30, timer_note("btimer")),
                   tw.enqueue(40, monitor))  # fmt: skip
        self.assertIsNone(self.stall(18 * 60 + 28))
        rc, out = self.main(18 * 60 + 28)
        self.assertEqual(rc, 0)
        self.assertNotIn("stalled: ", out)

    def test_a_run_finished_after_the_handover_is_still_a_stall(self) -> None:
        self.p.launch(-60, "t1", "wf_a", tw.issue_args(150))
        self.p.launch(-50, "t2", "wf_b", tw.issue_args(152))
        self.handed_over()
        done = tw.note_text("t1", "wt1", "completed", '{"pr":151}')
        self.p.add(tw.enqueue(20, done), tw.enqueue(21, tw.note_text("t2", "wt2", "stopped")),
                   tw.enqueue(25, ARTIFACT_WATCH), tw.enqueue(26, timer_note("btimer")))  # fmt: skip
        st = self.stall(120)
        assert st is not None
        self.assertEqual([r.run_id for r in st.runs], ["wf_a"])
        self.assertEqual([n.task_id for n in st.queued], ["wt1"])
        line = wave_stall.line_of(st, minutes(120))
        self.assertIn("no turn since 08:00Z (2 h 0 min); 1 run finished after it (#150 wf_a at 08:20Z); 1 notification "
                      "queued, the oldest since 08:20Z; it handed over at 08:00Z. The engineer:", line)  # fmt: skip

    def test_a_turn_after_the_handover_takes_it_back(self) -> None:
        # A prompt after the handover that the session answers without handing over again: it works on.
        self.handed_over()
        self.p.add(prompt(5, "ні, лишайся, продовжуй"), said(6, "m-on", "Добре, продовжую."),
                   tw.enqueue(10, timer_note("btimer")))  # fmt: skip
        self.assertIsNone(wave_stall.read_activity(self.p.write()).handed_over)
        st = self.stall(60)
        assert st is not None
        self.assertEqual([n.task_id for n in st.queued], ["btimer"])
        # A task notification or an interrupt is no prompt: the handover holds through the turn they start.
        self.p.lines = self.p.lines[:-3]
        self.p.add(tw.user_note(5, timer_note("bt0")), said(6, "m-noted", "Таймер спрацював."),
                   prompt(7, "[Request interrupted by user]", origin=None), tw.enqueue(10, timer_note("btimer")))  # fmt: skip
        self.assertEqual(wave_stall.read_activity(self.p.write()).handed_over, minutes(0))
        self.assertIsNone(self.stall(60))

    def test_the_handover_marks(self) -> None:
        # Game and meta post the comment with `wave --title`; an English For-you; an older Claude Code with no origin.
        for last in (tw.assistant(0, "m-w", [bash("h2", HANDOVER_WAVE)]),
                     said(0, "m-en", "For you:\n1. Close this session, open a new one in `D:\\prime-game` and paste "
                                     "the kickoff below.")):  # fmt: skip
            with self.subTest(last=last["message"]["id"]):
                self.p.lines = self.p.lines[:1]
                self.p.add(prompt(-5, "hand over", origin=None), last, tw.enqueue(10, timer_note("btimer")))
                self.assertEqual(wave_stall.read_activity(self.p.write()).handed_over, minutes(0))
                self.assertIsNone(self.stall(60))
        # A fresh session reading its predecessor's handover, or a "close" with no kickoff to paste, hands nothing over.
        read = ("gh api repos/o/r/issues/34/comments --jq '.[] | select(.body | startswith(\"## Handover to a fresh "
                "manager session\")) | .html_url'")  # fmt: skip
        for last in (tw.assistant(0, "m-r", [bash("r1", read)]),
                     said(0, "m-c", "Закрийте цю сесію, коли перевірите сторінку.")):  # fmt: skip
            with self.subTest(last=last["message"]["id"]):
                self.p.lines = self.p.lines[:1]
                self.p.add(prompt(-5, 'Continue from the latest comment titled "Handover to a fresh manager session"'),
                           last, tw.enqueue(10, timer_note("btimer")))  # fmt: skip
                self.assertIsNone(wave_stall.read_activity(self.p.write()).handed_over)
                self.assertIsNotNone(self.stall(60))

    def test_editing_a_file_that_holds_the_title_hands_nothing_over(self) -> None:
        # The handover skill's own file starts with the title as a heading: a turn that edits it posts no handover.
        title = "# Handover to a fresh manager session\n\nThe order from here."
        for tool, inp in (("Write", {"file_path": "handover.md", "content": title}),
                          ("Edit", {"file_path": "handover.md", "old_string": "x", "new_string": title}),
                          ("MultiEdit", {"file_path": "handover.md",
                                         "edits": [{"old_string": "x", "new_string": title}]})):  # fmt: skip
            with self.subTest(tool=tool):
                self.p.lines = self.p.lines[:1]
                call = {"type": "tool_use", "id": "e1", "name": tool, "input": inp}
                self.p.add(prompt(-5, "update the handover skill"), tw.assistant(0, "m-e", [call]),
                           tw.enqueue(10, timer_note("btimer")))  # fmt: skip
                self.assertIsNone(wave_stall.read_activity(self.p.write()).handed_over)
                self.assertIsNotNone(self.stall(60))

    def test_the_command_line(self) -> None:
        args = cli.build_parser().parse_args(["wave", "--stalled"])
        self.assertEqual((args.stalled, args.minutes, args.since, args.args), (True, None, None, None))
        self.assertEqual(cli.build_parser().parse_args(["wave", "--stalled", "--minutes", "45"]).minutes, 45)
        with self.assertRaises(SystemExit), redirect_stderr(io.StringIO()):
            cli.build_parser().parse_args(["wave", "--stalled", "--since", "T"])
        with mock.patch.object(wave_stall, "main", return_value=3) as run, redirect_stdout(io.StringIO()):
            self.assertEqual(cli.main(["wave", "--stalled", "--minutes", "45"]), 3)
            run.assert_called_once_with(minutes=45)
            self.assertEqual(cli.main(["wave", "--stalled"]), 3)
            self.assertEqual(run.call_args.kwargs, {"minutes": wave_stall.STALL_MINUTES})
            for bad in (["--session", "x"], ["--base", "main"], ["--no-merge-check"]):
                self.assertEqual(cli.main(["wave", "--stalled", *bad]), 1, bad)
            self.assertEqual(cli.main(["wave", "--args", "5", "--minutes", "9"]), 1)
            self.assertEqual(run.call_count, 2)


if __name__ == "__main__":
    unittest.main()
