# 16 — Reverse Al-Kaboot (الكبوت المقلوب)

**Source:** https://www.youtube.com/watch?v=WgU68NXZEH4
**Slug:** 16_reverse_kaboot
**Length:** Short (24 lines)
**Topic:** Definition of "Reverse Al-Kaboot" — a defender-side sweep variant where the **defenders** take all 8 tricks against the bidder team.

---

## 1. Definition (crisp)

**Reverse Al-Kaboot (الكبوت المقلوب)** = the **defender team** wins all 8 tricks against the bidder. Score = **88** points (per most speakers; some treat it as identical to a regular Al-Kaboot, scoring at the standard ×40 / Kaboot value — the speaker notes the dispute).

> Speaker (line 1-3): "كبوت المقلوب نقاطه 88 للكبوت العادي باربعين وبعض الناس يعتبر الكبوت المقلوب كانه الكبوت العادي" — Reverse Kaboot is 88; regular Kaboot is at 40; some treat Reverse as the same as a regular Kaboot.

### Required structural conditions (speaker, lines 5-13)

For the sweep to qualify as **Reverse Kaboot** (not just "defenders won the round"):

1. **Sweep must be by you + your partner** (the defender pair) — i.e. defender team takes every trick.
2. **The bidder (المشتري) must be on the OPPOSING team** — definitionally true, since "reverse" means the bidder is *not* sweeping.
3. **The opening lead of trick 1 must be on a defender's hand** — i.e. the first card of the round is led by a defender, not by the bidder.
   - Speaker explicit (lines 9-12): "يعني اول لاعب راح يلعب هذا او هذا المشتري نفسه يكون اللعب على يده اذا هذا اللاعب اشترى لازم اللعب يكون على يده فلو مثلا هذا الخصم اشترى وهذا لعب ما يعتبر كبوت مقلوب" — if the bidder bought it but the lead is not on the bidder's hand, it does NOT count as Reverse Kaboot.
   - **Read:** the bidder must be the trick-1 leader (and then loses every trick). Defenders sweep "from under" the bidder's lead.

### Disputed sub-condition (lines 13-24)

Speakers disagree on **which card** the defender uses to win trick 1 from the bidder's lead:

- **Strict view:** the defender takes the bidder's opening card with a **specific card** (speaker mentions بنت الشريعه = Queen of Hearts as an example), not the Ace.
- **Loose view:** "any card other than the Ace" is acceptable — the only firm requirement is the **bidder leads first** and a defender catches the lead.
- The speaker (lines 21-23) endorses the looser view: "لا مش شرط الورقه تكون مثلا بنت الشريعه اي ورقه غير الاكا لكن اهم شيء انه الخصم اللي راح يلعب اول واحد هو اللي يشتريها".

### Example flow (lines 14-19)

> "الخصم هذا كان اللعب على يده واخذ الاكا هذه صن وقام الفنان ما لعب لك لعب اي شيء ثاني جاك انت او خويك وخلاص وانتوا قاعدين تاكل كل الاكلات وجبتوا كبوت عليهم فهذه الحاله ينحسب 88"

Translation: bidder leads in **Sun** with the Ace; the next-to-act player ("الفنان" — likely partner of bidder, or just "the artist" colloquial for skilled player) plays anything other than [the matching response]; you or your partner take with a Jack; from there the defender team sweeps every remaining trick — count = **88**.

---

## 2. Game-state predicates (testable)

| Predicate | Source line |
|---|---|
| `defenderTeam.tricksWon == 8` | 5-6 |
| `S.s.contract.bidder ∈ opponents` | 7-8 |
| `firstLeaderOfRound == S.s.contract.bidder` | 9-12 |
| (Disputed) `winnerCardOfTrick1 != Ace` | 13-23 |

---

## 3. Decision rules (NEW — for `decision-trees.md`)

Reverse Kaboot is **scoring/recognition logic**, not a player decision. Almost all rules below belong in `Rules.lua` (`R.ScoreRound`) rather than a picker. Two picker-side rules emerge as corollaries.

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Round end; defender team has 8 tricks AND bidder led trick 1 | Award **88** raw to defender team as **Reverse Kaboot bonus** (in addition to the 152+10 trick total they already captured). | Standard Saudi recognition of defender sweep with bidder-led-trick-1. | `Rules.lua` `R.ScoreRound` — new `K.AL_KABOOT_REVERSE` constant `(not yet wired)`. **Rule-correctness item.** | Common | 16 |
| Round end; defender team has 8 tricks BUT bidder did NOT lead trick 1 | Do **NOT** award Reverse Kaboot bonus — score as ordinary failed-bid round (defenders take all trick points; no sweep bonus). | Speaker explicit: "ما يعتبر كبوت مقلوب" if leader != bidder. | `Rules.lua` `R.ScoreRound` defender-sweep gate `(not yet wired)`. | Common | 16 |
| Bidder, trick 1 leader, mid-round; you have lost the first 3-4 tricks AND remaining hand cannot recover | **Aggressively try to take ANY remaining trick** — even at cost of position — to deny defenders the +88 Reverse-Kaboot bonus. | Reverse-Kaboot bonus dominates a single trick's value (~88 vs ~10-20). Same logic as anti-Kaboot defense in reverse. | `pickFollow` Bot.lua:1457 / `pickLead` Bot.lua:953 anti-reverse-Kaboot branch `(not yet wired)`. | Sometimes | 16 |
| Defender, your team has won the first 4-5 tricks against the bidder AND bidder led trick 1 | **Promote secondary goal: pursue Reverse Kaboot.** Play to sweep the remaining tricks rather than just maximizing per-trick value. | +88 bonus dominates ordinary trick-points. Mirror of bidder-side Al-Kaboot pursuit. | `pickLead` Bot.lua:953 / `pickFollow` Bot.lua:1457 reverse-Kaboot pursuit `(not yet wired)`. | Sometimes | 16 |

---

## 4. New terms / glossary additions

| Arabic | English | Notes |
|---|---|---|
| الكبوت المقلوب (al-Kaboot al-maqloob) | **Reverse Al-Kaboot** | Defender-team sweep against bidder. **Requires bidder to be trick-1 leader.** Score 88 raw (disputed: some say equal to regular Kaboot value). |
| الفنان (al-fannan, "the artist") | colloquial for skilled/expected player | Used in the example flow (line 16); not a strategy term, just a speaker tic. |

**Glossary impact:** add ONE row to glossary.md "Special plays" table. No card/suit slang updates.

**Rules.lua impact:** new constant `K.AL_KABOOT_REVERSE = 88` (or, per the disputed view, `= K.AL_KABOOT_HOKM` / `K.AL_KABOOT_SUN`). New gating predicate in `R.ScoreRound`: `defenderSweep && firstLeader == bidder`.

---

## 5. Confidence + sourcing notes

- **Single source** (this video alone). All rules logged at `Common` or `Sometimes`.
- **Open ambiguities** that need a second source:
  1. **Score value:** 88 vs equal-to-regular-Kaboot. Speaker presents both views but personally seems to use 88.
  2. **First-card constraint:** "any card except Ace" vs "specific card (Queen of Hearts)". Speaker endorses looser view.
  3. **Hokm vs Sun:** the example uses Sun, but no statement that Reverse Kaboot is contract-restricted. Treat as applicable to both contracts pending corroboration.
- **Lookup for follow-up videos:** any future transcript discussing بل×2 / فور / قهوة scoring may also cover Reverse-Kaboot as a related score-bonus topic.

---

## Rule count: 4 new (2 score-correctness, 2 strategy). New terms: 2. Reverse-Kaboot definition: see Section 1.
