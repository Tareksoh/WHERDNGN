# v3.2.0 Cleanup Batch 7 — Design / Inventory Pass

Status: design pass only. No runtime code changed. No tests changed.
Working tree contains only this doc.

## 1. Current State

| Field | Value |
|---|---|
| `main` commit | `613c5be` — docs(batch6): correct projected test-count delta |
| Last shipped tag | **v3.1.14** (commit `c1c624f`) |
| Full harness | **1151 / 1151 pass** |
| Working tree | clean (this doc untracked) |
| Release tag for Batch 7 | none — cleanup-only |

## 2. Source-Pin Inventory

Pins relevant to the future `Bot/Bidding.lua` and/or `Bot/Escalation.lua` extractions, current-`main` line numbers. Convertibility ratings:
- **LOW** = direct fixture, deterministic, existing behavioral may already cover it
- **MEDIUM** = needs calibrated state + jitter freeze
- **HIGH** = deep choreography or invasive helper exposure
- **KEEP SOURCE-ONLY** = comment/ordering/diagnostic — converting adds friction without reducing risk

### 2A. Pins protecting Bot/Bidding.lua surface

| Pin | Line | Scans | Protects | Blocks | Convertibility |
|---|---|---|---|---|---|
| **W.1** | 3055-3070 | `aceCount == 2` / `sunAces == 2` / `K.BOT_SUN_2ACE_BONUS` inside PickBid (window 6 000 chars) | 2-Ace Sun bonus applied | Bidding | **LOW (CONVERT — new AJ.14 zero-jitter boundary test)** |
| **T.2b** | 2722 | `math.min(penalty, K.BOT_SUN_VOID_PENALTY_CAP)` in `sunStrength` | sunStrength uses K-cap constant | Bidding | MEDIUM (helper is local; behavioral needs massive-void fixture through PickBid) |
| T.2c | 2724 | `math.min(penalty, 18)` ABSENT | old 18-cap removed | Bidding | KEEP (absence assertion) |
| **T.3a** | 2743 | `hasTrumpA, hasTrumpNine` declaration in `hokmMinShape` | Lever C variable presence | Bidding | HIGH (purely structural variable name) — but T.4 behavioral already covers the J+8 mardoofa rejection |
| **T.3b** | 2745 | `hasTrumpNine or hasTrumpA` gate in `hokmMinShape` | Lever C count==2 gate | Bidding | MEDIUM — T.4 covers behaviorally for rejection side; acceptance side (J+9 self-sufficient) is X.2 territory |
| **X.1c** | 3169 | `K.BOT_OVERCALL_VOID_TRUMP_BONUS` reference in PickOvercall | overcall void bonus applied | Bidding | **LOW (CONVERT — new AJ.15 behavioral, Hokm overcall window)** |
| **X.1d** | 3171 | `trumpCount == 0` check in PickOvercall | void detection | Bidding | **LOW (CONVERT — same AJ.15 block)** |
| X.1c-setup | 3166 | `assertTrue(fnStart ~= nil)` for PickOvercall | function exists | Bidding | dies with X.1c block |
| **X.2** | 3189 | `count >= 3 and hasTrumpNine` in `hokmMinShape` | J+9+count≥3 self-sufficient mardoofa path | Bidding | MEDIUM (needs Hokm fixture without side Ace; X.4 already covers via Hokm-on-flipped behavioral) |
| Y.2b | 3276 | Belote-escape ordering before J-floor | structural order | Bidding | KEEP (ordering) |
| **Y.3a** | 3296 | `local sunHand = withBidcard(...)` in PickBid | bidcard inclusion for Sun | Bidding | MEDIUM (AE.X partially covers via Sun-strong behavioral, but the Y.3 block also covers R2 Hokm and PickOvercall in one shot) |
| **Y.3b** | 3298 | `local hokmHand = withBidcard(...)` in PickBid R2 | bidcard inclusion for R2 Hokm | Bidding | MEDIUM (AE.1 covers — sub-threshold K+Q+side-Ace fixture requires withBidcard) |
| **Y.3c** | 3304 | `withBidcard(hand, S.s.bidCard)` in PickPreempt | bidcard inclusion for preempt | Bidding | MEDIUM (no existing PickPreempt behavioral; new fixture would need PHASE_PREEMPT setup) |
| **Y.3d** | 3310 | `withBidcard(hand, bidCard)` in PickOvercall | bidcard inclusion for overcall | Bidding | LOW (H.10-H.14 + AC.4/AC.5 already exercise PickOvercall withBidcard end-to-end) |
| **Z.1** | 3370 | `belote = beloteSuit(withBidcard(...))` in PickBid | Belote computed post-bidcard | Bidding | MEDIUM (needs hand where bidcard COMPLETES K+Q — fragile calibration) |
| Z.2 | 3383 | hypHand precedes trumpCount loop in PickOvercall | ordering | Bidding | KEEP (ordering) |
| **Z.3** | 3392 | `aceCountAndMardoofa(sunHand)` post-bidcard | mardoofa recomputed post-bidcard | Bidding | MEDIUM (needs hand where bidcard COMPLETES mardoofa pair) |
| **AA.4** | 3463 | `local function bidderHoldsBidcard(seat, card)` defined | helper exists | Bidding | LOW retirement candidate — AE.3a smoke covers (weak coverage, see caveat below) |
| **AB.3** | 3511 | `S.s.phase ~= K.PHASE_PLAY` gate in bidderHoldsBidcard | phase-gate behavior | Bidding | LOW retirement candidate — AE.3c smoke covers (weak coverage) |
| AD.2 | 3707 | `bidderHoldsBidcard(contract.bidder, S.s.bidCard)` wiring | helper-wired into trump-J inference | Bidding | KEEP (wiring pin; harmless) |
| AD.9 | 3805-ish | btrace `sunAces=%d sunMardoofa=%d` format | bidcalc trace post-bidcard format | Bidding | KEEP (diagnostic format pin) |
| **AH.6** | 5090 | `seatIsBidder` in `partnerBidBonus` | bidder vs defender PASS split | Bidding | HIGH (multi-state PickBid fixture spanning bid history + dealer position; defer to Batch 8 or extraction commit) |
| AH.7 | 5101 | `"neutralize Sun-only penalty"` comment in escalationStrength | rationale comment | Both | KEEP (rationale comment) |

