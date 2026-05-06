# A-Src-03 — Re-extraction of Saudi Sun-Faranka 5-factor framework (video #06)

**Source transcript:** `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\lbIAJF5Eo28_06_faranka_in_sun.ar-orig.srt`
**Cross-check target:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_C_faranka.md` (existing extraction)
**Code under review:** `Bot.lua:2484` (`pickFollow`), specifically the Sun-pos-4 Faranka branch at `Bot.lua:2560-2613`.

**Mode:** Read-only re-verification. No code modifications.

---

## TL;DR (verdict on the 6 specific questions)

| # | Question | Verdict |
|---|---|---|
| 1 | Are the 5 factors WEIGHTED or AND-gated? | **WEIGHTED, situational, additive.** No quantified weights. Speaker uses "نسبه" (probability/ratio) language ~10x. **Code's single AND-gate at `Bot.lua:2584-2612` does NOT match the source.** |
| 2 | Is "Sun-Faranka DEFAULT YES" stated explicitly? | **NO — it's a soft default, not stated outright.** Speaker frames Sun as "do unless you have a reason not to" via reverse symmetry with the explicit Hokm "DEFAULT NO" rule. Sun-Faranka starts as a probability that rises/falls with factors. |
| 3 | Anti-rules in #06 (verbatim) | **5 anti-rules confirmed.** Listed below in Q3. |
| 4 | F-14 transcription slip context | **Confirmed in #06** — same Arabic slip ("لازم تتفرنك" where context demands "لازم تاكل / ما تتفرنك") at 6:45-7:09. Speaker's worked example contradicts the literal Arabic. |
| 5 | Bidder-team specificity | **Pro-Faranka triggers gate on bidder-team (mostly).** Anti-Faranka rules apply universally. Factor #4 explicitly gates on **opponents being bidders**. Factor #5 explicitly gates on **your team being bidders**. |
| 6 | Section 5 (Sun pos-4) Faranka — code interpretation | **Code's gate is too narrow.** Code is the canonical "A+T mardoofa, suitCount==2, lastSeat, partnerWinning, bidder-team" subset of Factor #1+#2. Misses Factors #3, #4, #5 entirely. |

---

## Q1 — WEIGHTED or AND-gated?

### Verdict: WEIGHTED (probabilistic, situational). Code's AND-gate is a NARROW SUBSET.

### Evidence — verbatim Arabic ≤15 words

**Q1-E1 — Speaker's framing as "raise the probability":**
- Arabic (≤15 words): `عشان تزيد نسبه الفرنك او تزيد افضليه انك تتفرج`
- English: "to *raise the probability of Faranka* or *raise the favourability* that you Faranka"
- Timestamp: **00:05:08–00:05:13**
- Confidence: **Definite**

**Q1-E2 — Each factor "raises probability" (نسبه), not "satisfies a gate":**
- Arabic (≤15 words): `الشايب قوه جدا مهم اذا كان معي الاكه هنا حتزيد نسبه الفرنكه`
- English: "Shayeb is very important strength — if I have the A here, *the Faranka probability rises*"
- Timestamp: **00:05:24–00:05:29**
- Confidence: **Definite**

**Q1-E3 — Closing summary explicitly invokes ratio-thinking, not boolean:**
- Arabic (≤15 words): `فهي نسبه تناسب وعلى حسب الظروف`
- English: "it's a *proportional ratio* and *according to circumstances*"
- Timestamp: **00:05:01–00:05:08**
- Confidence: **Definite**

**Q1-E4 — Five factors framed as inputs you weigh, not gates you pass:**
- Arabic (≤15 words): `راح اعطيك خمس عوامل رئيسيه اذا صارت لك الافضل انك تتفرنك`
- English: "I'll give you five main factors — if they happen for you, *it's better* that you Faranka"
- Timestamp: **00:05:18–00:05:21**
- Confidence: **Definite**

**Q1-E5 — Factor #5 itself is a conditional INVERSION (not just an AND):**
- Arabic (≤15 words): `راح تقل نسبه الفرنكه الا في حاله واحده`
- English: "the Faranka probability *drops* — except in one case [next-trick-leader + your team is bidder]"
- Timestamp: **00:06:04–00:06:10**
- Confidence: **Definite**

### Cross-reference vs code

`Bot.lua:2584-2612` — Faranka fires only if **ALL** of:
- `contract.type == K.BID_SUN`
- `lastSeat` (pos == 4)
- `partnerWinning`
- `R.TeamOf(seat) == R.TeamOf(contract.bidder)` (bidder-team)
- `hasA and cover and suitCount == 2`

This is a single AND-gated trigger. The source describes a probability-weighted decision where each of 5 factors contributes positively. Source C (`source_C_faranka.md` line 394, "Open ambiguities #5") already flagged: *"Speaker enumerates them in priority order but does NOT give numeric weights. The code likely needs a heuristic; cross-referencer should look for any other source that quantifies."*

**No quantitative weights or thresholds were found in video #06.** The speaker explicitly uses qualitative "نسبه" / "افضل" / "حتزيد" language throughout.

---

## Q2 — Is "Sun-Faranka DEFAULT YES" stated explicitly?

### Verdict: NOT stated as "default yes". It is a SITUATIONAL probability, not a default.

### Evidence

**Q2-E1 — Speaker introduces the topic with the question both ways (when DO and when DON'T):**
- Arabic (≤15 words): `ليش اتفرنك متى اتفرنك متى ما اتفرنك`
- English: "Why Faranka, when do you Faranka, *when do you NOT Faranka*"
- Timestamp: **00:00:12–00:00:14**
- Confidence: **Definite**

**Q2-E2 — Sun-Faranka described as a probability rising from a baseline, not a default-yes:**
- Arabic (≤15 words): `كل ما تكون نسبه التفرنك عندك اكبر`
- English: "the more (factor X holds), *the higher the Faranka probability*"
- Timestamp: **00:03:39–00:03:42**
- Confidence: **Definite**

**Q2-E3 — At the END of #06, speaker introduces the Hokm DEFAULT NO explicitly — by contrast Sun has no equivalent "default yes" sentence:**
- Arabic (≤15 words): `لا تتفرنك في الحكم الا اذا طمعت في كبوت فقط`
- English: "Do NOT Faranka in Hokm except if you covet a Kabout, only"
- Timestamp: **00:13:27–00:13:32**
- Confidence: **Definite**
- **Significance:** The "default NO in Hokm" is stated outright. By contrast, **no parallel "default YES in Sun" sentence exists in the transcript.** The default-yes posture is INFERRED from (a) the absence of a default-no statement, (b) the existence of a 5-factor "raise the probability" framework (which presupposes a non-zero baseline), and (c) explicit anti-rules for narrow Sun cases.

### Verdict refinement

**Source C's framing is correct but slightly overstated.** Sun-Faranka is presented as a situational decision starting from neutral and pushed up by 5 factors / pushed down by anti-rules. The phrase "DEFAULT YES" is a useful coding heuristic but is NOT stated literally by the speaker. **It is a reasonable inference, not a verbatim claim.**

---

## Q3 — All anti-rules (when NOT to Faranka) in #06

### Anti-rule #1 — Don't Faranka if you DON'T hold the K (الشايب)

- Arabic (≤15 words): `ما تفرنك اذا ما عندك الشاي`
- English: "*Don't Faranka if you don't have the K*"
- Timestamp: **00:11:46–00:11:48**
- Confidence: **Definite**

### Anti-rule #2 — Don't Faranka if you hold ≥3 cards in suit

- Arabic (≤15 words): `ما تترنك اذا عندك اكثر من ورقتين`
- English: "*Don't Faranka if you have more than 2 cards*"
- Timestamp: **00:11:58–00:12:04**
- Confidence: **Definite**
- Numerical threshold: ≥3 cards triggers. Speaker explicitly compares 2 vs 3 vs 4 holdings: 2 = 6 outstanding, 3 = 5 outstanding, 4 = 4 outstanding (00:12:18–00:12:34) — "more cards in suit means 10 drops naturally on first trick".

### Anti-rule #3 — When you hold the TWO highest live cards, NEVER Faranka

- Arabic (≤15 words): `اذا عندك اكبر ورقتين موجوده في اللعب لا تترنك ابدا`
- English: "*If you have the two biggest cards live in play, NEVER Faranka*"
- Timestamp: **00:09:49–00:09:54**
- Confidence: **Definite** (speaker uses "ابدا" — never)
- Phase: applies **regardless of seat position** (last player or not).

### Anti-rule #4 — When you're last and the trick is going to opponent → MUST take it (NOT Faranka)

- Arabic (≤15 words): `جاته وهذا ما كان الحله الدور عندك يا تاكل هذا الحله`
- English: "*the trick came to you — you either take this trick* (or they win)"
- Timestamp: **00:11:14–00:11:21**
- Confidence: **Definite**
- Note: This is the **same situation as F-14 in source_C** but the speaker restates it later in the video without the "لازم تتفرنك" transcription slip. The clean later phrasing confirms intent.

### Anti-rule #5 — Don't Faranka in Hokm (general default, transition to video #04)

- Arabic (≤15 words): `لا تتفرنك في الحكم الا اذا طمعت في كبوت فقط`
- English: "*Don't Faranka in Hokm except if you covet a Kabout, only*"
- Timestamp: **00:13:27–00:13:32**
- Confidence: **Definite**

### Bonus anti-rule (paragraph context, not a discrete rule line) — Take with A when partner pulled trick + you have top-2 live

- Arabic (≤15 words): `هذه الحاله لازم تلعب لك يعني ما تتفرلك ابدا`
- English: "*in this case you must play [for] yourself — i.e., NEVER Faranka*"
- Timestamp: **00:09:36–00:09:40**
- Confidence: **Definite**
- Maps to: F-39 in source_C (a worked-example variant of Anti-rule #3).

---

## Q4 — F-14 transcription slip context

### Verdict: CONFIRMED in #06 itself, not just in #04.

The speaker says "اذا كنت اخر لاعب انت لازم تتفرنك" (literally "must Faranka") at 6:45-7:09, immediately followed by a worked example that contradicts the literal Arabic.

### Evidence

**Q4-E1 — The slip itself:**
- Arabic (≤15 words): `اذا كنت اخر لاعب انت لازم تتفرنك اذا هذا الخصم لعب في البدايه`
- English: "*if you are the last player, you must [literally: Faranka] when this opponent led at the start*"
- Timestamp: **00:06:45–00:06:52**
- Confidence: **Definite the words exist; ambiguous the intent**

**Q4-E2 — The worked example that immediately contradicts the literal reading:**
- Arabic (≤15 words): `ولو عكست ما تفرمت الاكا بعدها راح تلعب الشايب وهذا راح ياكل بالعشره`
- English: "*if you reverse [the play] and don't play A, then play K, opp eats with the 10*"
- Timestamp: **00:07:02–00:07:09**
- Confidence: **Definite**
- Significance: This sentence describes the BAD outcome of NOT playing A (i.e. Faranking the A and playing K instead). Therefore the speaker's intended advice is the OPPOSITE of "must Faranka" — it's "must take with A".

**Q4-E3 — Restated cleanly later in the video (without the slip):**
- Arabic (≤15 words): `جاته وهذا ما كان الحله الدور عندك يا تاكل هذا الحله`
- English: "*the trick came to you — you either take this trick*"
- Timestamp: **00:11:14–00:11:21**
- Confidence: **Definite**
- Significance: Same rule (last seat, opp leading), restated as "take it" without the slip. Confirms the intent.

### Hypothesis

The Arabic colloquial verb stem ت-ف-ر-ن-ك literally means "you Faranka" — but the speaker is mid-rapid-explanation and the auto-generated SRT may have substituted تتفرنك for تاكل (take). Audio re-listening would confirm. Either way, the worked example and the later restatement make the intent unambiguous.

**This is exactly the F-14 trap source_C flagged.** Re-extraction confirms it is **a transcription artifact, not a real rule**, and the addon must NOT implement "must Faranka when last seat + opp leading".

---

## Q5 — Bidder-team specificity

### Verdict: Pro-Faranka triggers gate on bidder-team identity (mostly). Anti-rules apply universally.

### Evidence

**Q5-E1 — Factor #4 explicitly gates on OPPONENTS being bidders:**
- Arabic (≤15 words): `طبعا عشان تخسر عليهم لازم يكونوا الخصم هم المشترك`
- English: "obviously, *to make them lose, the opponents must be the bidders/buyers*"
- Timestamp: **00:05:48–00:05:50**
- Confidence: **Definite**

**Q5-E2 — Factor #5 explicitly gates on YOUR team being bidders:**
- Arabic (≤15 words): `وانتوا كنتوا مشترين سواء انت كنت مشتري او خوية كان مشتري صن`
- English: "*and you were the bidders — either you bought or your partner bought Sun*"
- Timestamp: **00:06:10–00:06:15**
- Confidence: **Definite**

**Q5-E3 — Inverse case: when opp is bidder and left-partner leads, Factor #5 fails:**
- Arabic (≤15 words): `لكن لو كان الخصم هم المشترين والخوي اللي على اليسار لعب اي ورقه هنا حيختلف`
- English: "*but if the opponents are the bidders and the left-partner played any card, [the rule] changes*"
- Timestamp: **00:06:23–00:06:28**
- Confidence: **Definite**

**Q5-E4 — Factor #1 (hold the K) is bidder-AGNOSTIC — applies to anyone:**
- Arabic (≤15 words): `اذا كان عندك الشايب يعني شايب مع عكه فالشايب قوه جدا مهم`
- English: "if you have the K, i.e. K with the A, the K is *very important strength*"
- Timestamp: **00:05:21–00:05:26**
- Confidence: **Definite**
- Significance: No bidder-team qualifier appears. This factor applies to either side.

**Q5-E5 — Factors #2 (partner winning) and #3 (heading to Kabout) are also bidder-AGNOSTIC:**
- Both factors are presented without bidder-team qualifiers. Factor #3 is naturally bidder-side because Kabout is a bidder concept, but the speaker does not gate it explicitly.

### Verdict refinement

**The rule "Faranka triggers fire only for bidder team" is contextual, not universal.**
- **Universal across all seats:** Factor #1 (hold K), Factor #2 (partner winning), Factor #3 (heading to Kabout)
- **Bidder-team-only:** Factor #5 (next-trick lead by left-opp)
- **Opponent-bidder-only:** Factor #4 (Faranka costs opps Game-points)
- **Anti-rules:** Apply universally regardless of bidder identity

Source C's claim (line 398) that "*Pro-Faranka triggers should be gated on bidder-team membership; anti-Faranka rules apply to all seats*" is **mostly correct but oversimplified**. The bidder gate is REAL for #4 and #5 only. The code should NOT gate Factor #1/#2/#3 on bidder-team identity.

---

## Q6 — Section 5 (Sun pos-4) Faranka code interpretation

### Verdict: Code captures ONE specific intersection (Factor #1 ∧ Factor #2 ∧ "A+T mardoofa, 2-card suit, last seat, bidder-team"). It misses Factors #3, #4, #5 and the "weighted accumulator" semantics entirely.

### Code reference

`Bot.lua:2584-2612` — single AND-gate:
```
contract.type == K.BID_SUN
AND lastSeat
AND partnerWinning
AND R.TeamOf(seat) == R.TeamOf(contract.bidder)  -- bidder-team
AND hasA AND cover (T or K) AND suitCount == 2
```

This is a **valid, conservative, pessimistic Faranka trigger**. It corresponds to the **canonical worked example** the speaker gives in #06 (around 8:43–9:23) — partner played K of side suit early, you have A+T+T mardoofa, last seat, side-suit lead — duck the cover, take next trick with the A.

### What the code IS doing right

- **lastSeat + partnerWinning** — implements a strong necessary condition for the canonical Faranka shape (Sun-Faranka video at 0:39 and elsewhere: "the Faranka must NOT come back to you").
- **suitCount == 2** — correctly implements **anti-rule #2** (≥3 cards = no Faranka, the 10 drops naturally).
- **bidder-team** — partial implementation of Factor #5 / Factor #4's bidder logic.
- **hasA + cover** — implements the canonical "A+T or A+K mardoofa" shape.

### What the code is MISSING relative to the source

| Source feature | Code state | Gap severity |
|---|---|---|
| Factor #1 alone (hold K, even without 2-card constraint) | NOT triggered | Medium — the code only fires on hand size 2; the source says K-hold strengthens favourability across all sizes |
| Factor #3 (heading to Kabout) — separate trigger or weight | NOT modeled | High — F-11 in source_C, "if heading to Kabout, Faranka regardless" |
| Factor #4 (lose Game-points to opp bidder) — distinct trigger gated on opp-bidder | NOT modeled | High — completely different gate (opp-bidder, not own-bidder) |
| Factor #5 (left-opp leads next trick AND own-bidder, on round transition) | NOT modeled | Medium — round-boundary detection needed |
| Anti-rule #1 (no K = no Faranka) | NOT modeled separately | Low — implicit because cover gate requires T or K, but A+T-without-K case slips through |
| Weighted accumulator vs single AND-gate | Single AND-gate | Architectural — source describes additive "نسبه" weights |
| Pos-2/Pos-3 Faranka (not just lastSeat) | NOT modeled | Low — the canonical shape IS lastSeat per video, but other shapes exist (Section 5 in source_C) |

### Severity assessment

**This is a "partial fidelity" gap, not a correctness bug.** The code's narrow gate produces correct Faranka decisions in the canonical case (and probably in most game states by virtue of being conservative). However it **systematically under-Farankas** in:

- Sun + partner-winning + we-hold-K-only (no A) + we are heading to Kabout
- Sun + partner-winning + opp is bidder + we'd cost them Game-points
- Sun + partner-winning + we are bidder + left-opp will lead next trick (round boundary)
- Sun + bidder-team + we hold K + suitCount 2 but we don't hold A as well (rare but exists)

These represent real Saudi-pro Faranka opportunities the bot would miss.

### Code-side recommendations (read-only suggestion, no edit performed)

The code at `Bot.lua:2560-2613` would benefit from being refactored as a **weighted accumulator** with the 5 factors as positive contributions and the 5 anti-rules as hard guards. Approximate sketch (illustrative only — not authored):

```
score = 0
if hasK: score += W1
if partnerWinning: score += W2
if headingToKabout: score += W3
if oppIsBidder and farankaLosesGameToOpp: score += W4
if leftOppLeadsNextTrick and onBidderTeam and atRoundBoundary: score += W5
-- Hard guards
if not hasK: return takeTrick    -- anti-rule #1
if suitCount >= 3: return takeTrick    -- anti-rule #2
if holdsTopTwoLive: return takeTrick    -- anti-rule #3
if lastSeat and oppWinning: return takeTrick    -- anti-rule #4
if contract.type == HOKM: ...    -- anti-rule #5 (separate path)
if score >= threshold: return faranka else return takeTrick
```

The threshold + weights would need empirical calibration. **Source #06 provides no numeric weights — calibration must come from a different source or simulation.**

---

## Flagged code-source mismatches (per X3)

1. **CRITICAL:** Code at `Bot.lua:2584-2612` is a single AND-gated trigger. Source #06 describes a probability-weighted, additive 5-factor framework with situational anti-rules. **The code is fidelity-incomplete, not incorrect on the canonical case.**

2. **HIGH:** Factor #3 (heading to Kabout) — not implemented anywhere in the Sun-Faranka path.

3. **HIGH:** Factor #4 (Faranka costs opp-bidder Game-points) — not implemented; the code's bidder-team gate is OWN-team-only and would actively REJECT this case.

4. **MEDIUM:** Factor #5 (left-opp next-trick lead + own-team bidder, on round-boundary) — not implemented.

5. **MEDIUM:** Anti-rule #3 (top-2 live cards) — not implemented as an explicit guard. The current code's `cover` discovery may incidentally cover the canonical "A+T live both" case, but the broader "two highest LIVE" detection (which requires played-card memory) is not present.

6. **LOW:** F-14 transcription slip — the code does NOT implement the slip (correctly, since the slip is a transcription artifact). No action needed; this is a "near miss bug" the code avoided.

---

## Summary table — 5 factors and 5 anti-rules per video #06

| ID | Type | Description | Verbatim Arabic (≤15 w) | Timestamp | Confidence | In Bot.lua:2484-2613? |
|---|---|---|---|---|---|---|
| F1 | Factor | Hold the K (الشايب), ideally with A | اذا كان عندك الشايب يعني شايب مع عكه | 5:21-5:26 | Definite | Partial (requires A+cover) |
| F2 | Factor | Partner is winning the trick | اذا خويك كان حل يعني الحله تجيك وخويك اللي ماكلها | 5:29-5:36 | Definite | Yes (partnerWinning) |
| F3 | Factor | Hand is heading to Kabout | اذا اللعب كان رايح كبوت | 5:36-5:39 | Definite | **No** |
| F4 | Factor | Faranka loses Game-points to opp (gated: opps are bidders) | لازم يكونوا الخصم هم المشترك | 5:48-5:50 | Definite | **No** |
| F5 | Factor | Left-opp leads next trick + your team is bidder + round boundary | اذا اللاعب اللي يسارك اللعب اول واحد | 5:59-6:02 | Definite | **No** |
| A1 | Anti | Don't Faranka without K | ما تفرنك اذا ما عندك الشاي | 11:46-11:48 | Definite | Implicit only |
| A2 | Anti | Don't Faranka with ≥3 cards in suit | ما تترنك اذا عندك اكثر من ورقتين | 11:58-12:04 | Definite | Yes (suitCount==2) |
| A3 | Anti | Hold top-2 live cards → never Faranka | اذا عندك اكبر ورقتين موجوده في اللعب لا تترنك ابدا | 9:49-9:54 | Definite | Indirect via cover gate |
| A4 | Anti | Last seat, opp winning → take, never Faranka | جاته وهذا ما كان الحله الدور عندك يا تاكل هذا الحله | 11:14-11:21 | Definite | Yes (partnerWinning gate excludes opp-winning) |
| A5 | Anti | Don't Faranka in Hokm (default) | لا تتفرنك في الحكم الا اذا طمعت في كبوت فقط | 13:27-13:32 | Definite | Yes (`contract.type == K.BID_SUN`) |

---

## Cross-source agreement

This re-extraction **agrees with source_C_faranka.md on all 5 factors and the F-14 slip**. The two extractions are mutually corroborating. The new finding here is the **explicit verdict that the existing Bot.lua code is fidelity-incomplete**: it implements Factor #1 ∧ Factor #2 ∧ Anti-rule #2 only, plus a partial Factor #5 (bidder-team gate), and misses Factors #3 / #4 / #5-full.

**No conflict between source_C and this re-extraction. Source_C's "Open ambiguity #5" (the missing weights) is now confirmed unresolved by source-internal evidence.**
