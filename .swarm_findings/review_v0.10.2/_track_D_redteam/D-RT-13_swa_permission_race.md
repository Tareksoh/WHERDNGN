# D-RT-13: SWA Permission Flow Red-Team

**Audit version**: v0.10.2
**Track**: D (red-team)
**Date**: 2026-05-05
**Scope**: Red-team the SWA permission flow against the v0.10.0 R3 reaudit finding that the 5-second auto-approve timer is **NOT a Saudi rule** — it is an addon-UX construct. Find races, exploits, rule violations across the full pipeline. **No code modifications.**

---

## TL;DR (verdict at the top)

The SWA permission flow has **one CRITICAL rule violation**, **two MEDIUM races**, **two LOW pause-edge cases**, and **one INFO-level Saudi-strict caveat**. Confirmed prior findings: F-1 (UI no hand-count gate, MEDIUM), F-2 (Bot SWA timer no pause re-arm, MEDIUM), F-3 (banner countdown drift on pause, LOW), F-4 (Takweesh-during-SWA cleared correctly, LOW informational), F-5 (mid-trick OK).

**The CRITICAL find (RT-13.1)** is conceptual/rule-level rather than code-level: per video #35 the 5-second auto-approve **structurally inverts the Saudi rule** for ≥5-card SWA. Saudi convention for ≥5-card SWA is "تستاذن" (must ask permission, must hear permission granted) and "مستحيل يمشونها" (they would never let it pass). The addon's auto-approve makes silence = consent. A 5+-card invalid SWA caller who fires from a 3-bot table with a single human opponent who AFKs/disconnects/fails to see the banner gets **automatic permission they would never receive at a Saudi table**. This is documented in CLAUDE.md as "addon-UX timer to bypass deadlock" — but the rule-violation surface is exactly the ≥5-card mandatory-permission gate, which becomes silent-permission under the timer.

The CODE itself is internally consistent and the timer design is justified as a humans-AFK deadlock fallback. The red-team verdict is: **the timer's existence in the ≥5-card path is a Saudi-rule violation by construction**, regardless of code correctness. Recommendations below; no code change required by the prompt.

---

## RT-13.1 — CRITICAL: 5+-card SWA auto-approves on silence (Saudi-rule inverted)

**Confidence: HIGH (rule-level), HIGH (code traces).**

**Source rule (verbatim, from `reaudit_R3_swa.md` lines 87-93)**:

- Video #35 line 2244: "في شيء اسمه سوا من اول يد" — "there's a thing called 'swa from first hand'" (the ≥5-card SWA).
- Video #35 line 2404: "هنا تستالن طبعا ما تساوي" — "here you absolutely must ask permission, you don't just swa".
- Video #35 line 2414: "لو ساويت بدون ما تستاذن يا سلام هذه مستحيل يمشونها" — "if you swa'd without asking permission — wow — they would never let it pass; it's an opportunity for them to qaid you".

The rule is: **≥5 cards → permission MUST be explicitly granted. Otherwise it's a Qaid opportunity for the opponent.** Verbal verification (نسمح) or denial (خلينا نلعب). No clock.

**Code (Net.lua line 2473-2580, `N.LocalSWA`)**:

```lua
local handCount = #(S.s.hand or {})
local needPerm = (WHEREDNGNDB == nil)
              or (WHEREDNGNDB.swaRequiresPermission ~= false)
...
if needPerm then
    -- Permission flow: broadcast a request, wait for opponents.
    local enc = C.EncodeHand(S.s.hand or {})
    S.s.swaRequest = {
        caller    = S.s.localSeat,
        handCount = handCount,
        responses = {},
        encodedHand = enc,
        ts        = (GetTime and GetTime()) or 0,
        windowSec = K.SWA_TIMEOUT_SEC or 5,
    }
    N.SendSWAReq(S.s.localSeat, enc)
    ...
    if S.s.isHost then
        ...
        if C_Timer and C_Timer.After then
            local windowSec  = K.SWA_TIMEOUT_SEC or 5
            ...
            C_Timer.After(windowSec, function()
                ...
                local req = S.s.swaRequest
                if not req or req.caller ~= mySeat then return end
                if S.s.phase ~= K.PHASE_PLAY then return end
                S.s.swaRequest = nil
                N.HostResolveSWA(mySeat, pinnedHand)
            end)
        end
    end
```

The SAME `K.SWA_TIMEOUT_SEC = 5` (Constants.lua line 281) timer that handles a ≤3-card claim ALSO handles the ≥5-card claim. There is no hand-count branch. Net.lua line 2502 routes ALL `needPerm` paths through one `swaRequest` flow.

**Exploit scenario (rule-violation, not code-bug)**:

