# B-Net-04 — Deep audit of the SWA wire pipeline (v0.10.2)

**Track**: B (code review)
**Date**: 2026-05-05
**Scope**: End-to-end audit of the SWA pipeline — UI button → `Net.LocalSWA` → permission flow → `R.IsValidSWA` → `HostResolveSWA` → `S.ApplyRoundEnd` → `R.ScoreRound` sweep branch + `Bot.PickSWA` bot-side asymmetry. Eleven targeted checks.

**Files inspected**:
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 2452-2586 (LocalSWA), 2590-2638 (LocalSWAResp), 2640-2733 (_OnSWAReq), 2735-2807 (_OnSWAResp), 2809-2827 (_OnSWA), 2829-2846 (_OnSWAOut), 2862-3073 (HostResolveSWA), 4023-4075 (MaybeRunBot bot-SWA dispatch).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 355-501 (R.IsValidSWA).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — lines 3854-3938 (Bot.PickSWA).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — lines 196-208 (MSG_SWA_*), 274-281 (SWA_TIMEOUT_SEC).
- Prior swarm work: C-Xref-01_swa_pipeline.md, D-RT-13, D-RT-18, D-RT-20, D-RT-27, D-RT-28, D-RT-31.

---

## Executive verdict

The SWA pipeline is **structurally correct on the happy path** and the v0.10.1 M1 forfeit semantics are integrated cleanly. **No new blocker bugs surface in code-only review**. However, this audit confirms **three real bugs the prior tracks already filed** and isolates **one new MEDIUM finding** (B-Net-04-N1: `_OnSWAResp` accept-path misses pause guard) plus **two LOW notes**.

**Severity tally**: 1 CRITICAL (rule-level, RT-13.1), 4 HIGH (B-Net-04-1 Belote predicate, B-Net-04-2 tied-target backport, B-Net-04-3 Saudi-Master IsLegalPlay), 3 MEDIUM (B-Net-04-N1 pause-resp race, F-1 UI gate, F-2 bot-timer pause), 4 LOW (banner countdown, R.IsValidSWA AKA-blind, F-4 Takweesh race, RT-13.7-A reload re-arm).

---

## Pipeline structural map (cross-cut, for reference)

```
UI button (UI.lua:1997-2030, no hand-count gate — F-1)
   │
   ▼
Net.LocalSWA (Net.lua:2473-2586)
   ├── needPerm always true (default; ≤3 / 4 / ≥5 collapse to one path)
   ├── Builds S.s.swaRequest with encodedHand + ts + windowSec
   ├── N.SendSWAReq → MSG_SWA_REQ broadcast (Net.lua:2521)
   ├── if isHost: bot auto-accept loop (Net.lua:2526-2533)
   ├── if isHost: C_Timer.After 5s with pause re-arm (Net.lua:2546-2576)
   │
   ▼ [remote SWA path]
Net._OnSWAReq (Net.lua:2640-2733)
   ├── Same swaRequest build / bot auto-accept / 5s timer with pause re-arm
   │
   ▼ [opponent vote arrives]
Net._OnSWAResp (Net.lua:2735-2807)
   ├── deny → swaRequest = nil, swaDenied set, MaybeRunBot re-pump
   ├── accept counted: if accepts ≥ 2 → HostResolveSWA (NO pause guard — N1)
   │
   ▼ [timer fires OR both accepts arrive]
Net.HostResolveSWA (Net.lua:2862-3073)
   ├── R.IsValidSWA (Rules.lua:383-501, AKA-blind — RT-18 S4)
   ├── invalid → Qaid (offender melds zeroed, Belote scan player-gated — D-RT-20)
   ├── valid → synthetic 8-trick history, R.ScoreRound (Rules.lua sweep branch correct)
   │
   ▼
S.ApplyRoundEnd → tied-target check at Net.lua:3062-3068 (bidder-team-wins-tie — D-RT-28)
```

---

## 1. ≤3-card instant claim (collapsed to permission flow)

**Verdict**: NOT a separate path in current code. Confirmed.

`Net.lua:2502` gates on `needPerm`, which is `WHEREDNGNDB.swaRequiresPermission ~= false` — true by default. The "instant claim" branch at lines 2581-2585 is dead code unless the savedvar is explicitly toggled:

