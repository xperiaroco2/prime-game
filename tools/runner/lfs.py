"""Git LFS pointer files: what `check` does when a checkout has no LFS content (#515).

CI checks out without LFS content (`lfs: false`, the LFS ADR), so each file `.gitattributes` routes through LFS is a
pointer file there: a few lines of text that start with the spec's version line. Godot imports it by its extension and
fails (`Not a PNG file`, `Not a WAV file`, a glTF parse error), and rewrites its `.import` file as it does; every
resource that uses it then fails to load. The LFS ADR's amendment of 2026-10-07 (option 2) settles it: in CI (and a
Claude Code cloud session, also a checkout that may lack LFS content), the import never sees a pointer file. aside()
puts a stand-in of its type in its place (a 4x4 grey image, a silent WAV, an empty glTF scene: STAND_INS) under its
committed `.import` file, so Godot writes the imported file every resource that uses it loads, with its uid; a type
without a stand-in (WOFF, Ogg or MP3 audio, a video, an FBX) goes behind tools/out's `.gdignore` with its `.import`
file. Both are put back after the import, and the project check drops the lines a hidden one causes (drop_lines()).
Locally, with LFS content, ci_pointers() is empty and nothing changes. The credits check needs only the paths, so it
still covers pointer files. A build (release.yml, with LFS content) runs `check --lfs-content`, which fails on any
pointer file.
"""

from __future__ import annotations

import base64
import os
import re
import shutil
import struct
import zlib
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path

from . import common, credits
from .common import Failure

# The first line of every pointer file (https://github.com/git-lfs/git-lfs/blob/main/docs/spec.md); the spec keeps
# pointer files under 1024 bytes, so a larger file is content even if it starts the same way.
HEADER = b"version https://git-lfs.github.com/spec/v1\n"
MAX_SIZE = 1024


