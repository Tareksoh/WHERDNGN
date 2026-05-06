# S-Score-10 — ApplyMeld + meldsByTeam aggregation flow

**Scope.** Verify `S.ApplyMeld` → `S.s.meldsByTeam` → `R.ScoreRound`'s
`meldA`/`meldB` end-to-end. Confirm or refute the prior summary's
"State.lua:1167-1184 drops Hokm Carré-A (X5 inert)" finding.

**Files audited (read-only):**
- `C:\CLAUDE\WHEREDNGN\State.lua` — S.ApplyMeld 1149-1189, S.GetMeldsForLocal 1930-1959
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — R.DetectMelds 251-321, R.CompareMelds 374-384, meldRank 332-362, bestMeld 364-372, R.ScoreRound 692-, R.SumMeldValue 534-538
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — K.MELD_* 91-107
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — Bot.PickMelds 3452-3462
- `C:\CLAUDE\WHEREDNGN\Net.lua` — wire dispatch 3470-3490, 4150-4157
- prior summaries: `review_v0.10.0/_phase2_xref/xref_X5_meld_coverage.md`,
  `review_v0.10.2/_track_D_redteam/D-RT-06_carre_cascade.md`,
  `review_v0.10.2/_track_G_logic/G-Logic-01_coherence.md` §7.3,
  `review_v0.10.2/REVIEW_v0.10.2_validation.md` line 61,
  `review_v0.10.2/REVIEW_v0.10.4_ship_readiness.md` line 179.

---

## 1. TL;DR

**The X5-follow-through Hokm-Carré-A drop bug DOES still exist** in
`S.ApplyMeld` at `State.lua:1167-1184`. **CONFIRMED HIGH.**

- The detect path (`R.DetectMelds`, Rules.lua:285-318) was fixed in
  v0.10.0 X5: `value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER`
  (line 308) — Hokm Carré-A correctly resolves to 100.
- The apply path (`S.ApplyMeld`, State.lua:1171-1182) was **NOT** updated.
  When `kind=="carre"`, `top=="A"`, and `s.contract.type ~= K.BID_SUN`,
  the inner `if` (line 1174) is false, no `else` exists for Hokm, and
  `value` stays `nil`. Line 1184 (`if not value then return end`) then
  silently rejects the meld — it is never inserted into
  `s.meldsByTeam[team]`.
- The downstream pipeline (`R.SumMeldValue`, `R.CompareMelds`,
  `R.ScoreRound`'s meldA/meldB / Belote-cancellation / strict-majority
  threshold) is itself **correct**. The bug is purely at the apply
  boundary; everything downstream behaves correctly given the dropped
  meld is simply absent.
- The contradiction is also encoded in code comments: `Constants.lua:94`
  says "T, K, Q, J (any contract type) **AND Carré-A in Hokm**" → 100.
  `Rules.lua:285-298` X5 fix-comment confirms Hokm Carré-A scores 100.
  `State.lua:1177` comment says the opposite: "Hokm 4-Aces: doesn't
  score (per Pagat-strict)". The State.lua comment is wrong (it's
  copy-pasted from a pre-X5 misreading) and the code matches the wrong
  comment.

Live impact: a Hokm bidder who declares 4 Aces in trick 1 silently
forfeits **100 raw / 10 game points** (×mult). This also breaks the
v0.9.0 M5 Belote-cancellation logic (Rules.lua:769-777) — the predicate
checks `meldsByTeam[belote]` for any meld with `value >= 100`; the
dropped Carré-A leaves the +20 Belote uncancelled, an additional
silent +20 raw mis-attribution.

---

## 2. ApplyMeld trace (per kind)

`S.ApplyMeld(seat, kind, suit, top, encodedCards)` at State.lua:1149.

Common preamble (lines 1150-1163):
- Trick-1-only gate: `if (#(s.tricks or {})) >= 1 then return end` (1154).
- Team lookup: `team = R.TeamOf(seat)`; ensure `s.meldsByTeam[team]` (1155-1156).
- Idempotent dedupe by `(declaredBy, kind, top, suit-normalized)` (1158-1162).
- Decode cards: `cards = C.DecodeHand(encodedCards)` (1163).