```lua
-- Net.lua:2499-2585
if needPerm then
    -- Permission flow: broadcast a request, wait for opponents.
    ...
    return
end
-- Direct claim (≤3 cards or permission disabled): send the actual
-- SWA wire and let the host resolve immediately.
local enc = C.EncodeHand(S.s.hand or {})
N.SendSWA(S.s.localSeat, enc)
if S.s.isHost then N.HostResolveSWA(S.s.localSeat, S.s.hand or {}) end
```

The intentional collapse is documented at `Net.lua:2479-2484`:

> "Calls with ≤3 cards used to be instant; v0.5.17 routes ALL calls through the 5-second permission display so the caller's cards are visible to all players in every scenario."

**Severity**: INFO — design choice, not a bug. Saudi convention permits instant-claim at ≤3, but the addon's UX choice is "always show banner so opps can Takweesh-counter."

---

## 2. 4-card permission flow

**Verdict**: CORRECT — same path as ≤3-card and ≥5-card, no per-count branching.

The permission flow is the single `if needPerm then ...` branch at Net.lua:2502. There is no hand-count branch in N.LocalSWA after the initial gate — `handCount` is only used for `S.s.swaRequest.handCount` (UI display) and is NOT consulted for routing logic.

**No issue.**

---

## 3. ≥5-card mandatory permission (per video #35)

**Verdict**: **CRITICAL rule-level violation (RT-13.1 confirmed)**. The 5-second auto-approve violates Saudi mandatory-permission rule.

**Source rule** (per video #35, verbatim from `reaudit_R3_swa.md`):
- Line 2244: "في شيء اسمه سوا من اول يد" — "there's a thing called 'swa from first hand'"
- Line 2404: "هنا تستالن طبعا ما تساوي" — "here you absolutely must ask permission"
- Line 2414: "لو ساويت بدون ما تستاذن يا سلام هذه مستحيل يمشونها" — "if you swa'd without asking permission — wow — they would never let it pass"

**Code** (Net.lua:2546):

```lua
C_Timer.After(windowSec, function()
    if not S.s.isHost then return end
    if S.s.paused then ... return end
    local req = S.s.swaRequest
    if not req or req.caller ~= mySeat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(mySeat, pinnedHand)  -- silent-consent → resolve
end)
```

The same 5-second timer handles ≥5-card SWAs. There is no hand-count branch. **For ≥5-card claims this inverts the Saudi rule**: silence becomes consent where the rule demands explicit verbal grant.

**Reproduction**: 4-player table, 1 partner + 2 opp bots + 1 opp human. Caller (the host) fires SWA at 8 cards round 1 trick 1. The 2 opp bots auto-accept (Net.lua:2528-2533). Human opp has 5 seconds to deny via Takweesh / Accept-Deny vote. If the human is AFK / lagged / didn't see the banner, the timer fires; HostResolveSWA runs; R.IsValidSWA almost-certainly returns false; Qaid penalty applied AGAINST the caller. The user gets the Qaid that Saudi convention WOULD apply — but via "silent permission then validate," not "demand permission then play."

**Severity**: CRITICAL (rule-level), but **the bug is by-design per CLAUDE.md** (lines 41-46):

> "The 5-second auto-approve timer is an addon UX construct, NOT a Saudi rule. ... The addon's auto-approve prevents network deadlock when humans don't respond."

The addon authors KNOW this is a divergence; the documented justification is deadlock prevention. **Recommendation** (already on D-RT-13 backlog): branch on hand-count — ≥5 = explicit-accept-only OR timeout-deny semantics.

**No code change required by the prompt** (audit is read-only).

---

## 4. Permission timer (5s auto-approve)

### 4a. Bot-fired path missed pause re-arm (F-2 confirmed)

**Verdict**: **MEDIUM bug confirmed**. Three timer-arming sites have inconsistent pause behavior.

| Site | Lines | Pause re-arm? |
|---|---|---|
| `N.LocalSWA` host-self timer | 2546-2576 | YES (lines 2552-2569) |
| `N._OnSWAReq` remote-receive timer | 2693-2730 | YES (lines 2701-2718) |
| `MaybeRunBot` bot-fired timer | **4059-4067** | **NO — bare early-exit** |
| `WHEREDNGN.lua` PLAYER_LOGIN restore | 270-292 | YES re-arm; bare pause-exit (RT-13.7-C / 13.4-A) |

**The bad path** (Net.lua:4059-4067):

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not S.s.isHost then return end
    if S.s.paused then return end                   -- <-- bare early-exit, no re-arm
    local req = S.s.swaRequest
    if not req or req.caller ~= seat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(seat, hand)
end)
```

vs. the GOOD path (Net.lua:2552-2569):

```lua
if S.s.paused then
    local req2 = S.s.swaRequest
    if req2 and req2.caller == mySeat then
        req2.ts = (GetTime and GetTime()) or req2.ts
        if C_Timer and C_Timer.After then
            C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
                if S.s.isHost and S.s.swaRequest
                   and S.s.swaRequest.caller == mySeat
                   and S.s.phase == K.PHASE_PLAY
                   and not S.s.paused then
                    S.s.swaRequest = nil
                    N.HostResolveSWA(mySeat, pinnedHand)
                end
            end)
        end
    end
    return