### 2B. Pins protecting Bot/Escalation.lua surface

| Pin | Line | Scans | Protects | Blocks | Convertibility |
|---|---|---|---|---|---|
| AA.1a | 3427 | `voidCount * 5` in escalationStrength | Hokm bidder void bonus | Escalation | MEDIUM (escalationStrength is local; behavioral needs PickDouble/Triple deviation between void-rich vs void-free hands) |
| AA.1b | 3429 | `sideAces - 1` in escalationStrength | side-Ace bonus | Escalation | MEDIUM (same path) |
| AB.2 | 3498 | `"DEAD-2"` comment in PickGahwa | floor-cap-removal rationale | Escalation | KEEP (comment-only) |
| AD.3 | 3718 | `"DEAD-2"` comment in PickGahwa (duplicate of AB.2) | rationale | Escalation | KEEP (comment-only duplicate) |
| AD.7a | 3783 | `local function eltrace` in PickDouble | diagnostic helper | Escalation | KEEP (debug-mode) |
| AD.7b | 3785 | `"PickDouble eval: strength="` log format | diagnostic format | Escalation | KEEP (debug-mode) |
| **AH.3** | 5054-5065 | `th < K.BOT_TRIPLE_TH - 16 then th = K.BOT_TRIPLE_TH - 16` in PickTriple | floor cap | Escalation | **MEDIUM (KEEP source-only — see §5; AK.7 is general weak-hand coverage, does not tightly prove the cap is load-bearing)** |
| **AI.2a** | 5122 | `if contract.foured or contract.tripled then` in pickFollow smother gate | tiered smother gate strict tier | Escalation | HIGH (deep pickFollow fixture; defer to extraction commit) |
| **AI.2b** | 5124 | `elseif contract.doubled then` smother gate medium tier | tiered smother gate medium tier | Escalation | HIGH (same) |

