#!/usr/bin/env python3
"""
run_bel_decision_quality.py — Bel decision quality calibration runner.

Drives test_bel_decision_quality.lua via lupa (same pattern as run.py /
run_baseline.py), then serialises the Lua results to:

    .swarm_findings/bel_decision_quality.json

Usage:
    python tests/run_bel_decision_quality.py
    python tests/run_bel_decision_quality.py --verbose

Exits 0 on success, 1 on harness failure, 2 on setup error.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def lua_to_python(obj):
    """Recursively convert a lupa Lua table to plain Python."""
    try:
        import lupa  # noqa: F401
    except ImportError:
        raise

    if obj is None:
        return None
    if isinstance(obj, (bool, int, float, str)):
        return obj
    if not hasattr(obj, "keys"):
        return obj
    try:
        keys = list(obj.keys())
    except Exception:
        return str(obj)
    if not keys:
        return {}
    # 1-indexed integer sequence → list
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

    lua_file = os.path.join(here, "test_bel_decision_quality.lua")
    with open(lua_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except lupa.LuaError as e:
        print(f"\nLua error in test_bel_decision_quality.lua:\n  {e}", file=sys.stderr)
        return None

    raw = rt.globals().BEL_QUALITY_RESULTS
    if raw is None:
        print("error: harness did not produce BEL_QUALITY_RESULTS", file=sys.stderr)
        return None

    return lua_to_python(raw)


def derive_recommendation(results_by_th: dict) -> dict:
    """
    Pick the optimal threshold by maximising F1 = 2*P*R/(P+R),
    i.e. best harmonic mean of precision and recall.
    Falls back to lowest false_bel_rate as tiebreaker.
    """
    best_th = None
    best_f1 = -1.0
    best_fb = 1.0

    for th_str, r in results_by_th.items():
        p = r.get("precision", 0) or 0
        rec = r.get("recall", 0) or 0
        fb = r.get("false_bel_rate", 1) or 1
        f1 = (2 * p * rec / (p + rec)) if (p + rec) > 0 else 0
        if f1 > best_f1 or (f1 == best_f1 and fb < best_fb):
            best_f1 = f1
            best_th = th_str
            best_fb = fb

    return {
        "optimal_threshold": best_th,
        "best_f1": round(best_f1, 4),
        "rationale": (
            f"Threshold {best_th} maximises F1={best_f1:.3f} "
            f"(harmonic mean of precision and recall)."
        ),
    }


def main(argv: list[str]) -> int:
    flags   = [a for a in argv if a.startswith("-")]
    verbose = "--verbose" in flags or "-v" in flags

    try:
        import lupa  # noqa: F401
    except ImportError:
        print("error: lupa not installed. Run: pip install lupa", file=sys.stderr)
        return 2

    here       = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))

    print("Running Bel decision quality harness (1000 hands × 3 thresholds) …")
    results = run_harness(here, addon_root, verbose)
    if results is None:
        return 1

    print("\n=== Bel Decision Quality Summary ===")
    header = (
        f"{'TH':>4}  {'Fire%':>7}  {'FalseBel%':>10}  "
        f"{'MissedBel%':>11}  {'Precision%':>11}  {'Recall%':>8}"
    )
    print(header)
    print("-" * len(header))

    for th_str in sorted(results.keys(), key=lambda x: int(x)):
        r = results[th_str]
        print(
            f"{th_str:>4}  "
            f"{r.get('fire_rate', 0)*100:>7.1f}  "
            f"{r.get('false_bel_rate', 0)*100:>10.1f}  "
            f"{r.get('missed_bel_rate', 0)*100:>11.1f}  "
            f"{r.get('precision', 0)*100:>11.1f}  "
            f"{r.get('recall', 0)*100:>8.1f}"
        )

    recommendation = derive_recommendation(results)
    print(f"\nRecommendation: {recommendation['rationale']}")

    output = {
        "meta": {
            "harness":     "tests/test_bel_decision_quality.lua",
            "runner":      "tests/run_bel_decision_quality.py",
            "n_hands":     1000,
            "description": (
                "Empirical Bel decision quality for Bot.PickDouble. "
                "Each hand: bidder (seat 1) holds J+9 of a random trump suit "
                "plus 6 random cards; defender (seat 2, TeamB) has a random 8-card hand. "
                "Jitter is pinned to 0 so threshold comparisons are clean. "
                "Outcome ground-truth comes from a full 8-trick heuristic rollout "
                "at Basic tier. false_bel_rate = P(def loses | Bel fired). "
                "missed_bel_rate = P(no fire | def would win)."
            ),
        },
        "results":        results,
        "recommendation": recommendation,
    }

    out_dir  = Path(addon_root) / ".swarm_findings"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "bel_decision_quality.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, default=str)

    print(f"\nJSON output written to: {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
