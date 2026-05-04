# Extracted from 09_most_essential_tahreeb
**Video:** اكثر تهريب تحتاجه في البلوت
**URL:** https://www.youtube.com/watch?v=JUT6N-eZwD8

## 1. Decision rules

### Section 8 — Tahreeb (تهريب)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Receiver: partner Tahreebs me a card in suit X (single Tahreeb event) | Initial read: partner does NOT want suit X. Three remaining suits in play; redistribute weighting accordingly. Treat first Tahreeb as the "Aka of broadcast" — partner is signalling "not this" and pointing toward another suit. | First-Tahreeb axiom from speaker: "if partner Tahreebs you a card it (almost) means he doesn't want it" | `pickFollow` Bot.lua:1457 + style ledger; `(not yet wired)` for Tahreeb-receiver inference | Definite | Speaker calls this "the first essential rule"; lines 21-24 of transcript |
| Receiver: partner Tahreebs LOW card first (e.g. 7/8/9) — single event | Default suit prior: ~70% partner wants the OPPOSITE COLOR HIGH suit (e.g. led-Spade-Tahreeb → wants Hearts), ~25% wants the same-color other-shape suit, ~5% wants Diamonds (the partner's strongest from before). Wait for second Tahreeb to disambiguate. | One Tahreeb is ambiguous; need a second hop to confirm. Speaker: "Tahreeb needs another Tahreeb to confirm." | `pickFollow` style-ledger reads; `(not yet wired)` | Common | Lines 26-46. Probabilities approximate; note speaker explicitly enumerates 70/25/5. |
| Receiver: partner Tahreebs SECOND card LOWER than first in same direction (e.g. first Jack, then 9 — high-to-low) | Confirmed: partner wants the OPPOSITE color (Hearts in this example). Probability ~90%. Lead Hearts on next opportunity. | High-to-low or low-to-high pair across two Tahreebs is the disambiguation signal | `pickFollow` two-Tahreeb sequence detector; `(not yet wired)` | Definite | Lines 60-77. Speaker: "100% he doesn't want Diamonds, doesn't want Spades — must be Hearts." |
| Receiver: I have NO eat (no winning card) on the second Tahreeb attempt | Send your highest available card back to partner — this is itself a fine art (فن). Don't waste a low card; the high return is your only contribution. | Even when forced, cooperate maximally with the Tahreeb signal | `pickFollow` Bot.lua:1457 high-card-return branch; `(not yet wired)` | Common | Lines 51-58 |
| Receiver: I have a SECOND eat available beyond the first | Use the second eat to win the next trick — this lets partner do a second Tahreeb so you can fully read the signal | Eating creates the lead-back opportunity needed for partner's confirming Tahreeb | `pickFollow` Bot.lua:1457 information-gain branch; `(not yet wired)` | Common | Lines 59-62 |
| Sender: I have strength in suit X (e.g. Hearts) and want partner to lead Hearts to me | Tahreeb a LOW card from one of the other three suits; choose by the convention "opposite-shape" or "opposite-color" mapping you and partner have agreed (the speaker treats Spade-Tahreeb as the simplest signal for "I want Hearts") | Tahreeb is the only way to ask partner to attack a specific suit when you can't lead it yourself | `pickLead` Bot.lua:953 Tahreeb branch; `(not yet wired)` | Definite | Lines 110-117 |
| Sender: partner just ate trick and led Diamond-10 (high) | Do NOT play the lowest Diamond (e.g. 7). Play the SECOND-LOWEST or middle (e.g. Jack/9) when you must follow. Holding the lowest = "biggest mistake in Baloot" — opponents will jam/ride the trick. | Playing the absolute lowest invites opponents to over-take cheaply; mid-card preserves cover | `pickFollow` Bot.lua:1457 follow-suit-discard branch; `(not yet wired)` | Definite | Lines 134-141. Speaker: "tilbu il-saba'ah hatha akbar ghalaT fil-balout." |
| Sender: I want to Tahreeb but the suit I'm strong in (e.g. Spades) only has 3 cards in my hand | Don't Tahreeb FROM your strong suit. Tahreeb FROM a weak side suit using the agreed signal-shape mapping. Speaker example: "if I'm strong in Spades I Tahreeb a low Spade-→reverse mapping" — but reads as: send the low card from a NON-target suit. | Burning your own strong suit defeats the purpose; hold the strong suit for the actual attack | `pickLead` Bot.lua:953 Tahreeb-suit-selection; `(not yet wired)` | Common | Lines 110-117 |
| Sender: it is my turn and I have strength in side-suit; partner has not eaten yet | Hold the strong card (e.g. Diamond-10) for the END of the round; lead the Tahreeb signal first. Playing the 10 early lets opponents equalize/cut. | Strong-card timing — keep it as the final winner not the opening shot | `pickLead` Bot.lua:953 strong-card-hold branch; `(not yet wired)` | Common | Lines 128-138 |
| Sender: confirming Tahreeb after the first | Tahreeb the SECOND card in the SAME direction (low-to-high or high-to-low) within the SAME signal-suit. Don't switch suits between Tahreebs. | Direction (ascending vs descending) within one suit IS the message | `pickLead` two-call signal; `(not yet wired)` | Definite | Lines 67-77. Speaker: "tahreeb yasghar likabir, aw min kabir li-saghir." |
| Sender (substitute Tahreeb): instead of Diamond-10 I lead Diamond-Jack first | After partner responds, second Tahreeb should be the 10 (NOT the 7). Always play the larger of the two confirming cards. | Mirror-image of the previous rule for the high-to-low direction | `pickLead` two-call signal direction-2; `(not yet wired)` | Common | Lines 156-169 |

---

## 2. New terms encountered

| Arabic | Transliteration | Meaning | Notes |
|---|---|---|---|
| الشريحه / شرير | shareeha / shareer | Hearts (heart suit) — Saudi colloquial. Speaker uses both. | Frequent throughout transcript. Add to glossary suit-color section. |
| الدايمه / دايمن | dayma / dayman | Diamonds (suit) | Lines 17, 34, 65 etc. |
| السبيت / السبيد | sbeet / sbeed | Spades (suit) | Lines 29, 73 |
| الهاس / الهاوس | haas / haus | Clubs? (the suit speaker pairs as opposite-color of Hearts in this video). Possibly Hearts variant — confirm. **TENTATIVE** | Lines 32, 76. Speaker treats Haas as "opposite-color" of one of the other suits; mapping ambiguous. |
| فن (fan) | fann | "Art / craft" — used to describe the high-card-return technique when you can't eat partner's Tahreeb | Line 56 |
| تهريب نفس اللون عكس الشكل | tahreeb nafs al-lawn 3aks ash-shakl | "Same color, opposite shape" Tahreeb — variant 1 of three Tahreeb signal types | Line 4 |
| تهريب عكس اللون | tahreeb 3aks al-lawn | "Opposite color" Tahreeb — variant 2 | Line 4 |
| تهريب عكس شكل الارض | tahreeb 3aks shakl al-arD | "Opposite of the led-suit shape" Tahreeb — variant 3, requires double-call | Line 5 |

---

## 3. Contradictions

None internal to this video. Note: speaker explicitly says "forget the names" of the three Tahreeb variants and focus on examples — suggests prior video #1 had taxonomy that this video collapses to a probability-weighted single rule.

---

## 4. Non-rule observations

**The essential Tahreeb** — exact trigger conditions, exact card to play, exact partner expectation:

- **Trigger:** I am the receiver. Partner has just won a trick (eaten) and now leads a clearly LOW card (7, 8, or 9) of a side-suit (not trump for the contract being played).
- **Action by receiver (the "essential" read):** Treat partner's Tahreeb as a NEGATIVE signal about the led suit ("I don't want this suit") combined with a POSITIVE pointer toward another suit. With ONE Tahreeb event, default to the 70/25/5 prior described in the rules table. Eat with my second-best card if I can (NOT my lowest), so I can lead back.
- **Action by sender (the "essential" play):** When I want partner to attack my strong suit X, I lead a low card from a side-suit (not X). Partner reads this as "lead X back to me." If partner doesn't read it, I do a SECOND Tahreeb in the same suit, in a direction (ascending/descending) that confirms the target suit.
- **Exact card to play (sender side):** the LOW card of the agreed signal suit. If I'm strong in Spades and want partner to lead Spades, I Tahreeb the SEVEN of a side-suit. Never the highest card of the target suit; never the lowest of a 3-card suit I want to keep.
- **Partner expectation:** receiver eats with their HIGHEST eat if forced, or holds the second-eat to enable a second-Tahreeb cycle. Receiver leads the inferred target suit on the FIRST opportunity after the second Tahreeb confirms direction.

**Frequency** — how often should this fire?
- Speaker treats this as a play-pattern that should fire MULTIPLE times per round when partnership communication is the active strategy. Specifically: every time a player on a partnership ends up with a strong side-suit they cannot lead themselves (e.g. they're in pos-3 or pos-4 and partner is leading), the Tahreeb signal should be the default attempt to establish the suit. Realistically: at least ONCE per round in most rounds, often TWICE (initial + confirming). Across a full game (multiple rounds to 152) this is the SINGLE MOST COMMON partnership-coordination tool — speaker frames it as "the Tahreeb you most need."

**Failure mode** — what goes wrong if a player skips this Tahreeb when they should have done it?
- Receiver-side failure: if the receiver ignores partner's Tahreeb and just leads their own strongest suit, they burn partner's setup and likely play into the opponents' hand. Opponents capture the strong suit and the bidder team loses tempo. Speaker explicitly warns at line 134: leading the SEVEN (lowest) instead of the middle = "biggest mistake in Baloot" — opponents jam the trick and equalize.
- Sender-side failure: if the strong-suit holder fails to Tahreeb and instead plays their high card into a contested trick, the high card gets cut/over-trumped or opponents finesse it. The strong suit is wasted. Equivalently: leading the strong card EARLY (line 128 — "ihtfith fiha wa khalliha lil-akhir") instead of holding it for the round-ender means opponents can equalize.
- Net: the Tahreeb cycle is the partnership's main mechanism for delivering points to the strong hand. Skipping it leaves 30+ points per round on the table on average.

---

## 5. Quality notes

- Transcript is a single Saudi monologue, no diarization issues.
- Suit naming inconsistent: speaker uses شريحه / شرير / الشرع interchangeably — all = Hearts. الدايمه / الدايمن = Diamonds.  السبيت / السبيد / السبيل = Spades. الهاس / الهاوس = Clubs (best guess; confirm against video #1 since it is the one term I'm least certain of).
- Speaker references "previous video on Tahreeb" (likely 01_tahreeb_beginners) at line 6 — the three Tahreeb variant names are defined there and DELIBERATELY de-emphasized here. This video is the operational compression: forget names, use the receiver-side probability prior + sender-side double-Tahreeb confirmation.
- Probability numbers (70/25/5 and 90%) are explicit speaker quotes, not my interpolation. Useful as direct picker thresholds.
- Lines 134-141 have the cleanest "biggest mistake in Baloot" quote — load-bearing for `pickFollow` discard discipline.
- Several rules are HIGH confidence (Definite) because the speaker repeats the prescribed action across multiple worked examples (single + double Tahreeb examples, sender + receiver perspectives).
