#!/usr/bin/env python3
"""
Runner for tests/test_rules.lua.

Drives the harness via lupa (Python's Lua bindings) so the addon's
pure-logic tests run without a system Lua install.

Usage:
    python tests/run.py
    python tests/run.py --verbose   # print every PASS in addition to FAILs

Exits 0 on full pass, 1 on any failure, 2 on harness/setup error.
"""

from __future__ import annotations

import os
import sys


def main(argv: list[str]) -> int:
    verbose = "--verbose" in argv or "-v" in argv

    try:
        import lupa
    except ImportError:
        print("error: lupa not installed. Run: pip install lupa", file=sys.stderr)
        return 2

    here = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))
    test_file = os.path.join(here, "test_rules.lua")
    if not os.path.isfile(test_file):
        print(f"error: {test_file} not found", file=sys.stderr)
        return 2

    rt = lupa.LuaRuntime(unpack_returned_tuples=True)

    # Pass the addon root + verbose flag to the Lua side.
    rt.globals().WHEREDNGN_TESTS_ROOT = addon_root.replace("\\", "/")
    rt.globals().TEST_VERBOSE = verbose

    with open(test_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except lupa.LuaError as e:
        print(f"Lua error: {e}", file=sys.stderr)
        return 2

    results = rt.globals().TEST_RESULTS
    if results is None:
        print("error: harness did not produce TEST_RESULTS", file=sys.stderr)
        return 2

    failed = int(results.failed or 0)
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
