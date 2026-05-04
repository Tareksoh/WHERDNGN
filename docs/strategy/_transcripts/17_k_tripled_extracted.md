# Extraction — 17_k_tripled (مثلوث الشايب in Sun)

**Source:** https://www.youtube.com/watch?v=2U3EC76ZAqU
**Title:** كلام اول مرة تسمعه عن المثلوث K في بلوت
**Topic:** Mathlooth K (مثلوث الشايب) — 3-card holding including the شايب (King) in Sun.
**Section target:** Section 4 (mid-trick play / `pickFollow` Bot.lua:1457) + Section 3 (`pickLead` Bot.lua:953).

---

## 1. Decision rules

### Sender side (you hold مثلوث الشايب — K + 2 cards in some side suit, in Sun)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|
| Sun, you hold الشايب + 2 lower cards (مثلوث الشايب) in suit X; opponent led X with low (e.g. ثمانيه) and partner played الولد (J), opponent ruff-equivalent likely with البنت (Q) | Play SMALLEST first (e.g. ثمانيه/سبعه), let opponent eat with البنت; trick 2 your TSعه covers; trick 3 your شايب takes. **The "third trick" structure is the whole point of المثلوث.** | الشايب is the 3rd-rank live card in Sun (after إكَه, العشره). Three cards = three rounds before it walks; smaller-than-K must be in hand to bridge tricks 1-2. | `pickFollow` Bot.lua:1457 — مثلوث-K-preserve branch `(not yet wired)`. | Sometimes |
| Sun, you hold الشايب + only 1 card in suit X (شايب مردوف/doubled, NOT tripled) | Cannot use المثلوث plan — opponent eats round 1 with البنت, you cover round 2 with شايب. **2nd trick, not 3rd.** Do not need the مثلوث mechanic; the third low card was unnecessary. | Two cards = two rounds; شايب lands one round earlier. Speaker explicit: "ما احتجت للمثلوث". | `pickFollow` Bot.lua:1457 — distinguish مثلوث from مردوف `(not yet wired)`. | Sometimes |
| Variant: you hold مثلوث الولد (J + 2 lower) in Sun, no شايب | Same trick-3 capture plan applies but **lower probability of success** — البنت+الشايب both live above your الولد. Speaker says "نسبتها اقل من الشايب". | الشايب=3rd-rank; الولد=5th-rank → more cards above to fall first. | `pickFollow` Bot.lua:1457 — مثلوث-J-fallback branch `(not yet wired)`. | Sometimes |

### Sender side — opening play with مثلوث الشايب

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|
| Sun, you are leader trick 1; you hold near-Kaboot hand (إكَه + العشره + البنت + سبيت side) and a SUIT WHERE YOU LACK البنت/الولد such that an opp مثلوث-الشايب could trap you | **Lead the vulnerable suit FIRST**, NOT last. Get مثلوث-الشايب out of opp's hand before late-trick capture. | Speaker: "افضل اني العبها في البدايه ... هدفنا تعرف وين الشايب". Goal #1: locate الشايب. Goal #2: send signal "no العشره" to nudge opponent to تنفير (release a card from their مثلوث). | `pickLead` Bot.lua:953 — Kaboot-pursuit early-probe-vulnerable-suit branch `(not yet wired)`. | Sometimes |
| Sun, leading; you hold إكَه + العشره + lower in a suit | Lead إكَه first; **withhold العشره for trick 3+**. Goal: induce opp to believe you are void in العشره → opp will تنفير a card from their مثلوث (treat their شايب as مردوف, jettison spare). | "تبغى توهم خصمك انه ما عنده العشره". Reads as inverse-Faranka deception. Encodes false-info to opp. | `pickLead` Bot.lua:953 — A-first-T-hold deception branch `(not yet wired)`. | Sometimes |
| Same setup BUT you hold إكَه + الثمانيه only (NO العشره, NO البنت) of the suit | The deception still holds — opp cannot tell الثمانيه from البنت from your perspective. **Lead إكَه, hold الثمانيه; opp may still تنفير from مثلوث.** | Opp's read is "no العشره with leader" → same تنفير outcome. Deception is information-based, not card-based. | `pickLead` Bot.lua:953 — same branch as above; gate independent of mid-rank holdings `(not yet wired)`. | Sometimes |
| Sun, leading; you have إكَه + العشره of suit X but only الولد (J) as backup | Same plan — lead إكَه trick 1, withhold العشره. Opp may still hold الشايب w/ ولد (مردوف). Your الولد can capture late if opp تنفير'd one mid-rank away. | الولد ranks below البنت/الشايب but in Sun is 5th-rank; works as a 3rd-trick capture if mid-cards have fallen. | `pickLead` Bot.lua:953 — same branch with J-as-recapture vehicle `(not yet wired)`. | Sometimes |