def _png() -> bytes:
    """A 4x4 grey RGB PNG (4x4: a block for any VRAM compression a committed .import may ask for)."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)

    rows = (b"\x00" + b"\x80" * 12) * 4
    header = struct.pack(">IIBBBBB", 4, 4, 8, 2, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b"")


def _bmp() -> bytes:
    """A 4x4 grey 24-bit BMP (rows of 12 bytes need no padding)."""
    pixels = b"\x80" * 48
    info = struct.pack("<IiiHHIIiiII", 40, 4, 4, 1, 24, 0, len(pixels), 2835, 2835, 0, 0)
    return b"BM" + struct.pack("<IHHI", 14 + len(info) + len(pixels), 0, 0, 14 + len(info)) + info + pixels


def _tga() -> bytes:
    """A 4x4 grey uncompressed 24-bit TGA."""
    return struct.pack("<BBBHHBHHHHBB", 0, 0, 2, 0, 0, 0, 0, 0, 4, 4, 24, 0) + b"\x80" * 48


def _wav() -> bytes:
    """A 16-bit mono WAV of four silent samples."""
    data = b"\x00" * 8
    fmt = struct.pack("<HHIIHH", 1, 1, 44100, 88200, 2, 16)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


def _sfnt(tables: dict[bytes, bytes]) -> bytes:
    """An sfnt (TrueType) file of these tables: the directory sorted by tag, each table padded to 4 bytes."""
    count = len(tables)
    power = 1 << (count.bit_length() - 1)
    header = struct.pack(">IHHHH", 0x00010000, count, power * 16, power.bit_length() - 1, count * 16 - power * 16)
    offset = len(header) + 16 * count
    directory, body = b"", b""
    for tag in sorted(tables):
        data = tables[tag]
        padded = data + b"\x00" * (-len(data) % 4)
        checksum = sum(struct.unpack(f">{len(padded) // 4}I", padded)) & 0xFFFFFFFF
        directory += struct.pack(">4sIII", tag, checksum, offset + len(body), len(data))
        body += padded
    return header + directory + body


def _ttf() -> bytes:
    """A minimal TrueType font (#520): one empty glyph (.notdef), 1000 units per em, mapped from no character, named
    "StandIn". FreeType opens it, so Godot imports it as a FontFile; a font from the pointer file's place draws
    nothing (headless runs draw nothing anyway)."""
    name = "StandIn".encode("utf-16-be")
    return _sfnt(
        {
            # version, revision, checkSumAdjustment, magic, flags, unitsPerEm, created, modified, bbox, macStyle,
            # lowestRecPPEM, fontDirectionHint, indexToLocFormat (short), glyphDataFormat
            b"head": struct.pack(
                ">iiIIHHqqhhhhHHhhh", 0x00010000, 0x00010000, 0, 0x5F0F3CF5, 0x000B, 1000, 0, 0, 0, 0, 0, 0, 0, 8, 2,
                0, 0,
            ),  # fmt: skip
            # version, ascender, descender, lineGap, advanceWidthMax, three bearings and extents, caret slope and
            # offset, four reserved, metricDataFormat, numberOfHMetrics
            b"hhea": struct.pack(">ihhhHhhhhhhhhhhhH", 0x00010000, 800, -200, 0, 500, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 1),
            # version 1.0, numGlyphs 1, then the maxima (maxZones 2)
            b"maxp": struct.pack(">i14H", 0x00010000, 1, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0),
            b"hmtx": struct.pack(">Hh", 500, 0),
            b"loca": struct.pack(">HH", 0, 0),
            b"glyf": b"\x00" * 4,
            # one Windows Unicode BMP subtable, format 4 with only the closing 0xFFFF segment
            b"cmap": struct.pack(">HHHHI", 0, 1, 3, 1, 12) + struct.pack(">7H5H", 4, 24, 0, 2, 2, 0, 0, 0xFFFF, 0, 0xFFFF, 1, 0),
            # format 0, one record: Windows, Unicode BMP, en-US, the family name
            b"name": struct.pack(">HHH", 0, 1, 18) + struct.pack(">6H", 3, 1, 0x409, 1, len(name), 0) + name,
            # version 3.0 (no glyph names), italic angle, underline position and thickness, not fixed pitch, memory
            b"post": struct.pack(">iihhIIIII", 0x00030000, 0, -100, 50, 0, 0, 0, 0, 0),
        }
    )


GLTF = b'{"asset":{"version":"2.0"},"scene":0,"scenes":[{"nodes":[0]}],"nodes":[{"name":"StandIn"}]}'


def _glb() -> bytes:
    """GLTF in the binary container: a JSON chunk padded with spaces to 4 bytes."""
    json = GLTF + b" " * (-len(GLTF) % 4)
    return b"glTF" + struct.pack("<II", 2, 12 + 8 + len(json)) + struct.pack("<I", len(json)) + b"JSON" + json


# A stand-in of each type Godot imports from a few bytes, by extension (aside()). The JPEG and the WebP are a 4x4 grey
# image that Godot 4.7.2 wrote (Image.save_jpg_to_buffer, save_webp_to_buffer, probed for #515): Python has no
# encoder for them. A font (TTF or OTF, #520: the theme refers to Comfortaa's) is a minimal TrueType file, which
# FreeType opens whatever the extension. The other LFS types keep no stand-in (WOFF, Ogg or MP3 audio, a video, an FBX
# that needs the FBX2glTF importer, a .blend that needs Blender, files Godot does not import).
JPEG = base64.b64decode("/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAgGBgcGBQgHBwcJCQgKDBQNDAsLDBkSEw8UHRofHh0aHBwgJC4nICIsIxwcKDcpLDAxNDQ0Hyc5PTgyPC4zNDL/2wBDAQkJCQwLDBgNDRgyIRwhMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjIyMjL/wAARCAAEAAQDASIAAhEBAxEB/8QAHwAAAQUBAQEBAQEAAAAAAAAAAAECAwQFBgcICQoL/8QAtRAAAgEDAwIEAwUFBAQAAAF9AQIDAAQRBRIhMUEGE1FhByJxFDKBkaEII0KxwRVS0fAkM2JyggkKFhcYGRolJicoKSo0NTY3ODk6Q0RFRkdISUpTVFVWV1hZWmNkZWZnaGlqc3R1dnd4eXqDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uHi4+Tl5ufo6erx8vP09fb3+Pn6/8QAHwEAAwEBAQEBAQEBAQAAAAAAAAECAwQFBgcICQoL/8QAtREAAgECBAQDBAcFBAQAAQJ3AAECAxEEBSExBhJBUQdhcRMiMoEIFEKRobHBCSMzUvAVYnLRChYkNOEl8RcYGRomJygpKjU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6goOEhYaHiImKkpOUlZaXmJmaoqOkpaanqKmqsrO0tba3uLm6wsPExcbHyMnK0tPU1dbX2Nna4uPk5ebn6Onq8vP09fb3+Pn6/9oADAMBAAIRAxEAPwBKKKKAP//Z")
STAND_INS = {
    ".png": _png(),
    ".jpg": JPEG,
    ".jpeg": JPEG,
    ".webp": base64.b64decode("UklGRh4AAABXRUJQVlA4TBEAAAAvA8AAAAfQv/71r/+BiOh/AAA="),
    ".bmp": _bmp(),
    ".tga": _tga(),
    ".wav": _wav(),
    ".gltf": GLTF,
    ".glb": _glb(),
    ".obj": b"v 0 0 0\nv 1 0 0\nv 0 1 0\nf 1 2 3\n",
    ".ttf": _ttf(),
    ".otf": _ttf(),
}
# Where aside() keeps the pointer files during an import: a .gdignore in it makes Godot's scan skip it (as tools/out's
# own does, common.ensure_out), and tools/out is gitignored, so `git status` sees nothing once the files are back.
ASIDE = "tools/out/lfs-aside"
# A res:// path in a project check line, and a script's followed by `:<line>`: the file the line is about.
RES_PATH = re.compile(r"res://[^\s\"'()\[\],:;]+")
SCRIPT_LOCATION = re.compile(r"(res://[^\s\"'()\[\],:;]+\.gd):\d+")
# The lines by which a script says that it failed to load because of the file they name.
SCRIPT_FAILED = ("Could not preload resource file", "Parse Error")
CHECK_LINE = ("CHECK error ", "CHECK warning ")
SUMMARY = re.compile(r"\berrors=\d+ warnings=\d+")


def is_pointer(path: Path) -> bool:
    """Whether the file is a Git LFS pointer file rather than its content."""
    try:
        if path.stat().st_size >= MAX_SIZE:
            return False
        with path.open("rb") as file:
            return file.read(len(HEADER)) == HEADER
    except OSError:
        return False


def pointers(root: Path | None = None) -> list[str]:
    """The repo-relative paths of the files .gitattributes routes through LFS that are pointer files here (addons/
    is outside LFS). None in a folder whose .gitattributes routes nothing through LFS, or that is not a git work tree
    (a runner test's temp project): git cannot list its files, and it has no LFS files."""
    root = root or common.ROOT
    try:
        if "filter=lfs" not in (root / ".gitattributes").read_text(encoding="utf-8"):
            return []
    except (OSError, UnicodeDecodeError):
        return []
    try:
        assets = credits.lfs_assets(root, credits.repo_files(root))
    except Failure:
        return []
    return [name for name in assets if is_pointer(root / name)]


def ci_pointers(root: Path | None = None) -> list[str]:
    """pointers() in CI and in a Claude Code cloud session (common.IS_CLOUD), checkouts that may have no LFS content;
    locally none, so nothing changes there (check.main names them instead: lfs.local_hint)."""
    return pointers(root) if common.IS_CI or common.IS_CLOUD else []


def stand_in(name: str) -> bytes | None:
    """The stand-in aside() imports in place of the pointer file `name`, or None for a type without one."""
    return STAND_INS.get(Path(name).suffix.lower())


@contextmanager
def aside(names: list[str], root: Path | None = None) -> Iterator[None]:
    """Keep the pointer files `names` (repo-relative) out of Godot's sight for an import, and put them back
    afterwards, even when the import failed. Each is moved under ASIDE; one with a stand-in (stand_in()) gets it in
    its place under a copy of its committed `.import` file, so the import writes the imported file that file names,
    with its uid and params (a new asset's `.import`, which the import writes, is removed again); one without has its
    `.import` file moved too. The moved files go back as they were (their bytes and times: the import stays
    current). A file that cannot go back is a Failure that names it (the checkout would otherwise lose it)."""
    root = root or common.ROOT
    moved: list[tuple[Path, Path]] = []
    made: list[Path] = []
    try:
        if names:
            (root / ASIDE).mkdir(parents=True, exist_ok=True)
            (root / ASIDE / ".gdignore").touch()  # Godot's scan skips the folder, whoever made tools/out
        for name in names:
            data = stand_in(name)
            for rel in (name, name + ".import"):
                source = root / rel
                if not source.is_file():
                    if data is not None and rel != name:
                        made.append(source)
                    continue
                target = root / ASIDE / rel
                target.parent.mkdir(parents=True, exist_ok=True)
                if data is not None and rel != name:
                    shutil.copy2(source, target)  # the import reads it: its uid and params
                else:
                    os.replace(source, target)
                moved.append((source, target))
            if data is not None:
                (root / name).write_bytes(data)
        yield
    finally:
        lost = []
        for source, target in reversed(moved):
            try:
                os.replace(target, source)
            except OSError as exc:
                lost.append(f"{source.relative_to(root).as_posix()} ({exc})")
        for path in made:
            try:
                path.unlink(missing_ok=True)
            except OSError as exc:
                lost.append(f"{path.relative_to(root).as_posix()} (the import wrote it; {exc})")
        if lost:
            raise Failure(f"could not put the LFS pointer files back from {ASIDE}/: " + ", ".join(lost))


def res_paths(names: list[str], root: Path | None = None) -> set[str]:
    """The res:// paths by which the project check's lines name the pointer files `names`: each file's own, and the
    imported files its committed `.import` file names (`path=` and `dest_files`, under res://.godot/imported/), which
    the import never wrote in CI (`Unable to open file: res://.godot/imported/a.png-<hash>.ctex`)."""
    root = root or common.ROOT
    paths = set()
    for name in names:
        paths.add(f"res://{name}")
        try:
            text = (root / (name + ".import")).read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        paths.update(path for path in RES_PATH.findall(text) if path.startswith("res://.godot/imported/"))
    return paths


def drop_lines(lines: list[str], names: list[str], root: Path | None = None) -> tuple[list[str], int, int]:
    """The project check's output without the lines a pointer file causes, and how many errors and warnings it
    dropped.

    A CHECK error or warning line is dropped when it names a pointer file or its imported file (res_paths:
    `Failed loading resource: res://a.png`, `referenced non-existent resource at: res://a.png`, an `invalid UID ...
    using text path instead: res://a.png`, `Unable to open file: res://.godot/imported/a.png-<hash>.ctex`) or a script
    that failed to load because of one (`res://p.gd:3: Parse Error: Could not preload resource file "res://a.png"`,
    then `Failed to load script "res://p.gd"`, and a script that preloads that one). A scene that refers to one still
    loads, so its other lines are kept. A pointer file with a stand-in (aside()) causes no lines. The summary line gets
    the counts of the lines kept; with no pointer files the output is unchanged.
    """
    if not names:
        return lines, 0, 0
    checks = [line for line in lines if line.startswith(CHECK_LINE)]
    skipped = res_paths(names, root)
    grown = True
    while grown:  # a script that failed to load because of a skipped file makes the lines that name it dropped too
        grown = False
        for line in checks:
            if _names(line, skipped) and any(sign in line for sign in SCRIPT_FAILED):
                for where in SCRIPT_LOCATION.findall(line):
                    if where not in skipped:
                        skipped.add(where)
                        grown = True
    kept: list[str] = []
    errors = warnings = dropped_errors = dropped_warnings = 0
    for line in lines:
        if line.startswith(CHECK_LINE):
            error = line.startswith("CHECK error ")
            if _names(line, skipped):
                dropped_errors += error
                dropped_warnings += not error
                continue
            errors += error
            warnings += not error
        kept.append(line)
    summary = f"errors={errors} warnings={warnings}"
    kept = [SUMMARY.sub(summary, line) if line.startswith("CHECK summary") else line for line in kept]
    return kept, dropped_errors, dropped_warnings


def _names(line: str, paths: set[str]) -> bool:
    return any(path.rstrip(".") in paths for path in RES_PATH.findall(line))


def summary(names: list[str], errors: int, warnings: int) -> str:
    """check's one line in CI about the pointer files it skipped."""
    files = f"{len(names)} LFS pointer file{'' if len(names) == 1 else 's'}"
    standing = sum(stand_in(name) is not None for name in names)
    return (
        f"{files} skipped (this checkout has no LFS content): {standing} imported from a stand-in,"
        f" {len(names) - standing} kept out of the import; {errors} error and {warnings} warning lines of the project"
        " check about them dropped; credits still checked"
    )


def local_hint(root: Path | None = None) -> str:
    """check's warning on a PC whose checkout has pointer files ('' when none): the import fails on each."""
    names = pointers(root)
    if not names:
        return ""
    shown = ", ".join(names[:3]) + (f" and {len(names) - 3} more" if len(names) > 3 else "")
    return (
        f"{len(names)} LFS pointer file{'' if len(names) == 1 else 's'} instead of the content ({shown}): Godot cannot"
        " import them; get the content with `git lfs pull` (CI skips them)"
    )


def require_content(root: Path | None = None) -> list[str]:
    """`check --lfs-content`: a problem line for each pointer file, for a build that must ship the real assets."""
    return [
        f"{name}: a Git LFS pointer file, not its content: this checkout has no LFS content (actions/checkout with"
        " `lfs: true`, or `git lfs pull`)"
        for name in pointers(root)
    ]
