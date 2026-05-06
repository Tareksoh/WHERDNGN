# B-Bot-10 — Deep audit: `Bot.PickSWA` and `Bot.PickKawesh` (v0.10.2)

**Track**: B (code review)
**Date**: 2026-05-05
**Scope**: `Bot.PickSWA` (Bot.lua:3854-3938), `Bot.PickKawesh` (Bot.lua:3801-3807),
their joint dispatch site in `Net.MaybeRunBot` (Net.lua:3935-3979 for Kawesh,
4023-4075 for SWA), the validator `R.IsValidSWA` (Rules.lua:383-501), and the
hand-shape predicate `Cards.IsKaweshHand` (Cards.lua:170-177).

**Files inspected**:
- `C:\CLAUDE\WHEREDNGN\Bot.lua` lines 3801-3807 (Bot.PickKawesh), 3854-3938 (Bot.PickSWA, Hokm trump-safety belt-and-suspenders).
- `C:\CLAUDE\WHEREDNGN\Cards.lua` lines 160-177 (M.IsKaweshHand + 50-agent M-1 fix).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` lines 89-210 (R.IsLegalPlay with akaCalled), 383-501 (R.IsValidSWA recursion).
- `C:\CLAUDE\WHEREDNGN\Net.lua` lines 3501-3528 (HostHandleKawesh), 3935-3979 (MaybeRunBot Kawesh dispatch), 4023-4075 (MaybeRunBot bot-SWA dispatch).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-01_swa_pipeline.md` (F-1, F-2 cross-cut).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-04_swa_full.md` (S4 AKA-blind cluster, B-Net-04-3).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\REVIEW.md` lines 85-86, 233-235 (X4 missing-feature ledger MF-16, MF-17).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X4_pro2_deal.md` lines 120-150 (Source-J interpretation).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_H_bidding_penalty.md` H-34.8 — H-34.14 (self-trigger ladder).

---

## Executive verdict

`Bot.PickSWA` is **structurally correct** as a pure delegator to `R.IsValidSWA`
plus a defensive Hokm trump-top-rank gate. Its asymmetry vs the human path
(bot caps at `#hand <= 4`, human can fire at any count) is real but already
filed elsewhere (C-Xref-01 F-1).

`Bot.PickKawesh` is a **one-line policy** — unconditional redeal whenever
`Cards.IsKaweshHand` returns true. This is mechanically correct against the
*current* `IsKaweshHand` predicate but **misses three documented strategy
nuances** (sessional 7-8-9 same-suit prohibition, self-trigger override to
Hokm-buy on honor ground card, partner-Hokm-bid never-kasho).

**Severity tally**: 0 CRITICAL, 0 HIGH, 2 MEDIUM (pre-existing F-1 + B-Net-04
S4 AKA-blind both reach via this entry), 5 LOW (4 missing-strategy items
from MF-16/MF-17 + H-34 source ladder, 1 INFO confirming Sun/Hokm criteria
are *not* differentiated in code).

**No new blocker bugs.** All findings here either confirm prior-track
items (F-1, F-2, B-Net-04 S4) or surface absent-strategy items previously
catalogued in `xref_X4_pro2_deal.md` and `source_H_bidding_penalty.md` but
not yet wired through any picker.

---

## Functional walk-through

### `Bot.PickSWA` (Bot.lua:3854-3938)

```lua
function Bot.PickSWA(seat)
    if not Bot.IsAdvanced() then return false end
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.contract then return false end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 or #hand > 4 then return false end

    -- Reconstruct trick state for the validator.
    local trickPlays = (S.s.trick and S.s.trick.plays) or {}
    local trickLead = S.s.trick and S.s.trick.leadSuit
    local trickLeader
    if #trickPlays > 0 then
        trickLeader = trickPlays[1].seat
    else
        trickLeader = S.s.turn or seat
    end
    local trickState = {
        leadSuit = trickLead, leader = trickLeader, plays = trickPlays,
    }
    -- Build all four hands for the validator.
    local hands = {}
    for s2 = 1, 4 do
        hands[s2] = (S.s.hostHands and S.s.hostHands[s2]) or {}
    end

    -- Delegate to R.IsValidSWA — single source of truth for SWA legality.
    if not R.IsValidSWA(seat, hands, S.s.contract, trickState) then
        return false
    end

    -- v0.5.21 Hokm trump-top safety net (belt-and-suspenders).
    if S.s.contract.type == K.BID_HOKM and S.s.contract.trump then
        local trump = S.s.contract.trump
        local callerTopRank, oppTopRank = -1, -1
        for _, c in ipairs(hand) do
            if C.Suit(c) == trump then
                local r = C.TrickRank(c, S.s.contract)
                if r > callerTopRank then callerTopRank = r end
            end
        end
        for s2 = 1, 4 do
            if R.TeamOf(s2) ~= R.TeamOf(seat) then
                for _, c in ipairs(hands[s2]) do
                    if C.Suit(c) == trump then
                        local r = C.TrickRank(c, S.s.contract)
                        if r > oppTopRank then oppTopRank = r end
                    end
                end
            end
        end
        if oppTopRank > callerTopRank then return false end
    end

    return true
end
```

