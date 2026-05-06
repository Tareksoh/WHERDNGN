# Wave 5 C2 Findings — Integration (cont.) + First Human-Bid Reading Angles

Reviewer: wave5_C2 agent
Codebase version: v0.4.4
Date: 2026-05-03

---

## A-98 — fzlokyPrefSuit and fzlokyAvoidSuit nil path in pickLead

**VERDICT: PASS (with one latent info-level concern)**

**Evidence:**

The Fzloky block in `pickLead` (Bot.lua:747–773) reads:

```
local fzlokyPrefSuit, fzlokyAvoidSuit = nil, nil
if Bot.IsFzloky() and Bot._memory then
    local p = R.Partner(seat)
    local sig = Bot._memory[p] and Bot._memory[p].firstDiscard
    if sig and sig.suit then
        local r = sig.rank
        if r == "A" or r == "T" or r == "K" then
            fzlokyPrefSuit = sig.suit
        elseif r == "7" or r == "8" then
            fzlokyAvoidSuit = sig.suit
        end
    end
end
```

When both `fzlokyPrefSuit` and `fzlokyAvoidSuit` are nil (partner hasn't discarded yet, or the signal rank was Q/J/9), the code falls through cleanly to the `isBidderTeam and isBidder` branch (Bot.lua:785). There is no early return, no state mutation, and no variable shared between the Fzloky block and later logic. The `fzlokyPrefSuit` and `fzlokyAvoidSuit` locals are used only in the two guard blocks below (Bot.lua:760 and Bot.lua:867) and in the `longestN` comparison (Bot.lua:867–870). All three consume them in a purely read-only way.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:747–892`

**Latent info concern:** Signal ranks Q, J, and 9 produce neither pref nor avoid (both remain nil). There is no code comment calling this out as intentional. It is a silent no-op: mid-rank discards carry no signal. This is reasonable but undocumented. A future contributor could interpret the "Q/J/9 gap" as a bug. No functional defect.

**Severity:** INFO

**Recommendation:** Add a one-line comment at Bot.lua:753 noting: "Q/J/9 discards are uninformative — neither prefer nor avoid" so the intentional gap is visible.

---

## A-100 — Bot.Reset / Bot.Init: initialization call chain

**VERDICT: WARNING**

**Evidence:**

There is no `Bot.Reset` or `Bot.Init` function. The two reset calls are issued inline at the only call-site that matters: `N.HostStartRound()` in Net.lua.

`C:/CLAUDE/WHEREDNGN/Net.lua:1363–1370`:

```
if B.Bot and B.Bot.ResetMemory then B.Bot.ResetMemory() end
if roundNum == 1 and B.Bot and B.Bot.ResetStyle then
    B.Bot.ResetStyle()
end
```

The semantics are:
- `ResetMemory` — every round (correct: per-round card memory).
- `ResetStyle` — only when `roundNum == 1` (correct: cross-round style learning must survive round boundaries).

**The `_HostRedeal` path** (Net.lua:1321–1344) also calls `Bot.ResetMemory` (Net.lua:1328) before issuing a fresh `ApplyStart`. That path does NOT call `ResetStyle`, which is correct since a redeal is not a new game.

**What is missing:** There is no `Bot.Reset` umbrella function. The design relies on callers knowing to call both functions in the right lifecycle sequence. Currently only one caller exists (`HostStartRound`), but if a second entry point for starting a game is ever added (e.g., a rejoin path or a test harness), the two-call sequence would have to be duplicated or `ResetStyle` would be silently skipped. The `_HostRedeal` path already diverges: it calls `ResetMemory` but not `ResetStyle` — correct behavior, but the asymmetry is navigable only because it's all in one 20-line block.

**Secondary concern:** `Bot._partnerStyle` and `Bot._memory` are initially `nil`, and both are lazily initialized inside their respective functions (`emptyMemory()` / `emptyStyle()` called on first use). This means a `PickBid` or `PickPlay` call before `HostStartRound` is called (e.g., in a unit-test scenario without a net layer) will silently operate on a nil style table. `OnPlayObserved` already guards this with `if not Bot._partnerStyle then Bot._partnerStyle = emptyStyle() end` (Bot.lua:229), but `styleBelTendency` and `styleTrumpTempo` return nil with no fallback hint when `_partnerStyle` is nil — callers would need to guard.

**Severity:** WARNING

**File:line:** `C:/CLAUDE/WHEREDNGN/Net.lua:1363–1370`, `C:/CLAUDE/WHEREDNGN/Net.lua:1328`, `C:/CLAUDE/WHEREDNGN/Bot.lua:118`, `C:/CLAUDE/WHEREDNGN/Bot.lua:149`

**Recommendation:** Introduce a `Bot.ResetForNewRound()` and `Bot.ResetForNewGame()` pair (or a single `Bot.Reset(isNewGame)`) that encapsulate the two calls. Route both `HostStartRound` and `_HostRedeal` through these functions. This makes the lifecycle contract explicit and prevents divergence if a second entry point is added.

---

## B-01 — Human Hokm bid honesty: does the bot read/exploit human Hokm bidder hand range?

**VERDICT: WARNING — Bot trusts human Hokm bids at face value; no skepticism path for bluff hands**

**Evidence:**

The bot reads human bids through `partnerBidBonus()` (Bot.lua:410–427) and `PickBid`'s `anyHokm`/`anySun` scan (Bot.lua:547–551). When a human partner has bid `HOKM:<suit>`, `partnerBidBonus` returns:
- `+20` if the contract trump matches the human's declared suit (implying partner holds J/9 of that suit)
- `+10` for any other Hokm bid

These bonuses are unconditional: they treat every human Hokm bid as honest. There is no mechanism to discount the +20 when a human bids Hokm on A+9+T-no-J, or on a long suit (5+ cards, no honors). Saudi Baloot human players commonly bid Hokm on:
- A+9+T without J (strong Hokm by point count, no step-function J bonus)
- Long 5-card suits (K+Q+J+x+x) — legitimate but far weaker than J+9

The `suitStrengthAsTrump` function (Bot.lua:298–332) for the BOT's own hand applies an Advanced-mode J step-function penalty (`strength * 0.4`) when there is no J and no 9+A pair, but this knowledge is never applied skeptically to a human partner's declared trump.

The resulting over-trust in human Hokm bids propagates directly into escalation decisions: `partnerBidBonus` is added to the bot's `strength` in `PickDouble`, `PickTriple`, `PickFour`, `PickGahwa`, and `escalationStrength` (Bot.lua:1159–1199). A bot that receives +20 from a human who bluffed Hokm on a bare long suit will systematically over-escalate.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:410–427`, `Bot.lua:1153–1200`

**Severity:** WARNING

**Recommendation:** Add a confidence-discounting variant of `partnerBidBonus` for human seats. When the partner seat is not a bot (check `S.s.seats[partner] and not S.s.seats[partner].isBot`), lower the Hokm-matching bonus from +20 to +12, and the other-Hokm bonus from +10 to +6. Human Hokm bidders in Saudi Baloot cover a wide range including A+9+T (no J) and length-only hands; the J+9 certainty implied by the +20 value does not hold for human bids. Alternatively, expose a config flag (e.g., `K.BOT_HUMAN_BID_TRUST = 0.6`) that scales the bonus.

---

## B-02 — Human Sun bid honesty: over-optimistic Sun bidders and Bel calibration

**VERDICT: WARNING — Bot does not distinguish human Sun marginal bidder from a sure Sun hand**

**Evidence:**

`partnerBidBonus` returns a flat `+15` for a partner Sun bid regardless of whether that partner is a human or a bot (Bot.lua:416). The bot's `PickDouble` (Bel decision) computes:

```
strength = strength + partnerBidBonus(seat, contract)
                   + partnerEscalatedBonus(seat, contract)
local th = K.BOT_BEL_TH - (scoreUrgency(...) + matchPointUrgency(...))
```

`K.BOT_BEL_TH = 70` (Constants.lua:252). A bot defender at sunStrength ~58 with a human partner who bid Sun receives +15, pushing it to 73 and over the Bel threshold. But if the human bid Sun on a marginal 45–55 score hand (common in close-score situations), the +15 bonus is optimistic: the human Sun bidder is more likely to fail, meaning Bel is statistically profitable for the defenders.

The intended behavior, noted in the B-02 angle brief, is: "the bot's defender decision should Bel against more Sun contracts than against equivalent Hokm contracts, knowing the Sun bidder is more likely on a marginal hand." The current code does the opposite: it adds the flat +15 partner-Sun bonus unconditionally to the BOT's own strength before comparing to `BOT_BEL_TH`, which means the bot Bels less readily when its own partner bid Sun. This is the correct direction for partner-Sun cases, but the same flat +15 value also appears in `escalationStrength` for opponent-Sun cases indirectly (the contract type adds a separate +10 to `strength` in `PickDouble` at Bot.lua:1165). There is no path where the bot detects that the current Sun bidder is a human with a known marginal-score motivation and applies a higher-aggression Bel bias.

The `N._SunBelAllowed` gate (Net.lua:68–76) correctly enforces the Saudi rule that Sun Bel is only legal when the bidder team crossed 101 and the defender team hasn't. But this is a legality gate, not a bot-strategy adjustment.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:416`, `Bot.lua:1153–1180`, `C:/CLAUDE/WHEREDNGN/Net.lua:68–76`

**Severity:** WARNING

**Recommendation:** In `PickDouble`, when `contract.type == K.BID_SUN`, check whether the bidder is a human seat (`not S.s.seats[contract.bidder].isBot`). If so, reduce `th` by an additional 5–8 points (i.e., the bot Bels more aggressively against human Sun bidders) to account for the higher bluff-rate of human Sun bids on marginal hands. This is the correct direction per B-02: human Sun bidder → defenders should be more willing to Bel, not less.

---

## B-03 — Human Ashkal usage: does the bot correctly read Ashkal as a dual signal?

**VERDICT: WARNING — Bot reads Ashkal only as "partner holds Sun-strong hand", not as "partner's J in original suit is confirmed"**

**Evidence:**

When a human calls Ashkal, `partnerBidBonus` returns `+15` — treated identically to a direct Sun bid (Bot.lua:417). The Saudi Baloot meaning of Ashkal is richer: the Ashkal caller is signaling:
1. They hold strong Sun-side cards (enough to contribute to a Sun contract), AND
2. They are weak in the original flipped trump suit — implying the partner who bid Hokm likely holds the J (and possibly 9) of that suit.

The second implication is never exploited. The bot (as the original Hokm bidder's partner-teammate in the new Sun contract) does not get any play-phase benefit from knowing that the Ashkal caller's discard pile is likely to be trump-weak and side-suit-strong.

More concretely: after Ashkal finalizes the contract as `{type=BID_SUN, viaAshkal=true}` (State.lua:1448), the `Bot.PickPlay` and `pickLead` functions treat it identically to a plain Sun contract. The `viaAshkal` flag on the contract is set (State.lua:1448) but is never read in Bot.lua or BotMaster.lua.

**File:line:** `C:/CLAUDE/WHEREDNGN/Bot.lua:417`, `C:/CLAUDE/WHEREDNGN/State.lua:1448`, `C:/CLAUDE/WHEREDNGN/Bot.lua:1110–1124`
<br>Search confirmed `viaAshkal` is set in State.lua but no grep match exists in Bot.lua or BotMaster.lua for the string `viaAshkal`.

**Severity:** WARNING

**Recommendation (two parts):**

1. In `partnerBidBonus`, when `b == K.BID_ASHKAL`, return `+15` as now (correct for general hand strength), but also set a local flag or pass it through to the caller that the original bidder's suit likely contained J — this could bias leading behavior if the bot is the declared bidder (now forced into Sun via Ashkal, they are the declarer and should not lead trump, which the Sun play logic already handles, so this part is low-priority).

2. In `pickLead` and `pickFollow`, read `contract.viaAshkal`. When true and the bot is the declared Sun bidder (the partner of the Ashkal caller), the bot knows its Ashkal-calling partner is strong in side suits. This could be used as a lightweight signal equivalent to a Fzloky firstDiscard with a high-rank on a non-trump side suit. Currently this information is entirely wasted.

---

## Cross-cutting observation

All three B-angle failures share the same root cause: `partnerBidBonus` applies fixed flat bonuses to human-seat bids using the same values as bot bids, even though bot bids are generated by a deterministic threshold function (so the signal reliability is known) whereas human bids span a wide bluff range. A single `isHumanBidder` confidence multiplier (e.g., 0.5–0.7) applied uniformly inside `partnerBidBonus` would address all three B-angles at once with minimal code change.

---

*No code changes made. Report only.*
