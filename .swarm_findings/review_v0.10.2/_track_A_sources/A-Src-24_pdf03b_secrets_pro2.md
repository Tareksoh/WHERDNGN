# A-Src-24 — PDF 03b سر الاحتراف في لعبة البلوت ٢ (Secrets of Pro 2) re-extraction

**Source file:** `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\03b_secrets_pro_2.txt`
(pasted from Google Doc — content known clean, 1 page only)

**Purpose:** Verify v0.10.0 X4/L07 (`hokmMinShape` Ace-gate) and v0.10.2 M8
(`pickLead` Sun-trick-1 mardoofa probe) implementations against the
authoritative Pro-2 source. **The hard-rule-vs-strategy question is the
key arbitration for D-RT-11.3/11.4/11.6 cascade fail.**

**No code modified.** Read-only review.

---

## Source structure

The Pro-2 PDF contains **exactly three numbered rules** (lines 10-23 of
the extracted text). They are explicitly numbered ١, ٢, ٣ in the Arabic
source — the author treats these as a closed enumeration, not a list of
strategic tips among many. The text uses imperative mood ("فلابد",
"اجبارية") on rules 1 and 2, conditional mood ("فحاول") on rule 3.

The full source is 17 lines of Arabic prose, no headings other than the
numerals. Page reference for all three rules is `03b:1`.

---

## Q1 — L07 Hokm-needs-Ace rule verbatim

### Verbatim Arabic (≤15 words)

> «اذا اراد ان يحكم اللاعب فلابد من وجود اكه لديه»

(line 10 of `03b_secrets_pro_2.txt`)

### Two stated rationales (lines 11-12, verbatim ≤15 words each)

**Rationale A (defensive):**
> «خوفا من إجبار الخصم على الصن او من الكبوت او من الاربع ميه»
>
> "Fear of [the opponent] forcing-on-Sun, or of Kaboot, or of 4-Hundred."

The "اربع ميه" = 4-Hundred = Carré-of-Aces (4 Aces × 100 each = the
project that generates 100 points per declared four). The L07 author is
saying: if you bid Hokm Aceless, opps holding 3-4 Aces can use the
information to drive Sun, Kaboot, or claim Carré-A — and you have no
Ace to fight back with.

**Rationale B (informational / partner-coordination):**
> «خوفا من ظن زميلك بأن لديك اكه ف بموجبها يشكل او يشتري صن»
>
> "Fear that your partner will assume you have an Ace and on that basis
> Ashkal or buy Sun."

If you bid Hokm without an Ace, partner trusts the implicit Ace-claim
and may overcall to Sun/Ashkal on a hand that depends on partner's
non-existent Ace. The convention is therefore **partner-coordination
discipline**, not just defensive shape.

### English summary

To declare Hokm, the player MUST hold an Ace (suit unspecified — any
Ace, including A-of-trump). Two rationales:
1. Defensive: the Ace is your fight-back card if opp drives Sun /
   Kaboot / Carré-A.
2. Informational: partner trusts Hokm-bidder to hold an Ace and may
   overcall to Sun/Ashkal on that assumption.

### Confidence: **HIGH**

Clean Google-Doc text. Rule is explicitly numbered ١. Arabic is
unambiguous. Page: `03b:1`.

---

## Q2 — L07 hard rule vs strategy

### The Pro-2 wording

> «فلابد من وجود اكه لديه»

The word **«فلابد»** is imperative ("it is necessary that", "must").
Standard MSA / Saudi colloquial usage. This is **categorical phrasing**,
not advisory ("ينصح" / "يفضل").

### What other Saudi-pro sources say (Phase-1 Source-H X-4)

