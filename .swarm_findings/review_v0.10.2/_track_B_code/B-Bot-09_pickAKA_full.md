# B-Bot-09: Bot.PickAKA — full sender-side AKA decision audit

**Function:** `Bot.PickAKA(seat, leadCard)` — `Bot.lua:3261-3370`
**Caller:** `Net.lua:4096-4101` (`MaybeRunBot` lead path; `S.ApplyAKA` + `N.SendAKA` after card chosen)
**Inputs:** `seat` (the leader), `leadCard` (already-chosen lead card from `Bot.PickPlay`)
**Output:** non-trump suit string `"S"|"H"|"D"|"C"` to broadcast AKA on, or `nil` to skip.

The function is a **gate stack** — every gate that fires returns `nil`. The
"call AKA" outcome is the fall-through after all gates pass. Order matters
only for short-circuit cost; the gates are otherwise independent.

---

## Scope-by-scope audit

### 1. Hokm-only gate — **PASS**

**Code (Bot.lua:3263):**
```lua
if not S.s.contract or S.s.contract.type ~= K.BID_HOKM then return nil end
```

**Verdict:** Match — G18-02 / J-066. AKA is a Hokm-only convention; Sun/SWA
have no boss-suit signal because every plain rank is symmetric (no trump-
ruff to suppress). Defence-in-depth confirmed elsewhere (`N.LocalAKA`
Net.lua:2337, `N._OnAKA` Net.lua:3076, `UI:2037`, `S.LocalAKAcandidate`
State.lua:1345). **No finding.**

---

### 2. Largest-remaining check (boss of suit) — **PASS, with subtle edge**

**Code (Bot.lua:3290-3292):**
```lua
-- The lead card must be the highest UNPLAYED rank of its suit.
-- Otherwise the signal is false (we don't actually hold the boss).
if S.HighestUnplayedRank(su) ~= r then return nil end
```

**Verdict:** Strong. `S.HighestUnplayedRank` (State.lua:1326+) walks
`AKA_ORDER = {"A","T","K","Q","J","9","8","7"}` for non-trump, popping
played cards. Sender cannot announce AKA on a non-boss card — the false-
AKA-by-self-bug threat is closed at sender side.

**Edge — F1 [LOW / philosophical]: "boss of suit by rank only" misses non-trump
domination sub-cases.** `HighestUnplayedRank` returns the rank-wise highest
unplayed card ignoring suit-level cards still out. It does NOT verify that
the bot's lead card actually wins against opponent voids that may already
be exhausted. In practice this is fine because rank-AKA is the convention,
but the sub-rule "if the rank below is also exhausted in non-friend hands,
the next-down is bossless too" (G18-12 / G18-13 chain) is implicitly handled
via played-card pop. **No bug, just brittle if `AKA_ORDER` is ever changed.**

---

### 3. Lead-only gate — **PASS**

**Code (Bot.lua:3264):**
```lua
if not S.s.trick or #S.s.trick.plays > 0 then return nil end  -- lead only
```

**Verdict:** Match — G18-05. AKA is meaningful only when the bot is *about
to lead* (the partner-coordination signal arrives before the trick opens,
so partner can plan their follow). Calling AKA mid-trick or after winning
a trick is structurally meaningless. Hard gate. **No finding.**

---

### 4. Non-Ace gate (AKA on Ace = trivial / redundant) — **PASS**

**Code (Bot.lua:3289):**
```lua
if r == "A" then return nil end
```

**Verdict:** Match — G18-08 / S6-6. Bare-A lead in non-trump is the
*implicit AKA* case; receiver detects via `pickFollow` H-5 branch
(Bot.lua:2396-2426 confirmed in xref X2). Broadcasting MSG_AKA on top of
a bare-A lead is a free info-leak with zero added coordination value.
The receiver-side branch is wired; sender-side suppression is correct.

---

### 5. Partner-not-void-in-trump check — **PASS, with seat-perspective caveat**

**Code (Bot.lua:3313-3319):**
```lua
do
    local partner = R.Partner(seat)
    local pmem = Bot._memory and Bot._memory[partner]
    if pmem and pmem.void and pmem.void[trump] then
        return nil
    end
end
```