### 2C. Pins that should KEEP SOURCE-ONLY

| Pin | Line | Reason |
|---|---|---|
| R.2a-e | 2684-2693 | btrace diagnostic helper inside PickBid — debug-mode wiring; not behavior |
| AD.7a-b | 3783-3785 | eltrace diagnostic helper inside PickDouble — debug-mode wiring |
| AB.2 / AD.3 | 3498 / 3718 | DEAD-2 rationale comment in PickGahwa — comment-only |
| AI.1 | 5112 | `agent #1 urgency-aware swing` comment marker |
| AI.4 | 5140 | `agent #4 bid-history inflection` comment marker |
| AI.5 | 5148 | `Bargiya receiver phase-split` comment marker |
| Y.2b | 3276 | Belote-escape-before-J-floor ordering |
| X.2b | 3197 | self-sufficient-path-before-L07 ordering |
| Z.2 | 3383 | hypHand-precedes-trumpCount-loop ordering |
| T.2c | 2724 | absence of old 18-cap — protects against revert |
| AD.2 | 3707 | wiring pin for `bidderHoldsBidcard` into trump-J inference — cheap structural check |
| AD.9 | 3805-ish | btrace format string — debug-mode |

These 13 pins should not be converted in Batch 7 or any other batch. Their conversion would either be vacuous (comment-only pins protect documentation, not behavior) or replace a cheap structural check with a brittle behavioral fixture.

---

## 3. Conversion Ranking

After Codex review the recommended scope is narrowed to **2 picks** —
both pure conversions (no citation-only retirements). Codex's findings:

- **W.1 → cite-W.2 retirement REJECTED.** W.2 is gameplay coverage, not
  a tight regression guard for the exact 2-Ace bonus application.
  Convert W.1 to a new jitter-frozen boundary test instead (AJ.14).
- **AH.3 retirement REJECTED.** AK.7 is a general weak-hand non-fire
  test; it does not tightly prove the floor cap line is load-bearing.
  Keep AH.3 source-only for now.
- **AA.4 + AB.3 retirement REJECTED.** AE.3a/b/c is smoke-level only
  and would still pass under subtle bidderHoldsBidcard regressions
  (including phase-gate breakage). Keep AA.4 + AB.3 source-only
  until the eventual Bot/Bidding.lua extraction retargets them
  mechanically.
- **X.1c + X.1d** original AJ.14 sketch was incorrect (returned WAIVE
  on both sides because PickOvercall was being exercised under a Sun
  contract). Replace with a corrected fixture inside an active Hokm
  overcall window (`S.BeginOvercall`).

| Rank | Pin(s) | Action | Behavioral fixture | Flake risk | Failure mode if regressed |
|---|---|---|---|---|---|
| 1 | **W.1** (PickBid 2-Ace Sun bonus) | RETIRE + NEW **AJ.14** | Zero-jitter PickBid hand calibrated so `K.BOT_SUN_2ACE_BONUS` is load-bearing: with bonus → SUN, without → PASS | LOW — jitter frozen via arity-aware shim | If PickBid stops applying the 2-Ace bonus, AJ.14's hand falls below the Sun threshold even at jitter=0 → SUN flips to PASS |
| 2 | **X.1c + X.1d** (PickOvercall void-trump bonus) | RETIRE + NEW **AJ.15** | Hokm overcall window via `S.BeginOvercall`; void-in-S 8-card hand → TAKE; same shape with one S card → WAIVE | LOW — overcall thresholds are fixed; no jitter freeze needed | If void bonus is removed, TAKE flips to WAIVE on the void hand. If trumpCount==0 check is removed, every hand gets the bonus and WAIVE flips to TAKE on the one-trump hand |

