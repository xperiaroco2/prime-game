"""ui-sync (#288, #520): pinning the UI pack from a fixture git repository built here (a JSON, two SVGs, a PNG, a
font outside the assets list, tags), the imported copy of the assets with each SVG's import scale, the offline verify
of a pinned copy and each problem it names, atomicity on a bad pack, and the committed copy."""

from __future__ import annotations

import contextlib
import hashlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

from runner import cli, ui_sync
from runner.common import ROOT, Failure, force_rmtree

SVG = b'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="#ffffff" d="M0 0h1"/></svg>\n'
# A CRLF in a source blob must reach the copy byte for byte: no checkout, so no line-ending conversion.
SVG_CRLF = b'<svg xmlns="http://www.w3.org/2000/svg">\r\n<circle r="1"/>\r\n</svg>\r\n'
PNG = b"\x89PNG\r\n\x1a\n" + bytes(range(64))
TTF = b"\x00\x01\x00\x00" + bytes(range(32))


def pack_json(version: str, schema: int = 1, svg_sha: str | None = None) -> bytes:
    pack = {
        "format": "prime-game-ui/pack",
        "schema": schema,
        "version": version,
        "variations": {},
        "assets": [
            {"path": "cards/a.png", "kind": "card-art", "sha256": hashlib.sha256(PNG).hexdigest()},
            {
                "path": "icons/a.svg",
                "kind": "icon",
                "sha256": svg_sha or hashlib.sha256(SVG).hexdigest(),
                "svg_scale": 1.17,
            },
            {"path": "icons/room/b.svg", "kind": "icon", "sha256": hashlib.sha256(SVG_CRLF).hexdigest()},
        ],
    }
    return (json.dumps(pack, indent=2) + "\n").encode("utf-8")


def git(cwd: Path, *args: str) -> str:
    res = subprocess.run(["git", *args], cwd=cwd, capture_output=True, check=True)
    return res.stdout.decode("utf-8").strip()


class Fixture:
    """A prime-game-ui stand-in: tag ui-9.9.9 (good), ui-9.9.10 (adds a file, drops one), ui-9.9.11 (schema 2) and
    ui-9.9.12 (its version says 9.9.0); and a game root to sync into."""

    def __init__(self) -> None:
        self.base = Path(tempfile.mkdtemp(prefix="ui-sync-test-"))
        self.repo = self.base / "prime-game-ui"
        self.root = self.base / "game"
        self.root.mkdir()
        self.repo.mkdir()
        git(self.repo, "init", "--quiet")
        git(self.repo, "config", "core.autocrlf", "false")
        git(self.repo, "config", "user.email", "test@example.com")
        git(self.repo, "config", "user.name", "test")
        self.commits: dict[str, str] = {}
        files = {
            "dist/pack/toy.pack.json": pack_json("9.9.9"),
            "dist/pack/icons/a.svg": SVG,
            "dist/pack/icons/room/b.svg": SVG_CRLF,
            "dist/pack/icons/LICENCES.json": b'{"a.svg": "own work"}\n',
            "dist/pack/cards/a.png": PNG,
            "dist/pack/fonts/x.ttf": TTF,
            "README.md": b"not in the pack\n",
        }
        self.commit("ui-9.9.9", files)
        del files["dist/pack/icons/LICENCES.json"]
        files["dist/pack/icons/c.svg"] = SVG
        files["dist/pack/toy.pack.json"] = pack_json("9.9.10")
        self.commit("ui-9.9.10", files)
        files["dist/pack/toy.pack.json"] = pack_json("9.9.11", schema=2)
        self.commit("ui-9.9.11", files)
        files["dist/pack/toy.pack.json"] = pack_json("9.9.0")
        self.commit("ui-9.9.12", files)

    def commit(self, tag: str, files: dict[str, bytes]) -> None:
        for path in self.repo.rglob("*"):
            if path.is_file() and ".git" not in path.relative_to(self.repo).parts:
                path.unlink()
        for name, data in files.items():
            target = self.repo / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "--quiet", "-m", tag)
        git(self.repo, "tag", "-a", tag, "-m", tag)
        self.commits[tag] = git(self.repo, "rev-parse", "HEAD")

    def close(self) -> None:
        force_rmtree(self.base)

    def sync(self, tag: str) -> dict:
        with contextlib.redirect_stdout(io.StringIO()):
            return ui_sync.sync(tag, str(self.repo), root=self.root)

    def main(self, *args: str, **kwargs: object) -> tuple[int, str]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            rc = ui_sync.main(*args, root=self.root, **kwargs)  # type: ignore[arg-type]
        return rc, out.getvalue()

    @property
    def dest(self) -> Path:
        return self.root / ui_sync.DEST

    @property
    def lock_path(self) -> Path:
        return self.root / ui_sync.LOCK

    @property
    def imported(self) -> Path:
        return self.root / ui_sync.IMPORTED

    def snapshot(self) -> dict[str, bytes]:
        paths = [p for p in self.dest.rglob("*") if p.is_file()] + [self.lock_path]
        paths += [p for p in self.imported.rglob("*") if p.is_file()]
        return {p.relative_to(self.root).as_posix(): p.read_bytes() for p in paths}


class SyncTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.fx = Fixture()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.fx.close()

    def setUp(self) -> None:
        for path in (self.fx.dest, self.fx.lock_path, self.fx.imported):
            if path.is_dir():
                force_rmtree(path)
            elif path.exists():
                path.unlink()

    def test_sync_lands_the_text_files_byte_for_byte_and_defers_binaries(self) -> None:
        lock = self.fx.sync("ui-9.9.9")
        self.assertEqual((self.fx.dest / "icons" / "a.svg").read_bytes(), SVG)
        self.assertEqual((self.fx.dest / "icons" / "room" / "b.svg").read_bytes(), SVG_CRLF)
        self.assertEqual((self.fx.dest / "toy.pack.json").read_bytes(), pack_json("9.9.9"))
        self.assertFalse((self.fx.dest / "cards" / "a.png").exists())
        self.assertEqual((self.fx.dest / ".gdignore").read_bytes(), b"")
        self.assertEqual(lock["repo"], "xperiaroco2/prime-game-ui")
        self.assertEqual(lock["tag"], "ui-9.9.9")
        self.assertEqual(lock["commit"], self.fx.commits["ui-9.9.9"])
        self.assertEqual(
            sorted(lock["files"]), ["icons/LICENCES.json", "icons/a.svg", "icons/room/b.svg", "toy.pack.json"]
        )
        self.assertEqual(lock["files"]["icons/a.svg"], hashlib.sha256(SVG).hexdigest())
        self.assertFalse((self.fx.dest / "fonts" / "x.ttf").exists())
        self.assertEqual(lock["deferred"], {"fonts/x.ttf": hashlib.sha256(TTF).hexdigest()})
        self.assertEqual(sorted(lock["imported"]), ["cards/a.png", "icons/a.svg", "icons/room/b.svg"])
        self.assertEqual(lock["imported"]["cards/a.png"], hashlib.sha256(PNG).hexdigest())
        self.assertEqual((self.fx.imported / "cards" / "a.png").read_bytes(), PNG)
        self.assertEqual((self.fx.imported / "icons" / "room" / "b.svg").read_bytes(), SVG_CRLF)
        self.assertFalse((self.fx.imported / "fonts").exists())
        self.assertFalse((self.fx.imported / ".gdignore").exists())
        # Each SVG gets the pack's import scale (1 when it gives none); a PNG's .import is Godot's to write.
        a_import = (self.fx.imported / "icons" / "a.svg.import").read_text(encoding="utf-8")
        self.assertIn("svg/scale=1.17\n", a_import)
        b_import = (self.fx.imported / "icons" / "room" / "b.svg.import").read_text(encoding="utf-8")
        self.assertIn("svg/scale=1.0\n", b_import)
        self.assertFalse((self.fx.imported / "cards" / "a.png.import").exists())
        on_disk = json.loads(self.fx.lock_path.read_text(encoding="utf-8"))
        self.assertEqual(on_disk, lock)
        self.assertNotIn(b"\r", self.fx.lock_path.read_bytes())
        self.assertEqual(ui_sync.verify(self.fx.root), [])
        self.assertFalse((self.fx.root / "tools" / "out" / "ui-sync" / "clone").exists())

    def test_sync_twice_is_identical_and_a_new_tag_removes_stale_files(self) -> None:
        self.fx.sync("ui-9.9.9")
        first = self.fx.snapshot()
        self.fx.sync("ui-9.9.9")
        self.assertEqual(self.fx.snapshot(), first)
        stale = self.fx.imported / "icons" / "gone.svg"
        stale.write_bytes(SVG)
        Path(str(stale) + ".import").write_bytes(b"[remap]\n")
        self.fx.sync("ui-9.9.10")
        self.assertFalse(stale.exists())
        self.assertFalse(Path(str(stale) + ".import").exists())
        self.assertFalse((self.fx.dest / "icons" / "LICENCES.json").exists())
        self.assertTrue((self.fx.dest / "icons" / "c.svg").exists())
        self.assertEqual(ui_sync.verify(self.fx.root), [])

    def test_a_bad_pack_leaves_the_pinned_copy_untouched(self) -> None:
        self.fx.sync("ui-9.9.9")
        before = self.fx.snapshot()
        with self.assertRaisesRegex(Failure, "schema 2 is unknown"):
            self.fx.sync("ui-9.9.11")
        self.assertEqual(self.fx.snapshot(), before)
        with self.assertRaisesRegex(Failure, "version '9.9.0' does not match the tag ui-9.9.12"):
            self.fx.sync("ui-9.9.12")
        self.assertEqual(self.fx.snapshot(), before)

    def test_an_asset_whose_sha_differs_from_the_packs_record_is_refused(self) -> None:
        fetched = ui_sync.Fetched(
            commit="a" * 40, files={"toy.pack.json": pack_json("9.9.9", svg_sha="0" * 64), "icons/a.svg": SVG}
        )
        with self.assertRaisesRegex(Failure, "icons/a.svg: sha256 .* differs from the pack's assets record"):
            ui_sync.plan("ui-9.9.9", fetched)

    def test_a_resync_keeps_godots_import_file_and_sets_only_the_scale(self) -> None:
        self.fx.sync("ui-9.9.9")
        path = self.fx.imported / "icons" / "a.svg.import"
        godot = (
            '[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\nuid="uid://b1"\n\n[params]\n\n'
            "compress/mode=0\nsvg/scale=2.0\neditor/scale_with_editor_scale=false\n"
        )
        path.write_text(godot, encoding="utf-8")
        self.fx.sync("ui-9.9.9")
        self.assertEqual(path.read_text(encoding="utf-8"), godot.replace("svg/scale=2.0", "svg/scale=1.17"))

    def test_an_asset_the_pack_lists_but_does_not_ship_is_refused(self) -> None:
        fetched = ui_sync.Fetched(commit="a" * 40, files={"toy.pack.json": pack_json("9.9.9"), "icons/a.svg": SVG})
        with self.assertRaisesRegex(Failure, "cards/a.png: in the pack's assets record but not in dist/pack/"):
            ui_sync.plan("ui-9.9.9", fetched)

    def test_the_tag_must_be_ui_semver(self) -> None:
        for tag in ("0.4.0", "ui-0.4", "main", "ui-0.4.0-rc1"):
            with self.subTest(tag=tag), self.assertRaisesRegex(Failure, "is not a UI pack tag"):
                ui_sync.check_tag(tag)
        ui_sync.check_tag("ui-10.20.30")

    def test_a_tag_already_pinned_is_not_fetched_again(self) -> None:
        self.fx.sync("ui-9.9.9")
        calls: list[str] = []

        def offline(tag: str, source: str, work: Path) -> ui_sync.Fetched:
            calls.append(tag)
            raise Failure("network is down")

        rc, out = self.fx.main("ui-9.9.9", fetcher=offline)
        self.assertEqual((rc, calls), (0, []), out)
        self.assertIn("already pinned and intact", out)
        rc, out = self.fx.main(None, fetcher=offline)
        self.assertEqual((rc, calls), (0, []), out)
        rc, out = self.fx.main("ui-9.9.9", check=True, fetcher=offline)
        self.assertEqual((rc, calls), (0, []), out)
        rc, out = self.fx.main("ui-9.9.10", check=True, fetcher=offline)
        self.assertEqual((rc, calls), (1, []), out)
        self.assertIn("the pinned tag is ui-9.9.9, not ui-9.9.10", out)
        before = self.fx.snapshot()
        with self.assertRaisesRegex(Failure, "(?s)could not fetch ui-9.9.9 .*network is down.*ui-sync --check"):
            self.fx.main("ui-9.9.9", force=True, fetcher=offline)
        self.assertEqual(calls, ["ui-9.9.9"])
        self.assertEqual(self.fx.snapshot(), before)

    def test_main_fetches_a_new_tag(self) -> None:
        self.fx.sync("ui-9.9.9")
        rc, out = self.fx.main("ui-9.9.10", source=str(self.fx.repo))
        self.assertEqual(rc, 0, out)
        self.assertEqual(json.loads(self.fx.lock_path.read_text(encoding="utf-8"))["tag"], "ui-9.9.10")

    def test_a_missing_tag_is_a_failure_that_names_the_pinned_copy(self) -> None:
        with self.assertRaisesRegex(Failure, "(?s)could not fetch ui-1.2.3 .*pinned copy is untouched"):
            self.fx.sync("ui-1.2.3")