**Verdict:** Match — G18-09 partner-trump-void cell collapses to SKIP.
Once partner has shown void in trump (failed to follow trump lead), the
ruff-suppression value of AKA is zero — they couldn't ruff anyway —
while the info-leak cost remains. Suppress. Correct.

**F2 [LOW / behavioral]: `Bot._memory` is the single shared observer
ledger.** `pmem.void` is written by `Bot.OnPlayObserved` (Bot.lua:340-356)
when ANY seat (host-observed) fails to follow lead. This is a **global
truth flag**, not "what seat `seat` knows about partner's void." In a
mixed bot/human game where the bot at `seat` is reasoning about its
human partner, the void inference is correct (host sees all plays).
But the comment at Bot.lua:3309-3311 says "If partner is OBSERVED void
in trump" which matches reality. **No bug.** The caveat is that with
incomplete info models (e.g., a non-host bot ever calling PickAKA),
the ledger would be stale — but Bot decisions are host-only by gating
in `MaybeRunBot` (Net.lua:3552-3553).

---

### 6. v0.10.2 L3 doubled-contract conservatism — **PASS, but with B-Net-05 F12 timing-window gap**

**Code (Bot.lua:3332):**
```lua
if S.s.contract and S.s.contract.doubled then return nil end
```

**Verdict:** Implementation matches X2 B3 / G18-10 paragraph 2. Once the
round is doubled (Bel set on `S.s.contract.doubled = true` at State.lua:1077
via `S.ApplyDouble`), AKA is suppressed categorically.

**F3 [MED] — sender-side L3 gate does NOT retroactively retract a live AKA
banner if opp doubles AFTER the AKA was sent.** This is **B-Net-05 F12 /
D-RedTeam-01 E7** (cross-referenced confirmed). The exploit:

1. Bot at S1 leads non-trump, sends AKA on suit X (banner on, partner
   honors via pickFollow:2427).
2. Opp at S2 immediately doubles (Bel) the round.
3. **The L3 gate runs only on the next `Bot.PickAKA` call** — it does
   not consult `S.s.contract.doubled` to rescind the live banner.
4. Partner continues honoring AKA-relief; opp now has both the
   coordination read AND the ×2 multiplier. Net negative.

**Repro:** trick 1 lead-AKA → trick 2 opp Bel call → trick 2 partner
play decision. Partner reads `S.s.akaCalled.suit` not `s.contract.doubled`,
so AKA-relief still fires. Verified via cross-reference to
`B-Net-05_aka_wire.md:386-389` and `:433`.

**Severity MED:** behaviorally correct in 95% of cases (Bel-after-AKA is
rare in normal play). Skilled adversary exploit only.

**Fix sketch (do not apply per scope):** at `S.ApplyDouble` (State.lua:1077)
also clear `S.s.akaCalled = nil` if any banner is live, mirroring the
trick-end clear at State.lua:1284. Send a retraction wire frame too.

---

### 7. Late-game conservatism (Bot.lua:3350-3366) — **PASS**

**Code (Bot.lua:3350-3366):**
```lua
if trickNum >= 6 then
    -- Allow the late-round AKA when score-state is meaningful
    -- (close race, opp near-win, we near-clinch). Suppress when
    -- it's just a normal late-round info reveal.
    if S.s.cumulative then
        local myTeam = R.TeamOf(seat)
        local meCum = S.s.cumulative[myTeam] or 0
        local oppCum = S.s.cumulative[(myTeam == "A") and "B" or "A"] or 0
        local target = S.s.target or 152
        local clutch = (oppCum >= target - 25)  -- opp near-win
                       or (meCum >= target - 25)  -- we near-clinch
                       or (math.abs(oppCum - meCum) <= 20)  -- close race
        if not clutch then return nil end
    else
        return nil
    end
end
```

**Verdict:** Match — G18-10 paragraph 1 ("late-game ⇒ conservative") with
clutch override. Three OR'd clutch conditions cover the speaker's "decisive
round" carve-out. Cumulative-fallback default-suppress when score state is
unknown is conservative-correct.

