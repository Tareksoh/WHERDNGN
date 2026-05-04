# 38 — Melds Intro (Beginner)

**Source:** https://www.youtube.com/watch?v=9hJEA_McqOA
**Title:** شرح مشاريع البلوت للمبتدئين | 2 | تمهيد (Melds intro)
**Slug:** 38_melds_intro
**Topic:** Beginner-level introduction to melds (مشاريع) — the two
families (صور / face-card carrés, and سره / sequences), their
scoring, and the Sun-vs-Hokm difference for four Aces.

This is the companion intro to video #32 (melds detailed). Most
content is corroborative; flagged any deltas vs `saudi-rules.md`
below.

---

## 1. Decision rules

### R1 — Two meld families
- **WHEN:** Identifying melds in your hand at trick-1 declaration.
- **RULE:** Saudi melds split into two families: **مشاريع صور**
  (face-card carrés — four-of-a-kind on A, T, K/شايب, Q/بنت,
  J/ولد) and **مشاريع سره** (sequences — 3, 4, or 5+ consecutive
  cards same suit).
- **MAPS-TO:** Existing meld categorization in `Bot.PickMelds`.
  No code change.

### R2 — Four Aces (الأربع اكك / 400)
- **WHEN:** Player holds four Aces, contract is **Sun**.
- **RULE:** Score is **400** ("الأربع مئة" — Four Hundred).
  Speaker calls this *"اقوى شيء في اللعبه"* — the strongest meld
  in the game.
- **MAPS-TO:** `K.MELD_CARRE_A_SUN`.
- **DISCREPANCY FLAG:** `saudi-rules.md` line 55 and `glossary.md`
  line 119 list the value as **200**. Speaker explicitly says
  **400** twice in the transcript ("اربع يكت معناته 400",
  "ميه يعني... تقول 400"). Video #32 (melds detailed) corroborated
  the codebase's existing values per task hint, so the 200 figure
  is presumed correct for *raw* and 400 may be the *post-multiplier*
  display value (Sun ×2 → 200 raw × 2 = 400 effective). **Worth
  confirming** — if speaker means raw 400, code constant is wrong.

### R3 — Four Aces in Hokm (downgrade to 100)
- **WHEN:** Player holds four Aces, contract is **Hokm**.
- **RULE:** Score is **100**, not 400. *"اربع عكك في الحكم ما
  تقولوا 400 تقول 100 تعامل معامله الميه"* — "in Hokm don't say
  400, say 100; treats it as a regular hundred."
- **MAPS-TO:** `K.MELD_CARRE_OTHER` (100) for Aces in Hokm.
  Confirms the contract-conditional branch in scoring.

### R4 — Four Tens, Kings, Queens, Jacks
- **WHEN:** Player holds four T / K / Q / J in any contract.
- **RULE:** All score **100** uniformly in both Sun and Hokm
  (*"تعتبر مئه سواء في الصن او في الحكم"*).
- **MAPS-TO:** `K.MELD_CARRE_OTHER` = 100. No change.

### R5 — Four 9s, 8s, 7s are NOT melds
- **WHEN:** Player holds four 9s, four 8s, or four 7s.
- **RULE:** **Not a meld.** Explicitly: *"اربع تسعات... ما يعتبر
  مشروع. اربع ثمانيات اربع سبعات برضو ما يعتبر."*
- **MAPS-TO:** `K.CARRE_RANKS` excluding "9", "8", "7". Confirms
  existing exclusion list.

### R6 — Three-of-a-kind is NEVER a meld
- **WHEN:** Player holds three Js, three Ts, etc.
- **RULE:** Three-of-a-kind in any rank is **not a meld**. *"ثلاثه
  عيال... ثلاثه عشرات... ما يعتبر مشروع. لازم تكون اربع اوراق."*
  Carrés require exactly four cards.
- **MAPS-TO:** `Bot.PickMelds` carré detector requires count ≥ 4.

