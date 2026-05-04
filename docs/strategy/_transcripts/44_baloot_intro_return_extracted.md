# 44 — Baloot Intro / Return-After-Long-Absence (Refresher)

**Slug:** `44_baloot_intro_return`
**URL:** https://www.youtube.com/watch?v=r3GiDLvLeQM
**Title (Arabic):** شرح لعبة البلوت للمبتدئين | رجعة بعد غياب طويل
**Type:** High-level beginner refresher; speaker returns after a 2-year break.
**Topic hint confirmed:** Restates basics — suit identification, Sun/Hokm rank order, mashari3 (melds), trick-following rule, the Qaid penalty, last-trick value, and the 152-target.

---

## Section 1 — Net-new claims vs prior corpus

**Almost nothing is net-new.** The video is a high-level beginner overview that re-states material already corroborated multiple times in videos 01-43. Below are the only entries that add anything not already in `glossary.md` / `saudi-rules.md` / `decision-trees.md`.

| Claim | Net-new? | Notes |
|---|---|---|
| **Trick-points-only floor (Sun = 26, Hokm = 16) stated as the *bidder's earned base*** at 26/16 raw before melds. | Partial reinforcement | Speaker frames "the Sun is 26 points, Hokm is 16 points" as the *trick-side score* (نقاط) that counts toward the 152 target — this matches the Qaid table (`saudi-rules.md` line 119: 26 raw Sun / 16 raw Hokm) but here it is given as the **base trick-point yield** of a round, not as a Qaid penalty value. **Mild ambiguity** — the speaker conflates the two; treat as confirming the 26/16 numbers but **not** as a new mechanic. |
| **Match target = 152** | Already in `glossary.md` HAND_TOTAL section. Re-confirmed. | No change. |
| **Suit-name ordering as recited** هاص → شريه → ديمن → سبيت | Already in `glossary.md` suit-slang table. Re-confirmed pronunciation. | No change. |
| **Suit-name regional variation acknowledged** ("تختلف من منطقه لمنطقه") | Already implicit in glossary's "multiple spellings" notes; **video #44 is the first explicit speaker-acknowledgement** of regional variation. | Minor metadata only. |
| **Saudi rank order recited (Sun): A > T > K > Q > J > 9 > 8 > 7** | Matches `glossary.md` plain-suit table. Re-confirmed. | No change. |
| **Saudi rank order recited (Hokm trump): J > 9 > A > T > K > Q > 8 > 7** | Matches `glossary.md` Hokm trump-rank table. Re-confirmed. | No change. |
| **Must-follow-suit penalty = Qaid** ("اذا اكتشفنا نقيد عليه ... ناخذ النقاط حقته كامله") | Already in `saudi-rules.md` Qaid section. Re-confirmed. | Speaker uses verb form **نقيد عليه** ("we Qaid him") which is **net-new verb form** — adds a vernacular conjugation worth noting in glossary. |
| **Cut-priority rule:** when void in led suit, **first priority is to cut with trump** ("الاولويه انك تقطع بالحكم"). Not mandatory — depends on whether partner or opponent is currently winning. | **Net-new framing as "اولويه" (priority), not absolute rule.** | The "must-trump-ruff if not winning" rule already exists in `saudi-rules.md` Trick-play rules, but speaker explicitly softens it to a *priority/preference* qualified by trick-winner identity. Matches existing AKA-receiver convention (suppress ruff when partner winning). |
| **Over-cut rule:** when forced to cut, must play a trump **higher than any trump already on the table**. ("يكون اكبر من العشره" given an example where T-trump was already played and the speaker says you must play J, 9, or A of trump if you have one.) | Already implicit in `saudi-rules.md` ("Must over-trump"). Speaker articulates the cut-amount logic clearly with example. | Re-confirmed. |
| **Fallback when over-cut impossible:** play any other off-trump suit ("تقطع بشريا او ديمن"). | Already standard but **not explicitly written** in `saudi-rules.md`. Mild clarification: speaker notes that if you can't over-cut and can't follow, you may shed any non-led, non-trump card. | Minor. |
| **Carré-others (4-of-a-kind, ranks T/K/Q/J)** described as "صور" (suwar — "pictures/face cards"). Speaker uses example "اربع شياب" (four Kings). | **Net-new term:** **صور (suwar)** as the collective name for the four-of-a-kind family meld. | Worth adding to glossary under melds. |
| **Practice prescription:** speaker recommends 3-5 سكات (sakkat / "rounds") per session before re-watching follow-up videos. | **Net-new term:** **سكه / سكات (sikkah / sakkat)** ≈ "round" or "session deal". | Add to glossary. |

---

## Section 2 — Decision rules (operational WHEN/RULE entries)

This video offers no novel decision rules. **All if-then content is recap.** The two rule rows that come closest to operational specificity are below; they reinforce existing rows in `decision-trees.md` rather than adding new ones.

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | SOURCES |
|---|---|---|---|---|---|
| Void in led suit; must play | First **priority** is trump-ruff (cut). Not absolute — partner-winning can suppress. | Saudi cut-preference convention. | `pickFollow` Bot.lua:1457 trump-ruff branch; existing AKA-receiver suppress logic already encodes the partner-winning override (H-5 v0.5.1). | Reinforces existing `saudi-rules.md` "Must trump-ruff if void + team not winning" rule. **Upgrade prior 'Definite' → still Definite (44 confirms).** | 44 + existing |
| Cutting with trump and a higher trump is already on the table | Must over-cut (play higher than the live trump on table). | Saudi "must over-trump" rule. | `R.IsLegalPlay` already enforces. | Confirms existing `saudi-rules.md` over-trump rule. | 44 + existing |

