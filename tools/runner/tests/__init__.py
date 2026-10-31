import os

from runner.common import long_temp

# Before any test: an 8.3 short TEMP (C:\Users\XPERIA~1\...) in its long form, as tools/run.py does (issue #542), so
# `python -m unittest runner.tests.<module>` compares the paths git and Path.resolve give with tempfile's.
long_temp()

# Every git the tests start (the temp repos included) runs with no auto-gc and no auto-maintenance: a background gc
# writing into a temp repo's .git while force_rmtree deletes it raised ENOTEMPTY (#1142). Git reads these from the
# environment, so no test needs its own `git config`.
if "GIT_CONFIG_COUNT" not in os.environ:
    os.environ.update(
        GIT_CONFIG_COUNT="2",
        GIT_CONFIG_KEY_0="gc.auto", GIT_CONFIG_VALUE_0="0",
        GIT_CONFIG_KEY_1="maintenance.auto", GIT_CONFIG_VALUE_1="false",
    )  # fmt: skip

# Gaming mode (#1505) reads one machine-local file; the engineer turns it on while he plays. The tests never see his
# switch: they point it at a file that is never written (a test that turns it on points it at its own temp file).
# runner.tests.test_focus reads the real switch, before this line, to keep its opt-in window run off while he plays.
REAL_GAMING_FILE = os.environ.get("PRIME_GAMING_FILE", "")
_HERE = os.path.dirname(os.path.abspath(__file__))
os.environ["PRIME_GAMING_FILE"] = os.path.join(_HERE, "no-gaming-mode", "never.json")
