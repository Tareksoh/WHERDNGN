# B-Net-05: Deep audit of AKA wire path (v0.10.2 M3 false-AKA + M4 receiver-relief)

**Scope.** End-to-end audit of the AKA mechanism following v0.10.2 closure of M3 (host-side false-AKA = Qaid via `.illegal` mark) and M4 (receiver-relief at `R.IsLegalPlay` legality layer). Cross-references prior findings: D-RT-04, D-RT-07, D-RT-18, D-RT-19, D-RT-29, D-RedTeam-01, B-Bot-03, B-Rules-01, B-Rules-08, X2.

**Read-only audit. No code modified.**

**Files inspected (verbatim line citations):**

- `C:\CLAUDE\WHEREDNGN\Net.lua` — `N.LocalAKA` (2344-2372), `N._OnAKA` (3075-3096), `N.SendAKA` (208-210), MSG_AKA replay (461-464), bot AKA dispatch (4096-4102), AFK / fallback IsLegalPlay (3412, 4136), LocalPlay IsLegalPlay (2040)
- `C:\CLAUDE\WHEREDNGN\State.lua` — `S.ApplyAKA` (1443-1450), false-AKA detection in `S.ApplyPlay` (1238-1265), trick-end clear (1327), `S.LocalAKAcandidate` (1387-1402), `S.HighestUnplayedRank` (1367-1381), `S.HostValidatePlay` (1660-1666), `S.GetLegalPlays` (1961-1969), `s.akaCalled` transient field (216), `S.ApplyPlay` IsLegalPlay (1219)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `R.IsLegalPlay` AKA-relief (89-210), `R.IsValidSWA` recursion (435)
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — `Bot.PickAKA` (3261-3370), `pickFollow` AKA-receiver branch (2484-2558), `legalPlaysFor` (1600-1614), touching-honors WRITE (449-508), `Bot.OnPlayObserved` (340-356)
- `C:\CLAUDE\WHEREDNGN\BotMaster.lua` — `BM.PickPlay:830` outer driver, rollout `heuristicPick:649`

---

## Wire path summary (the canonical happy-path)

1. **Sender.** `Bot.PickAKA(seat, leadCard)` returns the AKA suit when conditions hold (lead-only, Hokm only, non-trump only, boss validation via `S.HighestUnplayedRank`, trick≥2, partner-not-known-void-in-trump, not doubled-contract, late-game-not-conservative).
2. **Wire send.** `Net.lua:4096-4102` — `S.ApplyAKA(seat, akaSuit)` then `N.SendAKA(seat, akaSuit)` synchronously, before `S.ApplyPlay`. Wire format `"a;<seat>;<suit>"`.
3. **Wire receive.** `N._OnAKA` (3075-3096): rejects `fromSelf`, validates seat 1..4, drops if non-PHASE_PLAY, drops if non-Hokm, runs `authorizeSeat(seat, sender)` unless replay, then `S.ApplyAKA(seat, suit)`.
4. **Apply.** `S.ApplyAKA` (1443-1450) sets `s.akaCalled = {seat, suit}` unconditionally, fires voice cue.
5. **Lead play (host).** `S.ApplyPlay` (1238-1265, host-only) validates the lead card matches the AKA truth-claim using `s.playedCardsThisRound` walk; on mismatch marks `.illegal=true, illegalReason="false AKA"` AND clears `s.akaCalled = nil` host-side.
6. **Receiver relief.** `R.IsLegalPlay` (115-121, 175): when partner of `seat` is the AKA caller, `akaCalled.suit == leadSuit`, Hokm — sets `akaRelief=true`, returns `true` for any non-trump card on the void+has-trump path (closes M4 dead-code from v0.10.0).
7. **Trick end.** `S.ApplyTrickEnd` (1327): clears `s.akaCalled = nil`. `playedCardsThisRound` retained.

---

## Findings

### F1 — AKA Hokm-only gate (defense-in-depth) — PASSES

**Severity:** none.

Five independent enforcements (all verbatim verified):

- `Bot.PickAKA` Bot.lua:3263 — `if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end`
- `N.LocalAKA` Net.lua:2347 — same predicate
- `N._OnAKA` Net.lua:3094 — same predicate (wire-side defense)
- `S.LocalAKAcandidate` State.lua:1388 — same predicate (UI button enable gate)
- `R.IsLegalPlay` Rules.lua:119 — `contract and contract.type == K.BID_HOKM` is required for `akaRelief`

