# Source K — PDF Basic Rules

**Sources extracted:**
1. `01_registration_system.txt` — نظام التسجيل في البلوت (Registration / scoring system) — 3 pages
2. `02_playing_system.txt` — نظام اللعب في البلوت (Playing system, foundational rules) — 3 pages
3. `06_third.txt` — الثالث (The Third — third-position privilege) — 1 page

**Author**: Twitter handle visible in PDF 02: `https://twitter.com/wms5250`
**Note on source quality**: pymupdf-extracted Arabic text. Letter ordering is generally
correct but right-to-left punctuation, ligatures and digit grouping are sometimes
mangled (e.g. "٢٥١" appears in pristine form on PDF02 p.1, while PDF01 renders
the same target as "٦٢" / "٦١" fragments — these are mojibake of "26"/"16" not
target-score numbers; I have flagged where reading is uncertain). Numbers ending
"٠٠١" are right-to-left renderings of "100"; "٠٥" = "50"; "٤٤" = "44"; "٢٦" = "26";
"٦١" = "16"; "٢٥١" = "152"; "٦٤" = "16+4? — see K-04 note".

---

## Conventions, score targets, scoring framework

### K-01 — Game target score is 152 **[FOCUS]**
- **Source**: PDF 02 (Playing System), p.1 — "اولاً"
- **Arabic (≤15)**: "اللعب يكون ٢٥١ ... يبدأ من الصفر وينتهي عند النقطة ٢٥١"
- **English**: The game is played to **152** points. It starts at zero and ends when a side reaches 152.
- **Confidence**: High
- **Page**: PDF 02 p.1
- **Phase**: Match-level scoring / SWA legality / R.ScoreRound
- **Thresholds**: target = **152** (not 251; the digit string ٢٥١ is RTL-mangled "152" — confirmed by being the canonical Saudi Baloot target). Single-source for exact value but standard for the variant.

### K-02 — Penalty for breaking the rules ("القيد") is 16 (sun) or 26 (hokm) **[FOCUS]**
- **Source**: PDF 02 p.1 ("سادساً"), PDF 01 p.1 (multiple repetitions)
- **Arabic (≤15)**: "يسجل على الخصم ٢٦ او ٦١ حسب اللعبة"
- **English**: When a player commits a foul/error and the opponent invokes "registration" (نظام التسجيل / القيد), the offending side is charged **26 (in Hokm)** or **16 (in Sun)** depending on the contract. (Digits ٦٢/٦١ in extraction are RTL-flipped 26/16.)
- **Confidence**: High (consistent across both PDFs)
- **Page**: PDF 02 p.1 sixth point; PDF 01 p.1 throughout
- **Phase**: Penalty / foul handling
- **Thresholds**: 26 in Hokm contracts; 16 in Sun contracts

### K-03 — When a foul occurs, the offender's own meld (المشروع) is NOT taken away by opponent
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "مشروعي لي ومشروعك لك مالي حق اخذه منك"
- **English**: "My meld is mine, your meld is yours." Even when one side fouls, the opponent does NOT score the offender's melds. Melds only transfer to the opponent in **one** specific case: when the meld was actually contested in completed play (i.e. the round was played out and the offender lost it cleanly), not when play was halted by a foul.
- **Confidence**: High
- **Page**: PDF 01 p.1
- **Phase**: Scoring on foul
- **Thresholds**: meld transfer condition = "round completed without foul/error"

### K-04 — When the buyer (المشتري) commits the foul: opponent scores the round only
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "اذا كان صاحب المشروع هو المشتري وحدث منه الخطأ ... فانه يخسر اللعبة فقط"
- **English**: If the buyer (contract holder) is the one with a meld and is the one who fouls, the buyer loses the round, the **26/16** is scored against them, and the buyer's meld is forfeited (kept by neither side, just lost). The opponent does not gain the buyer's meld.
- **Confidence**: High
- **Page**: PDF 01 p.1
- **Phase**: Foul handling when offender = buyer

