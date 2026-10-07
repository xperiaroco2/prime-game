"""`sfx-check` (#524): check sound files with the Python standard library only, and write a listening page.

What a file of each category must measure is data: tools/sfx/categories.json (its numbers are provisional until #525
picks the real sounds). A WAV is read whole (RIFF chunks with `struct`, its samples with `array`): PCM 16-bit, mono,
an allowed sample rate, peak headroom, RMS loudness and duration within its category's bounds, leading silence and
DC offset. The standard library cannot decode Vorbis, so an OGG gets its identification header (channels, rate) and
its length (the last page's granule position) checked, and is reported as "header-checked only".

The listening page is one HTML file under tools/out/sfx/ with the sounds inside it as data: URLs, so it needs no
server, no external script or font, and still plays when moved. Its verdicts (approve or reject, and a note) stay in
the browser's storage for that page and are exported as a JSON download, to be saved next to the set.
"""

from __future__ import annotations

import array
import base64
import fnmatch
import html
import json
import math
import re
import struct
import sys
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

from .common import OUT, ROOT, Failure, bad, ok, say, warn

TABLE = ROOT / "tools" / "sfx" / "categories.json"
PAGES = OUT / "sfx"
EXTENSIONS = (".wav", ".ogg")
FULL_SCALE = 32768.0
VERDICTS_FILE = "sfx-verdicts.json"
DEFAULT_KEYS = ("sample_rates", "max_peak_dbfs", "silence_dbfs", "max_leading_silence_s", "max_dc_offset")
CATEGORY_KEYS = ("globs", "rms_dbfs", "duration_s")
# The rules a failure names, in the order a file is checked (the help and the page list them).
RULES = (
    "format",
    "pcm16",
    "mono",
    "sample-rate",
    "category",
    "duration",
    "peak",
    "rms",
    "leading-silence",
    "dc-offset",
)
FORMAT_NAMES = {1: "PCM", 3: "IEEE float", 6: "A-law", 7: "mu-law", 0xFFFE: "extensible"}
# The bytes after the format tag in WAVE_FORMAT_EXTENSIBLE's sub-format GUID (xxxxxxxx-0000-0010-8000-00aa00389b71).
KS_GUID_TAIL = b"\x00\x00\x00\x00\x10\x00\x80\x00\x00\xaa\x00\x38\x9b\x71"


@dataclass(frozen=True)
class Category:
    name: str
    globs: tuple[str, ...]
    rms_dbfs: tuple[float, float]
    duration_s: tuple[float, float]
    about: str = ""


@dataclass(frozen=True)
class Table:
    source: str
    sample_rates: tuple[int, ...]
    max_peak_dbfs: float
    silence_dbfs: float
    max_leading_silence_s: float
    max_dc_offset: float
    categories: dict[str, Category]


@dataclass
class Sound:
    path: Path
    shown: str
    kind: str  # "wav", "ogg" or "other"
    category: str | None = None
    numbers: dict[str, object] = field(default_factory=dict)
    failures: list[tuple[str, str]] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    @property
    def status(self) -> str:
        if self.failures:
            return "failed"
        return "header-checked" if self.kind == "ogg" else "passed"

    def fail(self, rule: str, message: str) -> None:
        assert rule in RULES, rule
        self.failures.append((rule, message))

    def as_json(self) -> dict[str, object]:
        return {
            "path": self.shown,
            "kind": self.kind,
            "category": self.category,
            "status": self.status,
            "numbers": self.numbers,
            "failures": [{"rule": rule, "message": message} for rule, message in self.failures],
            "notes": self.notes,
        }


# --- the table ---------------------------------------------------------------------------------------------------


def _bounds(value: object, where: str) -> tuple[float, float]:
    if (
        not isinstance(value, list)
        or len(value) != 2
        or not all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value)
        or value[0] > value[1]
    ):
        raise Failure(f"{where}: give [low, high], two numbers with low <= high, not {value!r}")
    return float(value[0]), float(value[1])


def _number(value: object, where: str) -> float:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        raise Failure(f"{where}: give a number, not {value!r}")
    return float(value)