### R7 — Sequence rank order in Sun
- **WHEN:** Computing sequences (سره) in a Sun contract.
- **RULE:** Order matches **plain-suit rank** (A high, then T, K,
  Q, J, 9, 8, 7). The 10 sits **immediately after the Ace** in Sun.
- **MAPS-TO:** `K.RANK_PLAIN`. No change.

### R8 — Sequence rank order in Hokm
- **WHEN:** Computing sequences in a Hokm contract.
- **RULE:** Same as Sun **except** when the suit IS the trump.
  Speaker's stated framing: in non-trump suits the order is the
  natural high-to-low; in trump the J (ولد) jumps to top, with
  the 10 sitting **after the J** ("بعد الولد") rather than after
  the Ace.
- **MAPS-TO:** `K.RANK_TRUMP_HOKM` for the trump suit; `K.RANK_PLAIN`
  for off-trump. No change.
- **NOTE:** Speaker's wording is slightly garbled here ("الترتيب
  تقريبا هو نفس ترتيب الصن لكن الفرق العشره كانت بعد الاكا في الصن
  وهنا في تكون بعد الولد"). Interpretation is that the speaker is
  describing the sequence-order rule for the **trump suit** in
  Hokm. Consistent with the existing rank table.

### R9 — Sequence-100 (مئه) requires 5+ cards
- **WHEN:** Detecting a 100-point sequence.
- **RULE:** **Five or more** consecutive cards of the same suit.
  Examples given: A-T-K-Q-J (the natural top-five); K-Q-J-T-9
  (5-from-the-top excluding A). *"الميه لا تكون خمسه اوراق
  فاكثر."*
- **MAPS-TO:** `K.MELD_SEQ5` = 100. No change.

### R10 — Sequence-50 (خمسين) requires exactly 4 cards
- **WHEN:** Detecting a 50-point sequence.
- **RULE:** **Exactly four** consecutive cards same suit. Examples:
  Q-J-?-? (paraphrased), K-Q-J-T. *"الخمسين تكون اربعه وراك فقط."*
- **MAPS-TO:** `K.MELD_SEQ4` = 50. No change.
- **NOTE:** Strictly, "exactly 4" is functionally the slot
  between 3 and 5+. A 5-sequence is automatically 100 (not double-
  counted as a 50 + an extra card).

### R11 — Sequence-20 (سيره) requires 3 cards
- **WHEN:** Detecting a 20-point sequence ("سيره").
- **RULE:** **Three** consecutive cards same suit. Example: T-9-8.
- **MAPS-TO:** `K.MELD_SEQ3` = 20. No change.

### R12 — "Sykl" / Cycle (سيكل) — NEW TERM
- **WHEN:** Player holds 9-8-7 of a suit specifically.
- **RULE:** Speaker calls this *"سيكل"* (sykl, "cycle") rather
  than سيره. *"تسعه ثمانيه سبعه هذا يسمونه سيكل."*
- **MAPS-TO:** No code change. This is a colloquial label for the
  **bottom-three sequence** (9-8-7). Whether it scores as a
  regular `K.MELD_SEQ3` (20) or has different behavior is **not
  stated** in this video — speaker introduces the name then moves
  on. **Flag for follow-up** in a later video.

### R13 — Sequences identical between Sun and Hokm except Belote
- **WHEN:** Comparing meld scoring across contracts for sequences.
- **RULE:** Sequence values (20/50/100) are the **same** in Sun
  and Hokm. *"صانع الحكم كلها زي بعض"* (with the implicit "اللهم"
  exception:). The **only** Hokm-only addition is the **Belote**.
- **MAPS-TO:** `K.MELD_SEQ3/4/5`, `K.MELD_BELOTE`. No change.

### R14 — Belote (بلوت) = K + Q of trump
- **WHEN:** Player holds **شايب** (King) + **بنت** (Queen) in the
  same suit, AND that suit is **the trump** (matches the Hokm
  contract's trump or the bidder's declared suit).