end
```

**Practical consequence**: bot fires SWA → host pauses within the 5-sec window → timer fires while paused → bare early-exit → `swaRequest` stays populated. Banner stuck. Workarounds: human opp clicks Takweesh, /reload (which does fire WHEREDNGN.lua:270-292's re-arm), or the next round-start's ApplyStart wipe.

**Severity**: MEDIUM. Recommendation: copy LocalSWA's pause re-arm block to MaybeRunBot's timer (F-2 in C-Xref-01).

### 4b. UI no hand-count gate (F-1 confirmed)

**Verdict**: **MEDIUM confirmed**. UI button (UI.lua:1997-2030) has no `#hand <= 4` gate; bot does (Bot.lua:3871). Asymmetric. Humans can fire 8-card SWA — gated only by R.IsValidSWA's deterministic check, which will return false in 99.99%+ cases → Qaid penalty against the caller.

**Severity**: MEDIUM. Self-grief (caller chose) — not adversarial-grief.

---

## 5. R.IsValidSWA adversarial-partner over-rejection (D-RT-31 confirmed; deferred)

**Verdict**: **Known v0.5.17 design trade-off, deferred per D-RT-31**.

**Code** (Rules.lua:494-500):

```lua
for _, card in ipairs(legal) do
    local nh, ns = applyMove(card)
    if not R.IsValidSWA(callerSeat, nh, contract, ns) then
        return false
    end
end
return true
```

Every legal play of every seat (caller, partner, both opponents) must lead to a winning subtree. Partner is treated adversarially.

**Specific over-rejection scenarios** (per D-RT-31):
- Hokm two-hand SWA via partner-ruff
- Hokm two-hand SWA via مجاوب (matching-side-suit)
- Sun two-hand SWA
- 4-card × 4-seat round-end two-hand SWA

Bot impact: ZERO (Bot.PickSWA only fires when validator returns true; over-rejection just means missed opportunities).

Human impact: an expert who tries the canonical two-hand SWA strategy from video #35 will hit the strict rejection roughly every time.

**Severity**: deferred — pending user re-arbitration on whether to add a cooperative-mode flag.

---

## 6. Cross-Takweesh during SWA window (D-RT-13 confirmed)

**Verdict**: **CORRECT — Takweesh dominance is sound (RT-13.5)**.

Path verified end-to-end:

```
SWA window open → swaRequest = { caller = A, responses = {} }
Opp B calls Takweesh:
  N.LocalTakweesh → broadcast MSG_TAKWEESH → N._OnTakweesh on host
  → N.HostResolveTakweesh(B)
    Net.lua:2129: phase guard (PHASE_PLAY) ✓
    Net.lua:2144: S.s.swaRequest = nil   ← explicit clear
    Net.lua:2150-2162: scanIllegal across all tricks (caller A's plays)
    Net.lua:2175: winnerTeam = (foundIllegal ? B's team : A's team)
    Net.lua:2196-2218: Saudi Qaid: offender's melds zeroed, winner's kept
    Net.lua:2264: S.ApplyRoundEnd

Later: SWA's 5-sec timer fires (Net.lua:2546 timer body):
  Net.lua:2570: `local req = S.s.swaRequest` → nil → return ✓
```

