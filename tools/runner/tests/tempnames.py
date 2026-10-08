"""Windows 8.3 short names of the temp folder, for the tests of issue #542 (no test case in this module)."""

import os
import tempfile
import unittest
from pathlib import Path

from runner.common import IS_WINDOWS


def short_path(path: str | Path) -> str | None:
    """The Windows 8.3 short form of an existing path (`C:\\Users\\XPERIA~1\\...`, GetShortPathNameW), or None where
    the OS gives none: not Windows, or a volume that makes no 8.3 names (issue #542)."""
    if not IS_WINDOWS:
        return None
    import ctypes

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    buffer = ctypes.create_unicode_buffer(32768)
    written = kernel32.GetShortPathNameW(str(path), buffer, len(buffer))
    return buffer.value if 0 < written < len(buffer) and "~" in buffer.value else None


def short_temp(case: unittest.TestCase) -> tuple[str, str]:
    """A fresh folder with a long name in the temp folder, removed after the test: (its long path, its 8.3 short
    path); the test is skipped where the OS gives no short name."""
    tmp = tempfile.TemporaryDirectory(prefix="prime-game-long-name-")
    case.addCleanup(tmp.cleanup)
    full = os.path.realpath(tmp.name)
    short = short_path(full)
    if short is None:
        case.skipTest("no 8.3 short names here (not Windows, or a volume with 8.3 name creation off)")
    return full, short