Value derivation (lines 1167-1183):
```lua
local value
if kind == "seq3" then value = K.MELD_SEQ3                -- 20
elseif kind == "seq4" then value = K.MELD_SEQ4            -- 50
elseif kind == "seq5" then value = K.MELD_SEQ5            -- 100
elseif kind == "carre" then
    if K.CARRE_RANKS[top] then                            -- T,J,Q,K,A
        if top == "A" then
            if s.contract and s.contract.type == K.BID_SUN then
                value = K.MELD_CARRE_A_SUN                -- 400
            end
            -- ★ no else → Hokm Carré-A leaves value nil
        else
            value = K.MELD_CARRE_OTHER                    -- 100 (T,J,Q,K)
        end
    end
    -- 9/8/7 carrés (not in CARRE_RANKS) drop with value=nil
end
if not value then return end                              -- 1184: silent drop
```

Insertion (1185-1188):
```lua
table.insert(s.meldsByTeam[team], {
    kind = kind, value = value, suit = nsuit,
    top = top, cards = cards, len = #cards, declaredBy = seat,
})
```

**Per-kind result table:**

| Call | top | contract.type | value branch | value | meldsByTeam updated? |
|------|-----|---------------|--------------|-------|----------------------|
| seq3 | any | any | line 1168 | 20 (K.MELD_SEQ3) | YES |
| seq4 | any | any | line 1169 | 50 (K.MELD_SEQ4) | YES |
| seq5 | any | any | line 1170 | 100 (K.MELD_SEQ5) | YES |
| carre | T/J/Q/K | any | 1179 else | 100 (K.MELD_CARRE_OTHER) | YES |
| carre | A | BID_SUN | 1175 | 400 (K.MELD_CARRE_A_SUN) | YES |
| **carre** | **A** | **BID_HOKM** | **none — value=nil** | **nil** | **NO (dropped)** |
| carre | 9/8/7 | any | none — top not in CARRE_RANKS | nil | NO (correct, doesn't score) |

**Belote (K+Q of trump) is NOT processed by ApplyMeld at all.** There's
no `kind == "belote"` branch. Belote is detected and scored exclusively
inside `R.ScoreRound` (Rules.lua:723-740) by scanning `tricks[*].plays`
for K and Q of trump played by the same seat. This is intentional —
belote scoring requires play-trace data unavailable at meld-declaration
time. K.MELD_BELOTE=20 (Constants.lua:107) is referenced only by
ScoreRound and BOT_PICKBID_BELOTE_BONUS (Constants.lua:345).

**Belote-cancellation runs at SCORE TIME, not apply time.** Rules.lua:
769-777, post-sweep override. Predicate: any meld in
`meldsByTeam[beloteOwnerTeam]` with `value >= 100` cancels the +20
Belote bonus. Team-level (v0.9.0 M5 fix), not player-level.

---

## 3. meldsByTeam aggregation (R.ScoreRound)

`R.ScoreRound(tricks, contract, meldsByTeam)` at Rules.lua:692.

**Sum step** (lines 711-712):
```lua
local meldA = R.SumMeldValue(meldsByTeam.A)   -- sum of all m.value
local meldB = R.SumMeldValue(meldsByTeam.B)   -- in the team's array
```
`R.SumMeldValue` (Rules.lua:534-538) is a trivial accumulator over
`m.value or 0`. Both teams' totals are computed.

**Best-meld verdict** (line 791):
```lua
local meldVerdict = R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)
local effMeldA = (meldVerdict == "A") and meldA or 0
local effMeldB = (meldVerdict == "B") and meldB or 0
```

**Strict-majority threshold check** (lines 794-797): bidder's total
includes ONLY the meld-winner team's melds + the belote owner's +20.
This is per-Saudi-rule winner-takes-all even at the threshold gate
(NOT just at scoring time) — important because asymmetric meld values
(seq3=20 vs seq4=50, or trump-tie-break) would flip the threshold if
both sides summed naively.

**Final scoring branches** (lines 845-893):
- `sweepTeam` (Al-Kaboot): meldPoints[sweepTeam] = meld of sweeper, other = 0.
- `outcome_kind == "fail"`: BOTH teams keep their own melds (meldPoints.A=meldA, meldPoints.B=meldB). Per Saudi rule "مشروعي لي ومشروعك لك" — failed-contract penalty is the handTotal qaid only; melds are NOT confiscated. Comment at lines 856-867 documents the v0.4.3 audit fix.
- `outcome_kind == "take"` (rule 4-10 doubled-tie inversion): same as fail — both sides keep their melds; only the qaid handTotal flips to bidder.
- `outcome_kind == "make"` (line 885-892): **winner-takes-all melds**. `R.CompareMelds(meldsByTeam.A, meldsByTeam.B, contract)` decides; loser's melds drop to 0.

**So the answer is nuanced**: it's NOT pure winner-takes-all in all
branches. It's:
- **made**: winner-takes-all (per Pagat-strict; saudi-rules.md aligned)
- **failed/taken**: each team keeps own melds (Saudi-specific carve-out)

---

## 4. R.CompareMelds correctness

`R.CompareMelds(meldsA, meldsB, contract)` at Rules.lua:374-384, plus
helpers `bestMeld` (364-372) and `meldRank` (332-362).

`meldRank(m, contract)` returns:
- **Carré branch** (333-352): `1000 + m.value + rankBonus`. The `+1000`
  base ensures any carré beats any sequence regardless of values.
  `rankBonus = TrickRank(top..probeSuit) * 0.01` provides the
  carré tie-break: when two carrés have equal raw value (e.g. K-carré
  vs J-carré, both 100), the higher-trick-rank top wins. In Hokm,
  if probeSuit is the trump, J/9/A trump ordering kicks in, so a
  trump-J carré would sit above a non-trump-J carré — **but four-of-a-rank
  carrés don't have a "suit" so this only matters at carré-vs-carré
  comparison and the trump-bonus naturally weights J > 9 > A > T > K > Q
  in Hokm via TrickRank.**
- **Sequence branch** (354-361): `len*10 + topIdx + trumpBonus`.
  - `len*10`: 5+seq=50, seq4=40, seq3=30 → longer beats shorter.
  - `+ topIdx`: A=8, K=7, Q=6, J=5, T=4, 9=3, 8=2, 7=1 → higher top
    wins on equal length.
  - `+ trumpBonus = 0.5` if Hokm and `m.suit == contract.trump`. Small
    enough not to flip carré-vs-sequence (carré base is 1000), and
    not to flip seq4-vs-seq3 (length step is 10), but breaks ties
    between equal-length-equal-top sequences in Hokm.

**Hierarchy verification (per saudi-rules.md "Best-meld hierarchy"):**

| Rule | Where checked | Verdict |
|------|---------------|---------|
| Carré beats sequence at any value | base 1000 vs ≤50ish for sequences | ✓ PASS (Rules.lua:352 vs 354-361) |
| Higher carré value wins | carré branch `+ m.value` | ✓ PASS (line 352) |
| Carré tie-break by trick-rank top | `rankBonus = TrickRank * 0.01` | ✓ PASS (340-351) |
| Longer sequence wins | `len*10` weight | ✓ PASS (354) |
| Equal-length: higher top wins | `+ topIdx` | ✓ PASS (355) |
| Trump-suit sequence beats non-trump (Hokm only) | `+0.5 trumpBonus` | ✓ PASS (357-360) |

`R.CompareMelds` itself (374-384):
- Both teams empty → `"tie"`.
- One side empty → other wins.
- Otherwise compare `meldRank(bestA)` vs `meldRank(bestB)`. Strict
  greater-than for "A"/"B"; equal → `"tie"`.

---

## 5. Tied melds — Pagat strictness

When both teams have a Carré-J (value=100, top=J) in Hokm:
- Each team's `bestMeld` returns the J-carré with `meldRank = 1000 + 100 + (TrickRank(JS) * 0.01)`.
- `TrickRank` for J of trump in Hokm is the highest (rank 8). Both
  teams' best-meld would compute the same probeSuit bonus (since the
  carré's `m.suit` is nil → fallback to "S"; both teams get the same
  ".rankBonus"). So `meldRank` is **exactly equal** → `R.CompareMelds`
  returns `"tie"`.
