# 13_predict_trick — Extracted rules

**Slug:** `13_predict_trick`
**URL:** https://www.youtube.com/watch?v=zCubr1YEJBE
**Title:** توقع الحلَّة | 2 | #احترف_البلوت — "Predicting the trick (outcome)" — Master Baloot ep. 2
**Contract focus:** Both صن and حكم. Mostly Sun examples.

---

## 1. Decision rules (WHEN / RULE / WHY)

### Rule 13-A — Cash points when partner-win is ~100%
- **WHEN:** It's your turn (pos 2/3/4); you can already see the trick will go to خويك (partner) at near-100% probability (e.g., partner played the highest unplayed card and remaining seats can't beat it).
- **RULE:** Play your **largest scoring** card you can (تكبر) — preferably one with نقاط/ابناط (A=11, T=10, K=4, Q=3, J=2). If you must follow suit, "كبر بالشكل" with the biggest in suit; if void, ruff with junk OR shed a high-pointer from another suit ("تكبر والعكس").
- **WHY:** Trick already won — every point you add to partner's pile counts in الحسبة. "كل ما تعطي خويك ابناء تفيدكم في الحسبه".

### Rule 13-B — Save points when opp-win is ~100%
- **WHEN:** Trick will go to opponent (LHO/RHO) at near-100% probability.
- **RULE:** Play **smallest non-scoring** card — "ورق بدون ابناط": 9, 8, 7 in Sun (zero points). If you don't have 7/8/9 in that suit but have ولد + بنت, dump the **ولد (J)** because J is the lowest-point face card in Sun (J=2 vs Q=3 vs K=4).
- **WHY:** Don't feed opp's pile. The "single-point مناطق" matters — losing a Q to opp can flip a marginal round-loss.

### Rule 13-C — Don't dismiss the single-point bracket
- **WHEN:** Choosing a discard onto an opp-winning trick where it "feels small."
- **RULE:** Even a 1-point spread (J=2 vs Q=3) is decisive — "لا تستهين في المنطقه الواحد". Especially when YOU were the مشتري — losing one face card on opp can move the round from making to failing.
- **WHY:** Bidder fails on tied 81/162 (Saudi strict-majority rule); single points decide the boundary. See `R.ScoreRound`.

### Rule 13-D — Pos-3 (after partner already won) example: J vs Q dump
- **WHEN:** Sun, pos-3, partner is winning trick with high card; you hold بنت + ولد of that suit; void in led suit is irrelevant — just discarding into partner's win.
- **RULE:** Dump the **بنت (Q)** onto partner — Q=3 is the bigger pointer; **don't** dump the J (J=2). "البنت والولد واحد الفرق" — but the right one is بنت.
- **WHY:** Maximize "كبر لخويك" point delivery.

### Rule 13-E — Lead-position prediction is 100%
- **WHEN:** YOU are about to lead a trick (الحلة في يدك / البدايه عندك).
- **RULE:** Trick-winner is **100% knowable** before play — "هذا اللاعب تقدر تتوقع الحله رايحه فين بنسبه 100%". Reason: nobody has played yet; you compute who eats the trick by simulating the lead against the highest unplayed card in each opp/partner hand.
- **WHY:** All 3 other plays are still ahead — you have full structural info.

### Rule 13-F — After-partner-played, pos-3 prediction is reduced
- **WHEN:** Partner has already played; you are pos-3 deciding.
- **RULE:** Confidence drops below 100% — speaker says "راح تقل النسبه" — but still high if partner played near-top. You must factor in remaining opp's hand.
- **WHY:** One unknown player remains.

### Rule 13-G — Track the big four cards
- **WHEN:** Always (at every trick).
- **RULE:** Maintain a running mental ledger of which **A (الإكَه), T (العشره), K (الشايب), Q (البنت)** of each suit have been played. "التوقع يعتمد بشكل كبير على متابعة الورق". Without this, prediction is impossible.
- **WHY:** Once these four are dead in a suit, anything else automatically becomes "highest unplayed".