**Verdict**: deterministic per-host; no host-vs-host race exists because only the host runs the timer. swaRequest nil-check at every site is the dominant defense.

**Sub-finding (F-4 informational, RT-13.5-A)**: the bot auto-accepts at Net.lua:2683 fire SYNCHRONOUSLY inside `_OnSWAReq` BEFORE the function returns. So when Takweesh arrives, `req.responses` may already contain bot accepts. **Harmless** because `HostResolveTakweesh` is the dominant resolver and `_OnSWAResp` re-checks `req` for nil before recording further accepts.

---

## 7. Mid-SWA /reload (D-RT-13.7 + D-RT-27 F-15 mid-resolve race)

**Verdict**: **5s window RESTARTS post-/reload (correct), but TWO LOW sub-findings.**

**Code** (WHEREDNGN.lua:270-292):

```lua
if B.State.s.swaRequest and B.State.s.swaRequest.caller
   and B.State.s.phase == K.PHASE_PLAY then
    -- The 5s clock restarts so opponents see a full window post-reload.
    local req = B.State.s.swaRequest
    req.ts = (GetTime and GetTime()) or req.ts
    if C_Timer and C_Timer.After then
        C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
            if not B.State.s.isHost then return end
            if not B.State.s.swaRequest then return end
            if B.State.s.swaRequest.caller ~= req.caller then return end
            if B.State.s.phase ~= K.PHASE_PLAY then return end
            if B.State.s.paused then return end                  -- <-- bare exit
            local hand = (req.encodedHand
                          and B.Cards.DecodeHand(req.encodedHand))
                         or {}
            local caller = req.caller
            B.State.s.swaRequest = nil
            B.Net.HostResolveSWA(caller, hand)
        end)
    end
end
```

**Sub-finding RT-13.7-A (LOW)**: WHEREDNGN.lua:283 has the same bare `if B.State.s.paused then return end` early-exit pattern as MaybeRunBot — same drop-on-pause failure mode. If a player /reloads during a paused game, this re-arm fires once and exits if still paused, without re-arming.

**Sub-finding RT-13.7-B (LOW)**: theoretical exploit — a malicious host could repeatedly /reload to extend the SWA window (the 5s clock restarts each /reload). Practical risk LOW; opponents can still Takweesh.

**D-RT-27 F-15 mid-resolve race** noted in D-RT-27 line 269-298: the `swaRequest` field is intentionally NOT in TRANSIENT_FIELDS (so it survives /reload). The "abandoned-round-end fork" gap is: if HostResolveSWA fires AFTER ApplyRoundEnd has already moved phase to PHASE_SCORE, a stale `swaRequest` could persist. **The phase guards at every timer site (Net.lua:2572 / 2722 / 4064 / WHEREDNGN.lua:284) prevent reaching HostResolveSWA in PHASE_SCORE.** ApplyStart wipes swaRequest defensively at next round.

**Severity**: LOW. No round-end miscount surface confirmed.

---

## 8. v0.10.1 M1 forfeit in invalid-SWA branch (line 2939: `mpA = (callerTeam == "A") and 0 or meldA`)

**Verdict**: **CORRECT**. v0.10.1 M1 fix verified in place.

**Code** (Net.lua:2940-2952):

```lua
-- Saudi Qaid rule (offender melds forfeited).
--
-- v0.10.1 M1 fix (user-arbitrated): an invalid-SWA call is a Qaid
-- context — the caller (offender) forfeits their team's own declared
-- melds. Per Source H H-36.12 + PDF 02 K-04 ("the buyer's meld is
-- forfeited"), offender's melds are not just transferred elsewhere —
-- they are zeroed for the round.
local mpA = (callerTeam == "A") and 0 or meldA
local mpB = (callerTeam == "B") and 0 or meldB
```

Matches `HostResolveTakweesh`'s offender-forfeit semantics (Net.lua:2216-2218):

