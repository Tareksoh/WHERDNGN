#!/usr/bin/env python3
"""
run_multiseed_tournament.py — Multi-seed tournament runner for WHEREDNGN.

Drives test_multiseed_metrics.lua 5 times (one per seed) via lupa, collects
all results, computes mean + stddev per (config, mode) cell, then writes:

    .swarm_findings/v0.5_multi_seed_tournament.json

Seeds: 1, 12345, 999, 7, 42  (5 total)
Configs × modes: 6 × 2 = 12 cells
Total: 60 tournaments × 100 rounds each

Usage:
    python tests/run_multiseed_tournament.py
    python tests/run_multiseed_tournament.py --verbose

Exits 0 on success, 1 on harness failure, 2 on setup error.
"""

from __future__ import annotations

import json
import math
import os
import sys
import time
from pathlib import Path

SEEDS = [1, 12345, 999, 7, 42]

CONFIGS_ORDER = [
    "all_basic", "all_advanced", "all_m3lm", "all_master",
    "mixed_basic_master", "mixed_m3lm_master",
]

# Metric fields to aggregate across seeds.
AGGREGATE_FIELDS = [
    "bel_rate", "triple_rate", "four_rate", "gahwa_rate",
    "sweep_rate", "avg_gp_delta_A", "avg_gp_delta_B",
    "rounds_played", "win_rounds_A", "win_rounds_B",
]


def lua_to_python(obj):
    """Recursively convert lupa Lua table to plain Python dict/list/scalar."""
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

    try:
        int_keys = sorted([k for k in keys if isinstance(k, int)])
        if int_keys and int_keys == list(range(1, len(int_keys) + 1)):
            return [lua_to_python(obj[k]) for k in int_keys]
    except Exception:
        pass

    return {str(k): lua_to_python(obj[k]) for k in keys}


def run_one_seed(here: str, addon_root: str, seed: int, verbose: bool) -> dict | None:
    """Execute the Lua harness for a single seed value. Returns the results dict."""
    try:
        import lupa
    except ImportError:
        print("error: lupa not installed. Run: pip install lupa", file=sys.stderr)
        return None

    rt = lupa.LuaRuntime(unpack_returned_tuples=True)
    rt.globals().WHEREDNGN_TESTS_ROOT = addon_root.replace("\\", "/")
    rt.globals().MULTI_SEED_VALUE     = seed
    rt.globals().TEST_VERBOSE         = verbose

    lua_file = os.path.join(here, "test_multiseed_metrics.lua")
    with open(lua_file, "r", encoding="utf-8") as f:
        src = f.read()

    try:
        rt.execute(src)
    except Exception as e:
        print(f"\nLua error (seed={seed}):\n  {e}", file=sys.stderr)
        return None

    raw = rt.globals().MULTISEED_RESULTS
    if raw is None:
        print(f"error: harness produced no MULTISEED_RESULTS (seed={seed})", file=sys.stderr)
        return None

    return lua_to_python(raw)


def mean_stddev(values: list[float]) -> tuple[float, float]:
    n = len(values)
    if n == 0:
        return 0.0, 0.0
    m = sum(values) / n
    if n == 1:
        return m, 0.0
    variance = sum((v - m) ** 2 for v in values) / (n - 1)
    return m, math.sqrt(variance)


def winner_from_counts(counts: dict[str, int]) -> str:
    """Return the plurality winner label from a {'A':n, 'B':n, 'tie':n} dict."""
    return max(counts, key=lambda k: counts[k])


