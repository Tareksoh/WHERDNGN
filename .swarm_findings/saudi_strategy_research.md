# Saudi Baloot Strategy Research Report

**Codebase:** WHEREDNGN v0.4.11  
**Date:** 2026-05-03  
**Pathfinder agent scope:** Saudi-specific pro strategy vs. current Bot.lua / BotMaster.lua coverage

---

## Sources Consulted

1. **CHANGELOG.md v0.4.3** — cross-references 7 canonical Saudi Baloot PDFs used in the 10-agent scoring audit:
   - نظام التسجيل في البلوت (Scoring System)
   - نظام الدبل في لعبة البلوت (Doubling System)
   - نظام اللعب في البلوت (Play System)
   - ماهو البلوت في لعبة البلوت (Bloot Definition)
   - الثالث (Triple-on-Ace)
   - سر الاحتراف 1 + 3 (Pro Secrets 1 & 3)
2. **Pagat.com** — `pagat.com/jass/baloot.html` (Saudi tournament rules, Ekka/AKA mechanics, locked/open play, meld timing)
3. **Wikipedia** — Baloot article (escalation chain confirmation, Sun restriction at 100 points)
4. **Jawaker blog** — rules source confirming Sun/Hokm priority order, locked/open distinction
5. **Arabic-language resources** — wjaaar.com, arrajol.com, vipbaloot.com (general strategy pedagogy)
6. **Coinche (La Coinche) / Belote** — Pagat.com crossover conventions for J+9 evaluation
7. **Existing swarm findings** — waves 2–8 (C1–C5 clusters), providing codebase-grounded gap analysis
8. **Bot.lua / BotMaster.lua / Constants.lua / Rules.lua** — direct code reading

**Access notes:** Several Arabic-language coaching sites (wjaaar.com, arrajol.com) returned 403 errors or suspended accounts. The vipbaloot.com "10 Commandments" article was generic motivational content with no tactical depth. The most authoritative strategic content came from Pagat.com (Saudi tournament rules), the prior swarm-agent findings (waves 2–8), and the CHANGELOG.md PDF citations.

---

## Section 1 — Bidding Conventions: Hokm vs Sun

### Pro Concept (Sources: Pagat.com, سر الاحتراف, wave2 C1/C2/C3 findings, wave3 C1 findings)

**When to bid Hokm:**  
Saudi pro convention requires at minimum the Jack of trump (بدون الجاك ما تلعب هكم — "without the J, don't play Hokm") with a supporting card (9, A, or length ≥5). The J+9 combination is treated as a synergy threshold — a step-function, not linear — because J captures the opponent 9 and 9 captures the opponent J in cross-ruff positions. Expert players also bid Hokm on 9+A+T with suit length (a robust "secondary trump" holding). Seat-1 bids carry more information weight than Seat-4 bids (maximum information before committing).

