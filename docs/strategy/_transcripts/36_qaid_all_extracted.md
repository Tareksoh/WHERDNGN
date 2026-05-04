# 36_qaid_all — extracted rules

**Source:** https://www.youtube.com/watch?v=IEdE-FMXQ00
**Title (Arabic):** كل شي عن القيد في البلوت | 13
**Topic:** Qaid (القيد) — illegal-play penalty mechanics

---

## 1. New / refined glossary terms

| Arabic | Pronunciation | Meaning | Code touchpoint |
|---|---|---|---|
| قيد | qaid | "the recording / the entry" — penalty applied for illegal play or rule-break. Score awarded to the calling team. | `K.MSG_TAKWEESH` (the call); qaid is the resulting score event |
| تكويش / كوّش | takweesh / kawwash | the **act** of declaring the qaid (verb form: "to call qaid"). Synonym usage with قيد in this video — speaker treats them as interchangeable mechanics. | `K.MSG_TAKWEESH`, `K.MSG_TAKWEESH_OUT` |
| قطع | qataʕ | "cut" — illegal trump-ruff or illegal failure-to-follow-suit; the canonical qaid trigger. | `R.IsLegalPlay` violation case |
| امنع اللون | imnaʕ al-lawn | "block the color/suit" — a non-qaid request a player can issue to constrain partner play, used as a softer alternative when the breach is ambiguous. | (informational only) |
| كَوش / يكوش | kawsh / yikoosh | "absorb / let it ride" — informal table custom of letting a small breach slide rather than calling qaid. | (no code mapping) |
| الجلسات / المتعارف | al-jalasaat / al-mutaʕaaraf | "house rules / table convention" — explicit speaker framing that most qaid edge cases are settled by table custom, not formal rules. | (informational) |

---

## 2. Bidding rules

*No bidding rules in this video.*

---

## 3. Trick-play / signal rules

| WHEN | RULE | SOURCE |
|---|---|---|
| Opponent failed to follow suit (qataʕ when they held the led suit) | Eligible qaid trigger — caller announces qaid AND throws their cards face-up to reveal the proof. | 36 |
| Opponent in Hokm did not over-trump when forced ("ما دق بحكم وهو معاه حكم") | Eligible qaid trigger. | 36 |
| Opponent in Hokm did not play the higher trump when obligated to over-cut ("ما كبر بحكم وهو معاه كبير") | Eligible qaid trigger. | 36 |
| Player declared a meld (e.g., 100, 50, sirah) but failed to lay it down ("قال 100 وما نزلها وما فرشها") | Eligible qaid trigger — declaration without showing. | 36 |
| Any form of cheating / signal-flashing (غش, غمز) detected | Eligible qaid trigger but speaker notes denial often stalemates the call — frequently devolves into table dispute. | 36 |
| Score-tally mismatch in Sun (caller said 63 but actual count is 67) | Eligible qaid trigger — incorrect counting can be qaid'd. Speaker notes some tables only enforce on differences large enough to flip the round outcome (1-2 point miscounts often ignored). | 36 |
| Card accidentally exposed (طاحت ورقه بالغلط) | **House-rule dependent** — some tables qaid, some let it ride (kawsh), some say "play on". No universal rule. | 36 |

---

## 4. Decision-tree rules (WHEN / RULE / WHY / MAPS-TO / CONFIDENCE / SOURCES)

