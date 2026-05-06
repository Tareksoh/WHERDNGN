# Wave 7 C2 — Score-Position Exploitation, Batch B

Codebase v0.4.4. Files audited: Bot.lua, BotMaster.lua, Constants.lua, Rules.lua, UI.lua, State.lua.

---

## B-51 — Human Al-Kaboot awareness: do humans play for the sweep?

**SIGNAL** / **OCCASIONAL** / **BOT-EXPLOITS-IT: PARTIALLY**

Saudi human players rarely target Al-Kaboot as a deliberate game plan; the sweep (all 8 tricks) emerges incidentally. The value is extreme — K.AL_KABOOT_HOKM = 250 raw (K.AL_KABOOT_SUN = 220 × 2 = 440 raw) vs. a normal made hand of ~162 raw in Hokm — so a single defensive trick costs the entire bonus.

**Bot behavior:** `rolloutValue` in BotMaster.lua:475 calls `R.ScoreRound(simTricks, contract, meldsByTeam)`, which correctly returns `result.raw` reflecting the Al-Kaboot bonus when `sweepTeam` is set (Rules.lua:614–620). The ISMCTS diff at BotMaster.lua:483 propagates this as a massive positive swing (~+250/+440 raw vs. a normal ~±162 outcome). So the rollout **does** account for the Al-Kaboot cliff and will implicitly steer toward keeping 7 tricks in hand when it detects the sweep is achievable in rollout worlds.

**Gap identified:** Bot.lua's `pickLead` and `pickFollow` have no explicit "sweep-in-progress" check at the heuristic tiers (Advanced, M3lm, Fzloky). At trick 7, when the bot has won 6/7 tricks so far, the heuristic fallback (Basic/Advanced/M3lm without SaudiMaster) applies `lowestByRank(winners)` — cheapest winner, not "always win." A bot at a heuristic tier that happens to hold a non-winner on trick 7 will throw a low card without any awareness that it just forfeited the 250-point bonus. Only Saudi Master's ISMCTS rollout surfaces this via the scoring cliff. No explicit `if trickCount >= 6 and allWonByMyTeam then force win` guard exists in Bot.lua.

- **C:/CLAUDE/WHEREDNGN/BotMaster.lua:475–483** — rolloutValue uses R.ScoreRound which handles Al-Kaboot correctly
- **C:/CLAUDE/WHEREDNGN/Bot.lua:962–1068** — pickFollow has no sweep-awareness guard
- **C:/CLAUDE/WHEREDNGN/Constants.lua:107–111** — K.AL_KABOOT_HOKM = 250, K.AL_KABOOT_SUN = 220

**Fix:** In `pickFollow` (Advanced+ gate), when `#(S.s.tricks or {}) >= 6` and the bot's team has won all prior completed tricks, always choose a winner if any exists rather than cheapest winner. Similarly, in `pickLead` at trick 7 with 6 wins, never cede the lead.

---

## B-52 — Human reaction to bot AKA signal: do they take the appropriate trick?

**MISTAKE (human)** / **HIGH** / **BOT-EXPLOITS-IT: NO**

The AKA signal ("I hold the boss of this non-trump suit, don't over-trump it") is communicated to human partners via a banner (UI.lua:2726–2746) and a voice cue (K.SND_VOICE_AKA). Both mechanisms have usability problems:

1. **Banner placement and legibility:** The banner is 180×22 px, anchored at the TOP of `centerPad` with offset (0, -4) (UI.lua:1279–1280), placing it inside the center trick area at approximately y+89..+111 from centre. Its frame level is bumped to `centerPad:GetFrameLevel() + 50` (UI.lua:1288) to prevent overlap with the center trick card at the top slot. The green text (`0.40, 1.00, 0.55`) at 13 pt is readable on the dark felt backdrop. However, a human player whose attention is on their own hand at the bottom of the screen will rarely look at the top of the center area when it is their turn to play a following card. The banner does not produce any animation, glow, or repositioning to draw attention.