**Recommended 2 picks:**

1. Convert **W.1** → add **AJ.14** NEW (PickBid 2-Ace Sun bonus boundary, jitter-frozen).
2. Convert **X.1c + X.1d** → add **AJ.15** NEW (PickOvercall void-trump bonus boundary, Hokm overcall window via `S.BeginOvercall`).

### Test count delta

| Action | Asserts retired | Asserts added |
|---|---|---|
| Retire W.1 (block has setup-found + substantive) | -2 | 0 |
| Retire X.1c + X.1d block (setup-found + X.1c + X.1d = 3 asserts) | -3 | 0 |
| Add AJ.14 (single assertEq: PickBid returns SUN under zero-jitter 2-Ace fixture) | 0 | +1 |
| Add AJ.15 (two assertEq: void → TAKE, one-trump → WAIVE) | 0 | +2 |
| **Total** | **-5** | **+3** |

Net delta: **-2**. Final harness: 1151 − 2 = **1149**.

### Why these 2 picks now

- Both target `Bot/Bidding.lua` extraction friction.
- Both have clear behavioral failure modes (boundary tests where the protected mechanism is load-bearing).
- Codex verified the fixtures pre-implementation: AJ.14 returns SUN with bonus / PASS without; AJ.15 returns TAKE for void / WAIVE for one-trump.
- Neither requires exposing internal helpers as new exports.
- Only AJ.14 needs `math.random` jitter freeze (arity-aware shim, same shape as commit `08473ce`).
- AH.3, AA.4, AB.3 stay source-only until extraction-time retarget — see §5 deferrals.

---

## 4. Per-Pick Sketches

### 4A. Retire W.1 → add AJ.14 NEW (PickBid 2-Ace Sun bonus boundary)

**Current pin (tests/test_state_bot.lua:3055-3070):**
```lua
-- W.1 — Bot.PickBid applies the 2-Ace bonus. Source-pin: the
-- elseif that adds K.BOT_SUN_2ACE_BONUS is present in PickBid.
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickBid")
    assertTrue(fnStart ~= nil, "W.1 setup: Bot.PickBid found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 6000)
        local hasAceMatch = body:find("aceCount == 2") ~= nil
                            or body:find("sunAces == 2") ~= nil
        assertTrue(hasAceMatch and body:find("K%.BOT_SUN_2ACE_BONUS") ~= nil,
                   "W.1 (v0.11.14): PickBid applies K.BOT_SUN_2ACE_BONUS for 2-Ace count")
    end
end
```

**Retirement comment (Batch 3 / Batch 6 style):**
```lua
-- W.1 (v3.2.0 cleanup batch 7): source pin RETIRED. Behavioral
-- counterpart at AJ.14 calibrates a zero-jitter PickBid hand where
-- K.BOT_SUN_2ACE_BONUS is load-bearing: with the bonus -> SUN,
-- without the bonus -> PASS.
```

**New AJ.14 block (Codex-verified fixture):**
```lua
-- AJ.14 (v3.2.0 cleanup batch 7, replaces W.1 source pin):
-- behavioral counterpart for PickBid's 2-Ace Sun bonus. The hand
-- is calibrated under zero jitter so the 2-Ace bonus is load-bearing:
-- with K.BOT_SUN_2ACE_BONUS applied -> SUN; without it -> PASS.
do
    local restore = snapshotS({
        "bidRound", "bidCard", "dealer", "hostHands", "cumulative", "bids",
    })
    local prevAdvanced = WHEREDNGNDB.advancedBots
    WHEREDNGNDB.advancedBots = true

    local origRandom = math.random
    math.random = function(a, b)
        if a == -K.BOT_BID_JITTER and b == K.BOT_BID_JITTER then return 0 end
        if a == -3 and b == 3 then return 0 end
        if a == nil then return origRandom() end
        if b == nil then return origRandom(a) end
        return origRandom(a, b)
    end

    S.s.bidRound = 1
    S.s.bidCard = "7C"
    S.s.dealer = 4
    S.s.cumulative = { A = 0, B = 0 }
    S.s.bids = {}
    S.s.hostHands = {
        [1] = { "7S", "TS", "QS", "AH", "AD" },
    }

    local result = Bot.PickBid(1)

    math.random = origRandom
    WHEREDNGNDB.advancedBots = prevAdvanced
    restore()

    assertEq(result, K.BID_SUN,
             "AJ.14 (W.1 behavioral): 2-Ace bonus is load-bearing for zero-jitter PickBid Sun boundary")
end
```

