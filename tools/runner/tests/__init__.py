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
