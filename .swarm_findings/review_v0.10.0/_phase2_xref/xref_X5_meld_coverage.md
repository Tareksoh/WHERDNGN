# X5: Meld coverage completeness

**Audit version**: v0.10.0
**Phase**: Phase 2 — Cross-reference
**Files inspected**:
- `C:\CLAUDE\WHEREDNGN\Constants.lua` (K.MELD_*, K.CARRE_RANKS, K.MULT_*)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` (R.DetectMelds, R.CompareMelds, R.ScoreRound)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_I_melds_swa_scoring.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_L_pdf_secrets_doubling.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R5_carre_a_sun.md`

---

## Per-meld verification

| Meld | Source value (raw) | Code constant | Detection logic (Rules.lua) | Bug? |
|---|---|---|---|---|
| **Carré-A in Hokm** | 100 (per #32 L243-245, #38 L59-61, Source I §A7) | _none_ — silently dropped | L240-242: `if rank == "A" then if isSun then value = K.MELD_CARRE_A_SUN end` — no `else` branch for Hokm; `value` stays `nil`; no meld emitted | **CRITICAL BUG**: Hokm Carré-A is silently dropped. Player loses entire 100-meld (= 10 nq + bidder-threshold contribution). |
| **Carré-A in Sun** | 400 raw (per #32 L235-249, #38 L27-31, Source I §A7) | `K.MELD_CARRE_A_SUN = 200` (Constants.lua L95) | L240-242: `if rank == "A" then if isSun then value = K.MELD_CARRE_A_SUN end` — emits 200 raw | **BUG (R5 already filed)**: stored 200 → mult×2 → 400 raw → /10 = 40 nq. Should be 80 nq (400 raw /5 in Sun). Off by factor of 2. |
| **Carré-T (10s)** | 100 (Source I §A8) | `K.MELD_CARRE_OTHER = 100` | L242-243: rank ≠ "A" branch sets `value = K.MELD_CARRE_OTHER`; emits 100 raw | OK |
| **Carré-K** | 100 (Source I §A8) | `K.MELD_CARRE_OTHER = 100` | Same as Carré-T branch | OK |
| **Carré-Q** | 100 (Source I §A8) | `K.MELD_CARRE_OTHER = 100` | Same as Carré-T branch | OK |
| **Carré-J** (any suit) | 100 (per Source I §A8 + §A10 — explicit "no special bonus") | `K.MELD_CARRE_OTHER = 100` | Same as Carré-T branch (no trump-conditional fork) | OK — does NOT match CLAUDE.md remark "J carré only counts trump-implicit". CLAUDE.md remark appears wrong; sources confirm Carré-J = 100 regardless of trump. Tie-break in `meldRank` (L274-286) pushes trump-J carré above non-trump-J carré on equal value, but value itself is 100 in either case. |
| **Carré-9** | excluded (Source I §A9, two-source confirmation) | `K.CARRE_RANKS = { A, T, K, Q, J }` (L105) | L238 `if count == 4 and K.CARRE_RANKS[rank]` filters out 9/8/7 | OK |
| **Carré-8** | excluded (Source I §A9) | not in `K.CARRE_RANKS` | Filtered same as 9 | OK |
| **Carré-7** | excluded (Source I §A9) | not in `K.CARRE_RANKS` | Filtered same as 9 | OK |
| **Tierce (3-seq)** | 20 (Source I §A2, A15) | `K.MELD_SEQ3 = 20` | L216 `if runLen == 3 then kind, value = "seq3", K.MELD_SEQ3` | OK |
| **Quarte (4-seq)** | 50 (Source I §A4) | `K.MELD_SEQ4 = 50` | L217 `elseif runLen == 4 then kind, value = "seq4", K.MELD_SEQ4` | OK |
| **Quinte (5+ seq)** | 100 (Source I §A5, A6) | `K.MELD_SEQ5 = 100` | L218 `else kind, value = "seq5", K.MELD_SEQ5` — note: ≥5 all collapse to seq5 because `runLen >= 3` opens a single while-loop and all run-lens 5/6/7/8 fall into the `else` arm. | OK — matches video #32 L145-172 ("6/7/8 cards = still 100"). Quinte constant **is** used for any 5+ run. |
| **سيكل (9-8-7 tierce)** | 20 (same as any tierce, Source I §A15) | _no special constant_ — falls through SEQ3 | The 9-8-7 sequence has rank indices 3-2-1 (`K.RANK_INDEX["7"]=1, ["8"]=2, ["9"]=3`); detected as a runLen=3 same-suit run → emits seq3 = 20 raw | OK — sykl is just a name; same value as tierce. Code correctly treats it as a SEQ3. |
| **Belote (K+Q trump)** | 20, multiplier-immune (Source I §A11, Source L L22-L24) | `K.MELD_BELOTE = 20` | Detection at R.ScoreRound L669-684 (scans played cards for who held trump-K and trump-Q); cancellation at L713-721 (≥100 meld on holder's team kills belote — TEAM-level per v0.9.0 M5 fix); applied at L861-865 AFTER multiplier (immune) | OK — TEAM-level cancellation correctly implemented per v0.9.0 M5 fix. Multiplier-immunity correctly implemented. |
| **Sun Belote (ملكي)** | NOT confirmed in any source (Source I §A14, D2) | _no constant_ | R.ScoreRound L669: `if contract.type == K.BID_HOKM and contract.trump then` — Belote scoring is gated on Hokm only. Sun never scores Belote. | OK — code correctly does NOT score K+Q in Sun. The "Sun Belote" was an earlier extraction artifact; matches Source I/L silence. |
| **Bidder strict-majority** | strict > (Source I §C13, Source L L40) | gated by R.ScoreRound L750-780 | L750: `if bidderTotal > oppTotal then outcome_kind = "make"` (strict-greater); equal → `outcome_kind = "fail"` (per L778) unless escalation tie inverts (rule 4-10 L770-779) | OK for unescalated. Strict-majority enforced (81/162 in Hokm fails bidder; 65/130 in Sun fails bidder). |

---

## Bugs found / missing

### Bug 1 (NEW — primary finding): Carré-A in Hokm silently dropped

**Location**: `C:\CLAUDE\WHEREDNGN\Rules.lua` lines 240-242:

```lua
if rank == "A" then
    if isSun then value = K.MELD_CARRE_A_SUN end
else
    value = K.MELD_CARRE_OTHER
end
```

**The bug**: When `rank == "A"` AND `isSun == false` (i.e., Hokm contract), the inner `if isSun then ... end` does nothing. `value` stays `nil`. The block at L245-251 then has `if value then ... end` which suppresses the meld emission entirely. **The player's Hokm Carré-A is dropped — no meld appears in `R.DetectMelds`'s output.**

**Source verdict**: Two sources unambiguously call for Carré-A in Hokm = 100 raw:
- Video #32 L243-245: "في الحكم لو جاتك اربع عكك تعتبر ميه تعامل معامله الميه" — "In Hokm, four Aces count as 100, treated like a 100-meld."
- Video #38 L59-61: "اربع عكك في الحكم ما تقولوا 400 تقول 100 ... تعامل معامله الميه ونفس نقاط المياه" — "Four Aces in Hokm — don't say 400; say 100. Treated like a 100-meld with the same point value."
- Source I §A7 explicit: "in Hokm, four Aces = 100 raw points = 10 nq"
- Reaudit R5 §5 "Side-finding (out of scope but flag)" already identified this as a separate bug.

**Impact**:
- Hokm contract: player's 100-meld disappears from declaration phase.
  - Misses 10 nq (100 raw /10).
  - Removes their entry from `R.CompareMelds` (could give opp's tierce/quarte the win when player should have won with their 100).
  - Removes their meld points from the bidder-strict-majority threshold check (`bidderTotal` calc, L738-741) — could flip a make/fail outcome.
- Triggers the **Belote-cancellation interaction** improperly: in Hokm with K+Q-of-trump holder also holding Carré-A, the ≥100 cancellation should kill their +20 Belote. With the meld dropped, Belote stays — silent over-scoring of +20 raw.
- Affects Hokm + escalation: with mult ×4 (Four), missing 100 raw becomes 400 raw lost = 40 nq.

**Required fix** (NOT applied — audit only):

```lua
if rank == "A" then
    if isSun then value = K.MELD_CARRE_A_SUN
    else value = K.MELD_CARRE_OTHER end          -- Hokm Carré-A = 100 raw
else
    value = K.MELD_CARRE_OTHER
end
```

Or equivalently flatten to: any rank in `K.CARRE_RANKS` defaults to `K.MELD_CARRE_OTHER`; Aces in Sun get bumped to `K.MELD_CARRE_A_SUN`.

---

### Bug 2 (R5 already filed): Carré-A in Sun off by factor of 2

**Status**: Documented in `reaudit_R5_carre_a_sun.md` — `K.MELD_CARRE_A_SUN = 200` should be `400`. Independently corroborated by all source extractions. Not re-litigated here.

---

### Bug 3 (potential — flagged): CLAUDE.md "Carré-J trump-implicit" remark contradicts sources

**CLAUDE.md** says: "J carré only counts trump-implicit" (in user's prompt summary). Source I §A10 explicitly contradicts this: "There is NO Saudi-special elevated value for four Jacks. The video does NOT distinguish Carré J as larger than Carré K/Q/10."

**Code aligns with sources**: `K.MELD_CARRE_OTHER = 100` for J in any contract; no trump-conditional fork. The `meldRank` tie-break at L267-287 only adjusts ordering (so trump-J carré beats non-trump-J carré on equal raw value via the `rk * 0.01` rankBonus), but the raw value is 100 either way.

**Recommendation**: this is a CLAUDE.md / docs cleanup item, NOT a code bug. The code is correct.

---

### Bug 4 (NOT a bug — verified safe): Sun Belote (ملكي) absent from code

**Code**: R.ScoreRound L669 gates Belote detection on `contract.type == K.BID_HOKM`. Sun never gets a +20 K+Q bonus.

**Source verdict**:
- Source I §A11, A14, D2: NEITHER #32, #35, #38, NOR #43 mention a Sun-Belote. Single-source absence.
- Source L: PDF 05 (what_is_baloot) defines Belote as the K+Q-of-trump bonus *to balance Hokm vs Sun*; logically a Sun-Belote is incoherent because Sun has no trump. Source L L37 derives the same conclusion.

**Verdict**: Code correctly omits Sun Belote. The user's prompt question 5 ("Should this be in code at all?") — **NO. Current behavior is correct.**

---

### Bug 5 (NOT a bug — verified): Quinte (K.MELD_SEQ5) is correctly used

**Question 7 from prompt**: "is K.MELD_SEQ5 = 100 used? When?"

**Verified**: Yes. R.DetectMelds L218 emits `seq5` for any run of length ≥5 (the `else` arm of the `if runLen == 3 / elseif runLen == 4 / else`). The constant is used. A 5-, 6-, 7-, or 8-card same-suit run all emit a single seq5 meld worth 100 raw — correct per Source I §A6.

---

### Bug 6 (NOT a bug — verified): سيكل (9-8-7) detection

**Question 8 from prompt**: "does the tierce detection correctly identify 9-8-7 as a 20-point sequence?"

**Verified**: Yes. `K.RANK_INDEX = { ["7"]=1, ["8"]=2, ["9"]=3, ... }` — so 9-8-7 same-suit = consecutive indices 3, 2, 1 → after `table.sort` (L206), they become 1, 2, 3 → runLen = 3 → seq3 = 20 raw. The 9-8-7 case is just a SEQ3 like any other tierce; sykl name has no code-side effect, which matches Source I §A15 ("سيكل is purely a NAME, not a different score").

---

### Bug 7 (NOT a bug — verified): Bidder strict-majority

**Question 6 from prompt**: "does R.ScoreRound correctly fail bidder at exactly 81/162 in Hokm? At 65/130 in Sun?"

**Verified**: Yes (with one caveat). R.ScoreRound L750:
```lua
if bidderTotal > oppTotal then outcome_kind = "make"
elseif bidderTotal < oppTotal then outcome_kind = "fail"
else
    -- tie branch — unescalated → "fail" (defenders win)
```

For exactly tied raw points (e.g., 81/81 in Hokm with handTotal=162 split, or 65/65 in Sun with handTotal=130 split), the unescalated path falls through L774 (`highest = "none"`) and L778 (`outcome_kind = "fail"`). **Bidder fails on exact tie** — correct strict-majority semantics. Confirmed by Source I §C15, Source L L40, CLAUDE.md ("Bidder fails on tied 81/162").

**Caveat**: the tie branch has rule-4-10 inversion when escalation is active (L775-776). With Bel/Four (defender's escalation), tied → `outcome_kind = "take"` — bidder takes the count instead. That's per Saudi 4-10 rule and is INDEPENDENT of the strict-majority question (it's an escalation-tie-flip, not an unescalated 81/81). So the strict-majority answer for unescalated rounds is "yes, bidder fails on tie" — correct.

---

### Bug 8 (NOT a bug — verified): Belote cancellation team-level

**Question 4 from prompt**: "does v0.9.0 M5 fix correctly cancel Belote on 100-meld holder's team?"

**Verified**: Yes. R.ScoreRound L713-721:
```lua
if belote and kWho then
    local list = (meldsByTeam and meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```

Cancellation iterates the **team's** declared meld list (`meldsByTeam[belote]`), not the K+Q-holder's individual list. Correctly cancels Belote when ANY team member declared a ≥100 meld (sequence-of-5, Carré-T/K/Q/J, or Carré-A in Sun). Aligns with Source L L24 + comment block L707-712.

**Sweep override at L696-698** correctly re-routes Belote to the sweeping team BEFORE running cancellation; if the sweeper has a ≥100 meld, their Belote (now reassigned) gets cancelled. If the original K+Q-holder swept and had a ≥100 meld, same result. All combinations correct.

---

## Confidence

**HIGH** on all findings.

- **Bug 1 (Hokm Carré-A dropped)**: arithmetic + control-flow trace in `R.DetectMelds` — `value` stays `nil` for the Hokm-A path, so no meld is appended. Two source-side videos (#32, #38) explicitly state the rule. The R5 reaudit already flagged this as a "side-finding worth a separate spawn." This audit confirms it's a real, independent bug.
- **Bug 2 (Sun Carré-A factor of 2)**: already filed in R5 reaudit; confirmed here unchanged.
- All other rows in the per-meld table verified by direct code inspection of the cited line numbers in Constants.lua and Rules.lua, cross-checked against Source I §A1-A18 and Source L L22-L24, L40.

### Severity ranking

1. **Bug 1 (Hokm Carré-A dropped)** — HIGH severity. Affects every Hokm round where a player happens to hold all 4 Aces. Drops 100 raw (= 10 nq baseline; 40 nq under Four ×4). Also breaks Belote cancellation: holder's missing 100-meld means their Belote is no longer cancelled, silent +20 over-scoring.
2. **Bug 2 (Sun Carré-A 200 → should be 400)** — HIGH severity. Affects every Sun round where a player holds 4 Aces. Off by 2× (40 nq instead of 80 nq baseline).
3. **Bug 3 (CLAUDE.md J-carré remark)** — LOW severity, docs-only. Code is correct.

Bugs 1 and 2 should be addressed together — they're sibling cases of the Carré-A logic and the fix shape is symmetric.
