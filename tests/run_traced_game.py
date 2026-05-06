#!/usr/bin/env python3
"""
Runner for the v0.5.1 traced-game test harness.

Usage:
    python tests/run_traced_game.py
    python tests/run_traced_game.py --verbose

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

    here       = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))
    test_file  = os.path.join(here, "test_v0.5_traced_game.lua")

    print("========== traced_game  (v0.5.1 bot behaviour) ==========")

    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().WHEREDNGN_TESTS_ROOT = addon_root.replace("\\", "/")
    rt.globals().TEST_VERBOSE = verbose

    with open(test_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except lupa.LuaError as e:
        print(f"\nLua error:\n  {e}", file=sys.stderr)
        return 2

    results = rt.globals().TEST_RESULTS
    if results is None:
        print("error: test did not produce TEST_RESULTS", file=sys.stderr)
        return 2

    passed = int(results.passed or 0)
    failed = int(results.failed or 0)
    print("")
    print(f"========== Total: {passed} passed, {failed} failed ==========")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
