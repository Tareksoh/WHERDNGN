#!/usr/bin/env python3
"""
run_baseline.py  —  Extended baseline metrics runner for WHEREDNGN.

Drives test_baseline_metrics.lua via lupa (same pattern as run.py),
then serialises the Lua results table to JSON and writes it to:

    .swarm_findings/bot_baseline_metrics.json

(relative to the addon root, i.e. C:/CLAUDE/WHEREDNGN/.swarm_findings/)

Usage:
    python tests/run_baseline.py
    python tests/run_baseline.py --verbose

Exits 0 on success, 1 on harness failure, 2 on setup error.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def lua_to_python(obj):
    """
    Recursively convert a lupa Lua table to a plain Python dict/list/scalar.
    Lua tables that are 1-indexed integer sequences become lists; all others
    become dicts.
    """
    try:
        import lupa
    except ImportError:
        raise

    if obj is None:
        return None
    if isinstance(obj, (bool, int, float, str)):
        return obj

    # lupa wraps Lua tables as a _LuaTable proxy with .keys() / .values().
    if not hasattr(obj, 'keys'):
        return obj

    try:
        keys = list(obj.keys())
    except Exception:
        return str(obj)

    if not keys:
        return {}

    # Is it a 1-indexed integer sequence?
    try:
        int_keys = sorted([k for k in keys if isinstance(k, int)])
        if int_keys and int_keys == list(range(1, len(int_keys) + 1)):
            return [lua_to_python(obj[k]) for k in int_keys]
    except Exception:
        pass

    return {str(k): lua_to_python(obj[k]) for k in keys}


def run_harness(here: str, addon_root: str, verbose: bool) -> dict | None:
    try:
        import lupa
    except ImportError:
        print("error: lupa not installed. Run: pip install lupa", file=sys.stderr)
        return None

    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().WHEREDNGN_TESTS_ROOT = addon_root.replace("\\", "/")
    rt.globals().TEST_VERBOSE = verbose

    lua_file = os.path.join(here, "test_baseline_metrics.lua")
    with open(lua_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except lupa.LuaError as e:
        print(f"\nLua error in test_baseline_metrics.lua:\n  {e}", file=sys.stderr)
        return None

    raw = rt.globals().BASELINE_RESULTS
    if raw is None:
        print("error: harness did not produce BASELINE_RESULTS", file=sys.stderr)
        return None

    return lua_to_python(raw)


def main(argv: list[str]) -> int:
    flags   = [a for a in argv if a.startswith("-")]
    verbose = "--verbose" in flags or "-v" in flags

    here       = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))

    print("Running extended baseline metrics harness …")
    results = run_harness(here, addon_root, verbose)
    if results is None:
        return 1

    # Produce a clean summary of key metrics.
    print("\n=== Summary ===")
    header = (
        f"{'Config':<36} {'Mode':<8} {'Bel':>6} {'Tri':>6} "
        f"{'4':>6} {'Ghw':>6} {'Sw':>6} {'AvgA':>7} {'AvgB':>7} {'Winner':<6}"
    )
    print(header)
    print("-" * len(header))

    configs_order = [
        "all_basic", "all_advanced", "all_m3lm", "all_master",
        "mixed_basic_master", "mixed_m3lm_master",
    ]
    for cfg in configs_order:
        for mode in ("natural", "forced"):
            key = f"{cfg}__{mode}"
            r = results.get(key)
            if not r:
                continue
            print(
                f"{cfg:<36} {mode:<8} "
                f"{r.get('bel_rate', 0):>6.2f} "
                f"{r.get('triple_rate', 0):>6.2f} "
                f"{r.get('four_rate', 0):>6.2f} "
                f"{r.get('gahwa_rate', 0):>6.2f} "
                f"{r.get('sweep_rate', 0):>6.2f} "
                f"{r.get('avg_gp_delta_A', 0):>7.1f} "
                f"{r.get('avg_gp_delta_B', 0):>7.1f} "
                f"{r.get('game_winner', '?'):<6}"
            )

    # Enrich results with a metadata block.
    output = {
        "meta": {
            "harness":       "tests/test_baseline_metrics.lua",
            "runner":        "tests/run_baseline.py",
            "rounds_per_tournament": 100,
            "description":   (
                "Empirical baseline metrics for WHEREDNGN bot tiers. "
                "Each tournament runs 100 rounds without ResetStyle between "
                "rounds so the M3lm/Master style ledger accumulates. "
                "natural = bots decide escalation normally; "
                "forced = PickDouble/PickTriple always fire to guarantee "
                "Bel+Triple in every round so Four/Gahwa exposure is measurable."
            ),
        },
        "results": results,
    }

    out_dir = Path(addon_root) / ".swarm_findings"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "bot_baseline_metrics.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, default=str)

    print(f"\nJSON output written to: {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