### K-05 — Buyer foul example: Sun 26 contract with meld
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "اللعب صن ٢٦ ومعك مشروع"
- **English**: Concrete example: contract is Sun for 26 (so the contract value being defended is 26 trick points), buyer has a meld. Any tricks won by the offender's side are added to the buyer's running meld total because "the meld is yours and I have no right to take it."
- **Confidence**: Medium (example interpretation; uses 26 as illustrative contract value)
- **Page**: PDF 01 p.1
- **Phase**: Worked example (illustrative only)

### K-06 — Kaboot (capot) example: opponent gets 64 if they capot
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "اذا راحت كبوت لي اخذ ٤٤"
- **English**: If the opponent achieves Kaboot (capot — wins all tricks), they score **44** but do not also take the buyer's meld. Conversely, if the buyer scores Kaboot, buyer takes their own meld plus the round.
- **Confidence**: Medium-High (٤٤ = 44 is the Saudi Kaboot bonus for sun-defender capot in this PDF's convention)
- **Page**: PDF 01 p.1
- **Phase**: Kaboot scoring
- **Thresholds**: Kaboot value cited = **44**

### K-07 — Defender on opponent's 100-meld bid: equality threshold rule
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "صار اللعب ٤٦ يعني انت مشتري على ٤٦ ... اعادلك ... اخسرك"
- **English**: When defender holds a 100-meld and contract is sun-46 (illustrative), getting **23** ties (تعادل) and getting **24+** beats the buyer. (Numbers ٤٦/٢٣/٤٢ appear RTL-flipped — the worked example is internally consistent: bid amount X, half-X+1 = beat threshold.)
- **Confidence**: Medium (example numbers RTL-mangled; principle is clear)
- **Page**: PDF 01 p.1
- **Phase**: Round-result calculation in defender meld scenarios

### K-08 — On foul, melds are FROZEN and not transferred (no contest = no transfer)
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "في حالة القيد اوالخطا يتوقف اللعب هنا يعني مافي منافسة"
- **English**: In the foul/registration case "play stops here, meaning there is no contest" — therefore neither side wins the meld off the other. The meld stays with whoever owned it; only the round-penalty (16/26) transfers.
- **Confidence**: High
- **Page**: PDF 01 p.1
- **Phase**: Foul handling

### K-09 — When defender fouls: buyer takes only the round, not defender's meld **[FOCUS]**
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "اذا الخطأ منك اخذ ٢٦ بس ... ماخذ مشروع هو بالاساس لك"
- **English**: If the defender is the one with a meld and they foul, the buyer scores only the round (16 or 26) and does NOT take the defender's meld, because the meld "is fundamentally yours."
- **Confidence**: High
- **Page**: PDF 01 p.1
- **Phase**: Foul handling when offender = defender

### K-10 — Late-round fouling to deny opponent's Kaboot is illegitimate
- **Source**: PDF 01 p.2; PDF 01 p.3
- **Arabic (≤15)**: "اذا شفتها راحت كبوت لهم اروح اقطع واحرمهم الكبوت"
- **English**: A player **cannot** foul deliberately on the last card to deny the opponents the Kaboot bonus and substitute the lower 16/26 penalty. The PDF mocks this excuse ("ماله علاقة بالموضوع" — has nothing to do with the matter); the meld/foul rules are not a loophole for capot-avoidance.
- **Confidence**: High (entire pp.2–3 of PDF 01 argue this point)
- **Page**: PDF 01 pp.2–3
- **Phase**: Foul intent / cheating prevention

### K-11 — Player can refuse "registration" and just play through — wait for last card
- **Source**: PDF 01 p.1
- **Arabic (≤15)**: "ومن حقي أمشيها وأسكت ماأطلب التسجيل األ في أخر ورقة"
- **English**: An aggrieved player has the right to NOT invoke the registration penalty immediately when an opponent fouls — they may continue play silently and only call it on the final card, in case a Kaboot opportunity emerges first.
- **Confidence**: High
- **Page**: PDF 01 p.1
- **Phase**: Foul handling — timing/strategic deferral

### K-12 — In **all** foul cases the offender is also charged 44 (or "44 against") **[FOCUS]**
- **Source**: PDF 01 p.3
- **Arabic (≤15)**: "طبعاً بكل الحالات تسجل ٤٤ ضده"
- **English**: "Of course, in **all** cases, **44** is recorded against him." This is presented as a uniform additional penalty — the foul incurs the contract-side penalty (16/26) AND a fixed 44 against. (NOTE: this is a single-source, possibly variant-specific bookkeeping convention; verify against other sources before encoding.)
- **Confidence**: Medium (single-source, but stated emphatically); **flag as single-source claim**
- **Page**: PDF 01 p.3
- **Phase**: Penalty bookkeeping
- **Thresholds**: additional fixed penalty = **44**

### K-13 — Meld is independent of "cutting" (القطع) — capot scoring not negotiable via cuts
- **Source**: PDF 01 p.3
- **Arabic (≤15)**: "المشروع ماله علاقة بالقطع"
- **English**: The meld scoring is unrelated to whether a player "cuts" (interrupts/foul-stops). Specifically: if Kaboot, opponent gets 44 only; if opponent merely beats you they can force you to continue and take 36 (٦٣ RTL-flipped); if you foul-stop and registration is called, opponent gets 26 only — but **never** the meld.
- **Confidence**: Medium (numbers ٦٣→36 inferred from RTL convention; principle is consistent with K-08, K-09)
- **Page**: PDF 01 p.3
- **Phase**: Scoring interactions
- **Thresholds**: cited values: 44 (Kaboot), 36 (forced continue + beat), 26 (foul-stop in Hokm)

### K-14 — Same rules apply when Double (الدبل) is in effect
- **Source**: PDF 01 p.3
- **Arabic (≤15)**: "نفس الكلام في حالة الدبل المشروع لصاحبه"
- **English**: All of the above (meld stays with owner during foul) applies identically when a Double (دبل) has been declared. The meld remains with its owner regardless of multiplier state.
- **Confidence**: High
- **Page**: PDF 01 p.3
- **Phase**: Multiplier interaction with foul

---

## Foundational gameplay rules (PDF 02)

### K-15 — Bid order goes around the table starting from dealer's right (فرار = "escape"/free) **[FOCUS]**
- **Source**: PDF 02 p.1 ("ثانياً")
- **Arabic (≤15)**: "اللعب او التوزيع يكون فرار ... المشترى من حق الجميع"
- **English**: Play/dealing is "free" (فرار) — the contract-buying right belongs to **everyone** equally and is not restricted to a particular team or seat. (This affirms open-bid order; both teams may compete for the contract.)
- **Confidence**: High
- **Page**: PDF 02 p.1
- **Phase**: Bidding / Bot.PickBid

### K-16 — Only seats 3 and 4 may declare Ashkal (الشكل) **[FOCUS]**
- **Source**: PDF 02 p.1 ("ثالثاً")
- **Arabic (≤15)**: "يحق للاعب الثالث والرابع الشكل فقط"
- **English**: Only the **third and fourth** players (in bid order) may call Ashkal. Seats 1 and 2 cannot.
- **Confidence**: High
- **Page**: PDF 02 p.1
- **Phase**: Bidding / Bot.PickAshkal — seat eligibility

### K-17 — On Ashkal, the BUYER is the one who CALLED the Ashkal, not their partner **[FOCUS]**
- **Source**: PDF 02 p.1
- **Arabic (≤15)**: "المشتري هو صاحب الشكل وليس زميله"
- **English**: A common mistake: people think the player **on whom** Ashkal is called becomes the buyer. The PDF corrects this: the buyer is the one who **declared** the Ashkal. Therefore seat 2 may still buy Sun before seat 1 if seat 1 hasn't taken Sun yet.
- **Confidence**: High
- **Page**: PDF 02 p.1
- **Phase**: Ashkal mechanics / seat resolution

### K-18 — Ashkal must be declared on the FIRST bid round, not the second
- **Source**: PDF 02 p.1
- **Arabic (≤15)**: "بشرط أن يكون المشترى بالشكل الول وليس الثاني"
- **English**: Buying-via-Ashkal works only if the Ashkal call happens in the **first** bidding round. In the second round, no Ashkal is allowed because there is no third position remaining. Same applies to seats 3/4.
- **Confidence**: High
- **Page**: PDF 02 p.1
- **Phase**: Ashkal timing

### K-19 — "Third" (الثالث) is conditional: only when face-up card is an Ace AND bought as Sun **[FOCUS]**
- **Source**: PDF 02 p.1 ("رابعاً"); PDF 06 (entire page)
- **Arabic (≤15)**: "ان تكون الورقة المكشوفة الكه ويصبح الثالث ... اذا تشترى صن وليس حكم"
- **English**: The "Third" privilege exists only when (a) the face-up upcard is an **Ace (الإكَة)**, and (b) the contract is bought as **Sun**, not Hokm. Under those two conditions, only **player 1 and player 2** are entitled to "the Third."
- **Confidence**: High
- **Page**: PDF 02 p.1; PDF 06 p.1
- **Phase**: Bidding-phase resolution — Third privilege

### K-20 — Hokm uses Bnut (البناط); Sun does NOT use Bnut **[FOCUS]**
- **Source**: PDF 02 p.1 ("خامساً")
- **Arabic (≤15)**: "يلعب الحكم بالبناط ... ويلعب الصن بدون ابناط"
- **English**: Hokm contracts use Bnut (announced melds based on trump) regardless of whether a Double (دبل) was declared. Sun contracts do **not** use Bnut at all.
- **Confidence**: High
- **Page**: PDF 02 p.1
- **Phase**: Contract type → meld eligibility

### K-21 — Sun has only Double; no Triple, Four, or Gahwa in Sun **[FOCUS]**
- **Source**: PDF 02 p.2 ("سابعاً")
- **Arabic (≤15)**: "في الصن لايوجد الثري والفور والقهوة وانما يلعب دبلاً فقط"
- **English**: In Sun contracts, the escalation chain is truncated: only **Double (دبل)** exists. Triple, Four, and Gahwa do **not** apply in Sun.
- **Confidence**: High
- **Page**: PDF 02 p.2
- **Phase**: Escalation chain — Bot.PickTriple / PickFour / PickGahwa restrictions in Sun

### K-22 — In Sun, Double can only be declared after opponent crosses **101** **[FOCUS]**
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "ولايحق للاعب ان يدبل خصمة الا بعد ان يتجاوز المئة اي ١٠١"
- **English**: In Sun, a player may **not** double an opponent until the opponent has surpassed 100, i.e. is at **101 or above** in the running match score. Before that, no doubling is legal.
- **Confidence**: High
- **Page**: PDF 02 p.2
- **Phase**: Double legality in Sun
- **Thresholds**: minimum opponent match-score to permit Sun-Double = **101**

### K-23 — In Hokm, full escalation (Double/Triple/Four/Gahwa) is allowed from the start by either side **[FOCUS]**
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "في الحكم فيكون الدبل أو الثري أو الفور أو القهوة مسموح بهما للفريقين من بداية اللعبة"
- **English**: In Hokm, the full escalation chain (Double → Triple → Four → Gahwa) is permitted for **both teams from the start** of the round. No score precondition applies.
- **Confidence**: High
- **Page**: PDF 02 p.2
- **Phase**: Escalation legality in Hokm

### K-24 — Sira (سرى) ranking: largest is Ace-Sira, smallest is 9-Sira
- **Source**: PDF 02 p.2 ("ثامناً")
- **Arabic (≤15)**: "أكبر سرى هو سرى الكه وأصغرها سرى التسعة"
- **English**: For the Sira meld (run/sequence), the **largest** is one ending at the **Ace**; the **smallest** is one ending at the **9**.
- **Confidence**: High
- **Page**: PDF 02 p.2
- **Phase**: Meld comparison / R.ScoreRound

### K-25 — 50-meld ranking: largest = K-Q-J-A-10 ending in Ace; smallest = ending in 10
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "أكبر خمسين هو خمسين الكة وأصغرها خمسين العشرة"
- **English**: For the 50-meld (4-card sequence): largest = the 50 that ends with **Ace**, smallest = the 50 that ends with **10**.
- **Confidence**: High
- **Page**: PDF 02 p.2
- **Phase**: Meld comparison

### K-26 — 100-meld ranking: largest = four Aces, smallest = four 10s (quarter-ranks)
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "أكبر مئة هي مئة الكة من فئة ٥ الأوراق ... وأصغرها هي مئة الـ ٤ عشرات من فئة الربع اوراق"
- **English**: For the 100-meld (Carré / four-of-a-kind worth 100): largest = four **Aces** from the "5-card category"; smallest = four **10s** from the "quarter (4-card) category." (The "quarter" classification distinguishes 100-melds from "quarter-100" / ربع مئة.)
- **Confidence**: Medium-High (terminology slightly elliptical in extraction)
- **Page**: PDF 02 p.2
- **Phase**: Meld comparison

### K-27 — Belote (البلوت) cannot be doubled — fixed value of 2
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "البلوت لايدبل لانه عدد مفروض على اللعبة وليس اساسي"
- **English**: Belote does **not** get the Double multiplier applied to it. It is a "mandatory imposed value, not foundational." (Aligns with CLAUDE.md note: "Belote is multiplier-immune.")
- **Confidence**: High
- **Page**: PDF 02 p.2 + reaffirmed PDF 02 p.2 ("تاسعاً")
- **Phase**: Multiplier scoring / R.ScoreRound

### K-28 — Quarter-100 (ربع مئة) is the four Aces; "needs no explanation" per source
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "اما الربع مئة فهي الربع اكك"
- **English**: The "Quarter-100" meld is specifically the **four Aces** ("ربع اكك" = "quarter of Aces"). The PDF treats this as self-evident.
- **Confidence**: Medium (terminology compressed; reading "الربع اكك" as "Quarter-of-Aces")
- **Page**: PDF 02 p.2
- **Phase**: Meld classification

### K-29 — Sira disclosure rule: second player must NOT reveal full sira until comparison **[FOCUS]**
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "عند ذكر سرى من الفريقين فلايحق للاعب التالي الإفصاح عن سراه"
- **English**: When one team announces a Sira, the next player on the opposing team announcing **also** has a Sira must **not** disclose the size of theirs (to avoid revealing hand strength). Only at the comparison/showdown step does the first player reveal their sira; the second player only discloses if theirs is larger. **This rule applies to all melds**, not just Sira.
- **Confidence**: High
- **Page**: PDF 02 p.2
- **Phase**: Bidding/announcement information rules

### K-30 — Belote = K-Q of trump in Hokm, fixed +20 ... wait, fixed value 2 (?) — clarification needed **[FOCUS]**
- **Source**: PDF 02 p.2 ("تاسعاً")
- **Arabic (≤15)**: "البلوت هو قيمة ثابتة تعادل ٢ ... بنت وشايب الحكم"
- **English**: PDF defines Belote as **the King and Queen of trump together** (شايب الحكم = King of trump; بنت = Queen). It states the value is "**equal to 2**" — the digit ٢ likely is RTL-mangled "20" (i.e. 20 points) given Saudi convention; alternatively it could indicate "2 cards." **Reading uncertain — flag.**
- **Confidence**: Medium (cards are clear; numeric value 2 vs 20 ambiguous in extraction)
- **Page**: PDF 02 p.2
- **Phase**: Belote scoring / Constants
- **Thresholds**: cards = K + Q of trump; value = 2 or 20 (verify against Rules.lua)

### K-31 — Belote is cancelled when buyer holds the 100-meld (only)
- **Source**: PDF 02 p.2
- **Arabic (≤15)**: "ويلغى اذا كان معه مشروع المئة فقط"
- **English**: Belote is annulled (لا يحتسب) **only** when the holder also has the 100-meld (Carré). Single-source claim and worth verifying.
- **Confidence**: Medium (single-source; flag for cross-check)
- **Page**: PDF 02 p.2
- **Phase**: Belote scoring exception

### K-32 — Ace cannot be Ashkal'd; calling Ashkal on an Ace is "ignorance" **[FOCUS]**
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "الكة ماعليها اشكل ... من يشكل الكة يعتبر غشيم"
- **English**: An Ace **cannot** be the target of Ashkal. Doing so is described as "غشيم" (ignorant/inept). Rationale: there's no benefit — no meld depends on someone else holding a particular Ace (4-Aces meld is held by one player), and a partner can simply lead an Ace.
- **Confidence**: High
- **Page**: PDF 02 p.3
- **Phase**: Ashkal legality

### K-33 — In Sun, declaring Triple is allowed but pointless (Double suffices)
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "في الصن لايحق للاعب ان يعطي الثري ... ماهو ممنوع ولكن ماله داعي"
- **English**: In Sun, a player technically **can** declare Triple (الثري), but it is unnecessary because Double already maximizes the multiplier — "not forbidden but pointless." (Note: this slightly tempers K-21; the absolute "no Triple in Sun" reading should be re-examined — it may be "no escalation **chain** beyond Double" rather than "Triple call literally illegal." **Flag for verification.**)
- **Confidence**: Medium (creates ambiguity with K-21; flag)
- **Page**: PDF 02 p.3
- **Phase**: Escalation in Sun

### K-34 — "Cashew" (الكاشو) is forbidden except for verifying card count
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "ممنوع مايسمى بالكاشو باللعب الا في حالة نقص او زيادة في عدد اوراقك"
- **English**: "Cashew" (likely meaning a re-deal request or shuffle complaint) is forbidden during play **except** when the player's hand has the wrong card count (under or over 8). The buyer specifically may verify each player has 8 cards and reject extras (with partner's agreement) to prevent the opponent from forcing a redeal.
- **Confidence**: Medium-High (Saudi-specific term; clear from context)
- **Page**: PDF 02 p.3
- **Phase**: Pre-play verification / dispute handling

