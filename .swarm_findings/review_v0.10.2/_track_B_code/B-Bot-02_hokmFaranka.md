# B-Bot-02 — Hokm Faranka exception block in `pickFollow` (v0.10.2)

**Reviewer:** Code-track agent
**File reviewed:** `C:\CLAUDE\WHEREDNGN\Bot.lua` lines **2857-3022** (the Hokm Faranka block — line numbers in prompt referenced post-v0.10.0 X3 but block has shifted to 2857-3022 in v0.10.2 due to other inserts)
**Cross-refs read:**
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X3_faranka.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_C_faranka.md`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\decision-trees.md` Section 10 (lines 242-264)
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\h1eEwSezzic_04_faranka_in_hokm.ar-orig.srt` (Video 04 spot-checked; coverage already in source_C_faranka.md row-level)
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` v0.10.0 + v0.10.2 entries
- `C:\CLAUDE\WHEREDNGN\Bot.lua` 2880-3022 (block proper) + 2584-2613 (Sun Faranka, for cross-check on F-17/F-30 question)
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` 580-898 (rolloutValue + BM.PickPlay for delegation question)
- `C:\CLAUDE\WHEREDNGN\State.lua` 1349-1381 (HighestUnplayedRank trump-aware order)

---

## Findings

### F1 — All 6 source-C exceptions: wired vs unwired status (v0.10.2)

| Source-C ID | Code label | File:line | Wired? | Notes |
|---|---|---|---|---|
| **F-24** Type-3 cabotage (Kabout-pursuit, side-suit only) | n/a | not present in `pickFollow` Hokm-Faranka block | **NOT WIRED** | Partial sweep-track detection in `pickLead` (~Bot.lua:1581-1589 per X3) but no cross-wire here. Confirmed unchanged since X3 audit. CHANGELOG carries it as deferred. |
| **F-26** Type-1 J-preserve (9-with-RHO) | n/a | not present | **NOT WIRED** | Requires seat-order-aware "9 location" inference (CCW position of 9-of-trump). Confirmed unchanged. |
| **F-27** Weak trump (only 2 trumps) | code's "Exception #2" | `Bot.lua:2900-2902` | **WIRED** | `myTrumpCount == 2 and onBidderTeam`. v0.9.2 #49 added the bidder-team gate. |
| **F-28** 9-mardoofa while J live | n/a | not present | **NOT WIRED** | Code's 9-branch only fires when J is dead (= F-29). Confirmed unchanged. |
| **F-29** J-dead 9-branch | code's "Exception #3" | `Bot.lua:2922-2932` | **WIRED** | `S.HighestUnplayedRank(contract.trump) == "9"` + `hold9 = true` + (post-v0.10.0 X3) `onBidderTeam`. |
| **F-30** Bidder + opp trump void | code's "Exception #4" | `Bot.lua:2943-2955` | **WIRED (predicate b only)** | `onBidderTeam` (relaxed v0.10.0 X3 from strict bidder-self) + per-opp `Bot._memory[s2].void[contract.trump]`. Predicate (a) "covet Kabout" still NOT WIRED (depends on `partner_tricks_won >= 6` ledger that doesn't exist). Hand-shape A+K-of-side precondition from Source C also NOT enforced; X3 flagged as low-severity. |

**3 wired** (F-27, F-29, F-30b) — gating verified below in F2.
**3 unwired** (F-24, F-26, F-28) — confirmed deferred per CHANGELOG and X3.

---

### F2 — Bidder-team gate completeness (post-v0.10.0 #2 + #3 onBidderTeam, #4 relaxed)

`onBidderTeam = (contract.bidder and R.TeamOf(contract.bidder) == R.TeamOf(seat))` is computed **once** at `Bot.lua:2898-2899` and reused for all three triggers. Gating audit:

| Trigger | Predicate | Gated? |
|---|---|---|
| #2 (F-27) | `myTrumpCount == 2 and onBidderTeam` | **YES** |
| #3 (F-29) | `not farankaTriggered and onBidderTeam and S.HighestUnplayedRank(...) == "9"` + hold9 | **YES (v0.10.0 X3 fix)** |
| #4 (F-30b) | `not farankaTriggered and onBidderTeam` + per-opp void check | **YES (relaxed v0.10.0 X3 from `bidder == seat` to `onBidderTeam`)** |

**Other paths to enable Faranka in this block?** Searched the entire 2880-3022 region:
- `farankaTriggered = true` appears at 3 sites (2901, 2931, 2954). All three sit inside `onBidderTeam`-gated `if`.
- `farankaTriggered = false` appears at 4 sites (2882 init, 2971 F-16 anti-rule, 2990 J+8 anti-trigger, 3021 implicit fall-through). All are veto-only — none can enable.

**Result:** there is **no path** to `farankaTriggered = true` that bypasses `onBidderTeam`. The anti-trigger un-veto concern in the prompt is unfounded — anti-triggers (F-16, J+8) only veto, never re-enable.

---

### F3 — F-16 anti-rule (`hasKtrump` post-veto)

Block at `Bot.lua:2964-2972`:
```lua
if farankaTriggered then
    local hasKtrump = false
    for _, c in ipairs(hand) do
        if C.IsTrump(c, contract) and C.Rank(c) == "K" then
            hasKtrump = true; break
        end
    end
    if not hasKtrump then farankaTriggered = false end