**F4 [LOW / parameter tuning]: hard-coded thresholds (`target - 25`,
`|delta| <= 20`) are not tuned against any test data.** The values are
intuition-pegged; without playtest metrics we can't know if "clutch"
fires too rarely (suppresses legitimate signals) or too eagerly (leaks
info in pseudo-clutch). Same severity as B-Bot-01 F-* parameter findings.
Not blocking.

**F5 [LOW / over-filter]: trickNum >= 6 with no clutch → skip is INDEPENDENT
of partner-bot-status.** Already gated to bot-partner upstream (3278), so
this is fine — but if a future refactor moves the bot-partner gate AFTER
the late-game gate, the late-game branch would short-circuit before
checking partner type, giving inconsistent skip semantics. Cosmetic.

---

### 8. D-RT-04 F1 + D-RT-18 S1: BotMaster.PickPlay:830 path bypasses M4 — **NOT APPLICABLE to PickAKA itself, but cross-cuts**

**Question scope:** D-RT-04 F1 / D-RT-18 S1 / B-Net-05 (re-confirmed)
identify that `BotMaster.PickPlay:830` builds its own `legal` list via
`R.IsLegalPlay(c, hand, trick, S.s.contract, seat)` — **5 args, no
`S.s.akaCalled` 6th arg.** This is the AKA-receiver-relief blind spot in
ISMCTS-tier play.

**Relevance to Bot.PickAKA:** Bot.PickAKA is the **sender** decision; the
M4 issue affects the **receiver** legal-play layer. They are independent
gates. **However**, the M4 bypass amplifies the cost of any false-positive
AKA send by the sender:

1. Sender (Bot.PickAKA) broadcasts AKA on suit X.
2. Partner is Saudi Master tier on `BotMaster.PickPlay`.
3. Receiver-relief at Bot.lua:2427 wants partner to discard non-trump.
4. **`BotMaster.PickPlay:830` builds `legal` AKA-blind**, returns trump
   ruff as the highest-rolloutValue card.
5. Partner ruffs anyway, defeating the AKA primary purpose AND wasting
   the sender's signal-leak risk.

**Verdict — F6 [HIGH cross-track]: Bot.PickAKA's safety budget assumes a
working AKA-receiver-relief downstream.** The doubled-contract suppression,
late-game suppression, and bot-partner gate are all *information-leak
mitigations* — they assume the upside (partner correctly defers ruff)
materializes when the gate is opened. With S1 open at `BotMaster:830`,
**the upside is null for Saudi Master partners** — every AKA is pure leak.

The PickAKA function does NOT check the partner's bot tier (Advanced vs
M3lm vs Saudi Master). Adding such a check is the cleanest sender-side
mitigation until S1 is fixed at the BotMaster layer. The right fix is
upstream (B-Net-05 S1 / D-RT-18 S1) but a defensive PickAKA tier-aware
suppression is one-line.

**Repro:** see B-Net-05 §2 / D-RT-18 — Saudi-Master partner ruffs AKA'd
suit despite partner-winning + relief branch firing in Bot.lua:2427.

**Status:** OPEN, dependent on S1.

---

### 9. B-Net-05 F12: L3 sender-side only — **CONFIRMED in Bot.PickAKA scope**

Already covered in #6 above. The Bot.PickAKA function correctly implements
the L3 gate **for future calls within the same round**. It cannot
retroactively retract a live banner because:

- `S.s.akaCalled` is set by `S.ApplyAKA` (called by Net.lua:4099 after
  PickAKA returns the suit).
- `S.ApplyAKA` is cleared only at trick end (State.lua:1284) — there is
  no "round-event-driven" rescind hook.
- `S.ApplyDouble` (State.lua:1077) writes `s.contract.doubled = true` but
  does not touch `s.akaCalled`.