`source_H_bidding_penalty.md:874-877` recorded that **across the 6
bidding-mechanics videos** (#27, #28, #29, #30, #34, #36) the
"side-Ace minimum for J+3-trump Hokm" was NOT stated as a hard
bidding rule:

> "Across #27 and #28, the videos describe HOW Hokm bidding works
> mechanically — but DO NOT state an explicit 'must have a side-suit
> Ace' pre-condition for the Hokm bid."
>
> "**[FOCUS]** The 'side-Ace minimum for J+3-trump Hokm' appears to be
> a STRATEGIC guideline (likely from #26 / other strategy videos), NOT
> a stated bidding RULE in this cluster."

Source-H's Phase-1 verdict was **STRATEGY (not a hard rule)** — but
that verdict was based on **bidding-mechanics videos** which describe
how Hokm bidding mechanically works (turn-order, override-rules,
Ashkal-eligibility), **not** strategic-content videos.

### Arbitration: Pro-2 itself frames this as a numbered rule

The Pro-2 PDF is a **strategy book** ("سر الاحتراف" = "Secrets of
Pro"), not a rules treatise. **Within the strategy framework**, the
author elevates L07 to a numbered, mandatory-mood rule. The phrasing
«فلابد» is the same imperative used in actual rules (e.g. «اجبار»
"obligation" appears in L08 below, where the play is genuinely
obligatory by table convention).

### The arbitration verdict

**Pro-2 L07 is a STRATEGY CONVENTION presented in mandatory-mood
phrasing.** It is NOT a rule of the game (a violation produces no
qaid, no kasho, no game-state consequence; the Hokm bid stands legally
even Aceless). It IS a Saudi-pro convention that Pro-2's author treats
as binding on serious players.

**Implementation severity:** L07 should be enforced at **strategic-
strength level**, not at **legal-veto level**.

In code terms:
- `Bot.lua:798-805`'s **hard veto** (`return false` from `hokmMinShape`
  when no Ace) is **stronger than the source warrants**. It treats a
  strategy convention as a hard rule.
- A **strength-penalty bias** (subtract from Hokm strength score, let
  the threshold gate the decision) would faithfully reflect the
  source's "convention with strong recommendation" framing.

This directly addresses **D-RT-11.6**: the design wrinkle of "hard veto
for soft Saudi convention" is real. Pro-2's text supports a **graduated
discouragement** (penalty-bias), NOT a **hard veto**. The Saudi-pro
convention is real and serious; but it is not at the same severity
level as B-4 (no-J → no-Hokm), which IS a hard mechanical floor.

This also addresses **D-RT-11.3 / 11.4** (5-trump-no-Ace force-pass
cascade): Pro-2's text does NOT prescribe "MUST pass" — it prescribes
"must hold an Ace if you wish to bid Hokm". The two are equivalent in
the simplest implementation but **diverge** when the bot's hand is
sweep-strong without an Ace. Pro-2's listed rationales (Sun-overcall
fear, Kaboot fear, Carré-A fear, partner Ace-assumption) **all weaken
substantially** when bot already holds 5 trumps including J+9:
- Opp can't force Sun without 3 Aces + cover, very rare
- Opp can't run Kaboot if bot has 5 trumps (likely sweeps anyway)
- Carré-A means opp holds all 4 Aces — possible, but bot's sweep
  in trump still scores its trump points
- Partner Ace-assumption is moot if bot's sweep wins regardless

Pro-2 does NOT state an exception for sweep-strong shapes — but it
also does NOT explicitly require "MUST pass". The arbitration is:
**the source supports `Bot.IsM3lm() and not hasAnyAce → strength
penalty` more than `→ return false`**.

### Confidence: **HIGH** (on the strategy-vs-rule classification)

The Pro-2 PDF is consistent with Source-H's Phase-1 verdict. The
mandatory phrasing «فلابد» reflects strategy-book emphasis, not
mechanical rule severity. The veto vs penalty-bias arbitration falls
clearly on the **penalty-bias side** because Pro-2's listed rationales
are scenario-specific defenses, not invariant prohibitions.

---

## Q3 — L08 Sun seat-1 mandatory backed-A+T pair lead verbatim

### Verbatim Arabic (≤15 words)

> «اذا اشترى اللاعب صن وهو الذي على رأس اللعب فلابد عليه بان يلعب الاكه المردوفة بعشرة إن وجدت»

(lines 14-15 of `03b_secrets_pro_2.txt`)

### English

If a player buys Sun and is "on the head of play" (i.e. the trick-1
leader, الذي على رأس اللعب), he MUST play the Ace-backed-by-the-Ten
(الاكه المردوفة بعشرة) if he holds one. Purpose: discover whether
projects/melds (مشاريع) exist on the table. The play is OBLIGATORY on
him AND on his partner.

### Mandatory-on-partner clause (verbatim ≤15 words)

> «وهذه اللعبة اجبارية عليه وعلى زميله»

(line 15-16)

> "And this play is obligatory on him AND on his partner."

This means: if **partner** is the trick-1 leader (because dealer
position rotates), and partner holds a backed A+T, **partner is also
obligated to play the Ace-pair** on trick 1.

### Confidence: **HIGH**

Clean text. Rule is explicitly numbered ٢. The phrasing «فلابد» +
«اجبارية» is the strongest mandatory mood the source uses. Page:
`03b:1`.

---

## Q4 — L08 mandatory vs strategy (Pro-2 wording strength)

### The dual-imperative phrasing

L08 uses **TWO** mandatory-mood markers:
1. «فلابد عليه» — "it is obligatory on him"
2. «اجبارية» — "obligatory" (literally "compulsory")

This is the strongest mandatory phrasing in the entire Pro-2 PDF. By
comparison:
- L07 uses single-imperative «فلابد» ("must")
- L09 uses recommendation «فحاول ان لا تشتريها» ("try not to buy it")

L08 sits at the top of Pro-2's strength-ladder. The author is saying
this convention is **as binding as the actual rules of the game**, even
though it is technically a play-strategy convention.

### Saudi-table reality

In real Saudi-pro tables, the "mandatory mardoofa probe lead" is
treated as a serious convention — failing to lead the backed Ace on
trick 1 of Sun, when you have one, is a sign of an inexperienced or
careless player. It would not generate qaid (no formal penalty), but
it would generate **table-talk criticism** ("you wasted the probe").
The source's «اجبارية» phrasing reflects this social-enforcement
weight.

### Implementation severity arbitration

**M8's hard `return aceCard[su]` (Bot.lua:1822) is appropriate.** L08
is the strongest mandatory-mood rule in Pro-2, and it is targeted at
the very narrow scenario "Sun bidder team's trick-1 leader holds A+T
mardoofa". The hard mandatory return matches the source's «اجبارية»
phrasing.

**This is OPPOSITE to L07.** L07 has **single** mandatory-mood
phrasing and **scenario-specific rationales** that weaken in
sweep-strong cases. L08 has **double** mandatory-mood phrasing and
**information-gathering rationale** that does NOT weaken (the probe
value of leading the Ace is constant across hand shapes — you always
learn the same amount about projects/melds from the discards).

So:
- L07 → **strategy convention** → penalty-bias appropriate
  (current code's hard veto over-reaches)
- L08 → **mandatory convention** → hard return appropriate
  (current code's hard return is correct)

### Confidence: **HIGH**

The dual-imperative phrasing is unambiguous. Saudi-table convention
weight matches.

---

## Q5 — L09 seat-1/2 deferral rule verbatim

### Verbatim Arabic (≤15 words)

> «اذا كنت على رأس اللعب أي اللاعب رقم 1 او تكون اللاعب رقم 2 والورقة المكشوفة تدعم قوتك فحاول ان لا تشتريها بالاول وانما اجلها للثاني»

(lines 18-19 of `03b_secrets_pro_2.txt`)

### English

If you are "on the head of play" — i.e. player #1 — or you are player
#2, and the up-card (الورقة المكشوفة) supports your strength, **try
not to buy it on the first round; defer it to the second round.**

### Stated reasons (verbatim ≤15 words each)

**Reason 1 — partner's first chance:**
> «لإعطاء زميلك الفرصة بالمشترى الاول»
>
> "To give your partner the chance at the first buy."

**Reason 2 — partner may form a stronger meld:**
> «فقد تشكل له هذه الورقة قوة اقوى منك اما بمشروع الخمسين او المئة»
>
> "This card may form a stronger combination for him — either the
> 50-meld project or the 100-meld project."

**Reason 3 — partner reveals Sun strength:**
> «او تكشف لك هذه الورقة بان لدى زميلك قوة صن فيشكلها او ياخذها»
>
> "Or it reveals partner has Sun strength, so he Ashkals or takes
> it himself."

### Caveats (verbatim ≤15 words each)

**Caveat 1 — only when intending Sun, AND up-card is NOT your 100-meld:**
> «هذا اذا كنت تنوي بان تشتري صن ولا تشكل لك هذه الورقة مشروع المية تحديدا»
>
> "This is when you intend to buy Sun, and the card does not
> specifically form your 100-meld."

**Caveat 2 — Hokm partner has overcall right anyway:**
> «اما بالحكم فان زميلك له الحق بالزيادة عليك اما بالاشكل او بالصن»
>
> "But for Hokm, partner has the right to overcall you with either
> Ashkal or Sun."

(Caveat 2 is a *contrast* — for Hokm bidding, the deferral logic does
not apply because partner can overcall the Hokm with Ashkal/Sun later
anyway. So the deferral is **specifically a Sun-direct strategy**,
not a Hokm strategy.)

### Confidence: **HIGH**

Clean text. Rule is explicitly numbered ٣. The full conditional chain
(seat 1/2 + up-card-supports-strength + intending Sun + up-card
NOT-100-meld) is explicit.

---

## Q6 — L09 deferral vs hard rule

### The Pro-2 wording

> «فحاول ان لا تشتريها بالاول»

The word **«فحاول»** is **conditional / advisory** ("try" — literally
"attempt"). This is the **weakest mandatory-mood marker** in the
Pro-2 PDF.

### Comparison ladder

Within Pro-2's three numbered rules:

| Rule | Mandatory phrasing | Strength |
|---|---|---|
| L07 (Hokm-needs-Ace) | «فلابد» (must) | medium-strong |
| L08 (Sun mardoofa lead) | «فلابد» + «اجبارية» (must + obligatory) | strongest |
| L09 (seat 1/2 deferral) | «فحاول» (try) | weakest |

L09 is **explicit advisory mood**. The author is recommending a
behavior, not requiring it.

### Implementation severity arbitration

**L09 is STRATEGY (not a hard rule), per the explicit advisory phrasing
in the source.** The current code's "not implemented" status (per
`xref_X4_pro2_deal.md` MF-3) is acceptable as a **missing-feature**,
not a bug. Adding L09 would improve Sun-bidder team coordination, but
its absence is not a calibration failure.

If L09 were implemented, it should be a **strength penalty** on
seat-1/2 first-round Sun bids when up-card supports strength but
doesn't complete 100-meld — letting the bid still fire on
overwhelmingly strong Sun hands while deferring the marginal cases.

### Confidence: **HIGH**

«فحاول» phrasing is unambiguous advisory mood.

---

## Q7 — Comprehensive scan: any other rules in Pro-2

The full source is 17 content lines (lines 7-23 of the extracted file).
Lines 7-9 are the title ("سر الاحتراف في البلوت ٢"). Lines 10-23 contain
the three numbered rules and their rationales/caveats. **There are NO
other rules.**

### Negative findings

- No 4th rule.
- No discussion of trick-by-trick play strategy beyond the trick-1
  Sun-mardoofa lead in L08.
- No discussion of Hokm-bid strength thresholds beyond L07's Ace
  requirement.
- No discussion of escalation chain (Bel/Triple/Four/Gahwa).
- No discussion of SWA / Kaboot mechanics.
- No discussion of Mardoof / Mathlooth / Bargiya hand-shape patterns.
- No discussion of Tahreeb / Tanfeer signals.
- No discussion of Belote (K+Q-of-trump) timing or announcements.
- No discussion of project-elimination inference (that's in PDF 04
  Pro-3, not Pro-2).
- No discussion of card-counting fundamentals (that's in PDF 03
  Pro-1).

### Confidence: **HIGH**

The PDF is exactly 1 page, the text is 17 lines, and the structural
numbering ١-٢-٣ is the closed enumeration. The scan is exhaustive.

---

## Q8 — D-RT-11.3 / 11.4 cascade fail: does Pro-2 say "MUST pass" or
recommend with EV trade-off?

### The exact Pro-2 text (re-quoted)

> «اذا اراد ان يحكم اللاعب فلابد من وجود اكه لديه»

Translation: "**If a player wants to call Hokm**, he must have an Ace."

### Linguistic analysis

The phrasing is **conditional**, not absolute:
- Antecedent: «اذا اراد ان يحكم» — "if he WANTS to call Hokm"
- Consequent: «فلابد من وجود اكه لديه» — "then he must have an Ace"

This is a **conditional implication**: IF you decide to bid Hokm, THEN
the bid presupposes an Ace. It is NOT phrased as: "If you have no Ace,
you MUST pass."

The two phrasings are **logically equivalent** (modus tollens of the
implication: ¬Ace → ¬Hokm-bid), but they have **different
implementation implications**:

- "If you bid Hokm, you must have an Ace" → **the Ace is a
  precondition for the bid** — natural implementation: in
  `hokmMinShape`, return false when Aceless.
- "If you have no Ace, you must pass" → **passing is the prescribed
  action** — natural implementation: in `Bot.PickBid`, force pass when
  Aceless.

Pro-2 chose the first phrasing. **Pro-2 does NOT say "MUST pass".**
It says "if you bid Hokm, you must have an Ace."

### What about Sun fallback?

Pro-2 L07 is silent about Sun. The defensive rationales (Sun-overcall
fear, Kaboot fear, 4-Hundred fear) all assume the bot already chose
Hokm. Nothing in Pro-2 says:
- "Aceless bot must consider Sun first"
- "Aceless bot must pass even if Sun is viable"
- "Aceless bot's only options are Hokm or pass"

The natural reading is: **if Aceless, the bot's Hokm-bid path is
closed; the rest of the picker (Sun-direct, etc.) is unaffected.**

### Implementation arbitration

**D-RT-11.3 / 11.4 cascade fail** (5+ trump no-Ace + sunMinShape false
→ R1+R2 PASS) is **NOT explicitly mandated by Pro-2**. Pro-2 closes the
Hokm path; it does not close the Sun path or the "if I have a strong
hand, find SOMETHING to bid" path.

The current code's `Bot.PickBid` cascade fail is a **side-effect of
implementation choice** (Hokm-path closure + Sun-path independent
shape requirement = cascade fail when both fail). It is NOT a verbatim
implementation of Pro-2 L07.

**Pro-2 supports the EV trade-off framing.** The source recommends
holding-an-Ace as the precondition for Hokm; it does not specify what
to do when Aceless-but-strong-trump. Saudi-pro tables in practice
would either:
1. **Bid Hokm anyway** on overwhelming trump shape (5+ trumps + J + 9),
   accepting the L07 risk for the trump sweep value. This is the
   "EV-positive deviation" approach.
2. **Pass and let opp fail on weaker shape**, accepting the Hokm-bid
   surrender for the L07 safety. This is the "convention-strict"
   approach.

Pro-2's text supports **Option 1 with caution** (the rationales weaken
when trump shape is overwhelming), but does NOT explicitly endorse it.
The convention-strict reading (Option 2) is what the v0.10.0 code
implements.

**The verbatim-strict arbitration verdict:**
- Pro-2 says: "Hokm bid → must have Ace"
- Pro-2 does NOT say: "no Ace → must pass"
- Pro-2 does NOT say: "no Ace → consider Sun then pass"
- Pro-2 IS SILENT on the cascade-fail edge case

The current code's hard-veto-then-cascade-fail is **a defensible but
strict reading** of L07. A penalty-bias implementation that lets the
strongest 5-trump-no-Ace hands STILL bid Hokm (because their strength
score survives the penalty) would be **more faithful to Pro-2's
conditional phrasing**. Either is defensible; the penalty-bias is
more nuanced.

### D-RT-11.3 / 11.4 verdict

**The cascade fail is NOT prescribed by Pro-2.** It is an
implementation artifact of treating L07 as a hard veto. Pro-2's text
neither requires nor prohibits the cascade — it's outside the source's
scope.

For the v0.10.2 review track, this means:
- Both **D-RT-11.3** (5+ trump no-Ace force-pass) and **D-RT-11.4**
  (R1+R2 cascade fail) are **legitimate calibration concerns** that
  the source does NOT settle.
- The recommendation in D-RT-11 to **either soften the gate
  (sweep-strong escape clause) OR convert to penalty-bias** is
  consistent with Pro-2's text.
- The current hard-veto implementation is **not contradicted by
  Pro-2** but is **not specifically endorsed** either.

### Confidence: **HIGH** (on the linguistic analysis)

The conditional-implication phrasing is unambiguous in Arabic.
Pro-2's silence on the cascade-fail edge is also unambiguous (the
source simply doesn't address it).

---

## Q9 — D-RT-11.6 design wrinkle: hard veto vs graduated discouragement

### Pro-2's specific support

Pro-2 L07's two rationales are **scenario-specific defenses**, not
invariant prohibitions:

**Rationale A** (defensive vs Sun-overcall / Kaboot / Carré-A):
- Probability of Sun-overcall scenario: opp needs ≥3 Aces + cover.
  Roughly 1.5-2% of hands.
- Probability of Kaboot run-out: opp needs trump-cover and Ace
  positioning. Variable.
- Probability of Carré-A: opp holds all 4 Aces. ~0.4% of hands.

These are **rare scenarios**. The convention exists to insure against
them, but the insurance value depends on the bot's own shape:
- Bot with 4 trumps + J + 0 Aces: insurance has high marginal value
  (bot is vulnerable to Sun-overcall on a marginal Hokm bid).
- Bot with 5 trumps + J + 9 + 0 Aces: insurance has low marginal
  value (bot's sweep already covers most Sun-overcall scenarios).

**Rationale B** (informational / partner-coordination):
- Partner trusts Hokm-bidder to hold an Ace.
- This trust matters for partner's overcall decisions (Ashkal, Sun
  buy).
- Strength of trust depends on session conventions — some Saudi
  tables strictly enforce, others treat as soft signal.

Both rationales are **graduated** in their force. They are NOT
binary "always applies / never applies" rules.

### Hard veto vs penalty-bias

**Hard veto** (`return false` from `hokmMinShape` when Aceless):
- Treats L07 as binary: either holds Ace or cannot bid Hokm.
- Does NOT discriminate between "marginal Hokm hand" and
  "sweep-strong Hokm hand".
- Does NOT account for Rationale A / B's graduated force.

**Penalty-bias** (subtract `K.BOT_PICKBID_NO_ACE_PENALTY` from
`strength` when Aceless):
- Treats L07 as a strong recommendation, not absolute.
- Discriminates by hand strength: marginal hands fall below threshold
  and pass; sweep-strong hands clear the threshold despite the
  penalty.
- Models Rationale A / B's graduated force naturally — the penalty
  is the "convention cost", and the bot pays it when strength is
  high enough to justify the L07 risk.

### Pro-2's specific arbitration

Pro-2 does NOT explicitly choose veto-vs-penalty. The text uses the
mandatory-mood «فلابد» but the rationales are scenario-specific. **The
honest reading is "graduated discouragement, not hard veto."**

Compare with L08's «اجبارية» (truly mandatory, no scenario-dependent
weakening): the rationale (probe value for projects/melds discovery)
is **invariant** across hand shapes. L08 deserves hard mandatory. L07's
rationale is **scenario-dependent**, so it deserves graduated
discouragement.