**Determinism plan:** arity-aware `math.random` shim freezes both the ±BID_JITTER jitter and the ±3 sub-jitter to 0 (Codex-confirmed fixture). Assert lands AFTER `math.random` is restored.

**Failure mode if regressed:** with `K.BOT_SUN_2ACE_BONUS = 0` (or the bonus block removed), Codex verified the same fixture returns `PASS` instead of `SUN`. The assert fails loud.

### 4B. Retire X.1c + X.1d → add AJ.15 NEW (PickOvercall void-trump bonus boundary)

**Current pin (tests/test_state_bot.lua:3162-3174):**
```lua
-- X.1c — Bot.PickOvercall applies the void/short bonus
do
    local botSrc = io.open(WHEREDNGN_TESTS_ROOT .. "/Bot.lua"):read("*a")
    local fnStart = botSrc:find("function Bot%.PickOvercall")
    assertTrue(fnStart ~= nil, "X.1c setup: Bot.PickOvercall found")
    if fnStart then
        local body = botSrc:sub(fnStart, fnStart + 3000)
        assertTrue(body:find("K%.BOT_OVERCALL_VOID_TRUMP_BONUS") ~= nil,
                   "X.1c (Q1): PickOvercall references K.BOT_OVERCALL_VOID_TRUMP_BONUS")
        assertTrue(body:find("trumpCount == 0") ~= nil,
                   "X.1d (Q1): PickOvercall checks for trump-suit void")
    end
end
```

**Retirement comment:**
```lua
-- X.1c + X.1d (v3.2.0 cleanup batch 7): source pins RETIRED.
-- Behavioral counterpart at AJ.15 covers both branches: true void
-- in contract trump -> TAKE via K.BOT_OVERCALL_VOID_TRUMP_BONUS;
-- one trump -> WAIVE because only the short-trump bonus applies.
```

**New AJ.15 block (Codex-verified fixture, Hokm overcall window):**
```lua
-- AJ.15 (v3.2.0 cleanup batch 7, replaces X.1c + X.1d source pins):
-- behavioral counterpart for PickOvercall's void-in-trump bonus.
-- The void hand clears TAKE only because trumpCount == 0 applies
-- K.BOT_OVERCALL_VOID_TRUMP_BONUS. The same face-strength hand with
-- one trump card gets only the short-trump bonus and returns WAIVE.
do
    local restore = snapshotS({
        "phase", "contract", "bidCard", "dealer", "hostHands",
        "cumulative", "bids", "overcall",
    })
    local prevDB = WHEREDNGNDB
    WHEREDNGNDB = { advancedBots = true, m3lmBots = true }

    local function setupOvercall(hand)
        S.s.contract = { type = K.BID_HOKM, trump = "S", bidder = 1 }
        S.s.dealer = 4
        S.s.overcall = nil
        S.s.phase = K.PHASE_DOUBLE
        S.s.bidCard = "9C"
        S.s.cumulative = { A = 0, B = 0 }
        S.s.bids = {}
        S.BeginOvercall("9C", 4)
        S.s.hostHands = { [3] = hand }
    end

    setupOvercall({ "AH", "TH", "KH", "QH", "AD", "TD", "AC", "KC" })
    local pickVoid = Bot.PickOvercall(3)
    assertEq(pickVoid, "TAKE",
             "AJ.15a (X.1c/d behavioral): void in contract trump applies overcall bonus -> TAKE")

    setupOvercall({ "AH", "TH", "KH", "QH", "AD", "TD", "AC", "KS" })
    local pickShort = Bot.PickOvercall(3)
    assertEq(pickShort, "WAIVE",
             "AJ.15b (X.1c/d behavioral): one trump gets short bonus only -> WAIVE")

    WHEREDNGNDB = prevDB
    restore()
end
```