**Verdict:** Strongly enforced, matches G18-02 / J-066 verbatim.

---

### F2 — Implicit AKA via bare-A lead — PASSES (receiver convention only)

**Severity:** none for the canonical flow; **MEDIUM for the touching-honors WRITE path** (see F11 below).

**Receiver branch (Bot.lua:2515-2532):**
```lua
local implicitAKA = false
if not explicitAKA and contract.type == K.BID_HOKM
   and contract.trump and trick.leadSuit
   and trick.leadSuit ~= contract.trump
   and partnerWinning
   and trick.plays and trick.plays[1] then
    local lead = trick.plays[1]
    if lead.seat == R.Partner(seat)
       and C.Rank(lead.card) == "A"
       and C.Suit(lead.card) == trick.leadSuit then
        implicitAKA = true
    end
end
```

Triggered ONLY at receiver side when partner LED bare A, non-trump, Hokm, partner-currently-winning. The gate fires correctly per S6-6.

**Sender side:** `Bot.PickAKA` line 3289 explicitly returns `nil` for `r == "A"` — no explicit MSG_AKA on bare-A leads (intentional; redundant per G18-08). M3 host-side validator (State.lua:1238) is gated on `s.akaCalled.seat == seat` — implicit AKA never sets `s.akaCalled`, so M3 NEVER fires for the implicit case. **This is by design** — leading the Ace IS holding the boss-by-construction (Ace is top plain rank, host validates `card in hand`). Implicit AKA cannot be falsified normally.

**HOWEVER (related to F11):** the touching-honors WRITE branch at Bot.lua:484-492 reads only `lead.card == A and lead.seat == Partner` — same touching-context detection without consulting `S.s.akaCalled`. A deceptive bare-A lead pollutes `topTouchSignal` for that suit. See **F11**.

---

### F3 — v0.10.2 M3 host-side validator: HOST-ONLY WIPE (D-RT-19) — MEDIUM

**Severity:** MEDIUM (cosmetic divergence with strategic implications).

**Code under review (State.lua:1238-1265):**
```lua
if not illegal and s.isHost and s.akaCalled
   and s.akaCalled.seat == seat
   and #s.trick.plays == 0  -- this play IS the lead
   and s.contract and s.contract.type == K.BID_HOKM then
    local cardSuit = card:sub(2, 2)
    if cardSuit == s.akaCalled.suit then
        ...
        if not valid then
            illegal = true
            illegalWhy = "false AKA"
            s.akaCalled = nil  -- HOST ONLY
        end
    else
        illegal = true
        illegalWhy = "false AKA"
        s.akaCalled = nil  -- HOST ONLY
    end
end
```

**The hole.** The whole branch is gated on `s.isHost`. When the host detects a false AKA on the lead play and clears `s.akaCalled = nil`:

- Host's `s.akaCalled` becomes `nil` immediately.
- Non-host clients receive **MSG_PLAY only** (no follow-up MSG_AKA wipe). They run `S.ApplyPlay` (Net.lua:1454) but `s.isHost = false`, so the false-AKA branch is skipped. Their `s.akaCalled` remains `{seat, suit}` until `ApplyTrickEnd` (line 1327) clears it organically.
- For the duration of trick T (between false-AKA-detected-on-lead and trick-end), non-host clients display the AKA banner AND `pickFollow`/`legalPlaysFor` consult the stale banner.

**Repro trace.** Hokm, Diamonds trump. Host = seat 1; non-host clients at seats 2-4. Bot at seat 3 sends MSG_AKA on Spades (somehow — see F4 wire-bypass scenario). Banner set on all clients via MSG_AKA broadcast. Seat 3 leads K♠ when A♠ is unplayed → host detects `false AKA`, marks `.illegal`, wipes its own `s.akaCalled`. **Non-host clients still have `s.akaCalled = {seat=3, suit="S"}`.** Bot at seat 1 (partner of seat 3, non-host) consults the stale banner via `pickFollow` (Bot.lua:2512-2514): `explicitAKA = true`, applies receiver-relief discard. Saudi convention: the AKA was false; the partner should have been ruffing or playing normally, not relieving on a phantom claim.

**Strategic impact.**
- The false-AKA caller gets a free relief on their partner-bot (host already knows it's false, but only the host bot would have access to that knowledge — host's bots get correct gameplay; non-host bots and humans get the wrong gameplay).
- Touching-honors WRITE (F11) on non-host clients keeps writing `topTouchSignal` for the rest of the (mid-)trick under the stale banner.
- Banner stays visible to humans on non-host clients until trick-end, which is misleading.