The Saudi PDF sources (سر الاحتراف) confirm the J-primacy: "الجاك هو أهم ورقة في الهكم" (the Jack is the most important card in Hokm). Round-1 Hokm is a strong commitment; Round-2 Hokm is frequently used as an escape valve against Ashkal exposure on marginal hands (strength 30–40 in the bot's formula).

**When to bid Sun:**  
Sun requires multi-suit coverage: 2+ honors across 3–4 suits. Void or singleton suits are structurally dangerous (opponents lead the weak suit repeatedly). The canonical Saudi short phrase: "اذا عندك أوراق في كل الأنواع" (if you have cards in every suit). Holding 3 Aces across suits with balanced distribution is the pro threshold.

**Sun vs Hokm priority:**  
Pagat.com confirms Sun overcalls Hokm in both bidding rounds. Round-1 Sun closes further Hokm bids. However, Saudi pro play distinguishes: a lopsided hand with a dominant trump suit (scoring 75+ as Hokm) is better played as Hokm than Sun even if the Sun threshold clears — the long trump suit works harder in a trump contract.

### Current Code Coverage

**Implemented:**
- `suitStrengthAsTrump`: J=20, 9=14, A=11; J+9 synergy +18 (Advanced); J-step penalty ×0.4 for no-J/no-9A hands under 5 cards — Bot.lua:428–462
- `sunStrength`: honors across suits, distribution penalty (−18 cap), long-suit walk bonus, AKQ stopper — Bot.lua:484–529
- Round-1: Sun evaluated first (bids if `sun >= thSun`), then Hokm — Bot.lua:764
- Round-2: head-to-head `sun > bestScore` comparison — Bot.lua:830–836
- Seat-position: handled only for Ashkal eligibility (positions 3–4), not for bid-strength calibration
- TH_HOKM_R1_BASE=42, TH_HOKM_R2_BASE=36 (38 Advanced), TH_SUN_BASE=50 — Constants.lua:263–268 and Bot.lua:34–38

**Gaps:**
- Round-1 lacks the head-to-head Sun vs Hokm comparison present in Round-2. A hand with dominant trump (strength 75 as Hokm) automatically bids Sun if `sun >= thSun`, even when Hokm is structurally stronger (wave3 C1 finding A-11).
- 9+A+T combination (raw strength 35) falls below the R1 jitter floor (~36), so it passes ~50% of the time in Basic mode despite being a biddable Saudi hand (wave2 C1 finding A-01).
- Seat-position is not factored into how the bot reads opponent bids — a Seat-4 Hokm bid (information-rich) should be treated as weaker evidence than Seat-1 (wave5 C3 finding B-04).
- R2 Hokm bids from humans are over-credited: human R2 Hokm frequently covers defensive/escape marginal hands (strength 30–38) but `partnerBidBonus` returns the same +20/+10 regardless of round (wave5 C3 finding B-05).

**Recommended implementations:**
- Add `sun > bestScore` comparison in Round-1 (mirrors Round-2 logic at Bot.lua:830) — slot into Bot.lua:764 before the `return K.BID_SUN` line.
- Lower TH_HOKM_R1_BASE from 42 to 40, reducing BID_JITTER from 6 to 4 (wave2 C1 A-01 + A-04 recommendations).
- Add `bidPositionFactor(bidderSeat)` (1.0 for Seat-1, 0.65 for Seat-4) scaling `partnerBidBonus` return — Advanced-gated (wave5 C3 B-04).
- Distinguish round of bid in state: `s.bids[seat]` + `s.bidRounds[seat]`; reduce partner HOKM bonus by 30% for R2 at M3lm tier (wave5 C3 B-05).

---

## Section 2 — Bel/Triple/Four/Gahwa Decision Logic

### Pro Concept (Sources: نظام الدبل في لعبة البلوت, Pagat.com, سر الاحتراف)

**Bel (Double, ×2):**  
Saudi pro rule from نظام الدبل: the doubling team must be the BEHIND team (score < 100) when the leading team is at 100+. This asymmetry is already confirmed correct in v0.4.3 CHANGELOG. Pro heuristic for Bel as defender: "بل مع الجاك والتسعة في الهكم" (Bel with J+9 of trump). Experts require J+9 as a near-minimum; J alone or 9+A is considered marginal. The locked/open specification is a pro-level decision: locked play prevents trump leads, which favors defenders with strong side-suit Aces; open play rewards strong trump holdings.

**Triple (×3) and Four (×4):**  
The bidder Triples only on a near-certain make — tournament players use the heuristic "triple only if you would have bid the hand at ×1 without hesitation." The defender Fours only on overwhelming defense: both J+9 of trump plus additional stoppers. Saudi pros rarely Four marginal hands; the hand-killer risk at ×4 is too severe.

**Gahwa (match-win):**  
Reserved for near-certain makes. "اذا ما عندك يقين 100%، ما تقول قهوة" (if you are not 100% certain, do not say Gahwa). Saudi tournament practice: the bidder Gahwas only after a Four from a defender, suggesting the defenders mis-assessed the bidder's strength.

**Locked vs open choice (pro-specific):**  
This is a Saudi-specific refinement absent from French Belote. Locked: strong side-suit Aces, weak trump (so opponent cannot profit from trump leads). Open: strong trump, plan to pull trump and run the hand.

### Current Code Coverage

**Implemented:**
- `PickDouble`: `sunStrength + trumpStr` vs BOT_BEL_TH=70; Sun bias +10; scoreUrgency; M3lm sunFail adjustment +8 — Bot.lua:1538–1588
- `PickTriple`: escalationStrength vs BOT_TRIPLE_TH=90; styleBelTendency –8 for habitual Belers — Bot.lua:1623–1651
- `PickFour`: vs BOT_FOUR_TH=110; gahwaFailed –5/–8 — Bot.lua:1653–1679
- `PickGahwa`: vs BOT_GAHWA_TH=135 — Bot.lua:1682–1697
- `partnerEscalatedBonus`: reads contract.doubled/tripled/foured/gahwa flags — Bot.lua:669–707

**Gaps:**
- The Bel locked/open decision (`wantOpen` return) is used in the protocol (`Net.lua` sends it), but no current code consults the locked/open state to adjust card play. When locked, the bot's `pickLead` should completely avoid trump leads even as bidder team — the constraint is never enforced as a play heuristic.
- Near-win conservatism bug (wave7 C1 B-46): `scoreUrgency` returns –8 for the leading team, which suppresses DEFENSIVE Bel even when a clinching Bel is strategically optimal. Context-blind modifier applies to both offensive bidding and defensive escalation identically.
- Opponent urgency is not modeled in the ISMCTS sampler (wave8 C5 B-95): a desperate opponent bidding marginal Hokm at –80 points should widen the trump distribution sampled for that seat, making Bel against them more attractive.

**Recommended implementations:**
- Introduce `context` parameter ("bid" vs "escalate") to `scoreUrgency` so the near-win –8 only suppresses offensive bids, not defensive Bel/Four — Bot.lua:582–592 (wave7 C1 B-46).
- Add `opponentUrgency(oppSeat)` helper; in `PickDouble`, lower BOT_BEL_TH by 5 when `opponentUrgency` is positive and the bid was likely marginal (desperate bid) — Bot.lua:1538 area (wave8 C5 B-95).
- In `pickLead`: when `S.s.contract.locked == true`, suppress trump leads even for bidder team (new guard before the `if isBidderTeam and isBidder` block at Bot.lua:975). The locked flag is already in state; it is simply never read by play logic.

---

## Section 3 — Ashkal Usage

### Pro Concept (Sources: Pagat.com, wave2 C2 finding A-08, wave5 C3 finding B-07)

Ashkal is available to positions 3–4 in bid order (Pagat.com). It transfers the Hokm-bidding partner's role: the Ashkal caller's partner takes the flipped card and becomes declarer in a Sun contract. Pro usage in Riyadh tournament play also allows R2 Ashkal to signal suit strength by color convention — Ashkal on a red-suit flip signals strength in the other red suit; Ashkal in R2 signals a suit of opposite color. This is an information-dense signal rarely exploited by casual players.

The pro threshold: bid Ashkal when Sun-strong but NOT holding the J of the flipped suit (if you hold J of flipped suit, partner's Hokm bid may be bluffing your own card's value; calling Ashkal then is risky).

### Current Code Coverage

**Implemented:**
- `PickBid` Ashkal path: positions 3–4, partner bid Hokm, no prior Sun, Advanced gate checks J-of-flip absence and suit depth ≤2 — Bot.lua:769–806
- BOT_ASHKAL_TH=65 (vs TH_SUN_BASE=50; gap ensures Ashkal only on Sun-strong hands)

**Gaps:**
- R2 Ashkal is not implemented. The code handles R1 Ashkal only (the condition at Bot.lua:769 is inside the `if round == 1` block). Saudi tournament play in Riyadh allows R2 Ashkal as a color-signal convention (Pagat.com).
- The jitter overlap between TH_SUN_BASE and BOT_ASHKAL_TH means a hand with sun=62 randomly bids Sun-direct on one draw and Ashkal on another (wave2 C2 A-08). This creates inconsistent behavior for the same hand strength.
- `partnerBidBonus` treats partner's Ashkal identically to Sun (+15). No escalation decision distinguishes Ashkal-as-Sun from direct Sun (wave5 C3 B-07).

**Recommended implementations:**
- Add R2 Ashkal path inside `if round == 2` block in `PickBid`. Gate on `Bot.IsM3lm()` since R2 Ashkal is a tournament-level signal feature.
- In `partnerBidBonus`, track if the Ashkal partner has a higher or lower sun score than typical (via historical `_partnerStyle` data) to adjust the +15 dynamically.

---

## Section 4 — Card Play Patterns: Opening Lead Conventions, Partner Signaling

### Pro Concept (Sources: Pagat.com AKA/Ekka rules, wave6 findings, wave4 C4 findings, B-20 wave6 C1)

**Opening leads (bidder):**  
Saudi pro convention: bidder pulls trump immediately (highest J/9) to clear opponent ruffs. Exception: trump-poor bidder (<4 trump, or no J+9) cashes side-suit Aces first. This is the "extract trump then run side suits" pattern fundamental to Saudi Hokm.

**Opening leads (defender):**  
Saudi pro rule: "lead shortest suit first" in Sun (wave6 C1 B-20, cited from Kammelna.com coaching). This is the primary distinction between novice and intermediate Saudi Sun play — the short suit exposes opponent voids early, enabling free tricks later. Novice players habitually lead LONGEST first.

**AKA/Ekka signal (Pagat.com):**  
Declaring "Ekka" when leading the highest remaining card of a non-trump suit is a partnership signal. It gives the partner the right to discard freely (no obligation to over-trump) when holding a void. Saudi pro rule: it is ILLEGAL to declare Ekka falsely (when a higher card remains unplayed). The signal is used at trick 2+ when voids have been established, not on trick 1 when no void information is known.

**Fzloky (first-discard signal):**  
Bot convention: high first-discard = "lead this suit"; low (7/8) = "avoid this suit." Applied only to bot-vs-bot play; human first discards are unreliable (wave4 C4, Tier-3 architectural fix already in v0.4.5).

### Current Code Coverage

**Implemented:**
- Bidder trump-pull (highest J/9) with trump-poor exception (<4 trump) — Bot.lua:975–1070
- Fzloky first-discard signal (high/low) bot-only — Bot.lua:922–963
- AKA/Ekka: fires at trick 2+ when bot holds highest unplayed non-trump card — Bot.lua:1453–1493; bot-partner only guard (v0.4.5 Tier-3 fix)
- `styleTrumpTempo` counter accumulates trump-lead timing data — Bot.lua:256–263

**Gaps:**
- Sun opening lead: the bot leads LONGEST non-trump in `pickLead` (Bot.lua:1200–1240). This is the novice mistake. Pro Sun lead is SHORTEST suit first to expose voids early. No shortest-suit Sun lead heuristic exists in the codebase (wave6 C1 B-20: "defining difference between novice and intermediate Sun play").
- AKA gate fires from trick 2 onwards unconditionally. Wave4 C4 finding A-73 identified that on a clean trick 1 (all follow suit), trick 2 AKA is still premature — void inference may be empty. Gate should be "any void known" not "trickNum > 1."
- `styleTrumpTempo` was defined but had zero callers before v0.4.5. The v0.4.5 fix wired it into the defender branch of `pickLead` (M3lm-gated, `saveHighTrump` flag). However, `pickFollow`'s discard selection does NOT consult `styleTrumpTempo` — the bot does not anticipate trump-heavy early leads and hold point cards (wave6 C3 B-29).
- No meld-intent reading: when an opponent declares a Hearts seq3 (7-8-9) at trick 1, the bot does not plan to void in Hearts before that run executes in tricks 2–4 (wave8 C3 B-97).
- No deceptive discard path: Saudi Master pro players deliberately discard high in a suit they want the opponent to avoid (false signal). The bot always discards lowest (wave6 C3 B-32).

**Recommended implementations:**
- Sun opening lead: in `pickLead` when `contract.type == K.BID_SUN`, replace "lead low from longest non-trump" with "lead low from SHORTEST non-trump suit" — Bot.lua:1202 area. Advanced-gated. This is the highest-frequency observable improvement in Sun play.
- AKA gate: replace `trickNum <= 1` guard with `anyVoidKnown` check (wave4 C4 A-73) — Bot.lua:1489.
- Meld-intent defensive planning: in `pickLead` add M3lm-gated scan of `S.s.meldsByTeam` for declared opponent sequences; flag the sequence suit as "likely opponent next lead" and plan a void in that suit by discarding from it in trick 1 if possible (wave8 C3 B-97 — Bot.lua:901 area).

---

## Section 5 — Endgame Play: Saudi-Specific Motifs

### Pro Concept (Sources: Pagat.com, CHANGELOG wave4/8 swarm findings, wave8 C5)

**Post-J+9 exhaustion (A-of-trump lock):**  
Once both J and 9 of trump are gone, the Ace of trump is the highest remaining trump and will win every trump trick. Saudi pro convention: once J+9 are exhausted, stop pulling trump and switch to cashing side-suit non-trump winners. The opponent's A-of-trump represents a last-trick bonus guarantee (+10 card points per Pagat.com) — concede it, secure the other 7 tricks.

**Smother (dump A/T on partner's winning trick):**  
"طلع الآسات والعشرات عند شريكك" (play out Aces and Tens when your partner wins) — cited as the single most exploited gap in Saudi casual play. The bot's smother already fires (Bot.lua:1292–1327); humans miss this 30–50% of the time (wave6 C1 B-19 citing Kammelna.com forum commentary). The bot does NOT plan to harvest opponent-held A/T cards into bot-winning tricks.

**Locked/open play endgame:**  
In locked play the trump suit cannot be led. Strong side-suit Aces become guaranteed winners once opponents are void. This is the locked-play profit scenario Saudi pros exploit: bid Bel with locked to guarantee side Aces run.

**Al-Kaboot (sweep, 25/44 pts):**  
Approaching a full-sweep line (all 8 tricks) earns 25 gp in Hokm, 44 in Sun — bypassing card-point rounding. Saudi pros recognize this as a match-altering threshold that changes play strategy: once a sweep is achievable, abandon individual trick optimization and commit to sweep-or-fail.

### Current Code Coverage

**Implemented:**
- Ace-exhaustion window (B-96): after trick 3, if all side-suit Aces observed played, switch from trump-pull to cashing non-trump — Bot.lua:989–1019 (Advanced+)
- J+9 trump-lock detection (B-98): once both J and 9 are in the played/held pool, switch to cashing side Aces — Bot.lua:1038–1068 (Advanced+)
- Smother: dumps A/T on partner-winning tricks — Bot.lua:1292–1327
- `gahwaWonGame` terminal boost in ISMCTS rollout: ±10000 — BotMaster.lua:545–549

**Gaps:**
- Post-J+9 A-of-trump lock (wave8 C5 B-98 — note: different from the B-98 in Bot.lua which is the J+9 switch): when J and 9 are gone but A-of-trump is still in an opponent's hand, the bot does not model "opponent has last-trump guarantee — stop pulling trump, cash non-trump instead." The `pickLead` bidder branch (Bot.lua:1069) falls through to `highestTrump(legal)` even when the highest remaining trump is the opponent's Ace.
- No harvest-opponent-A/T heuristic: the bot smothers its OWN A/T on partner's wins, but does not plan trick sequences to force an opponent to play their hoarded A/T into a bot-winning trick (wave6 C1 B-19).
- No sweep-pursuit mode: no code path detects "all 8 tricks achievable" and shifts to sweep-optimization. The ISMCTS rollout values a sweep via R.ScoreRound correctly, but heuristic `pickLead` has no "lock-sweep" flag.
- Locked-play card play (see Section 2): when `contract.locked == true`, trump leads are supposed to be illegal; no enforcement in `pickLead`.

**Recommended implementations:**
- Opponent A-of-trump guard: in `pickLead` bidder branch, after the J+9 lock check (Bot.lua:1038), add: if J+9 are gone AND the highest remaining trump is A (not in our hand), treat as "A-of-trump locked against us" — switch to highest non-trump rather than `highestTrump`. Bot.lua:1069 area.
- Smother exploitation: at M3lm tier, track `_memory[opp].hoarding[suit]` when an opponent fails to smother on a partner-winning trick (A/T unplayed). In `pickLead`, prefer leading that suit to force the hoarder to play into a bot-winning trick (wave6 C1 B-19).

---

## Section 6 — Match Strategy: Conservative vs Aggressive Near Target=152

### Pro Concept (Sources: نظام التسجيل في البلوت, Pagat.com tie rules, wave7 C1/C2 findings)

**Near-win (leading team):**  
Saudi tournament convention: when your team is within 10–15 points of 152, play conservatively — avoid Gahwa risk, accept small positive rounds, let opponents blunder into escalations. Declaring Bel/Four defensively when near-win to clinch (not to maximize points) is standard pro play. The goal shifts from "maximize score" to "secure the match."

**Near-loss (trailing team):**  
When trailing by 80+, escalate aggressively. Pros use this window to swing match points with Gahwa; a desperate Gahwa attempt by the trailing team is a culturally expected play pattern in Saudi tournament Baloot.

**Match-point calculus (Sun vs Hokm near target):**  
Sun earns more game points (26 available vs 16 in Hokm) but has a higher failure risk. A team at 140/152 that bids Sun risks overshooting and triggering a new deal if both teams reach 152 simultaneously. Saudi tie rule: "play another hand to break the tie" — ties at 152+ require another round.

**Kawesh near-win:**  
Calling Kawesh (hand annulment) when near-win is dangerous — the opponent gets a fresh deal and may receive a powerhouse hand. Saudi pros suppress Kawesh when their team needs only 1–2 more points to win (wave3 C1 A-13 finding).

### Current Code Coverage

**Implemented:**
- `scoreUrgency`: near-win –8 (conservative), near-loss +12 (desperate), far-behind +6 — Bot.lua:582–592
- `matchPointUrgency` (M3lm): finer-grained curve; opponent gahwa-history factor; capped at ±10 — Bot.lua:607–660
- `s.target` correctly read in all urgency calculations; configurable via `/baloot target N`

**Gaps:**
- Near-win conservatism applies to DEFENSIVE Bel too (wave7 C1 B-46). A near-win bot should be MORE willing to Bel a marginal opponent contract to clinch — but `scoreUrgency(myTeam)` returns –8 (raises Bel threshold) even when the clinching Bel is the optimal play.
- Kawesh is called unconditionally regardless of match position (wave3 C1 A-13). A bot at 150/152 should not redeal.
- Opponent score-urgency is not modeled in the ISMCTS sampler (wave8 C5 B-95): a desperate opponent bidding at –80 points should expand their sampled hand distribution.
- `_partnerStyle.gahwas` and `.fours` counters are accumulated but not fed back into urgency calculations for the "careful loser" pattern — a human team at –80 that is playing tightly should dampen the bot's `+6` aggression (wave7 C1 B-50).

**Recommended implementations:**
- Context-discriminated `scoreUrgency`: introduce `context` = "bid" | "escalate"; near-win –8 suppresses only bids (context="bid"); for escalation (context="escalate"), near-win should return +8 (clinching Bel is more valuable) — Bot.lua:582–592 + all 6 call sites.
- Kawesh score guard: in `Bot.PickKawesh`, add `if matchPointUrgency(R.TeamOf(seat)) < -3 then return false end` — suppress Kawesh when the bot's team is near-win (wave3 C1 A-13). Bot.lua:1755.
- `opponentUrgency` helper: mirrors `scoreUrgency` from the opponent's perspective; use in `PickDouble` to lower BOT_BEL_TH by 5 for desperate-opponent bids; use in `BotMaster.sampleConsistentDeal` to widen trump distribution for desperate bidders (wave8 C5 B-95).
- Careful-loser damping: in M3lm `matchPointUrgency`, before applying the `+6` far-behind boost, check opponent team's total `fours + gahwas` history. If zero escalation history (careful style), reduce +6 to +2 (wave7 C1 B-50).

---

## Section 7 — Pro Concepts with Partial or No Implementation

The following Saudi-specific pro concepts were found in sources or swarm findings but have minimal or zero implementation:

| Pro Concept | Source | Current Code | Status |
|---|---|---|---|
| Sun: lead shortest suit first | Wave6 C1 B-20, Kammelna.com coaching | pickLead leads LONGEST (novice pattern) | NOT IMPLEMENTED |
| Locked play: no trump leads | Pagat.com, نظام اللعب | locked flag in state, never read by pickLead | NOT IMPLEMENTED |
| Seat-position bid-strength calibration | Wave5 C3 B-04 | bidPos used only for Ashkal gate | NOT IMPLEMENTED |
| R2 Hokm as escape/weaker signal | Wave5 C3 B-05 | partnerBidBonus round-blind | NOT IMPLEMENTED |
| Meld silence vs crushed meld | Wave6 C2 B-24, Wave6 C3 B-30 | PickMelds always declares all | NOT IMPLEMENTED |
| Meld-declared suit as lead-intention signal | Wave8 C3 B-97 | meld pins in sampler only, no play read | NOT IMPLEMENTED |
| Post-J+9 A-of-trump concession | Wave8 C5 B-98 | J+9 switch exists; A-lock not modeled | PARTIAL |
| Deceptive discard (false Fzloky signal) | Wave6 C3 B-32 | Bot always discards lowest, no deception | NOT IMPLEMENTED |
| AKA void-aware gate | Wave4 C4 A-73 | gates on trickNum > 1, not void-known | PARTIAL |
| Opponent bid-round reading (R1 vs R2) | Wave5 C3 B-05 | partnerBidBonus round-blind | NOT IMPLEMENTED |
| Kawesh near-win suppression | Wave3 C1 A-13 | Kawesh called unconditionally | NOT IMPLEMENTED |
| Near-win context-discriminated escalation | Wave7 C1 B-46 | scoreUrgency context-blind | NOT IMPLEMENTED |
| Smother planning (harvest opponent A/T) | Wave6 C1 B-19 | bot smothers own A/T only | NOT IMPLEMENTED |
| Bot SWA dispute (deny invalid claims) | Wave6 C2 B-26 | bots auto-accept all SWA | NOT IMPLEMENTED |

---

## TOP 5 Strategy Gaps Summary (200-word chat version)

The five most impactful gaps between Saudi pro strategy and the current bot:

**1. Sun opening lead (Shortest suit first, NOT longest).** Saudi pros and Kammelna.com coaching universally identify leading the shortest suit first in Sun as the beginner-to-intermediate boundary. The bot currently leads longest non-trump — the novice error. Fix: one-line change in `pickLead` for Sun contracts.

**2. Near-win Bel suppression (context-blind scoreUrgency).** When the bot is winning by 127/152, `scoreUrgency` raises the Bel threshold by 8, making the bot LESS likely to clinch with a defensive Bel even when that Bel wins the match. Saudi pro play is the opposite: near-win teams Bel aggressively to close. Fix: context parameter distinguishing offensive bids from defensive escalation.

**3. Locked play trump-lead enforcement.** When the Bel is "locked," Saudi rules forbid trump leads. The bot never reads the `locked` flag during card play, leading trump freely even in locked contracts. This is a rules-level gap, not just strategy.

**4. Post-J+9 A-of-trump concession.** The bot knows to switch off trump-pull after J+9 are exhausted (Ace-exhaustion and J+9-lock branches exist), but does not model the opponent holding A-of-trump as a last-trick guarantee. It continues to lead into A-of-trump when it should redirect to non-trump cash.

**5. Opponent urgency in ISMCTS sampling.** A desperate opponent bidding at –80 points commits marginal Hokm hands that a neutral opponent would pass. The bot's ISMCTS sampler applies uniform strong-card bias to all bidder seats regardless of score position. Expanding the trump distribution for desperate bidders would make defensive Bel more attractive and rollout decisions more accurate.

---

*Report complete. All file:line references are absolute paths under `C:/CLAUDE/WHEREDNGN/`.*
