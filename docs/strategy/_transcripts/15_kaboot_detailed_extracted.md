# 15_kaboot_detailed — extracted

**Source:** الكبوت في البلوت ( شرح مفصل ) — https://www.youtube.com/watch?v=PPW4uSWTirA
**Topic:** Al-Kaboot (كبوت) — full mechanic, scoring, Kaboot-Maqloob (كبوت مقلوب), and Qaid-vs-Kaboot endgame interaction.

---

## 1. Definitions / new terms

| Arabic | Translation | Notes |
|---|---|---|
| كبوت (Kaboot) | sweep — bidder team wins all 8 tricks | Already in glossary. Confirmed: bonus = 250 raw Hokm (`K.AL_KABOOT_HOKM`), 220 raw Sun (`K.AL_KABOOT_SUN`). Author quotes the post-multiplier figures **44 (Sun)** and **25 (Hokm)** — i.e. final score-sheet pips after standard scaling, matching the constants. |
| كبوت من يد / كبوت من يدين (kaboot min yad / min yadayn) | "single-hand sweep" vs. "two-hand sweep" | Single-hand = one player wins all 8 tricks alone. Two-hand = bidder + partner alternate captures. Identical scoring; "two-hand" is the more aesthetically prized variant ("متعه اللعب"). |
| كبوت مقلوب (Kaboot Maqloob) — "inverted Kaboot" | Sun-only. **Defenders sweep against the bidder.** Worth ~88 (double a normal Kaboot — 44×2). Some house rules score it as a normal Kaboot (44). | New term — not in glossary. Triggers: bidder team must lose all 8 tricks AND lead-of-trick-1 belongs to bidder team. House-rule variation on whether the led card must specifically be Ace. |
| كسرت كبوت (kasart kaboot) | "I broke the Kaboot" | Defender's defensive milestone — first trick captured. Already informally referenced in decision-trees Section 7. |
| تخريب الكبوت (takhreeb al-kaboot) | "sabotaging your own Kaboot" | Bidder-side tactic: when the round is **doubled (Bel)**, intentionally feed defenders one trick so the score posts at the (higher) Bel multiplier rather than the (lower) Kaboot bonus. |
| تقيد / يقيد على نفسه (yiqayyid ʕala nafsuh) | "to call Qaid (illegal-play / Takweesh) on oneself" — verb form | Already partly in glossary as "Qaid". Verb usage here is a defender's spoiling tactic — see Section 4. |

---

## 2. Decision rules (WHEN / RULE / WHY) — for `decision-trees.md` Section 7

### Offensive (Kaboot pursuit)

| WHEN | RULE | WHY |
|---|---|---|
| Bidder team has won tricks 1+2 cleanly AND hand-shape is sweep-shaped (top suits + trump cover or singleton-supplied partner) | **Switch into Kaboot-pursuit mode from trick 3 onward** — hold strong cards back, prefer plays that keep partner in the lead. | Author walks both Sun and Hokm sweep examples starting trick 1; pursuit decision is essentially "if the path looks clear after the first 1-2 tricks, commit." |
| Hokm; bidder leads trump twice (e.g. ربع بالولد then second trump pull); both opponents follow trump and partner has cut a side suit | **Pursue Kaboot.** Trump is gone from opponents → free roll on side suits. | Worked example in transcript: J then second trump-lead clears all opp trumps; switch to Sun-style side-suit cycling for tricks 3-8. |
| Sun; partner has Tahreeb-discarded a high card to you in trick 1-2 (e.g. partner gives you the Q of your Ace-led suit) | **Treat partner-Tahreeb-after-clean-win as a Kaboot-pursuit signal.** Continue cycling top cards in their corresponding suits; rotate leads partner→you→partner. | Tahreeb's purpose here doubles as "I have cover; you can keep sweeping." |
| Round is **Bel'd (doubled)** AND Kaboot is reachable AND Bel-multiplier-score > Kaboot-bonus-score | **Optionally sabotage your own Kaboot (تخريب الكبوت)**: feed defenders 1 trick so final scoring posts at the Bel multiplier instead of the Kaboot constant. Sun: Bel = 52 vs Kaboot = 44 → sabotage. Hokm: Bel = 32 vs Kaboot = 25 → sabotage. ×3/×4 even more so. | Some house rules instead **double the Kaboot itself** under Bel — in those tables don't sabotage. Bot must read house-rule flag. |

### Defensive (preventing opponent's Kaboot)