```lua
-- HostResolveTakweesh
local offenderTeam = (winnerTeam == "A") and "B" or "A"
local mpA = (offenderTeam == "A") and 0 or meldA
local mpB = (offenderTeam == "B") and 0 or meldB
```

Saudi-strict deterministic-or-bust; offender forfeits melds, non-offender keeps theirs, Belote independent. The two paths are aligned.

**Severity**: INFO — no bug.

---

## 9. Belote scan in invalid-SWA branch — D-RT-20 confirmed STILL PLAYER-LEVEL

**Verdict**: **HIGH BUG (B-Net-04-1)**. The v0.9.0 M5 team-level Belote-cancel fix was applied to `R.ScoreRound` but **NOT** to the `HostResolveSWA` invalid branch. The pre-v0.9.0 player-gated predicate is still in place.

**Code** (Net.lua:2968-2977):

```lua
if kWho and qWho and kWho == qWho then
    beloteOwner = R.TeamOf(kWho)
    local list = (S.s.meldsByTeam and S.s.meldsByTeam[beloteOwner]) or {}
    for _, m in ipairs(list) do
        if m.declaredBy == kWho and (m.value or 0) >= 100 then
            beloteOwner = nil
            break
        end
    end
end
```

vs. `R.ScoreRound`'s post-v0.9.0 M5 team-level predicate (Rules.lua:738-746):

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

**Bug reproduction**:

