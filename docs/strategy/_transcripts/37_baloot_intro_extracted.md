# 37_baloot_intro — extracted decision rules

**Source:** https://www.youtube.com/watch?v=p5aA2oq6WFk
**Title (Arabic):** شرح لعبة البلوت للمبتدئين | 1 | تمهيد
**English gloss:** Baloot for beginners — Episode 1 (preamble)
**Transcript file:** `_transcripts/p5aA2oq6WFk_37_baloot_intro.ar-orig.txt`

ASR quality: low — Saudi-Arabic auto-captions are heavily corrupted
in places (e.g., "تفيد" almost certainly = تايد/تايل for clubs;
"دائما" = دايمن diamonds; "سوريا" = سبيد spades; "الان"/"كانت" are
unparseable garble). Read with caution; cross-reference with the
glossary's slang table.

---

## 1. Rules / mechanics extracted

Almost nothing new. The video is a beginner preamble, so it
restates fundamentals already in `saudi-rules.md`. One rule was
restated explicitly:

| # | Rule (as stated in video) | Status vs `saudi-rules.md` |
|---|---|---|
| R1 | "Match target = 152 — first team to exceed 152 wins." (Tx line ~21: "هي عباره عن جمع النقاط اللي وصل 152 تعداها هو الفائز") | **Corroborated** — matches `S.s.target = 152` (glossary "Match target"). |
| R2 | "Deck = 32 cards, two colors (red/black), four suits." (Tx ~22-23) | **Corroborated** — matches `saudi-rules.md` "Deck and deal". |
| R3 | "Four players, two teams of two. Three-player variant ('الحكم الثلاثي') exists but is rare." (Tx ~16-19) | **Mostly corroborated.** The three-player Hokm-Thulaathi variant is *not* modeled in `Rules.lua` (which assumes 4 seats, 2 teams) and is explicitly out of scope per `CLAUDE.md`. No action needed; flag only as a known unsupported variant. |
| R4 | "Game splits into two contract types — Sun and Hokm." (Tx ~36-37) | **Corroborated** — `K.BID_SUN`, `K.BID_HOKM`. (Ashkal/Pass not mentioned in this beginner intro, expected.) |
| R5 | Sun rank order (high→low): A, T, K, Q, J, 9, 8, 7. (Tx ~42-44, paraphrased through caption noise: "يبدأ من ... تنازليا يعني اكبر شيء عندكم اليه بعدين عشره ... البنت الولد 987") | **Corroborated** — matches `K.RANK_PLAIN` (Ace-high, J above 9 in Sun). |
| R6 | Hokm rank order (high→low): J, 9, A, T, K, Q, 8, 7 — "الولد والتسعه" (J and 9) jump to the top in trump. (Tx ~45-48) | **Corroborated** — matches `K.RANK_TRUMP_HOKM`. |

**No rule discrepancies found.**

---

## 2. New / clarified terms

None of strategic substance. Terms appearing in the transcript that
are already in `glossary.md`:

- الولد (walad) = J — confirms family-trio convention.
- البنت (bint) = Q — confirms.
- الشعب — almost certainly an ASR garble for **شايب** (shayib) = K.
  The two are phonetically close; the video is using the standard
  family trio (شايب / بنت / ولد). **No new term, just ASR noise.**
- الحكم / الصن — bid types, already mapped.
- اللون / الشكل — "color / suit shape", already in glossary's
  "Other strategy idioms" row "عكس اللون / عكس الشكل".

One **near-term** worth a single-line glossary note (optional, low
priority):

- **الحكم الثلاثي (al-hokm ath-thulaathi)** — three-player Baloot
  variant. Speaker mentions it exists ("نادي الوحده العربيه يعني
  الوصل") but says it is rare. **Out of scope** for WHEREDNGN
  (which is 4-seat). Flag only — no code change.

---

## 3. Heuristics / decision rules

**None.** This is a "what is the deck, what is the trump order"
preamble — it predates any strategy content. The author defers all
scoring details to "the next videos" (Tx ~38-40: "بعد ما راح ان شاء
الله اشرح لكم النقاط كل شيء ... في في الجواد القادمه").

---

## 4. Source-video log

| Timestamp (approx) | Topic |
|---|---|
| 0:00–0:30 | Preamble; "this isn't a Sniper episode, today is about Baloot itself." |
| 0:30–1:15 | Why people fail to learn Baloot — depends on partner, luck, opponent style, and intelligence. |
| 1:15–1:45 | Player count (4, two teams of 2; three-player variant noted as rare). |
| 1:45–2:00 | Win condition — first to exceed 152 raw points wins the match. |
| 2:00–2:30 | Deck composition — 32 cards, 2 colors, 4 suits. |
| 2:30–3:00 | Suit-name slang (corrupted by ASR — partial confirmation of glossary slang only). |
| 3:00–3:30 | Two contract types: Sun and Hokm. Defers point-counting to next episode. |
| 3:30–4:30 | Rank orders: Sun (A high, descending) and Hokm (J highest, then 9). |
| 4:30–end | Sign-off; invites questions in comments. |

---

## 5. Non-rule observations / open items

- **ASR is unusually noisy in this transcript.** Suit slang and
  card-name slang are partly garbled. The video is genuinely
  beginner-level, but the captions misrepresent specific words
  often enough that any extracted *strings* should be cross-checked
  against the glossary's slang section before being trusted.
- **Three-player Baloot ("الحكم الثلاثي")** — confirmed mentioned
  but treated by the author as a niche, club-specific variant
  (Wahda Arabia / Wasl). WHEREDNGN does not need to support it. No
  code change; add a single line to `glossary.md` "Open questions"
  if desired.
- **Author's framing of Baloot skill** — "depends on partner, luck,
  opponent style, and intelligence" — useful context for how Saudi
  commentators implicitly weight reading-vs-mechanics. Not a code
  rule, but reinforces the M3lm+ tier emphasis on partner reads.
- **No mention of:** AKA, SWA, escalation chain, Bel/Four/Gahwa,
  Tahreeb, Faranka, Kasho, Qaid, melds, Belote bonus, last-trick
  bonus, Al-Kaboot. All deferred to later episodes in the series.

---

## Summary

- **Rules extracted:** 6 (all corroborate existing `saudi-rules.md`).
- **New terms:** 0 of strategic substance; 1 noted-only term
  (الحكم الثلاثي, three-player variant, out of scope).
- **Discrepancies:** **None.**
- **Code action:** None required.
