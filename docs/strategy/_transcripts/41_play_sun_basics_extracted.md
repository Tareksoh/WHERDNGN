# 41_play_sun_basics — extracted rules

**Source:** https://www.youtube.com/watch?v=wvFAxUMggnY
**Title (Arabic):** طريقة لعب الصن في البلوت للمبتدئين | 8
**Title (English):** How to play Sun in Baloot — for beginners, ep 8
**Slug:** 41_play_sun_basics
**Topic:** Sun (الصن) play tutorial — absolute beginner level. Establishes
the trick-taking primitives, card-ordering convention specific to Sun,
meld-declaration timing, must-follow rule, and the "no looking at past
tricks" rule. Light on strategy; the speaker explicitly defers all
complex play to the upcoming Hokm episode.

---

## Section 1 — Summary

The video walks a beginner through a single Sun round from the dealer's
right (the opening leader). The speaker uses simplified phrasing
throughout and emphasizes that **Sun is mechanically simple compared to
Hokm**. The two foundational rules are stated up-front: (1) the bigger
card "eats" (يأكل) the smaller, and (2) you **must follow the led suit**
if able. The speaker then walks through hand-arrangement conventions
specific to Sun — alternating colors, and crucially the **A-T-K-Q-J
descending rank order** (different from Hokm's J-9-A-T-K-Q trump order).

Melds (سيرة / مشروع) are declared verbally **before** playing the first
card; the cards forming the meld are physically displayed on the second
trick. If the holder plays before announcing, the meld is forfeited
("ما يحتسب").

The video covers the must-follow rule with concrete examples: when void
in the led suit, the player may discard any card ("يقطع") — but in Sun
**this is just a discard, not a ruff** since there is no trump. Several
trick-resolution examples follow, including a touching-honors signal
(partner playing T under your A implies they hold the K).

The speaker introduces **الحلة** (the trick pile) and the rule that
**revealing past tricks is illegal** (يتقيد عليك = you get Qaid'd). The
sole exception: revealing an opponent's pile to prove they made an
illegal play or cheated. The video closes by saying Sun is "very, very
easy" with no complexity ("ما في تعقيد"); the meaty material is in the
Hokm episode.

---

## Section 2 — Decision rules extracted

| # | WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|---|
| 1 | Sun, any position; you are not leading and you hold ≥1 card of the led suit | **MUST follow suit** — illegal to discard otherwise | Saudi must-follow rule (already enforced); failure = Qaid (26 raw to opp) | `R.IsLegalPlay` (Rules.lua) — already enforced; `pickFollow` Bot.lua:1457 already gated by legality | Definite |
| 2 | Sun, any position; you are void in the led suit | You may **discard any card** (يقطع) — there is no must-ruff in Sun (no trump exists) | "يقطع باي شيء" — speaker explicit; Sun has no trump, so no ruff obligation | `R.IsLegalPlay` Sun branch — discard is unconstrained when void | Definite |
| 3 | Sun, any trick, you hold a meld (سيرة / سرى / ملكي = K+Q same suit) AND it is your first time to play in the round | **Announce the meld VERBALLY before playing the first card** ("سيرة" / meld name); failure to announce = forfeit ("ما يحتسب") | Saudi meld-declaration discipline: timing matters; declaration must precede the first played card | `Bot.PickMelds` — declaration timing constraint; meld score forfeited if declared post-play `(legality already gated; declaration-timing rule should be confirmed in Rules.lua)` | Definite |
| 4 | Sun, you announced a meld in trick 1 | **Display the meld cards physically in trick 2** ("ثاني اكله بينزل المشروع") | Saudi meld-display protocol — declared trick 1, shown trick 2 | `Bot.PickMelds` display branch — already partially encoded `(verify trick-2 display timing)` | Common |
| 5 | Sun hand arrangement (pre-play) — descending rank order within a suit | Order is **A → T → K → Q → J** (high to low). Distinct from Hokm trump order (J → 9 → A → T → K → Q). | Sun rank = `K.RANK_PLAIN`; A=11, T=10, K=4, Q=3, J=2 (then 9/8/7=0) | `K.RANK_PLAIN` in Constants.lua — already correct; mentioned for sampler / display sort | Definite |
| 6 | Sun trick resolution; led suit was X, all four cards played | Winner = **highest-rank card OF THE LED SUIT** only. Off-suit discards CANNOT win (no trump in Sun). | "اكبر شيء في [الشكل]" — speaker walks through 4 examples confirming this | `R.TrickWinner` Sun branch — already enforced | Definite |
| 7 | Sun, partner plays T (Ten / كه / العشرة) under your A on a trick you are winning | Infer: **partner holds the K (Shayeb / شايب) of that suit** (touching-honors signal). Partner would not waste T unless K is safely with them. | Saudi touching-honors convention; Speaker example: "يعطيك الشايب اكبر من التسعة عشان يزودك نقاط" — partner plays T to magnify your trick (Takbeer behavior) | `pickFollow` partner-supply read; new ledger key `Bot._partnerStyle[partner].toptouchSignal` `(not yet wired)` — corroborates rule already in Section 6 of decision-trees.md (sources 05 + 41) | Definite |
| 8 | Sun, partner plays K under your A | Infer: **partner holds the Q (Bint / بنت)** — next-down touching honors. | Same convention, one rung down | Same ledger as #7 | Definite |
| 9 | Sun, partner is winning; you are forced to follow (or able to play higher than the current winning card without leading); your high card would magnify the trick value | **Play your HIGH card** (Takbeer / تكبير) — donate ابناء to partner's trick | Speaker example: partner wins with A; you play T to "زود نقاط" (add points). Confirms Takbeer rule for Sun. | `pickFollow` partner-certain-winning branch `(not yet wired)` — corroborates Section 4 Takbeer rule (sources 21,22,23 + 41) | Definite |
| 10 | Any contract, any position; opponent has taken a trick (الحلة) and put it face-down | **DO NOT reveal / inspect the trick pile** (ممنوع تكشف الحلة) — illegal play, you will be Qaid'd | Saudi rule: post-trick info is sealed; revealing = Qaid penalty | `R.IsLegalPlay` (or game-flow rule) — already enforced player-side; bot must never request to reveal | Definite |
| 11 | Any contract; you suspect opponent made an illegal play or cheated | **You MAY reveal the opponent's trick pile** to call them out (تقيد عليه / تكويش) | Single legitimate exception to rule #10 — formal accusation flow | `K.MSG_TAKWEESH` flow in Net.lua — player-initiated; bot trigger discipline already restricted to explicit triggers (per video #36) | Definite |
| 12 | Any contract; trick is taken | Each player takes their own team's tricks and stacks them in front of the team. | Speaker recommends "كل واحد يشيل حليته" (each takes their own pile) to avoid confusion. Either teammate may collect, but consistent collector reduces error. | Display / book-keeping; no decision logic. Game-state already tracks `S.s.trickHistory` per team. | Common |
| 13 | Sun, any trick, leader is choosing what to play | The trick **is led with whatever card the leader plays**; led suit is determined by the leader's card, not pre-declared. | Standard Saudi convention — no separate "lead-suit announcement" phase | `pickLead` Bot.lua:953 — already encoded; led suit = first card's suit | Definite |
| 14 | Sun, you are void in led suit and discard | Speaker calls this **يقطع** ("to cut") — but the term is purely discard semantics in Sun (no trump exists). The Saudi noun "قاطع" applies. | Lexical: "قطع / يقطع" usually means trump-ruff in Hokm. In Sun the verb is reused for "void-discard" since there is no trump alternative. Sun discards never win the trick. | `pickFollow` void-discard branch — already legal; semantic note for translation only | Definite |

---

## Section 3 — New terms / corroborated terms

The video introduces no fundamentally new strategy terms but
corroborates several glossary entries with explicit beginner-level
phrasing.

### Corroborated (existing glossary entries)

| Saudi term | Glossary mapping | This video's contribution |
|---|---|---|
| الحلة (al-hilla) | "trick / round-of-cards" — already in glossary "Other strategy idioms" | Confirmed as standard term; speaker uses it ~5 times for the trick pile |
| أكلة (akla) | Synonym for trick — "اكل / ياكل / يأكل" | Confirms "the bigger eats the smaller" framing as the foundational primitive |
| السيرة (as-sirah) / المشروع (al-mashroo3) / الملكي (al-malaki) | Meld (general) — partially in glossary | **Refinement:** سيرة and مشروع used interchangeably for "meld"; **ملكي = K+Q same suit** (matches `K.MELD_BELOTE` semantics in Hokm; in Sun a K+Q same-suit meld appears to score equivalently — confirm in Rules.lua) |
| يقطع (yiqta3) | "to cut / to trump" — glossary entry sources video #04 | Confirms the verb is reused in Sun for any void-discard (not just trump-ruff). Saudi speakers do NOT distinguish lexically |
| القاطع (al-qaate3) | Newly attested noun form — "the void-discard / the cut card" | Speaker: "يعتبر قاطع او يسمى قاطع" — standard Saudi label for an off-suit discard, regardless of trump existence |
| يتقيد عليك (yitqayyad ʕalayk) | "you get Qaid'd" — glossary has "Qaid (قيد)" | Confirms the verb form for the penalty, used in two distinct legality contexts: revealing الحلة, and (by extension) any illegal play |

### New / proposed additions

| Saudi term | Proposed meaning | Rationale | Confidence |
|---|---|---|---|
| ربع / يربع (rabba3 / yirabba3) | Already in glossary as "to lead from a specific position" — confirmed in this video for Sun context (e.g. "اول واحد لعب شيريا" = "first led [hearts]") | Corroborating source for an existing entry | Common (already documented) |
| ملكي (malaki) | "Royal [meld]" = K+Q same suit. Saudi colloquial for what the speaker also calls سيرة | Speaker explicit: "مشروع سرة سيرا ملكي يسمونه اللي هو شايب وبنت نفس اللون ونفس الشكل" | Definite (single source but unambiguous definition) |

### Card-name slang corroborated

All the family-trio names appear and confirm the glossary table:
- **شايب (shayib)** = K — speaker uses it 6+ times unambiguously
- **بنت (bint)** = Q — speaker pairs it with شايب
- **ولد (walad)** = J — speaker uses for pos-3 and pos-4 plays
- **العشرة / كه (al-ʕashra / kah)** = T — both forms attested
- **التسعة (at-tisʕa)** = 9
- **الثمانية (ath-thamaaniya)** = 8
- **السبعة (as-sabʕa)** = 7
- **إكَه (ikah)** = A (used distinct from AKA the partner-call)
- **ريكا (reeka)** = A of trump variant — appears once in the final example ("هذا لعب ريكا"); confirms glossary entry from video #04 even though Sun has no trump — speaker may be using it as generic "Ace" colloquial

### Suit-name slang corroborated

- **سبيد (sbeed)** = Spades
- **شريحة / شريا / شريه (shareeha / shareeya)** = Hearts (multiple spellings within a single video — confirms glossary note)
- **الهاس / هاس (al-haas / haas)** = Clubs (best guess; speaker uses in trick example)
- (Diamonds not explicitly named in this transcript)

---

## Section 4 — Code mapping

### Already encoded (this video corroborates)

| Rule | Picker / line | Notes |
|---|---|---|
| #1 must-follow-suit | `R.IsLegalPlay` (Rules.lua) | Already enforced; this video is supporting documentation |
| #2 void → unconstrained discard in Sun | `R.IsLegalPlay` Sun branch | Sun has no trump-ruff requirement; already correct |
| #5 rank order Sun = A,T,K,Q,J | `K.RANK_PLAIN` (Constants.lua) | Already correct |
| #6 trick winner = highest of led suit | `R.TrickWinner` Sun branch | Already correct |
| #10 cannot reveal الحلة | Game-flow rule | Player-side only; bot will never attempt |

### Not yet wired / partial

| Rule | Picker / line | Status |
|---|---|---|
| #3 meld declaration BEFORE first card play (timing rule) | `Bot.PickMelds` (Bot.lua — re-grep) | **Verify timing constraint:** is the bot's meld-declaration call ordered before its first `Bot.PickPlay` call within a round? If not, declaration-after-play would forfeit melds. Rule-correctness item. |
| #4 meld DISPLAY in trick 2 | `Bot.PickMelds` | Display protocol — verify Saudi convention is honored in current code |
| #7, #8 touching-honors inference (Sun A-T → partner has K, A-K → partner has Q) | `pickFollow` Bot.lua:1457 partner-supply read; `Bot._partnerStyle[partner].toptouchSignal` ledger key | **Not yet wired** — corroborates Section 6 of decision-trees.md (sources 05 + 41 = upgrade confidence) |
| #9 Takbeer (donate high card to partner's certain trick) — Sun off-trump | `pickFollow` partner-certain-winning branch (Bot.lua:1457) | **Not yet wired** — corroborates Section 4 Takbeer rule (sources 21,22,23 + 41) |

### Confidence upgrades

The following existing decision-trees.md rules gain a corroborating
source from this video:

- **Section 6 row 1** (`Sun trick 1, partner leads Ace; partner plays T → infer partner has K`): sources `05` → `05, 41`. Already `Definite`; reinforces.
- **Section 6 row 2** (partner plays K under your A → infer Q): sources `05` → `05, 41`. Already `Definite`; reinforces.
- **Section 4 Takbeer rule** (partner certain-winning → play HIGH): sources `21, 22, 23` → `21, 22, 23, 41`. Already `Definite`; reinforces.

---

## Section 5 — Open questions / flags

1. **Meld declaration timing in code:** Rule #3 says meld must be
   declared verbally BEFORE the first played card. Confirm
   `Bot.PickMelds` is called and resolved in `Net.MaybeRunBot`
   *before* the `Bot.PickPlay` call for that bot's first action of
   the round. If not, the rule is violated for bots.
2. **K+Q meld in Sun:** Speaker uses ملكي (royal) for K+Q same suit
   in a Sun example. `K.MELD_BELOTE` is documented as "Hokm only" in
   the glossary. **Discrepancy:** does Saudi convention award the
   +20 K+Q-same-suit meld in Sun as well? The transcript suggests
   YES (the example walks through Sun and the meld is announced
   normally). Verify against `R.ScoreRound` Sun branch.
3. **ريكا (reeka) in Sun:** Glossary lists ريكا = "Ace of trump
   specifically". Speaker uses it once in a Sun trick example, where
   trump does not exist. Either (a) ريكا is also a generic "Ace"
   colloquial in some speakers, or (b) speaker mis-spoke. Single
   occurrence; flag as `Sometimes` data point.
4. **No Bel/escalation discussion:** Video is beginner-level and
   does NOT cover Bel, Bel-x2, Four, or Gahwa for Sun. The Bel-≥100
   gate from video #11 is unaddressed here. No contradiction; just
   absence.
5. **No Tahreeb / Tanfeer / Faranka discussion:** Beginner content
   stops at must-follow + touching-honors. The signaling layer is
   deferred (speaker explicitly defers complexity to the Hokm
   episode). No contradiction with video #01 / #03 / #06 — just
   beginner-level scope.
6. **Speaker promises a separate Hokm episode:** "الشغل الدسم
   والكلام كله حيكون في الحكم وباذن الله حيكون مقطع لحاله" — ("the
   meaty work and the whole conversation will be in Hokm; God
   willing it'll be a separate clip"). Indicates this is part of a
   beginner series; the Hokm pair-video should be located and
   extracted.

---

## Sources

- Transcript: `_transcripts/wvFAxUMggnY_41_play_sun_basics.ar-orig.txt`
- Cross-references: glossary.md, saudi-rules.md, decision-trees.md
  Sections 3, 4, 6
