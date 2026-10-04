"""`signal`: the signalling Worker's tests (tools/signal/test/, Node's own runner, no npm package; the M6 ADR E53).

They replay the shared transcripts and decoding cases in tests/fixtures/signal/ through the Worker's router and its
Durable Object code over fakes (docs/ARCHITECTURE.md §4.8). A `verify` step. The Worker itself is deployed by the
engineer (tools/signal/README.md); nothing here talks to Cloudflare.
"""

from __future__ import annotations

from pathlib import Path

from . import pins
from .common import ROOT, Failure, bad, node_bin, ok, rel, run, say, version_tuple

FOLDER = ROOT / "tools" / "signal"
TESTS = FOLDER / "test"
TIMEOUT = 120


def test_files(folder: Path = TESTS) -> list[Path]:
    """Every `*.test.js`, sorted, passed by name (as POSIX paths: Node reads its arguments as globs, where a Windows
    backslash escapes): `node --test` with a pattern that matches nothing passes."""
    return sorted(folder.glob("*.test.js"))


def main() -> int:
    say("signal")
    exe = node_bin()
    if not exe:
        raise Failure(f"node not found: install Node.js {pins.NODE_MAJOR} LTS (`doctor` prints how)")
    version = version_tuple(run([exe, "--version"], timeout=60).out)
    if version[:1] != (pins.NODE_MAJOR,):
        raise Failure(f"node is {'.'.join(map(str, version)) or '?'}, pinned {pins.NODE_MAJOR}.x (`doctor` prints how)")
    files = test_files()
    if not files:
        raise Failure(f"no *.test.js in {rel(TESTS)}")
    result = run(
        [exe, "--test", "--test-reporter=tap", *[path.relative_to(FOLDER).as_posix() for path in files]],
        timeout=TIMEOUT,
        cwd=FOLDER,
        log="signal",
    )
    if result.timed_out:
        bad(f"node --test ran over {TIMEOUT} s (log: tools/out/logs/signal.log)", result.out.rstrip())
        return 1
    if result.rc != 0:
        bad(f"node --test exited {result.rc} (log: tools/out/logs/signal.log)", result.out.rstrip())
        return 1
    # TAP's summary ("# tests 80", "# pass 80"): ASCII, unlike the spec reporter's, for a Windows console.
    summary = [line[2:] for line in result.out.splitlines() if line.startswith(("# tests ", "# pass "))]
    ok(f"node --test: {len(files)} files, " + ", ".join(summary))
    return 0