### K-35 — Ace cannot be flipped to Sun if its suit was Hokm'd
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "الكة ماتقلب صن اذا حكمت نهائياً وليس عليها ثالث"
- **English**: If a hand has been called Hokm on the Ace's suit, that Ace cannot be "flipped" to Sun afterward, **and** the "Third" privilege does not apply.
- **Confidence**: High
- **Page**: PDF 02 p.3
- **Phase**: Bidding / Third resolution

### K-36 — No "two strengths" (قوتين) in Belote — exception only in Sun
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "مافي شي اسمه قوتين بالبلوت ... وذلك بالصن فقط"
- **English**: There is no "double-priority" mechanism in Belote where a player can preempt their partner — **except** in Sun contracts. In Hokm, normal precedence applies.
- **Confidence**: Medium (terse statement, exact mechanic unclear; **flag**)
- **Page**: PDF 02 p.3
- **Phase**: Bidding precedence

### K-37 — Ashkal allowed by player 1 and 2 (in addition to 3 and 4?) — possible contradiction with K-16 **[FOCUS]**
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "يحق للاعب ان يشكل بالول والثاني"
- **English**: PDF 02 p.3 states: "A player has the right to Ashkal in [round/positions] **first and second**." This appears to **contradict** K-16 ("only third and fourth may Ashkal"). Most plausible reconciliation: K-16 refers to **seat order**, while this line refers to **bid round** ("first or second round"), meaning Ashkal is legal in either bidding round (subject to K-18). **Flag for cross-check with other sources.**
- **Confidence**: Low-Medium (apparent internal contradiction; pick interpretation carefully)
- **Page**: PDF 02 p.3
- **Phase**: Ashkal legality

