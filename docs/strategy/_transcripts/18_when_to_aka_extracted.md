# 18_when_to_aka — Extraction

**Source:** https://www.youtube.com/watch?v=V_xTjwSSKyQ
**Title:** متى تقول اكة في البلوت
**Slug:** 18_when_to_aka
**Topic:** AKA-call timing in Hokm — preconditions, partner-trump-read decision matrix
**Code anchor:** `Bot.PickAKA` (Bot.lua:1686)

---

## 1. Saudi-term map

| Arabic | Code identifier / English | Note |
|---|---|---|
| تاكيك / تاك | "calling AKA" — verb form | Speaker uses interchangeably with "قول إكَهْ"; both = announce AKA on a card |
| إكَهْ (AKA) | partner-call signal | `K.MSG_AKA` |
| إكَه / الإكه | Ace card | Distinguished phonemically from AKA |
| حكم / في الحكم | Hokm contract | `K.BID_HOKM` |
| صن | Sun contract | `K.BID_SUN` — speaker: "في الصن ما في شيء اسمه تاكيك" |
| قيد / فيها قد | "penalty / it's a penalty (call)" | Illegal-AKA penalty — Takweesh-adjacent (`K.MSG_TAKWEESH`) |
| الشريه / السبيت / الديما / الهاص | Hearts / Spades / Diamonds / Clubs | suit slang |
| العشره | T (Ten) | top non-trump after Ace |
| الشايب | K (King) | |
| البنت | Q (Queen) | |
| السبعه | 7 | speaker example: "if all higher hearts dead, even the 7 is AKA-eligible" |
| توضيح لعب | "play-clarification" | Speaker's gloss for what AKA leaks — some opponents call قيد on AKA-on-Ace because it telegraphs the T |
| دق بالحكم | trump-ruff (verb) | maps to existing `daqq` glossary entry |
| كبوت / تخرب كبوت | Al-Kaboot / "ruin the Kaboot" | `K.AL_KABOOT_HOKM`=250 |

---

## 2. Decision rules

### 2.1 — AKA preconditions (the four hard gates)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|
| Contract is Sun (`K.BID_SUN`) | **Never call AKA.** AKA does not exist in Sun. | Saudi rule: "في الصن ما في شيء اسمه تاكيك". | `Bot.PickAKA` Bot.lua:1686 — gate-off when `S.s.contract.bidType == K.BID_SUN`. Verify already enforced. | Definite |
| Card you intend to AKA is **trump (الحكم)** | **Never call AKA on a trump card** — this is a قيد (penalty). | Saudi rule: AKA is a non-trump-only signal in Hokm. | `Bot.PickAKA` Bot.lua:1686 — reject `card.suit == S.s.contract.trumpSuit`. | Definite |
| Card you intend to AKA is the Ace (إكَه) of its suit | **Never call AKA on the Ace.** Ace is self-evident — calling AKA on it is "play-clarification" and many tables enforce قيد. | "الاكه هي اكه بنفسها من اسمها ما يحتاج تقول عليها اكا"; some seats call قيد because AKA-on-Ace leaks the T. | `Bot.PickAKA` Bot.lua:1686 — reject when `card.rank == "A"`. | Definite |
| The card is NOT the **highest unplayed card** of its (non-trump) suit | **Never AKA.** AKA asserts top-of-suit; if a higher one is unplayed, the call is illegal (قيد). | Saudi rule: AKA = "the boss of this suit, no higher exists". | `Bot.PickAKA` Bot.lua:1686 — verify `card == highestUnplayed(suit)` against `Bot._memory[*].playedCards`. | Definite |
| The trick is NOT yours to lead — opp/partner is leading and you are following suit | **Never AKA.** AKA can ONLY be called when you are LEADING with that card on YOUR turn. | Speaker explicit: "لازم اللعب يكون على يدك وانت تلعب اول ورقه". A follow-card AKA is قيد. | `Bot.PickAKA` Bot.lua:1686 — gate on `S.s.trick.cardsPlayed == 0 && S.s.trick.leadSeat == mySeat`. | Definite |

### 2.2 — AKA decision matrix (call vs skip)

Speaker's structure: 3 own-confidence states × 3 partner-trump states = 9 cells. Below is the consolidated rule per cell.

| Self-confidence: top of suit | Partner has trump? | RULE | WHY |
|---|---|---|---|
| **Certain** I hold the boss | Certain partner HAS trump | **AKA — always.** | Partner suppresses the forced ruff → you keep this trick AND partner ruffs the next opp lead → +2 tricks vs no-AKA. |
| Certain | Uncertain partner has trump | **AKA — always.** | "ما انت خسران سواء طلع خويك عنده حكم ولا ما عنده حكم." Free signal — even if partner is void, you didn't lose anything by saying it. |
| Certain | Certain partner is **VOID** in trump | **Do NOT call AKA.** | The whole point is suppressing partner's forced ruff; if they have no trump, AKA conveys nothing and just leaks info. |
| **Uncertain** (you don't know if it's the boss) | Certain partner HAS trump | **Do NOT call AKA** *(default; situational override below)*. | If you're wrong → قيد penalty AND you may break Kaboot. "خويك حيلومك وحيفصل عليك". Skipping costs at most one trick; calling-and-wrong costs قيد + Kaboot loss. |
| Uncertain | Uncertain partner has trump | Do NOT call AKA. | Same downside risk; no upside guarantee. |
| Uncertain | Certain partner is void in trump | Do NOT call AKA. | No mechanism for upside even if you're right. |
| **Certain** the card is **NOT** boss (a higher live exists) | (any) | **Do NOT call AKA — illegal/قيد.** | Already covered by precondition gate, but speaker repeats it explicitly here. |

