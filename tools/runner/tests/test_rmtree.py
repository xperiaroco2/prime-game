"""common.force_rmtree: the vanish-tolerant delete of a folder git made, used by mutants and the runner tests (#440,
#453)."""

import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import common
from runner.common import force_rmtree


class RmtreeTest(unittest.TestCase):
    """force_rmtree, the cleanup of mutants' scratch worktrees and of every runner test that makes git repos in a temp
    folder (#440)."""

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="rmtree-"))
        self.addCleanup(force_rmtree, str(self.tmp))  # the read-only files a test leaves need the chmod retry
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
            force_rmtree(str(self.tmp / "remote.git"))
        self.assertEqual(raced, ["a6", "b7"])
        self.assertFalse((self.tmp / "remote.git").exists())

    def test_every_other_error_stays_loud(self) -> None:
        # A file that stays: a refused delete, and a "not found" for a path that is still there.
        with self.subTest(error="PermissionError"):
            with mock.patch.object(os, "unlink", side_effect=PermissionError(13, "Access is denied")):
                with self.assertRaises(OSError):
                    force_rmtree(str(self.tmp / "remote.git"))
            self.assertTrue((self.objects / "a6" / "obj").exists())
        # The handler itself, called as rmtree would: rmtree's own walk handles some errors differently per Python
        # version and OS (3.13+ ignores a "not found" from the walk, and on Linux a walk step's error reaches the
        # handler again for the folder), so only a direct call pins these down.
        obj = str(self.objects / "a6" / "obj")
        refused = PermissionError(13, "Access is denied", obj)
        with self.subTest(error="the retry's delete is refused too"):
            with mock.patch.object(os, "unlink", side_effect=PermissionError(13, "Access is denied", obj)):
                with self.assertRaises(PermissionError):
                    common._delete_again(os.unlink, obj, refused)
            mode = os.stat(obj).st_mode
            self.assertTrue(mode & stat.S_IREAD and mode & stat.S_IWRITE, oct(mode))  # the chmod only adds write
        with self.subTest(error="not found for a path that is still there"):
            with mock.patch.object(os, "unlink", side_effect=FileNotFoundError(2, "No such file or directory", obj)):
                with self.assertRaises(FileNotFoundError):
                    common._delete_again(os.unlink, obj, refused)
            self.assertTrue(os.path.exists(obj))
        with self.subTest(error="a walk step, not a delete"):
            folder = str(self.objects / "b7")
            before = os.stat(folder).st_mode
            listing = PermissionError(13, "Permission denied", folder)
            with self.assertRaises(PermissionError) as raised:
                common._delete_again(os.scandir, folder, (PermissionError, listing, None))  # onerror's sys.exc_info()
            self.assertIs(raised.exception, listing)
            self.assertEqual(os.stat(folder).st_mode, before)  # no chmod of a folder rmtree could not walk


if __name__ == "__main__":
    unittest.main()