class VerifyTest(unittest.TestCase):
    """Each problem verify() names, on a good pinned copy mutated one way at a time."""

    @classmethod
    def setUpClass(cls) -> None:
        cls.fx = Fixture()
        cls.fx.sync("ui-9.9.9")
        cls.good = cls.fx.snapshot()

    @classmethod
    def tearDownClass(cls) -> None:
        cls.fx.close()

    def setUp(self) -> None:
        force_rmtree(self.fx.dest)
        force_rmtree(self.fx.imported)
        for rel, data in self.good.items():
            path = self.fx.root / rel
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    def problems(self) -> str:
        return "\n".join(ui_sync.verify(self.fx.root))

    def edit_lock(self, change: dict) -> None:
        lock = json.loads(self.fx.lock_path.read_text(encoding="utf-8"))
        lock.update(change)
        self.fx.lock_path.write_text(json.dumps(lock), encoding="utf-8")

    def edit_pack(self, change: dict) -> None:
        """Change the pack and keep the lock's sha of it right, so only the named problem remains."""
        path = self.fx.dest / "toy.pack.json"
        pack = json.loads(path.read_text(encoding="utf-8"))
        pack.update(change)
        path.write_text(json.dumps(pack), encoding="utf-8")
        lock = json.loads(self.fx.lock_path.read_text(encoding="utf-8"))
        lock["files"]["toy.pack.json"] = hashlib.sha256(path.read_bytes()).hexdigest()
        self.fx.lock_path.write_text(json.dumps(lock), encoding="utf-8")

    def test_the_good_copy_has_no_problem(self) -> None:
        self.assertEqual(self.problems(), "")

    def test_a_changed_byte(self) -> None:
        (self.fx.dest / "icons" / "a.svg").write_bytes(SVG.replace(b"ffffff", b"fffffe"))
        self.assertRegex(self.problems(), r"icons/a.svg: sha256 differs from the lock")

    def test_a_missing_file(self) -> None:
        (self.fx.dest / "icons" / "a.svg").unlink()
        self.assertRegex(self.problems(), r"icons/a.svg: in the lock but missing")

    def test_an_extra_file(self) -> None:
        (self.fx.dest / "icons" / "extra.svg").write_bytes(SVG)
        self.assertRegex(self.problems(), r"icons/extra.svg: under .* but not in the lock")

    def test_no_gdignore(self) -> None:
        (self.fx.dest / ".gdignore").unlink()
        self.assertRegex(self.problems(), r"\.gdignore is missing")

    def test_no_lock(self) -> None:
        self.fx.lock_path.unlink()
        self.assertRegex(self.problems(), r"pack.lock.json is missing")

    def test_the_lock_tag_is_not_the_pack_version(self) -> None:
        self.edit_lock({"tag": "ui-9.9.8"})
        self.assertRegex(self.problems(), r"version '9.9.9' does not match the tag ui-9.9.8")

    def test_an_unknown_schema(self) -> None:
        self.edit_pack({"schema": 2})
        self.assertRegex(self.problems(), r"schema 2 is unknown")

    def test_a_wrong_format(self) -> None:
        self.edit_pack({"format": "something/else"})
        self.assertRegex(self.problems(), r"format is 'something/else'")

    def test_an_asset_record_that_differs_from_the_lock(self) -> None:
        pack = json.loads((self.fx.dest / "toy.pack.json").read_text(encoding="utf-8"))
        pack["assets"][1]["sha256"] = "0" * 64
        self.edit_pack({"assets": pack["assets"]})
        self.assertRegex(self.problems(), r"icons/a.svg: the lock's sha256 differs from the pack's assets record")

    def test_a_text_asset_missing_with_its_lock_line(self) -> None:
        (self.fx.dest / "icons" / "a.svg").unlink()
        lock = json.loads(self.fx.lock_path.read_text(encoding="utf-8"))
        del lock["files"]["icons/a.svg"]
        self.edit_lock({"files": lock["files"]})
        self.assertRegex(self.problems(), r"icons/a.svg: a pack asset missing from the lock")

    def test_an_asset_that_is_not_imported(self) -> None:
        lock = json.loads(self.fx.lock_path.read_text(encoding="utf-8"))
        del lock["imported"]["cards/a.png"]
        self.edit_lock({"imported": lock["imported"]})
        (self.fx.imported / "cards" / "a.png").unlink()
        self.assertRegex(self.problems(), r"cards/a.png: a pack asset missing from the imported copy")

    def test_an_imported_file_missing_changed_or_extra(self) -> None:
        png = self.fx.imported / "cards" / "a.png"
        png.unlink()
        self.assertRegex(self.problems(), r"cards/a.png: in the lock's imported but missing from assets/ui/toy_pack")
        png.write_bytes(PNG + b"x")
        self.assertRegex(self.problems(), r"cards/a.png: sha256 under assets/ui/toy_pack differs from the lock")
        png.write_bytes(PNG)
        (self.fx.imported / "icons" / "extra.svg").write_bytes(SVG)
        self.assertRegex(self.problems(), r"icons/extra.svg: under assets/ui/toy_pack but not in the lock's imported")

    def test_an_lfs_pointer_counts_by_its_oid(self) -> None:
        def pointer(digest: str) -> bytes:
            return f"version https://git-lfs.github.com/spec/v1\noid sha256:{digest}\nsize 72\n".encode("ascii")

        png = self.fx.imported / "cards" / "a.png"
        png.write_bytes(pointer(hashlib.sha256(PNG).hexdigest()))
        self.assertEqual(self.problems(), "")
        png.write_bytes(pointer("0" * 64))
        self.assertRegex(self.problems(), r"cards/a.png: sha256 under assets/ui/toy_pack differs from the lock")

    def test_an_svg_import_without_the_packs_scale(self) -> None:
        path = self.fx.imported / "icons" / "a.svg.import"
        path.write_text(path.read_text(encoding="utf-8").replace("svg/scale=1.17", "svg/scale=1.0"), encoding="utf-8")
        self.assertRegex(self.problems(), r"icons/a.svg: .import svg/scale=1.0, the pack's svg_scale is 1.17")
        path.unlink()
        self.assertRegex(self.problems(), r"icons/a.svg: no .import file under assets/ui/toy_pack")

    def test_a_deferred_file_on_disk(self) -> None:
        (self.fx.dest / "fonts").mkdir()
        (self.fx.dest / "fonts" / "x.ttf").write_bytes(TTF)
        self.assertRegex(self.problems(), r"fonts/x.ttf: deferred \(a binary\) but present")

    def test_unknown_lock_keys_and_a_bad_commit(self) -> None:
        self.edit_lock({"commit": "HEAD", "extra": 1})
        self.assertRegex(self.problems(), r"keys .*expected")
        self.assertRegex(self.problems(), r"commit 'HEAD' is not a 40-hex commit")


class CommittedCopyTest(unittest.TestCase):
    """The pinned copy in the repository matches its lock: a hand edit of client/ui/theme/pack/ fails verify."""

    def test_the_committed_pack_matches_its_lock(self) -> None:
        self.assertEqual(ui_sync.verify(ROOT), [])
        lock = ui_sync.read_lock(ROOT)
        assert lock is not None
        self.assertEqual(lock["tag"], "ui-0.4.0")
        self.assertEqual(lock["deferred"], {}, "#520 imports the card art")
        self.assertIn("cards/delivery-1.png", lock["imported"])
        self.assertIn("icons/room/lab.svg", lock["imported"])

    def test_the_command_is_registered(self) -> None:
        args = cli.build_parser().parse_args(["ui-sync", "ui-0.4.0", "--force", "--source", "D:/x"])
        self.assertEqual((args.command, args.tag, args.force, args.source, args.check), ("ui-sync", "ui-0.4.0", True, "D:/x", False))
        args = cli.build_parser().parse_args(["ui-sync"])
        self.assertIsNone(args.tag)


if __name__ == "__main__":
    unittest.main()