### D-RT-11.6 verdict

**Pro-2 supports graduated discouragement (penalty-bias) over hard
veto.** The current v0.10.0 implementation's hard veto:
- Is consistent with Pro-2's mandatory-mood phrasing.
- Is INCONSISTENT with Pro-2's scenario-specific rationale framing.
- Treats a soft strategy convention at the same severity as B-4
  (no-J → no-Hokm), which is a HARD shape rule.

**Recommendation (NOT applied per prompt):** Convert the hard veto at
`Bot.lua:798-805` to a strength-penalty:

```lua
-- Pro-2 L07 graduated discouragement (penalty, not veto):
-- Aceless Hokm hands take a strength penalty. Strong-enough trump
-- shapes survive the penalty; marginal shapes fall below threshold.
if Bot.IsM3lm and Bot.IsM3lm() and not hasAnyAce then
    strength = strength - K.BOT_PICKBID_NO_ACE_PENALTY  -- e.g. 12
    -- Drop through to the count >= 4 / count == 3 + side-Ace logic.
end
if not hasJ then return false end          -- B-4 (true hard rule)
if count >= 4 then return true end         -- B-2 self-sufficient
if count == 3 and hasSideAce then return true end  -- B-1 minimum
return false
```

This is the **strategy-as-soft-bias** approach. It preserves the L07
convention's force (most Aceless Hokm hands now fall below threshold)
while letting the strongest sweep-strong hands STILL bid (their
strength survives the penalty).

