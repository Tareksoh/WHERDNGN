#!/usr/bin/env python3
"""
run_asymmetric.py  —  Asymmetric-deal playtest fixture runner.

Drives test_asymmetric_metrics.lua via lupa. Same pattern as
run_baseline.py but biases the deal so the bidder gets a
known strong-Hokm trump pattern (J+9 / J+9+A / J+9+A+T of trump).

Usage:
    python tests/run_asymmetric.py
    python tests/run_asymmetric.py --verbose

Output: .swarm_findings/bot_asymmetric_metrics.json
Exit codes: 0 success, 1 harness failure, 2 setup error.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def lua_to_python(obj):
    """
    Recursively convert a lupa Lua table to plain Python types.
    """
    if obj is None:
        return None
    if isinstance(obj, (bool, int, float, str)):
        return obj
    if not hasattr(obj, 'keys'):
        return obj

    try:
        keys = list(obj.keys())
    except Exception:
        return str(obj)

    if not keys:
        return {}

    try:
        int_keys = sorted([k for k in keys if isinstance(k, int)])
        if int_keys and int_keys == list(range(1, len(int_keys) + 1)):
            return [lua_to_python(obj[k]) for k in int_keys]
    except Exception:
        pass

    return {str(k): lua_to_python(obj[k]) for k in keys}


def run_harness(here: str, addon_root: str, verbose: bool):
    try:
        import lupa
    except ImportError:
        print("error: lupa not installed. Run: pip install lupa", file=sys.stderr)
        return None

    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().WHEREDNGN_TESTS_ROOT = addon_root.replace("\\", "/")
    rt.globals().TEST_VERBOSE = verbose

    lua_file = os.path.join(here, "test_asymmetric_metrics.lua")
    with open(lua_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except lupa.LuaError as e:
        print(f"\nLua error in test_asymmetric_metrics.lua:\n  {e}", file=sys.stderr)
        return None

    raw = rt.globals().ASYMMETRIC_RESULTS
    if raw is None:
        print("error: harness did not produce ASYMMETRIC_RESULTS", file=sys.stderr)
        return None

    return lua_to_python(raw)


def main(argv):
    flags = [a for a in argv if a.startswith("-")]
    verbose = "--verbose" in flags or "-v" in flags

    here = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))

    print("Running asymmetric-deal playtest fixture …")
    results = run_harness(here, addon_root, verbose)
    if results is None:
        return 1

    print("\n=== Summary (per bias level) ===")
    header = (
        f"{'Bias':<10} {'Config':<22} {'Mode':<8} "
        f"{'Bel':>6} {'Tri':>6} {'4':>6} {'Ghw':>6} {'Sw':>6} "
        f"{'AvgA':>7} {'AvgB':>7} {'Winner':<6}"
    )
    print(header)
    print("-" * len(header))

    bias_order = ["moderate", "strong", "elite"]
    config_order = [
        "all_basic", "all_advanced", "all_m3lm", "all_master",
        "mixed_basic_master", "mixed_m3lm_master",
    ]
    for bias in bias_order:
        for cfg in config_order:
            for mode in ("natural", "forced"):
                key = f"{bias}/{cfg}__{mode}"
                r = results.get(key)
                if not r:
                    continue
                print(
                    f"{bias:<10} {cfg:<22} {mode:<8} "
                    f"{r.get('bel_rate', 0):>6.2f} "
                    f"{r.get('triple_rate', 0):>6.2f} "
                    f"{r.get('four_rate', 0):>6.2f} "
                    f"{r.get('gahwa_rate', 0):>6.2f} "
                    f"{r.get('sweep_rate', 0):>6.2f} "
                    f"{r.get('avg_gp_delta_A', 0):>7.1f} "
                    f"{r.get('avg_gp_delta_B', 0):>7.1f} "
                    f"{r.get('game_winner', '?'):<6}"
                )

    output = {
        "meta": {
            "harness":       "tests/test_asymmetric_metrics.lua",
            "runner":        "tests/run_asymmetric.py",
            "rounds_per_tournament": 100,
            "description": (
                "Asymmetric-deal playtest fixture. Bidder seat (random per "
                "seed) gets J+9 (moderate), J+9+A (strong), or J+9+A+T (elite) "
                "of trump; defenders dealt random over remainder. Tests whether "
                "the v0.5 escalation thresholds (Bel/Triple/Four/Gahwa) fire "
                "under realistic asymmetric clustering — the structural "
                "limitation in symmetric baselines was that defenders never "
                "cleared BOT_BEL_TH because random dealing under-represents "
                "bidder-strong / defender-Ace clusters that humans see."
            ),
        },
        "results": results,
    }

    out_dir = Path(addon_root) / ".swarm_findings"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "bot_asymmetric_metrics.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, default=str)

    print(f"\nJSON output written to: {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