**Determinism plan:** none — Codex confirmed PickOvercall compares against fixed overcall thresholds and `sunStrength` suit shuffling does not change the score for this fixture.

**Failure mode if regressed:** if `K.BOT_OVERCALL_VOID_TRUMP_BONUS` is removed, the void hand's strength drops by 15 → pickVoid flips from TAKE to WAIVE. If `trumpCount == 0` check is removed, every hand gets the bonus regardless of trump count → pickShort flips from WAIVE to TAKE. Either assert fails.

**Vacuous-pass risk:** LOW. Two-sided assertion (one positive, one negative) on the same 8-card face-strength shape.

---

## 5. Explicit Deferrals

Pins KEPT source-only for Batch 7 per Codex review:

| Pin | Reason kept source-only |
|---|---|
| **AH.3** (PickTriple floor cap) | AK.7 is a general weak-hand non-fire test; it does NOT tightly prove the floor cap line is load-bearing. Removing the floor cap might not flip AK.7's outcome on AK.7's specific fixture. Keep source-only until a stronger behavioral fixture is designed (recommended: defer to a dedicated floor-cap-targeted behavioral in Batch 8 or land mechanical pin retarget during Bot/Escalation.lua extraction). |
| **AA.4** (bidderHoldsBidcard helper exists) | AE.3a/b/c is smoke-level coverage — only asserts PickPlay returns a non-nil card. Helper-exists is a structural invariant; smoke does not protect against subtle regressions. Keep source-only until Bot/Bidding.lua extraction renames the helper and retargets the pin mechanically. |
| **AB.3** (bidderHoldsBidcard phase-gate to PHASE_PLAY) | Same reasoning as AA.4. AE.3c's PHASE_DOUBLE flip only asserts PickPlay doesn't crash, not that the phase-gate flipped the helper's return value. Keep source-only until the extraction commit. |

Pins reachable behaviorally but better handled during actual extraction:

| Pin | Reason for defer |
|---|---|
| T.2b | Reachable via PickBid massive-void Sun hand; reachable but brittle (need 4-suit-void fixture). Better handled during Bot/Bidding.lua extraction commit. |
| T.3a / T.3b | T.4 already covers the J+8 rejection side. T.3 specifically pins the variable-name and gate-condition; converting both T.3a + T.3b requires building a Hokm fixture that exercises J+9 acceptance separately from X.2. Better to merge into a future "Bot/Bidding.lua extraction with simultaneous T.3 retarget" commit. |
| X.2 (J+9+count≥3 self-sufficient) | X.4 already covers Hokm-on-flipped via withBidcard; X.2's self-sufficient-mardoofa path needs a Hokm fixture without side Ace, which is brittle calibration. Defer to Batch 8 or extraction commit. |
| Y.3a-d | Y.3a/b are covered via AE.1 / X.4. Y.3c (PickPreempt) has no existing behavioral; constructing a PHASE_PREEMPT fixture is brittle. Y.3d is covered by H.10-H.14. Mixed coverage — retire the covered ones individually (defer to Batch 8) or retarget mechanically during extraction. |
| Z.1 / Z.3 (post-bidcard recompute) | Need hand fixtures where bidcard COMPLETES the Belote pair / mardoofa pair. Calibration is brittle (small strength deltas, jitter window dependence). Defer to Batch 8 with explicit jitter-freeze design. |
| AH.6 (partnerBidBonus seatIsBidder) | Behavioral path needs multi-state PickBid fixture spanning bid history + dealer position; very brittle. Defer to Bot/Bidding.lua extraction commit (retarget mechanically). |
| AI.2a/b (tiered smother gate) | Deep pickFollow fixture for foured/tripled vs doubled tiers; high complexity, low payoff. Better handled during pickFollow refactoring (which is not on the near horizon). |
| AA.1a/b (escalationStrength void/sideAce bonus) | Reachable via PickDouble/Triple deviation between void-rich and void-free hands, but the bonus magnitudes are tied to specific thresholds (BOT_DOUBLE_TH etc.) — brittle. Defer to Bot/Escalation.lua extraction commit. |