### Confidence: **HIGH**

Pro-2's rationale framing is scenario-specific in the source text.
The graduated-discouragement reading is the more faithful match.

---

## Summary table — implementation severity arbitration

| Pro-2 rule | Verbatim phrasing | Strength | Code arbitration |
|---|---|---|---|
| **L07** (Hokm-needs-Ace) | «فلابد» (must) | medium-strong | **STRATEGY convention** → penalty-bias appropriate; current hard veto over-reaches |
| **L08** (Sun trick-1 mardoofa) | «فلابد» + «اجبارية» | strongest | **MANDATORY convention** → hard return appropriate; current code is correct |
| **L09** (seat 1/2 Sun deferral) | «فحاول» (try) | weakest | **STRATEGY recommendation** → not implemented = acceptable missing-feature; if implemented, penalty-bias |

---

## Verdict on the v0.10.0 X4/L07 implementation

**The hard veto in `Bot.lua:798-805` is more aggressive than Pro-2 L07
warrants.** Pro-2's rationale framing is scenario-specific, supporting
graduated discouragement (penalty-bias) over hard veto. The cascade
fail in D-RT-11.3 / 11.4 is **NOT explicitly mandated by Pro-2** — it
is a side-effect of treating L07 as a hard veto.

**Specific arbitration on D-RT-11 findings:**