end
```

**Correctness vs Source C F-16:**
- Source C F-16: "no K of trump → don't Faranka" (anti-rule applies to all seats).
- Code suppresses when **K of trump is not currently in `hand`**.

**Edge case: K of trump played earlier by us.** If we played K of trump on a previous trick, it is no longer in `hand`. The check therefore correctly suppresses Faranka — and this is **the right behavior**. F-16's reasoning is "the K is the cover card backing up the withhold"; if we no longer hold the K, it cannot back anything up. So even though the prompt asks whether the K-played-earlier case is a false suppression, the answer is **no** — it is a correct suppression. The K must be in the **current hand** to serve as Faranka cover.

**Edge case: K of trump played earlier by someone else.** If an opponent or partner played K of trump previously, we never had it. Check correctly suppresses, identical to never-dealt case.

**No bug here.** The check uses `hand` (live cards), not `mem.played`, and that is the semantically correct read of F-16.

**Order of evaluation:** F-16 fires AFTER all 3 triggers (line 2964, after the #4 block at 2955). All 3 are suppressed equally. Correct.

**Minor observation (non-bug):** F-16 is per Source C an anti-rule that applies to **all seats** (not just bidder-team). The code's F-16 placement is post-veto on `farankaTriggered`, which already requires `onBidderTeam`. Effectively the anti-rule only ever fires on bidder-team Farankas — but since opp-team Farankas are already structurally suppressed by F2 gating, the net behavior is identical to "F-16 universal". No functional gap.

---

### F4 — F-14 transcription slip (Sun pos-4 last-seat opp-winning)

The Sun Faranka block at `Bot.lua:2584-2613` requires `partnerWinning` as a precondition. When opp is winning, the block is skipped entirely (`partnerWinning == false`), and the seat falls through to the `winners` selection branch — which **takes** the trick.

This matches Source C F-14's **corrected intent** (do not take the literal Arabic "must Faranka" — take the trick with A as the worked example shows). **MATCH preserved at v0.10.2.** Unchanged from v0.10.0.

---

### F5 — F-17 (≥3 cards anti-rule) and what about side-suit Faranka in F-30?

**F-17 in the Sun block (`Bot.lua:2591, 2610`):** `suitCount == 2` strict — enforces "exactly 2 cards in led suit". A 4-trump-total hand still passes only if it has exactly 2 of the **led suit** (not 2 trumps). For Sun pos-4 Faranka the `lead` suit = led suit; for the trigger to fire the seat needs A + cover (T/K) + exactly 2 cards of that lead-suit, regardless of total trump count. **F-17 enforced.**

**Side-suit Faranka in F-30 (Hokm Type 2 / "trump+side"):** The Hokm Faranka block at 2857-3022 only triggers when `trick.leadSuit` is **trump** (the bot withholds top trump, plays a non-winner). It does NOT model side-suit Faranka — the F-30 case where the bidder holds A+K of a side suit and ducks the K to keep the A is **not represented**. The current F-30 code (2943-2955) gates on `oppTrumpExhausted` but the actual non-winner pool returned at 3009-3018 prefers non-trump-non-winners — which can produce a side-suit-cover-style play *only if* the legal set contains side-suit non-winners. This is incidental, not designed, and Source-C's "A+K of side-suit" hand-shape is not enforced (X3 Bug 3).

**Net for the prompt's question:** F-17 fires correctly via the strict `suitCount == 2` gate in the **Sun block**. The Hokm block has no per-trigger suit-count gate — instead it gates on bidder-team + trigger predicate + winners-exist. There is **no F-17 analogue** in the Hokm block, but Source C does not state F-17 applies to Hokm Faranka either (F-17 is in the Sun anti-rule cluster). **No gap created by the absence.**

---

### F6 — Anti-trigger rule 7 (J+8 vs Q-led-by-bidder) — broader Q-leads cases?

Code at `Bot.lua:2974-2993` wires only the J+8 case:
- `lead.seat == contract.bidder` (opp is bidder) AND
- `R.TeamOf(lead.seat) ~= R.TeamOf(seat)` (opp-bidder, redundant given onBidderTeam already required for trigger but kept for clarity) AND
- `C.Rank(lead.card) == "Q"` AND
- hand has J of trump AND 8 of trump → un-trigger

**Source C / decision-trees Section 10 lines 262-263:** Two anti-rules in the Q-led / opp-bidder family:
- Line 262 (wired): "Hokm; bidder is opp; opp led trump-Q; you hold trump-J + trump-8 → do NOT Faranka".
- Line 263 (NOT WIRED): "Hokm; you are pos-4 holding trump-9 only; opp Faranka'd by playing T after partner's J was over-trumped → MUST take with the 9".

The NOT-WIRED row 263 is **a separate scenario** from row 262 (different position, different hand). Source C / video 04 does not list other Q-led anti-rules in the Hokm block — Section 10 of decision-trees.md captures the only two video-04-attested cases.

**However**, the J+8 gate in the code requires onBidderTeam=true to even reach the un-veto. Tracing: trigger fires only when `onBidderTeam`. If opp is the bidder, then `onBidderTeam` is FALSE, none of the 3 triggers fires, and the un-veto code is unreachable. **The J+8 anti-trigger is structurally dead code post-v0.10.0** because the v0.9.2 #49 + v0.10.0 X3 changes already prevent any trigger from firing when opp is the bidder. The code retains it as a defensive belt-and-suspenders, which is fine, but worth flagging that its functional impact is now zero.

**Verdict:** the broader Q-leads class is captured by structural means (onBidderTeam gate suppresses all Hokm Faranka when opp bids). The J+8 anti-trigger is now redundant but harmless.

---

### F7 — Order of evaluation

Top-to-bottom in the block:

1. `farankaTriggered = false` (init, 2882)
2. **#2 / F-27 trigger** — `myTrumpCount == 2 and onBidderTeam` (2900-2902)
3. **#3 / F-29 trigger** — `not farankaTriggered and onBidderTeam and HighestUnplayedRank == "9"` (2922-2932)
4. **#4 / F-30b trigger** — `not farankaTriggered and onBidderTeam` + opp trump void (2943-2955)
5. **F-16 anti-rule** — `not hasKtrump` → veto (2964-2972)
6. **J+8 anti-trigger** — opp-bidder Q-led + J+8 → veto (2974-2993)
7. Non-winner selection — prefer non-trump-non-winner (2995-3021)

**Short-circuit semantics on triggers (steps 2-4):** each subsequent trigger guards on `not farankaTriggered`, so the first matching trigger wins. This is correct OR-semantics.

**Order of vetoes (steps 5, 6):** F-16 fires before J+8. Order doesn't matter — both veto, neither enables. If both want to suppress, the first one suppresses, the second one no-ops.

**Verdict:** Order is correct.

---

### F8 — Tier-gating: `Bot.IsM3lm()` only

Block opens at `Bot.lua:2880`:
```lua
if Bot.IsM3lm() and contract.type == K.BID_HOKM and contract.trump
   and trick.leadSuit and #winners > 0 then
