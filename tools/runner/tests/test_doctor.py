"""doctor's UDP backlog check (#159): a kernel that drops part of the stall step's backlog is warned about early;
its cloud TwoVoIP check (#345); and the worktrees' root CLAUDE.md exclude (#385)."""

import contextlib
import io
import json
import re
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import doctor
from runner.common import ROOT


class UdpBacklogTest(unittest.TestCase):
    def output(self, held: int | OSError, linux: bool = True) -> str:
        buffer = io.StringIO()
        probe = {"side_effect": held} if isinstance(held, OSError) else {"return_value": held}
        with (
            mock.patch.object(doctor, "loopback_datagrams_held", **probe),
            mock.patch.object(doctor, "IS_LINUX", linux),
            contextlib.redirect_stdout(buffer),
        ):
            doc = doctor.Doctor()
            doc.udp_backlog()
        self.assertEqual(doc.failures, 0)
        return buffer.getvalue()

    def test_a_socket_that_holds_the_backlog(self) -> None:
        out = self.output(doctor.STALL_BACKLOG_DATAGRAMS)
        self.assertIn("ok    a default UDP socket holds the stall backlog (320 datagrams)", out)

    def test_a_socket_that_drops_part_of_it_warns_with_the_fix(self) -> None:
        out = self.output(255)
        self.assertIn("warn  a default UDP socket on 127.0.0.1 holds only 255 of the stall step's 320", out)
        self.assertIn("sysctl -w net.core.rmem_default=425984", out)

    def test_only_linux_is_probed(self) -> None:
        self.assertEqual(self.output(0, linux=False), "")

    def test_a_probe_that_cannot_open_a_socket_only_warns(self) -> None:
        out = self.output(OSError("no loopback"))
        self.assertIn("warn  could not probe UDP on 127.0.0.1 for the stall step's backlog: no loopback", out)

    def test_the_probe_counts_what_a_real_socket_holds(self) -> None:
        self.assertEqual(doctor.loopback_datagrams_held(8), 8)

    def test_the_probe_counts_what_a_small_buffer_drops(self) -> None:
        held = doctor.loopback_datagrams_held(doctor.STALL_BACKLOG_DATAGRAMS, rcvbuf=4096)
        self.assertGreater(held, 0)
        self.assertLess(held, doctor.STALL_BACKLOG_DATAGRAMS)

    def test_the_backlog_matches_enet_stall_gd(self) -> None:
        """BACKLOG_POSES in enet_stall.gd is ENET_RECEIVES_PER_SERVICE (enet_transport.gd) + a margin."""
        transport = (ROOT / "net" / "transport" / "enet_transport.gd").read_text(encoding="utf-8")
        stall = (ROOT / "tests" / "integration" / "net" / "enet_stall.gd").read_text(encoding="utf-8")
        per_service = re.search(r"^const ENET_RECEIVES_PER_SERVICE := (\d+)$", transport, re.M)
        margin = re.search(r"^const BACKLOG_POSES := EnetTransport\.ENET_RECEIVES_PER_SERVICE \+ (\d+)$", stall, re.M)
        if per_service is None or margin is None:
            self.fail("ENET_RECEIVES_PER_SERVICE or BACKLOG_POSES changed form; update this test and doctor")
        self.assertEqual(int(per_service[1]) + int(margin[1]), doctor.STALL_BACKLOG_DATAGRAMS)