| D-RT-11 finding | Pro-2 verdict |
|---|---|
| **D-RT-11.1** (A-of-trump in `hasAnyAce`) | INFO — Pro-2 says "any Ace" without suit qualification. Code is correct. |
| **D-RT-11.2** (tier dispatch cascades correctly) | INFO — Pro-2 doesn't address tier; code's M3lm+ gate is implementation choice. |
| **D-RT-11.3** (5+ trump no-Ace force-pass) | **S2-medium CONFIRMED.** Pro-2 doesn't say "MUST pass" — its rationales weaken when trump is overwhelming. |
| **D-RT-11.4** (R1+R2 cascade) | **S2-medium CONFIRMED.** Pro-2 is silent on cascade-fail; the source doesn't prescribe pass. |
| **D-RT-11.5** (calibration drift) | S3-low — Pro-2 has nothing to say about tournament-vs-Advanced calibration. |
| **D-RT-11.6** (hard veto vs graduated) | **DESIGN CONFIRMED.** Pro-2 supports graduated discouragement. The hard veto is over-strict. |

---

## Verdict on the v0.10.2 M8 implementation

**The hard `return aceCard[su]` in `Bot.lua:1822` is CORRECT and
faithful to Pro-2 L08.** L08 is the strongest mandatory-mood rule in
Pro-2 (dual-imperative phrasing «فلابد» + «اجبارية»), and its rationale
(probe value for projects/melds discovery) is invariant across hand
shapes. The mandatory-return implementation matches the source.

