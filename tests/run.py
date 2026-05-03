#!/usr/bin/env python3
"""
Runner for the WHEREDNGN test harnesses.

Drives the addon's pure-logic tests via lupa (Python's Lua bindings) so
the tests run without a system Lua install.

Usage:
    python tests/run.py
    python tests/run.py --verbose      # print every PASS, not just FAILs
    python tests/run.py rules          # run only test_rules.lua
    python tests/run.py state_bot      # run only test_state_bot.lua

Exits 0 on full pass, 1 on any failure, 2 on harness/setup error.
"""

from __future__ import annotations

import os
import sys


HARNESSES = [
    ("rules",     "test_rules.lua",     "Rules.lua / Cards.lua / Constants.lua"),
    ("state_bot", "test_state_bot.lua", "State.lua / Bot.lua"),
]


def run_one(here: str, addon_root: str, lua_file: str, verbose: bool) -> tuple[int, int]:
    """Run a single Lua harness in a fresh runtime. Returns (passed, failed)."""
    import lupa

    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().WHEREDNGN_TESTS_ROOT = addon_root.replace("\\", "/")
    rt.globals().TEST_VERBOSE = verbose

    test_file = os.path.join(here, lua_file)
    with open(test_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except lupa.LuaError as e:
        print(f"\nLua error in {lua_file}:\n  {e}", file=sys.stderr)
        return (0, -1)

    results = rt.globals().TEST_RESULTS
    if results is None:
        print(f"error: {lua_file} did not produce TEST_RESULTS", file=sys.stderr)
        return (0, -1)

    return (int(results.passed or 0), int(results.failed or 0))


def main(argv: list[str]) -> int:
    args = [a for a in argv if not a.startswith("-")]
    flags = [a for a in argv if a.startswith("-")]
    verbose = "--verbose" in flags or "-v" in flags

    try:
        import lupa  # noqa: F401
    except ImportError:
        print("error: lupa not installed. Run: pip install lupa", file=sys.stderr)
        return 2

    here = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))

    # Filter harnesses by name args.
    selected = HARNESSES
    if args:
        wanted = set(args)
        selected = [h for h in HARNESSES if h[0] in wanted]
        if not selected:
            print(f"error: no harness matches {args}; available: {[h[0] for h in HARNESSES]}",
                  file=sys.stderr)
            return 2

    total_pass, total_fail = 0, 0
    for name, lua_file, label in selected:
        print(f"\n========== {name}  ({label}) ==========")
        passed, failed = run_one(here, addon_root, lua_file, verbose)
        if failed < 0:
            return 2  # harness error
        total_pass += passed
        total_fail += failed

    print("")
    print(("========== Total: %d passed, %d failed ==========")
          % (total_pass, total_fail))
    return 0 if total_fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
