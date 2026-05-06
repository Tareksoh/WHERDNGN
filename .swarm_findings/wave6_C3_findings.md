# Wave 6 C3 Findings — Human Play Mistake Taxonomy (Batch C: B-29/30/32/33/34)

Reviewer: wave6_C3 agent
Codebase version: v0.4.4
Date: 2026-05-03

---

## B-29 — Human consistent trump-lead culture: "always pull trump first" players

**MISTAKE:** Human bidders from Saudi Baloot trump-lead culture begin trick 1–3 with the highest trump regardless of hand texture.

**FREQUENCY:** High in Saudi Baloot convention play. The "pull trump first" opening is close to a cultural default for bidders in physical Saudi play. Online this is moderated but still majority behavior for non-expert bidders.

**BOT-EXPLOITS-IT:** Partial. The bot's `pickLead` (Bot.lua:785–801) leads high trump whenever `isBidderTeam and isBidder`, which mirrors the same culture — the bot produces the human-identical opening. However, when the bot is **defending** against a human bidder, there is no mechanism to exploit foreknowledge of "this human will lead trump in tricks 1–3." The bot's `pickFollow` (Bot.lua:915–1069) reads the current trick state reactively; it does not anticipate trump-heavy early leads and pre-position high non-trump cards for later tricks when trump density has dropped.

Specifically: if the bot knows the human bidder will burn trump early, the bot's optimal response is to hold high non-trump in tricks 1–3 (let the human expend trump) then cash side-suit aces in tricks 4–5 after trump is exhausted. The current code does not adjust discard strategy based on any trump-lead tempo prediction.

**FILE:LINE:**
- `C:/CLAUDE/WHEREDNGN/Bot.lua:785–801` — bidder-team trump-lead block
- `C:/CLAUDE/WHEREDNGN/Bot.lua:915–1069` — pickFollow: no anticipatory holding of non-trump honors
- `C:/CLAUDE/WHEREDNGN/Bot.lua:189–196` — `styleTrumpTempo()` function exists, returns +1 for aggressive, but is **never called** from `pickFollow` or `pickLead`

**FIX:** When bot is defending in PHASE_PLAY and `styleTrumpTempo(opponentSeat)` returns `1` (aggressive early-trump), the bot's pickFollow should prefer discarding low side-suit cards (not aces/tens) in the early tricks, conserving them for the mid-hand when opponent trump is projected to be exhausted. Hook `styleTrumpTempo` into the discard-selection branch in `pickFollow` (currently dead at Bot.lua:189–196) to bias toward holding point cards in tricks 1–3 against aggressive-tempo opponents.

---

## B-30 — Human first-trick meld silence: not declaring when opponent meld would be crushed

**MISTAKE:** A human strategist sometimes deliberately withholds a qualifying meld declaration during trick 1 when the opponent's already-declared meld outranks it, to avoid telegraphing hand strength or suit composition.

**FREQUENCY:** Low-moderate. Expert-level behavior, uncommon among casual Saudi Baloot players. Most human players declare all melds automatically (the app auto-prompts). The "silence" pattern requires understanding of meld override rules and deliberate UI non-action.

**BOT-EXPLOITS-IT:** No. And the bot itself does not practice silence — `Bot.PickMelds` (Bot.lua:1130–1139) calls `R.DetectMelds(hand, S.s.contract)` unconditionally and returns every detected meld. There is no check whether declaring would be strategically disadvantageous. The bot comment on line 14 says explicitly "Always declare detected melds." The code reflects this with zero strategic filtering.

Saudi Baloot meld override mechanics (Rules.lua:258–319) cause the losing team's meld to score zero when the best-meld comparison is lost (`R.CompareMelds` at Rules.lua:309). This means declaring a weak meld against a dominant opponent meld has zero point benefit while simultaneously revealing hand composition (suit and top rank of the declared sequence). A human exploiting this would produce no meld message; the bot will always declare.

**FILE:LINE:**
- `C:/CLAUDE/WHEREDNGN/Bot.lua:1130–1139` — `PickMelds` always declares all detected melds
- `C:/CLAUDE/WHEREDNGN/Rules.lua:309–319` — `CompareMelds`/`R.SumMeldValue` — losing team's meld scores 0
- `C:/CLAUDE/WHEREDNGN/Rules.lua:258–297` — `meldRank` scoring hierarchy

**FIX (Fzloky+ tier):** In `PickMelds`, before declaring a meld, compare its `meldRank` against the best meld already declared by opponents (`S.s.meldsByTeam` for the opposing team). If the bot's best meld would lose the `CompareMelds` comparison (score would be 0) and the meld would reveal the top card of a suit the bot plans to use as a surprise lead, suppress the declaration. This is an M3lm+ heuristic and should be gated behind `Bot.IsM3lm()`. The current "always declare" behavior is correct for Basic/Advanced since information concealment is not a priority at those tiers.

