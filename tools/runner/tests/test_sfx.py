"""sfx-check (#524): each rule's verdict on WAV and OGG fixtures generated here (no binary fixture is committed), the
table's validation, the report, the exit code and the listening page."""

from __future__ import annotations

import array
import contextlib
import io
import json
import math
import re
import struct
import sys
import tempfile
import unittest
import wave
from datetime import datetime, timezone
from pathlib import Path

from runner import cli, sfx
from runner.common import Failure

TABLE = {
    "defaults": {
        "sample_rates": [44100, 48000],
        "max_peak_dbfs": -1.0,
        "silence_dbfs": -50.0,
        "max_leading_silence_s": 0.05,
        "max_dc_offset": 0.01,
    },
    "categories": {
        "footstep": {"globs": ["footstep*", "step*"], "rms_dbfs": [-30, -1], "duration_s": [0.05, 1.0]},
        "ui": {"about": "menu clicks", "globs": ["click*"], "rms_dbfs": [-30, -10], "duration_s": [0.02, 0.5]},
    },
}


def table() -> sfx.Table:
    return sfx.parse_table(json.loads(json.dumps(TABLE)), "test-table.json")


def samples(
    seconds: float = 0.3,
    rate: int = 44100,
    channels: int = 1,
    amplitude: float = 0.2,
    lead: float = 0.0,
    dc: float = 0.0,
) -> list[int]:
    """A 440 Hz sine (amplitude as a fraction of full scale, clamped like a clipping recorder), after `lead` seconds
    of silence, plus a DC offset; interleaved when there is more than one channel."""
    out: list[int] = []
    for i in range(int(seconds * rate)):
        t = i / rate
        value = 0.0 if t < lead else amplitude * math.sin(2 * math.pi * 440 * t) + dc
        out += [max(-32768, min(32767, round(value * 32768)))] * channels
    return out


def write_wav(path: Path, sampwidth: int = 2, rate: int = 44100, channels: int = 1, **kwargs: float) -> Path:
    data = samples(rate=rate, channels=channels, **kwargs)  # type: ignore[arg-type]
    path.parent.mkdir(parents=True, exist_ok=True)
    with wave.open(str(path), "wb") as out:
        out.setnchannels(channels)
        out.setsampwidth(sampwidth)
        out.setframerate(rate)
        if sampwidth == 2:
            frames = array.array("h", data)
            if sys.byteorder == "big":
                frames.byteswap()
            out.writeframes(frames.tobytes())
        else:  # 24-bit: the top three bytes of each 32-bit sample, little-endian
            out.writeframes(b"".join(struct.pack("<i", s << 16)[1:] for s in data))
    return path


def wav_bytes(fmt: bytes, data: bytes, declared: int | None = None) -> bytes:
    size = len(data) if declared is None else declared
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", size) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


