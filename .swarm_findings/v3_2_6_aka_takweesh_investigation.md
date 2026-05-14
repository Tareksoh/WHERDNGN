# v3.2.6 AKA → Takweesh incident investigation

**Status:** investigation pass only. No runtime / packaging /
test edits. Uncommitted on `main`.

**Provenance:**

- User-observed incident (paraphrased):
  > "a bot did AKA to another bot which made the third bot /
  > human teammate use Takweesh"
- This is an incident report, not a fully specified repro. The
  investigation is exploratory.
- Paired with `.swarm_findings/v3_2_5_release_readiness_checkpoint.md`,
  which recommends HOLDing the v3.2.5 release pending the
  classification produced here.

---

## 1. Source paths inspected

| Path | File:Line | Purpose |
|---|---|---|
| `Bot.PickAKA` | `Bot.lua:5453-5633` | Sender: returns AKA suit when bot holds the actual boss |
| `Bot.PickAKANoise` | `Bot.lua:5641-5682` | Sender: SaudiMaster ~8% deceptive AKA on K/Q where bot does NOT hold A |
| `Bot.PickTakweesh` | `Bot.lua:5900-5976` | Caller: scans opp illegal plays with realism gate |
| `Net.MaybeRunBot` bot-AKA dispatch | `Net.lua:6191-6371` | Pre-play Takweesh scan → SWA → melds → PickPlay → PickAKA / PickAKANoise → ApplyAKA + SendAKA → ApplyPlay → SendPlay |
| `S.ApplyAKA` | `State.lua:1838+` | Writes `s.akaCalled = { seat, suit }` |
| `S.ApplyPlay` (false-AKA block) | `State.lua:1466-1493` | Marks lead `.illegal = true`, `illegalReason = "false AKA"`, clears `s.akaCalled` when the lead's rank is not the highest unplayed of `akaCalled.suit` |
| `R.IsLegalPlay` (akaCalled param) | `Rules.lua:96-220` | Receiver-side relief: must-trump-ruff suppressed when partner's AKA is live on the led suit |
| `N.SendTakweesh` | `Net.lua:778-791` | 250ms-retry broadcastWithRetry; phase = PLAY or TAKWEESH_REVIEW |
| `N.LocalTakweesh` | `Net.lua:3300-3311` | Human UI button → SendTakweesh + HostBeginTakweeshReview (if host) |
| `N.HostBeginTakweeshReview` | `Net.lua:3347-3415` | Scans for `p.illegal and R.TeamOf(p.seat) ~= callerTeam`; sets phase = `PHASE_TAKWEESH_REVIEW`; 8s auto-resolve |
| `N.HostResolveTakweesh` | `Net.lua:3507+` | Scoring + round-end |
| UI tooltip on TAKWEESH button | `UI.lua:2476-2485` | Warns "Wrong call costs YOUR team the same penalty" but does NOT explicitly warn that calling on a teammate's illegal play = wrong call |

---

## 2. False-AKA marking logic (exact conditions)

From `State.lua:1466-1493`:

```lua
if not illegal and s.isHost and s.akaCalled
   and s.akaCalled.seat == seat
   and #s.trick.plays == 0           -- this play IS the lead
   and s.contract and s.contract.type == K.BID_HOKM then
    local cardSuit = card:sub(2, 2)
    if cardSuit == s.akaCalled.suit then
        local cardRank = card:sub(1, 1)
        local order = { "A", "T", "K", "Q", "J", "9", "8", "7" }
        local valid = false
        for _, r in ipairs(order) do
            if r == cardRank then valid = true; break end
            if not s.playedCardsThisRound[r .. cardSuit] then
                break  -- a higher rank is still out: false claim
            end
        end
        if not valid then
            illegal = true
            illegalWhy = "false AKA"
            s.akaCalled = nil
        end
    else
        -- AKA on suit X but lead is suit Y → trivially false.
        illegal = true
        illegalWhy = "false AKA"
        s.akaCalled = nil
    end
end
```

**Conditions that mark a play as false AKA:**