**Mitigation (out of scope per brief):** broadcast a wire signal from the host on false-AKA detection — e.g., a synthetic MSG_AKA with empty suit, or an `illegal=1` flag in the MSG_PLAY format that triggers `ApplyAKA(0,"")` clear on non-host clients.

---

### F4 — v0.10.2 M3 multi-AKA bypass (D-RT-19 #7) — MEDIUM

**Severity:** MEDIUM. Requires hostile/buggy peer.

**Code under review.** `S.ApplyAKA` (State.lua:1443-1450):
```lua
function S.ApplyAKA(seat, suit)
    if not seat or not suit or suit == "" then return end
    s.akaCalled = { seat = seat, suit = suit }   -- UNCONDITIONAL OVERWRITE
    if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_VOICE_AKA) end
end
```

**`N._OnAKA`** does NOT validate that `seat == S.s.turn` or `#S.s.trick.plays == 0`. Lead-context guards exist on `LocalAKA` (Net.lua:2358-2363):
```lua
if S.s.trick and S.s.trick.plays and #S.s.trick.plays > 0 then
    return
end
if S.s.turn ~= S.s.localSeat or S.s.turnKind ~= "play" then
    return
end
```
But the wire receiver `_OnAKA` only checks phase, contract type, and `authorizeSeat`. **Missing:** lead-context, mid-trick rejection.

**Repro.** Seat 2 about to lead, calls AKA-on-Spades legitimately. Banner = `{2, "S"}`. **Before** seat 2 plays the lead card, seat 4 (a hostile peer or buggy non-host bot at their own seat) sends MSG_AKA-on-Diamonds for seat 4 — `authorizeSeat(4, sender)` passes because seat 4 is the sender. `_OnAKA` accepts. `ApplyAKA(4, "D")` overwrites. Banner = `{4, "D"}`.

When seat 2 leads, M3 gate at State.lua:1238-1241 evaluates:
- `s.akaCalled.seat == seat` → `4 == 2` → **FALSE**.

M3 short-circuits. Seat 2's lead bypasses the false-AKA check entirely. **Seat 2's AKA truth-claim is never validated.**

**Secondary impact.** When seat 2 leads, partner running `pickFollow` reads `s.akaCalled = {4, "D"}`. Partner = seat 4 of receiver-side check; receiver-side check at Bot.lua:2512-2514 demands `akaCalled.seat == R.Partner(seat) AND akaCalled.suit == trick.leadSuit`. The mismatch (suit D vs. lead S) suppresses explicit relief, **but** implicit AKA still fires correctly if seat 2 led a bare Ace (Bot.lua:2521-2532), so receiver-relief mostly recovers. M3 detection is the actual victim.

**Mitigation (out of scope):** add `if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end` and `if S.s.trick and #S.s.trick.plays > 0 then return end` at `_OnAKA`, mirroring `LocalAKA`. Or: refuse to overwrite `s.akaCalled` if it's already set in the same trick (FIFO).

---

### F5 — v0.10.2 M4 R.IsLegalPlay AKA-aware passthrough — caller catalog — MIXED

5 AKA-aware sites, 5 AKA-blind sites. Catalog (verified file:line):

| # | Location | AKA passed? | Severity | Path |
|---|---|---|---|---|
| 1 | `Bot.lua:1610` (`legalPlaysFor`) | YES (`S.s.akaCalled`) | OK | Bot heuristic picker |
| 2 | `Net.lua:2040` (`LocalPlay`) | YES (`S.s.akaCalled`) | OK | Anti-misclick warn |
| 3 | `Net.lua:3412` (AFK auto-play) | YES (`S.s.akaCalled`) | OK | AFK fallback |
| 4 | `Net.lua:4136` (post-meld-error fallback) | YES (`S.s.akaCalled`) | OK | Bot host fallback |
| 5 | `State.lua:1219` (`S.ApplyPlay` Takweesh mark) | YES (`s.akaCalled`) | OK | Host illegality detect |
| **6** | **`BotMaster.lua:830`** (`BM.PickPlay`) | **NO** | **HIGH (D-RT-04 F1, D-RT-18 S1)** | **Saudi Master tier outer driver** |
| 7 | `BotMaster.lua:649` (`heuristicPick` rollout) | NO | MEDIUM (D-RT-18 S3 — defensible per CHANGELOG: "rollouts get AKA-blind semantics") | ISMCTS rollout opponent sim |
| 8 | `Rules.lua:435` (`R.IsValidSWA` minimax) | NO | LOW (D-RT-18 S4) | SWA validator recursion (live-reachable, narrow window) |
| 9 | `State.lua:1665` (`S.HostValidatePlay`) | NO | LOW (D-RT-18 S2b) | Latent dead helper (no current callers; refactor footgun) |
| 10 | `State.lua:1966` (`S.GetLegalPlays`) | NO | MEDIUM-UI (D-RT-18 S2) | UI dimming for human player; trains humans against AKA convention |