Pins that should KEEP SOURCE-ONLY indefinitely (diagnostic / comment / ordering / wiring):

| Pin | Category |
|---|---|
| R.2a-e, AD.7a/b | Diagnostic helper pins. Stay source-only. |
| AB.2 / AD.3 / AI.1 / AI.4 / AI.5 / AH.7 | Comment/rationale markers. Stay source-only. |
| Y.2b / X.2b / Z.2 / T.2c | Ordering and absence assertions. Stay source-only. |
| AD.2 / AD.9 | Wiring / diagnostic format. Stay source-only. |

---

## 6. Extraction Readiness Assessment

**Recommendation: Batch 7 is the LAST pure source-pin-to-behavioral cleanup batch. After Batch 7, proceed directly to `Bot/Bidding.lua` extraction (Batch 8) with simultaneous mechanical pin retargets.**

Reasoning:

1. **Pin debt curve has flattened.** Batch 6 retired 7 pins (8 asserts). Batch 7 retires 2 more pins (5 asserts) and adds 2 new behavioral tests (3 asserts). After Batch 7, remaining bidding-area pins fall into two clusters:
   - Pins kept source-only this batch per Codex review (AA.4, AB.3, AH.3) — these are best retired mechanically inside the eventual extraction commit, not in a separate pin-cleanup batch.
   - Pins protecting internal variable names (T.3a, X.2, AH.6) — these are best retargeted as part of the extraction diff itself.

2. **Bot/Tiers.lua (5B) and Bot/PlayPrimitives.lua (5C) extractions retargeted dozens of dependent pins in a single diff** without issue. Bot/Bidding.lua extraction can follow the same pattern — the residual pin retargets are mechanical and contained.

3. **The high-confidence pin cleanups have been done.** The remaining HIGH-difficulty conversions (AH.6 partnerBidBonus split, AI.2 tiered smother gate, T.3 internal flags) yield diminishing returns vs the effort to land them safely.

4. **Behavioral coverage of PickBid / PickOvercall is now strong.** AE.1, AE.1c, AE.2, W.2, X.4, H.10-H.14, AC.4-AC.5, AJ.12 (Belote-escape), AJ.14 (2-Ace bonus boundary), AJ.15 (overcall void-trump bonus boundary) cover the bidding decision space end-to-end. The pin retargets in the extraction commit then become "did we keep the function's signature and dependencies the same?" — a structural check inside the diff itself.

### If Codex disagrees and prefers another pin-cleanup round

A hypothetical Batch 8-as-pin-cleanup would target:
- Z.1 + Z.3 → combined behavioral (bidcard-completes-Belote AND bidcard-completes-mardoofa, two-sub-assert block, jitter-frozen)
- Y.3c (PickPreempt withBidcard) → new PHASE_PREEMPT behavioral
- X.2 (hokmMinShape J+9+count≥3) → behavioral with no-side-Ace Hokm fixture
- AH.3 (PickTriple floor cap) → strengthened behavioral that tightly proves the cap is load-bearing (rather than the general weak-hand non-fire at AK.7)

These are MEDIUM-risk conversions; the risk-vs-reward is less favorable than Batches 5-7.

