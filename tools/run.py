"""prime-game task runner. Use the wrappers: tools\\run.cmd (PowerShell/cmd) or tools/run.sh (bash).

Run `tools\\run.cmd --help` for the command list.
"""

import sys
from pathlib import Path

if sys.version_info < (3, 11):
    sys.exit(f"The task runner needs Python 3.11+, this is {sys.version.split()[0]}. Set PYTHON_BIN.")

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.dont_write_bytecode = True

from runner.cli import main  # noqa: E402

sys.exit(main())
