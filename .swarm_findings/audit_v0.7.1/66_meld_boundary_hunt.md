# 66 — Meld Boundary Adversarial Hunt (Rules.lua HEAD v0.7.2)

Scope: `R.DetectMelds`, `R.CompareMelds`, `R.ScoreRound` belote logic.
Refs: `Rules.lua` lines 194–256, 267–319, 629–678; `Constants.lua` lines 91–105.

## 1. SEQ5+ (6 / 7-card sequences) — CORRECT

`Rules.lua:208–225`. The run-detection loop greedily extends `j` while
`list[j+1].idx == list[j].idx + 1`, then classifies:
`runLen==3 → seq3 (20)`, `runLen==4 → seq4 (50)`, `else → seq5 (100)`.
A 6- or 7-card sequence falls into the `else` branch, gets `value =
K.MELD_SEQ5 = 100`, and is **not scaled**. Verified.
`m.len = runLen` is propagated correctly so `meldRank` orders 7-seq
above 5-seq (line 289: `lenScore = (m.len or 3) * 10`). Cosmetic
nit: `kind` is hard-coded as `"seq5"` for runs ≥ 5 (UI label may
read "Seq-5" for an actual 7-seq). Not a scoring bug.

## 2. Carré of 9s — CORRECTLY FORBIDDEN

`Constants.lua:105` — `K.CARRE_RANKS = { A=true, T=true, K=true,
Q=true, J=true }`; 9 absent. `Rules.lua:238` gates on
`K.CARRE_RANKS[rank]`, so four-9s never reaches the value branch.
Verified.

## 3. Multiple Carrés in one hand — CORRECTLY ADDITIVE

`Rules.lua:237–253` iterates `byRank` and appends one entry per
qualifying rank. `R.SumMeldValue` (line 469–473) sums all `m.value`,
so Carré-of-Aces (Sun) + Carré-of-Tens = 200 + 100 = 300 raw. OK.

## 4. Ace-Carré in HOKM — DISCREPANCY WITH PROMPT

Prompt asserts: "Ace-Carré in HOKM should be 100 (CARRE_OTHER)".
**Code disagrees.** `Rules.lua:240–244`:
```
if rank == "A" then
    if isSun then value = K.MELD_CARRE_A_SUN end
else
    value = K.MELD_CARRE_OTHER
end
```
If rank=="A" AND not Sun, `value` stays `nil`, the meld is **not
emitted**. `Constants.lua:88` explicitly states "4 of A: Hokm 0,
Sun 200". This matches Pagat-strict Saudi (CLAUDE.md confirms 9-no-
carré + Sun-special Aces). So either the prompt's expectation is
wrong, or the documented rule is wrong. **Filing as: confirm with
saudi-rules.md / video #43 before changing.** Per current docs,
code is correct.

## 5. Belote detection (K+Q trump same seat) — CORRECT

`Rules.lua:631–646`. Scans every play across all tricks, records
`kWho`/`qWho` for trump K/Q. If both set and equal, belote =
`TeamOf(kWho)`. Else `kWho = nil` (resets so cancellation gate at
line 670 short-circuits). Verified.

## 6. Belote cancellation by 100-meld — BUG: SAME-DECLARER REQUIREMENT

`Rules.lua:670–678` cancels belote ONLY when:
- `m.declaredBy == kWho` (same seat declared the ≥100 meld), AND
- `m.value >= 100`.

**Two latent bugs:**
1. Requires `m.declaredBy` to be populated by the meld-declaration
   code path. If `meldsByTeam` entries lack `declaredBy` (e.g. test
   fixtures, or a Net.lua `OnMeld` that omits the field), cancellation
   silently never fires.
2. Saudi rule "100-meld subsumes belote" reads at the **team** level
   per `saudi-rules.md` reading, but code requires the **same player**
   to hold both. Counter-example: kWho declares belote (K+Q trump);
   partner declares Carré of T (100). Same team, ≥100 meld present
   — current code does NOT cancel. Per video #32 "100-meld subsumes
   belote", this should cancel. Confirm rule scope before patching.

## 7. Tie-breaker (seq-trump beats seq-non-trump) — CORRECT

`Rules.lua:292–295`: `trumpBonus = 0.5` added to `meldRank` only for
HOKM contracts when `m.suit == contract.trump`. Bonus < 1 (smallest
non-trump increment from `topIdx` step), so trump-bonus only flips
ties on identical (length, top). Carré bonus is `+1000` so trump
bonus never lifts a sequence above a carré. Verified safe.

## Additional finding — SWEEP OVERRIDES BELOTE CANCELLATION

`Rules.lua:658–660` reassigns `belote = sweepTeam` when the K+Q
holder is on the losing side of an Al-Kaboot. Then line 670 tests
`R.TeamOf(kWho) == belote` — after override, `kWho` is on the
NON-sweep team but `belote` is now the sweep team, so the equality
fails and the 100-meld cancellation cannot fire. Probably intended
(sweeper takes everything including the +20), but worth a comment
since the sweep + 100-meld + belote interaction is non-obvious.

---

VERDICT: 2 real bugs (Issue #6 same-declarer + missing declaredBy),
1 prompt/doc mismatch (Issue #4 — code matches saudi-rules.md),
1 cosmetic (SEQ5 label for ≥6-runs).
