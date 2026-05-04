# Extracted from 04_faranka_in_hokm
**Video:** الفرنكة في الحكم | بلوت
**URL:** https://www.youtube.com/watch?v=h1eEwSezzic

## 1. Decision rules

### Section 10 — Faranka (فرنكة) in Hokm

| WHEN | RULE | WHY | MAPS-TO | CONFIDENCE | NOTES |
|---|---|---|---|---|---|
| Contract = Hokm; you are not in one of the explicit exception cases below | **Default: do NOT Faranka in Hokm.** Play your natural high trump rather than withholding it. | Speaker's blanket rule: "لا تتفرنك في الحكم" — overwhelmingly safer in trump contracts because trump is short and the lurking high trump is more likely to fall to an opponent than to partner. | `pickFollow` (Bot.lua:1457) — default branch when contract == HOKM | Definite | Repeated multiple times in transcript as the framing rule. |
| Hokm contract; partner is bidder; partner led trump and you are 2nd to play; trick already shows the trump-Q (شايب) and trump-J (ولد) played, you hold trump-T (عشره) AND trump-9 (تسعه) | **Forced: play the 9 (must over-trump-rank), not the T.** This is mandatory cover, NOT a Faranka. | Saudi must-overcut rule when trump is led — playing the T when the 9 is in hand is illegal/wrong. | `pickFollow` over-trump branch + `R.IsLegalPlay` (Rules.lua) | Definite | Speaker uses this as the baseline before discussing Faranka. |
| Hokm; bidder led trump-Q (شايب); pos-2 partner played trump-J (ولد); 4th-position opponent holds trump-9 + trump-T | **The pos-3 opponent who holds 9+T MAY Faranka by playing the T (withholding the 9).** If the 9 is sitting at pos-4 with partner of the led-side, the Faranka catches it. | Withholding the 9 only pays off when the 9 is held by the player to your immediate left (pos-4). If the 9 sits with partner or with the opponent who has already played, the Faranka collapses. | `pickFollow` pos-3 Faranka branch (not yet wired) | Common | Speaker explicitly enumerates failure modes: 9 with partner = waste; 9 with the OTHER opponent (your right) = they take the trick and you lose face. |
| Hokm; you hold only TWO trumps total (e.g., J + T, or J + any other trump) | **Faranka (withhold the higher) is more permissible because your trump situation is already weak — you risk less by trying.** | When you have only 2 trumps, your defensive posture is already degraded; an aggressive Faranka costs little extra and may rescue a trick. | `pickFollow` two-trump Faranka branch (not yet wired) | Common | Speaker's "exception #1": "احكامك ضعيفه عندك الولد جنبها العشره...ممكن تتفرنك". |
| Hokm; you are 4th to play; pos-3 opponent has Faranka'd by playing trump-T after partner's trump-J was over-trumped on partner's lead; you hold trump-9 only (with no trump-T) | **MUST take the trick with the 9 — do NOT counter-Faranka.** Playing 9 here both kills the AKA threat and protects the 9 itself from being stranded. | Two-birds rationale ("هذا يشيل الايكا ولا يشيل التسعه") — winning here removes the opponent's signaling option AND prevents you from losing your 9 later. | `pickFollow` pos-4 cover-with-9 branch (not yet wired) | Common | Speaker is explicit: "لا طبعا تاكل بالتسعه". |
| Hokm; you hold trump-9 + trump-J; trump-J has been led/played earlier in the round (i.e., the J is already gone from the pool) so your 9 is now top trump | **You may Faranka by withholding the 9** — keep it as your guaranteed top, play a smaller trump (trump-Q "شايب") to break suit / cut. | When the 9 is the highest live trump, holding it back lets you ambush the opponent's high trump or AKA later. | `pickLead`/`pickFollow` Faranka-with-top-trump branch (not yet wired) | Common | Speaker: "اذا كانت تسعه اكبر ورق...تدق بالاصغر". |
| Hokm; trick is the 3rd type ("النوع الثالث") and you are pursuing **Al-Kaboot** (kabt) — i.e., team needs to sweep all 8 tricks | **Faranka is preferred / has positional advantage in this case** because behavior approximates Sun-style silence and you are usually certain of holding the cover. | Kaboot pursuit changes the EV — losing one trick is fatal, so calculated withholding to set up the sweep is justified. | `pickLead` trick-N kaboot pursuit (Bot.lua:953 trick-8 branch) | Sometimes | Speaker: "اذا تبغى تكبت اللعب زياده على الكبوت...لك افضليه في الفرنكه في النوع الثالث فقط". |
| Hokm; bidder is opponent (you are defender); opponent led trump-Q ("شايب") at trick start; you hold trump-J ("ولد") and trump-8 (الثمانيه) | **Do NOT Faranka — play the J normally, take the trick.** Withholding here will likely be punished on the next trick when opponents draw trump. | When the opponent bought the contract, opponent has the long trump suit. Withholding lets opponent's late-trick trump roll over you. Play your duty and take the available trick. | `pickFollow` defender-vs-bidder anti-Faranka branch | Definite | Speaker: "اذا الخصم مشتري حكم...تقل نسبه الفرنكه وما انصحك تتفرلك ابدا". |
| Hokm; YOU are bidder; you hold trump-AKA + trump-Q ("ريكا" + "الشايب"); you have either chased the opponent's trump out OR all remaining trump is with partner | **Faranka becomes acceptable if (a) you are pursuing Al-Kaboot OR (b) trump is exhausted from opponent hands.** | Once opponents are out of trump, withholding poses no risk — you can extract value in any order. | `pickLead` bidder-with-clean-trump branch (not yet wired) | Common | Speaker: "زيد نسبه التفرنك اذا طمعت في كبوت او اذا خلصت الاحكام من ايادي اللاعبين". |
| Hokm; trump still live in opponents' hands; you must choose between Faranka or covering | **Always assume worst case — opponent will cut.** Default to covering. Only Faranka if the worst-case outcome is still acceptable. | "حط دائما اسوء الاحتمالات" — risk-management rule: Faranka has high variance, only justified when the worst case still leaves the round salvageable. | All `pickLead`/`pickFollow` decision sites; principle-level | Definite | Speaker articulates this as the meta-principle for all Faranka decisions in Hokm. |
| Hokm; partner has shown signs of holding extra trump (e.g., partner is the cutter and has trumped a side suit cleanly) | **Faranka risk decreases — you may withhold trump to let partner extract more value.** | If partner has the trump residue, the cover-burden shifts to them; you can defer the high trump for endgame. | `pickFollow` partner-strong-in-trump branch + style ledger reads | Sometimes | Speaker mentions but does not strongly endorse: "ممكن انت خويك ما يكون عنده نفس الشكل فيقوم يدق". |