```

`Bot.IsM3lm()` returns true for M3lm OR Fzloky OR Saudi Master tiers (per `Bot.lua:60-65`). Per Source C audience framing ("Saudi tournament strategy"), tier-gating to M3lm+ is reasonable. Lower tiers (Basic, Advanced) play the natural winners branch — also documented in decision-trees.md row 256 ("wired by absence: bot has no Faranka path unless an exception fires").

**Verdict:** Reasonable. Matches CLAUDE.md tier table and Source C's "Saudi-strategy-pro" framing.

---

### F9 — Bot.PickPlay → BotMaster.PickPlay delegation: does Faranka logic still apply?

`Bot.PickPlay` at `Bot.lua:3372-3402`:
1. If Saudi Master active AND not in rollout, delegate to `BM.PickPlay` (returns ISMCTS-chosen card).
2. Otherwise, run heuristics (which include the Hokm Faranka block in `pickFollow`).

`BM.PickPlay` at `BotMaster.lua:812-898` runs ISMCTS — it samples worlds and uses **`heuristicPick`** (a local closure at `rolloutValue`, BotMaster.lua:645-755) as the rollout policy. **`heuristicPick` is a stripped-down rollout helper** — it implements:
- Smother (highest A or T to partner's winning trick on non-trump lead).
- pos-2 ducking, pos-3 third-hand-high, pos-4 cheapest winner.
- Lead heuristic: highest trump if Hokm bidder-team, else lowest non-trump.

**`heuristicPick` does NOT call `Bot.PickPlay` or `pickFollow`** — it is a parallel reimplementation. **Therefore the Hokm Faranka block (Bot.lua:2880-3022) is NEVER reached during BotMaster ISMCTS rollouts.**

**Consequence at the Saudi Master tier:**
- The **outer decision** (which card to actually play) goes through `BM.PickPlay`, which runs ISMCTS. ISMCTS evaluates each candidate via rollouts using `heuristicPick`. The candidate that scores best wins.
- **Within rollouts**, neither our seat nor any other simulated seat ever Farankas — all four seats are run through `heuristicPick`'s simplified policy.
- **Outside rollouts**, when `BM.PickPlay` is choosing the actual card to play, it does NOT call `pickFollow`. It picks via aggregated rollout scores.

**Net:** at Saudi Master tier, the Faranka heuristics **do not steer the actual play** — ISMCTS does. ISMCTS may *coincidentally* pick a Faranka-shaped card if rollouts favor the withhold play, but the explicit Source-C-derived rules in `pickFollow` are bypassed entirely.

**This is a notable strategic-policy gap.** Per CLAUDE.md "v0.5.0 fix: Bot.PickPlay delegates internally to BotMaster.PickPlay when Saudi Master tier is active" — this is structurally correct. But the consequence is that all the careful v0.9.2 / v0.10.0 Faranka work (#49, X3 #2, X3 #3, X3 #4, F-16 anti-rule) **has zero impact on Saudi Master tier behavior**. M3lm and Fzloky tiers do get the Faranka heuristics; Saudi Master does not.

**Severity:** medium. Not a v0.10.2 regression — the gap predates the entire Faranka block. Worth flagging as architectural drift between strategy-doc-derived heuristics (which are M3lm+ gated and visible in `pickFollow`) and Saudi Master tier (which uses independent ISMCTS + a stripped-down rollout heuristic). Two paths to address:
1. Wire `heuristicPick` to invoke `pickFollow` in rollouts (with `_inRollout = true` already set, so the recursion guard prevents ISMCTS re-entry).
2. Accept the policy split and document that Saudi Master is "ISMCTS+rollout-heuristic, not Source-C-rules-aware".

**Note on `_inRollout` flag:** `BM.PickPlay` sets `B.Bot._inRollout = true` at line 822 to prevent recursive ISMCTS entry. If `heuristicPick` were rewired to call `Bot.PickPlay` (which is the natural way to share heuristics), the recursion guard at 3381 (`if not Bot._inRollout`) would correctly skip the BotMaster delegation, and `pickFollow` would run. This is a small, targeted change but out of scope for v0.10.2 closure.

---

### F10 — Test coverage

Searched `tests/` for "faranka" / "Faranka" / "FARANKA" → **0 matches**. Searched for `pickFollow` / `farankaTriggered` / `withhold` in `test_state_bot.lua` → only the v0.5.11 regression pin block (E.1-E.6 in test_state_bot.lua:712+) tests pickFollow's Section-4-rule-1 / Takbeer / T-4 paths. **No test exercises the Hokm Faranka exception block** at any of:
- Trigger #2 / F-27 firing or its bidder-team gate
- Trigger #3 / F-29 firing or its bidder-team gate (added v0.10.0 X3)
- Trigger #4 / F-30b firing or the relaxation from `bidder == seat` to `onBidderTeam` (changed v0.10.0 X3)
- F-16 K-cover anti-rule (added v0.10.0 X3)
- J+8 anti-trigger un-veto

Confirmed: **the entire block is regression-bare** at v0.10.2, exactly as flagged in xref_X3 row 140 and audit_v0.9.0/22.

**Suggested fixture pattern** (deliberately schematic — not production code):

```
-- Pattern: test_hokm_faranka_<exception>_<scenario>.lua
-- Reuses test_state_bot.lua harness (freshState + S.s.* setup + Bot.PickPlay + assertEq).