- **RULE:** Score = **20** ("النقطتين"). Hokm-only — never scored
  in Sun. *"البلوت النقطتين في الحكم."*
- **MAPS-TO:** `K.MELD_BELOTE` = 20. No change.

### R15 — Belote requires same-suit-as-contract-trump
- **WHEN:** Validating a Belote claim.
- **RULE:** The K+Q pair must be in **the trump suit** of the
  current Hokm contract. Crucially, the speaker frames this as
  "either you bought spades-Hokm or your opponent bought
  spades-Hokm" — *the side holding K+Q-of-trump scores Belote
  regardless of which side won the bid*. *"انت مشتري سبيد حكم او
  اللي ضدك مشتري سبيد حكم وجاك في نفس الشكل."*
- **MAPS-TO:** `K.MELD_BELOTE`, `holdsBeloteThusFar`. Confirms
  the existing rule.

### R16 — Meld utility 1: deny opponent's contract
- **WHEN:** Opponent has won the bid; you hold a meld (e.g. 50
  or 100).
- **RULE:** Your meld can flip a winning bid into a loss for them.
  *"ممكن تخسره عليه تاخذ النقاق كلها خلاص لك."* Melds count toward
  the **defending** team and can deny majority.
- **MAPS-TO:** Existing `R.ScoreRound` meld-aggregation logic. No
  change. Confirms strategic rationale.

### R17 — Meld utility 2: rescue a marginal own-bid
- **WHEN:** You won the bid on a borderline hand.
- **RULE:** Your own melds can lift a losing trick-count into a
  passing total. *"ممكن تنقذك من خساره... بدون مشاريع الجيم خسران
  عليك لكن مع المشروع ما يخليك تخسر."*
- **MAPS-TO:** Bid-evaluation heuristic in `Bot.PickBid` — existing
  code already factors meld value into bid strength. No change.

---

## 2. Hand-shape priors

(Speaker uses melds as illustrative shapes only — no positional
priors / hand-strength categories introduced in this video.)

| Shape | Implication |
|---|---|
| Holds A-A-A-A | In Sun: max-strength meld (400 / 200-raw). In Hokm: regular 100. |
| Holds T-T-T-T or K-K-K-K or Q-Q-Q-Q or J-J-J-J | 100 in either contract. |
| Holds 9-9-9-9 / 8-8-8-8 / 7-7-7-7 | **No meld.** Treat as ordinary cards for shape evaluation. |
| Holds 5+ same-suit consecutive | 100 sequence. Strong meld-anchor for own bid. |
| Holds K+Q of (eventual) trump suit | Belote +20 in Hokm. Multiplier-immune (per saudi-rules.md). |
| Holds 9-8-7 same suit | "سيكل" (cycle) — likely scores 20 as a SEQ3, but speaker doesn't confirm scoring. |

---

## 3. New / confirmed terminology

