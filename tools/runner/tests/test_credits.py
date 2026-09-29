"""Credits: entry parsing, globs, the generated CREDITS.md and the LFS coverage check (in a real git repo)."""

import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path

from runner import credits

ENTRY = """# Crate Pack

- **Files:** `levels/props/crate/**`, `levels/crate.glb`
- **Author:** Someone
- **Source:** https://example.com/crates
- **License:** CC0 1.0

## Notes
Recolored.
"""


def write(root: Path, rel: str, text: str) -> None:
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))


class ParseTest(unittest.TestCase):
    def test_valid_entry(self) -> None:
        entry, errors = credits.parse("docs/credits/crates.md", ENTRY)
        self.assertEqual(errors, [])
        assert entry is not None
        self.assertEqual(entry.title, "Crate Pack")
        self.assertEqual(entry.globs, ["levels/props/crate/**", "levels/crate.glb"])
        self.assertEqual(entry.fields["License"], "CC0 1.0")

    def test_missing_fields_title_and_backticks(self) -> None:
        _, errors = credits.parse("x.md", ENTRY.replace("- **License:** CC0 1.0\n", ""))
        self.assertEqual(errors, ["x.md: missing '- **License:** ...'"])
        _, errors = credits.parse("x.md", ENTRY.replace("# Crate Pack", "Crate Pack"))
        self.assertEqual(errors, ["x.md: must start with '# <asset name>'"])
        _, errors = credits.parse("x.md", ENTRY.replace("`levels/crate.glb`", "levels/crate.glb").replace(
            "`levels/props/crate/**`, ", ""))
        self.assertIn("backticks", errors[0])

    def test_bad_globs_and_duplicates(self) -> None:
        bad = ENTRY.replace("`levels/crate.glb`", "`../x.png`, `/abs/*.png`, `a\\b.png`")
        bad += "- **Author:** Twice\n"
        _, errors = credits.parse("x.md", bad)
        joined = " | ".join(errors)
        for text in ("must not contain ..", "relative to the repo root", "use / in paths", "Author appears twice"):
            self.assertIn(text, joined)

    def test_crlf_is_accepted(self) -> None:
        self.assertEqual(credits.parse("x.md", ENTRY.replace("\n", "\r\n"))[1], [])


class GlobTest(unittest.TestCase):
    def test_star_stays_in_a_folder_and_double_star_crosses(self) -> None:
        cases = {
            ("levels/*.png", "levels/a.png"): True,
            ("levels/*.png", "levels/x/a.png"): False,
            ("levels/**", "levels/x/y/a.png"): True,
            ("**/*.ogg", "a.ogg"): True,
            ("**/*.ogg", "x/y/a.ogg"): True,
            ("levels/**/a.png", "levels/a.png"): True,
            ("a?.png", "ab.png"): True,
            ("a?.png", "a/.png"): False,
            ("a.png", "a_png"): False,
        }
        for (pattern, path), expected in cases.items():
            with self.subTest(pattern=pattern, path=path):
                self.assertEqual(bool(credits.glob_regex(pattern).fullmatch(path)), expected)


class RenderTest(unittest.TestCase):
    def test_sorted_by_title_with_headings_one_level_down(self) -> None:
        zebra, _ = credits.parse("docs/credits/z.md", ENTRY.replace("Crate Pack", "zebra sounds"))
        apple, _ = credits.parse("docs/credits/a.md", ENTRY.replace("Crate Pack", "Apple Model"))
        assert zebra is not None and apple is not None
        text = credits.render(sorted([zebra, apple], key=lambda e: e.title.casefold()))
        self.assertLess(text.index("## Apple Model"), text.index("## zebra sounds"))
        self.assertIn("\n### Notes\nRecolored.\n", text)
        self.assertTrue(text.startswith("# Credits\n"))

    def test_no_entries(self) -> None:
        self.assertIn("No third-party assets yet.", credits.render([]))


def git(root: Path, *args: str) -> None:
    subprocess.run(["git", *args], cwd=root, check=True, capture_output=True)


class RepoTest(unittest.TestCase):
    """Real git: .gitattributes decides what is an LFS asset; untracked files count before their commit."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        git(self.root, "init", "-q")
        write(self.root, ".gitattributes", "*.png filter=lfs diff=lfs merge=lfs -text\naddons/** !filter\n")
        write(self.root, ".gitignore", "out/\n")
        write(self.root, "levels/props/crate/wood.png", "x")
        write(self.root, "addons/tool/icon.png", "x")
        write(self.root, "out/shot.png", "x")
        write(self.root, "levels/room.tscn", "x")

    def tearDown(self) -> None:
        self._tmp.cleanup()

    def main(self) -> int:
        with contextlib.redirect_stdout(io.StringIO()):
            return credits.main(self.root)

    def entry(self, text: str = ENTRY.replace("`levels/crate.glb`", "`levels/room.tscn`")) -> None:
        write(self.root, "docs/credits/crates.md", text)

    def test_lfs_assets_skip_addons_and_ignored_files(self) -> None:
        files = credits.repo_files(self.root)
        self.assertEqual(credits.lfs_assets(self.root, files), ["levels/props/crate/wood.png"])

    def test_uncredited_asset_fails(self) -> None:
        errors = credits.check(self.root).errors
        self.assertTrue(any(e.startswith("levels/props/crate/wood.png: an LFS asset without") for e in errors), errors)

    def test_credited_asset_needs_a_current_credits_md(self) -> None:
        self.entry()
        self.assertEqual(credits.check(self.root).errors, ["CREDITS.md is missing: " + credits.FIX])
        self.assertEqual(self.main(), 0)
        report = credits.check(self.root)
        self.assertEqual((report.errors, report.entries, report.assets), ([], 1, 1))
        write(self.root, "CREDITS.md", "# Credits\nedited by hand\n")
        self.assertEqual(credits.check(self.root).errors, ["CREDITS.md is out of date: " + credits.FIX])

    def test_stale_glob_fails(self) -> None:
        self.entry(ENTRY)  # levels/crate.glb does not exist
        self.main()
        errors = credits.check(self.root).errors
        self.assertEqual(len(errors), 1, errors)
        self.assertIn("`levels/crate.glb` matches no file", errors[0])

    def test_broken_entry_is_reported_and_not_rendered(self) -> None:
        self.entry("no title\n")
        self.assertEqual(self.main(), 1)
        self.assertFalse((self.root / "CREDITS.md").exists())
        errors = credits.check(self.root).errors
        self.assertIn("docs/credits/crates.md: must start with '# <asset name>'", errors)


if __name__ == "__main__":
    unittest.main()