def parse_table(data: object, source: str) -> Table:
    """The table from its JSON data; a Failure names the key that is wrong."""
    if not isinstance(data, dict):
        raise Failure(f"{source}: the table is a JSON object with 'defaults' and 'categories'")
    unknown = sorted(set(data) - {"about", "defaults", "categories"})
    if unknown:
        raise Failure(f"{source}: unknown keys {unknown}")
    defaults = data.get("defaults")
    if not isinstance(defaults, dict) or sorted(defaults) != sorted(DEFAULT_KEYS):
        raise Failure(f"{source}: 'defaults' needs exactly {list(DEFAULT_KEYS)}")
    rates = defaults["sample_rates"]
    if not isinstance(rates, list) or not rates or not all(isinstance(r, int) and r > 0 for r in rates):
        raise Failure(f"{source}: defaults.sample_rates is a non-empty list of rates in Hz")
    categories = data.get("categories")
    if not isinstance(categories, dict) or not categories:
        raise Failure(f"{source}: 'categories' maps each category's name to its bounds")
    parsed: dict[str, Category] = {}
    for name, entry in categories.items():
        where = f"{source}: categories.{name}"
        if not re.fullmatch(r"[a-z][a-z0-9_-]*", name):
            raise Failure(f"{where}: a category's name is lowercase letters, digits, '-' and '_'")
        if not isinstance(entry, dict) or sorted(set(entry) - {"about"}) != sorted(CATEGORY_KEYS):
            raise Failure(f"{where}: needs exactly {list(CATEGORY_KEYS)} (and an optional 'about')")
        globs = entry["globs"]
        if not isinstance(globs, list) or not all(isinstance(g, str) and g for g in globs):
            raise Failure(f"{where}.globs: a list of file-name globs")
        parsed[name] = Category(
            name=name,
            globs=tuple(g.lower() for g in globs),
            rms_dbfs=_bounds(entry["rms_dbfs"], f"{where}.rms_dbfs"),
            duration_s=_bounds(entry["duration_s"], f"{where}.duration_s"),
            about=str(entry.get("about", "")),
        )
    return Table(
        source=source,
        sample_rates=tuple(rates),
        max_peak_dbfs=_number(defaults["max_peak_dbfs"], f"{source}: defaults.max_peak_dbfs"),
        silence_dbfs=_number(defaults["silence_dbfs"], f"{source}: defaults.silence_dbfs"),
        max_leading_silence_s=_number(defaults["max_leading_silence_s"], f"{source}: defaults.max_leading_silence_s"),
        max_dc_offset=_number(defaults["max_dc_offset"], f"{source}: defaults.max_dc_offset"),
        categories=parsed,
    )


def load_table(path: Path = TABLE) -> Table:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise Failure(f"{shown_path(path)}: cannot read the table ({exc})") from exc
    except json.JSONDecodeError as exc:
        raise Failure(f"{shown_path(path)}: not valid JSON ({exc})") from exc
    return parse_table(data, shown_path(path))


def folder_words(category: Category) -> set[str]:
    """The folder names that give a file `category`: its name and each glob that is a plain word and a trailing `*`
    (`step*` gives `step`), each also with an `s`. A folder name is a whole word, never a glob match: a `backup/`
    folder is not `ui` through `back*`, nor `selected/` through `select*`."""
    words = {category.name}
    for glob in category.globs:
        word = glob[:-1] if glob.endswith("*") else glob
        if word and not any(c in word for c in "*?["):
            words.add(word)
    return words | {w + "s" for w in words}


def category_of(path: Path, root: Path, table: Table) -> str | None:
    """The first category one of whose globs matches the file name (without its extension), else the nearest folder
    between the file and `root` (the folder it was found under) named after a category (see `folder_words`)."""
    stem = path.stem.lower()
    for category in table.categories.values():
        if any(fnmatch.fnmatchcase(stem, g) for g in category.globs):
            return category.name
    folder = path.parent
    while True:
        name = folder.name.lower()
        for category in table.categories.values():
            if name in folder_words(category):
                return category.name
        if folder == root or folder.parent == folder or root not in folder.parents:
            return None
        folder = folder.parent


# --- reading files -----------------------------------------------------------------------------------------------


@dataclass
class Wav:
    format_tag: int
    channels: int
    rate: int
    bits: int
    block_align: int
    data: bytes
    declared: int  # the data chunk's size as its header says


