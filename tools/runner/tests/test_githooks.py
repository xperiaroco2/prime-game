"""The pre-push hook (.claude/githooks/pre-push), run by real pushes to a local bare remote in a temp folder."""

import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner.common import ROOT
from runner.publish import MARKER


def _rmtree(path: str) -> None:
    """Git makes its object files read-only; Windows refuses to delete those without a chmod. A path that vanishes
    meanwhile (a git process of the test still tidying its object folders, #440) counts as deleted; every other error
    stays."""

    def retry(func, target, _exc):  # type: ignore[no-untyped-def]
        try:
            os.chmod(target, stat.S_IWRITE)
            func(target)
        except FileNotFoundError:
            if os.path.lexists(target):
                raise

    if sys.version_info >= (3, 12):
        shutil.rmtree(path, onexc=retry)
    else:
        shutil.rmtree(path, onerror=retry)


class PrePushTest(unittest.TestCase):
    tmp: Path
    work: Path

    @classmethod
    def setUpClass(cls) -> None:
        cls.tmp = Path(tempfile.mkdtemp(prefix="prepush-"))
        cls.addClassCleanup(_rmtree, str(cls.tmp))
        hooks = cls.tmp / "hooks"
        hooks.mkdir()
        shutil.copy(ROOT / ".claude" / "githooks" / "pre-push", hooks / "pre-push")
        (hooks / "pre-push").chmod(0o755)
        cls.work = cls.tmp / "work"
        cls.git_in(cls.tmp, "init", "-q", "--bare", "-b", "main", "remote.git")
        cls.git_in(cls.tmp, "init", "-q", "-b", "main", "work")
        for key, value in (("user.name", "t"), ("user.email", "t@example.com"), ("commit.gpgsign", "false")):
            cls.git_in(cls.work, "config", key, value)
        cls.git_in(cls.work, "remote", "add", "origin", str(cls.tmp / "remote.git"))
        cls.git_in(cls.work, "commit", "-q", "--allow-empty", "-m", "c1")
        cls.git_in(cls.work, "push", "-q", "origin", "main")  # before the hook: main exists on the remote
        cls.git_in(cls.work, "config", "core.hooksPath", str(hooks))

    @staticmethod
    def git_in(where: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        res = subprocess.run(
            ["git", *args],
            cwd=where,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env={**os.environ, **(env or {})},
            timeout=120,
        )
        return res

    def git(self, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
        return self.git_in(self.work, *args, env=env)

    def commit(self, message: str) -> None:
        self.assertEqual(self.git("commit", "-q", "--allow-empty", "-m", message).returncode, 0)

    def assert_pushed(self, res: subprocess.CompletedProcess[str]) -> None:
        self.assertEqual(res.returncode, 0, res.stderr)

    def assert_blocked(self, res: subprocess.CompletedProcess[str], what: str) -> None:
        self.assertNotEqual(res.returncode, 0, res.stderr)
        self.assertIn(f"pre-push: blocked {what}", res.stderr)

    def remote_oid(self, branch: str) -> str:
        return self.git_in(self.tmp / "remote.git", "rev-parse", f"refs/heads/{branch}").stdout.strip()

    def test_rules(self) -> None:
        # A new task branch and a fast-forward push go through, and the hook runs git lfs pre-push.
        self.git("switch", "-q", "-c", "tooling/1-probe")
        self.commit("c2")
        res = self.git("push", "-u", "origin", "tooling/1-probe", env={"GIT_TRACE": "1"})
        self.assert_pushed(res)
        self.assertRegex(res.stderr, r"exec: git-lfs pre-push origin")
        self.commit("c3")
        self.assert_pushed(self.git("push", "origin", "tooling/1-probe"))

        main_before = self.remote_oid("main")
        self.assert_blocked(self.git("push", "origin", "tooling/1-probe:main"), "a push to main")
        self.assert_blocked(self.git("push", "--dry-run", "origin", "HEAD:refs/heads/main"), "a push to main")
        self.assert_blocked(self.git("push", "origin", "--delete", "tooling/1-probe"), "the deletion")
        self.assertEqual(self.remote_oid("main"), main_before)

        # A rewritten task branch: a force push by hand is blocked, publish's marked lease push goes through.
        self.assertEqual(self.git("commit", "-q", "--amend", "--allow-empty", "-m", "c3 amended").returncode, 0)
        self.assert_blocked(self.git("push", "--force", "origin", "tooling/1-probe"), "a force push")
        self.assert_blocked(self.git("push", "--force-with-lease", "origin", "tooling/1-probe"), "a force push")
        lease = self.git("push", "--force-with-lease", "origin", "tooling/1-probe", env=MARKER)
        self.assert_pushed(lease)
        self.assertEqual(self.remote_oid("tooling/1-probe"), self.git("rev-parse", "HEAD").stdout.strip())

        # The marker covers only the current task branch.
        self.git("switch", "-q", "-c", "tooling/2-other", "main")
        self.commit("d1")
        self.assert_pushed(self.git("push", "origin", "tooling/2-other"))
        self.git("switch", "-q", "tooling/1-probe")
        other = self.git("push", "--force", "origin", "tooling/1-probe:tooling/2-other", env=MARKER)
        self.assert_blocked(other, "a force push")
        self.git("switch", "-q", "-c", "feature-x", "main")
        self.commit("e1")
        self.assert_pushed(self.git("push", "origin", "feature-x"))
        self.assertEqual(self.git("commit", "-q", "--amend", "--allow-empty", "-m", "e1 amended").returncode, 0)
        not_task = self.git("push", "--force-with-lease", "origin", "feature-x", env=MARKER)
        self.assert_blocked(not_task, "a force push")
        self.assertTrue(re.search(r"tools.run\.cmd publish", not_task.stderr))


class RmtreeTest(unittest.TestCase):
    """_rmtree, the cleanup of every runner test that makes git repos in a temp folder (#440)."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="rmtree-"))
        self.addCleanup(_rmtree, str(self.tmp))  # the read-only files a test leaves need the chmod retry
        self.objects = self.tmp / "remote.git" / "objects"
        for name in ("a6", "b7"):
            (self.objects / name).mkdir(parents=True)
            (self.objects / name / "obj").write_text("x\n", encoding="utf-8")
            (self.objects / name / "obj").chmod(stat.S_IREAD)  # git's object files are read-only

    def test_a_folder_that_vanishes_mid_delete_counts_as_deleted(self) -> None:
        # The first delete fails (a read-only file on Windows), and before the retry another git process (a gc of the
        # test's remote) removes the object folders: the one being deleted and any the walk has not reached yet.
        unlink = os.unlink
        raced: list[str] = []

        def racing_unlink(target, *args, **kwargs):  # type: ignore[no-untyped-def]
            if raced:
                return unlink(target, *args, **kwargs)
            for folder in sorted(self.objects.iterdir()):
                (folder / "obj").chmod(stat.S_IWRITE)
                unlink(folder / "obj")
                folder.rmdir()
                raced.append(folder.name)
            raise PermissionError(13, "Access is denied", str(target))

        with mock.patch.object(os, "unlink", racing_unlink):
            _rmtree(str(self.tmp / "remote.git"))
        self.assertEqual(raced, ["a6", "b7"])
        self.assertFalse((self.tmp / "remote.git").exists())

    def test_every_other_error_stays_loud(self) -> None:
        # A file that stays: a refused delete, and a "not found" for a path that is still there.
        with self.subTest(error="PermissionError"):
            with mock.patch.object(os, "unlink", side_effect=PermissionError(13, "Access is denied")):
                with self.assertRaises(OSError):
                    _rmtree(str(self.tmp / "remote.git"))
            self.assertTrue((self.objects / "a6" / "obj").exists())
        with self.subTest(error="FileNotFoundError"):
            # The walk's own delete is refused, so the retry runs; its delete then says "not found" for a file that
            # is still there. Python 3.13+ rmtree ignores a "not found" in its walk, so only the retry reaches it.
            calls: list[str] = []

            def refused_then_not_found(target, *args, **kwargs):  # type: ignore[no-untyped-def]
                calls.append(str(target))
                if len(calls) == 1:
                    raise PermissionError(13, "Access is denied", str(target))
                raise FileNotFoundError(2, "No such file or directory", str(target))

            with mock.patch.object(os, "unlink", refused_then_not_found):
                with self.assertRaises(FileNotFoundError):
                    _rmtree(str(self.tmp / "remote.git"))
            self.assertEqual(len(calls), 2, calls)  # the walk's delete and the retry's, then the error stops it
            self.assertTrue((self.objects / "a6" / "obj").exists())


if __name__ == "__main__":
    unittest.main()