**Specific verifications (vs `D-RT-10` findings):**

| D-RT-10 finding | Pro-2 verdict |
|---|---|
| **D-RT-10-r1** (CHANGELOG title misnomer) | CONFIRMED. Pro-2 explicitly says «اجبارية عليه وعلى زميله» — bidder AND partner. CHANGELOG should say "bidder-team" not "seat-1". |
| **D-RT-10-r2** (multi-mardoofa selection unsourced) | CONFIRMED. Pro-2 uses singular «الاكه المردوفة» — no tiebreaker. Hardcoded `{S,H,D,C}` order is acceptable but unsourced. |
| **D-RT-10-r3** (Advanced=false test gap) | Pro-2 doesn't address tier; code's Advanced+ gate is implementation choice, fine. |
| **D-RT-10-r4** (AKA structural impossibility comment) | Pro-2 doesn't address AKA; code's structural Hokm-only gate makes the interaction moot. Documentation note acceptable. |
| **D-RT-10-r5** (no doubled-contract gate, asymmetric with AKA L3) | **CONFIRMED genuine concern.** Pro-2 L08 has NO doubled-contract qualifier in the source text. The asymmetry with L3 is real but unsourced — needs cross-source arbitration. |
| **D-RT-10-r6** (calibration gap, no A/B simulation) | Pro-2 has nothing to say about tournament calibration. |

