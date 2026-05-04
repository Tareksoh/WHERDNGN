# Extracted from 10_tahreeb_small_to_big
**Video:** تهريب من صغير لكبير في البلوت
**URL:** https://www.youtube.com/watch?v=I-nQm6dgzv0

## 1. Decision rules

### Section 8 — Tahreeb (تهريب) — partner-supply convention

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Sun contract; you discard twice on partner's winners (e.g. partner ate Ace then Ten); first discard is SMALL, second is BIGGER (e.g. 8 of suit, then J of suit) | This is "Tahreeb min sagheer le-kabeer" (تهريب من صغير لكبير). Signals partner you want suit returned. Discard sequence ascending = "I want this suit back". | 100% reliability per video — the strongest tahreeb signal in Baloot. Two ascending discards = unambiguous request. | `pickFollow` discard logic (Bot.lua:1457) — `(not yet wired)` as cross-trick discard pattern | Definite | Lines 7-30: "اقوى تهريب في البلوت" — strongest tahreeb. Reliability stated as 100% (line 27). |
| You're discarding (no card in led suit / no need to win) and you HAVE a higher and a lower spare in target suit, AND you do NOT hold the Ten of that suit, AND you want partner to return that suit | Throw the SMALL card first, then the BIGGER card on the next discard. Sequence: small → big = "I want this suit". | The signal direction encodes intent. Reverse (big → small) = "I do NOT want this suit". | `pickFollow` discard branch (Bot.lua:1457) — `(not yet wired)` | Definite | Lines 29-36, 117-128. Explicit: "العب سبعه بعدين ثمانيه" if you want the suit; "العب ثمانيه بعدين سبعه" if you don't. |
| You're discarding and you DO NOT want partner to lead that suit (e.g. you have nothing protecting it) | Discard BIG → SMALL (descending). E.g. J first, then 8. This explicitly tells partner "do not return this suit". | Inverse of small-to-big convention. Without this discipline, partner cannot read intent. | `pickFollow` discard branch (Bot.lua:1457) — `(not yet wired)` | Definite | Lines 22-24, 33-36, 117-128. |
| Partner has tahreeb-ed you small→big in suit X; you hold the Ten of suit X | Lead the Ten of suit X back to partner (best return). | Partner's small→big tahreeb implies partner does NOT have the Ten — supply it. | `pickLead` partner-return branch (Bot.lua:953) — `(not yet wired)` | Definite | Lines 41-48: "اذا كانت 10 جدا كويس روح له بالعشره". |
| Partner has tahreeb-ed you small→big in suit X; you do NOT hold the Ten | Lead the largest card you hold in suit X back to partner. | Honor the request even without the Ten. | `pickLead` partner-return branch (Bot.lua:953) — `(not yet wired)` | Definite | Lines 45-47: "تروح له بالورقه الكبيره اللي عندك". |
| You're the discarder doing small→big tahreeb | Implies you do NOT hold the Ten of the tahreeb-ed suit (otherwise you'd lead it yourself). Partner should infer this. | The whole purpose: "I'm telling you I want it BUT I can't supply the top". | `pickFollow` style-ledger inference (Bot.lua:1457) — `(not yet wired)` | Definite | Lines 36-43: "ما عندك العشره... خويك لازم يفهم... انك تبغى الشكل وايضا ما عندك العشره". |
| Single discard only (one tahreeb card so far, e.g. partner ate Ace; you discarded a 7); you cannot win the next trick | Default-assume partner will follow with a higher card of the same suit (small→big from one discard). Treat the single small discard as a tentative tahreeb signal. | Heuristic prediction one move ahead based on smallness of the discard. | `pickLead` next-trick prediction (Bot.lua:953) — `(not yet wired)` | Common | Lines 49-62. "هو ما هرب لك المره الثانيه ولا لعبت انت المره الثانيه لكن انت تتوقع". |
| Same single-discard scenario; partner discarded a SMALL card (7, 8, 9) | Strength of small→big inference scales with how SMALL the discard was. 7 = strong inference, 8/9 = medium, J/Q = do NOT infer tahreeb. | Smaller cards are more obviously "throw-aways", so more clearly intent-bearing. Higher cards (J, Q) are too costly to be casual signals. | M3lm+ ledger heuristic — `(not yet wired)` | Common | Lines 73-82: "كل ما يصغر الورق كل ما تفترض انه ممكن يهرب لك من تحت لفوق". |
| Single small discard but you have NO card in that suit yourself | Override / cancel: if you cannot lead the suit, the tahreeb prediction is moot — play your own plan. Do NOT lead an unrelated suit just because partner MIGHT continue tahreeb. | The tahreeb hint can't be acted on; don't let it distort your lead. | `pickLead` partner-return branch (Bot.lua:953) — `(not yet wired)` | Common | Lines 62-66: "لكن لو انت اصلا ما عندك سبيت... هذا التهريب لغيته". |
| Opponent (not partner) does small→big tahreeb on you | Recognize that opponent wants that suit returned by their partner. Do NOT give it to them — i.e. do not lead that suit; treat it as a suit to AVOID returning. | Same convention applies to opponents — useful for read. Useful when opponent's partner has cards there. | `pickLead` opponent-read branch (Bot.lua:953) — `(not yet wired)` | Common | Lines 131-142: "لو الخصم هرب من تحت لفوق لازم تفهم انه يبغى نفس الشكل". |
| You're tahreeb-ing across THREE discards (you must dump three cards in suit X across three of partner's tricks); you have e.g. 7, 9, J in suit X | Discard the two smallest IN ASCENDING ORDER (7 then 9), keep the biggest (J) for last or for self-protection. Avoid mixing direction (e.g. 7 → J → 9 looks like reversal and confuses partner). | Three-card sequence small-to-big-to-bigger remains coherent; any descending step looks like a "no" signal. Also keep J for cases where opponent might hold the Q. | `pickFollow` extended discard pattern — `(not yet wired)` | Common | Lines 95-115. |