- In `R.ScoreRound` made-branch (line 890-892): `meldVerdict == "tie"`
  → neither `meldPoints.A = meldA` nor `meldPoints.B = meldB` fires
  → **both teams' melds drop to 0** in the made-contract case.
- In failed/taken branches: each team keeps own (lines 870-871, 883-884).

This matches saudi-rules.md "Best-meld hierarchy" tied case (Pagat
"neither scores" reading), but ONLY in the made branch. Note that
strict-majority threshold check (lines 791-797) also zeroes both
teams' melds in the tied case (effMeldA=0, effMeldB=0) — so a tie
removes the meld contribution from the threshold determination too,
consistent with the made-branch outcome.

---

## 6. Concrete repro for the Hokm Carré-A drop bug

**Setup:**
- 4-player Hokm contract, bidder = seat 1 (team A), trump = "S".
- Seat 1 deals into a hand containing all 4 Aces.
- Trick 1 begins; before any plays, bot/UI/wire calls
  `S.ApplyMeld(1, "carre", "", "A", encodedAceHand)`.

**Step-by-step trace through State.lua:1149-1189:**

1. Line 1154: `#s.tricks` = 0, gate passes.
2. Line 1155: `team = "A"`.
3. Line 1156: ensure `s.meldsByTeam.A`.
4. Lines 1158-1162: dedupe loop — no prior matching meld → continues.
5. Line 1163: `cards = {AS, AH, AD, AC}`.
6. Line 1167: `value = nil` (declared local).
7. Line 1168 `kind == "seq3"`? No.
8. Line 1169 `kind == "seq4"`? No.
9. Line 1170 `kind == "seq5"`? No.
10. Line 1171 `kind == "carre"`? **YES**.
11. Line 1172 `K.CARRE_RANKS[top]`? `K.CARRE_RANKS["A"] == true` → YES.
12. Line 1173 `top == "A"`? YES.
13. Line 1174 `s.contract.type == K.BID_SUN`? `"HOKM" == "SUN"` → **NO**.
14. Line 1175 NOT executed. **No `else` branch exists for Hokm-A** — comment line 1177 says "Hokm 4-Aces: doesn't score (per Pagat-strict)".
15. Line 1184 `if not value`? `not nil` → true → **`return`** silently.
16. Line 1185 `table.insert` NEVER FIRES.