### 2.3 — Override: early-round risk-tolerance

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|
| Self-confidence = uncertain BUT round is in **early stage** AND score is non-critical (not double, not opponent near match-target) | **AKA is acceptable** despite uncertainty. | "بدايه الجيم لسه عوافي" — early-round penalty is recoverable. Late round / sensitive score → don't gamble. | `Bot.PickAKA` Bot.lua:1686 — relax precondition strictness when `#tricks <= 2 && scoreUrgency(myTeam) < threshold`. | Common |
| Self-confidence = uncertain AND **opponent close to match-target** OR contract is **doubled** (`mult >= K.MULT_BEL`) | Even more conservative — **never AKA on uncertainty.** | "اذا اللعب حساس ولا الخصم مره فوق صعبه فهنا غلطتك حتاثر عليكم اكثر". | `Bot.PickAKA` Bot.lua:1686 — tighten when `S.s.contract.multiplier >= K.MULT_BEL || matchPointUrgency(theirTeam) >= K.URGENCY_HIGH`. | Common |

### 2.4 — Receiver convention (re-confirms v0.5.1 H-5)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE |
|---|---|---|---|---|
| Hokm; partner led non-trump suit X and announced AKA; you are void in X and would normally be forced to ruff with trump | **Suppress the forced ruff** — discard a side-suit card instead. Partner's AKA = "I take this trick, save your trump." | Speaker explicit: "خويك مش مجبر يدق بالحكم". Already wired in v0.5.1 H-5. | `pickFollow` Bot.lua:1457 AKA-receiver branch — already implemented. **No change needed; this transcript confirms the existing fix.** | Definite |
| Hokm; partner led the **Ace** of non-trump suit X (no AKA announced); you are void | Same suppression rule applies — Ace is implicitly AKA. | Speaker: "الاكه هي تاكيك نفسها بنفسها كانك قلت عليها اكه عشان كده اذا قلت اك لاي ورقه خويك مش مجبر يدق بالحكم." | `pickFollow` Bot.lua:1457 — extend AKA-receiver branch to fire on partner's Ace-lead even when `S.s.akaCalled == false`. **Refinement candidate.** | Definite |

### 2.5 — Suit selection when multiple AKA-eligible suits

Transcript does NOT directly address "which AKA-eligible suit do you pick when several are legal". Speaker's framework only covers *whether* to call AKA on the boss-of-suit you're leading; the suit-selection question reduces to the lead-suit choice (Section 3 / `pickLead`), independently of AKA. **No new rule extracted here.**

---

## 3. Non-rule observations (per format spec)

**AKA-call preconditions** — Four hard gates (must ALL pass before AKA is even considered):
1. Contract is Hokm (not Sun).
2. Card is non-trump.
3. Card is NOT the Ace of its suit (Ace is implicit-AKA).
4. Card IS the highest unplayed of its (non-trump) suit.
5. (Procedural) You are the trick-leader and this is the first card of the trick.

The 7 of a non-trump can be AKA-eligible if A/T/K/Q/J/9/8 are all dead — pure highest-unplayed test, not a rank floor.

**Timing — early-trick AKA vs late-trick AKA** — Speaker frames AKA primarily as a **lead-trick announcement**, not bound to "trick 1 vs trick 8". The timing nuance is *round-stage* not *trick-position*: early-round AKA can tolerate uncertainty (recoverable penalty); late-round / high-stakes AKA must be ironclad. **Existing `signals.md` line "AKA at trick-1 or trick-2 is the strongest read; later AKA is sometimes a bluff" is consistent** but the new transcript reframes the axis from *trick-index* to *round-stage × score-urgency*. Recommend updating `signals.md` to reflect the urgency axis.

**Suit selection** — Transcript silent. The decision sits in `pickLead`, not `Bot.PickAKA`; AKA is downstream of which suit you chose to lead.

**Anti-triggers** — Three crisp anti-trigger cases, all already encoded above:
1. Card is trump → قيد (illegal).
2. Card is the Ace → قيد (some tables) AND informational leak (telegraphs the T).
3. Partner is **certainly void in trump** → no upside; AKA leaks info for zero gain.
Plus one soft anti-trigger: high-uncertainty + high-stakes round (doubled / opponent near target).

**Receiver expectation** — v0.5.1 H-5 fix is **confirmed verbatim**: partner suppresses forced ruff under partner's AKA. **Refinement found:** the same suppression should fire when partner leads the Ace of a non-trump, even without an explicit AKA announcement. Speaker treats Ace-lead and AKA-lead as semantically identical for the receiver. This is one new wired branch in `pickFollow`.

---

## 4. Open questions for future videos

- **AKA on a card other than the leader of the trick** — speaker implies ONLY trick-leader can call AKA; but is there a "delayed AKA" convention if you draw down to bare-boss mid-trick?
- **AKA and partner's Tahreeb interaction** — if partner has Tahreeb'd suit X away (negative signal), does that pre-empt your AKA on suit X? Not addressed.
- **Suit selection among multiple AKA-eligible suits** — needs a separate video.

---

## 5. Source provenance

Transcribed from V_xTjwSSKyQ (Saudi YouTube, instructional). Speaker is the same channel as videos 01-10. Phrasing is unambiguous on the four hard gates and the 9-cell decision matrix. Override rule (early-round tolerance) is single-source — log as `Common` per project rule (single source + emphatic + corroborated by existing `signals.md`).