1. Player A is at a table with one human opponent (player B) and two bots on player B's team (or three opponents none of whom are watching).
2. Round 1, trick 1, player A's hand is 8 cards. Player A clicks SWA. `R.IsValidSWA` is **almost certainly going to return false** (an 8-card invalid SWA is a deterministic-or-bust failure, qaid-able).
3. Per Saudi rule (#35 line 2414), player B's table would NEVER let this pass — the rule says "مستحيل يمشونها" — "impossible they would let it pass". A Saudi opponent would say "خلينا نلعب" verbally.
4. The addon broadcasts MSG_SWA_REQ. Player A's team has no votes (caller doesn't vote on own request, partner doesn't vote — Net.lua line 2598 `if R.TeamOf == R.TeamOf(req.caller) then return end`).
5. Player B is the only human voter. Player B is AFK / didn't see the banner / disconnected / has a higher latency than the 5-sec timer.
6. The 2 opponent-team bots **auto-accept** (Net.lua line 2528-2533). The 5-sec timer fires (Net.lua line 2546). `swaRequest` is cleared. `HostResolveSWA` runs.
7. `R.IsValidSWA` returns false (invalid SWA). The code applies the **Qaid penalty**: opponent (player B's team) takes `handTotal × mult`, caller (player A) forfeits their team's melds.

**Where's the violation?**

The code "works correctly" — it applies Qaid because R.IsValidSWA failed. A Saudi player would ALSO take the Qaid. The rule-violation is more subtle: the **code's "silent consent ⇒ permission granted ⇒ then run validity check"** is not the Saudi flow. The Saudi flow is **"explicit verbal consent ⇒ play out the claim"** with no validity check at all (the consent IS the gate; if opponents grant permission, the SWA proceeds without R.IsValidSWA).

But more importantly, consider the **inverse exploit**: a player A claims an 8-card SWA that IS deterministically valid (mathematically possible only with 4 Aces + 4 Tens of trump in Hokm — extreme edge but possible in shuffled deals). Per #35, opponents would still NOT permit it ("مستحيل يمشونها" applies to ≥5-card SWAs categorically). The addon's auto-approve makes silence = "yes, fine, run the validator" — silent consent the Saudi convention says is impossible.

**Code citation: this conflict is by-design**. CLAUDE.md (after the R3 reaudit amendment) explicitly says:

> The 5-second auto-approve timer is an addon UX construct, NOT a Saudi rule. Per video #35... Saudi convention uses verbal negotiation with no timeout — opps either say "نسمح" (allow) or demand شرح (proof). The addon's auto-approve prevents network deadlock when humans don't respond.

So the code authors KNOW this is a divergence. The red-team observation: **the divergence is more rule-impactful for ≥5 than for ≤4**. A ≤3-card silent-consent is harmless (any reasonable opponent would say نسمح); a ≥5-card silent-consent inverts a categorical Saudi prohibition.

**Recommendation**:

- **(R1, behavioral)** Branch on hand-count: ≤4 cards uses the existing 5-sec auto-approve. ≥5 cards uses **opponent-must-explicitly-accept** (no auto-approve; deny-on-timeout instead of approve-on-timeout). This matches video #35's "must ask permission" reading literally.
- **(R2, less invasive)** Keep the timer but flip its semantics for ≥5: timeout = deny (with `swaDenied` toast and round resumes). Avoids the soft-lock, preserves the rule.
- **(R3, doc-only)** Annotate Constants.lua `K.SWA_TIMEOUT_SEC` with: "WARNING: timeout-approve at ≥5 cards inverts video #35's mandatory-explicit-permission rule. Acceptable for solo-bot tables (caller's only opponents are auto-approving bots anyway); a regression risk in mixed-human-bot tables where the human opp AFKs."

The prompt says "Do NOT modify code" — so the recommendation goes into the report only.

**Test fixture proposal (no code change)**:

```
SWA-RT-1: 5+-card, AFK opponent
  • Setup: 4-player table, host = bot opponent A, partner = human, opps = bot + human-AFK
  • Round 1, trick 1, host bot calls SWA at 8 cards
  • Wait 6 seconds without responding from human opponent
  • Expected (per Saudi rule): SWA must NOT auto-approve
  • Actual (per code): SWA auto-approves at t=5s, R.IsValidSWA runs,
    invalid → Qaid penalty applied
  • Verdict: code violates Saudi rule by approving where the rule
    requires explicit denial-on-silence
```

---

## RT-13.2 — MEDIUM: Mid-permission race winner is timer or deny, not deterministic across hosts

**Confidence: HIGH (code traces).**

The prompt's question 1: "caller sends MSG_SWA_REQ, opp clicks 'deny' via Takweesh, simultaneously timer fires to auto-approve. Which wins? Is the order deterministic across hosts?"

**Three competing resolvers can mutate `swaRequest`**:

1. **Auto-approve timer** (Net.lua line 2546 / 2693 / 4059) — sets `S.s.swaRequest = nil` and calls `HostResolveSWA`.
2. **Explicit deny via `_OnSWAResp`** (Net.lua line 2754) — sets `swaRequest = nil` and `swaDenied`.
3. **Takweesh via `HostResolveTakweesh`** (Net.lua line 2144) — sets `swaRequest = nil` and resolves the round on illegal-play scan.

All three are dispatched on the host's main thread (WoW addon channel handlers + C_Timer callbacks all run in the same single-threaded reactor). **There is no preemption mid-callback.** So the question reduces to: which message arrives first in the host's reactor?

```
case A: deny arrives first
  _OnSWAResp(deny) → swaRequest = nil → swaDenied set
  Timer fires later: line 2570 `local req = S.s.swaRequest` → nil → return
  ✓ Correct: deny wins.

case B: timer fires first
  Timer callback runs synchronously to completion
  _OnSWAResp(deny) arrives next:
    Net.lua line 2742-2743: `local req = S.s.swaRequest; if not req or req.caller ~= caller then return end`
    swaRequest is nil (timer cleared it) → return
  But: HostResolveSWA already ran inside the timer callback,
       phase has moved to PHASE_SCORE, S.s.lastRoundResult is set
  ✓ Correct: timer wins; deny is dropped silently.

case C: Takweesh and deny race
  Whichever arrives first, the other early-returns.
  HostResolveTakweesh's phase guard at line 2129
  (`if S.s.phase ~= K.PHASE_PLAY then return end`) ensures idempotence.
  ✓ Correct.
```

**Determinism across hosts**: `C_Timer.After(5)` resolution is host-clock-dependent. `GetTime()` is the WoW client's wall clock. Two hosts in different timezones or with clock drift CANNOT race here because **only the host runs the timer** — but if a /reload mid-flow cycles host responsibility (impossible in this codebase per `if S.s.isHost then return end` gates in WHEREDNGN.lua line 263, 279, 282), the reset would be deterministic.

**The sub-finding (NEW, MEDIUM-LOW)**: in `_OnSWAResp` at line 2742, after a deny clears `swaRequest`, the Takweesh path's auto-clear at line 2144 is **a redundant nil-write** — not a bug, just a code-smell. Belt-and-suspenders defensive.

**However, RT-13.2-A (race window):**

```
case D: rapid double-deny from the SAME opponent (network duplicate)
  First deny: swaRequest cleared at line 2754
  Second deny arrives: line 2742 `local req = S.s.swaRequest`
    → nil (already cleared by first deny) → early return
  ✓ Correct, idempotent.

case E: single deny + bot-auto-accept interleaved
  _OnSWAReq's bot auto-accept (line 2683) fires SYNCHRONOUSLY
  inside `_OnSWAReq` BEFORE the function returns. So when `_OnSWAReq`
  finishes, req.responses[bot1] = true and req.responses[bot2] = true
  (if both bots are opponents).
  Then the human deny arrives: line 2747 `req.responses[responder] = false`,
  line 2753-2787 deny path runs, swaRequest cleared, swaDenied set.
  Bot accepts are visible in req.responses but irrelevant — deny is final.
  ✓ Correct.
```

**Verdict on Q1**: Resolution is deterministic per-host; no host-vs-host race exists because only the host runs the timer. **Determinism is preserved by the swaRequest nil-check at every site.** The 50-agent audit's belt-and-suspenders (Net.lua line 2144) is what makes this robust.

---

## RT-13.3 — RT-13.1 corollary, REPEATED for emphasis: 5+-card auto-approve

**Confidence: HIGH.**

The prompt's question 2 is essentially RT-13.1. **Yes, a 5+-card SWA can pass via auto-approve**. The code routes 5+ through the same `K.SWA_TIMEOUT_SEC = 5` timer as ≤3. There is no hand-count branch in `N.LocalSWA` after `needPerm` is computed.

**Should it pass?** Per video #35: NO. Per the addon's stated UX rationale (deadlock prevention): YES.

**Code-paths confirming the routing**:

- `N.LocalSWA` Net.lua 2502: `if needPerm then ... encodedHand = enc, ... C_Timer.After(windowSec, ...) end`
- `N._OnSWAReq` Net.lua 2693: same `C_Timer.After(windowSec, ...)` for remote-receive path
- `MaybeRunBot` Net.lua 4059: same timer for bot-fired SWA

There is no code path that SAYS `if handCount >= 5 then require_explicit_accept = true`. The threshold is collapsed.

This is the most important red-team finding. Already counted as RT-13.1.

---

## RT-13.4 — MEDIUM: Pause+SWA — timer freezes on host's path but bot path drops silently (F-2 confirmed)

**Confidence: HIGH (code traces match C-Xref-01 F-2).**

The prompt's question 3: "SWA in flight, host pauses. Does the timer freeze? On resume, does it restart with a fresh 5s window?"

**Three timer-arming sites have inconsistent pause behavior** (already documented as F-2 in C-Xref-01):

| Site | Lines | Pause re-arm? |
|---|---|---|
| `N.LocalSWA` host-self timer | 2546-2576 | YES (full re-arm via line 2552-2569) |
| `N._OnSWAReq` remote-receive timer | 2693-2730 | YES (full re-arm via line 2701-2718) |
| `MaybeRunBot` bot-fired timer | 4059-4067 | NO — bare `if S.s.paused then return end` early-exit at line 4061 |
| `WHEREDNGN.lua` PLAYER_LOGIN restore | 270-292 | YES (timer body re-checks `if B.State.s.paused then return end` at line 283 — but does NOT re-arm; same flaw as MaybeRunBot) |

**Code (Net.lua line 2546-2569, the GOOD path)**:

```lua
C_Timer.After(windowSec, function()
    if not S.s.isHost then return end
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
    ...
```

If paused, schedule another 5s timer; on resume, that runs.

**Code (Net.lua line 4059-4067, the BAD path — bot-fired SWA)**:

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not S.s.isHost then return end
    if S.s.paused then return end                   -- bare early-exit
    local req = S.s.swaRequest
    if not req or req.caller ~= seat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    S.s.swaRequest = nil
    N.HostResolveSWA(seat, hand)
end)
```

If paused at fire-time, the timer callback returns silently. `swaRequest` stays set forever. The next thing that clears it is either:

- A human opp clicks Takweesh (Net.lua line 2144 clear).
- Round ends another way (ApplyStart line 813 clear, but ApplyStart doesn't fire if no round-advance happens).
- /reload triggers SaveSession → swaRequest persists (NOT in TRANSIENT_FIELDS per State.lua line 225-230 comment) → restored → WHEREDNGN.lua line 270-292 fires a fresh re-arm. ✓ This actually saves the day for the bot-fired path: a /reload mid-paused-bot-SWA does recover.
- Manually toggle pause off and on (since pause is idempotent per N.LocalPause line 2404 `if S.s.paused == paused then return end` — toggling off-on doesn't re-fire the bot timer).

**Practical consequence**: Bot fires SWA → host pauses → human stays paused → request hangs UI banner indefinitely (UI.lua banner OnUpdate guards on `S.s.paused` per F-3). After unpause, NOTHING re-fires the resolution. The user sees the banner stuck. Workarounds: human opp clicks Takweesh, or /reload to trigger restore-rearm.

**Recommendation**: copy LocalSWA's pause-re-arm block into MaybeRunBot's bot-SWA timer callback. Already on backlog as F-2.

**Sub-finding (NEW, RT-13.4-A)**: WHEREDNGN.lua line 270-292's PLAYER_LOGIN re-arm has the SAME bare early-exit pattern as MaybeRunBot — **if the player /reloads while paused, the auto-resolve timer arms but its body checks `if B.State.s.paused then return end` (line 283) without re-arming. Same drop-on-pause failure mode**. Severity LOW because /reload is rare during a paused game. Not previously flagged.

**Sub-finding (NEW, RT-13.4-B)**: `N._OnSWAReq`'s pause-re-arm at line 2693-2730 actually has a **silent integer-overflow risk in extreme cases** — the re-arm only fires once. If the host pauses, then 4.99s later un-pauses-and-re-pauses without the inner timer firing, the re-arm only stretched the window by 5s after the FIRST pause-detection. After multiple pause cycles, the inner re-arm timer would run and resolve mid-pause if `S.s.paused == false` at fire time. **The inner re-arm only fires once and trusts pause-state at fire time** — multiple rapid pause cycles cause a silent mid-cycle resolution. Practically rare; doc-as-known-quirk.

---

## RT-13.5 — LOW: Opp-Takweesh-during-SWA-window — correct (F-4 confirmed)

**Confidence: HIGH.**

The prompt's question 4: "opp calls Takweesh on the SWA caller while SWA permission window is open. Does Takweesh resolution clear the SWA request? Does it correctly compute the Qaid penalty?"

**Yes**, both correctly handled:

```
SWA window open → swaRequest = { caller = A, responses = {} }
Opp B calls Takweesh:
  N.LocalTakweesh → broadcast MSG_TAKWEESH → N._OnTakweesh on host
  → N.HostResolveTakweesh(B)
    line 2129: phase guard (PHASE_PLAY) ✓
    line 2144: S.s.swaRequest = nil   ← explicit clear
    line 2150-2162: scanIllegal across all tricks (caller A's plays)
    line 2175: winnerTeam = (foundIllegal ? B's team : A's team)
    line 2196-2218: Saudi Qaid: offender's melds zeroed, winner's kept
    line 2259-2260: addA, addB after div10
    line 2264: S.ApplyRoundEnd
    line 2275-2284: takweeshResult banner

Later: SWA's 5-sec timer fires (Net.lua line 2546 timer body):
  line 2570: `local req = S.s.swaRequest` → nil → return ✓
```

The Takweesh dominance is correct; the SWA request is fully cleared; Qaid penalty math is identical to the SWA-invalid path (both at handTotal × mult + own melds × mult, melds zeroed for offender, Belote independent).

**Subtle correctness preserved**: the offender in a Takweesh path is determined by `foundIllegal` (the actual illegal-play scan, not the SWA caller's seat). So an opp-Takweesh that finds NO illegal play in the caller's history awards the round to the SWA caller (`winnerTeam = oppTeam` of caller... wait, this is subtle):

**Re-reading Net.lua line 2175**:

```lua
local winnerTeam = foundIllegal and callerTeam or oppTeam
```

`callerTeam` here is the **Takweesh caller's team** (the OPP of the SWA caller). `oppTeam` is the SWA caller's team. So:

- If the Takweesh caller (opp B) finds an illegal play by SWA-caller A → winnerTeam = B's team ✓ Saudi-correct.
- If the Takweesh caller finds NO illegal play → winnerTeam = A's team (the opp of B) → Saudi-correct (false Takweesh punishes the Takweesh caller).

This is correct per Saudi convention "false-takweesh recoils on the caller". ✓

**No race window** for Takweesh during SWA. Confirmed.

**Sub-finding (RT-13.5-A, INFO)**: The Takweesh DURING SWA permission-window scenario is interesting because the SWA caller might have NOT yet committed to revealing their hand. The wire frame for SWA is `MSG_SWA_REQ;seat;encodedHand` (Net.lua line 2521), which DOES carry the hand. So even if the SWA is interrupted by Takweesh and never resolves, the caller's hand is already on the wire. Saudi privacy concern? Not really — once you announce SWA you're already publicly committing the claim. But for tournament/competitive play this might be worth a note.

---

## RT-13.6 — INFO: R.IsValidSWA partner-adversarial issue (v0.5.17 trade-off, known)

**Confidence: HIGH (rule), MEDIUM (specific Hokm scenarios).**

The prompt's question 5: "validator treats partner adversarially, which may over-reject Hokm two-hand SWA. Per video #35 'ثق تماما انه خويك راح يجي دائما' (trust completely your partner). Find specific Hokm scenarios where the validator rejects what Saudi convention accepts."

**Code (Rules.lua line 471-500, the v0.5.17 design comment)**:

```lua
-- v0.5.17: Saudi-strict-strict SWA. The caller's claim must hold
-- REGARDLESS of which legal card any other seat (partner OR
-- opponent) plays. No "back-and-forth" cooperation with partner
-- — partner is treated adversarially in the recursion. Combined
-- with the per-trick `winner == callerSeat` check at line 366,
-- this enforces: the caller alone wins every remaining trick
-- under ANY legal play sequence. Partner may not over-take with
-- a higher card; if partner CAN over-take in any legal play,
-- the SWA fails.
--
-- Was (pre-v0.5.17): cooperative branch accepted "SOME partner
-- play leads to a win" — partner could optimally duck low to
-- preserve caller's eventual win. Per the user's reported
-- expectation ("no back-and-forth with teammate"), that's too
-- permissive. This release tightens to "EVERY partner play
-- leads to a win", which is symmetric with the opponent branch.
```

**Specific over-rejection Hokm scenarios** (concrete examples per video #35 sub-rules and standard Saudi 2-hand SWA pattern):

**Scenario A — Two-hand SWA, partner holds void-and-trump** (#35 line 2814-2824 framing "trust your partner will come"):

```
Hokm contract, trump = ♠. Trick 1-6 played. Trick 7 about to start.
  Caller (seat 1, me):  A♥ K♥ Q♥ J♥           (4 cards, all hearts)
  Partner (seat 3):     ♠2 ♠3 ♠4 ♠5             (all trump, void in hearts)
  Opp (seat 2):         ♥10 ♥9 ♥8 ♥7            (all hearts)
  Opp (seat 4):         ♣10 ♥6 ♥5 ♣4 — wait, only 4 cards each, ok:
  Opp (seat 4):         ♣10 ♣9 ♣8 ♣7            (4 clubs, void in hearts and trump)

Caller's claim: "I win all 4 remaining tricks."

Saudi convention (#35): VALID. Caller leads A♥, K♥, Q♥, J♥ in
sequence. Each trick: opp 2 must follow hearts (legal). Partner
is void in hearts (per Saudi rule must trump or discard); under
Hokm rule "must trump if void and have trump" — partner MUST trump.
So partner trumps each trick. But partner trumping STEALS caller's
trick — caller's hearts lose to partner's spades.

Wait — Saudi rule on partner over-trumping: partner must trump if void
AND opponent already trumped. If opp didn't trump, partner can pitch
(sluff). Specifically: partner is FREE to discard a non-trump if no
opp has trumped. Saudi convention says partner WILL pitch (not steal),
because partner is cooperating.

So:
  Trick 7: caller leads A♥. Opp2 plays ♥10 (must follow). Partner is
           void; could trump but Saudi convention says partner pitches
           ♠2 (low trump). Wait — partner has only trump cards!
           Partner's hand is all spades. So partner MUST play a spade.
           Spade is trump. Partner ruffs.
  Result: partner's ♠2 beats caller's A♥. Caller loses the trick.

Hmm, this scenario doesn't work as-stated. Let me reconstruct.

Better scenario — the canonical "two-hand SWA":
  Caller (me):    A♥ K♥                       (2 cards, both winners
                                                in suit but I'm void in
                                                trump after trick 6)
  Partner:        A♠ K♠                       (2 trump aces)
  Opp 2:          Q♥ ♣2                       (1 heart, 1 club)
  Opp 4:          ♣10 ♥7                      (1 club, 1 heart)

Trick 7 (caller leads):
  Caller: A♥ → wins (Q♥ from opp 2, ♣10 from opp 4 sluff,
                       partner sluffs ♣ not relevant — actually partner
                       has only trumps, must follow spades... ah but
                       lead is hearts, partner is void, partner must
                       trump if has trump. Partner has trump.
                       Partner ruffs A♥ with K♠.
                       Result: partner steals caller's A♥.)

Saudi rule per #35: this is exactly the "trust partner" situation.
"ثق تماما انه خويك راح يجي دائما" — trust your partner will come.
The Saudi reading: partner WILL play their lower trump (or sluff if
allowed). Convention dictates partner ducks.

But Saudi RULES (R.IsLegalPlay) say: "void in lead suit → must trump if
have trump". Partner has only trumps; partner MUST play trump. The
Saudi CONVENTION (cooperate) overrides the strict rule? No — convention
doesn't override legality. The minimum-trump rule says partner must
play LEAST trump if they're forced to ruff. Wait — Saudi rule on
forced-ruff-rank: must overruff if possible? Per saudi-rules.md:
"must trump if void AND opponents trumped; if no opp trumped, free
to pitch only if no trump remaining (but must trump otherwise)".

So in the canonical Saudi 2-hand SWA, the partner-with-only-trumps
MUST RUFF caller's heart Ace (legal Saudi play). Partner's lowest
trump (e.g. ♠2) wins the trick. The trick ends with PARTNER as
winner — not caller. R.IsValidSWA correctly rejects this because
partner-wins-trick ≠ caller-wins-trick (per line 400 `winner !=
callerSeat → return false`).
```

**The conclusion**: per Saudi rules (forced-ruff legality), the canonical "trust partner" 2-hand SWA only works if partner can LEGALLY duck. If partner has only trumps (forced ruff) or has the higher trump in the suit caller is leading, partner's trump CAN steal the trick — and R.IsValidSWA correctly rejects per the ScoreRound semantic of "winner = whoever's card has highest rank".

**The actual Saudi exception per #35 line 2814** ("trust partner") applies in scenarios where:

1. Partner has the second-highest unplayed card of caller's lead suit (and partner CAN legally duck a low card).
2. Partner is void of caller's lead suit AND can legally pitch (no forced-ruff).

**In Hokm with no trump cards mid-flight**: partner CAN duck. Example:

```
Hokm trump=♠. Trick 7 about to start.
  Caller:  A♥ A♦                  (2 winners in side suits)
  Partner: K♥ K♦                  (2 second-best, no trump)
  Opp 2:   Q♥ ♣2                   (one of caller's suit + side suit)
  Opp 4:   ♣10 ♦Q                  (one of caller's suit + side suit)

Trick 7: caller A♥. Opp2 Q♥ (must follow). Partner K♥ (must follow,
        Saudi rule: must follow suit and BEAT if can — wait, NO,
        Saudi rule DOES require beating-if-possible? Per R.IsLegalPlay,
        the must-overcut rule is for when partner-following-suit and
        opp HAS BEATEN their team. Partner-of-leader is the team that
        currently leads; partner doesn't need to overcut their own
        partner. Standard Belote/Baloot: partner MAY undercut.)

So partner plays K♥ (must follow ♥, may play any heart, picks K♥).
Caller's A♥ > K♥ → caller wins. ✓

Trick 8: caller leads A♦. Opp2 sluffs (no diamonds → must
        follow if has, sluff if void; opp2 has ♣2, void in ♦,
        sluffs ♣2). Partner ducks K♦ (or plays K♦). Opp4 Q♦
        follows. A♦ > K♦ > Q♦. Caller wins. ✓
```

**In this scenario R.IsValidSWA's adversarial recursion considers EVERY legal play of partner**. Partner's options on trick 7 following A♥ in hearts: K♥. Only one card legal (K♥ — partner has K♥ and K♦, must follow ♥, only K♥ matches). Wait, if partner has K♥ AND no other heart, must play K♥. ✓ R.IsValidSWA correctly accepts. So this is NOT over-rejected.

**The OVER-REJECTION scenario** (where R.IsValidSWA fails but Saudi convention says VALID):

```
Hokm trump=♠. Trick 7.
  Caller:  A♥ Q♥                    (2 hearts, A high, Q low)
  Partner: K♥ J♥                    (2 hearts, second-high, third-high)
  Opp 2:   10♥ ♣2                    (1 heart + side suit)
  Opp 4:   9♥ ♦Q                     (1 heart + side suit)

Trick 7: caller A♥. Opp2 10♥. Partner has K♥ AND J♥ — choice. Opp4 9♥.
  Partner picks K♥ → caller A♥ wins. ✓
  Partner picks J♥ → caller A♥ wins. ✓
  Either way trick 7 won by caller.

Trick 8: caller Q♥. Opp2 sluff or follow? Has only ♣2, void → must follow
  Saudi rule: void → must follow if has, else trump if void+trump, else
  sluff. Opp2 plays ♣2 (sluff).
  Partner plays remaining ♥ (K♥ or J♥, whichever didn't go in trick 7).
  Opp4 plays remaining (♦Q sluff).
  Partner's K♥ or J♥ vs caller's Q♥:
    If partner has K♥ remaining → K♥ > Q♥ → PARTNER wins, not caller.
    If partner has J♥ remaining → J♥ > Q♥ — wait, J♥ < Q♥? Hmm,
    in Hokm side-suit ranking is A > K > Q > J > 10 > 9 > 8 > 7 (NOT
    the trump ranking which is J highest). So Q♥ > J♥.
    If partner has J♥ remaining → caller Q♥ wins. ✓

  Adversarial recursion: partner's two legal choices in trick 7 lead
  to different outcomes in trick 8.
    Branch 1: partner plays K♥ in trick 7 (kept J♥ for trick 8)
      Trick 8: caller Q♥ wins (Q♥ > J♥ partner > others).  ✓
    Branch 2: partner plays J♥ in trick 7 (kept K♥ for trick 8)
      Trick 8: K♥ partner > Q♥ caller → PARTNER wins.        ✗

  Adversarial-partner means R.IsValidSWA must succeed on BOTH branches.
  Branch 2 fails → R.IsValidSWA returns FALSE.

Saudi convention per #35 line 2814: "trust your partner — they will
play correctly". The cooperative reading: partner picks Branch 1 (J♥
first, K♥ later... wait, that's also Branch 2 of trick 7). Let me
re-do this.

  Partner picks J♥ in trick 7 → keeps K♥ for trick 8 → K♥ steals.   ✗
  Partner picks K♥ in trick 7 → keeps J♥ for trick 8 → caller Q♥ wins.  ✓

Saudi convention: partner WILL pick K♥ in trick 7 (ducking the high
into caller's already-winning trick) so that J♥ remains in their hand
for trick 8 where caller's Q♥ tops it. This is the "trust partner"
Hokm 2-hand SWA pattern.

R.IsValidSWA: rejects because Branch where partner plays J♥ in trick 7
fails. ✗ Saudi-strict over-rejection.
```

**This is the canonical scenario where v0.5.17's strictness over-rejects vs. video #35's "trust partner" framing.**

**Confirmed**: the v0.5.17 design comment at Rules.lua line 487-493 explicitly accepts this trade-off. The R3 reaudit's MEDIUM caveat at line 109 calls this out. **No new finding here**, just concrete example.

**Recommendation (already on backlog)**: relax to "partner plays adversarially-but-allows-mandated-cooperation" if Hokm 2-hand SWAs are observed to fail too often. Per #35 the Saudi reading is more permissive than v0.5.17's adversarial recursion.

---

## RT-13.7 — LOW: /reload mid-SWA — re-arm restarts with fresh 5s window (NOT continuation)

**Confidence: HIGH.**

The prompt's question 6: "caller /reloads while SWA permission is pending. v0.9.0 M2 added re-arm. Verify the timer state survives correctly (5s window restarts? continues from where it was?)."

**Code (WHEREDNGN.lua line 270-292)**:

```lua
if B.State.s.swaRequest and B.State.s.swaRequest.caller
   and B.State.s.phase == K.PHASE_PLAY then
    -- Reset SWA request ts and arm a fresh auto-resolve
    -- timer. The 5s clock restarts so opponents see a
    -- full window post-reload.
    local req = B.State.s.swaRequest
    req.ts = (GetTime and GetTime()) or req.ts
    if C_Timer and C_Timer.After then
        C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
            if not B.State.s.isHost then return end
            if not B.State.s.swaRequest then return end
            if B.State.s.swaRequest.caller ~= req.caller then return end
            if B.State.s.phase ~= K.PHASE_PLAY then return end
            if B.State.s.paused then return end
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

**Verdict: 5s window RESTARTS. NOT continuation.**

The comment is explicit: "The 5s clock restarts so opponents see a full window post-reload." `req.ts` is reset to current `GetTime()` (line 276), and the C_Timer fires `K.SWA_TIMEOUT_SEC` seconds later.

**Is this Saudi-correct?** No Saudi rule applies — there's no /reload concept. From a UX standpoint: the restart is reasonable because the reloading host's network state was just rebuilt, and a fresh window prevents a too-short race where the timer fires immediately on reload-completion.

**Exploit potential**: A malicious host could repeatedly /reload to **infinitely extend** the SWA window. Practical risk LOW — the malicious host is a human who'd notice the soft-lock; opponents can still Takweesh. But theoretically possible.

**Sub-finding (RT-13.7-A, NEW, LOW)**: this restart logic does NOT preserve the **bot-fired SWA case** correctly. If the host /reloads during a paused bot-fired SWA window, WHEREDNGN.lua line 270-292 fires a fresh timer (good). But the original bot-fire timer at MaybeRunBot's site (line 4059) is gone forever (process restart). So the SWA gets exactly ONE re-arm post-reload — not the same bug as F-2 (no pause re-arm at all), but worth noting.

**Sub-finding (RT-13.7-B, NEW, LOW)**: the re-arm at WHEREDNGN.lua line 281 captures `req.caller` via closure but compares `B.State.s.swaRequest.caller ~= req.caller`. If a NEW SWA from a different caller fires after restore but before the re-arm timer fires, the re-arm would return early (correct: doesn't clobber the new SWA's resolve path). ✓

**Sub-finding (RT-13.7-C, NEW, LOW)**: WHEREDNGN.lua line 283 has a bare `if B.State.s.paused then return end` early-exit (no re-arm). Same flaw as MaybeRunBot's bot-fired path. RT-13.4-A.

---

## RT-13.8 — INFO: Cross-character session — localName resolves before SWA window (audit #54 fix)

**Confidence: MEDIUM (didn't deeply trace audit #54).**

The prompt's question 7: "localName resolves before the SWA window? Per audit #54 fix."

**Code (WHEREDNGN.lua line 87-88, 144-145, 308)**:

```lua
B.State.SetLocalName(GetUnitName("player", true))    -- line 87 (init)
...
B.State.SetLocalName(GetUnitName("player", true))    -- line 145 (post-RestoreSession)
...
B.State.SetLocalName(GetUnitName("player", true))    -- line 308 (PLAYER_ENTERING_WORLD)
```

`localName` is set at three points: PLAYER_LOGIN init (line 87), post-RestoreSession (line 145), and PLAYER_ENTERING_WORLD (line 308). The PLAYER_ENTERING_WORLD path is critical — realm info may not be ready at PLAYER_LOGIN per the comment at line 306-307.

**Pre-/reload flow**:

1. Player /reloads.
2. PLAYER_LOGIN fires → init() → SetLocalName (may have stale realm).
3. RestoreSession kicks in → SWA timer re-arm at line 270-292.
4. PLAYER_ENTERING_WORLD fires → SetLocalName (correct realm now).

If a SWA-related message arrives between steps 2 and 4, `fromSelf(sender)` (Net.lua line 650) compares against the possibly-stale `localName`. Cross-realm: stale could be "Player" without "-Realm", live message has "Player-Realm" → fromSelf returns false → message would be processed as if remote.

**Practical consequence for SWA**: if the host /reloads with a pending swaRequest (own caller), the post-reload SWA timer at WHEREDNGN.lua line 286-289 calls `HostResolveSWA(req.caller, ...)` where `req.caller` is a SEAT NUMBER, not a name. Seats are network-stable. ✓ No localName dependency in the SWA timer body.

**However**, `_OnSWAResp` (Net.lua line 2735-2807) DOES use `fromSelf` (line 2739) and `authorizeSeat` (line 2740). If a delayed MSG_SWA_RESP arrives during the brief pre-PLAYER_ENTERING_WORLD window, `fromSelf` may misclassify it. Most likely outcome: the message is treated as remote, runs through `authorizeSeat`, which `normSender`s (Net.lua line 664) — and `normSender` uses `S.NormalizeName` (State.lua line 549-556), which appends realm suffix even if it wasn't there. So in the cross-realm case, both stored seat name and incoming sender are normalized, and matching works. ✓

**Verdict**: localName issues from cross-character sessions are MITIGATED by the normSender / NormalizeName helpers used throughout. The `fromSelf` early-return is one site that could misclassify, but the practical impact is limited — at worst a self-loopback would be processed twice (once locally, once via the message path), and both paths apply identical state mutations. Idempotent.

**Sub-finding (RT-13.8-A, NEW, INFO)**: the audit #54 fix referenced in the prompt likely refers to the `S.NormalizeName` chain that runs through `normSender` at every fromSelf/fromHost/authorizeSeat site. This pattern is broadly correct now.

---

## RT-13.9 — LOW: Wire-frame race — malformed MSG_SWA_REQ from stale (pre-v0.10.0) client

**Confidence: HIGH.**

The prompt's question 8: "malformed MSG_SWA_REQ from a stale client (pre-v0.10.0 timer behavior) — is the new logic robust?"

**Wire format**: `K.MSG_SWA_REQ;seat;encodedHand` (Net.lua line 2521 / 4049). Three fields. A pre-v0.10.0 client might send a 2-field version without `encodedHand`, or with an extra field, or with non-numeric seat.

**Code (Net.lua line 2640-2670, `N._OnSWAReq`)**:

```lua
function N._OnSWAReq(sender, seat, encodedHand)
    if fromSelf(sender) then return end
    if not seat or seat < 1 or seat > 4 then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not authorizeSeat(seat, sender) then return end
    if WHEREDNGNDB and WHEREDNGNDB.allowSWA == false then return end
    if S.s.swaRequest and S.s.swaRequest.caller then
        return
    end
    S.s.swaRequest = {
        caller    = seat,
        handCount = (encodedHand and (#encodedHand / 2)) or 0,
        responses = {},
        encodedHand = encodedHand,
        ts        = (GetTime and GetTime()) or 0,
        windowSec = K.SWA_TIMEOUT_SEC or 5,
    }
```

**Robustness checks**:

- Line 2641: `fromSelf` drops self-loopback.
- Line 2642: `seat < 1 or seat > 4` rejects garbage. **NOTE: doesn't reject non-integer seat (e.g. seat=2.5 passes).** Mild.
- Line 2643: phase guard.
- Line 2644: `authorizeSeat` rejects mismatched sender (a peer pretending to be another seat).
- Line 2645: tournament-mode opt-out.
- Line 2653-2655: pending-overwrite guard.

**`encodedHand` handling**:

- Line 2665: `(encodedHand and (#encodedHand / 2)) or 0` — if encodedHand is nil, handCount = 0. Doesn't error.
- Line 2667: stored as-is.
- Line 2711: `(encodedHand and C.DecodeHand(encodedHand)) or {}` — same nil-guard. Doesn't error.

If a malformed pre-v0.10.0 client sends MSG_SWA_REQ with a 0-card encodedHand or without it, the handCount stored is 0 → resolved at the timer with a 0-card hand. R.IsValidSWA receives `hands[caller] = {}`. Per Rules.lua line 418-420 (caller-empty short-circuit), it returns true ONLY when `#plays == 0`. So an empty-hand SWA between tricks → R.IsValidSWA returns true → valid SWA branch → caller's team gets remaining trick points.

**BUT — Net.lua line 2906-2916 has a defensive override**:

```lua
-- Re-audit W7 fix: reject claims with no cards in caller's hand
-- AND no in-flight plays. R.IsValidSWA's caller-empty short-
-- circuit returns true in that case (legitimate when reached
-- recursively at end-of-claim) but at top-level entry it's a
-- corrupted-state signature — meaningless claim.
local valid
if (#(hands[callerSeat] or {})) == 0 and #trickPlays == 0 then
    valid = false
else
    valid = R.IsValidSWA(callerSeat, hands, c, trickState)
end
```

**Verdict**: a malformed pre-v0.10.0 frame with empty encodedHand → `hands[caller] = {}` (since `S.s.hostHands[seat]` would be authoritative if available; if not, falls back to empty wire hand) → at the W7 check, valid = false → invalid branch → Qaid penalty against the malformed-frame caller. ✓

**Defensive line: `S.s.hostHands[callerSeat]`**: Net.lua line 2878 prefers the host's authoritative record. So even if a pre-v0.10.0 client sends a manipulated encodedHand, the host validates against its own record. Spoofing-resistant. ✓ (Already documented at the 9th-audit fix comment.)

**Recommendation**: integer-validate `seat` (current `seat < 1 or seat > 4` admits seat=2.5). Net.lua line 2642 / 2811. Mild defense-in-depth. Other validators already use `tonumber(...)` parse paths, so the pre-validation at the dispatch layer might already coerce; not deeply traced.

**Verdict**: pre-v0.10.0 MSG_SWA_REQ frames are robust against the new logic. ✓

---

## RT-13.10 — INFO: F-1 confirmed — UI has no hand-count gate; user can fire 8-card SWA

**Confidence: HIGH (already in C-Xref-01 F-1).**

This is RT-13.10 mostly for completeness with the prompt's "5+ card permission gate" question.

The UI button at UI.lua:1997-2030 has no hand-count check. A human can press SWA at any cards-remaining count. The bot equivalent (Bot.lua:3866-3871) gates at `#hand <= 4`. Asymmetric; humans can shoot themselves.

**Practical exploit**: a malicious-or-naive caller fires 8-card SWA on a table with 3 bot opponents (impossible, but say 1 human + 2 bots vs 1 partner). The 2 opp bots auto-accept. The 1 human opp must explicitly deny within 5s. If they fail, the timer fires, R.IsValidSWA almost-certainly returns false, Qaid penalty applies AGAINST THE CALLER. The caller chose this; not really an exploit. **Self-grief, not adversarial-grief.**

**Saudi-rule reading**: per #35 the rule is "at 5+ cards, opponent MUST explicitly grant permission". Code's auto-approve violates this (RT-13.1 already covers it). But the UI letting the user PRESS SWA at 5+ is itself just a UI choice — Saudi rule doesn't forbid PRESSING, it forbids the silent-permit response.

---

## RT-13.11 — LOW: HostResolveSWA missing explicit pause guard (cross-cut from C-Xref-01)

**Confidence: HIGH.**

`HostResolveSWA` (Net.lua line 2862-3073) checks `S.s.phase ~= K.PHASE_PLAY` at line 2864 but **does NOT check `S.s.paused`**.

**Reachable paths**:

1. **From timers**: all four timer sites check `S.s.paused` first → never reach a paused HostResolveSWA via timer. ✓
2. **From `_OnSWAResp` accept-path** (line 2800-2806): when both opponents accept, calls HostResolveSWA. **No pause check.**
3. **From direct ≤3-card path** (line 2585): dead code if `WHEREDNGNDB.swaRequiresPermission` default holds.

**Race**: caller pauses while opponent #1's accept is in flight. Pause arrives → `S.s.paused = true`. Opponent #1's accept arrives → `_OnSWAResp` runs, sets `req.responses[opp1] = true`. Opponent #2's accept arrives → `_OnSWAResp` runs, both opps now accepted, calls `HostResolveSWA(caller, hand)`.

**`HostResolveSWA` runs while `S.s.paused == true`**.

Practical consequence: round resolves mid-pause. The user pauseed THINKING they could veto; the SWA resolves anyway. Mild rule-violation surface — Saudi convention has no pause concept. Code behavior is "pause is best-effort UX, cannot block already-consented actions".

**Recommendation**: add `if S.s.paused then return end` at HostResolveSWA line 2864. Or better: add it in `_OnSWAResp` line 2800 before the accepts >= 2 check, which would defer the resolution until unpause.

---

## Cross-cutting summary

| ID | Severity | Question | Verdict | Recommendation |
|---|---|---|---|---|
| RT-13.1 | **CRITICAL (rule)** | Q2 (5+-card auto-approve) | Saudi rule inverted by silent-consent semantics | Branch on hand-count: ≥5 = explicit-accept-only OR timeout-deny |
| RT-13.2 | MEDIUM | Q1 (mid-permission race) | Deterministic per-host, robust to deny/timer/Takweesh ordering | None (correct) |
| RT-13.3 | (= RT-13.1) | Q2 | Same as RT-13.1 | Same |
| RT-13.4 | MEDIUM | Q3 (pause+SWA) | Bot-fired path drops on pause (F-2 confirmed); /reload re-arm has same flaw | Copy LocalSWA's pause-re-arm to bot path AND PLAYER_LOGIN restore |
| RT-13.5 | LOW | Q4 (Takweesh during SWA) | Takweesh correctly clears swaRequest; Qaid math correct | None (correct) |
| RT-13.6 | INFO | Q5 (R.IsValidSWA partner-adversarial) | v0.5.17 known trade-off; concrete Hokm Q♥/J♥ scenario over-rejected | Already on backlog as v0.10.x candidate |
| RT-13.7 | LOW | Q6 (/reload mid-SWA) | 5s window RESTARTS (correct); minor closure capture quirks | None |
| RT-13.8 | INFO | Q7 (cross-character session localName) | Mitigated by NormalizeName chain | None |
| RT-13.9 | LOW | Q8 (malformed pre-v0.10.0 wire) | Defended by W7 + hostHands authoritative | Tighten seat integer check |
| RT-13.10 | (= F-1) | Bonus | UI no hand-count gate (cross-cut) | Mirror Bot's `#hand <= 4` OR document |
| RT-13.11 | LOW | Bonus (cross-cut from C-Xref-01) | HostResolveSWA missing pause guard | Add `if S.s.paused then return end` at line 2864 |

---

## Confidence

**HIGH** on:

- RT-13.1 (5+-card auto-approve violates Saudi rule — sourced verbatim to #35 lines 2244, 2404, 2414).
- RT-13.2 (race ordering — code flows verified against per-handler pause/phase/req-nil guards).
- RT-13.4 (F-2 confirmed; verified bot-fired timer is missing the re-arm block present in LocalSWA's timer).
- RT-13.5 (Takweesh resolution path verified end-to-end).
- RT-13.7 (re-arm restarts the 5s clock; comment is explicit).
- RT-13.9 (W7 fix + hostHands authoritative wires up correct defense).

**MEDIUM** on:

- RT-13.6 (concrete Q♥/J♥ scenario is illustrative; real-world Hokm 2-hand SWA frequency in casual Saudi play not deeply traced).
- RT-13.8 (audit #54 referenced but not deeply traced; localName flow likely OK based on NormalizeName helpers).
- RT-13.11 (HostResolveSWA pause-gate gap — practical impact is one resolved-mid-pause SWA; not deeply tested).

**LOW** on:

- RT-13.7 sub-findings (A/B/C — closure-capture quirks; hardly exploitable but architecturally worth noting).

---

## Files cross-referenced

- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 640-678 (sender helpers normSender/fromHost/fromSelf/authorizeSeat), 2127-2287 (HostResolveTakweesh), 2473-2586 (LocalSWA), 2590-2638 (LocalSWAResp), 2640-2733 (_OnSWAReq), 2735-2807 (_OnSWAResp), 2809-2827 (_OnSWA), 2862-3073 (HostResolveSWA), 4040-4075 (MaybeRunBot bot-SWA dispatch).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 383-501 (R.IsValidSWA, including v0.5.17 design comment 471-493).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — lines 3854-3938 (Bot.PickSWA, including Hokm trump-safety gate).
- `C:\CLAUDE\WHEREDNGN\State.lua` — lines 110-126 (round-init clears), 191-248 (TRANSIENT_FIELDS — swaRequest NOT transient, line 225-230), 510-540 (ApplyResyncSnapshot wipes), 800-823 (ApplyStart clears).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — line 281 (`K.SWA_TIMEOUT_SEC = 5`).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — lines 75-89 (init + SetLocalName), 130-180 (PLAYER_LOGIN restore), 270-292 (PLAYER_LOGIN SWA re-arm), 305-313 (PLAYER_ENTERING_WORLD).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R3_swa.md` — full naming + mechanism reaudit (verbatim Saudi quotes lines 87-99).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-01_swa_pipeline.md` — F-1, F-2, F-3, F-4 cross-cut findings.
- `C:\CLAUDE\WHEREDNGN\CLAUDE.md` — lines 41-46 (post-R3 SWA section explicitly noting timer is addon-UX).
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\IMJIrhW4qOA_35_swa_term_detailed.ar-orig.srt` — verbatim source (lines 2204, 2244, 2404, 2414, 2814, 2944).
