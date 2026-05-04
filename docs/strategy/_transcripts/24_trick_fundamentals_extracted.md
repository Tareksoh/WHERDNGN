# 24 — Trick fundamentals (احترف البلوت ep 1) — extraction

**Source:** [Master Baloot ep 1 — اساسيات الحلة للمبتدئين](https://www.youtube.com/watch?v=FjgVrzBWm2s)
**Slug:** `24_trick_fundamentals`
**Transcript:** `_transcripts/24_trick_fundamentals_whisper.ar.txt` (whisper medium ASR)

Episode 1 of "احترف البلوت" — series-opener establishing baseline trick-resolution mechanics. Almost entirely rules-of-the-game content with light strategy framing. Foundational, not advanced.

---

## 1. Decision rules

### Rules-of-game (legality / trick-resolution — already in `Rules.lua`)

| WHEN | RULE | MAPS-TO | SOURCE |
|---|---|---|---|
| Any trick | Highest card of led suit wins, **unless trumped**. | `R.TrickWinner` (Rules.lua) | 24 |
| You are not the leader; you hold a card of the led suit | **Must follow suit** (الزام بشكل الأرض). | `R.IsLegalPlay` | 24 |
| You are void in led suit (Hokm); your team not winning | **Must trump-ruff** if you hold trump. | `R.IsLegalPlay` Hokm trump-discipline | 24 |
| Off-suit discard while a trump exists on table | Off-suit card has **value 0** to trick-resolution — cannot win regardless of rank. | `R.TrickWinner` | 24 |
| **Sun**, two A's of different suits on table | A of **led suit** beats A of off-suit (both 11 raw, but rank order resolves on led suit). | `R.TrickWinner` Sun branch | 24 |
| **Hokm**, any trump on table vs any non-trump | **Trump wins**, even trump-7 over A of off-suit. | `R.TrickWinner` Hokm branch | 24 |
| **Hokm**, multiple trumps on table | Highest by `K.RANK_TRUMP_HOKM` (J > 9 > A > T > K > Q > 8 > 7) wins, regardless of led suit. | `R.TrickWinner` | 24 |

### Sun rank order (informational — already in `K.RANK_PLAIN`)

A > T > K (شايب) > Q (بنت) > J (ولد) > 9 > 8 > 7. Sum 30 raw / suit. Confirms `K.POINTS_PLAIN`.

### Hokm trump rank order (informational — already in `K.RANK_TRUMP_HOKM`)

J (ولد) > 9 > A > T > K > Q > 8 > 7. Sum 62 raw / trump suit. Confirms `K.POINTS_TRUMP_HOKM`.

### Strategy heuristics (light, foundational)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Any contract; you are deciding play | **Track every card played** (32-card universe). Knowing which cards have hit the table is the gate to "احتراف". | Probabilistic reads (Tahreeb, تنفير, hand-shape inference) all require complete card-tracking. | `Bot._memory` already records all plays (Bot.lua:282-292). Read-side use is partial. | Sometimes | 24 |
| Any contract; partner just discarded while you/team won the trick | Treat the discard as a **Tahreeb / تنفير signal** (positive or negative directional). Speaker says **"التنفير اعتبره تهريب"** — Tanfeer is a Tahreeb subspecies. | Confirms parent/subset taxonomy from videos #03, #12. | `pickFollow` partner-winning discard branch (Bot.lua:1457) `(not yet wired)`. | Common | 24, 03, 12 |

(Speaker previews Faranka / فرنكة and SWA / سوا but defers actual rules to later episodes — no new substantive rules here.)

---

## 2. New terms

None genuinely new. Re-affirms existing glossary entries:

- **حلَّة / أَكلة** = trick (already in glossary).
- **أرض** = led-suit / table-led (informally "ground"); not previously catalogued as a term but is common Saudi parlance for "the suit that was led". Worth a glossary row at the "Other strategy idioms" table.
- **يقطع / قاطع** = "cut" — playing off-suit (no trump implied here; just "broke suit"). Distinct from دق (Hokm trump-ruff) — caller uses قطع loosely for any off-suit play, including trumps. Caption-disambiguation hint.
- **التنفير** explicitly equated with تهريب — corroborates video #12 taxonomy ("every Tahreeb is a Tanfeer").

---

## 3. Contradictions

None against existing docs. Speaker's "التنفير اعتبره تهريب" aligns with the video #12 taxonomy already recorded in glossary (Tanfeer = parent class; Tahreeb = intent-bearing subset).

---

## 4. Non-rule observations

- Series framing: speaker positions tournaments levels as **متوسط → محترف → أسطورة** (intermediate → professional → legendary). Maps loosely to bot tiers Advanced / M3lm / Saudi Master.
- Speaker's stated goal: viewer should reach the level where **توقعاتك واحتمالاتك صحيحة** ("your predictions and probabilities are correct") — i.e., probabilistic inference is the gating skill.
- Episode is **almost pure rules-of-game**; the actual decision-content is teased for follow-up episodes (Faranka, Tahreeb-deep, تفكير "thinking", reads).

---

## 5. Quality notes (ASR)

Whisper medium produced readable text with notable artifacts:
- Line 72: `smoking is the best` — clear ASR garbage hallucination injected mid-transcript. Ignore.
- Line 77: `الناسب음` — Korean Hangul `음` injected; another hallucination.
- Line 80: `tev grilling` — English-word hallucination; ignore.
- Suit-name spellings vary line-to-line: `سبيت` / `سبيد` / `اسبيت` (spades), `الهاس` (clubs), `الشريحه` / `الشريعة` / `الشري` (hearts), `الدامة` / `الدامن` / `الدايمه` (diamonds). All map to known glossary entries; example structure (rank order, who wins) overrides spelling per glossary's "Rule for transcripts".
- Line 97: `اشبطوهم` — likely `اخطأوا` ("got it wrong") or similar; ASR garble.
- Line 103: `شايب الدامة` correctly = K of diamonds (شايب = K confirmed by glossary; family-trio convention).
- Line 175-176: `الاككا` = الإكَه = Ace; not the AKA partner-call.
- Bid types referenced: صن (Sun) / حكم (Hokm) — both present and unambiguous.

Overall: rules-of-the-game content is clear despite ASR noise. No rule extraction was blocked by transcription quality.