### K-38 — Misdealt 9-card hand is a dealer error, not a rule violation
- **Source**: PDF 02 p.3
- **Arabic (≤15)**: "تم توزيع ٩ اوراق لاحد اللاعبين فهنا الخطأ من الموزع وليس من النظام"
- **English**: If a player is dealt 9 cards (instead of 8), it is the dealer's error, not a foul covered by the foul-system rules; resolved by mutual agreement between teams ("نظام آخر يكون مرضي للطرفين").
- **Confidence**: High
- **Page**: PDF 02 p.3
- **Phase**: Pre-play error handling

---

## "The Third" (PDF 06) — dedicated rules

### K-39 — Player 1 = the player to the dealer's right
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "الالعب الول هو اللي على يمين الموزع"
- **English**: Definition: **Player 1** is the player to the **right** of the dealer. (Establishes seat numbering for the rest of the rules — important: seat 1 is dealer's right, not dealer themselves.)
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Seat enumeration / Constants

### K-40 — Third privilege is held only by Player 1 and Player 2 **[FOCUS]**
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "شرط الثالث يكون للاعب الول والالعب الثاني فقط"
- **English**: Restated explicitly: **only** seats 1 and 2 may invoke "the Third." (Reinforces K-19.)
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Third privilege

### K-41 — Third exists primarily to address 4-Aces meld (ربع المئة) **[FOCUS]**
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "وضعوه عشان يحل مشكلة ... باختصار وضعوه عشان الربع ميه"
- **English**: The "Third" rule exists specifically to resolve the **Quarter-100** (4-Aces meld) edge case. It exists to give earlier seats a chance to grab the contract from later seats when the upcard is an Ace (so the player holding 3 of the 4 Aces — and thus near-completing Quarter-100 — can preempt).
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Third design rationale

### K-42 — Mechanics of Third in round 1: Player 1 may take Sun ahead of others **[FOCUS]**
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "اذا قال بس بالجولة الولى ... وأشتراها الالعب الثاني أو الرابع صن ... فيحق لالعب الول ان يأخذها قبلهما"
- **English**: If Player 1 said "pass" in round 1, and then Player 2 or Player 4 buys it as **Sun**, Player 1 may "take it before them" (pre-empt the contract) thanks to the Third privilege — to protect against losing a Quarter-100 opportunity. Only works if it's bought **Sun**, not Hokm.
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Third execution

### K-43 — If Player 2/4 buys it as Hokm, Third does NOT apply
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "اما اذا أشتراها الالعب الثاني او الرابع حكم فليس له ثالث"
- **English**: When the buy is Hokm (not Sun), no Third privilege applies. The reason: an Ace can't be "flipped" to Sun once Hokm'd (cf. K-35), so there's no legal path to Sun-on-Ace.
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Third — exclusion case

### K-44 — Player 2 has Third on Player 3 — same Sun-only condition
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "الالعب الثاني له ثالث ... عن الالعب الثالث ... اذا أخذها صن فقط فيقول قبلك"
- **English**: Player 2 has Third on Player 3: if Player 3 buys Sun, Player 2 may say "before you" (قبلك) and take it. Sun-only.
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Third execution — seat 2 case

### K-45 — Without an Ace upcard, no Third — only two bid rounds **[FOCUS]**
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "اذا كانت الورقة المكشوفة ماهي اكة ... مافي ثالث ... واللعب يكون جولتين فقط"
- **English**: When the upcard is anything other than an Ace (e.g. Jack, King), there is **no Third**, and bidding is only **two rounds**. After round 2, no preemption is possible.
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Bidding rounds — Third absence case

### K-46 — Player 1's "Hokm" call in round 2 may be flipped to Sun if no one else takes Sun
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "يحق له يقلب الحكم لصن اذا ماأخذها الالعب الثاني صن"
- **English**: If Player 1 calls Hokm in round 2 and **no one else** takes it as Sun, Player 1 has the right to "flip" their own Hokm into Sun. But once any other player declares Sun, this opportunity is gone.
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Bidding round 2 conversion

### K-47 — Round-2 Hokm gamble: holding 3 Jacks with Jack upcard is a trap
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "مثال معاك ٣ اولاد والورقة المكشوفة الولد الرابع وتبغى تحكم ثاني"
- **English**: Tactical warning (illustrative, not a hard rule): if you hold 3 Jacks (الأولاد) and the upcard is the 4th Jack, do **not** Hokm in round 2 — any opponent calling Sun afterwards will take it and you cannot reclaim it.
- **Confidence**: High (tactical advice, but explicit in source)
- **Page**: PDF 06 p.1
- **Phase**: Round-2 bidding heuristic (informational)

### K-48 — No Third on partner ("ما لك ثالث على خويك") **[FOCUS]**
- **Source**: PDF 06 p.1
- **Arabic (≤15)**: "ما لك ثالث على خويك"
- **English**: A player has **no** Third privilege over their **own partner**. Third only applies against opponents. (E.g. seat 1 can't preempt seat 3, who is the partner.)
- **Confidence**: High
- **Page**: PDF 06 p.1
- **Phase**: Third — partnership exclusion

---

## Cross-source observations / conflicts to flag

### Numbers possibly mojibake from RTL extraction
| Appears as | Likely actual value | Where |
|---|---|---|
| ٢٥١ | 152 (target score) | PDF 02 p.1 |
| ٦٢ | 26 (Hokm penalty) | PDF 01, PDF 02 |
| ٦١ | 16 (Sun penalty) | PDF 01, PDF 02 |
| ٤٤ | 44 (Kaboot value, also fixed penalty K-12) | PDF 01 |
| ٠٠١ | 100 (meld) | PDF 01 |
| ٠٥ | 50 (meld) | PDF 01 |
| ٦٤, ٤٦, ٢٣, ٤٢ | 16-? / 23 / 24 (in worked examples) | PDF 01 |
| ١٠١ | 101 (Sun-double threshold) | PDF 02 p.2 |
| ٢ | 2 or 20 (Belote value) | PDF 02 p.2 — **flag** |
| ٦٣ | 36? (forced-continue penalty) | PDF 01 p.3 |

### Potential PDF↔PDF or PDF↔YouTube conflicts
1. **K-21 vs K-33**: PDF 02 p.2 says Sun has no Triple/Four/Gahwa, but PDF 02 p.3 says Triple in Sun is "not forbidden, just pointless." Need to clarify whether the addon should treat Sun-Triple as illegal vs legal-but-disabled in bot strategy.
2. **K-16 vs K-37**: K-16 says only seats 3 & 4 may Ashkal; K-37 says "first and second" — the second likely means bid-round, not seat. This needs verification against other sources (Source A/B/etc.).
3. **K-12 (fixed 44 in all foul cases)** is a single-source bookkeeping claim — verify before trusting.
4. **K-31 (Belote cancelled when 100-meld present)** is single-source — verify.
5. **K-30 (Belote value = 2 vs 20)** — extraction ambiguity; the canonical Saudi value is +20 per CLAUDE.md but PDF shows ٢. Likely RTL-extraction loss of a digit.

### Treat-as-authoritative items vs YouTube-sourced rules
PDFs assert several items the user flagged as PDF-authoritative-over-video:
- **Target = 152** (K-01) — verify against any video-sourced "251" claim.
- **Foul penalty 16 in Sun / 26 in Hokm** (K-02) is consistently stated.
- **Ashkal seat eligibility (3 & 4 only)** (K-16) — verify against other sources.
- **Meld stays with owner during foul** (K-03, K-08, K-09, K-14) — strongly stated; should override any video that claims otherwise.
- **Sun escalation = Double only, with 101 threshold** (K-21, K-22) — important constraint for Bot.PickDouble in Sun.
- **Third = Player 1/2 only, Sun upcard-Ace only** (K-19, K-40, K-42, K-43, K-45, K-48) — clear PDF authority.

### Single-source claims (per instructions, flagging)
- K-12 (44 against the fouler in all cases)
- K-13 (specific 36 / forced-continue penalty)
- K-31 (Belote cancelled by 100-meld)
- K-36 (no "two strengths" in Belote, exception in Sun)
- K-46 (round-2 Hokm-to-Sun flip)

---

**Total rules extracted: 48** (K-01 through K-48), with 21 marked **[FOCUS]** for SWA / scoring / bot-decision relevance.