**Highest impact: site 6 — `BotMaster.lua:830`.** This is the canonical decision-point for Saudi Master tier (the highest-quality bot tier per CLAUDE.md). The `Bot.PickPlay` delegation at Bot.lua:3382-3386 short-circuits to `BM.PickPlay` when Saudi Master is active — bypassing the M4-aware `legalPlaysFor` at Bot.lua:1610. **The M4 fix's primary intended beneficiary silently reverts to AKA-blind legality.**

**Concrete fail (verified D-RT-18 §2 reconstruction):** Hokm trump=D, partnerships 1↔3. Bot at seat 3 (Saudi Master). Trick: seat 1 led A♠ + AKA, seat 2 (opp) cut with 2♦. Seat 3 hand `{7H, 8H, JD, QD}` — void in S, has trump.

Without `aka` at line 830:
- `R.IsLegalPlay("7H", ..., 3, NIL)` → no relief, partner-winning shortcut fails (curWinner=2), must-trump-ruff fires → 7H, 8H REJECTED. `legal = {JD, QD}`.
- ISMCTS picks one of the trumps and ruffs.

With `aka` (not the case here):
- `akaRelief = true`, void+has-trump returns true at line 175. `legal = {7H, 8H, JD, QD}`.
- Heuristic: lowest non-trump → 7H. Saves trump.

This is the **canonical M4-target case** — opp over-trumped partner's AKA'd lead, receiver should discard low. `BM.PickPlay` ruffs; the fix doesn't reach the highest-tier bot.

---

### F6 — AKA-relief discard poisons firstDiscard ledger (D-RT-04 F10) — LOW

**Severity:** LOW.

**Code path.** `Bot.OnPlayObserved` (Bot.lua:340-356, called from Net.lua after every `ApplyPlay`):
```lua
local cardSuit = C.Suit(card)
if not wasIllegal and leadSuit and cardSuit ~= leadSuit then
    mem.void[leadSuit] = true
    if not mem.firstDiscard then
        mem.firstDiscard = { suit = cardSuit, rank = C.Rank(card) }
    end
end
```