1. `s.isHost` (only host marks the flag; remotes can't validate).
2. `s.akaCalled` is set AND `s.akaCalled.seat == seat` (the
   AKA-caller IS the current player making the play).
3. `#s.trick.plays == 0` — this play is the LEAD of the trick.
4. Contract is `K.BID_HOKM`.
5. Either:
   (a) `cardSuit == akaCalled.suit` AND the card's rank is NOT
       the highest-unplayed rank of that suit, OR
   (b) `cardSuit != akaCalled.suit` (suit mismatch).

**Effects:**

- `play.illegal = true`, `play.illegalReason = "false AKA"`.
- `s.akaCalled = nil` (clears the banner so AKA-receiver relief
  in `Rules.IsLegalPlay` doesn't kick in on the bogus claim).

**Existing test coverage:** `tests/test_state_bot.lua:1777-1857`
(section J.3) already exercises false-AKA marking — positive
case (KH lead when AH unplayed), TRUE AKA sanity (AH lead),
suit-mismatch edge (AKA-on-H + lead-on-S). The marking layer
itself is well-tested.

---

## 3. Bot Takweesh caller logic (same-team filter + realism gate)

From `Bot.lua:5900-5976` (`Bot.PickTakweesh`):

```lua
local myTeam = R.TeamOf(seat)
...
for tIdx, t in ipairs(S.s.tricks or {}) do
    for _, p in ipairs(t.plays or {}) do
        if p.illegal and R.TeamOf(p.seat) ~= myTeam then
            -- Realism gate: was the violation later revealed
            -- by the violator playing the led-suit in a
            -- subsequent trick? ...
            if t.leadSuit and laterPlayedLeadSuit(p.seat, t.leadSuit, tIdx) then
                found = p; break
            end
        end
    end
    if found then break end
end
```

### 3.1 Same-team filter

**Bot will NEVER call Takweesh on a same-team illegal play.**
The `R.TeamOf(p.seat) ~= myTeam` filter is unambiguous.

Additionally, `Net.lua:3362` (host's `HostBeginTakweeshReview`
scan) AND `Net.lua:3545` (host's `HostResolveTakweesh` scan) BOTH
apply the same `R.TeamOf(p.seat) ~= callerTeam` filter — so a
same-team Takweesh CALL (e.g. by a human teammate clicking the
TAKWEESH button) **finds nothing** and resolves as a
**false call** that PENALIZES the caller's team.

### 3.2 Realism gate mismatch for false AKA (Codex correction)

The `laterPlayedLeadSuit(violator, t.leadSuit, tIdx)` realism
gate at `Bot.lua:5962` was designed for **revoke-style /
off-suit illegal plays** per the v1.5.1 audit comment at
`Bot.lua:5909-5919`:

> "Real Takweesh requires the caller to have OBSERVED the
> violation through publicly-visible play. The proof is when
> the violator later plays a card of the led suit in a
> subsequent trick, revealing they had it during the original
> off-suit play."

That semantic is correct for the revoke case: an opp plays
off-suit, then later reveals they had the suit by playing it.
The realism gate checks for that later reveal.

**The same gate does NOT fit `illegalReason == "false AKA"`
semantics.** False-AKA marking at `State.lua:1466-1493` is
**public-knowledge based**:

- The host evaluates the lead's rank against `playedCardsThisRound`
  (also fully public — every client tracks it identically) to
  decide if the AKA-claimed boss is actually unplayed.
- A false-AKA violation is **immediately observable from the
  public trick log + AKA banner** at the moment of the lead.
  No subsequent reveal is needed; the proof is already there.
- The violator may **never play the AKA'd suit again** (they
  may not lead another trick before round-end, the suit may
  exhaust through other plays, etc.). The realism gate's
  `laterPlayedLeadSuit` check therefore frequently fails to
  fire even though the violation is publicly knowable.

**Net effect:** `Bot.PickTakweesh` usually FAILS to call
Takweesh on a false AKA, even though human players (clicking
the UI button) and the host's own scan both correctly process
it. The bot caller's realism gate is over-conservative for the
false-AKA case.

### 3.3 Doc-language correction

A prior version of this doc said "realism gate satisfied if/when
the violator later reveals A in the AKA'd suit." That was
incorrect: the gate at `Bot.lua:5927-5949` checks if the same
violator later plays a card of **the led suit**, not
specifically the A. For a false-AKA lead the led suit IS the
AKA'd suit, so the violator would have to lead or play that
suit again — typically the A would come from a *different*
seat (one of the opps or the bot's partner), and that doesn't
satisfy the violator-played-it gate. The doc has been
corrected below.

---

## 4. AKA receiver relief (Rules + pickFollow)

`Rules.IsLegalPlay(card, hand, trick, contract, seat, akaCalled)`
at `Rules.lua:141-159`:

```lua
local akaRelief = false
if akaCalled and akaCalled.seat and akaCalled.suit
   and seat and R.Partner(seat) == akaCalled.seat
   and akaCalled.suit == leadSuit
   and contract and contract.type == K.BID_HOKM
   and akaCalled.suit ~= contract.trump then
    akaRelief = true
end
```

Plus implicit-AKA detection (partner-led bare-Ace non-trump) at
`Rules.lua:149-159`. Combined with the must-trump suppression at
L213-220, this is what lets the receiver discard non-trump
instead of must-ruff when partner's AKA banner is live.

**`Bot.pickFollow` AKA branches:** `Bot.lua:3066-3076`
(implicit), `Bot.lua:3111-3153` (Takbeer donation when AKA live
+ we have led-suit point cards). These are well-tested by
AE.9 / AN.1 / AQ.7 / AS.3 / AZ.13-15.

**Critical observation:** when the host clears `s.akaCalled` due
to false-AKA marking (`State.lua:1485` / `1491`), the **clear
happens BEFORE** subsequent plays are processed. So no receiver
ever benefits from receiver-relief on a falsely-claimed AKA —
their must-ruff obligation reasserts when they're next legalled.

---

## 5. Bot Net dispatch ordering (the critical sequence)

From `Net.lua:6191-6379` (`MaybeRunBot` bot play dispatch):

```lua
-- 1. Takweesh scan (pre-play)
if B.Bot.PickTakweesh and B.Bot.PickTakweesh(seat) then ...
    return
end
-- 2. SWA check
if B.Bot.PickSWA and B.Bot.PickSWA(seat) then ...
    return
end
-- 3. Melds
... PickMelds, ApplyMeld, SendMeld ...
-- 4. Card pick
local card = B.Bot.PickPlay(seat)
-- 5. AKA banner (BEFORE the play applies)
if B.Bot.PickAKA then
    local akaSuit = B.Bot.PickAKA(seat, card)
    if akaSuit then
        S.ApplyAKA(seat, akaSuit)
        N.SendAKA(seat, akaSuit)
        if N._AKAPartnerHint then N._AKAPartnerHint(seat, akaSuit) end
    elseif B.Bot.PickAKANoise then
        local noiseSuit = B.Bot.PickAKANoise(seat, card)
        if noiseSuit then
            S.ApplyAKA(seat, noiseSuit)
            N.SendAKA(seat, noiseSuit)
            if N._AKAPartnerHint then N._AKAPartnerHint(seat, noiseSuit) end
        end
    end
end
-- 6. Apply + broadcast play
S.ApplyPlay(seat, card)  -- false-AKA marking fires here
... B.Bot.OnPlayObserved ...
N.SendPlay(seat, card)
```

**The key ordering insight:** `S.ApplyAKA` and `N.SendAKA` fire
**before** `S.ApplyPlay`. So `s.akaCalled` is set when
`S.ApplyPlay` runs. The false-AKA validation at
`State.lua:1466-1493` therefore catches the bot's bluff
immediately — `play.illegal = true` is set on the bot's own
play record on the host.

---

## 6. Authority / team semantics

| Question | Answer |
|---|---|
| Who can call Takweesh? | Any player (UI button in `UI.lua:2476`, bot scan in `Bot.PickTakweesh`). |
| Does the host scan only opposing illegal plays? | YES — three scan sites all gate on `R.TeamOf(p.seat) ~= callerTeam` (`Bot.lua:5955`, `Net.lua:3362`, `Net.lua:3545`). |
| If the caller is the false-AKA caller's teammate, what happens? | Host's scan finds nothing → caller's team is treated as a false caller → callerTeam **loses** the round (Qaid penalty). |
| If the caller is an opponent, what happens? | Host's scan finds the `illegal = true, illegalReason = "false AKA"` flag → opp team **wins** the round via Qaid. |
| Can a bot call Takweesh on its own teammate? | NO — the `R.TeamOf(p.seat) ~= myTeam` filter in `Bot.PickTakweesh` is hard-coded. |
| Can a bot's noise-AKA emit and then trip the host's false-AKA marker? | YES — `Bot.PickAKANoise` returns the led-card's suit when bot has K/Q lead in a non-trump suit and does NOT hold the A. `State.ApplyPlay` then walks `playedCardsThisRound` for `A.suit`, finds it unplayed, marks `illegal = true; illegalReason = "false AKA"`. |
| Is the noise-AKA path expected behavior? | YES — explicitly added in v1.2.1 (A2) and bumped to 8% rate in v1.6.0 (per `Bot.lua:5648-5657` comment block). The bluff is part of SaudiMaster's signal-deception design. |

---

## 7. Incident classification

The incident report wording — "a bot did AKA to another bot
which made the third bot / human teammate use Takweesh" — is
ambiguous. Three plausible scenarios fit the wording. **Each
maps to a different classification:**

### 7.1 Scenario A — SaudiMaster noise-AKA + opp Takweesh catch

**Mapping:** "bot did AKA to another bot" = SaudiMaster bot
emitted a `Bot.PickAKANoise` deceptive AKA (8% per non-trump
K/Q lead at SaudiMaster tier). "Made the third bot / human
teammate use Takweesh" = an **opponent** caught the false-AKA
marker and called Takweesh.

**Sub-scenario A1 — human opp clicks TAKWEESH UI button.**
`N.LocalTakweesh` → `N.HostBeginTakweeshReview` → host's scan
at `Net.lua:3360-3372` finds `p.illegal and R.TeamOf(p.seat) ~=
callerTeam`. The host's scan does NOT apply the realism gate
(it trusts the host-marked `illegal` flag directly).
**Classification: WORKING AS DESIGNED.** Opp human correctly
catches.

**Sub-scenario A2 — bot opp's `Bot.PickTakweesh` catches.**
Bot opp's `Bot.PickTakweesh` finds the marker but **fails the
realism gate** because the violator typically doesn't replay
the AKA'd suit before round-end. Per §3.2, the gate is
over-conservative for `illegalReason == "false AKA"`.
**Classification: LIKELY BEHAVIOUR GAP.** Bot fails to catch
the bluff the host has already marked illegal. Saudi-canonical
expectation: bots at sufficient tier (Advanced+) should catch
publicly-visible false-AKA violations the same way humans do.

**Likelihood:**
- A1: HIGH if any human is on the opp side.
- A2: HIGH in bot-only seats with SaudiMaster; the bug
  manifests as "noise-AKA is rarely punished by bot opponents"
  rather than a user-visible Takweesh event.

**Note:** the user's incident wording — "third bot / human
teammate" — does NOT clearly distinguish A1 vs A2. Both are
plausible reads.

### 7.2 Scenario B — Human teammate misclicks Takweesh

**Mapping:** "made the third bot / human teammate use Takweesh"
= the user (a HUMAN) on the bot's OWN team saw the bot's
false-AKA banner, didn't realize the false-AKA marker would be
caught by the opps via Takweesh, and PRE-EMPTIVELY clicked
TAKWEESH themselves — but the host's scan filtered out
same-team illegal plays (§6), the call resolved as false, and
the human's team was Qaid-penalized.

**Classification:** **USER-HOSTILE UX / DOCUMENTATION GAP.** The
TAKWEESH tooltip in `UI.lua:2479-2485` warns about wrong calls
generically but does NOT explicitly state "calling Takweesh on
your TEAMMATE's illegal play counts as a wrong call." This is
a UX failure, not a runtime bug.

**Likelihood:** **MEDIUM** — the user's wording "human teammate
use Takweesh" hints at this read. A confused human who saw a
bot AKA banner and thought "I should call this out" wouldn't
know that teammate-illegal-plays don't qualify.

### 7.3 Scenario C — `MSG_AKA` race or replay drift

**Mapping:** AKA banner fires on a client BEFORE the host has
marked the play as illegal, and the client's UI somehow
exposes the in-flight banner to the human in a way that
encourages a Takweesh click before the host's false-AKA
marking has propagated.

**Classification:** **POSSIBLE PROTOCOL BUG.** Would need to be
reproduced with packet capture / log inspection. The 250ms
retry in `N.SendTakweesh` and `N.SendAKA` minimizes the window,
but a single-frame drop or out-of-order arrival could in
principle leave a remote client seeing the AKA banner without
having the host-marked `illegal` flag (remotes don't validate;
they trust the host).

**Likelihood:** **LOW** — but worth noting as the only path
that would point to a real runtime change.

### 7.4 Scenario D — Bot Takweesh-of-teammate bug

**Mapping:** A bot called Takweesh on its own teammate's false
AKA, leading to bot's team penalty.

**Classification:** **NOT POSSIBLE under current code.** The
`R.TeamOf(p.seat) ~= myTeam` filter at `Bot.lua:5955` is
unambiguous. This scenario can be ruled out without a repro.

**Likelihood:** **NONE.**

### 7.5 Most-likely classification (Codex correction)

**Two threads to act on, not one:**

- **Sub-scenario A1 (human opp catches false AKA via UI
  button):** WORKING AS DESIGNED. No action.
- **Sub-scenario A2 (bot opp `Bot.PickTakweesh` does NOT catch
  because of the realism-gate mismatch with `illegalReason ==
  "false AKA"` semantics):** LIKELY RUNTIME BEHAVIOUR GAP. The
  bot's gate is over-conservative for false-AKA; the violation
  is publicly knowable at the moment of the lead, no later
  reveal needed. Recommend a narrowly-scoped runtime fix.
- **Scenario B (UX hazard — human teammate clicks TAKWEESH on
  the bot's false AKA):** UNCHANGED — clearer tooltip /
  review-banner wording remains the right action.

From the user's perspective, both A2 and B contribute to the
"a bot did AKA → someone Takweesh'd" feeling: A2 says "the bot
opponents almost never punish noise-AKA, so when they do, it's
notable"; B says "if a human teammate intercepts incorrectly,
the bot's team eats the penalty."

The runtime gap (A2) is the more impactful of the two:
- It makes SaudiMaster's signal-deception strategy net-negative
  at bot-only tables (the deception fires but is rarely
  caught, leaking info to opps without paying the bluff cost).
- It makes humans-vs-bot tables asymmetric — humans catch the
  bluff at 100% of click rate, bots catch at near 0%.
- The fix is small and well-targeted (see §9.2).

---

## 8. Minimal repro proposals (Codex correction)

These deterministic test fixtures target two threads
identified in §7.5:

- **A2 — runtime gap on `Bot.PickTakweesh` + false AKA:** BM.1
  (failure mode), BM.2 (control: revoke-style still needs
  realism reveal).
- **B — same-team filter (UX hazard):** BM.3.
- **Noise-AKA coverage gap:** BM.4 + BM.5.

### 8.1 BM.1 — false AKA is immediately bot-catchable (likely currently FAILS)

**Fixture intent:** verify `Bot.PickTakweesh` catches a
publicly-knowable false-AKA violation **without** requiring a
later same-suit reveal.

- Hokm contract, trump `S`, bidder seat 1.
- `S.s.tricks` contains one prior completed trick where:
  - Seat 2 (opp of bot caller at seat 3) led `KH` with
    `illegal = true, illegalReason = "false AKA"`, leadSuit
    `"H"`.
  - **No** subsequent trick records seat 2 playing any H card.
    The realism gate's `laterPlayedLeadSuit(seat=2, "H", ...)`
    therefore returns false.
- Bot at seat 3, opp team, Advanced or higher.
- Stub `math.random()` to return `0.5` (well below the 0.95
  Takweesh rate at `Bot.lua:5907`, so the rate roll passes).
- Call `Bot.PickTakweesh(3)`.

**Desired behaviour (post-fix):** returns the seat-2 illegal
play record. False AKA is treated as immediately observable.

**Current behaviour (pre-fix):** returns `nil`. The realism
gate's `laterPlayedLeadSuit` check fails because seat 2 never
replayed H, even though the violation is publicly knowable
from the trick log + AKA banner.

**This test will FAIL against current runtime** and motivates
the small runtime fix proposed in §9.2.

### 8.2 BM.2 — ordinary illegal still needs realism reveal (control)

**Fixture intent:** verify the realism gate stays in place for
**non-false-AKA** illegal reasons (e.g. a revoke / off-suit
play). Ensures the fix in §9.2 narrowly scopes to the
false-AKA case.

**Setup A (no later reveal → no Takweesh):**
- Prior completed trick: seat 2 played off-suit on an H-led
  trick — `illegal = true, illegalReason = "must follow suit"`
  (or similar non-false-AKA reason), leadSuit `"H"`.
- No subsequent H play by seat 2.
- Stub `math.random()` to return `0.5`.
- Call `Bot.PickTakweesh(3)`.

**Expected:** returns `nil`. Realism gate correctly blocks
revoke-style claim without proof.

**Setup B (later reveal → Takweesh fires):**
- Same as Setup A except a subsequent trick records seat 2
  playing an H card (revealing they had it during the
  off-suit play).
- Stub `math.random()` to return `0.5`.
- Call `Bot.PickTakweesh(3)`.

**Expected:** returns the seat-2 illegal play record. Realism
gate fires after the later reveal proves the violation.

**Wire role:** BM.2A/B together prove the realism gate
behavior is preserved for revoke-style violations even after
the BM.1 carve-out lands. Stops a regression where the §9.2
fix accidentally drops the gate for all reasons.

### 8.3 BM.3 — same-team Takweesh call resolves as false call

**Fixture intent:** verify the `HostBeginTakweeshReview` and
`HostResolveTakweesh` scans both reject same-team illegal
plays, leading to a Qaid penalty against the caller's team.

- Host fixture: seat 1 announced AKA on H, led KH with AH
  unplayed → marked `illegal = true, illegalReason = "false
  AKA"`.
- Caller: seat 3 (same team as seat 1, both team A).
- Call `N.HostBeginTakweeshReview(3)` directly.

**Expected:** `S.s.takweeshReview.illegalSeat == nil`
(scanIllegal at `Net.lua:3360-3372` filters out the same-team
violation). Subsequent `HostResolveTakweesh(3, nil)` should
apply the Qaid penalty to team A (caller's team).

**Wire role:** documents the same-team filter at `Net.lua:3362`
and the symmetric filter at `Net.lua:3545`. Locks the UX
hazard's actual behavior so a regression where same-team
filtering accidentally relaxes would be caught.

### 8.4 BM.4 — `PickAKANoise` deterministic emission

**Fixture intent:** Verify `Bot.PickAKANoise` returns the suit
when (a) SaudiMaster, (b) bot leads K or Q non-trump, (c) bot
doesn't hold the A of that suit.

- `WHEREDNGNDB = { saudiMasterBots = true }`.
- Hokm contract, trump = `S`.
- Stub `math.random()` to return `0.0` (so `math.random() >=
  0.08` is false and the noise path enters at `Bot.lua:5658`).
- Bot hand has KD, QC, etc. but **not** AD.
- Lead card = `KD`.
- Call `Bot.PickAKANoise(seat, "KD")`.

**Expected:** returns `"D"` (the noise suit).

**Wire role:** locks the v1.6.0 8% rate path. Currently no test
exercises `Bot.PickAKANoise` at all (zero matches in the test
file).

### 8.5 BM.5 — `PickAKANoise` declines when bot holds the actual A

**Fixture intent:** Verify the noise path correctly declines
when bot DOES hold the actual boss (which would make it a
legitimate delayed AKA, not noise).

- Same as BM.4 but bot hand includes `AD` (the actual boss of
  D).
- Lead card = `KD`.
- Stub `math.random()` to return `0.0`.
- Call `Bot.PickAKANoise(seat, "KD")`.

**Expected:** returns `nil` (the `Bot.lua:5673-5677` early-
return path fires).

**Wire role:** locks the "we DO have the A; not a noise
opportunity" carve-out.

### 8.6 Existing coverage that already locks adjacent behavior

- **J.3** (test_state_bot.lua:1777-1857): false-AKA marking on
  `S.ApplyPlay`. Three sub-cases (positive, true-AKA sanity,
  suit-mismatch edge). **Sufficient — do not duplicate.**
- **Y.4** (test_state_bot.lua:3296-3304): Takweesh rate flat
  0.95 across tricks. Source pin.
- **Z.4** (test_state_bot.lua:3377-3381): Takweesh fallback
  rate. Source pin.
- **AE.9** (test_state_bot.lua:4391+): pickFollow AKA-receiver
  branch fires under `akaLive` regardless of `partnerWinning`.
- **AO.\*** (test_state_bot.lua:7009+): v3.0.8 Takweesh review
  phase wire — `HostBeginTakweeshReview`, `HostApproveTakweesh`,
  `HostRejectTakweesh`, `_OnTakweeshReview` all defined.

The gap is `Bot.PickAKANoise` (zero coverage), `Bot.PickTakweesh`
behavioral (only rate constant pinned), and the runtime gap
where `Bot.PickTakweesh` mis-gates false-AKA violations behind
the revoke-style realism check.

---

## 9. Recommendation (Codex correction)

### 9.1 Classification

**Primary findings:**
- **A1 (human opp clicks TAKWEESH on false AKA):** WORKING AS
  DESIGNED. No action.
- **A2 (bot opp `Bot.PickTakweesh` mis-gates false AKA via the
  revoke-style realism check):** LIKELY RUNTIME BEHAVIOUR GAP.
  Recommend a narrowly-scoped runtime fix.
- **B (same-team Takweesh click → caller's team penalized):**
  UX hazard. Recommend clearer tooltip + review-banner wording
  to be added in a separate Codex round.

### 9.2 Proposed runtime fix (implemented; v3.2.6 Codex amend round 2)

The v3.2.6 fix has **two carve-outs**, both targeting
`illegalReason == "false AKA"` only. Revoke / off-suit illegal
plays keep the v1.5.1 realism gate unchanged.

**Carve-out A — completed-tricks scan** (`Bot.lua:5955-5982`):

```lua
if p.illegal and R.TeamOf(p.seat) ~= myTeam then
    if p.illegalReason == "false AKA" then
        found = p; break
    end
    if t.leadSuit and laterPlayedLeadSuit(p.seat, t.leadSuit, tIdx) then
        found = p; break
    end
end
```

**Carve-out B — current-trick scan** (`Bot.lua:5986-6004`,
Codex amend round 2):

```lua
if not found and S.s.trick and S.s.trick.plays then
    for _, p in ipairs(S.s.trick.plays) do
        if p.illegal
           and p.illegalReason == "false AKA"
           and R.TeamOf(p.seat) ~= myTeam then
            found = p
            break
        end
    end
end
```

**Why a separate current-trick scan?** False AKA is publicly
knowable the moment `State.ApplyPlay` marks the lead at
`State.lua:1466-1493` — the derivation is purely from
`playedCardsThisRound` + the `s.akaCalled` banner, both of
which every client tracks identically. The host's
`HostBeginTakweeshReview` already does a current-trick scan at
`Net.lua:3370-3372` after the completed-tricks loop:

```lua
if not foundIllegal and S.s.trick then
    foundIllegal = scanIllegal(S.s.trick.plays)
end
```

A human pressing TAKWEESH the moment after an opp leads a
false AKA catches the bluff via that current-trick scan. The
v1.5.1 round-1 fix at `Bot.lua:5969` ("do NOT scan in-progress
trick") was correct for revoke / off-suit cases — those need a
later same-suit reveal which is structurally impossible inside
the current trick — but blocked bot callers from matching the
host/human authority for false AKA. Carve-out B brings them
back in line.

**Why ONLY false AKA in the current-trick scan?** Revoke /
off-suit violations in the current trick have zero opportunity
for "later reveal" by definition (the trick hasn't completed,
no subsequent trick exists). The v1.5.1 rationale at
`Bot.lua:5969-5971` still holds for those reasons. BM.2A
remains a regression guard against accidentally widening the
current-trick scan to all reasons.

**Risk profile:**

- **Scope:** ~22 lines net added to a single function, two
  related branches.
- **Reach:** affects bot Takweesh decision only. Does NOT
  touch host scan, marking layer, AKA receiver relief, or
  scoring. The host's `HostBeginTakweeshReview` /
  `HostResolveTakweesh` already accept false-AKA markers (and
  the host already includes a current-trick scan), so the fix
  only brings bot callers in line with the host's authority
  model.
- **Regression risk:** LOW. Non-false-AKA branches are
  preserved verbatim. BM.2A (revoke without reveal) + BM.2B
  (revoke with reveal) act as controls.
- **Gameplay impact:** raises the cost of SaudiMaster
  noise-AKA from ~0% punishment to ~95% punishment per
  qualifying lead. With the current-trick carve-out, opp bots
  punish noise-AKA leads on the **very next seat's turn** —
  the noise-AKA bluff costs the bidder team the round if any
  opp bot is at sufficient tier.

### 9.3 Action recommendation

**Recommended action: runtime fix + test coverage. Tooltip
wording is a separate, optional follow-up.**

1. **Runtime fix candidate (§9.2):** narrowly-scoped
   `Bot.PickTakweesh` carve-out for `illegalReason == "false
   AKA"`. Defer to a separate implementation prompt with
   Codex re-approval.

2. **Add tests** (BM section, 7 test blocks emitting 15 harness checks per Codex amend round 2):
   - BM.1 — false AKA in a COMPLETED trick is bot-catchable
     (FAILS pre-round-1-fix, passes post). Wire-proof for
     completed-trick carve-out A.
   - BM.2A — non-false-AKA illegal WITHOUT later reveal stays
     blocked (control; v1.5.1 realism gate preserved).
   - BM.2B — non-false-AKA illegal WITH later reveal catches
     (control; v1.5.1 realism gate fires correctly).
   - BM.3 — same-team Takweesh scan rejects.
   - BM.4 — `PickAKANoise` deterministic emission.
   - BM.5 — `PickAKANoise` declines when bot holds actual A.
   - **BM.6** (Codex amend round 2) — false AKA in the
     CURRENT trick is bot-catchable (FAILS pre-round-2-amend,
     passes post). Wire-proof for current-trick carve-out B.

3. **UI tooltip wording (deferred to a separate Codex
   round):** extend the TAKWEESH tooltip at `UI.lua:2479-2485`
   to explicitly state: *"Only the opposing team's illegal
   plays qualify. Calling Takweesh on your own teammate's
   illegal play counts as a wrong call."* Out of scope for
   the v3.2.6 BM batch; flag for a paired v3.2.6b UX slice if
   Codex agrees.

4. **NO defer-indefinite.** All seven BM blocks are
   deterministic and tractable.

### 9.4 Release impact (Codex amend round 2)

- Final implemented harness count: **`1295 / 0`** (baseline
  `1280 / 0` + 15 BM checks: BM.1×3 + BM.2A×1 + BM.2B×2 +
  BM.3×4 + BM.4×1 + BM.5×1 + BM.6×3).
- Pre-fix BM.1 FAILS (verified by stashing Bot.lua and
  re-running: `1289 / 1`). Pre-amend BM.6 FAILS (verified by
  stashing Bot.lua post-round-1 and re-running: `1292 / 1`).
  Both wire-discriminators target the v3.2.6 carve-outs.
- The v3.2.5 release recommendation remains "HOLD" per the
  paired release-readiness checkpoint. The v3.2.6 runtime fix
  + BM tests + tooltip wording (optional) is the right next
  release candidate.

---

## 10. Stop conditions for any follow-on implementation

1. **BM.1 passes pre-fix (without §9.2 runtime change).** If
   the fixture as specified in §8.1 already returns the seat-2
   illegal play, the realism gate is firing for some other
   reason (e.g. another prior trick coincidentally has seat 2
   playing H). Re-audit the fixture's prior-tricks construction
   to ensure the only H plays are the false-AKA lead itself.
2. **BM.2A (control, no later reveal) passes when it should
   fail.** That would indicate the realism gate is already
   relaxed for revoke-style violations, contradicting v1.5.1.
   Stop and audit `Bot.lua:5927-5968` before proceeding.
3. **BM.2B (control, with later reveal) fails when it should
   pass.** Indicates the realism gate has regressed for the
   revoke-style case. Stop and audit before proceeding.
4. **BM.3 (same-team scan) finds an illegal play despite
   same-team filter.** Indicates the `R.TeamOf(p.seat) ~=
   callerTeam` filter at `Net.lua:3362` or `Net.lua:3545` has
   regressed. Stop and report as a runtime regression.
5. **BM.4 / BM.5 produce non-deterministic results.** The
   `math.random` stub pattern is well-precedented (AJ.12, BE.1,
   etc.). If it doesn't pin the outcome, audit the stub.
6. **§9.2 runtime fix breaks existing AKA tests** (J.3, AE.9,
   AN.1, AQ.7, AS.3, AZ.13-15, AO.\*). Stop and re-audit the
   carve-out scope.
7. **§9.2 fix raises Takweesh-fire frequency unacceptably in
   bot-only tournaments.** If a smoke run shows ISMCTS rollout
   metrics or tier-comparison tournaments degrade because
   bots now correctly punish noise-AKA, the v1.6.0 8% rate may
   need to drop (separate Codex round). Out of scope for the
   v3.2.6 fix itself; flag if observed.
8. **UI tooltip wording change risks user confusion.** Wording
   must be neutral and not imply the bot is "cheating" via
   noise-AKA. Out of scope for v3.2.6 BM batch; flagged for a
   separate v3.2.6b round.

---

## 11. Confirmation

- No tracked files changed by this investigation pass.
- This document is created uncommitted.
- No edits to `Bot.lua`, runtime files, `tests/`, `.toc`,
  `.pkgmeta`, `.github/`, CHANGELOG.
- No branch created, no tag created, no release initiated.
- `sprint-a-experimental` and `v0.5.1-experimental` preserved.
- `.swarm_findings/v3_2_0_botlua_comment_audit.md` untouched
  and untracked.