---

## B-32 — Human signal exploitation: bot should SEND false signals to human opponents (deceptive discard)

**MISTAKE (human):** Human opponents watching a bot's first off-suit discard may naively apply the Fzloky convention interpretation — high discard = "strong in this suit" — and make suboptimal leads or avoid leading into the bot's actual strength.

**FREQUENCY:** Moderate. In Saudi Baloot circles aware of signal conventions, experienced human opponents will watch the bot's discard. Unsophisticated players ignore discards entirely. The exploitable population is the convention-aware middle tier.

**BOT-EXPLOITS-IT:** No. The bot currently has zero mechanism for deceptive signaling. `Bot.OnPlayObserved` (Bot.lua:200–270) records the bot's own discard into `firstDiscard` like any other seat, but the bot's `pickFollow` discard selection (Bot.lua:1052–1068) uses `lowestByRank(discardable, contract)` — the lowest non-trump. This produces a reliably LOW discard in normal defensive play, which by the Fzloky convention signals "don't lead this suit." The bot is not sending a deceptive HIGH discard.

There is no code path anywhere in Bot.lua, BotMaster.lua, or Net.lua that selects a deceptively-high off-suit card to mislead an observing human opponent. The Fzloky signal sending is purely for partner coordination; the bot never considers opponent-visibility of its discards.

**FILE:LINE:**
- `C:/CLAUDE/WHEREDNGN/Bot.lua:747–892` — `pickLead` Fzloky prefix reads PARTNER signals, never considers sending to opponents
- `C:/CLAUDE/WHEREDNGN/Bot.lua:1052–1068` — `pickFollow` discard: always `lowestByRank(discardable)` — no deceptive path
- `C:/CLAUDE/WHEREDNGN/Bot.lua:217–226` — `OnPlayObserved` records firstDiscard for bot seats but the recording is symmetric, not deception-aware

**FIX (SaudiMaster tier only):** Add a `_deceptiveDiscard` heuristic at the SaudiMaster tier gated behind `Bot.IsSaudiMaster()`. When the bot is void in a suit during a follow play, and at least one opponent seat is known to use Fzloky-style observation (heuristically: any seat that has responded to a high-discard signal in a prior round by leading that suit), the bot may select a HIGH card of another suit as the off-suit discard to manufacture a false preference signal. Guard with: (1) the suit being discarded high must be one where the bot has secondary strength (to avoid giving away real winners), and (2) deception fires at most once per round per opponent. This is a legitimate advanced-play behavior present in expert Saudi Baloot — a high discard in a suit you do NOT want led is a well-known deceptive device.

---

## B-33 — Human AKA interpretation: do human players respect bot AKA signals?

**MISTAKE (human):** Human partners routinely ignore or misinterpret the bot's AKA (إكَهْ) signal, over-trumping a suit the bot has announced as boss. This causes the bot's AKA signal to fail to coordinate as intended.

**FREQUENCY:** High. The AKA signal is a verbal/banner convention unfamiliar to most casual players. Human players who see the banner may not understand it means "I hold the highest unplayed card — do not trump this suit." Over-trumping by a human partner who received an AKA signal is extremely common in mixed bot-human games.

**BOT-EXPLOITS-IT:** No. And the bot's `PickAKA` function (Bot.lua:1078–1108) has no awareness of whether the partner is human or a bot. It fires unconditionally based on Advanced mode being active, card position, and per-round dedup. There is no `S.s.seats[partner].isBot` check before deciding whether AKA is worth sending.

The practical consequence: `PickAKA` is most useful when the partner is a bot (who will read the per-round `akaSent` flag and suppress over-trumping). When the partner is human and unfamiliar with the convention, firing the AKA signal has no coordination benefit and only reveals information to opponents.

**FILE:LINE:**
- `C:/CLAUDE/WHEREDNGN/Bot.lua:1078–1108` — `PickAKA`: no partner-is-human check
- `C:/CLAUDE/WHEREDNGN/Bot.lua:1096–1098` — `akaSent` per-suit dedup: correct for bot partners, wasted on human partners
- `C:/CLAUDE/WHEREDNGN/Net.lua:3353–3358` — AKA dispatch in MaybeRunBot: unconditional send if `PickAKA` returns non-nil