### Rule 13-H — "If they led X, they almost certainly don't have higher than X"
- **WHEN:** An opp leads a non-Ace card in Sun (e.g., leads T, K, Q, J).
- **RULE:** Assume opp does **NOT** hold Ace of that suit — convention: "في البلد بشكل عام اذا كان اللعب واحد لعب اي شيء غير الاكه بنسبه كبيره جدا ما عنده الاكه بنسبه 90%".
  - Lead = T → ~99.99% they don't hold A or higher of that suit.
  - Lead = K → ~95% they don't hold A.
  - Lead = Q → ~90% they don't hold A.
- **WHY:** Players don't lead under their own boss; leading T/K/Q is a "fishing"/setup play that assumes the A is elsewhere.

### Rule 13-I — Caveat to 13-H (deception window)
- **WHEN:** Opp leads K (Shayeb) specifically.
- **RULE:** ~10% chance they're trying to "fish" your T — "هو ممكن يفكر يصير العشره". Otherwise default-assume A is elsewhere.
- **WHY:** Single deceptive lead-pattern carved out by speaker.

### Rule 13-J — When uncertain (~50/50 split), play the "balanced" card
- **WHEN:** Sun, you're pos-2/3 and partner-vs-opp win probability is ~50/50.
- **RULE:** Play the **middle-tier** card by point-value — the **شايب/بنت/ولد** bracket (K, Q, J are 4/3/2 points, none worth 10 or 11, none worth 0). Speaker calls this **توازن في اللعب** ("balance"). Examples:
  - Hand has 10 + Q + J → play **Q** (middle).
  - Hand has K + Q + J → play **Q** (middle).
  - Hand has 10 + Q + 9 → play **Q**.
  - Hand has K + 7 + 9 → play **K** (it's the only middle-tier card; 7+9 are zero, K is the لعبة المتوسطة).
- **WHY:** Hedge — "لو اكلها هذا اللاعب ما راح تندم … لعبت ورقه متوسطه؛ اذا اكل خويك … لعبت ورقه متوسطه". Symmetric regret minimization.

### Rule 13-K — Three-tier card classification (for the balancing rule)
- **WHEN:** Reasoning about Sun card-strength buckets.
- **RULE:** Sun cards split into 3 tiers:
  1. **Top:** A (11), T (10) — the high-pointers, ~10–11 pts each.
  2. **Middle (الصور / ورق متوسط):** K (4), Q (3), J (2) — the شايب/بنت/ولد bracket.
  3. **Bottom (ورق بدون ابناط):** 9, 8, 7 — zero points.
  Speaker: "اقوى شيء في الصن إكَه وبعدين العشره … بعدين بفارق يجي شايب أربع … بنت ثلاثه … ولد … التسع صفر ثمانيه صفر".
- **WHY:** Foundation for 13-A / 13-B / 13-J discard policies.

### Rule 13-L — Hokm: someone playing a non-Ace lead is NOT a 100% read
- **WHEN:** Hokm contract; opp leads non-Ace of trump (or any non-Ace card off-suit).
- **RULE:** Unlike Sun, **Hokm leaves real probability that opp will دق/قطع (ruff)** — "في الحكم احتمال انه واحد ياخذ الحل اذا دق حكم". Apply 13-A/B with a discount; can't go to 100% even when surface-evidence suggests partner wins.
- **WHY:** Hokm has trump as override; even highest-of-led-suit can be ruffed.

### Rule 13-M — Hokm: bidder's partner must over-cover trump-led
- **WHEN:** Hokm; bidder partner (خويك) led trump or someone leads trump in a Hokm round; you hold بنت + 8 of trump; "عندك بنت وعندك ثمانيه".
- **RULE:** Play the **بنت (Q of trump)** — must over-trump if able (Saudi strict over-trump rule). Bidder partner is likely to win the trick anyway with the J/9 in their hand; you contribute the Q's 3 points to partner's pile.
- **WHY:** "في الحكم مجبر تعتلي" + bidder usually holds J/9 of trump → partner takes it → you cashed 3pts to partner.

### Rule 13-N — Hokm pos-3, opp-led, partner (cutter) probably ruffs
- **WHEN:** Hokm; opp led a side suit; you are void and partner has signaled potential trump strength; you hold 7 + Q of led suit.
- **RULE:** Play the **بنت (Q)** even though it gives points away — partner is overwhelmingly likely to ruff (دق بحكم) and the trick goes your team. The trade is +3 pts vs preserving Q for nothing.
- **WHY:** "احتمال خويك يدق بحكم" — given bid history (partner is bidder) it's near-100%; play 13-A logic.

### Rule 13-O — Hokm, opp is bidder, opp leads K-of-trump → don't Faranka, just feed J of trump if you have it
- **WHEN:** Hokm; opp is bidder and leads K of trump; you hold trump + a side-suit Q-only hold.
- **RULE:** Play normally — don't try to "balance" with J — give up the trick cleanly with smallest possible. Don't get cute when bidder has long trump.
- **WHY:** Cross-references Section 10 anti-Faranka rule. Bidder will pull trump anyway.

### Rule 13-P — When unsure between aggressive and conservative, default to balanced (don't speculate with the T)
- **WHEN:** Pos-3 in any contract, partner-vs-opp split feels ~50/50, you hold a 10 in the led suit.
- **RULE:** Some players "تتهور تلعب عشره" (rashly play the T) — speaker advises **don't**. Default to the middle-tier card (Q or J). T is too valuable to gamble.
- **WHY:** The 10 is the second-most-valuable card; only play it when prediction is ~100% partner-win.

---

## 2. Non-rule observations

**Trick-winner prediction algorithm** — the speaker's exact mental procedure:

1. **Read the cards already on the table this trick.** Identify the current leader card (highest in led suit, or highest trump if ruffed).
2. **Look at your own hand** for cards that beat the current leader in the led suit (or in trump if Hokm and you can ruff).
3. **For each unplayed seat behind you,** compute the probability they hold a card that beats the current leader:
   - Subtract: (a) cards already played this round, (b) cards in your hand, (c) cards you've inferred via signals (AKA, Tahreeb, void declarations).
   - The remainder is the "could-still-be-out-there" pool.
4. **Apply lead-pattern priors** (Rule 13-H): if a seat already led non-Ace this round, ~90% they don't hold A of that suit anywhere in their hand.
5. **Output one of three confidence buckets:**
   - **~100% partner wins** → apply Rule 13-A (cash big).
   - **~100% opp wins** → apply Rule 13-B (shed small).
   - **~50/50 uncertain** → apply Rule 13-J (play middle-tier).
6. **Confidence ceiling differs by contract:**
   - Sun: ~100% achievable on lead and pos-2/3 when top cards are dead.
   - Hokm: cap at ~85–90% even with structural certainty — trump-cut option always lurks (Rule 13-L).

**Inputs** — observable game state:
- `S.s.trick.cards[]` (cards played this trick)
- `S.s.trick.leadSuit`
- `S.s.contract.bidType` (Hokm vs Sun changes prediction ceiling)
- `S.s.contract.bidder` (for bidder-team trump-strength prior)
- Per-suit "highest unplayed" derived from `Bot._memory[seat].seenCards` and `S.s.tricks[]` history
- `Bot._partnerStyle[seat]` ledger entries (lead patterns, void declarations)
- Position relative to lead (pos-1/2/3/4)

**Output** — categorical classification (NOT a continuous PDF):
- `{partner_wins, opp_wins, uncertain}` with a boolean for each, plus a confidence-tier from `{near-100, ~85-90 (Hokm cap), ~50/50}`. Speaker doesn't emit fractional probabilities — he uses bucketed thresholds.

**Code-mapping suggestion:**

Two consumption paths, one shared helper:

```lua
-- New helper in Bot.lua, near pickFollow (Bot.lua:1457)
-- Returns: "partner_likely" | "opp_likely" | "uncertain"
-- Plus confidence: "high" (~100%) | "medium" (Hokm cap) | "low" (~50/50)
local function predictTrickWinner(seat, hand, trickState, contract)
  -- 1. Identify current trick leader card
  -- 2. Enumerate cards that could beat it from each unplayed seat
  -- 3. Apply Rule 13-H priors (lead patterns)
  -- 4. Bucket into one of 3 outcomes
end
```

- **`pickFollow` consumer** (Bot.lua:1457) — the **direct/heuristic** path:
  - Branch on `predictTrickWinner` output:
    - `partner_likely + high` → Rule 13-A: pick highest-point legal card in led suit (cash big).
    - `opp_likely + high` → Rule 13-B: pick lowest-point legal card (shed small).
    - `uncertain` → Rule 13-J: pick middle-tier card (شايب/بنت/ولد range).
  - This is a **fast deterministic shortcut** that should run BEFORE invoking the ISMCTS sampler when confidence is high — no need to roll out 100 samples if the trick winner is already known.

- **`BotMaster.PickPlay` ISMCTS sampler** (BotMaster.lua) — the **probabilistic** path:
  - Use `predictTrickWinner` as a **rollout-pruning heuristic**: when sampler considers a candidate play and post-play state shows `predictTrickWinner == high-confidence outcome`, terminate that rollout early using the corresponding bucket's expected delta. Saves rollouts.
  - Also use Rule 13-H priors (~90% no-Ace-after-non-Ace-lead) as a **sampler constraint**: when reconstructing unknown opp hands, drop reconstructions where they hold A of a suit they previously led non-Ace from. Extends H-1 (J/9 of trump pin) to J/9/A/non-trump.

**Key implementation note:** The 100% ceiling for Sun and the ~90% ceiling for Hokm should be **constants** (`K.PREDICT_CEIL_SUN = 1.0`, `K.PREDICT_CEIL_HOKM = 0.9`) so the same helper can serve both; tier (M3lm uses high-conf shortcut, Saudi Master also uses sampler-pruning hook).

---

## 3. New glossary terms

| Arabic | Likely meaning | Context |
|---|---|---|
| توقع الحلَّة (tawaqquʕ al-hilah) | "predicting the trick (outcome)" | Title concept; already noted in glossary as referenced from #03; this is the source episode. |
| الإكَه (al-ikah) | Ace | Already in glossary; used heavily here. |
| ابناء / ابناط (abnaa / abnaat) | "Points/pips" — the scoring value of a card | Recurring; speaker uses both spellings interchangeably. **NEW.** Maps to per-card Saudi point values (A=11, T=10, K=4, Q=3, J=2 in Sun; J=20, 9=14, A=11, T=10, K=4, Q=3 in Hokm trump). |
| ورق بدون ابناط (waraq bidoon abnaat) | "Cards without points" — the 9/8/7 zero-point cards | **NEW.** The "shed-small" target set in Rule 13-B. |
| توازن في اللعب (tawazun fi al-laʕb) | "Balance in play" — playing the middle-tier card under uncertainty | **NEW.** Hedging concept underlying Rule 13-J. |
| الورقة المتوسطة (al-waraqah al-mutawassitah) | "The middle card" — the K/Q/J bracket as a tier | **NEW.** Output of Rule 13-J. |
| الصور (as-suwar) | "The face cards" — collective for K/Q/J | **NEW.** Often paired with المتوسطة. |
| كبر / تكبر (kabbar / tikabbar) | "Play big/play a high-pointer" — the verb of Rule 13-A | **NEW.** Likely already implicit but spell out. |
| المنطقة الواحد (al-mintaqah al-waahid) | "The single-point region" — the J vs Q vs K spread | **NEW.** Used in Rule 13-C. Speaker emphasizes 1-point gap is decisive on round boundaries. |
| دق / يدق (daqq / yidiqq) | "to ruff" | Already in glossary. Reaffirmed here. |
| توقع البدايه (tawaqquʕ al-bidayah) | "Lead-position prediction" — the 100%-knowable case | **NEW.** Context-specific phrasing. |
| تتهور (tatahawwar) | "to be reckless" — speaker's word for over-aggressive T-play | **NEW.** Anti-pattern flag. |

---

## 4. Code mapping (BotMaster.lua / Bot.lua references)

| Rule | Picker site | Status |
|---|---|---|
| 13-A (cash big when partner wins) | `pickFollow` Bot.lua:1457 — partner-winning point-feed branch | `(not yet wired)` — needs `predictTrickWinner` helper |
| 13-B (shed small when opp wins) | `pickFollow` Bot.lua:1457 — opp-winning shed-low branch | `(not yet wired)` — same helper |
| 13-C (single-point matters) | Implicit in 13-A/B; ensure card-value tiebreak picks higher-point shed | `(not yet wired)` — implicit in pickFollow scoring |
| 13-D (Q over J onto partner) | `pickFollow` Bot.lua:1457 — sub-rule of 13-A | `(not yet wired)` |
| 13-E (lead = 100% predictable) | `pickLead` Bot.lua:953 — uses prediction; should set `confidence=high` | `(not yet wired)` |
| 13-F (pos-3 prediction reduced) | `pickFollow` Bot.lua:1457 — confidence factor | `(not yet wired)` |
| 13-G (track A/T/K/Q) | Already partially in `Bot._memory[seat].seenCards` | Existing infrastructure; ensure read-side hook in `predictTrickWinner` |
| 13-H, 13-I (lead-pattern priors ~90% no-Ace) | Sampler hand-reconstruction in `BotMaster.PickPlay` | `(not yet wired)` — extend H-1 pin logic |
| 13-J (balance with middle-tier on 50/50) | `pickFollow` Bot.lua:1457 — uncertainty fallback | `(not yet wired)` |
| 13-K (3-tier card classification) | New constant table: `K.SUN_TIER_TOP`, `K.SUN_TIER_MID`, `K.SUN_TIER_BOT` | `(not yet wired)` |
| 13-L (Hokm prediction cap ~90%) | Helper constant `K.PREDICT_CEIL_HOKM = 0.9` | `(not yet wired)` |
| 13-M (Hokm bidder-partner over-trump cash) | `pickFollow` Bot.lua:1457 — Hokm trump-follow + partner-bidder branch | `(not yet wired)` |
| 13-N (cash Q under partner-cutter scenario) | `pickFollow` Bot.lua:1457 — discard-while-partner-ruffs branch | `(not yet wired)` |
| 13-O (Hokm bidder leads K-trump → no Faranka) | `pickFollow.deceptiveOverplay` anti-trigger | `(not yet wired)` — see Section 4/10 of decision-trees |
| 13-P (don't speculate with T) | `pickFollow` Bot.lua:1457 — gate on `confidence != high` | `(not yet wired)` |

**`predictTrickWinner` placement:** new local function in `Bot.lua` near `pickFollow` (above line 1457). Should be called by both `pickFollow` directly AND by `BotMaster.PickPlay` (BotMaster.lua) as a rollout-pruning hook.

---

## 5. Rule corroboration / contradictions vs existing decision-trees.md

- **Section 4 row "Sun, you are losing-side off-suit follow … Dump HIGHEST"** (sources 05, 09): **CORROBORATED** by Rule 13-A here. Upgrade source list to `05, 09, 13`.
- **Section 4 row "Hokm, you are losing-side trump follow … Dump LOWEST"** (sources 05): **CORROBORATED** indirectly by Rule 13-B/13-L. Upgrade source list to `05, 13`.
- **Section 11 row "Sun, opp plays K or higher in 2nd-position … Infer no card lower"** (sources 05): **CORROBORATED** by Rule 13-H (opp-led non-Ace ⇒ ~90% no-A). Upgrade to `05, 13`.
- **NEW conceptual addition to Section 11:** Lead-pattern prior for ~90% no-Ace-after-non-Ace-lead. Add row.
- **NEW conceptual addition to Section 4:** 50/50 fallback rule (Rule 13-J / "balance / play the middle-tier card"). This is **not currently in decision-trees** — it's the core contribution of this video. Add row to Section 4 (or new Section 4.5 "Uncertainty fallback").
- **NEW infrastructure reference:** the `predictTrickWinner` helper itself is referenced implicitly throughout Sections 4, 5, 8, 9, 10, 11 — every Tahreeb/Tanfeer/Faranka rule depends on knowing who wins the trick. **This video is the canonical source for the trick-prediction primitive itself.**
- **No contradictions found.** This video extends but does not conflict with #01–10.