**Result**: `s.meldsByTeam.A` does NOT include the Carré-A.

**Downstream consequences:**

a. `R.SumMeldValue(meldsByTeam.A)` returns 0 instead of 100.
b. `R.CompareMelds`: if team B has any meld at all (even a seq3=20),
   B wins the meld comparison; team A loses meld points. If neither
   has any other meld, returns "tie" — A still gets 0.
c. Strict-majority threshold (Rules.lua:791-797): bidder lost 100 raw
   meld value. With ×mult applied, this is 10 game points (×1) up to
   40 gp (×4 Foured) the bidder should have earned.
d. **Belote-cancellation predicate (Rules.lua:769-777) fails**: if the
   bidder also has K+Q of trump in hand, the bidder's team would have
   2 Belote (Belote=20) PLUS the Carré-A (100) — the ≥100 meld should
   cancel the Belote per Saudi "100-meld subsumes belote". With the
   Carré-A absent from `meldsByTeam[belote]`, the predicate sees no
   ≥100 meld → Belote stands → silent **+20 raw** over-attribution.

**Caller graph confirming all paths converge on this bug:**

| Caller site | Why it hits ApplyMeld | Bug active? |
|-------------|----------------------|-------------|
| `Net.lua:1410` `_OnMeld` (peer broadcast) | Wire receive → ApplyMeld | YES |
| `Net.lua:2415` `LocalMeld` (local UI button) | Player clicks meld → ApplyMeld | YES |
| `Net.lua:3485` MaybeRunBot (bot pre-play) | Bot.PickMelds → loop ApplyMeld | YES |
| `Net.lua:4153` AFK auto-declare (AFK during trick 1) | Bot.PickMelds → loop ApplyMeld | YES |
| `Net.lua:407` rejoin replay | Replay frame → _OnMeld → ApplyMeld | YES |

Every funnel passes `(seat, kind, suit, top, encodedCards)` and
ApplyMeld re-derives the value; the pre-computed `m.value` returned
by `R.DetectMelds` is **not propagated** through ApplyMeld's signature.