**Cross-ref:** `B-Net-05_aka_wire.md:386-389` ("F12 L3 doubled-contract
PASSES — Asymmetric timing window").

**Severity:** MED. Already counted in #6 — not double-counted as a separate
finding.

---

### 10. AKA risk-tolerance dispersal (per video #18 G18-10) — **NOT IMPLEMENTED**

G18-10 paragraph 1 (the source-G transcript line at
`docs/strategy/_transcripts/18_when_to_aka_extracted.md:62`) describes
**5 inputs to AKA risk tolerance**, paralleling the bidding/ashkal frameworks
from videos #25 and #31 (also referenced in the grep above):

1. **Cards in hand** — code reads via `S.s.hostHands[seat]`. Not directly
   consulted in PickAKA; the boss-rank check assumes any hand shape is OK.
2. **Personal risk tolerance** — bot personality dimension. No
   per-personality dispersal in PickAKA. All bots use the same gate stack
   regardless of `WHEREDNGNDB.fzlokyBots` etc.
3. **النشرة (cumulative score)** — partially implemented in the late-game
   gate (#7) via `S.s.cumulative` clutch detection.
4. **Prior bidding context** — NOT consulted. Whether the contract was won
   on a strong "hokm-with-hand" call vs a marginal "hokm-on-faranka" win
   does not modulate AKA risk. (Cross-ref B-Bot-02 hokmFaranka.)
5. **Seat position** — NOT consulted. Bidder vs partner-of-bidder vs opp
   vs opp-of-opp all behave identically.

**Verdict — F7 [LOW / philosophical]:** PickAKA is a **single-axis gate
stack**, not the **5-input weighted decision** the speaker describes for
the related Ashkal/Bid frameworks. The structure of the function makes
risk-tolerance dispersal awkward to bolt on without rearchitecting.

**Severity:** LOW. The speaker frames G18-10 as a "modifier," not a
strict gate; current behavior is "play it safe always" which is
defensible bot behavior even if not maximally Saudi-style. Listed for
completeness.

---

### 11. AKA-on-T NOT IMPLEMENTED (X2 B5 / B-Net-01 F-AP-21) — **CONFIRMED**

**Code:** `Rules.lua:34-59` (`R.CurrentTrickWinner`) and
`Rules.lua:89-184` (`R.IsLegalPlay`) do NOT consult `S.s.akaCalled`. The
"AKA on T substitutes for Ace" rule (J-067 part 1) has two halves:

- **Receiver-relief (J-067 part 2):** Honored by `pickFollow` Bot.lua:2427
  (heuristic only). Saudi Master tier breaks via D-RT-18 S1 (see #8).
- **Trick-lock semantics (J-067 part 1):** Opponent over-trumping the
  AKA'd T should be illegal (or at least the trick-winner computation
  should treat T as A). NOT IMPLEMENTED. `R.CurrentTrickWinner` resolves
  by trump-rank/lead-suit-rank with no AKA consultation.

**Relevance to Bot.PickAKA:** The sender broadcasts AKA on T (when A is
dead) — `S.HighestUnplayedRank` walks AKA_ORDER and returns "T" once "A"
is in `playedCardsThisRound`. Bot.PickAKA emits MSG_AKA on a T lead in
this case without warning that the trick-lock half is missing.

**Verdict — F8 [LOW]: PickAKA emits AKA-on-T trusting downstream lock that
doesn't exist.** The receiver-relief works (in 3 of 4 bot tiers, modulo
S1); the trick-lock does not. An over-trumping opp wins the AKA'd T
trick legally.

Cross-ref: `B-Bot-03_akaReceiver_m4live.md` F2,
`B-Net-01_onPlay_full.md:429` F-AP-21,
`xref_X2_aka.md` B5.

**Severity:** LOW. Bot.PickAKA's behavior is **internally consistent** —
it sends AKA on T when T is the boss. The downstream gap is in
`R.CurrentTrickWinner` and `R.IsLegalPlay`, not in PickAKA. PickAKA
correctly chose to emit; the wire/legality layer fails to enforce.
Listed here for completeness; the actual fix lives in Rules.lua.

---

### 12. Trick-1 categorical skip vs G18-10 "بدايه الجيم لسه عوافي" (v0.10.0 review B4) — **CONFIRMED PHILOSOPHICAL DIVERGENCE**

**Code (Bot.lua:3299-3304):**
```lua
-- Skip on the very first trick lead: at that point no opponent has
-- shown a void yet, so the signal isn't actionable for partner —
-- they have no reason to over-trump a fresh suit yet anyway.
-- AKA is most useful in the mid/late hand once voids are showing.
local trickNum = #(S.s.tricks or {}) + 1
if trickNum <= 1 then return nil end
```

**Verdict:** Code rationale is internally coherent (no voids → signal is
not actionable → suppress) but **inverts** the speaker's intent in G18-10.

The speaker says (transcript line, ≤15 words): "بدايه الجيم لسه عوافي"
("early in the game, you still have room"). Speaker's framing: early
game = **permissive** zone, take risks on uncertain bossness. Late game =
**strict** zone, only act on certainty.

Code's framing: trick 1 = **strict** zone (always skip). Trick 6+ = mostly
strict but with clutch override.

**The two frames disagree on the early-game half.** The discrepancy was
flagged in v0.10.0 review_v0.10.0/xref_X2_aka.md as B4 (severity: trivial /
philosophical). It remains in v0.10.2.

**Why the divergence is defensible:**
- Bot.PickAKA's "boss" check is **deterministic** (perfect played-card
  memory). The speaker's permissiveness is about **uncertain bossness**
  — relax the certainty requirement when stakes are low.
