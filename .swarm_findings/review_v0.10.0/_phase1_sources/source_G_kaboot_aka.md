# Source G — Al-Kaboot (#15), Reverse Al-Kaboot (#16), AKA (#18)

**Cluster:** Al-Kaboot mechanics, scoring, defense; Reverse Al-Kaboot conditions and points; AKA partner-signal rules and decision matrix.

**Source files (read in full):**
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\PPW4uSWTirA_15_kaboot_detailed.ar-orig.srt`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\WgU68NXZEH4_16_reverse_kaboot.ar-orig.srt`
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\V_xTjwSSKyQ_18_when_to_aka.ar-orig.srt`

**Speaker:** "Energy" / "ANRJ" (انيرجي) — same channel-host across all three videos.

---

## High-confidence headline numbers (FOCUS items)

| Concept | Saudi name | Speaker's stated value (raw, pre-multiplier) | Where in the source |
|---|---|---|---|
| **Kaboot in Sun (الصن)** | كبوت في الصن | **44** | File 15, ~02:43 — `راح تاخذ في الصن 44 نقطه` |
| **Sun normal hand without kaboot** | نقاط الصن | **26** (no projects) | File 15, ~02:46 — `نقاط الصن كامله 26 بدون مشاريع` |
| **Kaboot in Hokm (الحكم)** | كبوت في الحكم | **25** | File 15, ~02:51 — `في الحكم اذا جبت كبوت راح تاخذ 25 نقطه` |
| **Hokm normal hand without kaboot** | نقاط الحكم | **16** | File 15, ~02:54 — `نقاط الحكم 16 لكن الكبوت راح تاخذ 25` |
| **Reverse Kaboot (Kaboot Maqloob)** | كبوت المقلوب | **88** (most rule-sets) | Files 15 (~03:37) & 16 (~00:00) — `الكبوت المقلوب نقاطه 88 يعني دبل الكبوت العادي` |
| **Reverse Kaboot — minority opinion** | — | **44** (some treat it = ordinary kaboot) | Files 15 & 16 — `بعض الناس يعتبر الكبوت المقلوب كانه الكبوت العادي يعني ب 44 ما فرق` |
| **Sun double (no kaboot, no projects)** | دبل الصن | **52** | File 15, ~03:09 — `دبل الصن ب 52 نقطه اذا كان اللعب بدون مشاريع` |
| **Hokm double (no kaboot)** | دبل الحكم | **32** | File 15, ~03:06 — `دبل الحكم ب 32 اكثر من الكبوت` |

**[FOCUS] CRITICAL DISCREPANCY with `saudi-rules.md`:** The current addon docs say Kaboot bonus is **"250 raw in Hokm, 220 in Sun (pre-multiplier)"**. The video speaker states **25 in Hokm, 44 in Sun**. The 250/220 numbers in `saudi-rules.md` look like the speaker's 25/44 multiplied by 10 — this is either a units convention difference (Saudi scoring sometimes uses 10× display points) OR a documentation error. The speaker's verbatim arithmetic in File 15 ~03:09 (`44 + سره 4 = 48`, `44 + 100 (=20) = 64`) makes clear his 44 figure is the RAW amount, not displayed/×10. **Verify code constant `K.AL_KABOOT` against this.**

---

## Rule extraction (rule-by-rule)

### --- File 15 — Kaboot detailed (PPW4uSWTirA) ---

### G15-01 Definition of Kaboot
- **Source:** File 15, ~00:11–00:50.
- **Arabic (≤15):** `معنى الكبوت انك راح تاكل جميع الاكلات`
- **English:** Kaboot means winning every trick of the round (all 8 tricks).
- **Confidence:** Very High (definitional).
- **Hand-shape:** Any hand strong enough to take all 8 tricks.
- **Phase:** Whole-round outcome.
- **Thresholds:** 8/8 tricks won by one team.

### G15-02 Kaboot can be one-handed or two-handed
- **Source:** File 15, ~00:40–01:01.
- **Arabic (≤15):** `الكبوت اما يكون من يد او من يدين`
- **English:** Kaboot can come from a single player's hand sweeping all 8, or be split between partners. Result is identical for scoring; speaker comments two-handed kaboot is "more enjoyable."
- **Confidence:** High.
- **Phase:** Trick play (any).
- **Thresholds:** N/A (cosmetic distinction only — scoring identical).

### G15-03 **[FOCUS]** Kaboot raw bonus in Sun = 44
- **Source:** File 15, ~02:40–02:46.
- **Arabic (≤15):** `راح تاخذ في الصن 44 نقطه`
- **English:** Bringing Kaboot in a Sun contract scores 44 points (replaces the normal hand value of 26 when no project bonuses).
- **Confidence:** Very High (explicit, repeated multiple times in the same video including 03:09 example computations).
- **Phase:** Round scoring.
- **Thresholds:** Replaces normal Sun value (26) when 8/8 sweep occurs.

### G15-04 **[FOCUS]** Kaboot raw bonus in Hokm = 25
- **Source:** File 15, ~02:51–02:58.
- **Arabic (≤15):** `في الحكم اذا جبت كبوت راح تاخذ 25 نقطه`
- **English:** Bringing Kaboot in a Hokm contract scores 25 points (vs normal Hokm value of 16).
- **Confidence:** Very High (explicit).
- **Phase:** Round scoring.
- **Thresholds:** Replaces normal Hokm value (16) when 8/8 sweep.

### G15-05 **[FOCUS]** Kaboot ADDITIVE with own-team projects (declarations)
- **Source:** File 15, ~03:01–03:34.
- **Arabic (≤15):** `لو جبت كبوت ومعاك سره راح تاخذ 25 زائد السره`
- **English:** Kaboot bonus is added on top of your own team's project/declaration values. Worked examples:
  - Sun + Kaboot + Sirra (4 pts) = 44 + 4 = **48**
  - Sun + Kaboot + 50-suite (5 pts) = 44 + 5 = **49** (speaker says "54", likely error or different scoring? — see verbatim)
  - Sun + Kaboot + 100-suite (20 pts) = 44 + 20 = **64**
  - Hokm + Kaboot + Sirra ×2 = 25 + 2 = **27**
  - Hokm + Kaboot + Belote (×2) + Sirra (×2) = 25 + 2 + 2 = **29**
  - Hokm + Kaboot + 50-suite (×5? ÷2?) = 25 + 5 = **30**
- **Confidence:** High for additive principle; Medium for the exact Hokm-multiplier interaction with project values (speaker's arithmetic at ~03:30 uses "×2" multipliers on Hokm declarations that don't match standard belote convention — possibly Saudi-specific Hokm-displays-half scoring).
- **Phase:** Round scoring.

### G15-06 **[FOCUS]** Kaboot CAPTURES opponent's projects ONLY when opponent is bidder
- **Source:** File 15, ~03:42–03:55.
- **Arabic (≤15):** `لو الخصم مشتري وجبت عليه كبوت راح تاخذ مشاريعه`
- **English:**
  - If YOU were the bidder and got Kaboot — you do NOT take opponent's projects.
  - If OPPONENT was the bidder and you Kaboot'd them — you DO take their projects (because they bought and got swept = full loss).
- **Confidence:** Very High.
- **Phase:** Round scoring.
- **Thresholds:** Conditional on bidder identity.

### G15-07 **[FOCUS]** When Hand was Doubled (دبل) AND Kaboot occurs — points awarded follow Kaboot, NOT the double
- **Source:** File 15, ~03:55–04:21.
- **Arabic (≤15):** `اذا جا كبوت واللعب دبل راح تاخذ نقاط الكبوت ما راح تاخذ الدبل`
- **English:** Most house rules: if a doubled (Bel) hand goes Kaboot, the scorer takes the Kaboot value (44/25), NOT the doubled value (52/32). Project values stay normal (no doubling either).
- **Confidence:** Very High (explicit speaker rule).
- **Phase:** Round scoring.

### G15-08 **[FOCUS]** Tactical "break-your-own-Kaboot" play to score Double instead
- **Source:** File 15, ~04:21–05:24.
- **Arabic (≤15):** `بعض ناس تدبل الكبوت ... عشان لا ينحسب الكبوت ويروح الدبل`
- **English:** Because in **Sun double** (52) > **Sun Kaboot** (44), and **Hokm double** (32) > **Hokm Kaboot** (25), some players intentionally GIVE UP one trick to break Kaboot status, so they score the Double rather than the Kaboot. (Speaker notes: in deeper escalation rungs e.g. ×3, ×4, this becomes even more profitable.)
- **Confidence:** High (speaker frames as a known tactic, but notes "house-rules vary").
- **Hand-shape:** Doubled bidder hand on track to sweep all 8 with strong cards remaining.
- **Phase:** Late mid-tricks (when bidder realises Kaboot is locked-in but Double points exceed Kaboot).
- **Thresholds:** Bidder team CAN choose to deliberately lose 1 trick if Kaboot < Double (i.e. always in Bel-Sun and Bel-Hokm by speaker's numbers).

### G15-09 Disclaimer — Baloot rules vary by table/sitting
- **Source:** File 15, ~05:13–05:24.
- **Arabic (≤15):** `اغلب قوانين البلوت ما فيها نص رئيسي`
- **English:** "Most Baloot rules don't have a single canonical text — they differ from sitting to sitting. Follow the rules of the table you're playing at."
- **Confidence:** Very High (meta-statement).
- **Phase:** Pre-game / rule-establishment.

### G15-10 Reverse Kaboot (الكبوت المقلوب) only exists in Sun, NOT Hokm
- **Source:** File 15, ~05:30–05:40.
- **Arabic (≤15):** `الكبوت المقلوب في الصن وليس في الحكم`
- **English:** Reverse Kaboot is a Sun-only concept; never applies in a Hokm contract.
- **Confidence:** Very High (explicit).
- **Phase:** N/A (definitional precondition).

### G15-11 **[FOCUS]** Reverse Kaboot raw value = 88 (majority view)
- **Source:** File 15, ~05:36–05:48; File 16, ~00:00.
- **Arabic (≤15):** `الكبوت المقلوب نقاطه 88 يعني دبل الكبوت العادي`
- **English:** Reverse Kaboot = 88 points (literally "double the normal Kaboot of 44"). This matches the existing addon constant `K.AL_KABOOT_REVERSE = 88`.
- **Confidence:** Very High for this rule-set (speaker notes a minority treats it as 44).
- **Phase:** Round scoring.

### G15-12 **[FOCUS]** Reverse Kaboot — agreed conditions
- **Source:** File 15, ~05:50–06:21; mirrored in File 16 ~00:13–00:31.
- **Arabic (≤15):** `لازم تجيب كبوت اما انت وخويك ... والمشتري لازم يكون الخصم`
- **English:** Universally-agreed prerequisites for Reverse Kaboot:
  1. **YOU AND YOUR PARTNER** must sweep all 8 tricks (not the bidder team).
  2. The **BIDDER must be on the OPPOSING team** (you are defenders).
  3. **The lead/play must be on the bidder's hand** at trick 1, OR on the bidder's partner's hand (i.e. opening trick must be led by the bidder team).
- **Confidence:** Very High (explicit, repeated).
- **Phase:** Conditions evaluated trick-1 onward.
- **Thresholds:** All three must hold.

### G15-13 **[FOCUS]** Reverse Kaboot — disputed condition: lead-card must be Ace
- **Source:** File 15, ~06:21–07:17; File 16 ~00:31–01:01.
- **Arabic (≤15):** `اغلب الناس تقول لازم الارض تكون اكا`
- **English:** **Most players** require: the bidder team's first lead card must be an **Ace** (specifically, the opponent leads an Ace, declines to play it OR plays something else, and you/partner sweep from then on). A minority allow ANY card to be the lead. The speaker says he's never seen the lenient version actually played.
- **Confidence:** High (speaker explicit on this being the disputed condition).
- **Hand-shape:** Defenders' combined hands must dominate from trick 2 onward.
- **Phase:** Trick 1.
- **Thresholds:** Strict reading: opening lead = Ace.

### G15-14 **[FOCUS]** Defender QAID strategy when sensing Kaboot — Sandbag the قيد call
- **Source:** File 15, ~07:27–08:11.
- **Arabic (≤15):** `خليني اقيد على اي شيء وانا عارف انه الجيد حقي غلط`
- **English:** When a defender suspects opposition is heading to Kaboot, defender deliberately calls قيد (an "I have it" claim) on something they KNOW is wrong, hoping to force a wrong-قيد penalty (26 in Sun / 16 in Hokm) rather than letting the actual Kaboot score (44 / 25). This is a known sabotage tactic.
- **Confidence:** Very High.
- **Hand-shape:** N/A — defender psychological tactic.
- **Phase:** Mid-trick when defender is sure their team is being swept.
- **Thresholds:** Defender chooses قيد even on positions where their cards don't actually warrant it.

### G15-15 **[FOCUS]** Bidder counter-defense — "Demand Kaboot" instead of accepting قيد
- **Source:** File 15, ~08:13–10:25.
- **Arabic (≤15):** `تقول اللعب رايح كبوت وتشرح كبوتك`
- **English:** When opponent calls قيد on a position you can prove is sweep-able:
  - You may either ACCEPT the قيد (and take 26/16),
  - OR refuse and DECLARE "the round is going Kaboot" — then you must lay out and PROVE the sweep card-by-card.
- **Confidence:** Very High.
- **Phase:** Mid-trick decision.
- **Thresholds:** Must be ABLE to actually demonstrate the sweep with remaining cards.

### G15-16 **[FOCUS]** "Bare-Ace" implicit-Kaboot from partner-tahreeb (تهريب)
- **Source:** File 15, ~09:11–09:48.
- **Arabic (≤15):** `لو خويك هرب لك اكه الهاص من اول كذا وكذا كبوت`
- **English:** If your partner gives up (tahreeb) the Ace of trump (or Ace of a key suit) early in the hand, this is conventionally read as Kaboot-confirmation: partner is signalling "I have nothing useful, sweep it yourself with your remaining bigs." The other side can't realistically sweep around this.
- **Confidence:** High.
- **Hand-shape:** Hand with bare-A or top-A-card sequence after partner's tahreeb.
- **Phase:** Trick 1–3.
- **Thresholds:** Partner unloads top card unsolicited.

### G15-17 **[FOCUS]** Wrong-Kaboot-claim → swa khate' (سوا خاطئ) penalty
- **Source:** File 15, ~10:15–10:27.
- **Arabic (≤15):** `لو اخذتها قيد اصلا عليهم 26 كان احسن لك`
- **English:** If you call/refuse-قيد and demand Kaboot but cannot actually deliver the sweep (your hand is "swa khate'" = wrong-claim), the penalty applies AGAINST you. Speaker recommends taking قيد if uncertain, since 26 against opponent is better than failing your own sweep claim.
- **Confidence:** Very High.
- **Phase:** Decision moment when opponent calls قيد on you.
- **Thresholds:** Must be 100% confident in sweepability before refusing قيد.

### G15-18 **[FOCUS]** Defender "spoil-the-sweep" via deliberate قطع (cut)
- **Source:** File 15, ~10:31–13:30.
- **Arabic (≤15):** `يقطع في اي لون ... عشان تقيد عليه`
- **English:** A defender suspecting Kaboot may deliberately renege/cut (qet') in any suit hoping bidder calls قيد on the wrong move. Worked example given: 5-cards-left endgame where defender cuts on a suit they actually held, hoping bidder responds with قيد instead of pursuing the Kaboot sweep.
- **Confidence:** Very High.
- **Phase:** Endgame tricks 5–7.
- **Thresholds:** Defender willing to take penalty if it derails Kaboot.

### G15-19 **[FOCUS]** Bidder rule when opponent cuts suspiciously — DON'T call قيد until last trick
- **Source:** File 15, ~13:14–13:50.
- **Arabic (≤15):** `حاول قدر مستطاع ما تقيد لين اخر حله`
- **English:** When bidder sees an opponent cut/renege and Kaboot is still in play, bidder should DELAY calling قيد all the way to the last trick, to confirm Kaboot is actually achievable. This guards against opponent's spoil-trap (G15-18).
- **Confidence:** Very High.
- **Phase:** Trick 6–8.
- **Thresholds:** Wait until last possible moment to call قيد.

### G15-20 Bidder priority summary — "go for Kaboot, not for قيد"
- **Source:** File 15, ~14:00–14:10.
- **Arabic (≤15):** `خذ الكبوت احسن لك من القد`
- **English:** When bidder is confident in Kaboot, taking the Kaboot (44/25) is always preferable to calling قيد (26/16). Use قيد only as fallback if Kaboot becomes impossible.
- **Confidence:** Very High.
- **Phase:** Endgame priority hierarchy.

---

### --- File 16 — Reverse Kaboot (WgU68NXZEH4) ---

This file is a 60-second SUMMARY/RECAP that re-states points G15-11, G15-12, G15-13. No NEW rules introduced; serves as confirmation. Notable verbatims:

### G16-01 **[FOCUS]** Confirmation: Reverse Kaboot = 88, ordinary = 44
- **Source:** File 16, ~00:00–00:13.
- **Arabic (≤15):** `كبوت المقلوب نقاطه 88 للكبوت العادي باربعين`
- **English:** Restates: Reverse Kaboot = 88 (vs ordinary Kaboot = 44 in Sun). Same disclaimer about minority "treat as 44".
- **Confidence:** Very High.

### G16-02 **[FOCUS]** Confirmation: Bidder must be opponent + lead must be on bidder team
- **Source:** File 16, ~00:13–00:25.
- **Arabic (≤15):** `المشتري لازم يكون الخصم ... اللعب يكون عند احد الخصمين`
- **English:** For Reverse Kaboot to qualify: (a) bidder is on opposing team, (b) opening lead is on the bidder team. Speaker notes "if THIS player [bidder] bought, the lead MUST be on his hand" — confirming the trick-1-leader requirement is read as bidder team's lead, NOT necessarily bidder personally.
- **Confidence:** High.

### G16-03 **[FOCUS]** "Bidder must be trick-1 leader" — NUANCE
- **Source:** File 16, ~00:18–00:27 (and File 15 ~05:50–06:08).
- **Arabic (≤15):** `يكون اللعب على يده او ... المشتري نفسه يكون اللعب على يده`
- **English:** Speaker's exact phrasing: lead must be either (a) the bidder personally, or (b) the bidder's partner ("احد الخصمين" — "one of the two opponents," i.e. either bidder or partner). **NOT strictly "bidder personally must lead trick 1"** — being on the bidder TEAM suffices.
- **Confidence:** High — speaker's wording is "one of the opponents," but earlier he says "if THIS player [bidder] bought, the lead MUST be on his hand." Slight ambiguity; safest read: bidder team leads trick 1.
- **[FOCUS] DISCREPANCY with `saudi-rules.md`:** Existing addon doc says Reverse Kaboot "Qualifies only when bidder was the trick-1 leader." The video supports a slightly LOOSER reading: trick-1-leader is on bidder TEAM (bidder OR bidder's partner). **Worth verifying which the code actually checks.**

### G16-04 Confirmation: Disputed Ace requirement
- **Source:** File 16, ~00:31–01:01.
- **Arabic (≤15):** `اغلب الناس يقول لازم المشترى ... اكا`
- **English:** Same as G15-13: most players require the lead card be an Ace; minority allows any card. No new info beyond File 15.
- **Confidence:** High.

---

### --- File 18 — When to call AKA (V_xTjwSSKyQ) ---

### G18-01 Definition of AKA / تاكيك (taakeek)
- **Source:** File 18, ~00:07–00:14.
- **Arabic (≤15):** `ترمي ورقه وتقول عليها اكه`
- **English:** Taakeek = playing a card and announcing "AKA" (إكَهْ) on it.
- **Confidence:** Very High.
- **Phase:** Trick lead.

### G18-02 **[FOCUS]** Condition #1 — AKA exists ONLY in Hokm, never in Sun
- **Source:** File 18, ~00:24–00:29.
- **Arabic (≤15):** `في الصن ما في شيء اسمه تاكيك فقط في الحكم`
- **English:** AKA is a Hokm-contract-only signal. Calling AKA in a Sun contract is invalid.
- **Confidence:** Very High (explicit).
- **Phase:** Trick lead.
- **Thresholds:** Contract type = Hokm.
- **NOTE for cross-ref:** This is the answer to one of the watchpoints — **"AKA is Hokm-only, NOT Sun-too."** Implicit-AKA via bare-A lead also follows this rule (since the AKA convention is undefined in Sun).

### G18-03 **[FOCUS]** Condition #2 — AKA only on NON-trump cards
- **Source:** File 18, ~00:29–00:48.
- **Arabic (≤15):** `تقول اكا على الاوراق غير الحكم`
- **English:** You can only AKA on the three NON-trump suits. Calling AKA on a trump card is illegal — counts as a wrong-call (قد).
- **Confidence:** Very High (explicit).
- **Phase:** Trick lead.
- **Thresholds:** Card suit ≠ trump suit.

### G18-04 **[FOCUS]** Condition #3 — AKA only on the LARGEST remaining card (excl. the Ace itself)
- **Source:** File 18, ~00:48–01:33.
- **Arabic (≤15):** `تقول اكه على اكبر ورقه موجوده عندك غير الاكه`
- **English:** AKA must be played on the **largest remaining card** of that suit in play (other than the actual Ace).
  - On the Ace itself: NO AKA needed — the Ace is "AKA by itself" (some players will حرام/قد you for redundantly calling AKA on a played Ace, but this is disputed).
  - On the 10 (next-largest): Only valid if Ace has already been played.
  - On the King: Only valid if Ace AND 10 already played.
  - And so on down to the 7.
- **Confidence:** Very High.
- **Phase:** Trick lead.
- **Thresholds:** Card = current top-of-suit-in-play.

### G18-05 **[FOCUS]** Condition #4 — Lead must be on YOUR hand (you must be opening the trick)
- **Source:** File 18, ~02:03–02:34.
- **Arabic (≤15):** `لازم اللعب يكون على يدك وانت تلعب اول ورقه`
- **English:** You can only call AKA when YOU are the trick leader (first card of the trick). Calling AKA when following someone else's lead = invalid (قد).
- **Confidence:** Very High.
- **Phase:** Trick lead position only.
- **Thresholds:** You hold the lead.

### G18-06 **[FOCUS]** AKA's PRIMARY effect — releases partner from "must trump" obligation
- **Source:** File 18, ~02:36–03:25.
- **Arabic (≤15):** `اذا قلت اك لاي ورقه خويك مش مجبر يدق بالحكم`
- **English:** When you AKA a card, your partner is RELEASED from the normal Hokm obligation to trump-cut (دق بالحكم) when void in lead suit. Without AKA, partner MUST trump-cut if void; with AKA, partner can keep trump for later.
- **Confidence:** Very High (explicit, with worked example).
- **Phase:** Affects partner's pickFollow when void in lead.
- **Thresholds:** AKA-call active for that trick.

### G18-07 **[FOCUS]** AKA's SECONDARY effect — preserves an extra trick
- **Source:** File 18, ~03:25–03:54.
- **Arabic (≤15):** `الفائده الثانيه انه تاخذوا وحله زياده اللي هي حله الحكم`
- **English:** Because partner can keep the trump, you collectively gain an extra trick later (the trump-trick partner would have wasted on this lead). Worked example demonstrates 2 tricks won with AKA vs. only 1 without.
- **Confidence:** Very High.

### G18-08 **[FOCUS]** Ace itself implicitly AKA — partner not forced to trump
- **Source:** File 18, ~04:00–04:20.
- **Arabic (≤15):** `الاكه هي تاكك نفسها بنفسها`
- **English:** When the bare Ace is led, partner is NOT forced to trump-cut — leading the Ace ITSELF acts as an implicit AKA call. (`فالاكه هي تاكك نفسها`)
- **Confidence:** Very High (explicit).
- **Phase:** Bare-A lead in Hokm.
- **Thresholds:** Ace led from leader's hand.
- **NOTE:** Confirms watchpoint — "implicit AKA via bare-A lead" IS in this video #18 (not only #05). And it's HOKM-ONLY (since AKA itself is Hokm-only, G18-02).

### G18-09 **[FOCUS]** AKA decision matrix — 9 cases (3×3 grid)
- **Source:** File 18, ~04:20–07:00.
- **Arabic (≤15):** `حنقسم القسمين قسم لك انت وقسم لخويك`
- **English:** Speaker presents a 3×3 decision matrix:

| | Partner DEFINITELY has trump | Partner MAYBE has trump | Partner DEFINITELY has NO trump |
|---|---|---|---|
| **You SURE this is largest card** | **CALL AKA** (essential) | **CALL AKA** (no downside) | **DO NOT CALL** (pointless, just risk قد) |
| **You SUSPECT this is largest** | **DO NOT CALL** (risk) | **DO NOT CALL** | **DO NOT CALL** |
| **You KNOW this is NOT largest** | **DO NOT CALL** (illegal qd) | **DO NOT CALL** | **DO NOT CALL** |

- **Confidence:** Very High (speaker walks through systematically).
- **Phase:** Trick-lead decision in Hokm.
- **Thresholds:**
  - Call AKA: certain-largest AND (partner has trump OR may have trump).
  - Never call AKA: when uncertain about being largest (risk of wrong-قد), OR when partner certainly has no trump (no benefit).

### G18-10 **[FOCUS]** Risk-tolerance modifier — game state matters
- **Source:** File 18, ~06:24–06:41.
- **Arabic (≤15):** `بدايه الجيم لسه عوافي`
- **English:** Speaker adds a state-sensitive modifier to G18-09: at the BEGINNING of a game (early hand, no double in play, score is comfortable), you may take a riskier AKA call even if uncertain about being-largest. In tense states (close score, doubled hand, opponents far ahead), be conservative.
- **Confidence:** High.
- **Phase:** Pre-trick risk assessment.
- **Thresholds:** Game-state and score balance.

### G18-11 AKA on a played-Ace = "wrong-call" risk
- **Source:** File 18, ~01:06–01:24.
- **Arabic (≤15):** `لو لعبت اكا وقلت اكا معناته معك العشره`
- **English:** Some players take "Ace + AKA called on it" as a play-clarification ("I also have the 10"); others قد you for it as redundant. Best practice: don't call AKA on the Ace itself.
- **Confidence:** High.

### G18-12 AKA on the 10 only valid if Ace already played
- **Source:** File 18, ~01:43–01:51.
- **Arabic (≤15):** `لازم الاكه تكون اتلعبت في الجيم اللي قبل`
- **English:** Calling AKA on the 10 of a side-suit is invalid unless the Ace of that suit has already been played in a prior trick.
- **Confidence:** Very High.

### G18-13 AKA on K/Q/J/etc. valid if all higher cards already out
- **Source:** File 18, ~01:53–02:03.
- **Arabic (≤15):** `ورميته تقدر تقول عليها هيك`
- **English:** Same principle generalizes: AKA on King requires Ace+10 out, AKA on Queen requires Ace+10+K out, etc. Speaker explicitly confirms even AKA on the 7 is valid if all higher cards are gone.
- **Confidence:** Very High.

### G18-14 Concrete worked example — "AKA on 10 of hearts" with vs. without AKA
- **Source:** File 18, ~02:36–03:25.
- **Arabic (≤15):** `اذا ما قلت اكا الخصم راح ياخذ اخيره`
- **English:** Example: trump = spades; you lead 10♥ (Ace already out). Partner has only 7♠ trump. WITHOUT AKA, partner must trump-cut with 7♠ → trick goes to your team but you waste the trump. WITH AKA, partner can sluff a heart, keep 7♠ for later trump trick. Net: 2 tricks vs. 1 trick.
- **Confidence:** Very High (full worked example).
- **Phase:** Trick lead in Hokm with non-trump strong cards.

---

## Cross-cluster watchpoint answers

### Watchpoint A — Kaboot bonus values
- **`saudi-rules.md` claims:** 250 raw in Hokm, 220 in Sun (pre-multiplier).
- **Speaker actually says:** **25 raw in Hokm, 44 raw in Sun**.
- **[FOCUS] Either an order-of-magnitude documentation error OR a units convention (×10 display points). Verify against `K.AL_KABOOT` and `R.ScoreRound`.**

### Watchpoint B — Kaboot pre-conditions
- **Bidder team requirement:** Yes — speaker confirms (G15-06): full Kaboot scoring (with project capture) only when bidder/non-bidder distinction matters. Bonus itself accrues to whoever sweeps.
- **Trick-1 leader requirement:** Speaker says NOTHING about trick-1-leader for ORDINARY Kaboot. Only for REVERSE Kaboot (G15-12, G16-03).

### Watchpoint C — When does bot recognize Kaboot is achievable
- Speaker's recommendation (G15-19): **delay قيد until last trick**. Implies the bot should keep Kaboot as a live target until trick 8, not commit early.
- Earliest recognition: trick 1, if hand has enough top-cards to lock all 8.
- Practical detection: by trick 3–5 if 0/X tricks lost so far AND remaining hand is sweep-strength.
- The speaker emphasises bidder should NOT call قيد early when Kaboot is in reach, EVEN IF opponents try to spoil with cuts.

### Watchpoint D — Reverse Kaboot
- **+88 raw:** **CONFIRMED EXPLICITLY** in both files 15 and 16. Single-source flag in `saudi-rules.md` is now corroborated by File 16 as a second confirmatory pass.
- **Bidder-must-be-trick-1-leader claim:** **PARTIALLY CONFIRMED but with nuance** — speaker says lead must be on the BIDDER TEAM (bidder OR bidder's partner), not strictly the bidder personally. See G16-03.
- **Sun-only:** **CONFIRMED EXPLICITLY** (G15-10): no Reverse Kaboot in Hokm.
- **Disputed Ace-lead requirement:** EXPLICIT (G15-13, G16-04) — most rule-sets require lead = Ace, minority allow any card.

### Watchpoint E — AKA scope
- **Hokm-only:** **CONFIRMED EXPLICITLY** (G18-02). Sun never uses AKA.
- **Implicit-AKA via bare-A lead:** **CONFIRMED IN VIDEO #18** (G18-08). Hokm-only by extension since AKA itself is Hokm-only.

---

## Summary of [FOCUS]-tagged items affecting SWA / scoring / bot decisions

1. **G15-03 / G15-04** — Kaboot raw bonus values (44 Sun / 25 Hokm) — POSSIBLE 10× DISCREPANCY with addon doc.
2. **G15-05** — Kaboot additive with own-team projects — verify scoring code adds project bonuses ON TOP of Kaboot.
3. **G15-06** — Kaboot captures opponent projects ONLY if opponent was bidder — verify R.ScoreRound branches on bidder-team identity.
4. **G15-07** — Kaboot overrides Double — when both happen, use Kaboot value, not Double value.
5. **G15-08** — Bidder may deliberately break own Kaboot to score Double instead — strategic, not a rule violation; bot tier should know this trade-off.
6. **G15-11 / G15-12 / G15-13** — Reverse Kaboot conditions: 88 pts, defenders sweep, bidder is opponent, lead on bidder team, Ace-lead requirement disputed.
7. **G15-14 to G15-19** — Kaboot endgame meta: defender sandbag-قيد tactic, bidder should delay قيد to last trick.
8. **G16-03** — Reverse Kaboot trick-1-leader nuance: bidder TEAM, not necessarily bidder personally.
9. **G18-02** — AKA Hokm-only.
10. **G18-04** — AKA only on largest-remaining card.
11. **G18-05** — AKA only when YOU lead the trick.
12. **G18-06** — AKA releases partner from must-trump obligation.
13. **G18-08** — Bare-Ace lead = implicit AKA (Hokm only).
14. **G18-09** — 3×3 AKA decision matrix — directly maps to `Bot.PickAKA`.
15. **G18-10** — AKA risk-modifier by game-state.

---

## Rule count

37 distinct rules / heuristics extracted (G15-01 through G15-20, G16-01 through G16-04, G18-01 through G18-14), 15 of which are flagged **[FOCUS]** for direct impact on SWA / scoring / bot decisions.
