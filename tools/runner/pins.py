"""Pinned tool versions. One place; CI reads them with `run.py pins`.

See docs/decisions/2026-09-28-toolchain-pins.md before changing any of these.
"""

GODOT = "4.7.2"
# Prefix of `godot --version` for the official 4.7.2 stable build.
GODOT_VERSION_PREFIX = "4.7.2.stable.official"
GDTOOLKIT = "4.5.0"
GDUNIT4 = "6.2.1"
PYTHON_MIN = (3, 11)
GH_MIN = (2, 97, 0)
CLAUDE_CODE_MIN = (2, 1, 281)

ALL = {
    "godot": GODOT,
    "gdtoolkit": GDTOOLKIT,
    "gdunit4": GDUNIT4,
    "python_min": ".".join(map(str, PYTHON_MIN)),
    "gh_min": ".".join(map(str, GH_MIN)),
    "claude_code_min": ".".join(map(str, CLAUDE_CODE_MIN)),
}
