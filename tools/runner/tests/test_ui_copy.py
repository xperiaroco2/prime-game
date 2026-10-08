"""ui-copy (#208): the copy deck at a tag of a local checkout (a throwaway git repository), its lock, the key count and
the decks and tags it refuses; and the committed deck against its lock."""

import contextlib
import hashlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from runner import common, ui_copy
from runner.common import Failure

DECK = (
    "keys,en,uk,?plural,?context\n"
    "lang.uk,Українська,Українська,,\n"
    'menu.join,"Join, now",Приєднатися,,\n'
    "unit.knives,{count} knife,{count} ніж,unit.knives,\n"
    ",{count} knives,{count} ножі,,\n"
    ",,{count} ножів,,\n"
)


def git(where: Path, *args: str) -> str:
    done = subprocess.run(["git", "-C", str(where), *args], capture_output=True, text=True, check=True)
    return done.stdout.strip()


class UiCopyTest(unittest.TestCase):
    def setUp(self) -> None:
        self._dir = tempfile.TemporaryDirectory()
        self.addCleanup(self._dir.cleanup)
        base = Path(self._dir.name)
        self.ui = base / "ui"
        self.game = base / "game"
        (self.ui / "copy").mkdir(parents=True)
        git(self.ui, "init", "-q")
        git(self.ui, "config", "user.email", "test@example.com")
        git(self.ui, "config", "user.name", "Test")
        git(self.ui, "config", "core.autocrlf", "false")

    def commit_deck(self, data: bytes, tag: str) -> str:
        (self.ui / "copy" / "strings.csv").write_bytes(data)
        git(self.ui, "add", "-A")
        git(self.ui, "commit", "-q", "-m", "deck")
        git(self.ui, "tag", tag)
        return git(self.ui, "rev-parse", "HEAD")

    def run_main(self, tag: str) -> str:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            self.assertEqual(ui_copy.main(tag, source=self.ui, root=self.game), 0)
        return out.getvalue()

    def test_copies_the_deck_at_the_tag_byte_for_byte_with_its_lock(self) -> None:
        data = DECK.encode("utf-8")
        commit = self.commit_deck(data, "ui-1.2.3")
        # A later commit does not reach a copy of the tag.
        self.commit_deck(data + "menu.quit,Quit,Вийти,,\n".encode("utf-8"), "ui-1.2.4")
        out = self.run_main("ui-1.2.3")
        self.assertIn("3 keys at ui-1.2.3", out)
        folder = self.game / ui_copy.FOLDER
        self.assertEqual((folder / ui_copy.DECK).read_bytes(), data)
        lock = json.loads((folder / ui_copy.LOCK).read_text(encoding="utf-8"))
        self.assertEqual(
            lock,
            {
                "repo": ui_copy.REPO,
                "tag": "ui-1.2.3",
                "commit": commit,
                "files": {"strings.csv": hashlib.sha256(data).hexdigest()},
            },
        )
        self.assertNotIn(b"\r", (folder / ui_copy.LOCK).read_bytes())

    def test_refuses_a_tag_that_is_not_a_ui_release(self) -> None:
        self.commit_deck(DECK.encode("utf-8"), "v1")
        for tag in ("v1", "ui-1.2", "ui-1.2.3-rc"):
            with self.assertRaises(Failure, msg=tag):
                ui_copy.main(tag, source=self.ui, root=self.game)
        self.assertFalse((self.game / ui_copy.FOLDER).exists())

    def test_refuses_a_missing_tag_and_writes_nothing(self) -> None:
        self.commit_deck(DECK.encode("utf-8"), "ui-1.0.0")
        with self.assertRaisesRegex(Failure, "no tag ui-9.9.9"):
            ui_copy.main("ui-9.9.9", source=self.ui, root=self.game)
        self.assertFalse((self.game / ui_copy.FOLDER).exists())

    def test_refuses_a_deck_the_import_cannot_take(self) -> None:
        bad = {
            "a header": DECK.replace("?context", "notes"),
            "CR line ends": DECK.replace("\n", "\r\n"),
            "a byte-order mark": "﻿" + DECK,
        }
        for number, (what, text) in enumerate(bad.items()):
            self.commit_deck(text.encode("utf-8"), f"ui-0.0.{number}")
            with self.assertRaises(Failure, msg=what):
                ui_copy.main(f"ui-0.0.{number}", source=self.ui, root=self.game)
        self.commit_deck(b"keys,en,uk,?plural,?context\n\xff\n", "ui-0.1.0")
        with self.assertRaisesRegex(Failure, "not UTF-8"):
            ui_copy.main("ui-0.1.0", source=self.ui, root=self.game)
        self.assertFalse((self.game / ui_copy.FOLDER).exists())


class CommittedDeckTest(unittest.TestCase):
    def test_the_committed_deck_matches_its_lock(self) -> None:
        folder = common.ROOT / ui_copy.FOLDER
        lock = json.loads((folder / ui_copy.LOCK).read_text(encoding="utf-8"))
        data = (folder / ui_copy.DECK).read_bytes()
        self.assertEqual(lock["repo"], ui_copy.REPO)
        self.assertRegex(lock["tag"], ui_copy.TAG_RE)
        self.assertRegex(lock["commit"], r"^[0-9a-f]{40}$")
        self.assertEqual(
            lock["files"], {ui_copy.DECK: hashlib.sha256(data).hexdigest()}, "run: tools/run.sh ui-copy <tag>"
        )
        self.assertGreater(ui_copy.key_count(data), 0)


if __name__ == "__main__":
    unittest.main()
