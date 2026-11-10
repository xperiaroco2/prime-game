"""A clock reading on which a file's float time and the float clock disagree, for the import-stamp tests of #1357,
#1575 and #1576 (no test case in this module).

On Windows, CPython 3.12 (the nightly Windows job's Python) reads time.time() from the same system time NTFS dates a
file with, which moves once a timer tick (1 to 16 ms, counted in 100 ns units), so a file written in the tick of a
later time.time() carries exactly that reading. CPython turns the two into floats by different formulas: os.stat's
st_mtime as `seconds + nanoseconds * 1e-9`, time.time() as `float(nanoseconds) / 1e9`. About one reading in eight they
round apart by one unit in the last place (0.24 us), and the file looks newer than the clock read after it. These
helpers pin the clock on such a reading.
"""

import os
import time
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from unittest import mock


def reading_that_rounds_apart(path: Path) -> int:
    """A clock reading (ns since the epoch, a multiple of NTFS's 100 ns, a second ago) for which `path`, dated at it,
    has an st_mtime above the time.time() of the same reading. Leaves `path` dated at it."""
    start = (time.time_ns() - 10**9) // 100 * 100
    for step in range(10_000):
        when = start + 100 * step
        os.utime(path, ns=(when, when))
        if path.stat().st_mtime > when / 1e9:
            return when
    raise AssertionError(f"no reading in the 1 ms after {start} ns rounds apart (os.stat's float formula changed?)")


@contextmanager
def clock_reads(when: int) -> Iterator[None]:
    """Stop the clock at `when` (ns): time.time() gives what CPython 3.12 gives for that reading on Windows (the
    float(nanoseconds) / 1e9 of _PyTime_AsSecondsDouble), time.time_ns() the reading itself."""
    with mock.patch("time.time", return_value=when / 1e9), mock.patch("time.time_ns", return_value=when):
        yield