def aggregate(all_seed_results: dict[int, dict]) -> dict:
    """
    Build per-(config, mode) aggregation across seeds.
    Returns dict keyed by "config__mode" with mean/stddev for each metric
    plus winner_counts and modal_winner.
    """
    agg = {}
    for cfg in CONFIGS_ORDER:
        for mode in ("natural", "forced"):
            key = f"{cfg}__{mode}"
            per_seed = []
            for seed, seed_results in all_seed_results.items():
                r = seed_results.get(key)
                if r:
                    per_seed.append((seed, r))

            if not per_seed:
                continue

            cell: dict = {
                "config": cfg,
                "escalation_mode": mode,
                "n_seeds": len(per_seed),
                "seeds_run": [s for s, _ in per_seed],
            }

            # Numeric aggregates.
            for field in AGGREGATE_FIELDS:
                vals = [r.get(field, 0) for _, r in per_seed]
                m, sd = mean_stddev(vals)
                cell[f"{field}_mean"]   = round(m, 4)
                cell[f"{field}_stddev"] = round(sd, 4)

            # Winner distribution (categorical).
            winner_counts: dict[str, int] = {"A": 0, "B": 0, "tie": 0}
            for _, r in per_seed:
                w = r.get("game_winner", "tie")
                winner_counts[w] = winner_counts.get(w, 0) + 1
            cell["winner_counts"]  = winner_counts
            cell["modal_winner"]   = winner_from_counts(winner_counts)
            cell["winner_consistency"] = round(
                max(winner_counts.values()) / len(per_seed), 4
            )

            # Per-seed winner list for direct inspection.
            cell["per_seed_winners"] = {
                str(s): r.get("game_winner", "?") for s, r in per_seed
            }
            cell["per_seed_rounds"] = {
                str(s): r.get("rounds_played", 0) for s, r in per_seed
            }

            agg[key] = cell

    return agg


def variance_ranking(agg: dict) -> list[dict]:
    """Return cells sorted by bel_rate_stddev descending (noisiest measurements first)."""
    rows = []
    for key, cell in agg.items():
        rows.append({
            "cell": key,
            "bel_rate_stddev":    cell.get("bel_rate_stddev", 0),
            "sweep_rate_stddev":  cell.get("sweep_rate_stddev", 0),
            "rounds_played_stddev": cell.get("rounds_played_stddev", 0),
            "winner_consistency": cell.get("winner_consistency", 1),
        })
    # Sort by winner_consistency ascending (least consistent = noisiest) then by bel stddev.
    rows.sort(key=lambda r: (r["winner_consistency"], -r["bel_rate_stddev"]))
    return rows


def check_mixed_basic_master_forced(agg: dict) -> dict:
    """
    Specifically examine mixed_basic_master__forced across seeds.
    In the v0.5.1 single-seed run, winner was 'A' (basic beats master under forced escalation).
    We check if this holds across all 5 seeds.
    """
    cell = agg.get("mixed_basic_master__forced", {})
    if not cell:
        return {"error": "cell not found"}

    pw = cell.get("per_seed_winners", {})
    consistent = all(w == "A" for w in pw.values())
    return {
        "per_seed_winners":   pw,
        "modal_winner":       cell.get("modal_winner"),
        "winner_consistency": cell.get("winner_consistency"),
        "all_seeds_agree":    consistent,
        "assessment": (
            "ROBUST — basic wins under forced escalation across all seeds."
            if consistent else
            "DEAL-SPECIFIC — result varies by seed; v0.5.1 finding is not stable."
        ),
    }


def check_v051_robustness(agg: dict) -> dict:
    """
    Evaluate whether the v0.5.1 single-seed results are statistically robust.
    Focus points from the original JSON:
    - mixed_basic_master__forced: winner was A (suspicious — basic beating master)
    - all_master__natural: winner was B (expected master advantage)
    - all_basic__natural: winner was A (marginal, 155 vs 148)
    """
    def cell_summary(key: str) -> dict:
        c = agg.get(key, {})
        return {
            "modal_winner":       c.get("modal_winner", "?"),
            "winner_consistency": c.get("winner_consistency", 0),
            "winner_counts":      c.get("winner_counts", {}),
            "rounds_played_mean": c.get("rounds_played_mean", 0),
            "rounds_played_stddev": c.get("rounds_played_stddev", 0),
        }

    return {
        "mixed_basic_master__forced":  cell_summary("mixed_basic_master__forced"),
        "mixed_basic_master__natural": cell_summary("mixed_basic_master__natural"),
        "all_master__natural":         cell_summary("all_master__natural"),
        "all_master__forced":          cell_summary("all_master__forced"),
        "all_basic__natural":          cell_summary("all_basic__natural"),
        "mixed_m3lm_master__forced":   cell_summary("mixed_m3lm_master__forced"),
    }