**Probability**: ~1.92% per round for any single hand to hold all 4
Aces (`C(4,4)*C(28,4)/C(32,8)` ≈ 0.0192). Over a multi-round
match, this fires often enough that long-running bot tournaments
would visibly under-score Hokm bidders by ~10 gp / round when it
fires. The bug is silent — no error, no log warning.

**Fix (one-liner mirror of Rules.lua:307-308):**
```lua
if top == "A" then
    if s.contract and s.contract.type == K.BID_SUN then
        value = K.MELD_CARRE_A_SUN
    else
        value = K.MELD_CARRE_OTHER         -- ← add this else
    end
else
    value = K.MELD_CARRE_OTHER
end
```
And update the misleading comment at line 1177 ("Hokm 4-Aces: doesn't
score") to match canonical Saudi rule (videos #32 + #38: scores 100).

---

## 7. Bugs found

### F1 (HIGH, CONFIRMED) — `S.ApplyMeld` drops Hokm Carré-A
- **Location**: `State.lua:1167-1184` (specifically lines 1173-1182).
- **Symptom**: Hokm bidder declaring 4-Aces silently forfeits 100 raw
  meld points (≈10-40 gp depending on multiplier).
- **Cause**: missing `else` branch for Hokm-A; v0.10.0 X5 fix was
  applied to `R.DetectMelds` but not to the parallel value-derivation
  in `S.ApplyMeld`.
- **Cascade**: also breaks v0.9.0 M5 Belote-cancellation predicate
  (the absent ≥100 meld leaves +20 Belote uncancelled).
- **Code/comment contradiction**: Constants.lua:94 explicitly says
  Hokm-A scores 100; Rules.lua:285-298 fix-comment confirms it;
  State.lua:1177 comment says the opposite. Comment is wrong.
- **Fix**: 1-line `else value = K.MELD_CARRE_OTHER` to mirror
  `R.DetectMelds` Rules.lua:307-311.
- **Test gap**: no integration test exercises `S.ApplyMeld` with
  `(kind="carre", top="A", contract.type=BID_HOKM)`. Existing
  `test_rules.lua` Section E only covers `R.DetectMelds`.

### F2 (LOW, observation) — comment at State.lua:1177 misleading
Comment says "Hokm 4-Aces: doesn't score (per Pagat-strict)" but the
v0.10.0 X5 review explicitly cites videos #32 line 245 + #38 line 61
that Saudi convention scores 4-Aces in Hokm at 100 (same as other
carrés). Misleading comment likely contributed to the X5 fix
missing this site.

### F3 (LOW, defensive) — value re-derivation duplicated
`S.ApplyMeld` re-derives the meld value rather than using the
pre-computed `m.value` returned by `R.DetectMelds`. Per
D-RT-06_carre_cascade.md §279-282, a cleaner design would have
`R.DetectMelds` write `m.value` once and `S.ApplyMeld` accept it
verbatim from the caller (or via a shared helper `R.MeldValue(kind,
top, contract)`). The current duplication is the structural reason
why the X5 fix had to be applied twice; it was applied to the detect
site only.

### Aggregation pipeline (R.SumMeldValue / R.CompareMelds / R.ScoreRound)
**No bugs found.** Downstream logic is consistent with Pagat-strict
Saudi rules, the v0.9.0 M5 fix, and the failed/taken-branch carve-out
that preserves each team's own melds. Trump-bonus sequences (Hokm
only), carré tie-break by top trick-rank, made-branch winner-takes-all,
and tied-meld zeroing in both threshold and scoring all behave
correctly — they just operate on a `meldsByTeam` table that is itself
missing entries due to F1.

---

## Cross-reference back to swarm
- `B-State-03 F1` ApplyMeld confirms identical finding; same line range.
- `D-RT-06_carre_cascade.md` Issue 1 — same finding with caller-graph and Belote-cancellation interaction expanded.
- `G-Logic-01 §7.3` ApplyMeld coherence — same finding.
- `REVIEW_v0.10.2_validation.md` line 61 — independently verified HIGH.
- `REVIEW_v0.10.4_ship_readiness.md` line 179 — flagged for v0.10.4 fix; not yet shipped at audit time (HEAD = v0.10.2).