---

## 2. New terms encountered

| Arabic | Transliteration | Meaning in this transcript |
|---|---|---|
| الفرنكة / تتفرنك / يتفرنك | faranka / tatfarank / yitfarank | The verb form: "to Faranka" — the act of withholding a higher card (especially the trump-9) instead of using it to win/cover, hoping the higher card scores later or ambushes opponent |
| دق / تدق / يدق | daqq / tadiqq | "to knock / to cut" — to trump a side suit. Used when discussing partner cutting or being forced to cut |
| ربع / يربع | rabba3 / yirabba3 | "to quarter" — context unclear; possibly "to lead-low into" or "open with" a suit (e.g., "ربع لك بالسبعه" = led the 7 to you) |
| دفرنك (variant of فرنك) | dafarank | Verbal noun / colloquial of Faranka — same meaning |
| النوع الثالث | an-naw3 ath-thalith | "the third type" — a Faranka category referenced as kaboot-related; no full taxonomy given here |
| الصمت | as-samt | "the silence" — used metaphorically for Sun-style withholding ("تقريبا نفس الصمت") |
| الشايب | ash-shayb | Saudi nickname for the **Queen** of trump (literally "the old man") |
| الولد | al-walad | Saudi nickname for the **Jack** of trump (literally "the boy") |
| البنت | al-bint | Saudi nickname for the **Queen** in non-trump contexts (literally "the girl") — used loosely in this transcript |
| ريكا / الريكا | reeka / ar-reeka | Likely the **Ace** of trump (Saudi colloquial) |
| الحلة / حلتين | al-7illa / 7iltayn | "the trick" / "two tricks" — Saudi for trick-rounds |