### Section: Qaid (new section — Takweesh enforcement)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Opponent visibly fails a must-follow obligation (cut while holding led suit; failed over-trump in Hokm; missed must-show meld) | Caller announces "qaid" AND **must throw cards face-up** to reveal proof. Verbal call without revealing is invalid. | Procedural rule — proof requirement prevents casual / strategic false calls. | `Net.lua` `K.MSG_TAKWEESH` handler — already player-initiated. Reveal-cards step is the proof; if false, penalty inverts. | Definite | 36 |
| You suspect a breach but are not certain | You may **defer the qaid** until end of round (any time before final scoring) but NOT after counting begins. | Allows confirmation through later play, but caps the window so counting is final. | `K.MSG_TAKWEESH` legality window — gate before scoring phase. `(partial wire — confirm timing)`. | Definite | 36 |
| You are certain a breach occurred | Call qaid **early** rather than late — if opponent qaids you first (perhaps for a different breach), they preempt you. | Race condition: first valid qaid wins; the late caller gets nothing even if their evidence is also valid. | `Net.lua` first-call-wins ordering on `K.MSG_TAKWEESH`. | Definite | 36 |
| Qaid is **valid** (breach confirmed by reveal) | Caller's team scores: **26 in Sun** (or Ashkal-as-Sun), **16 in Hokm** (whether 1st or 2nd Hokm). Same score regardless of who was the bidder. | Fixed penalty score — does NOT depend on bidder/defender split (unlike normal round scoring). | `R.ScoreRound` qaid branch — flat-score path, bypass bidder-split. `(not yet wired)` | Definite | 36 |
| Qaid is **false** (caller wrong) | The qaid **inverts** — the falsely-accused team scores instead. | Symmetry rule prevents nuisance qaid spam. | `R.ScoreRound` qaid-inversion branch. `(not yet wired)` | Definite | 36 |
| Qaid is valid AND caller's team has melds (sirah, 50, 100, Belote) | Caller's team **adds their own melds** to the qaid score. | Melds always score for the side that holds them. | `R.ScoreRound` qaid path — add `meldsForTeam(callerTeam)`. `(not yet wired)` | Definite | 36 |
| Qaid is valid AND opposing team has melds | Opposing team's melds are **forfeit** — qaid'd team loses their melds. | Penalty extends to forfeit of declared bonuses. | `R.ScoreRound` qaid path — zero `meldsForTeam(qaidedTeam)`. `(not yet wired)` | Definite | 36 |
| Qaid valid; round was Bel (×2) | Score doubles: **52 in Sun**, **32 in Hokm**. Caller's melds also double (×2). | Multiplier applies to qaid score same as round score, including meld bonus. | `R.ScoreRound` qaid path × `multiplier`. `(not yet wired)` | Definite | 36 |
| Qaid valid; round was Bel ×2 (×3) | Score triples: **48 in Hokm** (and 78 in Sun by extension). Caller's melds triple. | Extension of multiplier rule. | Same as above. | Definite | 36 |
| Card exposed accidentally; player declared 100 but didn't show; cheating detected; score miscount | **House-rule dependent** — three valid resolutions: (a) qaid, (b) kawsh (let it ride), (c) play on. | Speaker explicit: "في النهايه على حسب المتعارف او على حسب الجلسات". No formal rule. | `Net.lua` — these are NOT auto-qaid in code; remain player-discretion. Bot tier should default to "play on" (no qaid) for ambiguous cases. | Common | 36 |
| Disputed cheating: opponent denies the breach, partner doesn't confirm | Best resolution: **kawsh or play on** — even if you have the right, do not let it derail. Speaker explicit recommendation. | Practical / table-harmony reasoning. Affects bot meta-policy: avoid escalating ambiguous breaches. | `Bot.PickSWA` / takweesh-decline path — bots auto-decline ambiguous accusations they observe. `(not yet wired — currently bots never call qaid)` | Common | 36 |

---

## 5. Non-rule observations

**Qaid (القيد)** — the **scored penalty event** triggered when an opponent commits an illegal play and a player calls it out. Literal meaning: "the recording / entry" (as in writing the score down). It is a fixed-score award to the calling team, replacing the normal round score for that hand.

**Trigger conditions** — speaker enumerates **explicit (clear-cut)** triggers and **disputed (house-rule)** triggers:

*Explicit:*
1. Cut/قطع — failure to follow suit when holding the led suit.
2. Hokm-related: failed to ruff (دق) when forced; failed to over-cut (ما كبر) when holding higher trump.
3. Meld declared without being laid down (said 100, never showed).
4. Cheating (غش) — including signaling, peeking, etc.