def ogg_page(packet: bytes, granule: int, header_type: int, seq: int) -> bytes:
    lacing = [255] * (len(packet) // 255) + [len(packet) % 255]
    header = struct.pack("<4sBBqIIIB", b"OggS", 0, header_type, granule, 7, seq, 0, len(lacing))
    return header + bytes(lacing) + packet


def vorbis(channels: int = 1, rate: int = 44100, seconds: float = 0.3) -> bytes:
    ident = b"\x01vorbis" + struct.pack("<IBIiiiBB", 0, channels, rate, 0, 128000, 0, 0xB8, 1)
    # The last page's payload holds "OggS" with a bogus granule: only a page-by-page walk reads the right one.
    audio = b"OggS" + struct.pack("<BBq", 0, 0, 99 * rate) + b"\x00" * 300
    pages = ogg_page(ident, 0, 2, 0) + ogg_page(b"\x03vorbis", -1, 0, 1)
    return pages + ogg_page(audio, round(seconds * rate), 4, 2)


def opus() -> bytes:
    head = b"OpusHead" + struct.pack("<BBHIhB", 1, 1, 312, 44100, 0, 0)
    return ogg_page(head, 0, 2, 0) + ogg_page(b"\x00" * 10, 48000 // 4 + 312, 4, 1)


class Fixtures(unittest.TestCase):
    def setUp(self) -> None:
        self.dir = Path(self.enterContext(tempfile.TemporaryDirectory()))
        self.table = table()

    def check(self, path: Path, category: str | None = None) -> sfx.Sound:
        return sfx.check_file(path, path.parent, self.table, category)

    def rules(self, sound: sfx.Sound) -> list[str]:
        return [rule for rule, _message in sound.failures]

    def run_main(self, *paths: Path, **kwargs: object) -> tuple[int, str]:
        table_file = self.dir / "table.json"
        table_file.write_text(json.dumps(TABLE), encoding="utf-8")
        printed = io.StringIO()
        with contextlib.redirect_stdout(printed):
            code = sfx.main([str(p) for p in paths], out=self.dir / "out", table_path=table_file, **kwargs)
        return code, printed.getvalue()

    def make_set(self) -> Path:
        root = self.dir / "steps"
        write_wav(root / "good.wav")
        write_wav(root / "clipped.wav", amplitude=1.5)
        write_wav(root / "stereo.wav", channels=2)
        write_wav(root / "long.wav", seconds=1.5)
        (root / "step.ogg").write_bytes(vorbis())
        (root / "notes.txt").write_text("not a sound", encoding="utf-8")
        return root


class WavRulesTest(Fixtures):
    def test_a_clean_mono_16_bit_step_passes_with_its_numbers(self) -> None:
        sound = self.check(write_wav(self.dir / "step_01.wav"))
        self.assertEqual(sound.failures, [])
        self.assertEqual(sound.status, "passed")
        self.assertEqual(sound.category, "footstep")
        n = sound.numbers
        self.assertEqual((n["format"], n["channels"], n["sample_rate"], n["bits"]), ("PCM", 1, 44100, 16))
        self.assertAlmostEqual(n["duration_s"], 0.3, places=3)
        self.assertAlmostEqual(n["peak_dbfs"], 20 * math.log10(0.2), delta=0.05)
        self.assertAlmostEqual(n["rms_dbfs"], 20 * math.log10(0.2) - 3.01, delta=0.05)
        self.assertEqual((n["clipped_samples"], n["leading_silence_s"]), (0, 0.0))
        self.assertLess(abs(n["dc_offset"]), 0.001)

    def test_a_clipped_file_fails_peak_naming_the_clipped_samples(self) -> None:
        sound = self.check(write_wav(self.dir / "step_clipped.wav", amplitude=1.5))
        self.assertEqual(self.rules(sound), ["peak"])
        self.assertIn("clipped", sound.failures[0][1])
        self.assertGreater(sound.numbers["clipped_samples"], 0)

    def test_a_peak_over_the_ceiling_fails_without_clipping(self) -> None:
        sound = self.check(write_wav(self.dir / "step_hot.wav", amplitude=0.95))
        self.assertEqual(self.rules(sound), ["peak"])
        self.assertNotIn("clipped", sound.failures[0][1])

    def test_a_stereo_file_fails_mono(self) -> None:
        sound = self.check(write_wav(self.dir / "step_stereo.wav", channels=2))
        self.assertEqual(self.rules(sound), ["mono"])
        self.assertIn("2 channels", sound.failures[0][1])
        self.assertAlmostEqual(sound.numbers["duration_s"], 0.3, places=3)

    def test_a_too_long_file_fails_duration(self) -> None:
        sound = self.check(write_wav(self.dir / "click_long.wav", seconds=0.8))
        self.assertEqual(self.rules(sound), ["duration"])
        self.assertIn("ui's 0.02..0.5 s", sound.failures[0][1])

    def test_a_too_quiet_file_fails_rms_and_a_silent_one_reads_minus_infinity(self) -> None:
        sound = self.check(write_wav(self.dir / "step_quiet.wav", amplitude=0.005))
        self.assertEqual(self.rules(sound), ["rms"])
        silent = self.check(write_wav(self.dir / "step_silent.wav", amplitude=0.0))
        self.assertIn("rms", self.rules(silent))
        self.assertIn("RMS -inf dBFS", dict(silent.failures)["rms"])
        self.assertIsNone(silent.numbers["rms_dbfs"])

    def test_leading_silence_over_the_limit_fails(self) -> None:
        sound = self.check(write_wav(self.dir / "step_late.wav", lead=0.2))
        self.assertEqual(self.rules(sound), ["leading-silence"])
        self.assertAlmostEqual(sound.numbers["leading_silence_s"], 0.2, places=2)

    def test_a_dc_offset_fails(self) -> None:
        sound = self.check(write_wav(self.dir / "step_dc.wav", dc=0.05))
        self.assertEqual(self.rules(sound), ["dc-offset"])
        self.assertAlmostEqual(sound.numbers["dc_offset"], 0.05, places=3)

    def test_a_24_bit_file_fails_pcm16_and_its_levels_are_not_measured(self) -> None:
        sound = self.check(write_wav(self.dir / "step_24.wav", sampwidth=3))
        self.assertEqual(self.rules(sound), ["pcm16"])
        self.assertNotIn("rms_dbfs", sound.numbers)
        self.assertTrue(any("levels not measured" in note for note in sound.notes))

    def test_a_rate_off_the_list_fails_sample_rate(self) -> None:
        sound = self.check(write_wav(self.dir / "step_22k.wav", rate=22050))
        self.assertEqual(self.rules(sound), ["sample-rate"])

    def test_extensible_pcm_16_bit_passes_and_extensible_float_fails(self) -> None:
        data = array.array("h", samples())
        if sys.byteorder == "big":
            data.byteswap()

        def extensible(sub: int, bits: int) -> bytes:
            guid = struct.pack("<H", sub) + sfx.KS_GUID_TAIL
            return struct.pack("<HHIIHHHHI", 0xFFFE, 1, 44100, 44100 * bits // 8, bits // 8, bits, 22, bits, 4) + guid

        good = self.dir / "step_ext.wav"
        good.write_bytes(wav_bytes(extensible(1, 16), data.tobytes()))
        self.assertEqual(self.check(good).failures, [])
        floats = self.dir / "step_float.wav"
        floats.write_bytes(wav_bytes(extensible(3, 32), b"\x00" * 4 * 13230))
        self.assertEqual(self.rules(self.check(floats)), ["pcm16"])
        self.assertIn("IEEE float 32-bit", self.check(floats).failures[0][1])

    def test_a_truncated_data_chunk_and_a_file_that_is_no_wav_fail_format(self) -> None:
        fmt = struct.pack("<HHIIHH", 1, 1, 44100, 88200, 2, 16)
        data = array.array("h", samples()).tobytes()
        short = self.dir / "step_short.wav"
        short.write_bytes(wav_bytes(fmt, data, declared=len(data) + 1000))
        self.assertEqual(self.rules(self.check(short)), ["format"])
        junk = self.dir / "step_junk.wav"
        junk.write_bytes(b"ID3 not a wave at all")
        self.assertEqual(self.check(junk).failures, [("format", "not a RIFF WAVE file")])
        text = self.dir / "step.mp3"
        text.write_bytes(b"x")
        self.assertEqual(self.rules(self.check(text)), ["format"])


class CategoryTest(Fixtures):
    def test_the_file_name_then_the_nearest_folder_then_nothing(self) -> None:
        root = self.dir / "set"
        by_name = write_wav(root / "misc" / "Click_02.wav")
        by_folder = write_wav(root / "steps" / "wood" / "a.wav")
        by_folder_name = write_wav(root / "ui" / "b.wav")
        outside = write_wav(root / "c.wav")
        self.assertEqual(sfx.category_of(by_name, root, self.table), "ui")
        self.assertEqual(sfx.category_of(by_folder, root, self.table), "footstep")
        self.assertEqual(sfx.category_of(by_folder_name, root, self.table), "ui")
        self.assertIsNone(sfx.category_of(outside, root, self.table))

    def test_a_folder_counts_only_as_a_whole_word_never_as_a_glob_match(self) -> None:
        root = self.dir / "set"
        real = sfx.load_table()  # the generic globs (back*, select*, drop*) are the real table's
        cases = {
            "backup": None,
            "selected": None,
            "stepping": None,
            "footsteps": "footstep",
            "packages": "item",
            "drops": "item",
            "clicks": "ui",
            "tasks": "task",
        }
        for folder, expected in cases.items():
            with self.subTest(folder=folder):
                path = write_wav(root / folder / "a.wav")
                self.assertEqual(sfx.category_of(path, root, real), expected)

    def test_a_folder_above_the_one_given_does_not_count(self) -> None:
        inner = write_wav(self.dir / "steps" / "set" / "a.wav")
        self.assertIsNone(sfx.category_of(inner, self.dir / "steps" / "set", self.table))

    def test_no_category_fails_and_category_overrides(self) -> None:
        path = write_wav(self.dir / "thing.wav")
        sound = self.check(path)
        self.assertEqual(self.rules(sound), ["category"])
        self.assertIn("--category", sound.failures[0][1])
        self.assertEqual(self.check(path, "footstep").failures, [])


class OggTest(Fixtures):
    def write(self, name: str, raw: bytes) -> Path:
        path = self.dir / name
        path.write_bytes(raw)
        return path

    def test_a_mono_vorbis_file_is_header_checked_only_with_its_length(self) -> None:
        sound = self.check(self.write("step.ogg", vorbis()))
        self.assertEqual(sound.failures, [])
        self.assertEqual(sound.status, "header-checked")
        self.assertEqual(sound.numbers, {"format": "Ogg Vorbis", "channels": 1, "sample_rate": 44100, "duration_s": 0.3})
        self.assertTrue(any("header-checked only" in note for note in sound.notes))

    def test_its_header_and_length_fail_like_a_wav(self) -> None:
        sound = self.check(self.write("step_bad.ogg", vorbis(channels=2, rate=32000, seconds=2.0)))
        self.assertEqual(self.rules(sound), ["mono", "sample-rate", "duration"])

    def test_opus_and_garbage_fail_format(self) -> None:
        sound = self.check(self.write("step_opus.ogg", opus()))
        self.assertEqual(self.rules(sound), ["format"])
        self.assertIn("Ogg Opus, not Ogg Vorbis", sound.failures[0][1])
        self.assertAlmostEqual(sound.numbers["duration_s"], 0.25, places=3)
        self.assertEqual(self.rules(self.check(self.write("step_x.ogg", b"RIFF...."))), ["format"])


class TableTest(unittest.TestCase):
    def bad(self, change: dict[str, object], words: str) -> None:
        data = json.loads(json.dumps(TABLE))
        for path, value in change.items():
            *parents, key = path.split(".")
            target = data
            for parent in parents:
                target = target[parent]
            if value is None:
                del target[key]
            else:
                target[key] = value
        with self.assertRaises(Failure) as caught:
            sfx.parse_table(data, "t.json")
        self.assertIn(words, str(caught.exception))

    def test_a_bad_table_names_the_key(self) -> None:
        self.bad({"categories.ui.rms_dbfs": [-10, -30]}, "categories.ui.rms_dbfs")
        self.bad({"categories.ui.duration_s": None}, "categories.ui: needs exactly")
        self.bad({"categories.ui.loudness": 3}, "categories.ui: needs exactly")
        self.bad({"defaults.max_dc_offset": None}, "'defaults' needs exactly")
        self.bad({"defaults.sample_rates": []}, "sample_rates")
        self.bad({"categories.Door": TABLE["categories"]["ui"]}, "categories.Door")
        self.bad({"extra": 1}, "unknown keys ['extra']")

    def test_the_real_table_loads_and_a_file_in_the_middle_of_each_band_passes(self) -> None:
        real = sfx.load_table()
        self.assertTrue(real.categories)
        with tempfile.TemporaryDirectory() as tmp:
            for category in real.categories.values():
                with self.subTest(category=category.name):
                    rms = sum(category.rms_dbfs) / 2
                    seconds = sum(category.duration_s) / 2
                    amplitude = 10 ** (rms / 20) * math.sqrt(2)  # a sine's RMS is its amplitude over sqrt 2
                    path = write_wav(
                        Path(tmp) / f"{category.name}.wav", rate=real.sample_rates[0], seconds=seconds,
                        amplitude=amplitude,
                    )
                    sound = sfx.check_file(path, path.parent, real, category.name)
                    self.assertEqual(sound.failures, [])


class CommandTest(Fixtures):
    def test_a_failure_exits_1_naming_the_file_and_the_rule_in_the_output_and_the_report(self) -> None:
        root = self.make_set()
        code, printed = self.run_main(root)
        self.assertEqual(code, 1)
        for name, rule in (("clipped.wav", "peak"), ("stereo.wav", "mono"), ("long.wav", "duration")):
            self.assertRegex(printed, rf"FAIL  \S*{name}: {rule}: ")
        self.assertIn("header-checked only", printed)
        self.assertIn("sfx-check: FAILED (1 passed, 3 failed, 1 header-checked only)", printed)
        report = json.loads((self.dir / "out" / "steps.json").read_text(encoding="utf-8"))
        self.assertEqual(report["summary"], {"passed": 1, "failed": 3, "header-checked": 1})
        verdicts = {Path(f["path"]).name: (f["status"], [x["rule"] for x in f["failures"]]) for f in report["files"]}
        self.assertEqual(
            verdicts,
            {
                "clipped.wav": ("failed", ["peak"]),
                "good.wav": ("passed", []),
                "long.wav": ("failed", ["duration"]),
                "step.ogg": ("header-checked", []),
                "stereo.wav": ("failed", ["mono"]),
            },
        )
        self.assertFalse((self.dir / "out" / "steps.html").exists(), "the page only with --page")

    def test_a_clean_set_exits_0_and_a_header_checked_ogg_does_not_fail_it(self) -> None:
        write_wav(self.dir / "ok" / "step_1.wav")
        (self.dir / "ok" / "step_2.ogg").write_bytes(vorbis())
        code, printed = self.run_main(self.dir / "ok")
        self.assertEqual(code, 0, printed)
        self.assertIn("sfx-check: passed (1 passed, 0 failed, 1 header-checked only)", printed)

    def test_a_missing_path_an_empty_folder_and_an_unknown_category_are_errors(self) -> None:
        with self.assertRaises(Failure):
            self.run_main(self.dir / "nothing-here")
        (self.dir / "empty").mkdir()
        with self.assertRaises(Failure):
            self.run_main(self.dir / "empty")
        write_wav(self.dir / "a" / "x.wav")
        with self.assertRaises(Failure) as caught:
            self.run_main(self.dir / "a", category="door")
        self.assertIn("--category door", str(caught.exception))

    def test_a_file_given_twice_or_inside_a_folder_given_is_checked_once(self) -> None:
        root = self.make_set()
        good = root / "good.wav"
        found = sfx.collect([str(root), str(good), str(good)])
        self.assertEqual(len(found), 5)
        self.assertEqual([f for f, _ in found].count(good), 1)
        self.assertEqual(dict(found)[good], root)  # the first path that gives it wins
        _code, _printed = self.run_main(root, good)
        report = json.loads((self.dir / "out" / "sfx.json").read_text(encoding="utf-8"))
        self.assertEqual(len(report["files"]), 5)

    def test_the_cli_passes_its_options(self) -> None:
        args = cli.build_parser().parse_args(["sfx-check", "a", "b", "--page", "--category", "ui", "--out", "o"])
        self.assertEqual((args.paths, args.page, args.category, args.out), (["a", "b"], True, "ui", Path("o")))


class PageTest(Fixtures):
    def page(self) -> str:
        root = self.make_set()
        when = datetime(2026, 10, 7, 12, 0, tzinfo=timezone.utc)
        self.run_main(root, page=True, now=when)
        return (self.dir / "out" / "steps.html").read_text(encoding="utf-8")

    def test_one_audio_per_file_with_the_sound_inside_grouped_by_category(self) -> None:
        text = self.page()
        self.assertEqual(len(re.findall(r"<audio ", text)), 5)
        self.assertEqual(len(re.findall(r'<audio controls preload="metadata" src="data:audio/wav;base64,', text)), 4)
        self.assertEqual(len(re.findall(r'src="data:audio/ogg;base64,UklG|src="data:audio/ogg;base64,T2dn', text)), 1)
        self.assertIn("<h2>footstep (5)</h2>", text)
        self.assertNotIn("<h2>ui", text, "an empty category gets no section")
        self.assertIn("Generated 2026-10-07 12:00 UTC", text)
        self.assertIn("peak at most -1.0 dBFS", text)

    def test_numbers_failures_approve_reject_a_note_and_the_export(self) -> None:
        text = self.page()
        self.assertEqual(text.count('value="approve"'), 5)
        self.assertEqual(text.count('value="reject"'), 5)
        self.assertEqual(text.count("<textarea"), 5)
        self.assertIn("peak: peak 0.0 dBFS, over the -1.0 dBFS ceiling", text)
        self.assertIn("<td>channels</td><td>2</td>", text)
        self.assertIn('id="export"', text)
        self.assertIn("sfx-verdicts.json", text)
        self.assertIn("new Blob(", text)
        data = json.loads(re.search(r"const PAGE = (\{.*\});\n", text).group(1))  # type: ignore[union-attr]
        self.assertEqual(data["set"], "steps")
        self.assertEqual(
            sorted((Path(f["path"]).name, f["status"]) for f in data["files"]),
            [
                ("clipped.wav", "failed"),
                ("good.wav", "passed"),
                ("long.wav", "failed"),
                ("step.ogg", "header-checked"),
                ("stereo.wav", "failed"),
            ],
        )

    def test_nothing_external_no_server_no_script_or_font_from_elsewhere(self) -> None:
        text = self.page()
        for pattern in (r"https?:", r"<link", r"@import", r"@font-face", r"<script [^>]*src", r"""src=["']//""",
                        r"url\(", r"fetch\(", r"XMLHttpRequest"):
            with self.subTest(pattern=pattern):
                self.assertIsNone(re.search(pattern, text))
        self.assertEqual(text.count("<script"), 1)

    def test_a_path_cannot_close_the_script_or_break_the_markup(self) -> None:
        sound = sfx.Sound(path=self.dir / "missing.wav", shown='a</script><b x="1">.wav', kind="wav")
        text = sfx.render_page([sound], self.table, "s", "now")
        self.assertEqual(text.count("</script>"), 1)
        self.assertIn("a&lt;/script&gt;&lt;b x=&quot;1&quot;&gt;.wav", text)
        self.assertIn("<h2>no category (1)</h2>", text)

    def test_a_comment_opener_in_a_path_cannot_reach_the_script(self) -> None:
        shown = "a<!--<script>b.wav"
        sound = sfx.Sound(path=self.dir / "missing.wav", shown=shown, kind="wav")
        text = sfx.render_page([sound], self.table, "s", "now")
        script = text[text.index("<script>") + len("<script>") : text.rindex("</script>")]
        self.assertNotIn("<", script.split(";\n", 1)[0], "the embedded data holds no raw <")
        data = re.search(r"const PAGE = (\{.*?\});\n", script).group(1)
        self.assertEqual(json.loads(data)["files"][0]["path"], shown)

    def test_the_set_name_comes_from_the_one_path(self) -> None:
        self.assertEqual(sfx.set_name(["content/sfx/foot steps"]), "foot-steps")
        self.assertEqual(sfx.set_name(["a/click.wav"]), "click")
        self.assertEqual(sfx.set_name(["a", "b"]), "sfx")

    def test_a_dotted_folder_keeps_its_whole_name(self) -> None:
        dotted = self.dir / "kenney_impact-sounds.v1"
        dotted.mkdir()
        self.assertEqual(sfx.set_name([str(dotted)]), "kenney_impact-sounds.v1")
        self.assertEqual(sfx.set_name(["a/audio.wav-set"]), "audio.wav-set")
        self.assertEqual(sfx.set_name(["a/Step.OGG"]), "Step")


if __name__ == "__main__":
    unittest.main()