- Hokm contract.
- Seat 1 holds K-of-trump and Q-of-trump (would-be Belote +20).
- Seat 3 (seat 1's partner) declared a quinte (100 raw). Seat 1 has no ≥100 meld personally.
- An invalid SWA fires.

In the SWA-invalid branch at Net.lua:2972, `m.declaredBy == kWho` skips partner's quinte (declaredBy ≠ K-holder). Cancellation does NOT fire. Belote = +20 raw applied. ❌ Pre-v0.9.0 buggy behavior.

In `R.ScoreRound` (regular round-end): partner's quinte cancels Belote. Final Belote = 0. ✅

**EV impact**: +20 raw incorrectly added to the K+Q holder's team in the invalid-SWA path. Belote is multiplier-immune so the swing is flat **+2 nq per affected round**. Probability ~0.003-0.012% of all rounds.

**Severity**: HIGH (correctness bug, predicate divergence) but very low frequency. Same bug exists in `HostResolveTakweesh` (Net.lua:2239-2244) — D-RT-20's primary HIGH finding.

**Recommendation** (D-RT-20): align the two Net.lua sites with R.ScoreRound's M5 predicate; drop the `m.declaredBy == kWho` clause.

---

## 10. Score-boundary tied-target — D-RT-28 confirmed bidder-team-wins-tie (D-RT-28 NOT BACKPORTED v0.8.6 H3)

**Verdict**: **HIGH BUG (B-Net-04-2)**. The v0.8.6 H3 multi-criteria tiebreaker is in `_HostStepAfterTrick` only; the SWA-invalid branch has the pre-v0.8.6 H3 bidder-shortcut.

**Code** (Net.lua:3062-3068):

```lua
if totA >= S.s.target or totB >= S.s.target then
    local winner
    if totA == totB and S.s.contract and S.s.contract.bidder then
        winner = R.TeamOf(S.s.contract.bidder)
    elseif totA > totB then winner = "A"
    elseif totB > totA then winner = "B"
    else                    winner = "A" end
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

vs. the v0.8.6 H3 fix at `_HostStepAfterTrick` (Net.lua:1693-1709):

```lua
if totA == totB then
    if res.gahwaWonGame and res.gahwaWinner then
        winner = res.gahwaWinner
    elseif S.s.contract and S.s.contract.bidder then
        local bidderTeam = R.TeamOf(S.s.contract.bidder)
        if res.bidderMade then
            winner = bidderTeam       -- bidder made → they win tie
        else
            winner = (bidderTeam == "A") and "B" or "A"
                                      -- bidder failed → opp won round
        end
    else
        winner = "A"                  -- defensive fallback
    end
elseif ...
```

**Bug**: an invalid SWA call is by definition the caller's team failing. If caller is on the bidder team, the SWA-invalid branch awards the tie to the BIDDER (caller's) team — even though they just failed the round. ❌

**Probability**: sub-0.1% (both teams exactly at target after Qaid/SWA). When triggered: awards the match to the team that just lost the round. Severity LOW probability, HIGH impact.

**Same bug exists in `HostResolveTakweesh` (Net.lua:2327-2331)** — D-RT-28's primary finding.

**Recommendation**: backport the v0.8.6 H3 priority chain from Net.lua:1693-1709 to both 2327-2331 and 3064-3068. For Takweesh: offender's team always loses; for Invalid-SWA: caller's team always loses.

---

## 11. AKA-aware R.IsValidSWA (D-RT-18 Bug D — AKA-blind reachable from live SWA validation)

**Verdict**: **HIGH BUG (B-Net-04-3) for the broader cluster, LOW for the SWA-specific reach (RT-18 S4)**.

**The cluster (D-RT-18)**: `R.IsLegalPlay` gained an optional 6th param `akaCalled` in v0.10.2 M4. Live-play sites pass it; some sites silently lose it. The audit-relevant sites for the SWA pipeline:

| Site | Live? | Passes akaCalled? |
|---|---|---|
| `Bot.lua:1610` legalPlaysFor heuristic | yes | YES |
| `Net.lua:2040` LocalPlay misclick warn | yes | YES |
| `Net.lua:3412` AFK auto-play | yes | YES |
| `Net.lua:4136` bot-side host fallback | yes | YES |
| `State.lua:1219` ApplyPlay Takweesh illegal-mark | yes | YES |
| `BotMaster.lua:830` BM.PickPlay decision-point | **yes** | **NO (S1 — HIGH)** |
| `BotMaster.lua:649` heuristicPick rollout | rollout | NO (defensible) |
| `Rules.lua:435` R.IsValidSWA recursion | **dual** | **NO (S4 — LOW)** |
| `State.lua:1665` HostValidatePlay | latent | NO (S2b) |
| `State.lua:1966` GetLegalPlays UI dimming | yes | NO (S2) |

**The SWA-specific reach** (S4, Rules.lua:430-437):

```lua
-- Build legal-play set for this seat.
local trickProbe = { leadSuit = leadSuit, plays = plays }
local legal = {}
local hand = hands[nextSeat] or {}
for _, c in ipairs(hand) do
    local ok = R.IsLegalPlay(c, hand, trickProbe, contract, nextSeat)
    if ok then legal[#legal + 1] = c end
end
```

`R.IsValidSWA` is invoked from:
- `Net.lua:2915` (HostResolveSWA — live-play SWA validator gate).
- `Bot.lua:3892` (Bot.PickSWA gate).

Both are LIVE. Inside the recursion, `R.IsLegalPlay` is called WITHOUT `akaCalled` — so the validator's projection of partner / opponent plays under an active AKA banner is AKA-blind. **Direction of bias: SWA-conservative** (false-negative SWA).

**Reachability window** (RT-18 S4 line 437):
1. SWA caller is the AKA caller's PARTNER.
2. SWA call is mid-trick (before partner plays).
3. Opp has cut over partner's AKA'd lead (so receiver-relief is meaningful).

Narrow but reachable.

**Severity**: LOW for the SWA-specific reach (window is narrow; bot direction is conservative). HIGH for the broader cluster (S1: BotMaster.PickPlay:830 silently reverts Saudi Master tier to AKA-blind legality, negating v0.10.2 M4's primary intent).

**Recommendation**: thread `S.s.akaCalled` through the R.IsValidSWA recursion (out of scope per prompt; deferred).

---

## New finding: B-Net-04-N1 — `_OnSWAResp` accept-path missing pause guard (MEDIUM)

**Verdict**: **NEW MEDIUM**. Cross-cut from C-Xref-01 § "Pause behavior" line 326-333 / D-RT-13 RT-13.11.

`HostResolveSWA` (Net.lua:2862-3073) checks `S.s.phase ~= K.PHASE_PLAY` at line 2864 but does NOT check `S.s.paused`.

**Reachable paths**:
1. **From timers**: all four timer sites (LocalSWA 2546, _OnSWAReq 2693, MaybeRunBot 4059, WHEREDNGN.lua restore 270-292) check `S.s.paused` first. ✓
2. **From `_OnSWAResp` accept-path** (Net.lua:2800-2806): when both opponents accept, calls HostResolveSWA. **No pause check.** ✗
3. **From direct ≤3-card path** (Net.lua:2585): dead code if `WHEREDNGNDB.swaRequiresPermission` default holds.

**Code** (Net.lua:2800-2806):

```lua
if accepts >= 2 then
    -- Both opponents granted permission. Resolve the claim using
    -- the encoded hand stashed in the request.
    local hand = C.DecodeHand(req.encodedHand or "")
    S.s.swaRequest = nil
    N.HostResolveSWA(caller, hand)         -- <-- runs even if S.s.paused
end
```

**Race**: caller pauses while opponent #1's accept is in flight. Pause arrives → `S.s.paused = true`. Opponent #1's accept arrives → `_OnSWAResp` runs, sets `req.responses[opp1] = true`. Opponent #2's accept arrives → `_OnSWAResp` runs, both opps now accepted, calls `HostResolveSWA(caller, hand)`. **HostResolveSWA runs while `S.s.paused == true`**.

**Practical consequence**: round resolves mid-pause. The pauser thinks they can veto / confer; the SWA resolves anyway. Mild rule-violation surface — Saudi convention has no pause concept; Saudi-correct semantics are "pause is best-effort UX, cannot block already-consented actions." But it's surprising UX.

**Severity**: MEDIUM. Note that `LocalSWAResp` itself is pause-gated (Net.lua:2591 `if S.s.paused then return end`), so a HUMAN cannot vote while paused. The race window is "human voted before pause; pause arrives mid-resolve." For host-pause-vs-bot-auto-accept, the bots ALL fire synchronously in the same frame as `_OnSWAReq` (Net.lua:2683), so a pause that arrives between bot-accepts is unlikely.

**Quote code**: Net.lua:2800-2806 above + Net.lua:2862-2865 (HostResolveSWA entry):

```lua
function N.HostResolveSWA(callerSeat, callerHand)
    if not S.s.isHost or not S.s.contract then return end
    if S.s.phase ~= K.PHASE_PLAY then return end       -- <-- no S.s.paused check
    N.CancelTurnTimer()
    ...
```

**Recommendation**: add `if S.s.paused then return end` at HostResolveSWA line 2864, OR add it in `_OnSWAResp` line 2800 before the `accepts >= 2` check (which would defer the resolution until unpause and avoid clobbering swaRequest mid-flight).

---

## Findings summary

| ID | Severity | Layer | Finding | Status |
|---|---|---|---|---|
| **RT-13.1** | CRITICAL (rule) | Net | 5+-card SWA auto-approves on silence (inverts Saudi mandatory-permission rule) | **Confirmed** (D-RT-13) |
| **B-Net-04-1** | HIGH | Net | Belote-cancel predicate in HostResolveSWA invalid branch is pre-v0.9.0 player-gated | **Confirmed** (D-RT-20) |
| **B-Net-04-2** | HIGH | Net | Tied-target tiebreaker in HostResolveSWA NOT v0.8.6 H3 multi-criteria | **Confirmed** (D-RT-28) |
| **B-Net-04-3** | HIGH (cluster) | Rules/Bot | R.IsValidSWA AKA-blind; broader S1 BotMaster.PickPlay:830 cluster | **Confirmed** (D-RT-18) |
| **B-Net-04-N1** | **MEDIUM (NEW)** | Net | `_OnSWAResp` accept-path missing pause guard before HostResolveSWA | **NEW from this audit** |
| **F-1** | MEDIUM | UI | UI button no hand-count gate (humans can fire 8-card SWA) | **Confirmed** (C-Xref-01) |
| **F-2** | MEDIUM | Net | MaybeRunBot bot-fired timer no pause re-arm | **Confirmed** (C-Xref-01) |
| **D-RT-31** | MEDIUM (deferred) | Rules | R.IsValidSWA partner-adversarial over-rejection | **Confirmed; deferred** |
| **F-3** | LOW | UI | renderSWABanner countdown drift on pause | **Confirmed** (C-Xref-01) |
| **RT-18 S4** | LOW | Rules | R.IsValidSWA recursion AKA-blind (narrow window) | **Confirmed** (D-RT-18) |
| **F-4** | LOW (info) | Net | Takweesh-during-SWA bot accepts partially populated | **Confirmed** (C-Xref-01) — harmless |
| **RT-13.7-A** | LOW | WHEREDNGN.lua | PLAYER_LOGIN re-arm has bare paused-exit | **Confirmed** (D-RT-13) |

---

## Pipeline correctness verdict

The SWA pipeline is **functionally correct on the happy path** and the v0.10.1 M1 forfeit-melds fix is **integrated cleanly**. The 5-sec timer is consistently treated as addon-UX (per CLAUDE.md). No new blocker bugs surface in code-only review.

The cumulative known-bug surface is:
- 1 CRITICAL rule-level (RT-13.1) — accepted-by-design per CLAUDE.md but documented as a divergence.
- 3 HIGH (B-Net-04-1, B-Net-04-2, B-Net-04-3) — all confirmed in prior tracks; mechanical fixes (predicate alignment, tiebreaker backport, akaCalled threading).
- 4 MEDIUM (1 NEW: B-Net-04-N1) — pause races, UI gates.
- 4 LOW — banner UX, narrow-window AKA-blind, info-only.

**No code modifications were made.** This audit is read-only per the prompt.

---

## Confidence

**HIGH** on:
- Pipeline structural correctness end-to-end (matches C-Xref-01 baseline).
- v0.10.1 M1 forfeit semantics integration (Net.lua:2940-2952 verified).
- The three HIGH backports (B-Net-04-1 / -2 / -3) — all reproduced from prior track findings with code-quoted predicates.
- B-Net-04-N1 reachability — `_OnSWAResp` accept-path verified to call `HostResolveSWA` without `S.s.paused` check; HostResolveSWA verified to lack the guard at line 2864.
- F-1 / F-2 confirmation against bot-vs-human asymmetry.

**MEDIUM** on:
- B-Net-04-N1 practical-impact magnitude — the pause-race window requires a vote-in-flight at exact pause-arrival timing. Hard to estimate empirically without instrumentation, but the structural gap is unambiguous.
- Whether RT-13.1's "by-design" exemption should override the CRITICAL severity. The addon authors documented the divergence; the rule says it's wrong.

**LOW** on:
- D-RT-27 F-15 mid-resolve race surface — phase guards make this practically unreachable but the structural concern around `swaRequest` being non-transient persists.

---

## Files cross-referenced

- `C:\CLAUDE\WHEREDNGN\Net.lua` — 2473-2586 (LocalSWA), 2590-2638 (LocalSWAResp), 2640-2733 (_OnSWAReq), 2735-2807 (_OnSWAResp), 2809-2827 (_OnSWA), 2829-2846 (_OnSWAOut), 2862-3073 (HostResolveSWA), 4023-4075 (MaybeRunBot bot-SWA dispatch).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — 355-501 (R.IsValidSWA), specifically 397-404 (V14 4-play resolve), 418-420 (v0.5.17 short-circuit), 435 (AKA-blind), 471-499 (partner-adversarial design).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — 3854-3938 (Bot.PickSWA, including Hokm trump-safety gate).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — 196-208 (MSG_SWA_*), 274-281 (SWA_TIMEOUT_SEC = 5).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — 270-292 (PLAYER_LOGIN restore re-arm).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-01_swa_pipeline.md` — F-1 / F-2 / F-3 / F-4 baseline.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-13_swa_permission_race.md` — CRITICAL RT-13.1 + race verifications.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-18_aka_simulator_mismatch.md` — S1 / S4.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-20_belote_cancel_edges.md` — Net.lua predicate divergence.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-27_reset_redeal.md` — swaRequest non-transient + abandoned-fork.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-28_score_boundary.md` — tiebreaker not backported.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-31_swa_partner_adversarial.md` — over-rejection deferred.
- `C:\CLAUDE\WHEREDNGN\CLAUDE.md` — lines 41-46 (SWA timer addon-UX disclaimer).