**Behaviour summary**:
- Five short-circuits before validation (tier, phase, contract, hand-empty, hand>4).
- Reconstructs a trickState compatible with `R.IsValidSWA` from `S.s.trick.plays` + `S.s.trick.leadSuit` + `S.s.turn`.
- Single delegate to `R.IsValidSWA`; if that returns false, bot does NOT call SWA.
- v0.5.21 add-on: in Hokm, additionally rejects if any opponent holds a higher trump than caller's top trump (defense against R.IsValidSWA edge cases — described inline as belt-and-suspenders).

### `Bot.PickKawesh` (Bot.lua:3801-3807)

```lua
function Bot.PickKawesh(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    if S.s.phase ~= K.PHASE_DEAL1 then return false end
    if C.IsKaweshHand and C.IsKaweshHand(hand) then return true end
    return false
end
```

**Behaviour summary**: Three short-circuits, then unconditional `true` whenever
the predicate fires.

**Predicate** (`Cards.IsKaweshHand`, Cards.lua:170-177):
```lua
function M.IsKaweshHand(hand)
    if not hand or #hand < 5 then return false end
    for _, card in ipairs(hand) do
        local r = M.Rank(card)
        if r ~= "7" and r ~= "8" and r ~= "9" then return false end
    end
    return true
end
```

Correctness wrt the simple Saudi rule "5-card hand of all {7,8,9} → annul".
50-agent M-1 fix tightened the empty-hand guard from `#hand == 0` to `#hand < 5`
(prevents partial-deal false-positives). Confirmed.

### Dispatch sites

- **Kawesh** (Net.lua:3951-3961, inside the bid-decision callback):
  ```lua
  if S.s.phase == K.PHASE_DEAL1
     and B.Bot.PickKawesh and B.Bot.PickKawesh(seat) then
      ...
      broadcast(("%s;%d"):format(K.MSG_KAWESH, seat))
      N.HostHandleKawesh(seat)
      return
  end
  ```
  Fires inside the `BOT_DELAY_BID` `C_Timer.After` body, gated by paused, phase, turn, turnKind, and "no bid yet". Kawesh is checked **before** PickBid. The host's `HostHandleKawesh` re-validates with `IsKaweshHand` (Net.lua:3520) — bot can't fake.

- **SWA** (Net.lua:4023-4075, inside the bid-play decision callback):
  ```lua
  if B.Bot.PickSWA and B.Bot.PickSWA(seat) then
      local hand = (S.s.hostHands and S.s.hostHands[seat]) or {}
      local enc = C.EncodeHand(hand)
      ...
      S.s.swaRequest = { caller = seat, ... }
      broadcast(MSG_SWA_REQ)
      -- Auto-accept all opponent bots.
      C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function() ... HostResolveSWA ... end)
      return
  end
  ```
  Fires before PickMelds + PickPlay. Five-second permission window even for
  ≤3-card "instant claim" (per v0.5.17 SWA-card-display fix; see C-Xref-01 §3).

---

## Findings

### B-Bot-10-1 — Bot.PickSWA hand-count gate is bot-only (asymmetric vs human path)