-- E.G. Exception #2 / F-27 — bidder-team gate (v0.9.2 #49)
do
    freshState()
    WHEREDNGNDB.m3lmBots = true
    S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }  -- bidder = seat 1
    -- Hand: 2 trumps (J, 8) + 6 non-trumps. We are seat 3 (partner of bidder).
    S.s.hostHands = {
        [1] = { /* opp-side filler, 8 cards */ },
        [2] = { /* opp-side filler */ },
        [3] = { "JS", "8S", "AH", "KH", "AD", "KD", "AC", "KC" },
        [4] = { /* partner-side filler */ },
    }
    -- Trick led by seat 4 with high trump; we (seat 3) face winners.
    S.s.trick = { leadSuit = "S", plays = { { seat = 4, card = "9S" }, ... } }
    -- Force a winners > 0 setup: must have a card that wouldWin.
    -- assert: Bot.PickPlay(3) returns NON-winner because Faranka triggered.
    --    (specifically not the high trump winner)

    -- Negative twin: same hand-shape with bidder = seat 2 (opp-team).
    --    assert: Bot.PickPlay(3) returns the WINNER, not a withhold.
end

-- E.G. Exception #3 / F-29 — J-dead 9-branch + bidder-team gate (v0.10.0 X3)
do
    freshState()
    -- Set up s.playedCardsThisRound so HighestUnplayedRank("trump") = "9".
    -- Pre-condition: J of trump played, 9 of trump still in our hand.
    -- Two sub-tests: bidder-team (Faranka fires) vs opp-bidder (Faranka suppressed).