**No new rule rows proposed.** Existing `decision-trees.md` Sections 4 (mid-trick play), 8 (Tahreeb), 10 (Faranka) already cover the bot-relevant material this video touches on, and the speaker explicitly defers tactical detail to other videos in the series ("هذا شارح انا في مقطع بالتفصيل").

---

## Section 3 — New terms (proposed additions to `glossary.md`)

| Arabic | English / meaning | Where to add | Confidence |
|---|---|---|---|
| **صور (suwar)** | "Pictures / face-card four-of-a-kind" — collective name for Carré of T/K/Q/J. Speaker example: "اربع شياب" = four Kings = a صور. | `glossary.md` Melds section, footnote next to `K.MELD_CARRE_OTHER`. | Common (single-source-strong; family of words صوره/صور is standard Arabic). |
| **سكه / سكات (sikkah / sakkat)** | "Round / hand / deal-cycle." Speaker uses to recommend "العب 3-5 سكات بين كل مقطع". Likely cognate of "circuit / cycle". | `glossary.md` "Other strategy idioms" table. | Common (standard Saudi gaming colloquial). |
| **نقيد عليه (nqayyid ʕalayh)** | Verb form: "we apply Qaid against him" = call the illegal-play penalty. | `glossary.md` Qaid row — add as verb conjugation. | Common (vernacular). |
| **مشاريع (mashari3)** | "Projects" — the umbrella term for melds (sequences + carrés). Plural of مشروع (mashroo3). | `glossary.md` Melds section header. Speaker uses "مشاريع البلوت" to introduce the meld concept. | Common — already implicit in existing docs but never given the umbrella name. |
| **حله / الحله (hilla / al-hilla)** | "Trick / round-of-cards" — singular form. Speaker uses repeatedly: "مين ياكل الحله". Already in glossary as `hilla`; this video confirms the spelling **حله** (one-l) variant. | Reinforce existing entry. | — |
| **اكل (akala — "eat")** | "Wins the trick" — verb. "اكبر ورقه هي اللي تاكل" = "the biggest card is the one that eats". Standard idiom; already implicit. | Optional glossary mention. | — |

**Net-new term count:** 4 (صور, سكه, نقيد, مشاريع as umbrella term). The remaining are reinforcements.

---

## Section 4 — Reinforced (already-corroborated) content

The following are already in the corpus and need no change. Listed for audit completeness.

- 4 players, 2 partnerships, partner across (يمين/شمال = right/left = opponents). [`saudi-rules.md` Players]
- 8 cards dealt (speaker says **5 face-down at start** — likely a phrasing slip referring to the 5-card pre-bid sample, since standard Saudi/Belote deal is 5+3; not a rule contradiction). [`saudi-rules.md` Deal]
- Bid choices: Sun / Hokm. (Ashkal & Pass not mentioned in this beginner refresher.) [`glossary.md` Bid types]
- Sun rank order A>T>K>Q>J>9>8>7. [`glossary.md` plain-suit]
- Hokm trump rank order J>9>A>T>K>Q>8>7. [`glossary.md` Hokm trump]
- Hokm: only the named suit is trump; remaining three suits play in Sun order. [`saudi-rules.md`]
- Mashari3 (melds): sequences and four-of-a-kind. (Speaker mentions "100" as a meld value — matches Sequence-5 / Carré-others = 100.) [`glossary.md` Melds]
- Match target = 152 raw cumulative. [`glossary.md`, `saudi-rules.md`]
- Must-follow-suit; failure → Qaid (full points to non-offender). [`saudi-rules.md`]
- Trump-ruff priority when void. [`saudi-rules.md`]
- Over-cut required when cutting and prior trump already on table. [`saudi-rules.md`]

---

## Section 5 — Summary

**Rule count (operational WHEN/RULE entries):** 0 new; 2 reinforcements of existing rows.
**New-terms count:** 4 (صور, سكه/سكات, نقيد عليه as verb form, مشاريع as umbrella).
**Net-new content:** Effectively none on the strategy side. This video is a **return-after-absence beginner intro**; the speaker explicitly defers tactical detail to other (already-extracted) episodes ("هذا شارح انا في مقطع بالتفصيل"). The only tangible additions are vernacular terminology (صور, سكه, نقيد عليه) and a confirmation that suit-name pronunciation varies regionally.

**Recommendation:**
- Add the 4 new terms to `glossary.md` (low-priority, vernacular).
- **No changes** to `decision-trees.md` or `saudi-rules.md`.
- This transcript can be cited as a corroborating source for: must-follow-suit, must-over-cut, trump-ruff priority, 152-target, Sun/Hokm rank orders, Qaid penalty mechanics. Bump confidence on prior rows that cite single-source from the basics layer if desired.