### Receiver / opponent side (recognizing opp's مثلوث الشايب)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|
| Sun, opp leads الولد (J) of suit X early, then opp's partner plays low | Infer: leader has either **الشايب alone** or **الشايب + مردوف**. With مردوف opp likely wins late with شايب. Adjust sampler. | Speaker spelling out the read sequence. | Sampler in `BotMaster.PickPlay` — infer-K-presence branch `(not yet wired)`. New ledger key: `Bot._partnerStyle[seat].kingHoldSuspect[suit]`. | Sometimes |
| Sun, opp on lead, plays إكَه but does NOT play العشره on next opportunity | Read as POSSIBLE deception: opp may still hold العشره. Do **NOT** auto-تنفير ورقه from your مثلوث الشايب. Hold the مثلوث intact until trick 3+. | Speaker explicit: this is the bait. Releasing a card from مثلوث الشايب walks into opp's plan. | `pickFollow` Bot.lua:1457 — مثلوث-K-defense branch `(not yet wired)`. | Sometimes |

---

## 2. New terms / concepts

| Term | Meaning | Notes for glossary |
|---|---|---|
| مثلوث الشايب (Mathlooth ash-Shayib) | 3-card holding in a side suit that includes the K | "Shayib (شايب)" = K (already in glossary). The compound noun should be added under "Strategy terms" — central enough to merit a row. Authoritative phrasing: 3 cards is the rule (not 4, not 2); K specifically because K is the 3rd-rank live card in Sun (إكَه, العشره, شايب). |
| مثلوث الولد (Mathlooth al-Walad) | 3-card holding including the J (no K) | Same structure, weaker payoff — البنت + الشايب both above. Speaker uses as a "still works but lower probability" example. |
| Verb: ينفر / ينفر ورقه (yinaffir warqa) | "to repel a card / release-tempo a card" | Already in glossary as تنفير but here used in sender-bait context: opponent تنفير'ing a card from THEIR مثلوث because they were misled. |
| إيهام / يوهم خصمك (yu-wahim khasmak) | "to mislead your opponent (about a card you hold)" | Glossary candidate under "strategy idioms"; this is the deception primitive that الفرنكة, the "smart move", and now A-first-T-hold all share. |

**Recommendation:** Add a "Mathlooth-K" row to glossary.md "Strategy terms" section, separate from generic مثلوث (which already has a definition implicitly via the escalation chain). The compound (K + 3-card holding) is the named concept.

---

## 3. Contradictions / corroborations

- **Corroborates Section 5 anti-Faranka rule** ("Sun pos-4; you hold ≥3 cards of suit → do NOT Faranka"): this video gives the **opposite-perspective reason** — when YOU hold the 3-card K, opp expects the 10/Q to drop naturally and may release. Same fact, different side of the table. Upgrade Section 5 row to **Definite** (now sources 06 + 17).
- **Corroborates Section 7 Bargiya / "set up SWA via deception"** — same family of deception-leads. The "lead A early, withhold T" pattern here is structurally similar to Bargiya: send a misleading signal to manipulate opp's discards.
- **No contradictions** with existing rules. Speaker's framing ("المثلوث قوة، حافظ عليه") aligns with Section 4 "Sun losing-side: dump highest" only if you read it carefully — this video is about a **WINNING-side preserve**, not a losing-side dump. Different branch.

---

## 4. Non-rule observations

- Speaker explicitly endorses **mental-modeling the opponent** ("حط نفسك مكان الخصم") as the pedagogical core of Baloot — squarely a M3lm/Fzloky tier behavior (style-ledger reads in `Bot._partnerStyle`).
- Reference to a separate video on "تكبير وتصغير" (raising/lowering reads) — likely the same target as Section 11's "M3lm partner-style inference" rules. Worth re-examining if that video appears in a future batch.
- The deception ("lead A, hold T") implies the bot needs an **information-state model** of what each opponent thinks YOUR hand contains, not just what cards are out. This is ISMCTS-territory (`BotMaster.PickPlay`); cannot be fully expressed in the heuristic Bot.lua picker.

---

## 5. Quality notes

- **Single-source:** all rules above marked **Sometimes** unless cross-referenced. Mathlooth-K mechanic itself is not corroborated by videos 01-10.
- **Card-name disambiguation clean:** speaker uses شايب/بنت/ولد consistently; auto-caption did not introduce confusion. سبيت/سميد/شريحة/دايمه all present (suit slang stable).
- **One auto-caption error noted:** "الشاعر" in line 95 is clearly a homophone error for "الشايب" (context: locating the K). Treat as الشايب throughout.
- **One ambiguous moment:** lines 67-69 ("معاه مردوف ... حيكون في الهاص") — speaker switches between hypothetical hand shapes mid-sentence; the rule extracted from the surrounding context is the cleaner reading.
- **Pedagogical not exhaustive:** speaker focuses on Sun + side-suit; does NOT discuss مثلوث الشايب in Hokm side-suits or in trump. Gaps logged for a future video.