**Severity**: MEDIUM (already filed as **C-Xref-01 F-1**; this audit confirms the
asymmetry from the bot side and adds context per the prompt's check 1.)

**Code quote** (Bot.lua:3866-3871):
```lua
function Bot.PickSWA(seat)
    if not Bot.IsAdvanced() then return false end
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.contract then return false end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 or #hand > 4 then return false end
```

**Evidence of asymmetry**:
- Bot path: `#hand > 4` → `return false`. Bot will NEVER fire SWA at 5, 6, 7, or 8 cards.
- Human path (UI.lua:1997-2030 per C-Xref-01): no hand-count gate. Human at 8 cards round-start can press SWA → routes through `LocalSWA` → `R.IsValidSWA`.

**Repro**: hand = 8 cards round 1, seat 1 (human). UI button visible (`phase == PLAY`,
`localSeat`, `allowSWA ≠ false`, `swaRequest == nil`). User clicks SWA. `LocalSWA` runs
without hand-count check. `R.IsValidSWA` returns false (mathematically: 4 Aces + 4 Tens
+ perfect partner alignment is the only config that passes). HostResolveSWA invalid
branch fires → `handTotal × mult` Qaid against caller's team + caller's melds zeroed
(Net.lua:2940-2952, the v0.10.1 M1 forfeit fix).

**Direction of risk**: user shoots-self at 5+ cards. Bot's `<=4` gate is a strategic
choice mirroring the Saudi convention "≤3 instant claim, 4 conditional, 5+ mandatory
permission and near-impossible to validate". Source #35 line 2353 doesn't FORBID 8-card
SWA — it says "they would never let it pass" — so the human UI path matches the source's
"allowed but discouraged" reading. The bot is conservatively stricter.

**Recommendation** (already pending): mirror `#hand <= 4` at UI.lua:2011 OR document
the asymmetry as intentional (bot conservatism). No new code change required for
B-Bot-10 specifically.

---

### B-Bot-10-2 — Bot.PickSWA strength evaluation is "the validator"

**Severity**: NONE (info; this confirms prompt's check 2.)

**Verdict**: The bot performs **no independent strength heuristic**. The "evaluation"
for SWA is exactly:
1. Five short-circuits (Bot.lua:3866-3871).
2. Pure delegation: `R.IsValidSWA(seat, hands, S.s.contract, trickState)` (Bot.lua:3892).
3. Hokm-only trump-top safety net (Bot.lua:3906-3935) — pure boolean comparison
   `oppTopRank > callerTopRank`.

There is no probability gate, no `math.random`, no threshold like "≥ 0.85". This
matches the design comment in the proposed-patch lineage:

> **C-2 patch (audit_v0.7.1/26_pickswa.md)**: "Delegate correctness entirely
> to the minimax validator. No extra heuristic: if R.IsValidSWA says yes, it
> IS unbeatable."

`Bot.lua:3892`:
```lua
if not R.IsValidSWA(seat, hands, S.s.contract, trickState) then
    return false
end
```

The Hokm trump-top gate is described in-comment as a "belt-and-suspenders" net for
edge cases in the recursive validator; user-direct on v0.5.20 → v0.5.21. It is
conservative (over-rejects) by design, which is the safe direction for SWA.

**No action.**

---

### B-Bot-10-3 — `R.IsValidSWA` call does NOT pass `akaCalled` (D-RT-18 Bug D / B-Net-04 S4)

**Severity**: LOW for the SWA-specific reach (already filed as **B-Net-04 S4**;
**B-Net-04-3** for the broader cluster). Confirms the prompt's check 3.

**Code quote** (Bot.lua:3892):
```lua
-- Delegate to R.IsValidSWA — single source of truth for SWA legality.
if not R.IsValidSWA(seat, hands, S.s.contract, trickState) then
    return false
end
```

`R.IsValidSWA` accepts `(callerSeat, hands, contract, trickState)` — **no
akaCalled parameter**. Internally at Rules.lua:435 the recursion calls:

```lua
local ok = R.IsLegalPlay(c, hand, trickProbe, contract, nextSeat)
```

The 6th parameter `akaCalled` (added in v0.10.2 M4) is **omitted** at that call site.
`Bot.PickSWA` could not pass it through R.IsValidSWA's current signature even if it
wanted to — but the host-side resolver `Net.HostResolveSWA:2915` makes the same
omission, so the asymmetry is consistent end-to-end (no caller-vs-host disagreement).

**Bias direction**: AKA-blind validation under-counts cases where partner has called
AKA on the led suit (AKA-receiver relief — Rules.lua:103-121, J-066/J-067 + v0.10.2 M4).
Without that relief, the recursion treats receiver as bound by must-trump-ruff,
artificially narrowing legal-play sets, generally rendering FEWER claim sequences
valid (false-negative SWA). **Direction is conservative** for the bot — bot under-fires.

**Window** (per B-Net-04 §11): only triggers when (a) AKA banner is live AND (b) caller
seat is the partner of the AKA-caller AND (c) Hokm contract AND (d) caller is at ≤4
cards considering SWA. Narrow.

**Recommendation** (cluster fix): thread `S.s.akaCalled` through R.IsValidSWA's
recursion (4 sites: Bot.lua:3892, Net.lua:2915, Rules.lua:401, Rules.lua:496). Out
of scope for this audit per prior tracks; deferred.

---

### B-Bot-10-4 — Bot.PickSWA does NOT differentiate Sun vs Hokm criteria

**Severity**: NONE (info; addresses prompt's check 4.)

**Verdict**: The validator delegation `R.IsValidSWA` is contract-agnostic in shape
(walks legal plays per `R.IsLegalPlay`, which itself branches on contract type), so
the *core* validity check uses different rules in Sun vs Hokm naturally — but
**Bot.PickSWA itself adds an asymmetric Hokm-only trump-top gate**:

```lua
if S.s.contract.type == K.BID_HOKM and S.s.contract.trump then
    -- ... compute callerTopRank vs oppTopRank ...
    if oppTopRank > callerTopRank then return false end
end
return true
```

Sun has no analogous extra gate. The rationale (v0.5.21 user-reported safety net) is
specific to Hokm because Hokm SWA decisions hinge on top-trump dominance — there's no
analogous single-card "lock" in Sun where one card guarantees winning every remaining
trick of all suits.

**Net effect**: bot is *more conservative* in Hokm than the validator alone would be;
bot trusts the validator alone in Sun. This matches Saudi practice: Hokm SWA is
high-variance because trump is short, so an extra "do you actually own the boss
trump?" check is paranoia; Sun SWA only reaches `R.IsValidSWA == true` after a much
deeper recursion (no trump shortcut), so the validator's verdict is taken at face
value.

**No action.** The asymmetric extra gate is intentional. The fact that *the validator*
handles Sun vs Hokm correctness internally (via the IsLegalPlay branch + per-trick
winner check) is documented in B-Rules-04_isValidSWA.md. The bot wrapper adds Hokm-only
defense in depth.

---

### B-Bot-10-5 — Bot.PickKawesh: unconditional redeal whenever IsKaweshHand fires

**Severity**: LOW (matches Source-J's "redeal is strictly better than playing it"
framing, but **misses three documented sessional/strategic nuances** — see B-Bot-10-7,
B-Bot-10-8, B-Bot-10-9.)

**Code quote** (Bot.lua:3801-3807):
```lua
function Bot.PickKawesh(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    if S.s.phase ~= K.PHASE_DEAL1 then return false end
    if C.IsKaweshHand and C.IsKaweshHand(hand) then return true end
    return false
end
```

**Behaviour**:
- The function returns `true` **unconditionally** whenever `IsKaweshHand` returns
  `true`. There is no game-state context (e.g., partner has bid Hokm, opponent has
  bought, ground card identity, score state).
- Source-J says "redeal is strictly better" framing — the unconditional policy is
  defensible *as a simplification*. But the source ladder H-34.8 — H-34.14
  (`source_H_bidding_penalty.md`) documents at least **five** decision branches
  the bot ignores:
  - H-34.7 Opponent bought + you have kasho hand → default kasho (yes — already covered).
  - H-34.8 Game close-to-finish → may forgive the kasho call to avoid double penalty.
  - **H-34.9 Partner bought Hokm → NEVER kasho (regardless of state)** [bug seed].
  - **H-34.10 Self-trigger: kasho hand + ground J of matching suit → BUY HOKM, don't kasho** [missing-feature; MF-17].
  - **H-34.11 Ground 10 of matching suit → BUY HOKM** [missing-feature; MF-17].
  - **H-34.12 Ground Aka (A or T-mardoofa) → may buy** [missing-feature; MF-17].
  - **H-34.13 Near-kasho (missing 9) → buy only at game start** [missing-feature].
  - **H-34.14 Kasho hand → NEVER buy SUN** [implicit: bot does kasho, so doesn't reach
    the buy-Sun path; functionally OK].

**Dispatch ordering note** (Net.lua:3951): the bid-decision callback checks
PickKawesh **before** PickBid. So the override decision "kasho-hand but ground card
is honor → don't redeal, prefer Hokm" must happen INSIDE PickKawesh (or be staged
between PickKawesh and PickBid via a new override). The code currently has no such
branch.

**Repro** for the bug seed (H-34.9):
1. Round 1, seat 1 (bot, advanced) is dealt 7♠ 8♠ 9♠ 7♥ 8♥ (kasho-shape).
2. Partner (seat 3) is to-bid earlier than seat 1 and bid Hokm-trump=♠ first.
3. Seat 1 reaches its bid turn. `Bot.PickKawesh(1)` returns `true` because
   `IsKaweshHand(hand1)` is true.
4. Bot calls Kawesh, deal annuls, partner's Hokm bid is wiped along with it.

**Source rule**: H-34.9 "Partner bought Hokm → NEVER kasho, regardless of state.
Even if you lose, the loss is small and partner may have a project."

The bot's unconditional PickKawesh **always overrides** the partner-Hokm-no-kasho
rule. The redeal forfeits whatever the partner had built up. Severity is LOW because
the kasho-hand IS unwinnable for the kasho-holder, but the SOURCE explicitly says
"loss is small and partner may have a project" — meaning the kasho-holder should
take the marginal loss to preserve partner's contract. The bot does the opposite.

**Recommendation**: add `S.s.bids[R.Partner(seat)] ~= K.BID_PASS and
S.s.bids[R.Partner(seat)] ~= nil` (i.e., partner has bid something non-pass, presumably
Hokm) → return `false` from PickKawesh as an override.

**Caveat**: this requires the partner-already-bid path to be live. In round-1 bidding
the bid order rotates (forehand first), so seat 1's PickKawesh check may run before
the partner has bid in the same round. The `S.s.bids[partner]` check would be a no-op
if partner hasn't acted yet. A more robust override needs cross-round memory or a
look-ahead. In practice the simpler "if partner has bid Hokm, don't kasho" is the
H-34.9 one-liner that covers most cases.

---

### B-Bot-10-6 — Self-trigger override missing (MF-17 / X-Ref X4 missing-feature)

**Severity**: LOW (matches the prior X4 finding line `xref_X4_pro2_deal.md:137-150`
and `REVIEW.md:86, 234, 279`. Confirms prompt's check 6.)

**Source rules ignored** (from `source_H_bidding_penalty.md`):
- **H-34.10**: kasho-shape AND ground card = J of matching suit → BUY HOKM (you'd
  hold J + 9 + 8 + 7 = 50 meld + 4 trumps; the Hokm is "guaranteed").
- **H-34.11**: ground card = 10 of matching suit → BUY HOKM.
- **H-34.12**: ground card = Aka (A or T-mardoofa) → may buy.

**Current code path** (Bot.lua:3801-3807 + Net.lua:3951-3961):

```
Net.MaybeRunBot bid callback
   │
   ▼
B.Bot.PickKawesh(seat) — returns true on IsKaweshHand
   │
   ├── true → broadcast MSG_KAWESH + N.HostHandleKawesh(seat) + return  ← HARDWIRED
   │
   └── false (i.e., NOT all 7/8/9) → fall through to B.Bot.PickBid(seat)
```

The self-trigger override (MF-17) requires consulting:
- `S.s.cutCard` or equivalent ground/bid-card identity (the "ولد" — bid card on the
  table — is the rank/suit visible at deal time before bidding starts).
- `S.s.contract.trump` candidates.
- The bot's hand to compute trump-suit count if buying Hokm.

**Code quote** (Bot.lua:3801-3807, no override branch):
```lua
function Bot.PickKawesh(seat)
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand then return false end
    if S.s.phase ~= K.PHASE_DEAL1 then return false end
    if C.IsKaweshHand and C.IsKaweshHand(hand) then return true end  -- no override
    return false
end
```

**Repro**: bot dealt 5×{7,8,9} hand including 7♠ 8♠ 9♠ 7♥ 8♥. Ground-card visible to all
is J♠. Source says: **buy Hokm-spades**, get J + 9 + 8 + 7 = "Khamsin" 50-meld bonus
plus 4 spades trump (7,8,9 + the J on the ground if cut-deal mechanic gives it to the
buyer — depends on cut-deal rules). The bot instead does Kawesh → forfeits the 50
meld and the trump dominance.

**Recommendation** (already in MF-17 backlog): rewrite Bot.PickKawesh to consult the
ground card, e.g.:
```lua
if C.IsKaweshHand(hand) then
    if S.s.cutCard and groundCardIsHonorOfMatchingSuit(hand, S.s.cutCard) then
        return false  -- override; let PickBid see the kasho-hand and choose Hokm
    end
    return true
end
```
This requires `S.s.cutCard` (or whatever holds the visible bid card) to be wired and
exposed to bots. Some plumbing audit needed (out of scope for this finding —
xref_X4 line 141 notes the override "would require Bot.PickBid to consult kasho-hand
state" so the partial fix may need to be in TWO sites: PickKawesh exits early, AND
PickBid recognizes the kasho-shape + ground-honor to bid Hokm-matching-suit).

---

### B-Bot-10-7 — Sessional 7-8-9 same-suit Kasho variant missing (MF-16)

**Severity**: LOW (matches REVIEW.md:85, 233; xref_X4_pro2_deal.md:126-135. Confirms
prompt's check 7.)

**Source rule** (`source_H_bidding_penalty.md:482-489`):
> "All 5 cards must qualify — sessional variant: some sessions DISALLOW 7-8-9 of
> same suit ('سرها') and qaid the kasho-caller in that sub-case."

**Two distinct sessional variants exist**:
1. **Disallow-variant**: 7+8+9 of same suit → INELIGIBLE for kasho; if you call
   kasho, you're qaid'd. Some sessions use this.
2. **Trigger-variant**: 7+8+9 of same suit → kasho/redeal eligible *even with only
   3 cards* (looser than the standard 5-card all-{7,8,9}). Other sessions use this.

**Current code** (Cards.lua:170-177):
```lua
function M.IsKaweshHand(hand)
    if not hand or #hand < 5 then return false end
    for _, card in ipairs(hand) do
        local r = M.Rank(card)
        if r ~= "7" and r ~= "8" and r ~= "9" then return false end
    end
    return true
end
```

**No suit check.** The predicate is rank-only. Neither sessional variant is encoded.
Greps for `7.*8.*9.*suit` and `same.suit.*kasho` in Bot/Cards/Rules confirm: nothing.

**Repro**: bot dealt {7♠ 8♠ 9♠ 7♣ 8♥}. `IsKaweshHand` returns `true` (rank-only check
passes; 7+8+9 of spades is part of the hand but mixed with off-spade). With the
disallow-variant active, this would qaid the bot if kasho is called. The bot fires
kasho unconditionally → free qaid for opponents in those sessions.

**Recommendation** (MF-16 backlog): add an opt-in flag (e.g.,
`WHEREDNGNDB.kasho789Disallow`) and a sub-predicate `Cards.HasSameSuit789(hand)`. If
the flag is on AND the sub-predicate fires, force PickKawesh to return `false` (with
in-comment caveat that the player would still need to NOT play kasho voluntarily —
under the disallow variant, the kasho call itself is the qaid trigger).

---

### B-Bot-10-8 — Kawesh detection accuracy: rank-only, no suit considered

**Severity**: NONE (info; addresses prompt's check 8.)

**Verdict**: `Cards.IsKaweshHand` correctly tests "all cards rank ∈ {7,8,9}".
This matches the standard Saudi rule. The 50-agent M-1 fix (Cards.lua:170 comment)
correctly tightened `#hand == 0` → `#hand < 5` to prevent partial-deal false-positives.

**Edge cases verified**:
- 4-card hand of 7/8/9: `#hand < 5` → returns false. Correct (deal not yet complete).
- 5-card hand all 7/8/9: passes both gates. Correct.
- 5-card hand with one T or J: rank loop returns false. Correct.
- 5-card hand all 7/8/9 same-suit (e.g., {7♠, 8♠, 9♠, 7♠ — duplicate}): would still
  return true at the predicate level; the underlying card de-duplication is upstream's
  responsibility (deck integrity). The predicate alone is correct.

**Note**: the predicate is symmetric — it doesn't distinguish suits or session variants
(see B-Bot-10-7). For the *standard* Saudi rule it is exact.

**No action.**

---

### B-Bot-10-9 — Edge case: 8-card hand vs Kawesh detection mid-game

**Severity**: NONE (info; addresses prompt's check 9.)

**Verdict**: Kawesh is **only checked at deal time** by virtue of two gates:

1. `Bot.PickKawesh` (Bot.lua:3804): `if S.s.phase ~= K.PHASE_DEAL1 then return false end`
2. `Net.HostHandleKawesh` (Net.lua:3517): `if S.s.phase ~= K.PHASE_DEAL1 then return end`

PHASE_DEAL1 is the initial 5-card-deal-then-bid phase. After bidding completes, the
phase transitions away (PHASE_DEAL2BID / PHASE_PLAY) and Kawesh is structurally
unreachable.

**Predicate-level guard** (Cards.lua:171): `if not hand or #hand < 5 then return false end`.
This means an 8-card hand of all 7/8/9 (after second-deal completes) **would** still
return `true` from the predicate alone (8 ≥ 5; rank-loop passes). But the phase guards
above prevent any caller from acting on the predicate at 8 cards. The predicate is
self-consistent: any 5-card prefix of an 8-card all-{7,8,9} hand is also kasho-shape,
so the deal-time check is sufficient.

**Repro check**: phase transitions:
- Round-1 deal of 5 → PHASE_DEAL1 → bid round 1 → if all-pass-no-Kawesh → PHASE_DEAL2BID.
- PHASE_DEAL1 is gone by the time the second 3-card deal lands.
- Any retrospective "now I see I have 8 cards of 7/8/9" call is structurally blocked.

**No action.** The two-phase gate is correct and matches Saudi convention (kasho is
a pre-bid procedural redeal; once bidding has completed it is no longer available).

---

### B-Bot-10-10 — Permission-required gating (≥5-card mandatory per video #35)

**Severity**: NONE (info; addresses prompt's check 10.)

**Verdict**: From the BOT side, the gate is **`#hand <= 4` rejects 5+ outright**, so
the bot never enters the "must ask permission for 5+" regime. C-Xref-01 §3 confirms the
*human* path collapses 4-card permission and 5+-card mandatory permission into the
same `needPerm`-default-true single flow (Net.lua:2502 + 2521-2533). For the bot:

- 0 cards: short-circuit (Bot.lua:3871 `#hand == 0`).
- 1-3 cards: would normally be "instant claim" per Saudi convention. v0.5.17 SWA
  display fix routes ALL flows through the 5-second window (Net.lua:4040-4067) — so
  even ≤3 goes through the permission window with auto-accept by opponent bots.
- 4 cards: same 5-second window.
- 5-8 cards: blocked at Bot.lua:3871. Bot does not initiate.

**Mandatory-permission semantics** are upheld because:
(a) Bot does not attempt 5+.
(b) For 1-4, the permission window (with auto-accept by opponent bots) is the addon's
   UX implementation of the Saudi "verbal negotiation no-timeout" convention. CLAUDE.md
   line 41-46 documents this is addon-UX (5-sec timer is not Saudi); video #35 verbatim
   "ما تساوي بدون ما تستاذن مستحيل يمشونها" means "you cannot SWA without asking; it's
   impossible they'd let it pass at 5+".

The bot respects the spirit of "5+ mandatory permission" by simply not firing at 5+.
For 1-4 it uses the addon's permission flow (which an opponent could deny in principle;
in practice opponent bots auto-accept).

**No action.**

---

## Cross-cuts touching this audit

- **C-Xref-01 F-1** (UI hand-count gate missing) — bot has `#hand <= 4`, human doesn't.
  Confirmed from bot side here (B-Bot-10-1).
- **C-Xref-01 F-2** (bot SWA timer pause re-arm asymmetry) — Net.lua:4059's bot-fired
  timer doesn't re-arm on `/pause`, while Net.lua:2552 + 2701 + WHEREDNGN.lua:270 all
  do. Fires from the SAME callback that consumed Bot.PickSWA → true. Re-stating
  here so it's visible from the bot-side audit.
- **B-Net-04-3 / D-RT-18 S4** (R.IsValidSWA AKA-blind) — confirmed at Bot.lua:3892
  (the Bot.PickSWA call site). Direction conservative for bot. Cluster fix needed
  upstream.
- **REVIEW.md:233-234 / xref_X4_pro2_deal.md MF-16, MF-17** — sessional 7-8-9 same-suit
  variant and self-trigger override. Both still missing (B-Bot-10-6, B-Bot-10-7).

---

## Findings summary

| ID | Severity | Layer | Finding | New / Confirmed |
|---|---|---|---|---|
| **B-Bot-10-1** | MEDIUM | Bot | Bot.PickSWA `#hand <= 4` gate is bot-only; human path has no gate | **Confirmed** (C-Xref-01 F-1) |
| **B-Bot-10-2** | INFO | Bot | Bot.PickSWA strength evaluation = pure validator delegation + Hokm trump-top safety net | **Confirmed** (audit_v0.7.1/26) |
| **B-Bot-10-3** | LOW | Bot/Rules | R.IsValidSWA call from Bot.PickSWA does NOT pass akaCalled | **Confirmed** (B-Net-04 §11 / D-RT-18 S4) |
| **B-Bot-10-4** | INFO | Bot | Sun vs Hokm criteria differ: Hokm adds extra trump-top gate; Sun trusts validator alone | **New** (info-only confirmation) |
| **B-Bot-10-5** | LOW | Bot | Bot.PickKawesh unconditional redeal — ignores H-34.9 partner-Hokm-no-kasho | **New** (bug seed; H-34.9) |
| **B-Bot-10-6** | LOW | Bot | Self-trigger override (kasho-hand + ground J/T/A → buy Hokm) NOT implemented | **Confirmed** (MF-17 / xref_X4 / H-34.10-12) |
| **B-Bot-10-7** | LOW | Cards | Sessional 7-8-9 same-suit variant NOT implemented (no suit check in IsKaweshHand) | **Confirmed** (MF-16 / xref_X4 / H-34.6) |
| **B-Bot-10-8** | INFO | Cards | Kawesh detection rank-only; correctness verified for the standard rule | **Confirmed** (matches Cards.lua 50-agent M-1 fix) |
| **B-Bot-10-9** | INFO | Bot/Net | Phase-DEAL1 dual gate prevents 8-card mid-game Kawesh — structurally safe | **New** (info-only confirmation) |
| **B-Bot-10-10** | INFO | Bot | Permission-required gating: bot upper-bounds at 4 cards, never enters 5+ regime | **New** (info-only confirmation) |

---

## Verdict

`Bot.PickSWA` is **structurally correct** — the validator-delegation pattern is sound,
the Hokm trump-top safety gate is documented and conservative, and the
asymmetry vs human SWA is already on the v0.10.3+ backlog (F-1).

`Bot.PickKawesh` is **mechanically correct** for the standard Saudi rule but
**ignores three documented sessional/strategic nuances**:
- H-34.9 (partner Hokm bid → never kasho) — bug seed; one-line fix.
- MF-17 (self-trigger override on honor ground card) — feature gap; ~10-line fix
  with cut-card plumbing.
- MF-16 (sessional 7-8-9 same-suit variant) — feature gap; ~5-line predicate +
  opt-in flag.

**No new blocker bugs.** All findings either confirm prior cross-cut items
(F-1, F-2, B-Net-04 S4) or surface absent-strategy items previously catalogued in
`xref_X4_pro2_deal.md` and `source_H_bidding_penalty.md` but not yet wired through
any picker.

---

## Confidence

**HIGH** on:
- Mechanical correctness of Bot.PickSWA's five-short-circuit + delegate + Hokm-gate flow.
- Mechanical correctness of `Cards.IsKaweshHand` for the standard rule.
- Phase-DEAL1 dual gate making 8-card mid-game Kawesh structurally unreachable (B-Bot-10-9).
- All "INFO" findings (B-Bot-10-2, B-Bot-10-4, B-Bot-10-8, B-Bot-10-9, B-Bot-10-10).
- Confirmation of B-Bot-10-1 / B-Bot-10-3 / B-Bot-10-6 / B-Bot-10-7 against prior tracks.

**MEDIUM** on:
- B-Bot-10-5 H-34.9 partner-Hokm-no-kasho — depends on bid-order (whether partner has
  acted in the same round when seat 1's PickKawesh runs). Fix requires care.
- Whether B-Bot-10-6 self-trigger needs cut-card plumbing or can be implemented with
  existing `S.s.cutCard` (didn't trace cut-card state thread end-to-end here).

**LOW**:
- Whether MF-16 disallow-variant or trigger-variant should be the default; needs
  user/session-config decision.

---

## Files cross-referenced

- `C:\CLAUDE\WHEREDNGN\Bot.lua` — 3801-3807 (Bot.PickKawesh), 3854-3938 (Bot.PickSWA).
- `C:\CLAUDE\WHEREDNGN\Cards.lua` — 160-177 (IsKaweshHand, 50-agent M-1 fix).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — 89-210 (R.IsLegalPlay with akaCalled), 383-501 (R.IsValidSWA).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — 3501-3528 (HostHandleKawesh), 3935-3979 (MaybeRunBot Kawesh dispatch), 4023-4075 (MaybeRunBot bot-SWA dispatch).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-01_swa_pipeline.md`.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-04_swa_full.md`.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\REVIEW.md` lines 85-86, 233-235, 278-279.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X4_pro2_deal.md` lines 120-150.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_H_bidding_penalty.md` H-34.6 — H-34.14.