## 2. New terms encountered

| Arabic | Transliteration | Meaning | First-line |
|---|---|---|---|
| تهريب من تحت لفوق / من صغير لكبير | tahreeb min taht le-fawg / min sagheer le-kabeer | "Smuggling from low to high" / "from small to big" — discard sequence ascending in value across two consecutive partner-won tricks, signalling "I want this suit returned" | line 8-9 |
| اقوى تهريب | aqwa tahreeb | "the strongest tahreeb" — claimed at 100% reliability | line 9, 27 |
| تهريب البرقيه | tahreeb al-barqiyya | "telegraph tahreeb" — referenced as the strongest single-discard tahreeb (separate video). Possibly a one-shot variant. | line 12 |
| لغه البلوتو | lughat al-Baloot | "the language of Baloot" — phrase used to describe tahreeb conventions as the only partner-communication channel | line 114-115 |

## 3. Contradictions

None internal to this video. With video #9 ("essential tahreeb"): no direct contradiction yet — small→big appears to be a SPECIFIC variant of tahreeb keyed to multi-discard sequences, while #9 likely covers single-discard tahreeb. Need #9 transcript to confirm.

## 4. Non-rule observations

**Small-to-big Tahreeb — exact card sequence:**

The pattern requires partner to win two consecutive tricks (e.g. partner leads Ace, then leads Ten in the same suit). On EACH of those tricks, you (discarder) are void in led suit and choose what to throw. The signal is:

1. **First discard:** the SMALLER spare card from your target suit (e.g. 8 of clubs).
2. **Second discard:** the BIGGER spare card from your target suit (e.g. J of clubs).

Example from transcript (Sun contract; partner leads Diamond Ace then Diamond Ten):
- Trick 1: you throw 8 of Spades.
- Trick 2: you throw J of Spades.
- Translation: "I want Spades. I do NOT have the Ten of Spades. Lead Spades to me — preferably your Ten if you have it, otherwise your highest Spade."

Reverse (J first, then 8) = "I do NOT want Spades; do not return."

**Cross-trick vs single-trick:**

This is a **CROSS-TRICK / multi-trick** pattern. It requires TWO tricks to fully express. The two cards are played on different tricks, both as discards (you are not the leader, you are not following the led suit, and you are not winning).

This distinguishes it from single-trick tahreeb (a single discard read as a hint) and from leading-tahreeb (where you LEAD a small card to draw partner out). The video explicitly notes (lines 49-82) that with only one discard observed, the inference is weaker — partner can only PREDICT the second card based on smallness of the first.

**Comparison with "essential Tahreeb" (video #9):**

Best guess: #9 (essential tahreeb) is the BROADER category — covering single-discard tahreeb, leading tahreeb, and the general "throw a small card to hint" mechanic. #10 (small-to-big) is a SPECIFIC SUBSET / VARIANT — the multi-discard cross-trick form, which the speaker explicitly calls "the strongest" (اقوى تهريب) at 100% reliability when fully expressed across two discards.

The speaker references #9 by mentioning "تهريب البرقيه" (telegraph tahreeb) and "التهريب بشكل عام" (tahreeb in general) as separate prior videos with descriptions in the video's metadata (lines 11-14). This suggests #10 is a follow-up that drills into one specific high-reliability form. Implementation-wise: the small→big signal should sit ALONGSIDE #9's rules, not replace them.

## 5. Quality notes

- Transcript is 145 lines, dense, no advertising filler. Auto-captioned Arabic with typical OCR/ASR errors (e.g. "اكا" misrendered as variants, "السبيد" likely "السبيت" = spades).
- Suit examples in the video use الديمن (diamonds), السبيت (spades), الشريحه (clubs / "trefle"), and reference cards like الولد (Jack), الشايب (King), البنت (Queen). Saudi card-naming consistent with glossary.
- The video is self-contained on this rule but assumes viewer has watched #9 ("essential tahreeb") for foundational concepts.
- One minor inconsistency: line 17 mentions "هرب ثمانيه السبيت" then line 18 "هرب الولد" — the J is the "big" in this 8→J pair. Confirms cross-suit example: Sun contract, opponent leads Aces in Diamonds, partner discards Spades (8 then J).
- Confidence rating: rules are stated definitively and repeatedly by the speaker; this is "Definite" for the core mechanic. Single-source for now (one video) — but speaker frames it as a fixed convention ("قاعده ثابته ما فيها نقاش", line 113-114) consistent with strong community standard.