### After Bot/Bidding.lua: Bot/Escalation.lua

The escalation surface (PickDouble + PickTriple + PickFour + PickGahwa + escalationStrength + partnerBidBonus + partnerBel signaling) has its own pin cluster: AA.1a/b, AH.3, AH.6, AH.7, AI.2a/b, AB.4a-d (state-coupling, not retirement candidates), AC.6. Most are HIGH-difficulty conversions. Recommended path: extract Bot/Escalation.lua in Batch 9 with mechanical pin retargets, same as Bot/Bidding.lua.

---

## 7. Implementation Guardrails For Later

When Batch 7 is implemented (separate prompt, separate feature branch):

- **Expected files to touch:** `tests/test_state_bot.lua` only.
- **No runtime Lua changes.** Bot.lua / Net.lua / State.lua / Rules.lua / UI.lua / UI/Themes.lua / Bot/Tiers.lua / Bot/PlayPrimitives.lua / WHEREDNGN.toc / Constants.lua / Cards.lua / BotMaster.lua / WHEREDNGN.lua / Slash.lua / Sound.lua / Log.lua / MinimapIcon.lua / Easter.lua all stay untouched.
- **Expected harness count:** **1149 / 1149** (1151 baseline − 5 retired source-pin asserts + 3 new behavioral asserts = −2 net).
- **Required standalone smokes:** `tests/test_H1_pin_J9_trump.lua` (11/0), `tests/test_H7_sun_shortest_lead.lua` (9/0).
- **Optional smokes:** `tests/test_numworlds_scaling.lua`, `tests/test_v0.5_traced_game.lua`, `tests/test_bel_decision_quality.lua` (full sweep).
- **Determinism plan:** AJ.14 freezes `math.random` to 0 for both `(-K.BOT_BID_JITTER, K.BOT_BID_JITTER)` and `(-3, 3)` ranges (Codex-verified necessary). AJ.15 does NOT need a jitter freeze (Codex-verified).
- **Retirement comment style:** Batch 3 / Batch 6 pattern — one-line comment at deleted-pin position citing the new behavioral test ID.
- **Feature branch:** `v3.2.0-cleanup-batch7`. Push for Codex review before merge. No release tag.

---

## 8. Summary

**Inventoried 25 candidate source pins** (15 bidding-relevant + 10 escalation-relevant + 13 KEEP-source-only meta-classifications).

**Recommended Batch 7 picks (2 actions, per Codex narrowing):**

1. **Convert W.1** → new **AJ.14** (PickBid 2-Ace Sun bonus boundary, jitter-frozen Codex-verified fixture).
2. **Convert X.1c + X.1d** → new **AJ.15** (PickOvercall void-trump bonus boundary, Hokm overcall window via `S.BeginOvercall`, Codex-verified fixture).

**Kept source-only this batch per Codex review:**
- **AH.3** — AK.7's coverage is too weak; needs a dedicated floor-cap-targeted behavioral.
- **AA.4 + AB.3** — AE.3 smoke is too weak; would still pass under subtle bidderHoldsBidcard regressions.
- All other deferrals from §5.

**Expected test-count delta:** −2 net (5 retired source-pin asserts − 3 new behavioral asserts → 1151 → 1149).

**Extraction-readiness verdict:** Batch 7 should be the **last pure source-pin cleanup batch**. After Batch 7, proceed directly to **Bot/Bidding.lua extraction** in Batch 8, retargeting residual pins (AA.4, AB.3, AH.3, T.3, X.2, AH.6, Y.3, Z.1, Z.3) mechanically inside the extraction commit (same pattern as Batches 5B / 5C).

**Working tree status:** clean except for this design doc untracked at `.swarm_findings/v3_2_0_batch7_design.md`.

Stopping per the prompt's stop conditions. No runtime/test code changed. No implementation branch cut. No commits made. Awaiting Codex review before any implementation.
