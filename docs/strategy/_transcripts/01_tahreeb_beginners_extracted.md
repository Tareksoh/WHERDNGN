# Extracted from 01_tahreeb_beginners

**Video:** شرح التهريب في البلوت للمبتدئين
**URL:** https://www.youtube.com/watch?v=WF1315jTVsw

## 1. Decision rules

### Section 4 — Mid-trick play (`pickFollow` Bot.lua:1457, positions 2-3)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Sun contract; partner is winning the trick (pos-2/3 ahead of you) AND you are void in led suit | Discard a Tahreeb-signal card (NOT your top winners) to telegraph desired suit | Goal is to score MORE on partner's win, not waste high cards; partner's winning trick is the "free" signal opportunity | `pickFollow` discard branch when partner already winning (not yet wired) | Common | Speaker frames Tahreeb specifically as plays "when the trick is on partner's hand" (اذا كان اللعب لعب عند خويك) |
| Sun; partner winning; you hold A+J of an off-suit (e.g., suits' A and J) and want partner to next-lead THAT suit | Play the A on this trick (the "Bargiya" / برقية signal — top card means "I have the slam in this suit") | A = strongest discard in that suit = clearest "come back here, I'm boss" message | `pickFollow` Sun signal branch (not yet wired); add MELD-tracker first | Common | Caller must hold SWA (top remaining in suit) for the A-signal to be sound |
| Sun; partner winning; you want to DISCOURAGE a suit (you have nothing meaningful there) | Play your highest card of the unwanted suit FIRST, then a lower one next time (top-down sequence) | Top-down = "I do not want this suit" convention | `pickFollow` discard ordering (not yet wired) | Common | Speaker: "من فوق لتحت" — top-down means refusing the suit |
| Sun; partner winning; you want partner to lead a specific suit AND you do NOT hold that suit's Ace | Play your lowest card of the WANTED suit first, then a higher one next time (bottom-up sequence) | Bottom-up = "yes, this suit, even though I lack the Ace to do Bargiya" | `pickFollow` discard ordering (not yet wired) | Common | Speaker: "من تحت لفوق" inverse of top-down; used when caller lacks A so cannot Bargiya |
| Sun; partner winning; multiple cards in a suit you want to dump (e.g., J + 9 of unwanted suit) | When dumping, lead with the LARGER (J before 9), not smaller | Top-down dumping is the canonical "I don't want this" pattern; reversing confuses partner | `pickFollow` discard sub-branch (not yet wired) | Common | Speaker: "اذا عندك البنت والتسعه تلعب اكبر شيء عندك البنت" |
| Sun; partner winning; you have only ONE remaining card in a refused suit (no follow-up signal possible) | Play that card; partner will resolve via the OTHER suit's signal | Single-card cases default to "play it"; the meaningful signal lives in the other suit | `pickFollow` fallback branch (not yet wired) | Sometimes | Implied by speaker showing 3-card endgame examples |
| Sun; partner winning; you signal-discard a high card (e.g., J of Spades worth 2 pts) and you actually hold the suit's T | Caveat: signal may be misread as Bargiya by partner's read | Top discard from a holding that contains T is ambiguous: partner may bring suit when you cannot SWA | document as anti-pattern (not yet wired) | Sometimes | Speaker: "ممكن انت مثلا ما يكون عندك الكاله... فخويك لعب لكه وهذا لعب الشايب وانت لعبت مثلا بنت الشريه..." — admits Tahreeb is ~70% reliable |

### Section 8 — Tahreeb (تهريب) — partner-supply convention

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Any contract; you must discard while partner controls the trick | Every discard must encode intent (positive want OR negative want for a suit) | "Each card you play must have a reason" — Tahreeb is the framework for that meaning | (not yet wired) — would need a discard-intent table | Definite | Speaker's thesis line: "اي ورقه راح تلعبها لازم يكون لها معنى" |
| Encoding "I want suit X" via discard | Either Bargiya (play Ace of X) OR bottom-up sequence in X (low first, then higher) | Two parallel idioms; Bargiya only available when caller holds top of X | (not yet wired) | Definite | The "two types of Tahreeb" listed by speaker |
| Encoding "I do NOT want suit X" via discard | Same-suit top-down (high first, low next), OR opposite-color top-card discard | Top-down within suit = strongest negative signal | (not yet wired) | Definite | Speaker's "نفس اللون عكس الشكل" + "عكس اللون" forms |
| You hold two cards of an unwanted suit AND must dump one | Always dump the LARGER (J > 9 > 8); never the smaller first | Larger first = unambiguous refusal; smaller first reads as bottom-up positive signal | (not yet wired) | Definite | Direct quote: "تلعب اكبر شيء عندك البنت" — pick J over 9 |
| You hold A of suit X and want partner to lead X | Play A on the current trick (Bargiya) | A is highest possible signal; conveys "lead X, I'll slam" | (not yet wired) | Common | Speaker labels A-discard "البرقيه" (telegram) |
| You want suit X but do NOT hold A of X | Use bottom-up: discard 7 or 8 of X first, then 9 or J on the next opportunity | Without A you can't Bargiya, so reverse the top-down pattern instead | (not yet wired) | Common | Speaker: "بدال البرقيه" — substitutes for Bargiya when no Ace |
| You hold two cards of one suit (both unwanted) AND must give two signals | Top-down within that suit, then partner reads the remaining suit (red-vs-black) as your wanted | Two negative signals → wanted suit is whatever's left | (not yet wired) | Common | Speaker's third "form" — same-suit pair both refused |

### Section 11 — Reads / partner-style inference (M3lm+ tier)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You are AKA-receiver / partner discarded high-then-low in suit X | Read: partner is REFUSING suit X; lead the OTHER suit they implied | Top-down sequence means refuse | `pickFollow` partner-style branch (not yet wired) | Common | Symmetric to the senders' rule above |
| Partner discarded low-then-high in suit X | Read: partner WANTS suit X (and lacks its Ace) | Bottom-up = positive without Bargiya | partner-style read (not yet wired) | Common | Inverse of the negative-top-down |
| Partner Bargiya'd (discarded A) of suit X | Lead suit X next opportunity; partner is claiming SWA in X | A-discard is the maximally strong "come here" | partner-style read (not yet wired) | Common | Override: still consider score state — speaker notes ~70% reliability |
| Partner sent only ONE Tahreeb signal so far | Reliability ~70%; do not commit hand on it alone | Speaker explicit: "مش مضمون 100% خلينا نقول 70%" | weight signal in `escalateDecision` heuristics (not yet wired) | Common | Avoid hard-coding 100% trust on a single Tahreeb |
| Partner did NOT respond to a Tahreeb | Three possibilities: (a) beginner who didn't read it, (b) inattentive, (c) genuinely void in the suit | Don't punish partner; re-evaluate hand from absolute strength | partner-style adjust (not yet wired) | Sometimes | Use across-game ledger entry to mark beginner-tier partners |

## 2. New terms encountered

- **برقية** (Bargiya / barqiya) — "telegram"; the special form of Tahreeb where you discard the **Ace** of a suit to signal "I want this suit, I hold the slam here". Context: "لعبت اكت الهاس هذه اسمها برقيه البرقيه تكون اكه وتكون نفس الشكل اللي تبغاه".
- **حلة / حلَّة** (halla / hilla) — "the trick / the round-of-cards"; speaker's idiom for a single trick. Context: "خويك راح ياكل الحله". Likely a colloquial synonym for "trick" (already represented in code as trick).
- **أكلة** (akla / aklah) — literally "meal"; another idiom for "a captured trick". Context: "خويك اكل اكله". Synonymous with حلة above.
- **الأخيري** (al-akheeri) — "the last one"; refers to the +10 last-trick bonus. Context: "والاخيري قلنا في 10 ابناط زياده". Maps to existing `K.LAST_TRICK_BONUS`.
- **سوا** (SWA) — already in glossary; speaker uses it casually as "lock / I have the rest" rather than the formal claim mechanic. Context: "وعندك سوا" used loosely meaning "you have the slam-out".

## 3. Contradictions

None within this transcript. Speaker is internally consistent: top-down = refuse, bottom-up = want, A-discard = Bargiya/want.

## 4. Non-rule observations

- **Thesis:** Tahreeb is "the joy of Baloot" (متعة اللعب) — every discard, especially when partner is winning, must encode a positive or negative preference for a suit. The video's full scope is **Sun-contract endgame discard signaling**, not Hokm play.
- **All examples are 3-card endgames in Sun.** The framework generalizes (speaker says "Tahreeb can be early-game too") but every concrete example uses the last-three-cards layout. Beginner level — reads/style inference are alluded to but deferred to a future video labeled "التفصيل" (tafseel).
- **Speaker explicitly says reliability is ~70%** because partners may be (a) beginners, (b) inattentive, or (c) void.
- **Pedagogical note from speaker (verbatim spirit):** don't memorize the names of the five forms — memorize the examples and apply.
- **Five "forms" enumerated by speaker:**
  1. Same-suit top-down (refuse): nfs alawn, ʿaks alshakl
  2. Cross-color top discard (refuse via opposite color): ʿaks alawn
  3. Two-card same-suit refusal: hrabt waraqatayn nfs alawn → want opposite
  4. Bargiya (discard Ace, want same suit): البرقية
  5. Bottom-up same-suit (want, no Ace): من تحت لفوق

## 5. Quality notes

- Auto-caption renders "إكَهْ" (AKA) inconsistently as "اكا" / "اكه" / "إكه". Several spots talk about "playing the إكه" where it's ambiguous whether the speaker means the AKA signal or just "the Ace" (الإكه) of a suit; context (Sun contract, no AKA signal in Sun) suggests "the Ace" in most cases.
- "هاص" / "ها" / "هاس" appear as caption transliteration of "♠ Spades" (English "Hearts" loaned in via gulf-Arabic conventions can shift). Cross-reference with example structure: speaker's "هاص" = Hearts (♥) in this video.
- "شريا / شريه" used for one suit and "ديما / ديمن / دي" for another, "سبيت / سبيد" for a third — these are caption renderings of suit names (Spades / Diamonds / Hearts) that don't 100% match standard Khaleeji spellings; rules abstract from suit names so this doesn't affect rule extraction.
- "بنت" (bint, "girl") = Jack (J), per Saudi card-naming convention. "ولد" (walad, "boy") = Queen (Q). "شايب" (shayib, "old man") = King (K). "كاله" / "كه" = Ten (T). "إكه" / "اكه" = Ace (A). Worth adding to glossary if not already there.