---

## 3. Contradictions

None internal to this transcript. Cross-video contradiction with #6 (Faranka in Sun) is expected — the speaker explicitly notes Hokm Faranka and Sun "silence" are *similar but not identical*; the Hokm rule is restrictive while Sun is permissive.

---

## 4. Non-rule observations

**Faranka in Hokm (فرنكة في الحكم)** — definition based on this transcript.

Faranka in Hokm is the deliberate act of **withholding a higher trump (most canonically the trump-9 — second-highest trump in Hokm) when you would normally be forced/expected to cover with it**, instead playing a lower card (typically the trump-J "الولد" or trump-Q "الشايب"). The hope is that the withheld 9 (a) ambushes the opponent's J/AKA later, or (b) breaks an opposing AKA signal, or (c) survives to win a critical late trick. The general framing is *aggressive trump conservation* — the opposite of "play your big trump when forced".

**Trigger conditions** — when do you Faranka in Hokm?
1. **You are pursuing Al-Kaboot** (sweeping all 8 tricks) — variance is acceptable because losing any trick already kills the goal. Speaker calls this "النوع الثالث" and notes it is "almost the same as silence (Sun)".
2. **You hold only 2 trumps total** — your trump posture is already weak, Faranka costs little incremental EV.
3. **The trump-J is already played/dead** and your 9 is now the top live trump — Faranka withholds the new top.
4. **You are bidder AND opponents are exhausted of trump** (or all remaining trump is with your partner) — no one can punish the withhold.
5. **You hold trump-9 + trump-T and the J + Q have both been played in the current trick, AND the only live trump-9 catcher (the J) is at pos-4 to your left** — the Faranka catches the 9.

**Counter-defense** — how does an opponent neutralize a Faranka?
- **Cover with the 9 immediately** when offered the chance: if you are pos-4 holding the 9 (with no trump-T to choose between), play the 9 — it both wins the trick AND removes the Faranka payoff. Speaker's "هذا يشيل الايكا ولا يشيل التسعه" (kills both AKA and 9-loss).
- **Force opponent to cut by leading their long side suit** — if opponent has trump residue, drag it out before they can ambush.
- **As bidder facing defender Faranka attempts**, simply play your natural cover; Faranka against the bidder's long trump suit is structurally weak.
- **Worst-case planning** — assume any held-back high trump is in the worst-case opponent hand. If you can survive that worst case, ignore the Faranka threat; if not, draw trump preemptively.

**Speaker's framing principle** — Hokm is short on trump compared to Sun, so withholding a trump in Hokm is far riskier than withholding a non-trump in Sun. Default rule: do NOT Faranka in Hokm; the listed exceptions are the only justifications.

---

## 5. Quality notes

- Transcript is auto-captioned Saudi Arabic with consistent informal spelling (تتفرنك / تتفرلك / تتفرج are all the same word — likely "تتفرنك" mis-transcribed).
- Speaker is concrete: walks through specific card combinations (Q+J on table, hand has 9+T) which makes WHEN clauses testable.
- The "النوع الثالث / النوع الثاني" taxonomy is referenced but never fully enumerated — likely covered in a longer Faranka series. The transcript only resolves "type 3" as kaboot-pursuit and "type 2" as the standard partner-led-trump scenario; "type 1" is not defined here.
- "ربع / يربع" verb is unclear from context — appears in setup descriptions, not in rule statements, so omitted from the rule rows.
- Saudi card-name slang is consistent: الولد=Jack, الشايب=Queen of trump, ريكا=Ace (likely), التسعه=9, العشره=10. Belote-K is not named here.
- Strong overall: the rule "default = no Faranka in Hokm + listed exceptions" is unambiguous and load-bearing for `pickLead`/`pickFollow`.
