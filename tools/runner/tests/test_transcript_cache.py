"""The transcript cache (#1014): metrics.read_agent's parsed summaries kept per transcript, keyed by path, size and
mtime, on test_metrics' synthetic project folder (never real transcripts): a hit, a miss on a changed size or mtime,
a corrupt entry, a version or parser change, a file written while it is read, and every report byte-identical with
and without the cache; and metrics' GitHub lists read at once."""

import json
import os
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

from runner import cli, common, metrics, transcript_cache
from runner.common import Failure
from runner.tests.test_metrics import SESSION, UNTIL, Fixture, assistant, usage

WINDOWS = [(None, UNTIL), ("2026-10-02T08:20:00Z", UNTIL), ("2026-10-02T08:01:00Z", "2026-10-02T08:30:00Z")]


def t(text: str | None) -> float | None:
    return metrics.parse_time(text) if text else None


class TranscriptCacheTest(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.fx = Fixture(self.root)
        self.store = self.root / "cache"
        self.agent = self.fx.dir.joinpath(SESSION, "subagents", "workflows", "wf_done", "agent-a-impl.jsonl")
        self.addCleanup(transcript_cache.enable, None)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def report(self, since: str | None, until: str) -> tuple[str, str, list[str]]:
        data = metrics.collect([self.fx.dir], {}, t(since), t(until))
        md, record, compact = metrics.build(data, [], None, t(since), t(until))
        return md, json.dumps(record, sort_keys=True, default=str), compact

    def counted(self, read):
        """read() with metrics.parse_agent counted: (its value, how many transcripts were parsed)."""
        with mock.patch.object(metrics, "parse_agent", wraps=metrics.parse_agent) as parse:
            value = read()
        return value, parse.call_count

    def test_off_unless_enabled(self) -> None:
        self.assertIsNone(transcript_cache.folder())
        metrics.read_agent(self.agent)
        self.assertFalse(self.store.exists())

    def test_every_report_is_identical_with_and_without_the_cache(self) -> None:
        for since, until in WINDOWS:
            with self.subTest(since=since, until=until):
                transcript_cache.enable(None)
                plain = self.report(since, until)
                transcript_cache.enable(self.store)
                cold, parsed = self.counted(lambda: self.report(since, until))
                warm, again = self.counted(lambda: self.report(since, until))
                self.assertEqual(cold, plain)
                self.assertEqual(warm, plain)
                self.assertGreater(parsed, 0)
                self.assertEqual(again, 0)  # every transcript a hit
        self.assertTrue(any(self.store.glob("*.pickle")))

    def test_a_hit_returns_the_parsed_types(self) -> None:
        transcript_cache.enable(self.store)
        cold = metrics.read_agent(self.agent)
        warm, parsed = self.counted(lambda: metrics.read_agent(self.agent))
        self.assertEqual(parsed, 0)
        self.assertEqual(warm, cold)
        self.assertIsNot(warm, cold)  # a fresh copy: a caller that changes it changes no later hit
        self.assertIs(type(warm["kind_counts"]), type(cold["kind_counts"]))
        self.assertEqual([type(x) for x in warm["fore"]], [type(x) for x in cold["fore"]])

    def test_until_after_the_last_line_is_one_window(self) -> None:
        # A report "until now" hits the entry of an earlier "until now": both cut nothing.
        transcript_cache.enable(self.store)
        metrics.read_agent(self.agent, None, t(UNTIL))
        _, parsed = self.counted(lambda: metrics.read_agent(self.agent, None, t(UNTIL) + 3600))
        self.assertEqual(parsed, 0)
        # An until inside the file is a window of its own, parsed.
        cut, parsed = self.counted(lambda: metrics.read_agent(self.agent, None, t("2026-10-02T08:09:00Z")))
        self.assertEqual(parsed, 1)
        transcript_cache.enable(None)
        self.assertEqual(cut, metrics.read_agent(self.agent, None, t("2026-10-02T08:09:00Z")))

    def test_a_grown_file_is_parsed_again(self) -> None:
        # The live session: each read after an append sees the new lines.
        transcript_cache.enable(self.store)
        before = metrics.read_agent(self.agent)
        line = json.dumps(assistant(11, "msg-new", usage(inp=1, read=100))) + "\n"
        mtime = self.agent.stat().st_mtime_ns
        with open(self.agent, "a", encoding="utf-8", newline="\n") as f:
            f.write(line)
        os.utime(self.agent, ns=(mtime, mtime))  # the same mtime: the size alone tells
        after, parsed = self.counted(lambda: metrics.read_agent(self.agent))
        self.assertEqual(parsed, 1)
        self.assertEqual(after["api_calls"], before["api_calls"] + 1)
        self.assertEqual(self.counted(lambda: metrics.read_agent(self.agent)), (after, 0))

    def test_a_changed_mtime_is_parsed_again(self) -> None:
        transcript_cache.enable(self.store)
        before = metrics.read_agent(self.agent)
        text = self.agent.read_text(encoding="utf-8")
        same_size = text.replace("msg-i4", "msg-i9")  # the same size, other content
        self.assertEqual(len(same_size), len(text))
        mtime = self.agent.stat().st_mtime_ns
        self.agent.write_bytes(same_size.encode("utf-8"))
        os.utime(self.agent, ns=(mtime + 1_000_000_000, mtime + 1_000_000_000))
        after, parsed = self.counted(lambda: metrics.read_agent(self.agent))
        self.assertEqual(parsed, 1)
        self.assertEqual(after["api_calls"], before["api_calls"])
        transcript_cache.enable(None)
        self.assertEqual(after, metrics.read_agent(self.agent))

    def test_a_corrupt_entry_is_parsed_again_and_replaced(self) -> None:
        transcript_cache.enable(self.store)
        cold = metrics.read_agent(self.agent)
        entry = transcript_cache.entry_path(self.store, self.agent)
        for garbage in (b"", b"not a pickle", entry.read_bytes()[:40]):
            with self.subTest(garbage=garbage[:12]):
                entry.write_bytes(garbage)
                again, parsed = self.counted(lambda: metrics.read_agent(self.agent))
                self.assertEqual((again, parsed), (cold, 1))
                self.assertEqual(self.counted(lambda: metrics.read_agent(self.agent)), (cold, 0))

    def test_a_version_or_parser_change_is_parsed_again(self) -> None:
        transcript_cache.enable(self.store)
        cold = metrics.read_agent(self.agent)
        with mock.patch.object(transcript_cache, "VERSION", transcript_cache.VERSION + 1):
            self.assertEqual(self.counted(lambda: metrics.read_agent(self.agent)), (cold, 1))
        with mock.patch.object(metrics, "_PARSER_SALT", "another parser"):
            self.assertEqual(self.counted(lambda: metrics.read_agent(self.agent)), (cold, 1))

    def test_a_file_written_while_it_is_read_is_not_stored(self) -> None:
        transcript_cache.enable(self.store)
        parse = metrics.parse_agent

        def appending(path, since=None, until=None):
            value = parse(path, since, until)
            with open(path, "a", encoding="utf-8", newline="\n") as f:
                f.write(json.dumps(assistant(12, "msg-late", usage(inp=1))) + "\n")
            return value

        with mock.patch.object(metrics, "parse_agent", side_effect=appending):
            metrics.read_agent(self.agent)
        self.assertFalse(transcript_cache.entry_path(self.store, self.agent).exists())
        transcript_cache.enable(None)
        whole = metrics.read_agent(self.agent)
        transcript_cache.enable(self.store)
        self.assertEqual(metrics.read_agent(self.agent), whole)

    def test_an_entry_keeps_the_newest_windows(self) -> None:
        transcript_cache.enable(self.store)
        sinces = [t("2026-10-02T08:00:00Z") + 10 * n for n in range(transcript_cache.WINDOWS + 2)]
        for since in sinces:
            metrics.read_agent(self.agent, since)
        entry = transcript_cache.load(transcript_cache.entry_path(self.store, self.agent))
        self.assertEqual([k[0] for k in entry["windows"]], sinces[-transcript_cache.WINDOWS:])

    def test_the_cli_caches_only_while_metrics_runs(self) -> None:
        seen = []
        def main(*_args, **_kwargs) -> int:
            seen.append(transcript_cache.folder())
            return 0

        with mock.patch.object(metrics, "main", side_effect=main):
            self.assertEqual(cli.main(["metrics", "--compact"]), 0)
        self.assertEqual(seen, [common.TRANSCRIPT_CACHE])
        self.assertIsNone(transcript_cache.folder())


class ReadGithubTest(unittest.TestCase):
    """#1014's other half: a warm `metrics` run waits mostly on its three `gh` listings, so they are read at once."""

    def test_the_three_lists_are_read_at_once(self) -> None:
        barrier = threading.Barrier(3, timeout=10)  # passes only when all three calls wait together

        def gh(args: list[str]) -> str:
            barrier.wait()
            return json.dumps([{"kind": args[0]}])

        github = metrics.read_github(gh)
        self.assertEqual([github[k] for k in ("prs", "runs", "issues")], [[{"kind": "pr"}], [{"kind": "run"}],
                                                                           [{"kind": "issue"}]])  # fmt: skip

    def test_a_failure_is_the_first_in_order(self) -> None:
        def gh(args: list[str]) -> str:
            if args[0] == "pr":
                return "[]"
            raise Failure(f"gh {args[0]} list failed")

        with self.assertRaisesRegex(Failure, "gh run list failed"):
            metrics.read_github(gh)

if __name__ == "__main__":
    unittest.main()
