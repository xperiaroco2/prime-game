"""prime-game task runner. Use the wrappers: tools\\run.cmd (PowerShell/cmd) or tools/run.sh (bash).

Run `tools\\run.cmd --help` for the command list.
"""

import os
import sys

if sys.version_info < (3, 11):
    sys.exit(f"The task runner needs Python 3.11+, this is {sys.version.split()[0]}. Set PYTHON_BIN.")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.dont_write_bytecode = True

# Where the hooks keep their own modules compiled (#568): gitignored, one per checkout.
HOOK_BYTECODE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "out", "pycache")
# The flags of a pyc that the import system checks against its source's hash on every import (PEP 552).
CHECKED_HASH = 0b11


def hook_main(name: str):  # noqa: ANN201 - runner.hooks.main, imported here
    """Import the hook's modules from bytecode cached in HOOK_BYTECODE (#568): compiling guard.py from source cost
    the guard about 40 ms before every shell call, more under load. The cache holds checked-hash pycs, which the
    import system compares with their source's hash, so an edit is never missed, even one that keeps the file's size
    and second (a timestamp pyc's whole check). The standard library keeps its own bytecode (imported first), and
    the runner's other modules, imported later, are compiled as before."""
    import __future__  # noqa: F401 - the standard library the hooks import, from its own bytecode
    import fnmatch  # noqa: F401
    import json  # noqa: F401
    import re  # noqa: F401

    prefix, nowrite = sys.pycache_prefix, sys.dont_write_bytecode
    sys.pycache_prefix, sys.dont_write_bytecode = HOOK_BYTECODE, False
    try:
        import runner
        from runner import hooks

        modules = [runner, hooks]
        if name == "guard":
            from runner import guard

            modules.append(guard)
    finally:
        sys.pycache_prefix, sys.dont_write_bytecode = prefix, nowrite
    for module in modules:
        if module.__file__ and module.__cached__:
            _checked_hash(module.__file__, module.__cached__)
    return hooks.main


def _checked_hash(source: str, cached: str) -> None:
    """Rewrite a module's cached pyc as a checked-hash one unless it is one already: the import system writes a
    timestamp pyc for a module it had no pyc of, and keeps a hash-based one hash-based when it recompiles it."""
    try:
        with open(cached, "rb") as handle:
            if int.from_bytes(handle.read(8)[4:8], "little") == CHECKED_HASH:
                return
    except OSError:
        pass
    import py_compile

    try:
        py_compile.compile(
            source, cfile=cached, doraise=True, invalidation_mode=py_compile.PycInvalidationMode.CHECKED_HASH
        )
    except (OSError, py_compile.PyCompileError):
        pass  # the next run compiles it again, as before #568


# A worker process of `selftest` (multiprocessing's spawn) imports this file again as __mp_main__: it must not run.
if __name__ == "__main__":
    if sys.argv[1:2] == ["hook"] and len(sys.argv) == 3:
        # Claude Code runs the guard before every shell command: skip the CLI imports (about 100 ms).
        sys.exit(hook_main(sys.argv[2])(sys.argv[2]))

    # A human's own terminal lacks the machine paths a Claude Code session gets from its settings (#55).
    from runner import machine_env

    machine_env.apply()

    from runner.cli import main

    sys.exit(main())