def read_wav(raw: bytes) -> Wav:
    """The fmt chunk and the data of a RIFF WAVE file; a ValueError says what is wrong with it."""
    if len(raw) < 12 or raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise ValueError("not a RIFF WAVE file")
    fmt: tuple[int, int, int, int, int] | None = None
    data: tuple[bytes, int] | None = None
    pos = 12
    while pos + 8 <= len(raw):
        chunk, size = struct.unpack_from("<4sI", raw, pos)
        body = raw[pos + 8 : pos + 8 + size]
        if chunk == b"fmt ":
            if len(body) < 16:
                raise ValueError("its fmt chunk is shorter than 16 bytes")
            tag, channels, rate, _byte_rate, block_align, bits = struct.unpack_from("<HHIIHH", body)
            if tag == 0xFFFE and len(body) >= 40 and body[26:40] == KS_GUID_TAIL:
                tag = struct.unpack_from("<H", body, 24)[0]  # WAVE_FORMAT_EXTENSIBLE: the sub-format's own tag
            fmt = (tag, channels, rate, block_align, bits)
        elif chunk == b"data" and data is None:
            data = (body, size)
        pos += 8 + size + (size & 1)
    if fmt is None:
        raise ValueError("it has no fmt chunk")
    if data is None:
        raise ValueError("it has no data chunk")
    tag, channels, rate, block_align, bits = fmt
    return Wav(tag, channels, rate, bits, block_align, data[0], data[1])


@dataclass
class Ogg:
    codec: str
    channels: int
    rate: int
    duration_s: float | None


def read_ogg(raw: bytes) -> Ogg:
    """The first packet of an Ogg stream (its identification header) and the last page's granule position."""
    if len(raw) < 27 or raw[:4] != b"OggS":
        raise ValueError("not an Ogg stream")
    segments = raw[26]
    lacing = raw[27 : 27 + segments]
    length = 0
    for value in lacing:
        length += value
        if value < 255:
            break
    start = 27 + segments
    packet = raw[start : start + length]
    if packet[:7] == b"\x01vorbis" and len(packet) >= 16:
        channels, rate = struct.unpack_from("<BI", packet, 11)
        codec = "Vorbis"
    elif packet[:8] == b"OpusHead" and len(packet) >= 16:
        channels, rate = packet[9], 48000  # Opus always decodes at 48 kHz; the header's rate is the input's
        codec = "Opus"
    else:
        return Ogg("unknown", 0, 0, None)
    granule = -1
    pos = 0
    while pos + 27 <= len(raw) and raw[pos : pos + 4] == b"OggS":  # page by page: audio bytes may hold "OggS" too
        count = raw[pos + 26]
        page_granule = struct.unpack_from("<q", raw, pos + 6)[0]
        if page_granule != -1:  # -1: no packet ends on this page
            granule = page_granule
        pos += 27 + count + sum(raw[pos + 27 : pos + 27 + count])
    pre_skip = struct.unpack_from("<H", packet, 10)[0] if codec == "Opus" else 0
    duration = (granule - pre_skip) / rate if granule > 0 and rate else None
    return Ogg(codec, channels, rate, duration)


def dbfs(level: float) -> float | None:
    """A level (0..32768) in dBFS; None for silence (minus infinity, which JSON cannot hold)."""
    return 20 * math.log10(level / FULL_SCALE) if level > 0 else None


def _db_text(value: object) -> str:
    return "-inf" if value is None else f"{value:.1f}"


def _number_text(key: str, value: object) -> str:
    if key.endswith("dbfs"):
        return _db_text(value)
    return "unknown" if value is None else str(value)


# --- checking ----------------------------------------------------------------------------------------------------