class CloudTwovoipTest(unittest.TestCase):
    """#345: a cloud session runs verify without the Windows-only TwoVoIP extension, as CI does, left out by a sparse
    checkout rather than deleted (a deletion could be committed). Each case is a real git repository."""

    def check(self, state: str, *, cloud: bool = True, ci: bool = False) -> tuple[int, str]:
        """state: "present" (as cloned), "deleted" (by hand, as CI does), "sparse" (as tools/cloud/setup.sh does) or
        "untracked" (a checkout from before M5)."""
        buffer = io.StringIO()
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)

            def git(*args: str) -> None:
                config = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
                subprocess.run(["git", *config, *args], cwd=root, check=True, capture_output=True)

            git("init", "-q")
            (root / "project.godot").touch()
            for path in doctor.TWOVOIP_FILES if state != "untracked" else ():
                (root / path).parent.mkdir(parents=True, exist_ok=True)
                (root / path).touch()
            git("add", "-A")
            git("commit", "-q", "-m", "x")
            if state == "deleted":
                for path in doctor.TWOVOIP_FILES:
                    (root / path).unlink()
            elif state == "sparse":
                git("sparse-checkout", "set", "--no-cone", "/*", *(f"!/{path}" for path in doctor.TWOVOIP_FILES))
            with (
                mock.patch.object(doctor, "ROOT", root),
                mock.patch.object(doctor, "IS_CLOUD", cloud),
                mock.patch.object(doctor, "IS_CI", ci),
                contextlib.redirect_stdout(buffer),
                contextlib.redirect_stderr(buffer),
            ):
                doc = doctor.Doctor()
                doc.cloud_twovoip()
        return doc.failures, buffer.getvalue()

    def test_a_cloud_session_with_the_extension_fails_with_the_fix(self) -> None:
        failures, out = self.check("present")
        self.assertEqual(failures, 1)
        self.assertIn("addons/twovoip/twovoip.gdextension is in the working tree", out)
        self.assertIn("Run: tools/cloud/setup.sh", out)
        self.assertIn("'!/addons/twovoip/twovoip.gdextension' '!/addons/twovoip/twovoip.gdextension.uid'", out)

    def test_a_deletion_by_hand_fails_too(self) -> None:
        failures, out = self.check("deleted")
        self.assertEqual(failures, 1)
        self.assertIn("deleted, not left out by the sparse checkout", out)

    def test_the_sparse_checkout_is_ok(self) -> None:
        failures, out = self.check("sparse")
        self.assertEqual(failures, 0)
        self.assertIn("ok    TwoVoIP extension left out", out)

    def test_a_checkout_from_before_the_addon_is_ok(self) -> None:
        failures, out = self.check("untracked")
        self.assertEqual(failures, 0)
        self.assertIn("ok    no TwoVoIP extension in this checkout", out)

    def test_a_pc_and_ci_are_not_checked(self) -> None:
        self.assertEqual(self.check("present", cloud=False), (0, ""))
        self.assertEqual(self.check("deleted", ci=True), (0, ""))

    def test_the_paths_are_the_committed_extension(self) -> None:
        """git tracks both even where the sparse checkout leaves them out of the working tree."""
        tracked = subprocess.run(
            ["git", "ls-files", "--", *doctor.TWOVOIP_FILES], cwd=ROOT, capture_output=True, text=True, check=True
        )
        self.assertEqual(tracked.stdout.split(), list(doctor.TWOVOIP_FILES))