| WHEN | RULE | WHY |
|---|---|---|
| You are defender; opponents have won tricks 1+2 cleanly; you suspect a sweep | **Defensive Qaid-bait (تقيد عليه)**: deliberately call a wrong Qaid against the bidder to force a 26-pt (Hokm: 16-pt) trick-point swing instead of letting the 44/25 Kaboot bonus land. | Wrong-Qaid penalty is *less than* a Kaboot bonus, so defenders prefer it as the "lesser of two evils" outcome. |
| You are defender; bidder team has won tricks 1+2; opponent (you/partner) **cuts in a wrong suit** mid-round (illegal-shape play designed to bait the bidder into calling Qaid) | **Bidder-side counter:** do NOT call Qaid yet — request **Kaboot adjudication instead** ("اطلب كبوت"). The bidder must then explicitly walk through the remaining tricks proving the sweep is forced. | If bidder calls Qaid greedily and the cut was a setup, bidder loses Kaboot bonus (gets 26/16 trick-points only). Counter: claim Kaboot, show the proof. Saudi rule lets bidder choose Qaid OR Kaboot-claim. |

### Mid-round triggers — pursuit/abandonment

| WHEN | RULE | WHY |
|---|---|---|
| Bidder; tricks 6-7 won, trick 8 hand reduces to a card you cannot certainly take | **Abandon Kaboot pursuit** — accept loss of trick 8. | Standard SWA-equivalent verification: if the last trick isn't forced by hand-shape (no top of led suit, no high trump), Kaboot is dead; play normally for trick-bonus instead. |
| Bidder claiming Kaboot (after defender Qaid-bait); your hand has the top card in every remaining suit + cover | **Eligible to declare Kaboot now** — speak the line ("اللعب كبوت") and walk the proof. | Saudi adjudication procedure: Kaboot-claimant must demonstrate forced-win sequence aloud. |
| Bidder claiming Kaboot but hand reveals a "gap" suit (no top + can't reach partner) | **Kaboot claim FAILS — Qaid sticks against bidder.** This is "false SWA-like" — a wrongful Kaboot claim costs the bidder. | Author: "هذا يعتبر سوا خاطئ" (this counts as a false SWA). Defense risk inverted. |

### Hand-shape signals (pre-trick-1, used to set Kaboot ambition)

| WHEN | RULE | WHY |
|---|---|---|
| Sun; you hold A+T+(K or J) in 2 suits, plus an A in a third | **Kaboot-feasible hand** — bid Sun and plan for sweep. | Worked example in transcript: A-Hass + A-Sbeet + A+T-Shareeha + Ace-routes ≈ instant SWA-shaped. |
| Hokm; you hold J+9+A of trump (or J+9 + 1 cover trump) AND a singleton or void in 1 side suit AND partner has shown supply (Tahreeb / cut) | **Kaboot-feasible hand** — pull trump twice to clear opps, then cycle. | Worked example: ربع بالولد twice, then Sun-style A-T cycling. |
| Either contract; ≤2 honors total in hand AND no void/singleton | **Not Kaboot-shaped** — bid for make only; Kaboot pursuit triggers should NOT activate. | Hand needs explicit reach into all 4 suits (top-card or partner-supply) to even attempt sweep. |

---

## 3. Worked examples / corroboration

- **Sun Kaboot from one hand:** bidder leads Ace of led-suit, captures; T (10), then K (شايب), continues with other-suit Ace, then K of new suit — all 8 tricks one-handed. Confirms "single-hand sweep" mechanic.
- **Hokm Kaboot two-handed:** bidder leads J (الولد) of trump, partner follows trump, opp trumps, opp Tahreebs a high (e.g. K of side suit), bidder takes; second trump lead clears opps; partner takes via cut on trick 4-5; bidder cycles A+T of remaining suits; both AKA'd to prevent late cuts. Walks Hokm sweep with 2 AKA calls.
- **Scoring math (transcript-explicit):**
  - Sun Kaboot: 44 raw round-pips (matches `K.AL_KABOOT_SUN`=220 with the standard ÷5 score-sheet conversion the addon uses; or the non-multiplied raw view depending on house). With بلوت/سره/Belote melds: add melds normally. Defender melds **also forfeited to bidder** when bidder makes Kaboot against bidder-team-defender (rare configuration).
  - Hokm Kaboot: 25 raw round-pips. With sره (20) → 27. With بلوت (20) → 29. With 50-meld → 30.
- **Bel + Kaboot interaction (house variation):**
  - Variant A (transcript primary): Bel doesn't multiply Kaboot — Kaboot constant pays out flat. Bidder may sabotage own Kaboot to chase Bel multiplier.
  - Variant B: Bel × Kaboot stacks. No sabotage incentive.
- **Defender Qaid-bait sequence (transcript primary tactic):**
  1. Bidder is sweeping; 3rd or 4th trick.
  2. Defender intentionally plays an off-shape card (cut wrong suit, void-claim wrong, etc.).
  3. Defender then calls Qaid against the bidder (knowing it's wrongly applied).
  4. **If bidder accepts the Qaid:** defenders score 26 (Sun) / 16 (Hokm) — the Qaid penalty — and Kaboot is dead. Net: defender wins ~26 instead of losing 44 = ~70-pt swing.
  5. **If bidder declares Kaboot instead:** bidder must walk the proof. Success → 44/25 + opponent-meld forfeit. Fail → Qaid sticks against bidder.

---

## 4. Non-rule observations

**Al-Kaboot pursuit triggers (offensive)** — Saudi convention is to commit to pursuit **as early as trick 3** if the first two tricks resolved cleanly (bidder takes both with top cards, partner shows supply via Tahreeb or natural follow). Unlike the v0.5 trick-8 sweep-pursuit logic which only switches into pursuit at the very last trick, this transcript supports an **earlier promotion**: any trick where (`bidder team trick count` ≥ 2 AND `hand-shape Kaboot-feasibility` holds AND `no opp cut occurred`) should flip a `kabootMode = true` flag on the bidder. From there, lead selection prefers continuation (top cards in fresh suits, alternating with partner) over equity-grinding plays.

**Al-Kaboot defense (defender)** — primary defensive tool is **Qaid-bait (تقيد عليه)** — deliberately call a *wrong* Qaid to swap a 44/25 Kaboot bonus for the smaller 26/16 trick-point penalty. This is a uniquely-Saudi defensive trick that assumes both teams play bookkeeping rather than card-correctness. Secondary tool: when defending and forced to discard, dump the suit you LEAST want bidder to lead next (anti-Tahreeb / Tanfeer-style; opp is winning). Tertiary: **never call Qaid as bidder during a suspected Kaboot run — request Kaboot adjudication instead**, because if the defender pre-baited a Qaid your Kaboot bonus dies the moment you accept.

**Hand-shape signals** — Kaboot is reachable when (Sun) **two complete A+T pairs + one extra A**, OR (Hokm) **J+9 of trump + 1 cover trump + 1 void/singleton suit + partner-supply signal**. With fewer than this the bot should bid for make and not promote pursuit. The transcript also implies that **"clean trick 1+2"** (no opp cut, no opp top-card surprise) is a necessary trigger — without it, abandon Kaboot ambition immediately.

**Pivot decisions** — abandon pursuit when: (a) opponent **cuts in any suit** before trick 6 (single cut kills Kaboot in Hokm; cut on a high in Sun usually kills it); (b) defender **calls Qaid mid-round** AND the call appears wrong (defensive bait — bidder should pivot to *Kaboot claim*, not Qaid acceptance — but if hand can't prove it, pivot to standard play); (c) round is **Bel'd** AND Bel-multiplier > Kaboot-bonus AND house plays "Bel doesn't multiply Kaboot" — actively *sabotage* your own Kaboot to land at the higher Bel score (تخريب الكبوت); (d) trick 7 hand-state shows you cannot 100%-take trick 8.

---

## 5. Open questions / contradictions

- **Kaboot-Maqloob lead-card requirement:** transcript reports a house-rule split — some require the bidder's first card to be specifically the **Ace** of the led suit; others accept any card. Bot needs a configurable flag (default: any card permitted, more permissive).
- **Bel × Kaboot stacking:** house-rule variation. Default the addon to **Variant A (no stacking, sabotage incentive exists)** because the transcript treats it as the "majority" rule, but expose a setting.
- **Defender meld forfeit on Kaboot:** transcript states bidder takes opp melds when Kaboot lands against opp who was the bidder (Kaboot-Maqloob case). Reverse direction (bidder Kaboots own bid → does bidder take defender melds?) — the transcript implies **no** for normal Kaboot ("ما راح تاخذ مشاريع الخصم" when you're the bidder making Kaboot). Confirm against `R.ScoreRound`.
- **Earlier-trigger pursuit conflict with v0.5 logic:** existing trick-8 sweep-pursuit logic in `pickLead` Bot.lua:953 fires only at `#tricks==7`. This source supports an earlier `#tricks>=2` trigger gated on hand-shape feasibility + clean-tricks-so-far. **Requires new helper** `Bot._kabootFeasible(seat, hand)` and a `S.s.kabootPursuit` flag in state.
- **MAPS-TO sites for the Qaid-bait logic:** defender-side Qaid-bait isn't a play-picker decision — it's a Takweesh-call decision. Lives in whichever module owns Takweesh decision-making (search `K.MSG_TAKWEESH` callers in `Net.lua`/`Bot.lua`). Not yet wired.