end

-- E.G. F-16 — K-of-trump absent → suppress
do
    -- Set up Trigger #2 to fire (myTrumpCount == 2, bidder-team).
    -- Hand: J + 8 of trump (no K). assert: Bot.PickPlay returns winner, not withhold.
    -- Counter: Hand: K + 8 of trump → Faranka fires.
end

-- E.G. J+8 anti-trigger
do
    -- Set up the "structurally dead" path for documentation:
    -- bidder = opp, opp leads QS, we hold JS+8S+JD+KD,
    -- Trigger #2 cannot fire (onBidderTeam=false), so this is a no-op test
    -- but documents that the un-veto path is unreachable post-v0.10.0.
end
```

**Minimum viable pin:** 2 tests per wired trigger (positive: trigger fires, negative: bidder-team gate prevents fire) + 1 test per anti-rule (F-16, J+8) = **8-10 tests** to fully pin v0.10.2 behavior. Additional fixture for Saudi Master tier delegation gap (F9): one test asserting that ISMCTS bypasses the Faranka block (currently true).

---

## Verdict

**Block status at v0.10.2: structurally sound for the wired triggers, with one architectural gap.**

- **3 of 6 source-C exceptions wired** (F-27, F-29, F-30b). Bidder-team gating is now consistent across all 3 wired pro-triggers (v0.9.2 #49, v0.10.0 X3 closures all landed cleanly).
- **3 of 6 deferred** (F-24, F-26, F-28) — confirmed unchanged since X3 audit; CHANGELOG carries them as known gaps.
- **F-16 anti-rule wired correctly** at v0.10.0 X3. Edge cases (K-played-earlier) handled correctly by the live-hand semantic.
- **J+8 anti-trigger now structurally redundant** post-v0.10.0 (onBidderTeam already prevents Hokm Faranka when opp bids). Harmless — kept as belt-and-suspenders.
- **Order of evaluation correct**: triggers OR-short-circuit, then F-16 veto, then J+8 veto, then non-winner selection.
- **F-30 hand-shape gap remains** (no A+K-of-side check, predicate (a) "covet Kabout" not wired) — X3 Bug 3 + 4 carried forward, not v0.10.2 regression.
- **Tier-gating to M3lm+ correct** per CLAUDE.md and Source C.
- **Saudi Master tier delegation bypasses the entire Faranka block.** ISMCTS uses `heuristicPick` (a parallel stripped-down rollout policy in BotMaster.lua) which never reaches `pickFollow`. All v0.9.2/v0.10.0 Faranka work has **zero effect at Saudi Master tier**. Notable architectural gap; not a v0.10.2 regression.
- **Test coverage = 0.** Block is regression-bare. Recommend pinning before any further changes; minimum 8-10 tests sketched above.

**No new bugs introduced by v0.10.2.** The v0.10.0 X3 closures (Exception #3 onBidderTeam gate, Exception #4 relaxation, F-16 anti-rule) are intact and correctly implemented.

## Confidence

**HIGH** for the rule-by-rule mapping and gating audit (F1, F2, F3, F4, F5, F7, F8, F10). All trigger predicates and veto sites read end-to-end against the v0.10.2 source; cross-checked against xref_X3 + source_C + decision-trees.md.

**HIGH** for the Saudi Master delegation finding (F9). `BotMaster.lua:592-806` (rolloutValue) and 812-898 (BM.PickPlay) read end-to-end; `heuristicPick` is fully self-contained and verifiably does not call `Bot.PickPlay` or `pickFollow`.

**MEDIUM** for the J+8 redundancy claim (F6). The anti-trigger is unreachable in the gate-flow as currently written, but a future change to onBidderTeam semantics could re-enable the path; keeping the J+8 veto is defensive-good even if currently dead-code.

**LOW** for the suggestion that `heuristicPick` should call `pickFollow` to inherit Faranka logic at Saudi Master tier — this is a design-level call with non-trivial test/regression risk and out of scope for a v0.10.2 review.

**Test coverage = 0** for the block confirmed; a per-branch fixture pattern is suggested (F10) but not implemented (review-only, no code modifications per scope).