def main(argv: list[str]) -> int:
    flags   = [a for a in argv if a.startswith("-")]
    verbose = "--verbose" in flags or "-v" in flags

    here       = os.path.abspath(os.path.dirname(__file__))
    addon_root = os.path.abspath(os.path.join(here, ".."))

    print(f"Multi-seed tournament: {len(SEEDS)} seeds × 12 cells × 100 rounds")
    print(f"Seeds: {SEEDS}")
    print()

    t0 = time.time()
    all_seed_results: dict[int, dict] = {}

    for seed in SEEDS:
        print(f"--- Seed {seed} ---")
        seed_results = run_one_seed(here, addon_root, seed, verbose)
        if seed_results is None:
            print(f"Harness failed for seed={seed}", file=sys.stderr)
            return 1
        all_seed_results[seed] = seed_results
        print()

    elapsed = time.time() - t0
    print(f"All seeds complete in {elapsed:.1f}s")
    print()

    # Aggregate.
    agg = aggregate(all_seed_results)

    # Variance ranking.
    ranked = variance_ranking(agg)

    # Specific checks.
    mbm_forced_check = check_mixed_basic_master_forced(agg)
    robustness       = check_v051_robustness(agg)

    # Print summary table.
    print("=== Multi-Seed Summary (mean ± stddev across 5 seeds) ===")
    hdr = (
        f"{'Cell':<38} {'BelMn':>6} {'BelSD':>6} "
        f"{'SwMn':>6} {'SwSD':>6} {'RdsMn':>6} {'RdsSD':>5} "
        f"{'Modal':>6} {'Cons':>5}"
    )
    print(hdr)
    print("-" * len(hdr))
    for cfg in CONFIGS_ORDER:
        for mode in ("natural", "forced"):
            key = f"{cfg}__{mode}"
            c = agg.get(key)
            if not c:
                continue
            print(
                f"{key:<38} "
                f"{c['bel_rate_mean']:>6.3f} {c['bel_rate_stddev']:>6.3f} "
                f"{c['sweep_rate_mean']:>6.3f} {c['sweep_rate_stddev']:>6.3f} "
                f"{c['rounds_played_mean']:>6.1f} {c['rounds_played_stddev']:>5.1f} "
                f"{c['modal_winner']:>6} {c['winner_consistency']:>5.2f}"
            )

    print()
    print("=== Variance Ranking (noisiest cells first) ===")
    for i, row in enumerate(ranked[:6], 1):
        print(
            f"  {i}. {row['cell']:<38} consistency={row['winner_consistency']:.2f} "
            f"bel_sd={row['bel_rate_stddev']:.3f}"
        )

    print()
    print("=== mixed_basic_master__forced cross-seed check ===")
    for k, v in mbm_forced_check.items():
        print(f"  {k}: {v}")

    # Build output.
    output = {
        "meta": {
            "harness":      "tests/test_multiseed_metrics.lua",
            "runner":       "tests/run_multiseed_tournament.py",
            "seeds":        SEEDS,
            "rounds_per_tournament": 100,
            "n_configs":    len(CONFIGS_ORDER),
            "n_modes":      2,
            "total_tournaments": len(SEEDS) * len(CONFIGS_ORDER) * 2,
            "elapsed_seconds": round(elapsed, 2),
            "description": (
                "Multi-seed tournament to test statistical robustness of v0.5.1 "
                "baseline metrics. Each (config, mode) cell is run 5 times with "
                "different deal-seed sequences. mean/stddev computed over seeds. "
                "winner_consistency = fraction of seeds that agree on the winner."
            ),
        },
        "aggregated": agg,
        "variance_ranking": ranked,
        "v051_robustness_check": robustness,
        "mixed_basic_master_forced_check": mbm_forced_check,
        "per_seed_raw": {
            str(s): results for s, results in all_seed_results.items()
        },
    }

    out_dir  = Path(addon_root) / ".swarm_findings"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_file = out_dir / "v0.5_multi_seed_tournament.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(output, f, indent=2, ensure_ascii=False, default=str)

    print(f"\nJSON output written to: {out_file}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