---

## Final confidence ladder

| Question | Confidence | Source basis |
|---|---|---|
| Q1 (L07 verbatim) | **HIGH** | Direct line 10 quote, clean text |
| Q2 (L07 hard rule vs strategy) | **HIGH** | Linguistic analysis + Source-H Phase-1 corroboration |
| Q3 (L08 verbatim) | **HIGH** | Direct line 14-16 quote |
| Q4 (L08 mandatory wording) | **HIGH** | Dual-imperative phrasing analysis |
| Q5 (L09 verbatim with conditions) | **HIGH** | Direct line 18-22 quote |
| Q6 (L09 deferral vs hard rule) | **HIGH** | «فحاول» advisory phrasing analysis |
| Q7 (comprehensive scan) | **HIGH** | 1-page PDF, exhaustive |
| Q8 (D-RT-11.3/11.4 MUST-pass) | **HIGH** | Conditional-implication phrasing analysis; Pro-2 is silent on cascade |
| Q9 (D-RT-11.6 hard veto vs graduated) | **HIGH** | Scenario-specific rationale analysis |

---

## Cross-references

- Source file: `C:\CLAUDE\WHEREDNGN\.swarm_findings\_pdf_extracted\03b_secrets_pro_2.txt`
- Phase-1 source synthesis: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_L_pdf_secrets_doubling.md` (sections L07-L09 lines 80-113)
- Phase-1 cross-source verdict: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase1_sources\source_H_bidding_penalty.md` (X-4 lines 874-877: "STRATEGIC guideline ... NOT a stated bidding RULE")
- Phase-2 cross-ref: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X4_pro2_deal.md` (MF-1/MF-2/MF-3 missing-features list)
- v0.10.0 X4/L07 implementation: `C:\CLAUDE\WHEREDNGN\Bot.lua:782-806` `hokmMinShape`
- v0.10.2 M8 implementation: `C:\CLAUDE\WHEREDNGN\Bot.lua:1806-1823` `pickLead` Sun-trick-1 mardoofa branch
- Track-D red-team L07: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-11_hokm_ace_tier.md`
- Track-D red-team M8: `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-10_m8_mardoofa_probe.md`

---

**No code modified.** This is a source-arbitration document only.