- The code has no "uncertain bossness" branch — `HighestUnplayedRank` is
  always definite. So the surface for the speaker's permissiveness rule
  to attach to does not exist.
- The trick-1 skip's stated reason (no voids shown) is a **separate**
  concern (signal actionability) and is correct on its own merits.

**Verdict — F9 [TRIVIAL / philosophical]:** The trick-1 skip is correct
for its stated reason. It happens to also conflict with G18-10's
spirit-of-the-rule but cannot be trivially aligned with the speaker
because the underlying "uncertain bossness" branch has no implementation.
**Not a bug.** Listed for traceability and to confirm the v0.10.0 B4
finding has not been addressed (and likely cannot be in current
architecture without major restructuring).

---

## Summary table

| # | Concern | Severity | Status | Cross-ref |
|---|---------|----------|--------|-----------|
| 1 | Hokm-only gate | — | PASS | G18-02 / J-066 |
| 2 | Largest-remaining (boss) | — | PASS (F1 LOW edge) | G18-04 |
| 3 | Lead-only gate | — | PASS | G18-05 |
| 4 | Non-Ace gate | — | PASS | G18-08 / S6-6 |
| 5 | Partner-not-void-in-trump | — | PASS (F2 LOW caveat) | G18-09 cell |
| 6 | L3 doubled-contract suppression | — | PASS (F3 MED — see #9) | X2 B3 / G18-10 ¶2 |
| 7 | Late-game conservatism | — | PASS (F4/F5 LOW) | G18-10 ¶1 |
| 8 | D-RT-18 S1 BotMaster:830 bypass | **HIGH** (cross-track) | OPEN — F6 | D-RT-18, B-Net-05 §2 |
| 9 | B-Net-05 F12 timing window | MED | OPEN — F3 (=#6) | B-Net-05:386 |
| 10 | Risk-tolerance dispersal | LOW / philosophical | F7 — not impl | G18-10 5-inputs |
| 11 | AKA-on-T trick-lock missing | LOW (downstream) | F8 — confirmed | X2 B5 / F-AP-21 |
| 12 | Trick-1 skip vs G18-10 spirit | TRIVIAL | F9 — confirmed v0.10.0 B4 | X2 B4 |

---

## Findings (per-finding format)

### F1 [LOW / cosmetic]: HighestUnplayedRank brittle to AKA_ORDER changes

- **Severity:** LOW
- **Repro:** N/A — cosmetic / future-proofing concern only.
- **Quote (Bot.lua:3290-3292):**
  ```lua
  -- The lead card must be the highest UNPLAYED rank of its suit.
  -- Otherwise the signal is false (we don't actually hold the boss).
  if S.HighestUnplayedRank(su) ~= r then return nil end
  ```
- **Detail:** Sender-side false-AKA prevention works correctly. If
  `AKA_ORDER` (State.lua:1326) is ever extended (e.g., to add joker
  ranks), the rank-string equality check would silently break.
  Acceptable as-is.

### F2 [LOW / behavioral caveat]: pmem.void perspective

- **Severity:** LOW
- **Repro:** Non-host bot calling PickAKA — would read stale ledger.
  In current code path bots are host-only via Net.lua:3552-3553;
  no live exposure.
- **Quote (Bot.lua:3313-3319):** see scope #5.
- **Detail:** Comment says "OBSERVED void" matches reality (host-side
  ledger). Latent risk only if non-host bot dispatch is ever added.

### F3 [MED]: L3 doubled gate is sender-side only — no live banner retraction

- **Severity:** MED
- **Repro:**
  1. Trick 1: Seat 1 (bot, partnered with seat 3) leads K of clubs (A
     dead). PickAKA fires, broadcasts AKA on clubs. `S.s.akaCalled =
     {seat=1, suit="C"}`.
  2. Trick 2: Seat 2 (opp human) calls Bel after seeing the AKA banner.
     `S.s.contract.doubled = true` via `S.ApplyDouble` State.lua:1077.
  3. Trick 2: Seat 3 (partner bot) needs to follow. `pickFollow` AKA-
     receiver branch at Bot.lua:2427 reads `S.s.akaCalled.suit == "C"`
     and `partnerWinning` — fires receiver-relief, partner does not
     ruff.
  4. Net effect: opp got both the coordination read (seat 1 holds boss
     of clubs) AND the ×2 multiplier on the round.
- **Quote (Bot.lua:3332):**
  ```lua
  if S.s.contract and S.s.contract.doubled then return nil end
  ```
- **Detail:** Gate is correct for **future** calls. State.lua:1077
  (`S.ApplyDouble`) does NOT clear `s.akaCalled`; only trick-end clears
  it (State.lua:1284). No retraction wire frame exists. Cross-ref
  B-Net-05 F12 / D-RedTeam-01 E7.

### F4 [LOW]: Late-game thresholds are hard-coded, untuned

- **Severity:** LOW
- **Repro:** Set up a contrived end-game where score diff = 21 (just
  outside `|delta| <= 20` clutch). Late-game AKA suppressed even though
  the round materially affects match. Or: opp at 126 (target=152, so
  126 < 127 = target-25) → not clutch by `oppCum >= target - 25`. AKA
  suppressed even though opp is one round from match victory.
- **Quote (Bot.lua:3354-3361):**
  ```lua
  local clutch = (oppCum >= target - 25)
                 or (meCum >= target - 25)
                 or (math.abs(oppCum - meCum) <= 20)
  ```
- **Detail:** Hand-tuned thresholds. No test pin or empirical basis.

### F5 [LOW / cosmetic]: Late-game gate ordering is fragile to refactor

- **Severity:** LOW
- **Repro:** N/A — refactoring concern.
- **Detail:** Bot-partner gate (3278) is upstream of late-game gate
  (3350). If a future refactor moves them, late-game's `return nil`
  could fire before the human-partner check, yielding inconsistent
  skip semantics. Add a comment lock-in.

### F6 [HIGH cross-track]: PickAKA does not check partner's bot tier

- **Severity:** HIGH (because compounded with D-RT-18 S1 OPEN)
- **Repro:**
  1. Saudi Master enabled (`WHEREDNGNDB.saudiMasterBots = true`).
  2. Bot at S1 (Advanced or higher) calls PickAKA → emits AKA on suit X.
  3. Partner at S3 is Saudi Master → uses BotMaster.PickPlay.
  4. BotMaster:830 builds `legal` via `R.IsLegalPlay(c, hand, trick,
     S.s.contract, seat)` — 5 args, no `S.s.akaCalled` 6th arg.
  5. Partner ruffs the AKA'd suit despite the receiver-relief branch
     at Bot.lua:2427 wanting them to discard.
  6. Net: AKA leak with no upside.
- **Quote (Bot.lua:3263-3370 collectively):** PickAKA never reads
  `WHEREDNGNDB.saudiMasterBots`, `BM.IsActive()`, or any partner-tier
  flag.
- **Detail:** Cross-ref D-RT-18 S1, B-Net-05 §2. PickAKA's gate stack
  assumes the receiver-relief downstream works. With S1 open, the
  Saudi Master receiver path is AKA-blind. Defensive sender-side fix
  is one line: skip if `BM.IsActive()` and partner is Saudi Master.
  Cleaner fix is upstream at BotMaster:830.

### F7 [LOW / philosophical]: 5-input dispersal not implemented

- **Severity:** LOW
- **Repro:** N/A — design philosophy.
- **Detail:** G18-10 frames AKA risk as a 5-input modifier (cards / risk
  tolerance / cumulative / prior bid / seat). PickAKA implements:
  - cumulative: partial (#7 clutch detection)
  - others: not consulted
  PickAKA is a single-axis gate stack; the speaker's framework would
  require restructuring to a weighted-score model.

### F8 [LOW]: AKA-on-T sent without downstream trick-lock support

- **Severity:** LOW (downstream gap, not PickAKA bug)
- **Repro:**
  1. A of clubs played and dead.
  2. Bot at S1 holds T of clubs as boss → leads it.
  3. PickAKA fires (HighestUnplayedRank("C") == "T"), emits MSG_AKA.
  4. Opp at S2 ruffs with Jack of trump.
  5. R.CurrentTrickWinner → trump rank > non-trump rank → opp wins.
  6. AKA-on-T "lock" semantic (J-067 part 1) was never enforced.
- **Quote (Bot.lua:3290-3292) + Rules.lua:34-59 (absence):** PickAKA
  correctly identifies T as boss. Rules.lua never reads
  `S.s.akaCalled` for trick-winner computation.
- **Detail:** Cross-ref B-Bot-03 F2, B-Net-01 F-AP-21, X2 B5. The PickAKA
  function is internally correct. The fix lives in Rules.lua trick-
  winner / legal-play layer, not here. Listed for traceability.

### F9 [TRIVIAL / philosophical]: Trick-1 skip inverts G18-10 spirit

- **Severity:** TRIVIAL
- **Repro:** N/A — interpretive.
- **Quote (Bot.lua:3299-3304):**
  ```lua
  local trickNum = #(S.s.tricks or {}) + 1
  if trickNum <= 1 then return nil end
  ```
- **Detail:** G18-10 says "early game is the permissive zone." Code's
  trick-1 skip is the strictest zone. Code's stated reason (no voids
  shown → signal not actionable) is correct on its own merits. The
  philosophical conflict cannot be resolved without an "uncertain
  bossness" branch which the architecture lacks. Carryover from
  v0.10.0 B4. **Not a bug.**

---

## Confidence

**HIGH** — gates 1, 2, 3, 4, 5, 7 verified by direct code read + code
quote + cross-ref to xref_X2_aka.md and the v0.10.0 review.

**HIGH** — F3 (L3 timing window) cross-confirmed in B-Net-05_aka_wire.md
F12 / D-RedTeam-01 E7.

**HIGH** — F6 (BotMaster:830 bypass) cross-confirmed in B-Net-05 §2 and
D-RT-18 S1 (the "single highest-impact finding" in B-Net-05).

**HIGH** — F8 (AKA-on-T trick lock) cross-confirmed in B-Bot-03 F2,
B-Net-01 F-AP-21, X2 B5.

**MEDIUM** — F4 threshold tuning. Not empirically validated; based on
inspection only.

**LOW** — F7 (5-input dispersal) is interpretive; the speaker's "5
inputs" framing comes from videos #25 and #31 (Bid / Ashkal), not video
#18 directly. Mapping it to AKA is by analogy.

---

## Net summary

Bot.PickAKA's **happy path** (gates 1-5, 6, 7) is **correctly
implemented**. The sender-side gate stack is logically sound and
matches the documented G18-09 decision matrix where the surface exists
in code (perfect-bossness, partner-void).

The **risks** are downstream:

1. **F6 / D-RT-18 S1 (HIGH):** Saudi Master partner ruffs anyway —
   makes AKA pure leak. Sender doesn't gate on partner tier.
2. **F3 / B-Net-05 F12 (MED):** doubled-after-AKA window. Live banner
   not retracted on opp double.
3. **F8 / X2 B5 (LOW):** AKA-on-T trick lock missing in Rules.lua.

PickAKA itself is **clean**; the AKA mechanism's structural gaps live
in `Rules.lua` (legality / trick-winner) and `BotMaster.lua:830`
(parallel legal-list builder). Recommend the v0.10.3 fix targets be
B-Net-05 S1 (BotMaster:830) and B-Net-05 F12 (banner retraction on
double), in that order.