class ClaudeMdExcludeTest(unittest.TestCase):
    """#385: the full doctor adds the worktrees' root CLAUDE.md exclude to the main checkout's settings.local.json,
    merged into what is there; the quick one only warns. Every case writes a temporary folder, never the real file."""

    PATTERN = "**/.claude/worktrees/*/CLAUDE.md"

    def setUp(self) -> None:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name).resolve()
        self.settings = self.root / ".claude" / "settings.local.json"

    def write(self, text: str, encoding: str = "utf-8") -> None:
        self.settings.parent.mkdir(parents=True, exist_ok=True)
        self.settings.write_bytes(text.encode(encoding))

    def test_the_pattern_is_the_one_probed(self) -> None:
        self.assertEqual(doctor.CLAUDE_MD_EXCLUDE, self.PATTERN)

    def test_a_missing_file_is_created_with_the_exclude_only(self) -> None:
        self.assertEqual(doctor.add_claude_md_exclude(self.settings), doctor.ADDED)
        expected = '{\n  "claudeMdExcludes": [\n    "' + self.PATTERN + '"\n  ]\n}\n'
        self.assertEqual(self.settings.read_bytes().decode("utf-8"), expected)
        self.assertEqual([p.name for p in self.settings.parent.iterdir()], ["settings.local.json"])

    def test_it_merges_into_what_the_file_holds(self) -> None:
        self.write(
            json.dumps(
                {
                    "permissions": {"allow": ["Bash(git fetch *)", "PowerShell(tools\\run.cmd doctor --quick)"]},
                    "claudeMdExcludes": ["**/vendor/CLAUDE.md"],
                    "env": {"GODOT_BIN": "C:\\Godot\\Gödot.exe"},
                },
                indent=2,
            )
        )
        self.assertEqual(doctor.add_claude_md_exclude(self.settings), doctor.ADDED)
        data = json.loads(self.settings.read_text(encoding="utf-8"))
        self.assertEqual(list(data), ["permissions", "claudeMdExcludes", "env"])
        self.assertEqual(data["claudeMdExcludes"], ["**/vendor/CLAUDE.md", self.PATTERN])
        self.assertEqual(data["permissions"]["allow"][1], "PowerShell(tools\\run.cmd doctor --quick)")
        self.assertEqual(data["env"]["GODOT_BIN"], "C:\\Godot\\Gödot.exe")
        self.assertNotIn(b"\r\n", self.settings.read_bytes())

    def test_a_present_exclude_leaves_the_file_untouched(self) -> None:
        text = '{"claudeMdExcludes": ["' + self.PATTERN + '"], "model": "opus"}'
        self.write(text)
        for write in (True, False):
            self.assertEqual(doctor.add_claude_md_exclude(self.settings, write=write), doctor.PRESENT)
        self.assertEqual(self.settings.read_bytes().decode("utf-8"), text)

    def test_a_byte_order_mark_is_read(self) -> None:
        self.write('{"model": "opus"}', encoding="utf-8-sig")
        self.assertEqual(doctor.add_claude_md_exclude(self.settings), doctor.ADDED)
        self.assertFalse(self.settings.read_bytes().startswith(b"\xef\xbb\xbf"))
        self.assertEqual(json.loads(self.settings.read_text(encoding="utf-8"))["model"], "opus")

    def test_without_write_nothing_is_written(self) -> None:
        self.assertEqual(doctor.add_claude_md_exclude(self.settings, write=False), doctor.MISSING)
        self.assertFalse(self.settings.parent.exists())
        self.write('{"model": "opus"}')
        self.assertEqual(doctor.add_claude_md_exclude(self.settings, write=False), doctor.MISSING)
        self.assertEqual(self.settings.read_text(encoding="utf-8"), '{"model": "opus"}')

    def test_a_file_it_cannot_merge_into_is_left_alone(self) -> None:
        for text in ('{"model": ', "[1, 2]", '{"claudeMdExcludes": "**/x/CLAUDE.md"}'):
            with self.subTest(text=text):
                self.write(text)
                with self.assertRaises(ValueError):
                    doctor.add_claude_md_exclude(self.settings)
                self.assertEqual(self.settings.read_text(encoding="utf-8"), text)

    def run_check(
        self, quick: bool, *, windows: bool = True, ci: bool = False, root: Path | None = None
    ) -> tuple[int, str]:
        """claude_md_exclude() with self.root as the main checkout, or from `root` (a real worktree of it)."""
        buffer = io.StringIO()
        main = root or self.root
        with (
            mock.patch.object(doctor, "ROOT", main),
            mock.patch.object(doctor, "IS_WINDOWS", windows),
            mock.patch.object(doctor, "IS_CI", ci),
            mock.patch.object(doctor.metrics, "main_checkout", return_value=self.root) if root is None
            else contextlib.nullcontext(),
            contextlib.redirect_stdout(buffer),
            contextlib.redirect_stderr(buffer),
        ):  # fmt: skip
            doc = doctor.Doctor()
            doc.claude_md_exclude(quick)
        return doc.failures, buffer.getvalue()

    def test_the_full_doctor_adds_it_and_says_where(self) -> None:
        failures, out = self.run_check(quick=False)
        self.assertEqual(failures, 0)
        self.assertIn(f"claudeMdExcludes: added {self.PATTERN} to {self.settings}", out)
        self.assertEqual(json.loads(self.settings.read_text(encoding="utf-8")), {"claudeMdExcludes": [self.PATTERN]})
        failures, out = self.run_check(quick=False)
        self.assertEqual(failures, 0)
        self.assertIn(f"claudeMdExcludes has {self.PATTERN} ({self.settings})", out)

    def test_the_quick_doctor_only_warns(self) -> None:
        failures, out = self.run_check(quick=True)
        self.assertEqual(failures, 0)
        self.assertIn(f"lacks claudeMdExcludes {self.PATTERN}", out)
        self.assertIn("run the full doctor once to add it: tools\\run.cmd doctor", out)
        self.assertFalse(self.settings.exists())

    def test_a_broken_file_fails_the_full_doctor_and_warns_the_quick_one(self) -> None:
        self.write('{"model": ')
        failures, out = self.run_check(quick=False)
        self.assertEqual(failures, 1)
        self.assertIn(f"cannot add claudeMdExcludes to {self.settings}", out)
        failures, out = self.run_check(quick=True)
        self.assertEqual(failures, 0)
        self.assertIn(f"cannot add claudeMdExcludes to {self.settings}", out)
        self.assertEqual(self.settings.read_text(encoding="utf-8"), '{"model": ')

    def test_ci_and_other_systems_are_left_alone(self) -> None:
        """Off Windows a session started in a worktree reads the main checkout's settings.local.json (Claude Code's
        settings docs), so there the exclude would take that session's only root CLAUDE.md."""
        for kwargs in ({"ci": True}, {"windows": False}):
            with self.subTest(**kwargs):
                failures, out = self.run_check(quick=False, **kwargs)
                self.assertEqual(failures, 0)
                self.assertIn("skip  claudeMdExcludes", out)
                self.assertFalse(self.settings.exists())

    def test_from_a_worktree_it_writes_the_main_checkouts_file(self) -> None:
        git = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]
        subprocess.run([*git, "init", "-q"], cwd=self.root, check=True)
        subprocess.run([*git, "commit", "-q", "--allow-empty", "-m", "x"], cwd=self.root, check=True)
        worktree = self.root / ".claude" / "worktrees" / "7"
        subprocess.run([*git, "worktree", "add", "-q", str(worktree)], cwd=self.root, check=True)
        failures, _out = self.run_check(quick=False, root=worktree)
        self.assertEqual(failures, 0)
        self.assertEqual(json.loads(self.settings.read_text(encoding="utf-8")), {"claudeMdExcludes": [self.PATTERN]})
        self.assertFalse((worktree / ".claude" / "settings.local.json").exists())

    def test_a_worktree_named_as_the_main_checkout_is_never_written(self) -> None:
        """main_checkout falls back to the checkout itself when git fails: from a worktree that is the worktree's own
        settings.local.json, the one a session started there reads on Windows."""
        worktree = self.root / ".claude" / "Worktrees" / "7"
        own = worktree / ".claude" / "settings.local.json"
        with mock.patch.object(doctor.metrics, "main_checkout", return_value=worktree):
            failures, out = self.run_check(quick=False, root=worktree)
            self.assertEqual(failures, 1)
            self.assertIn(f"cannot find the main checkout from {worktree}", out)
            failures, out = self.run_check(quick=True, root=worktree)
            self.assertEqual(failures, 0)
            self.assertIn("Run the full doctor from the main checkout: tools\\run.cmd doctor", out)
        self.assertFalse(own.exists())
        self.assertFalse(self.settings.exists())

    def test_in_worktrees_folder(self) -> None:
        self.assertTrue(doctor.in_worktrees_folder(Path("D:/prime-game/.claude/worktrees/385")))
        self.assertFalse(doctor.in_worktrees_folder(Path("D:/prime-game")))
        self.assertFalse(doctor.in_worktrees_folder(Path("D:/prime-game/worktrees/.claude")))
