"""prime-game task runner. Use the wrappers: tools\\run.cmd (PowerShell/cmd) or tools/run.sh (bash).

Run `tools\\run.cmd --help` for the command list.
"""

import os
import sys

if sys.version_info < (3, 11):
    sys.exit(f"The task runner needs Python 3.11+, this is {sys.version.split()[0]}. Set PYTHON_BIN.")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True

# A worker process of `selftest` (multiprocessing's spawn) imports this file again as __mp_main__: it must not run.
if __name__ == "__main__":
    if sys.argv[1:2] == ["hook"] and len(sys.argv) == 3:
        # Claude Code runs the guard before every shell command: skip the CLI imports (about 100 ms).
        from runner.hooks import main as hook

        sys.exit(hook(sys.argv[2]))

    # A human's own terminal lacks the machine paths a Claude Code session gets from its settings (#55).
    from runner import machine_env

    machine_env.apply()

    from runner.cli import main

    sys.exit(main())