**FIX:** In `Bot.PickAKA(seat, leadCard)`, check whether the partner seat is a bot. If `S.s.seats[R.Partner(seat)]` exists and `not S.s.seats[R.Partner(seat)].isBot`, return `nil` (suppress the signal). The AKA coordination signal has no value when the partner is human and cannot be reliably counted on to respect it. The signal still benefits bot-bot team coordination and should remain active in that case. A softer alternative: keep sending to human partners but add a comment documenting the known ineffectiveness — this preserves future UX where a tutorial could teach human players to recognize AKA.

---

## B-34 — Human partner reading: bot should model human over-trump tendencies from style ledger

**MISTAKE (human):** Human "always leads trump first" bidders accumulate observable behavior that the bot can read and adjust play for.

**FREQUENCY:** This is not a human mistake per se; it is an audit of whether the bot captures human play data in its style model.

**BOT-EXPLOITS-IT:** Partially, with a critical gap. `Bot.OnPlayObserved(seat, card, leadSuit)` (Bot.lua:200–270) is called for **every** seat whose play passes through `N._OnPlay` (Net.lua:1065–1066) and `N.LocalPlay` (Net.lua:1609–1610). There is no `isBot` filter in `OnPlayObserved`. Human plays are observed and their trump-lead behavior is counted into `style.trumpEarly` / `style.trumpLate` (Bot.lua:244–254) in `_partnerStyle[seat]` identically to bot plays.

Therefore: **yes**, human plays are captured by `OnPlayObserved`, and a human who always leads trump early accumulates `style.trumpEarly` counts across the game. `styleTrumpTempo(seat)` returns `1` (aggressive) once `trumpEarly > trumpLate * 1.5` with at least 2 samples (Bot.lua:192–195).

The critical gap is that `styleTrumpTempo` is defined but **never consumed**. Neither `pickLead`, `pickFollow`, nor any other play decision reads the result of `styleTrumpTempo`. The style ledger accumulates human data correctly but the data is a dead end — no bot decision is gated on it. The same dead-end finding was noted for `styleBelTendency` in Bot.lua:181–187, which is also never called from any picker.

**FILE:LINE:**
- `C:/CLAUDE/WHEREDNGN/Bot.lua:200–254` — `OnPlayObserved`: no isBot filter; human trump-leads are counted correctly
- `C:/CLAUDE/WHEREDNGN/Bot.lua:189–196` — `styleTrumpTempo`: defined, computes correctly from human data, but never called
- `C:/CLAUDE/WHEREDNGN/Bot.lua:181–187` — `styleBelTendency`: same pattern — accumulates, never consumed
- `C:/CLAUDE/WHEREDNGN/Bot.lua:720–891` — `pickLead`: no reference to `styleTrumpTempo` or `styleBelTendency`
- `C:/CLAUDE/WHEREDNGN/Bot.lua:915–1069` — `pickFollow`: no reference to either style metric

**FIX:** Wire `styleTrumpTempo` into `pickLead` and/or `pickFollow` at the M3lm tier. Two natural integration points:

1. In `pickLead` for the defending bot (non-bidder): if `styleTrumpTempo(opponentBidderSeat) == 1`, prefer retaining non-trump Aces in early tricks by checking whether leading that Ace now vs. waiting 2 tricks is better. Currently the `HighestUnplayedRank` short-circuit (Bot.lua:731–739) already handles the "lead the boss" case, so the integration is: don't lead the boss Ace in tricks 1–2 if opponent is aggressive-tempo (they will lead trump and exhaust their holdings before you need to lead the boss).

2. In `pickFollow` under "Can't win — discard" path (Bot.lua:1057–1068): if `styleTrumpTempo(opponentSeat) == 1` and this is trick 1 or 2, prefer discarding from a suit with a low card rather than a mid-rank, preserving the best point cards for later tricks after trump draw is complete.

---

## Cross-cutting observation

All five angles converge on the same structural finding: the `_partnerStyle` ledger (`trumpEarly`, `trumpLate`, `bels`, `triples`, `fours`, `gahwas`) accumulates data correctly for both bot and human seats via `OnPlayObserved` and `OnEscalation`, but the derived metrics `styleTrumpTempo` and `styleBelTendency` are dead code — they are computed and returned but no caller ever invokes them. The entire M3lm style-learning subsystem is a data accumulator with no consumer. Wiring `styleTrumpTempo` into `pickLead`/`pickFollow` at M3lm tier would simultaneously address B-29 (trump culture exploitation), B-34 (human trump-pattern reading), and provide the infrastructure for B-32 (deceptive discard timing awareness). The AKA issue (B-33) and the meld-silence issue (B-30) are independent and require their own targeted fixes.

---

*No code changes made. Report only.*
