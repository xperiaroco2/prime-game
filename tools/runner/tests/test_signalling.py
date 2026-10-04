"""`signal` (#368): the signalling Worker's tests under the pinned Node, and doctor's Node check."""

import contextlib
import io
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from runner import doctor, pins, signalling
from runner.common import Failure, Result


def result(rc: int = 0, out: str = "") -> Result:
    return Result(rc, out, False, 0.1)


class SignalTest(unittest.TestCase):
    def run_main(self, *results: Result, node: str | None = "/bin/node") -> tuple[int, str, list[list[str]]]:
        calls: list[list[str]] = []

        def fake_run(cmd: list[str], **kwargs: object) -> Result:
            calls.append(cmd)
            return results[len(calls) - 1]

        out = io.StringIO()
        with (
            mock.patch.object(signalling, "node_bin", return_value=node),
            mock.patch.object(signalling, "run", side_effect=fake_run),
            contextlib.redirect_stdout(out),
        ):
            rc = signalling.main()
        return rc, out.getvalue(), calls

    def test_runs_every_test_file_by_its_posix_path_and_reports_the_counts(self) -> None:
        version = result(out=f"v{pins.NODE_MAJOR}.1.2\n")
        rc, text, calls = self.run_main(version, result(out="TAP version 13\n# tests 80\n# pass 80\n# fail 0\n"))
        self.assertEqual(rc, 0)
        names = [path.relative_to(signalling.FOLDER).as_posix() for path in signalling.test_files()]
        self.assertIn("test/router.test.js", names)
        self.assertEqual(calls[1], ["/bin/node", "--test", "--test-reporter=tap", *names])
        self.assertIn("tests 80, pass 80", text)

    def test_a_failing_run_fails_with_its_output(self) -> None:
        version = result(out=f"v{pins.NODE_MAJOR}.0.0")
        rc, text, _calls = self.run_main(version, result(1, "not ok 3 - flow_join.json replays\n"))
        self.assertEqual(rc, 1)
        self.assertIn("not ok 3 - flow_join.json replays", text)

    def test_another_major_or_no_node_stops_it(self) -> None:
        with self.assertRaisesRegex(Failure, "pinned"):
            self.run_main(result(out="v22.22.0"))
        with self.assertRaisesRegex(Failure, "node not found"):
            self.run_main(node=None)

    def test_no_test_file_is_a_failure_not_a_pass(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            self.assertEqual(signalling.test_files(Path(folder)), [])
            with mock.patch.object(signalling, "test_files", return_value=[]), self.assertRaisesRegex(Failure, "no"):
                self.run_main(result(out=f"v{pins.NODE_MAJOR}.0.0"))


class DoctorNodeTest(unittest.TestCase):
    def check(self, node: str | None, version: str = "") -> tuple[int, str]:
        out = io.StringIO()
        with (
            mock.patch.object(doctor, "node_bin", return_value=node),
            mock.patch.object(doctor, "run", return_value=result(out=version)),
            contextlib.redirect_stdout(out),
        ):
            doc = doctor.Doctor()
            doc.node()
        return doc.failures, out.getvalue()

    def test_the_pinned_major_passes(self) -> None:
        failures, text = self.check("/bin/node", f"v{pins.NODE_MAJOR}.3.0\n")
        self.assertEqual(failures, 0)
        self.assertIn(f"Node.js {pins.NODE_MAJOR}.3.0", text)

    def test_another_major_or_none_fails_with_the_fix(self) -> None:
        for node, version in (("/bin/node", "v22.22.0"), (None, "")):
            failures, text = self.check(node, version)
            self.assertEqual(failures, 1)
            self.assertIn("winget install OpenJS.NodeJS.LTS", text)

    def test_the_pin_is_one_release_of_its_major(self) -> None:
        self.assertEqual(pins.NODE.split(".")[0], str(pins.NODE_MAJOR))
        self.assertIn(f"v{pins.NODE}/node-v{pins.NODE}-linux-x64.tar.xz", pins.NODE_LINUX_URL)
        self.assertRegex(pins.NODE_LINUX_SHA256, r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