def check_wav(sound: Sound, raw: bytes, table: Table) -> None:
    try:
        wav = read_wav(raw)
    except ValueError as exc:
        sound.fail("format", str(exc))
        return
    n = sound.numbers
    n.update(channels=wav.channels, sample_rate=wav.rate, bits=wav.bits)
    n["format"] = FORMAT_NAMES.get(wav.format_tag, f"format tag {wav.format_tag}")
    if len(wav.data) < wav.declared:
        sound.fail("format", f"its data chunk holds {len(wav.data)} of the {wav.declared} bytes its header says")
    if wav.format_tag != 1 or wav.bits != 16:
        sound.fail("pcm16", f"{n['format']} {wav.bits}-bit, not PCM 16-bit")
    if wav.channels != 1:
        sound.fail("mono", f"{wav.channels} channels, not mono")
    if wav.rate not in table.sample_rates:
        sound.fail("sample-rate", f"{wav.rate} Hz, not one of {', '.join(map(str, table.sample_rates))} Hz")
    frame_bytes = wav.block_align or max(1, wav.channels * wav.bits // 8)
    frames = len(wav.data) // frame_bytes
    duration = frames / wav.rate if wav.rate else 0.0
    n["duration_s"] = round(duration, 4)
    category = check_category(sound, table, duration)
    if wav.format_tag != 1 or wav.bits != 16 or wav.channels < 1 or not wav.rate:
        sound.notes.append("levels not measured: sfx-check reads PCM 16-bit samples only")
        return
    samples = array.array("h")
    samples.frombytes(wav.data[: len(wav.data) - len(wav.data) % 2])
    if sys.byteorder == "big":
        samples.byteswap()
    if not samples:
        return
    if wav.channels > 1:
        sound.notes.append(f"levels measured over all {wav.channels} channels together")
    peak = max(max(samples), -min(samples))
    clipped = sum(1 for s in samples if s >= 32767 or s <= -32768)
    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    threshold = FULL_SCALE * 10 ** (table.silence_dbfs / 20)
    first = next((i for i, s in enumerate(samples) if abs(s) > threshold), len(samples))
    leading = (first // wav.channels) / wav.rate
    dc = sum(samples) / len(samples) / FULL_SCALE
    n.update(
        peak_dbfs=_rounded(dbfs(peak)),
        clipped_samples=clipped,
        rms_dbfs=_rounded(dbfs(rms)),
        leading_silence_s=round(leading, 4),
        dc_offset=round(dc, 5),
    )
    peak_db = dbfs(peak)
    if peak_db is not None and (peak_db > table.max_peak_dbfs or clipped):
        clip = f", {clipped} samples at full scale (clipped)" if clipped else ""
        sound.fail("peak", f"peak {peak_db:.1f} dBFS, over the {table.max_peak_dbfs} dBFS ceiling{clip}")
    if category is not None:
        low, high = category.rms_dbfs
        rms_db = dbfs(rms)
        if rms_db is None or not low <= rms_db <= high:
            sound.fail("rms", f"RMS {_db_text(rms_db)} dBFS, outside {category.name}'s band {low}..{high} dBFS")
    if leading > table.max_leading_silence_s:
        sound.fail(
            "leading-silence",
            f"{leading:.3f} s before the first sample above {table.silence_dbfs} dBFS, over "
            f"{table.max_leading_silence_s} s",
        )
    if abs(dc) > table.max_dc_offset:
        sound.fail("dc-offset", f"DC offset {dc:+.4f} of full scale, over {table.max_dc_offset}")


def _rounded(value: float | None) -> float | None:
    return None if value is None else round(value, 2)


def check_category(sound: Sound, table: Table, duration: float | None) -> Category | None:
    category = table.categories.get(sound.category or "")
    if category is None:
        names = ", ".join(table.categories)
        sound.fail(
            "category",
            f"no category: name the file or its folder after one ({names}; globs in {table.source}) or pass "
            "--category",
        )
        return None
    if duration is not None:
        low, high = category.duration_s
        if not low <= duration <= high:
            sound.fail("duration", f"{duration:.3f} s, outside {category.name}'s {low}..{high} s")
    return category


def check_ogg(sound: Sound, raw: bytes, table: Table) -> None:
    try:
        ogg = read_ogg(raw)
    except ValueError as exc:
        sound.fail("format", str(exc))
        return
    n = sound.numbers
    n.update(format=f"Ogg {ogg.codec}", channels=ogg.channels, sample_rate=ogg.rate)
    n["duration_s"] = None if ogg.duration_s is None else round(ogg.duration_s, 4)
    if ogg.codec != "Vorbis":
        sound.fail("format", f"Ogg {ogg.codec}, not Ogg Vorbis")
        check_category(sound, table, None)
        return
    if ogg.channels != 1:
        sound.fail("mono", f"{ogg.channels} channels, not mono")
    if ogg.rate not in table.sample_rates:
        sound.fail("sample-rate", f"{ogg.rate} Hz, not one of {', '.join(map(str, table.sample_rates))} Hz")
    check_category(sound, table, ogg.duration_s)
    if ogg.duration_s is None:
        sound.notes.append("no duration: its last page has no granule position")
    sound.notes.append(
        "header-checked only: the standard library cannot decode Vorbis, so peak, RMS, leading silence and DC offset "
        "are not measured"
    )


def check_file(path: Path, root: Path, table: Table, category: str | None = None) -> Sound:
    suffix = path.suffix.lower()
    kind = {".wav": "wav", ".ogg": "ogg"}.get(suffix, "other")
    sound = Sound(path=path, shown=shown_path(path), kind=kind)
    sound.category = category or category_of(path, root, table)
    if kind == "other":
        sound.fail("format", f"not a {' or '.join(EXTENSIONS)} file")
        return sound
    try:
        raw = path.read_bytes()
    except OSError as exc:
        sound.fail("format", f"cannot read it ({exc})")
        return sound
    (check_wav if kind == "wav" else check_ogg)(sound, raw, table)
    return sound


def shown_path(path: Path) -> str:
    try:
        return path.resolve().relative_to(ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def collect(paths: list[str]) -> list[tuple[Path, Path]]:
    """Each file to check with the folder it was found under: a folder gives its .wav and .ogg files (all depths,
    sorted), a file itself, each file once (the first path that gives it wins). A relative path is looked up under the
    current folder first, then the repository."""
    found: list[tuple[Path, Path]] = []
    seen: set[Path] = set()
    for arg in paths:
        path = Path(arg)
        if not path.is_absolute() and not path.exists() and (ROOT / path).exists():
            path = ROOT / path
        if path.is_dir():
            files = sorted(p for p in path.rglob("*") if p.is_file() and p.suffix.lower() in EXTENSIONS)
            if not files:
                raise Failure(f"{arg}: no {' or '.join(EXTENSIONS)} files in this folder")
            found += [(p, path) for p in files]
        elif path.is_file():
            found.append((path, path.parent))
        else:
            raise Failure(f"{arg}: no such file or folder")
    unique: list[tuple[Path, Path]] = []
    for file, root in found:
        key = file.resolve()
        if key not in seen:
            seen.add(key)
            unique.append((file, root))
    return unique


# --- the report and the page -------------------------------------------------------------------------------------


def report_data(sounds: list[Sound], table: Table, name: str) -> dict[str, object]:
    counts = {status: sum(1 for s in sounds if s.status == status) for status in ("passed", "failed", "header-checked")}
    return {
        "tool": "sfx-check",
        "set": name,
        "table": table.source,
        "summary": counts,
        "files": [s.as_json() for s in sounds],
    }


NUMBER_LABELS = (
    ("format", "format", ""),
    ("channels", "channels", ""),
    ("sample_rate", "rate", " Hz"),
    ("bits", "bits", ""),
    ("duration_s", "duration", " s"),
    ("peak_dbfs", "peak", " dBFS"),
    ("clipped_samples", "clipped", ""),
    ("rms_dbfs", "RMS", " dBFS"),
    ("leading_silence_s", "lead silence", " s"),
    ("dc_offset", "DC offset", ""),
)

STYLE = """
body { font-family: system-ui, sans-serif; margin: 1.5rem; max-width: 70rem; color: #1d1d1f; background: #fafafa; }
h1 { font-size: 1.4rem; } h2 { margin-top: 2rem; border-bottom: 1px solid #ccc; } .band { color: #555; }
.sound { background: #fff; border: 1px solid #ddd; border-left: 6px solid #3a3; border-radius: 4px;
  padding: .6rem .8rem; margin: .6rem 0; display: grid; grid-template-columns: 1fr 1fr; gap: .4rem 1rem; }
.sound.failed { border-left-color: #c33; } .sound.header-checked { border-left-color: #c90; }
.sound h3 { grid-column: 1 / -1; margin: 0; font-size: 1rem; font-family: ui-monospace, monospace; }
.sound audio { width: 100%; } .numbers { font-size: .85rem; border-collapse: collapse; }
.numbers td { padding: 0 .6rem 0 0; } .fails { color: #a11; margin: 0; } .notes { color: #555; margin: 0; }
.verdict label { margin-right: 1rem; } .verdict textarea { width: 100%; min-height: 2.2rem; }
.status { font-size: .8rem; font-weight: normal; margin-left: .6rem; }
.toolbar { position: sticky; top: 0; background: #fafafa; padding: .5rem 0; border-bottom: 1px solid #ddd; }
"""

SCRIPT = """
const KEY = "sfx-verdicts:" + PAGE.set + ":" + PAGE.generated;
const saved = JSON.parse(localStorage.getItem(KEY) || "{}");
function card(path) { return document.querySelector('.sound[data-path="' + CSS.escape(path) + '"]'); }
function read(path) {
  const el = card(path);
  const picked = el.querySelector("input[type=radio]:checked");
  return { verdict: picked ? picked.value : null, note: el.querySelector("textarea").value };
}
function count() {
  const done = PAGE.files.filter(f => read(f.path).verdict !== null).length;
  document.getElementById("count").textContent = done + " of " + PAGE.files.length + " sounds have a verdict";
}
function save() {
  const all = {};
  for (const f of PAGE.files) { all[f.path] = read(f.path); }
  try { localStorage.setItem(KEY, JSON.stringify(all)); } catch (e) { /* storage off: the export still works */ }
  count();
}
for (const f of PAGE.files) {
  const el = card(f.path);
  const old = saved[f.path];
  if (old) {
    if (old.verdict) { el.querySelector('input[value="' + old.verdict + '"]').checked = true; }
    el.querySelector("textarea").value = old.note || "";
  }
  el.addEventListener("change", save);
  el.addEventListener("input", save);
}
document.getElementById("export").addEventListener("click", () => {
  const verdicts = PAGE.files.map(f => Object.assign({ path: f.path, category: f.category, status: f.status },
    read(f.path)));
  const out = { tool: "sfx-check", set: PAGE.set, table: PAGE.table, generated: PAGE.generated,
    exported: new Date().toISOString(), verdicts: verdicts };
  const blob = new Blob([JSON.stringify(out, null, 2) + "\\n"], { type: "application/json" });
  const a = document.createElement("a");
  a.href = URL.createObjectURL(blob);
  a.download = PAGE.download;
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
});
count();
"""


def render_page(sounds: list[Sound], table: Table, name: str, generated: str) -> str:
    """The listening page: one <audio> per file, grouped by category in the table's order (files with none last),
    each with its numbers, its failures, approve or reject and a note; an export button writes the verdicts."""
    e = html.escape
    groups: dict[str | None, list[Sound]] = {c: [] for c in table.categories}
    for sound in sounds:
        groups.setdefault(sound.category if sound.category in table.categories else None, []).append(sound)
    parts = [
        "<!doctype html>",
        '<html lang="en"><head><meta charset="utf-8">',
        f"<title>sfx-check: {e(name)}</title>",
        f"<style>{STYLE}</style></head><body>",
        f"<h1>sfx-check: {e(name)}</h1>",
        f"<p>Generated {e(generated)} by <code>tools/run.sh sfx-check --page</code> with the table "
        f"<code>{e(table.source)}</code>. Listen to each sound, approve or reject it and add a note; the page keeps "
        f"them in this browser. Then <b>Export verdicts</b> and save the file next to the set as "
        f"<code>{VERDICTS_FILE}</code>.</p>",
        '<div class="toolbar"><button id="export" type="button">Export verdicts (JSON)</button> '
        '<span id="count"></span></div>',
    ]
    index = 0
    for key, members in groups.items():
        if not members:
            continue
        category = table.categories.get(key or "")
        title = key or "no category"
        parts.append(f"<section><h2>{e(title)} ({len(members)})</h2>")
        if category is not None:
            about = f"{e(category.about)}. " if category.about else ""
            parts.append(
                f'<p class="band">{about}RMS {category.rms_dbfs[0]}..{category.rms_dbfs[1]} dBFS, '
                f"{category.duration_s[0]}..{category.duration_s[1]} s; peak at most {table.max_peak_dbfs} dBFS.</p>"
            )
        for sound in members:
            index += 1
            parts.append(_card(sound, index))
        parts.append("</section>")
    page = {
        "set": name,
        "table": table.source,
        "generated": generated,
        "download": VERDICTS_FILE,
        "files": [{"path": s.shown, "category": s.category, "status": s.status} for s in sounds],
    }
    data = json.dumps(page, ensure_ascii=True).replace("</", "<\\/")
    parts.append(f"<script>\nconst PAGE = {data};\n{SCRIPT}</script>")
    parts.append("</body></html>")
    return "\n".join(parts) + "\n"


def _card(sound: Sound, index: int) -> str:
    e = html.escape
    mime = "audio/ogg" if sound.kind == "ogg" else "audio/wav"
    try:
        url = f"data:{mime};base64," + base64.b64encode(sound.path.read_bytes()).decode("ascii")
    except OSError:
        url = ""
    rows = "".join(
        f"<tr><td>{label}</td><td>{e(_number_text(key, sound.numbers[key]))}{unit}</td></tr>"
        for key, label, unit in NUMBER_LABELS
        if key in sound.numbers
    )
    fails = "".join(f'<p class="fails">{e(rule)}: {e(message)}</p>' for rule, message in sound.failures)
    notes = "".join(f'<p class="notes">{e(note)}</p>' for note in sound.notes)
    group = f"v{index}"
    return (
        f'<div class="sound {sound.status}" data-path="{e(sound.shown)}">'
        f'<h3>{e(sound.shown)}<span class="status">{e(sound.status)}</span></h3>'
        f'<div><audio controls preload="metadata" src="{url}"></audio>{fails}{notes}</div>'
        f'<div><table class="numbers">{rows}</table></div>'
        f'<div class="verdict" style="grid-column: 1 / -1">'
        f'<label><input type="radio" name="{group}" value="approve"> approve</label>'
        f'<label><input type="radio" name="{group}" value="reject"> reject</label>'
        f'<textarea placeholder="note"></textarea></div>'
        "</div>"
    )


def set_name(paths: list[str]) -> str:
    """The set's name for the report and the page: the one folder's or file's name, else `sfx`."""
    if len(paths) == 1:
        name = Path(paths[0]).resolve().name
        name = Path(name).stem if Path(paths[0]).suffix else name
        cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "-", name).strip("-.")
        if cleaned:
            return cleaned
    return "sfx"


# --- the command -------------------------------------------------------------------------------------------------


def main(
    paths: list[str],
    *,
    page: bool = False,
    category: str | None = None,
    out: Path | None = None,
    table_path: Path = TABLE,
    now: datetime | None = None,
) -> int:
    say("sfx-check")
    table = load_table(table_path)
    if category is not None and category not in table.categories:
        raise Failure(f"--category {category}: not in {table.source} ({', '.join(table.categories)})")
    files = collect(paths)
    sounds = [check_file(path, root, table, category) for path, root in files]
    for sound in sounds:
        numbers = sound.numbers
        summary = ", ".join(
            part
            for part in (
                sound.category or "no category",
                f"{numbers['duration_s']} s" if numbers.get("duration_s") is not None else "",
                f"peak {_db_text(numbers['peak_dbfs'])} dBFS" if "peak_dbfs" in numbers else "",
                f"RMS {_db_text(numbers['rms_dbfs'])} dBFS" if "rms_dbfs" in numbers else "",
            )
            if part
        )
        if sound.status == "passed":
            ok(f"{sound.shown} ({summary})")
        elif sound.status == "header-checked":
            warn(f"{sound.shown} ({summary}): header-checked only")
        for rule, message in sound.failures:
            bad(f"{sound.shown}: {rule}: {message}")
    name = set_name(paths)
    folder = out if out is not None else PAGES
    folder.mkdir(parents=True, exist_ok=True)
    data = report_data(sounds, table, name)
    report = folder / f"{name}.json"
    report.write_bytes((json.dumps(data, indent=2) + "\n").encode("utf-8"))
    say(f"  report {shown_path(report)}")
    if page:
        generated = (now or datetime.now(timezone.utc)).strftime("%Y-%m-%d %H:%M UTC")
        written = folder / f"{name}.html"
        written.write_bytes(render_page(sounds, table, name, generated).encode("utf-8"))
        say(f"  page   {shown_path(written)} (open it in a browser; no server needed)")
    counts = data["summary"]
    assert isinstance(counts, dict)
    failed = counts["failed"]
    say(
        f"sfx-check: {'FAILED' if failed else 'passed'} ({counts['passed']} passed, {failed} failed, "
        f"{counts['header-checked']} header-checked only)"
    )
    return 1 if failed else 0