| Term | Meaning | Status |
|---|---|---|
| مشاريع (mashareeʕ) | "Projects" — generic word for **melds**. | Confirmed (already implicit in `Bot.PickMelds`). Not in glossary. |
| مشاريع صور (mashareeʕ suwar) | "Picture-card melds" — i.e. carrés (4-of-a-kind). | Confirmed. Not in glossary. |
| مشاريع سره (mashareeʕ sirreh) | "Sequence melds" — runs of consecutive same-suit cards. | Confirmed. Not in glossary. |
| الأربع مئة (al-arbaʕ mi'ah) | "The Four Hundred" — four Aces in Sun. | Already in glossary line 119. Confirmed naming. |
| ميه (miyyah) | "The Hundred" — colloquial label for any 100-point meld (4× T/K/Q/J/A-in-Hokm, OR 5+ sequence). | New shorthand. Not in glossary. Worth adding. |
| خمسين (khamseen) | "The Fifty" — 50-point 4-card sequence. | New shorthand. Not in glossary. |
| سيره (seereh) | "Sequence" — generic 3-card sequence (20). | New term. **Should be added to glossary**. |
| سيكل (sykl) | "Cycle" — colloquial for the bottom 9-8-7 same-suit sequence. **English loan-word.** | **NEW TERM.** Not in glossary. Scoring behavior unconfirmed. **Add to "open questions" until follow-up video clarifies.** |
| الجيم (al-jeem) | "The game" / round score. (Loan-word: English "game" → جيم.) | New term — colloquial. Not in glossary. Equivalent to `S.s.cumulative` accumulation. |
| طفايه (tafaayah) | "Ash-tray" / drubbing — colloquial for taking a heavy loss ("ماشيه 200"). | Pure flavor, no rule. |

---

## 4. Discrepancies vs `saudi-rules.md` / `glossary.md`

1. **R2 (Four Aces in Sun = 400 vs codebase 200):** Speaker says
   400 explicitly; `K.MELD_CARRE_A_SUN` in glossary (line 119) and
   `saudi-rules.md` (line 55) both list **200**. The most likely
   reconciliation: codebase stores the **raw** value (200), and
   Sun's ×2 round multiplier produces the **400** the speaker
   names. But melds are typically multiplier-immune in some
   contexts (Belote is — saudi-rules.md line 56), so it isn't
   obvious whether four-Aces is multiplier-applied or not. Video
   #32 (melds detailed) per task hint already corroborated the
   codebase. **No code change yet** — flag for explicit confirm:
   does `R.ScoreRound` apply ×2 to `K.MELD_CARRE_A_SUN`?

2. **R12 (سيكل / cycle term):** New colloquial label not in
   `glossary.md`. The 9-8-7 SEQ3 is presumed to still score as a
   regular 20 (the speaker doesn't say otherwise), but the
   distinct naming hints at possible special handling that this
   intro video doesn't elaborate. **Single-source for the term;
   confirm in a later video before code change.**

3. **R7/R8 (sequence rank order in trump):** Speaker's verbal
   rendering is messy ("العشره كانت بعد الاكا في الصن وهنا في تكون
   بعد الولد"). Best interpretation aligns with existing
   `K.RANK_TRUMP_HOKM`. No discrepancy, but transcript clarity is
   poor; flag if a later video contradicts.

No other discrepancies. Everything else (sequence sizes 3/4/5+,
carré exclusion of 9/8/7, three-of-a-kind not counting, Belote
= K+Q-of-trump = 20 = Hokm-only) matches the existing rules
exactly.

---

## 5. Implementation hints

| Rule | Code site | Action |
|---|---|---|
| R1–R6 | `Bot.PickMelds`, `K.MELD_*` | None — corroborates existing constants. |
| R2 (400 vs 200) | `R.ScoreRound` meld-multiplier handling for `K.MELD_CARRE_A_SUN` | **Verify** whether four-A in Sun is multiplied or not. If multiplied → docs match. If not multiplied → either constant or speaker is off by 2×. |
| R7–R8 | `K.RANK_PLAIN`, `K.RANK_TRUMP_HOKM` | None — existing tables correct. |
| R9–R11 | `K.MELD_SEQ3/4/5` | None. |
| R12 (سيكل) | New term — add row to glossary's "Card-name slang" or "Strategy idioms" table when scoring is confirmed. | Glossary update only after a second corroborating source. |
| R14–R15 | `K.MELD_BELOTE`, `holdsBeloteThusFar` | None. |
| R16–R17 | Bid-strength heuristic and round-scoring | None — meld-aggregation already counts toward defenders. |

**Net effect on codebase:** likely **zero changes** required.
This is a beginner-tier introduction whose content is already
captured. The only items to confirm via a follow-up video are
(a) whether 4-Aces-in-Sun is 200 raw or 400 raw, and (b) whether
"سيكل" (9-8-7) has any special scoring/calling behavior beyond
the standard SEQ3.