The trump-ruff rollback at Bot.lua:431-438 reverts `firstDiscard` if the off-suit play was a trump card (forced ruff, not preference). **However:** when an AKA-receiver discards a low non-trump under M4 relief, `cardSuit ~= leadSuit` and `cardSuit ~= contract.trump` (it's a side-suit discard), so the trump-ruff rollback does NOT fire. The Fzloky `firstDiscard` records this AKA-relief discard as a preference signal.

**Strategic impact.** Subsequent partner-bot decisions consult `mem.firstDiscard` (Bot.lua:1963 — `pickLead` Fzloky avoid logic) interpreting the receiver's side-suit dump as "I want this suit returned." But the discard was **forced by AKA-relief**, not a Tahreeb/Tanfeer preference — the receiver may not actually want the suit returned. The Tahreeb interpretation is corrupted.

**Window.** Limited — fires once per round (only on first off-suit discard). The receiver's actual preference signaling logic suppresses the relief-discard's downstream Tahreeb classification (Bot.lua:1963 region uses `tahreebClassify` which expects ascending/descending sequences, not single-shot). So the impact bottoms out on **suit-avoid hints only**, not full Tahreeb classification.

**Suggested fix (out of scope):** add a rollback in `OnPlayObserved` that mirrors the trump-ruff revert when the discarded play occurred under AKA-relief active for the seat (`S.s.akaCalled.seat == R.Partner(seat) and akaCalled.suit == leadSuit`).

---

### F7 — Touching-honors WRITE missing partner-still-winning gate (D-RT-07 RT-07-H) — HIGH

**Severity:** HIGH (R6 K-fix magnifies pre-existing gap).

**Code under review (Bot.lua:485-492):**
```lua
local touchContext = false
if lead.seat == R.Partner(seat)
   and C.Suit(lead.card) == cardSuit
   and C.Rank(lead.card) == "A" then
    touchContext = true
elseif S.s.akaCalled and S.s.akaCalled.seat == R.Partner(seat)
       and S.s.akaCalled.suit == cardSuit then
    touchContext = true
end
```

**Missing:** check that partner is STILL WINNING when `seat` plays. Source #05 line 280 explicitly says: "partner played and you are NOT yet winning the trick → touching-honors inference does NOT apply (partner forced to follow legally)."

**Repro (D-RT-07 RT-07-H exploit reconstruction).** Hokm, trump=H. Bot is seat 1 (sampler-caller). Partner is seat 3.

- Trick 3: bot leads bare A♠. Seat 2 (opp) ruffs with 9♥ (void in S). Trick is now winning for opp seat 2.
- Partner (seat 3) is forced to follow if they have spades. Partner's only legal spades are K♠+Q♠+9♠. Partner dumps K♠ (highest of a losing trick — not a "K-singleton" signal at all).
- WRITE-site gate from partner's perspective: `seat=3`, `lead.seat=1=R.Partner(3)`, `cardSuit=S=Suit(lead)`, `Rank(lead)="A"`. **WRITE fires.** `entry.cleared = {"Q","J"}` written to `style[3].topTouchSignal["S"]`.
- READ-site weaponization: bot at seat 1 in next ISMCTS rollout sees `cleared={"Q","J"}` — clears Q♠/J♠ from partner's possible holdings. Sampler now distributes Q♠/J♠ to opps when **partner actually has them**.

**Why R6 amplifies this.**
- Pre-R6: K-signal wrote `nextDown="Q"` (mispin Q TO seat 3 via SOFT bias). Under-ruff scenario: mispin direction was right but reasoning was wrong.
- Post-R6: K-signal writes `cleared={"Q","J"}` (HARD negative bias against Q at seat 3). Under-ruff scenario: hard-clears Q from partner who actually has it. **Worse than pre-R6** for the under-ruff case.

**Suggested fix (out of scope):** gate WRITE on `R.CurrentTrickWinner(trickWithoutSeatPlay, contract) == lead.seat` (i.e., partner still winning when `seat` plays).

---

### F8 — _OnAKA mid-trick + AKA-on-trump bypass (D-RedTeam-01 E1, E11) — HIGH

**Severity:** HIGH. Multi-trick damage on a single bypass.

#### F8a — AKA-on-trump bypasses every gate (E1)

**Code paths:**
- `LocalAKAcandidate` (State.lua:1394) filters trump out of AKA candidates: `if su ~= trump`. **UI-side only — wire path is open.**
- `_OnAKA` Net.lua:3075-3096: no `suit ~= contract.trump` check.
- `S.ApplyAKA` (State.lua:1443-1450): no validation, accepts any suit.
- M3 detector (State.lua:1245): walks PLAIN-rank order `{"A","T","K","Q","J","9","8","7"}` — wrong for trump ranking (trump order is J>9>A>T>K>Q>8>7).
- `Rules.lua:115-121` (M4 relief): does NOT check `akaCalled.suit ~= contract.trump`.

**Repro.** Hokm, trump=Spades. Skilled human at seat 1 sends `MSG_AKA;1;S` directly via wire (skipping the UI button which `LocalAKAcandidate` correctly hides). `_OnAKA` accepts. Banner = `{1, "S"}` on every client. Human at seat 1 leads J♠ (top trump in trump-ranking).

M3 detector walks plain order: if A♠/T♠/K♠/Q♠ are ALL played (likely by trick 3+), the J♠ lead PASSES M3's plain-rank validation (A,T,K,Q gone, walk reaches J → `valid=true`). **No `.illegal` mark.**

Now `s.akaCalled = {1, "S"}` and `leadSuit = trump = S`. Bot at seat 3 (partner of seat 1) plays next:
- Void in S, has another trump. `R.IsLegalPlay` (Rules.lua:115-121): partner=1=akaCalled.seat ✓, suit=S=leadSuit ✓, Hokm ✓ → **akaRelief = TRUE on a trump-led trick.**
- Line 175: `if akaRelief then return true` for non-trump cards. Bot may discard low non-trump on a trump trick.
- Touching-honors WRITE (Bot.lua:489-491) reads `S.s.akaCalled.suit == cardSuit` (trump suit) → writes phantom `topTouchSignal[trump]` entry, polluting future trump-distribution predictions.

**Strategic impact.** Bot partner discards instead of overcutting opp's mid-trump → opp wins trump trick worth ~30+ points; in Bel-doubled hand can flip contract make/fail.

#### F8b — _OnAKA accepts AKA mid-trick on the wire (E11)

The L4 fix (per Net.lua:2358-2363 comment block) prevents human from clicking AKA mid-trick. `LocalAKA` blocks. **But `_OnAKA` does NOT have the same gate.**

**Repro.** Trick 2 in progress: seat 1 has played, seats 2,3,4 not yet played. Seat 1 sends `MSG_AKA;1;H` via wire **after** their play (bypassing `LocalAKA`). `_OnAKA` accepts (no `#S.s.trick.plays == 0` check). Banner mid-trick.

Subsequent bot decisions at seats 2,3,4 consult `S.s.akaCalled` for receiver-relief and touching-honors-WRITE inferences. Pre-AKA plays in the same trick are retroactively re-classified by the WRITE branch using the stale-after-the-fact AKA banner.

**This is the exact class of bug L4 was supposed to close.** Wire-bypass undoes the fix.

---

### F9 — Resync replay path (Net.lua:461-463) AKA banner — PASSES

**Severity:** none.

**Code (Net.lua:459-464):**
```lua
if S.s.akaCalled then
    whisper(target, ("%s;%d;%s;1"):format(
        K.MSG_AKA, S.s.akaCalled.seat or 0, S.s.akaCalled.suit or ""))
end
```

Trailing `"1"` flag tells `_OnAKA` it's a replay → bypasses `authorizeSeat` (sender is host, not seat owner). The replay re-applies `ApplyAKA(seat, suit)` on the rejoiner, setting their local banner for cosmetic display.

**Edge cases checked:**
- M3 is host-only — rejoiner doesn't run M3, no duplicate `.illegal` marks.
- If host already cleared `s.akaCalled = nil` from M3 false-AKA detection BEFORE the resync, the replay condition short-circuits. No stale replay.
- `if isReplay and S.s.isHost then return end` (Net.lua:3083) — defensive: hosts never receive replay AKA frames.

**Verdict:** clean. The AKA banner replay is purely cosmetic and doesn't propagate across host/non-host divergence (F3 issue).

**Note (CONNECTS TO F3):** If the host's M3 already cleared `s.akaCalled = nil` and a non-host client requests resync mid-trick, the host's replay correctly skips the AKA frame. **But:** if the false-AKA detection happens AFTER another client's resync, that client carries the stale banner with no in-band correction (same as F3). The resync replay path doesn't help here — it relies on the host's CURRENT state.

---

### F10 — AKA-on-T trick-locking (J-066/J-067 part 1) — NOT IMPLEMENTED

**Severity:** LOW per prior X2 B5 / B-Rules-08 F11 / B-Bot-03 F2 classification.

**Code surface.** `R.CurrentTrickWinner` (Rules.lua:34-59) computes trick winner purely by trump-rank/leadSuit-rank — does NOT consult `s.akaCalled` anywhere.

**Phase-1 J-067 part 1.** "AKA on 10 = 10 substitutes for Ace and the trick is locked for over-trumping requirements." Saudi convention: if A is dead, leading T under AKA should treat T as the boss and the trick should be considered closed for opps' must-overcut requirements.

**v0.10.2 M4 status.** Closed Part 2 only (the receiver-side relief in `R.IsLegalPlay`). Part 1 (the trick-resolution side) is unchanged. An opp can still legally over-trump partner's AKA'd 10, and `R.CurrentTrickWinner` will report the opp as winning, breaking the bot's `partnerWinning` gate at Bot.lua:2547.

**Concrete impact (D-RedTeam-01 E4 reconstruction).**
- Hokm, trump=Diamonds. A♥ played in trick 1. Seat 1 declares AKA on hearts (boss = T because A is dead).
- Seat 1 leads T♥. Seat 2 (opp) void in hearts, must ruff with low D. CurrentTrickWinner=seat 2.
- Seat 3 (partner of 1) void in hearts, has trump. `pickFollow` checks `partnerWinning` — FALSE because curWinner=2.
- Receiver-relief gate at Bot.lua:2547 requires `partnerWinning`. **Falls through.** Bot tries to overcut opp's trump.
- Seat 4 (opp, last) overtrumps with high trump. Trick goes to opp.

Saudi convention says T should have substituted for Ace and locked the trick — but `R.CurrentTrickWinner` is suit-rank-blind to AKA. So the bot's AKA-relief receiver branch only fires while partner is already winning, not when an opp ruffs the AKA'd lead.

**Source confirmation.** Per X2 B5 finding (CONFIRMED NOT IMPLEMENTED); B-Rules-08 F11 carried this forward; B-Bot-03 F2 cosmetic-only.

---

### F11 — False-AKA = Qaid (J-069) — Partial via .illegal flag

**Severity:** LOW (deterrent works; missing post-round auto-Takweesh).

**Code (State.lua:1238-1265, host-only).** Marks the false-AKA lead with `.illegal=true, illegalReason="false AKA"` and clears `s.akaCalled` host-side. Takweesh resolution scans `.illegal` (Net.lua:2150-2162):
```lua
local function scanIllegal(plays)
    for _, p in ipairs(plays or {}) do
        if p.illegal and R.TeamOf(p.seat) ~= callerTeam then return p end
    end
end
```

When an opponent calls Takweesh, the false-AKA lead is caught, reason `"false AKA"` propagates to the chat and banner. **Mechanism is correct for the same-trick-Takweesh case.**

**Gap.** Takweesh requires a defender to actually call. If no opponent calls Takweesh during PHASE_PLAY, the `.illegal` mark in `s.tricks` history is never resolved. **A false AKA played but un-Takweesh'd by round-end is a free pass.**

This is intentional per Saudi convention (defenders must notice and call), but the M3 `.illegal` mark has zero deterrent unless a defender presses Takweesh. No post-round auto-Takweesh sweep exists.

**No `R.ScoreRound` branch on `s.akaWasFalse` flag exists.** No `K.MSG_QAID` triggered on AKA-mismatch directly.

---

### F12 — Late-game conservatism (Bot.lua:3350-3366) + L3 doubled-contract (3332) — PASSES

**Severity:** none for the conservatism implementations themselves; **MEDIUM for the asymmetric timing window** (D-RedTeam-01 E7).

**Late-game (Bot.lua:3350-3366):**
```lua
if trickNum >= 6 then
    if S.s.cumulative then
        local myTeam = R.TeamOf(seat)
        local meCum = S.s.cumulative[myTeam] or 0
        local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
        local target = S.s.target or 152
        local clutch = (oppCum >= target - 25)
                       or (meCum >= target - 25)
                       or (math.abs(oppCum - meCum) <= 20)
        if not clutch then return nil end
    else
        return nil
    end
end
```

Implements decision-trees.md Section 6 row "preconditions" subitem g. Suppresses AKA at trickNum>=6 unless score-state is "clutch" (close race / opp near-win / we near-clinch). **Mechanism correct.**

**L3 doubled-contract (Bot.lua:3332):**
```lua
if S.s.contract and S.s.contract.doubled then return nil end
```

Closes X2 B3 (G18-10 paragraph 2). **Mechanism correct in isolation.**

**Asymmetric timing window (D-RedTeam-01 E7 — MEDIUM).** L3 is sender-side suppression. The wire path doesn't consult L3. A skilled human exploits this:
- Bot at seat 1 sends AKA legitimately (not doubled at the time). Banner live.
- Mid-trick or between tricks, opp seat 4 calls Bel → `S.s.contract.doubled = true`.
- L3 gate runs only at next `Bot.PickAKA` call, doesn't retroactively retract the live banner.
- Bot partner of seat 1 at seat 3 still applies receiver-relief based on the now-stale-by-policy banner.
- Opps know "team A has the boss of suit X" → can plan trump-tempo accordingly.

Worse case: human team A's seat 1 calls AKA legitimately, human at seat 4 (opp) immediately calls Bel — every legitimate AKA-call becomes an instant ×2 setup if opp is willing to Bel.

**Suggested fix (out of scope per brief):** on `S.ApplyDouble` (or wherever `contract.doubled` is set to true), if `s.akaCalled` is live, clear it.

---

## Cross-reference summary table

| Finding | Severity | Source xref | Status |
|---|---|---|---|
| F1 — AKA Hokm-only gate (5-layer defense) | OK | X2 G18-02/J-066 | PASS |
| F2 — Implicit AKA via bare-A receiver-only | OK | X2 G18-08, F11 connects | PASS receiver / sender by design |
| F3 — M3 false-AKA host-only wipe | MEDIUM | D-RT-19 #6 (extended here) | NEW: non-host stale banner mid-trick |
| F4 — M3 multi-AKA bypass via clobber | MEDIUM | D-RT-19 #7 | OPEN |
| F5 — M4 IsLegalPlay caller catalog | MIXED | D-RT-04, D-RT-18 | site 6 (BotMaster:830) HIGH; sites 7-10 MED-LOW |
| F6 — AKA-relief discard pollutes firstDiscard | LOW | D-RT-04 F10 | OPEN, narrow window |
| F7 — Touching-honors WRITE missing partnerWinning gate | HIGH | D-RT-07 RT-07-H | OPEN, R6 magnifies |
| F8a — AKA-on-trump bypass | HIGH | D-RedTeam-01 E1 / D-RT-04 F11+F12 | OPEN |
| F8b — _OnAKA mid-trick wire bypass of L4 | HIGH | D-RedTeam-01 E11 | OPEN |
| F9 — Resync replay path | OK | — | PASS (but propagates F3 stale state) |
| F10 — AKA-on-T trick-locking | LOW | X2 B5, B-Rules-08 F11, B-Bot-03 F2 | NOT IMPLEMENTED (per spec) |
| F11 — False-AKA = Qaid (.illegal flag) | LOW | J-069 partial | DETERRENT MECHANISM CORRECT; no post-round auto-Takweesh |
| F12 — Late-game + L3 doubled conservatism | OK / MED | X2 B3 / D-RedTeam-01 E7 | implementation OK; timing-window asymmetric |

---

## Highest-impact open findings (prioritized)

1. **F5 site 6 (`BotMaster.lua:830`) — HIGH.** Saudi Master tier silently reverts to AKA-blind legality. The v0.10.2 M4 fix's primary intended beneficiary (highest-quality bot tier) gets the dead-code semantic the fix was meant to close. **Two-line patch suggested by D-RT-18 §2.**

2. **F7 (touching-honors WRITE under-ruff) — HIGH.** Pre-existing gate gap that v0.10.0 R6 K-fix MAGNIFIES — a forced K-dump in a partner-led-but-over-ruffed trick is now read as a HARD K-singleton signal (post-R6 `cleared={"Q","J"}`), pinning Q♠/J♠ to the wrong side of the partnership for the rest of the round.

3. **F8a (AKA-on-trump wire bypass) — HIGH.** UI prevents trump-AKA, but wire is open. M3 walks the wrong rank order for trump suits, M4 doesn't gate `akaCalled.suit ~= contract.trump`. Single hostile message → multi-trick relief on a trump trick.

4. **F8b (_OnAKA mid-trick) — HIGH.** L4 fix is client-side only. Wire-direct mid-trick AKA undoes the fix. Same L4-class bug.

5. **F3 (M3 host-only wipe) — MEDIUM.** Non-host clients display stale AKA banner and run stale `pickFollow`/`legalPlaysFor` for the duration of the false-AKA trick. Strategic divergence between host and non-host bot decisions.

6. **F4 (M3 multi-AKA clobber) — MEDIUM.** Hostile peer broadcasts spurious MSG_AKA from their own seat to clobber the legitimate caller's banner before M3 fires.

7. **F12 / E7 (doubled-after-AKA timing) — MEDIUM.** L3 doesn't retroactively retract live banner when an opp doubles. Every legitimate AKA-then-Bel sequence becomes a free coordination + ×2 multiplier setup.

---

## Confidence

**HIGH confidence:**
- F1 (defense-in-depth: 5 verbatim-cited gates).
- F5 caller catalog (10/10 sites file:line cross-checked).
- F8a (M3 plain-rank walk verified at State.lua:1245; M4 missing trump-gate verified at Rules.lua:115-121).
- F10 (`R.CurrentTrickWinner` Rules.lua:34-59 contains zero references to `akaCalled`; verified via grep).
- F11 (M3 `.illegal` flag mechanism mechanically correct for the same-trick Takweesh path).

**MEDIUM confidence:**
- F3 host-only wipe propagation timing (depends on actual MSG_PLAY → MSG_TRICK ordering observed in real network conditions; verified gate at State.lua:1238).
- F6 firstDiscard pollution (mechanism reachable, strategic impact downstream depends on `tahreebClassify` consumer paths not fully re-traced).

**LOW confidence:**
- F4 multi-AKA clobber actual exploit window — relies on hostile-peer model, which is non-trivial to engineer in WoW addon channels but not impossible.