*House-rule (jalasat-dependent):*
1. Accidentally dropped/exposed card.
2. Score-counting mismatch (small differences often ignored).
3. Saying "50 with Belote" — some tables qaid the redundant declaration.
4. Forgetting to declare a held sirah.
5. Buying Sun with sanʕa — variable enforcement.

**Score impact** — fixed flat score (NOT bidder-split):
- **Sun (or Ashkal-as-Sun):** 26 raw to caller's team.
- **Hokm (1st or 2nd):** 16 raw to caller's team.
- **With Bel (×2):** Sun → 52, Hokm → 32.
- **With Bel ×2 (×3):** Hokm → 48 (Sun → 78 by extrapolation).
- Caller's team **keeps their own melds** (sirah, 50, 100, Belote) added on top.
- Qaid'd team's melds are **forfeit** (do not score even if they were laid down).
- If qaid is **false** (caller wrong), the qaid **inverts** — the falsely-accused team scores instead.

**Player roles** — the call is **player-initiated only**:
- **Caller:** any player who detects the breach. Must (1) verbally announce qaid, AND (2) throw cards face-up to reveal evidence. Verbal call without reveal = invalid (no qaid recorded).
- **Suffering team:** the player who broke the rule + their partner (penalty is team-level, not individual).
- **Timing:** call early if certain — first valid qaid preempts later ones. Speaker emphasizes the race-condition: if you wait and the opponent qaids you for a different reason, your evidence becomes moot. May be deferred until end of round but NOT after counting starts.
- **Reveal requirement:** "هذه طريقه انه لازم ترمي الورق وتكشفه ما تقول قيد وما ترمي الورق ما يعتبر قاعد" — if you don't show cards, the qaid does not register.
- **Discussion/consultation with partner:** speaker notes opponent may **refuse** to allow partner-discussion before the call. Best practice is to either commit the call (throw the cards) or defer.

**Relationship to Takweesh** — speaker uses the verbs **يكوش / تكوش / تكويش (takweesh)** synonymously with قيد throughout this video. Codebase glossary already pairs them: **Takweesh is the call (act of declaring), Qaid is the consequence (the scored penalty)**. The code's `K.MSG_TAKWEESH` is the network message for the call; what `R.ScoreRound` produces afterward is the qaid score event. The distinction is real (call vs. consequence) but speakers rarely separate them lexically — both terms refer to the same procedural event. The video confirms the player-initiated-only design: there is no auto-qaid by the engine.

**Meta-policy note** — speaker's **central thesis** is that most qaid disputes resolve by **table custom (الجلسات / المتعارف)**, not formal rule. Three legitimate resolutions exist for ambiguous breaches: (a) qaid, (b) kawsh (let it ride), (c) "play on" / continue. Speaker explicitly recommends kawsh or play-on for disputed cases ("الحل الانسب طبعا تشيل") — even when the caller is technically correct — to preserve table harmony. **Implication for `Bot.PickSWA` / takweesh validity checks:** bots should be conservative — only call qaid on the **explicit** triggers (the four enumerated above), never on house-rule-dependent ones. The current code design (player-initiated only, no auto-qaid) already aligns with this.

---

**Report:**

- Rule count: **11** decision-tree rules (new "Qaid" section under Section 11 or new Section 12).
- New-terms count: **6** (qaid refined; takweesh refined; qataʕ; imnaʕ al-lawn; kawsh; jalasaat).
- Refined Qaid definition: **Qaid is the scored penalty event** (flat 26 Sun / 16 Hokm + ×N multiplier + caller's melds, forfeit opponent's melds), triggered when a player calls **Takweesh** AND reveals cards as proof. False call inverts. Player-initiated only — no engine auto-detect. Most ambiguous breaches resolve by house rule, not formal qaid; bots should restrict qaid calls to explicit triggers (failed-follow, failed-Hokm-ruff, failed-over-cut, undeclared meld, observed cheat).