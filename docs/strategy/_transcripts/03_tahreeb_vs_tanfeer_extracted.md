# Extracted from 03_tahreeb_vs_tanfeer
**Video:** حالة بين التهريب والتنفير في بلوت
**URL:** https://www.youtube.com/watch?v=_QI8wcpnrNU

## 1. Decision rules

### Section 8 — Tahreeb (تهريب)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Partner has 100% taken (will surely win) the trick (e.g. via AKA), and play comes to you while you can ruff/cut on a different suit later — you are about to discard on partner's certain trick | Discard a card whose suit you DO NOT want partner to lead back. The discard is itself a Tahreeb message: "I am not asking for this suit." | Tahreeb is a negative signal — every card you Tahreeb implies "don't return this suit, except the suit I'm withholding." | `pickFollow` (Bot.lua:1457) discard branch when partner is already winning; (not yet wired as signal) | Common | Speaker: قاعده تهريب الاساسيه اي ورقه يهربها خويك او انت تهربها يعني ما تبغاها باستثناء |
| You must Tahreeb (partner is sure to win) and your hand has weak cards (no honors, no Ace) in some suits | Tahreeb a weak suit — a suit you have nothing in / don't need. Partner reads "no Ace there" and won't return it. | Discarding weakness signals where you are NOT strong; partner uses the inverse to decide return suit. | `pickFollow` discard when partner-wins-trick; (not yet wired) | Common | Example: holding T+J of one suit, you would NOT Tahreeb that suit; you'd Tahreeb a junk suit |
| You must Tahreeb and you hold a "medium" suit (≥1 Ace but no real strength beyond it) | Tahreeb that medium suit (lead/discard the Ace's suit small card) so partner reads "I have at least the Ace there — return it." | Tahreeb on Ace-only suit invites partner to return it; bot says: "اقل شيء اكه واحده ورق يعتبر متوسط ... المفروض تلعب ابشر عشان خويك يفهم انه انت عندك" | `pickFollow` discard branch; (not yet wired) | Common | "ابشر" appears to be an OCR/transcription artifact for the Ace small-card the speaker is gesturing at |
| You must Tahreeb and you hold a STRONG suit (e.g. K + T after the Ace has gone, or two top cards left) | Do NOT Tahreeb the strong suit. Tahreeb a different suit. Partner will return the OPPOSITE-color/opposite suit by convention, which is exactly the strong one you're protecting. | Strong suits should be preserved; the convention is "Tahreeb away from your real holding" — partner returns what you withheld. | `pickFollow` discard branch; (not yet wired) | Common | Example given: when partner played J of trump and you held K+T elsewhere, you Tahreeb a different suit so partner returns the K+T color |
| You yourself become the cutter (will ruff a led suit), AND it is partner who has 100% taken some prior reference trick | Your ruff IS the Tahreeb event — the suit you choose to discard while ruffing carries the message | Tahreeb works through any card you "throw away" while a teammate is winning, not just on partner's lead | `pickFollow` ruff branch | Common | "ولما نجي الدور عندك انت راح تقطع فبالتالي اذا قطعت هذا اعتبر تهريب" |

### Section 9 — Tanfeer (تنفير)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| OPPONENT (not partner) has 100% taken the trick, you are forced to discard, and you ruff/cut | The discard is a Tanfeer. Tanfeer's rule is INVERSE to Tahreeb: the suit you discard IS the suit you want partner to return / the suit you're strong in. | Against an opponent there's no point hiding your strength via "negative discard"; instead you discard a suit you DO want, signaling partner. | `pickFollow` discard branch when opponent-wins-trick; (not yet wired) | Common | "بالنسبه للتنفيذ عكس التهريب تماما ... اذا انت نفرت يعني تبغى الشكل او عندك اكه الشكل" — note transcript spells it تنفيذ but means تنفير |

### Section 8/9 — Ambiguity case (the core point of this video)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You are about to discard, and it is UNCERTAIN who wins the current trick (e.g. opponent led the J of trump, you are void and will ruff, but you don't know whether partner or the 4th-seat opponent holds the higher unplayed trump) | Default to Tahreeb semantics, not Tanfeer. Tahreeb is the stronger / more reliable convention; partner will read the discard as a Tahreeb message. | "بحكم انه التهريب اقوى من التنفيذ وقاعده تهريب تمشي معاك اكثر من التنفيذ" — Tahreeb is "stronger" and "applies more often" than Tanfeer. | `pickFollow` discard branch when trick-owner uncertain; (not yet wired) | Common | The whole video is built around this case |
| Trick-owner uncertainty is roughly 50/50 partner-vs-opponent | Treat as Tahreeb (above row) | Same — Tahreeb dominates as the default convention | (not yet wired) | Common | Speaker explicitly walks through 50/50 and 45/45/10 splits |
| Trick-owner uncertainty leans 45% partner / 45% one opponent / 10% other opponent | Still treat as Tahreeb (above row); the slight tilt does not flip the rule | Tahreeb is the prior; only flip to Tanfeer when opponent-wins is certain (≈100%) | (not yet wired) | Common | |

### Section 6 — Signaling (Tahreeb/Tanfeer as a partner-message channel)

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| You are the partner observing a teammate Tahreeb (they discarded suit X while you were 100% winning) | Read: "partner has nothing in suit X." On your next lead, do NOT lead suit X back to them. Lead a different suit — by convention, the opposite-suit-of-the-same-color or the suit they DIDN'T Tahreeb. | Tahreeb is a deliberate message; partner signaling logic should consume it. | `pickLead` style-ledger reads (M3lm+); style-ledger key (proposed) | Common | "لا تنسى ان التهريب رساله لخويه يعني اي ورقه تهربها تقصد فيها حاجه" |
| Your partner Tahreebs a "medium" suit (suit where they signal they hold the Ace) | On the lead-back, return THAT suit | Inverse of weak-Tahreeb: medium-Tahreeb is an invitation, not a denial | (not yet wired) | Sometimes | Single source so far |
| Your partner Tahreebs and you can infer they had a strong suit elsewhere (because they did NOT Tahreeb it) | Lead the OPPOSITE-color/opposite suit on return — this matches the suit they were protecting | "عكس اللون / عكس الشكل" — the "opposite suit" / "opposite color" return convention | `pickLead` partner-return logic; (not yet wired) | Common | The video uses "شكل" (suit-form) and "لون" (color) somewhat interchangeably |

---

## 2. New terms encountered

| Arabic | Transliteration | Meaning in this video |
|---|---|---|
| باستثناء | bi-istithnaa' | "with the exception of" — used in Tahreeb's core rule: "I don't want any suit I Tahreeb, **except** the one I'm signaling." |
| عكس اللون / عكس الشكل | 'aks al-lawn / 'aks ash-shakl | "opposite color / opposite suit" — partner-return convention after Tahreeb |
| فئه ضعيفه / متوسطه / قويه | fi'ah da'eefah / mutawasitah / qawiyyah | "weak / medium / strong category (of suit holding)" — the speaker's tripartite classification of the suit you hold when choosing what to Tahreeb |
| توقع الحله | tawaqqu' al-hilah | "predicting the trick (outcome)" — speaker references a separate video by this title for inferring trick-owner probability |

Note: transcript repeatedly writes **تنفيذ** ("execution") where the speaker clearly means **تنفير** ("repulsion/Tanfeer"). This is an Arabic auto-caption homophone error; the spoken word is Tanfeer throughout.

---

## 3. Contradictions

None within this video.

Versus other strategy docs: glossary placeholder for Tanfeer ("forcing opponent to discard high cards by leading a suit they're known to be strong/long in") describes a **lead-side** Tanfeer (a specific lead choice). This video defines Tanfeer as a **discard-side signal** (which suit you throw when an opponent already wins). Both can be true — Tanfeer as a name covers two distinct micro-conventions; the glossary should be expanded to cover both.

---

## 4. Non-rule observations

**Tahreeb (تهريب)** — A discard signal made when **partner is the certain (or default-assumed) winner of the current trick**. You discard a card whose suit you do **not** want returned. Every Tahreeb means "I have nothing of value here" — except for the special "medium" case where Tahreeb on an Ace-only suit is an invitation. Partner's expected response on the lead-back is to play the **opposite suit/color** (the one you withheld), because that's the suit you were protecting.

**Tanfeer (تنفير)** — The **inverse-meaning** discard signal made when **opponent is the certain winner of the current trick**. The suit you discard IS the suit you want — you're signaling strength there, not weakness. Inverse rule because there's no point in negative signaling against an opponent who already won; you instead use the discard channel to point partner at your real strength.

**Choice criterion** — Look at the trick currently in progress: who, with high confidence, will win it?
- Partner ≈100% winning → Tahreeb (negative-signal semantics).
- Opponent ≈100% winning → Tanfeer (positive-signal semantics).
- Uncertain (50/50, 45/45/10, or any non-near-certain split) → **default to Tahreeb**. The speaker's explicit rule: "Tahreeb is stronger than Tanfeer and applies more often."

The video's whole point is that the two conventions are **observationally identical at the moment of discard** — same physical action, opposite intended meaning — and the disambiguator is the assumed trick winner. The asymmetric tiebreaker (when uncertain, assume Tahreeb) is the load-bearing rule.

---

## 5. Quality notes

- Auto-caption is rough: spells Tanfeer as تنفيذ throughout, fragments words ("ابشر" is likely "أعشر" / a card-name attempt, "السبيد/السبيت/السبيتي" all refer to the same suit, "الشريحه" is likely "الشريك" or a sample slide). Meaning is recoverable from context.
- Speaker references two companion videos (his own): one on Tahreeb-vs-Tanfeer basics, one on "predicting the trick" (توقع الحله). Linking these in `decision-trees.md` Section 8/9 once those videos are processed would close the loop on the "uncertainty" rule.
- The example walked through (opponent led J of trump; you are void and will ruff; partner played 9 of trump on the same trick) is a clean Tahreeb-default case but the speaker hand-waves the exact card values; treat the worked example as illustrative, not as a hard rule with specific cards.
- Confidence rating: this is a single-source video, but the speaker is explicit and the rule structure is internally consistent — graded as Common rather than Sometimes for the core Tahreeb-default rule and the inversion principle.