2. **No partner-is-human check in PickAKA:** `Bot.PickAKA` (Bot.lua:1078–1108) fires unconditionally when Advanced mode is active, without checking `S.s.seats[R.Partner(seat)].isBot`. When the partner is human, the signal has no coordination benefit (humans don't read the banner reliably) but the `akaSent[su]` flag is still consumed, permanently suppressing future AKA announcements on that suit for the rest of the round. The bot wastes its one-time signal and may forgo a later, more tactically valuable announcement.

3. **Rollout impact:** The ISMCTS sampler in BotMaster.lua has no model of human partner AKA compliance. Even if the bot signals, it cannot predict whether the human will honor it. `sampleConsistentDeal` treats all partners identically regardless of `isBot` status when computing expected outcomes.

- **C:/CLAUDE/WHEREDNGN/Bot.lua:1078–1108** — PickAKA: no `S.s.seats[partner].isBot` check before marking `akaSent`
- **C:/CLAUDE/WHEREDNGN/UI.lua:1279–1289** — akaBanner: no motion/highlight to attract human attention
- **C:/CLAUDE/WHEREDNGN/UI.lua:2726–2746** — renderAKABanner: small 180×22 banner, no animation

**Fix:** Gate AKA signaling on partner being a bot seat (`S.s.seats[R.Partner(seat)].isBot`). When partner is human, suppress AKA to preserve the `akaSent` flag for more useful moments, or decouple the `akaSent` dedup from partner-type so re-announcement is allowed when the previous signal was wasted on a human.

---

## B-53 — Human fatigue pattern: late-game plays more mechanical, less strategic

**SIGNAL (human model gap)** / **COMMON** / **BOT-EXPLOITS-IT: INVERTED**

Human players in Saudi Baloot increasingly default to "play highest card" in tricks 6–8 as cognitive fatigue sets in. This is a genuine, well-documented pattern. At late game, opponent behavior becomes highly predictable — they lead their highest remaining card, follow with the highest winning card, and discard their lowest loser. Rollout worlds at tricks 6–7 have at most 1–2 cards per opponent (seatHandSize returns 1 at trick 7). There are at most 6 permutations of 3 remaining cards across 3 opponents at trick 7.

**Current behavior:** BotMaster.lua:514–517 scales `numWorlds` UPWARD at late game:
```
if numTricks >= 6 then numWorlds = 100
elseif numTricks >= 4 then numWorlds = 60 end
-- else BASE_NUM_WORLDS = 30 (tricks 0-3)
```
This inverts the optimal sampling strategy. At trick 6 (`numTricks >= 6`), opponents hold at most 2 cards each; with void constraints applied there may be only 2–6 valid deals total. Running 100 worlds samples a universe of size ≤6 approximately 16× redundantly. The performance cost (100 worlds × ~25 plays) is wasted on what is effectively an exact search.

At tricks 0–3, each opponent holds 7–8 unknown cards, producing C(24,8)×... possible worlds. 30 worlds substantially undersample the space (previously flagged in wave4_C2). The late-game 100-world scaling does not exploit human predictability (no heuristic models "human plays highest at trick 6+") and over-models complexity that simply isn't there.

The rollout policy itself at BotMaster.lua:424–436 uses `highestRank(legal)` for the bidder team's lead heuristic ("placeholder: lead high trump"). This accidentally captures "play highest" human behavior at late game, but it's not purposeful and applies to all seats including partner.

- **C:/CLAUDE/WHEREDNGN/BotMaster.lua:514–517** — numWorlds scaling inverted vs. uncertainty profile
- **C:/CLAUDE/WHEREDNGN/BotMaster.lua:424–436** — late-game rollout lead heuristic coincidentally matches human behavior

**Fix:** Invert the scaling: `if numTricks <= 3 then numWorlds = 60 elseif numTricks <= 5 then numWorlds = 45 else numWorlds = 25 end`. At trick 6+ where hands are nearly empty, reduce to 25 worlds (still covers all meaningful permutations) and redirect budget to tricks 0–3 where variance is highest. Documented in wave4_C2_findings.md as well but not yet acted on.

---

## B-54 — Human bluffing Bel to test bot Triple response

**SIGNAL (human exploit)** / **MODERATE** / **BOT-EXPLOITS-IT: NO**

The "probe Bel" tactic: a human defender Bels on a marginal hand specifically to observe whether the bot triples (revealing strong hand / contract confidence). If the bot doesn't triple, the human infers the bidder-bot is weak and may elect to Four with higher confidence on a subsequent hand.

**Bot Triple decision:** `Bot.PickTriple` (Bot.lua:1215–1224) computes `escalationStrength` (sunStrength + trump suit strength + partnerBidBonus + partnerEscalatedBonus) then applies a fixed threshold `K.BOT_TRIPLE_TH = 90` modified by `scoreUrgency + matchPointUrgency`. The jitter is `BEL_JITTER = 10`, so the effective threshold ranges from `90 - urgency ± 10`.

**Fixed threshold problem:** The Triple decision is a hard strength threshold with ±10 jitter. A human probe-Beling can reliably infer the bot's hand strength bucket by observing Triple/No-Triple outcomes across multiple rounds (the bot Triples when strength ≥ 80..100 range). With 3 rounds of observations, the human narrows the bot's effective strength range to ±10 units. This is a full information leak about the bot's contract confidence.

No countermeasure exists: there is no bluff-Triple mechanism, no random Triple below threshold (even on low-probability), and no check of `S.s.seats[contract.bidder].isBot` to detect when the caller is human. The jitter is applied identically whether the Bel came from a bot (honest threshold signal) or a human (potentially a probe).

Additionally, `partnerBidBonus` and `partnerEscalatedBonus` are not gated on `isBot` for the opponent's Bel. A human probe-Bel increases `strength` via `partnerEscalatedBonus` when `pIsDefender and contract.doubled`, adding +5 (Bot.lua:525) — a human's probe Bel slightly lowers the bot's effective Triple threshold, making it easier for the probe to trigger a Triple that the human reads as a confidence signal.

- **C:/CLAUDE/WHEREDNGN/Bot.lua:1215–1224** — PickTriple: deterministic threshold with only ±10 jitter
- **C:/CLAUDE/WHEREDNGN/Constants.lua:253** — K.BOT_TRIPLE_TH = 90 (fixed, readable)
- **C:/CLAUDE/WHEREDNGN/Bot.lua:524–526** — partnerEscalatedBonus: human probe-Bel adds +5 to bot Triple threshold

**Fix:** When the Bel came from a human seat (`not S.s.seats[opponent].isBot`), increase jitter from 10 to 20 on the Triple threshold, and add a small probability (10–15%) of a "bluff Triple" below threshold to prevent perfect readability. Alternatively, gate `partnerEscalatedBonus` on `opponent.isBot` so a human probe-Bel doesn't lower the bot's threshold.

---

## B-55 — Human "sacrifice play" in critical tricks: deliberate self-defeat to score position

**SIGNAL (human exploit)** / **RARE** / **BOT-EXPLOITS-IT: NO**

The sacrifice play (tempo steal): a defender intentionally wins a trick they didn't want — by leading a high card to capture the bot's winning card — in order to gain the lead and then fire a "killer" suit they know the bot is void in. This is analogous to bridge's "unblock" or "throw-in" and is rare in Saudi Baloot but occurs at intermediate-advanced level.

**Bot's pickFollow logic** (Bot.lua:915–1068) has no mechanism to detect whether an opponent is intentionally "gifting" the bot a lead by underplaying, nor does it anticipate that winning a trick might result in being put in a dangerous lead position. The key code path:

When the bot is at position 3 (third to play), it plays `highestByRank(winners)` (Bot.lua:1045) — committing the highest winner to prevent a 4th-seat overcut. This is correct defensively but means the bot will always "take" a trick when it can, even if taking it results in being on lead in a suit where all its remaining cards are losers.

There is no analysis in `pickLead` that asks "do I want to be on lead in this position?" The heuristic always leads low from the longest non-trump suit (steps 1–3 of pickLead). If the opponent sacrifice play has created a situation where the bot has only short or honor-light suits remaining, pickLead will dutifully lead low from the best available suit without recognizing it has been maneuvered into a losing lead structure.

The ISMCTS rollout in BotMaster.lua's `heuristicPick` does model "commit high at position 3" (line 416–419), but this models the BOT's position-3 play optimally; it does not model the OPPONENT's willingness to sacrifice a trick at their position 3 or 4 to gain an advantageous lead. The rollout policy for opponent seats uses the same heuristic as for the bot: opponents try to win cheaply when they can (lowestByRank(winners)). An opponent who would strategically LOSE a trick to steer lead is not modeled — this makes the rollout systematically under-predict opponent sacrifice-play value.

No tracking of "opponent passed on a winning card" patterns exists in `Bot._memory` or `Bot._partnerStyle`. The `styleTrumpTempo` style-ledger (Bot.lua:189–196) tracks early vs. late trump leads but has no "voluntary underplay" counter.

- **C:/CLAUDE/WHEREDNGN/Bot.lua:1027–1049** — pos==3 always plays highestByRank(winners) regardless of positional consequences
- **C:/CLAUDE/WHEREDNGN/Bot.lua:720–892** — pickLead: no "am I in a bad lead position?" evaluation
- **C:/CLAUDE/WHEREDNGN/BotMaster.lua:396–421** — heuristicPick: opponent rollout policy uses lowestByRank(winners), not sacrifice modeling
- **C:/CLAUDE/WHEREDNGN/Bot.lua:136–146** — emptyMemory: no voluntary-underplay counter per seat

**Fix:** In BotMaster's `heuristicPick` for opponent seats (non-`myTeam`), with low probability (10–20%) substitute `lowestByRank(legal)` even when winners are available, modeling the human sacrifice-play distribution. This forces the ISMCTS rollout to account for opponent tempo-steal scenarios when evaluating whether the bot should accept a "gift" trick.

---

## Summary

Across the five B-51–B-55 angles, two confirmed correctness signals and three human-model gaps were found. **B-51** (Al-Kaboot): the ISMCTS rollout correctly propagates the sweep bonus via R.ScoreRound, but heuristic tiers (below Saudi Master) have no explicit sweep-pursuit guard — a bot defending an in-progress sweep at tricks 7–8 may cede the final trick at the heuristic level. **B-52** (AKA signal): the banner is rendered but has no motion to attract human attention during their turn, and `PickAKA` unconditionally consumes the `akaSent` flag whether the partner is human or bot — wasting the one-time signal and leaking suit information to opponents without coordination benefit. **B-53** (late-game fatigue): the `numWorlds` scaling at BotMaster.lua:514–517 is inverted relative to the actual uncertainty profile — 100 worlds are deployed at trick 6+ where opponent hands are nearly empty (2–6 valid permutations), while only 30 worlds are used at tricks 0–3 where uncertainty is highest; this misallocates sampling budget and does not exploit late-game human predictability. **B-54** (probe Bel): `PickTriple` uses a fixed threshold (K.BOT_TRIPLE_TH = 90) with only ±10 jitter and no bluff-Triple path, making the bot's contract confidence fully readable after 2–3 probe rounds; the human probe-Bel also lowers the effective Triple threshold by +5 via `partnerEscalatedBonus` without any `isBot` guard. **B-55** (sacrifice play): neither `pickFollow` nor the ISMCTS rollout models the opponent's willingness to voluntarily lose a trick to gain a favorable lead; `heuristicPick` for opponent seats always plays `lowestByRank(winners)` (greedy) and no voluntary-underplay event is tracked in `Bot._memory` or `Bot._partnerStyle`.
