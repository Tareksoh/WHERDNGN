# Opening leads — trick 1 strategy

> **v1.4.2 video-mining update**: 44-transcript scan completed for
> the 5 prose TODOs. PARTIALLY UNBLOCKED. Most topics now have
> Common-or-better evidence; gaps explicitly marked at section ends.

> Status by topic:
> - **9-of-trump vs J-of-trump first lead** — Common evidence (J is
>   canonical; 9 is "AKA-equivalent, don't sacrifice")
> - **AKA-setup lead conditions** — Definite evidence (already
>   wired; doc clarified)
> - **Sun "establishing" conventions** — Common evidence (the
>   «مسك اللون» concept formalized)
> - **"Lead the boss" deviations** — 4 distinct cases identified,
>   each Common-or-Definite
> - **Tenor / sequence-lead timing** — Common evidence on T-lead
>   tree; new "don't lead 9 from T+9" rule found

## What this file informs

- `Bot.PickPlay` → `pickLead` early-trick branch (Bot.lua, around
  line 950)
- Trick-1 decisions affect partner-style inference for the rest of
  the round (M3lm tier and above).

---

## Hokm contracts — bidder leads

The bidder takes trick 1 (lead position). Bidder lead conventions:

- **J of trump** (boss-lead) — pulls trump, draws partner's signal,
  reveals defender voids.
- **A of side suit** — captures probable trick + signals partner
  to follow with low.
- **Tenor lead (low trump)** — "milking" lead, used when bidder
  has J + 9 but no side-suit Aces; preserves J for trick 2-3.

### v1.4.2 video-mining update — 9 vs J first lead

Source: `08_smart_move_extracted.md` (video NW2GTyrqGXM):

> «ما يمديك تضحي بالتسعه في الحكم … التسعه والولد اعتبرهم اكه»
> (You cannot sacrifice the 9 in Hokm … treat the 9 and the J as
> [equivalent to] the Ace)

Corroborated by `15_kaboot_detailed_extracted.md` worked Hokm
Kaboot example which shows leading the J twice to clear trump.

**Rule**: J of trump is the canonical first-lead trump card for
the bidder. The 9 of trump is treated as AKA-equivalent — a
guaranteed future winner that should never be sacrificed in
trick 1. Confidence: **Common** by implication (no video
explicitly debates "9-lead vs J-lead" but the 9-as-AKA-equivalent
framing is emphatic).

**Code mapping**: `pickLead` Hokm bidder branch — preference for
J of trump as first lead is wired implicitly via
`highestByRank(trumpCards)` in many call paths. No specific gate
needed; the convention is naturally followed by current code.

**Gap remaining**: no transcript explicitly frames "leading 9
first is a beginner mistake" as a standalone lesson. Treated as
so obvious that no video bothers.

---

## Hokm contracts — defender leads (after bidder loses trick 1)

If bidder loses trick 1, the trick winner leads trick 2. Defender
team in this position should:

- Lead a side-suit Ace if held (forced bidder discard).
- Lead a low non-trump in a suit where partner is strong (signal
  reading via play observation).
- Avoid leading trump back into bidder.

### v1.4.2 video-mining update — AKA-setup lead conditions

Sources: `18_when_to_aka_extracted.md` + `42_play_hokm_basics_extracted.md`.

**Definite preconditions**:
1. Defender holds the highest unplayed card of a non-trump suit
2. Partner is likely void in that suit (has shown void OR has
   trump available to ruff)
3. Defender is leading (not following)
4. NOT the Ace itself (Ace lead is "implicit AKA" without
   announcement — covered by the implicit-AKA path)

> «الاكه هي تاكيك نفسها بنفسها كانك قلت عليها اكه عشان كده اذا
> قلت اك لاي ورقه خويك مش مجبر يدق بالحكم»
> (The Ace is its own AKA, like you said AKA on it, so partner
> isn't forced to ruff with trump.)

**Code mapping**: largely wired:
- `pickLead` defender boss-of-suit logic exists
- `Bot.PickAKA` (Bot.lua:1686) fires after the lead
- Implicit-AKA path on bare-Ace lead wired v0.5.16 + v0.11.18-final U-1
- Partner-AKA-receiver ruff suppression wired v0.11.19 U-6

**Gap remaining**: trick-1 *opening lead choice* as a function of
"I want to maximize my AKA-call opportunity" — what suit should a
defender lead trick-1 to set up the BEST AKA call? No transcript
addresses this from the pre-trick-1 perspective.

---

## Sun contracts — much different

Sun (no-trump) flips strategy. Key differences:

- **Lead shortest non-empty suit** (current bot heuristic, H-7 from
  v0.5.0). Reasoning: establish a long suit, force opponents to
  discard from theirs.
- **A-of-suit leads are less valuable in Sun** because there's no
  trump to ruff with — the Ace just wins one trick at face value.
- **9-of-suit leads make sense** in Sun if you have the 8 and 7;
  forces opponents to play their high cards early.

### v1.4.2 video-mining update — Sun "establishing" suits

Sources: `20_control_game_extracted.md` (primary), `06_faranka_in_sun_extracted.md`,
`13_predict_trick_extracted.md`.

The Saudi term is **«مسك اللون»** ("holding the suit") — not
"establishing", but the concept maps directly. From video #20:

**Common-confidence rules**:
1. Sun, you hold the top live cards of suit X (A + K, or after A
   you hold T + K) AND multiple cards in X → LEAD X yourself.
   You're "holding" the suit; cash multiple tricks.
2. Sun, your top in side suit X is bare T (T + 1 side card) AND
   you have NO independent strength elsewhere → LEAD T (give it
   up to partner). T won't survive.
3. Sun, your top is T with 2+ side cards → DO NOT lead T. Lead a
   low side card and preserve T as re-entry.

From video #6 (Faranka in Sun) — anti-establishing reverse:

> «ما تترنك اذا عندك اكثر من ورقتين … العشره راح تنزل من اول حله»
> (Don't Faranka if you have more than two cards [in the suit] …
> the Ten will fall on the first trick [naturally])

When you have 3+ cards including A, just lead the A — opp T falls
naturally; no need to duck (Faranka) to "fish" the T.

From video #13 prediction logic: opp leading non-Ace card → ~90%
they don't hold the Ace. Symmetric prior: if YOU hold the Ace,
opp leading non-Ace signals A is with you → free establishing
play.

**Synthesized convention**:
- Lead your highest live card when you hold 3+ of that suit
- Bargiya (signal partner via A discard) when you hold A + 1 low
- Hold strong card for round-end if turn comes early with partner
  not yet captured (video #9, "احتفظ فيها وخليها للأخير")
- "مسك اللون" requires LEAD-LEAD repetition; one Ace-lead followed
  by abandoning the suit doesn't establish

**Code mapping**: `pickLead` Sun branch. The current
shortest-suit-lead heuristic (H-7 from v0.5.0) is the OPPOSITE
direction. The "establishing" rule conflicts with shortest-suit
in 3+-card-with-A scenarios. **DEFERRED** — implementation
requires careful integration with existing Sun-shortest-suit
logic. Recommended approach: add an explicit
"isBossAndLong(suit)" gate that overrides shortest-suit when
the bot holds a 3+-card with top live cards.

---

## Cross-contract: when leading from a non-bidder seat

After trick 1 (in any contract), the leader rotates to whoever won
the previous trick. Leading from a defender position:

- Read the contract: in Hokm, force trump expenditure. In Sun, build
  long suits.
- Read partner's signals: if partner played a high card on bidder's
  earlier lead, they're showing strength in that suit.

### v1.4.2 video-mining update — "Lead the boss" deviations

Sources: `20_control_game`, `08_smart_move`, `13_predict_trick`,
`09_most_essential_tahreeb`, `06_faranka_in_sun`.

**Four distinct deviation cases identified**:

**Deviation 1 — Hold back when partner is the boss** (video #20):
Sun, partner led small/mid card (e.g. 9), you're pos-3, you hold
K of led suit AND a low card → Play LOW, let opp win this trick;
keep K in reserve. Confidence: Sometimes.

> «تخليه يمسك» (let him think he's holding the suit; you ambush
> next round)

**Deviation 2 — Hold strong card for round-end** (video #9):
Your turn, you have strength in side suit, partner not yet
captured → Hold strong card for END of round; lead Tahreeb
signal first instead. Confidence: Common.

> «احتفظ فيها وخليها للأخير» (preserve it and keep it for the end)

Already partially captured in existing `decision-trees.md` Section
3 strong-card-timing rule.

**Deviation 3 — Deceptive overplay/sacrifice** (video #8):
Sun pos-3/4, will win trick anyway, hold J + 9 → Play J (top),
NOT 9. Bait opp into believing void below J. Confidence: Common.

> «لا تلعب التسعه … العب الشايب»

Already wired at `Bot.lua:5311+` (deceptiveOverplay), M3lm-gated.
v1.4.0 narrowed T-sacrifice fallback to Saudi Master tier only.

**Deviation 4 — Faranka pos-4 duck** (video #6):
Sun pos-4, you hold A+T, partner winning → duck with T, partner
takes, cash A next round to fish opp's T. Confidence: Definite.
Anti-trigger: you hold the two highest unplayed → NEVER Faranka.

Wired at `Bot.lua:3995+` (full Faranka logic), v1.4.0 added the
"two highest unplayed" anti-trigger row 167.

**Code mapping summary**: deviations 3 and 4 are wired. Deviation
1 (pos-3 hold-back) and Deviation 2 (round-end deferral) are
PARTIALLY wired via the strong-card-timing rule but not as
explicit gates. **Recommended next steps**:
- Add explicit pos-3 hold-back gate when we hold K-of-led-suit +
  low + opp hasn't shown void
- Strengthen round-end deferral with explicit
  `partnerNotYetCapturedTrick` predicate

---

## NEW (from videos — see `decision-trees.md` Sections 3 + 8)

### Strong-card timing rule (video #9)

When you hold strength in a side-suit (especially a Ten as your
top), and turn comes to you with partner not yet having captured
a trick, **hold the strong card for the END of the round**. Lead
a Tahreeb signal first instead. Rationale: leading T early lets
opponents equalize/cut.

### Tahreeb-return lead (video #2)

If partner Tahreeb'd, the lead-back card depends on your length
in the candidate suit. Full decision tree in
[`signals.md`](./signals.md) Section 1. Summary:

- Bare T (singleton) → lead T immediately.
- T + 1 (doubled) → contract-dependent (Sun bidder partner = lead
  side card; otherwise lead T).
- T + 2+ (tripled) → lead LOW (8/9), preserve T.
- 3+ without T → lead LOW (don't burn high cards).

---

## Tenor / sequence-lead timing (v1.4.2 video-mining update)

Sources: `02_partner_after_tahreeb` (primary T-lead tree),
`05_baloot_predictions_general` (touching-honors inference).

### T-lead decision tree (Common, all from video #2)

In Tahreeb-return context (partner Tahreeb'd, you must lead back):
- **Bare T (singleton)** → lead T immediately
- **T + 1 (doubled)**: default = lead T; exception = if partner is
  Sun bidder, lead side card
- **T + 2+ (tripled)** → lead LOW (8 preferred, then 9); preserve T
  as re-entry
- **3+ without T** → lead LOW (don't burn high cards)

### NEW: Adjacent-to-T anti-rule (video #2)

> «خطأ أنك تروح بالورقة اللي جنب العشرة لو كانت العشرة مردوفة»
> (It's wrong to lead the card adjacent to T when T is doubled —
> e.g. don't lead the 9 when you hold T+9)

**Rule**: from T+9 doubleton, leading 9 telegraphs the T to
opponents. Lead T directly instead, OR lead from a different
suit. Confidence: Common.

**Code mapping**: `pickLead` Tahreeb-return branch at
Bot.lua:2931-2998. Need new predicate: `adjacentToT(card, hand)`
→ block this lead when T is in hand. **DEFERRED** —
straightforward addition.

### Sequence (tenor / مثلوث) leads — partial evidence

3-card sequence WITHOUT T (e.g. K + 7 + 8): speaker hedges,
suggests leading 8 or 7 (low) is "better." Confidence: Sometimes.

### Touching-honors inference for sequence reads (video #5)

> Partner plays T under my Ace → infer partner has K (touching
> honors). Definite.

This is the READ side: your sequence lead will be inferred by
partner. Leading T from T+K signals to partner "K is coming"
via touching-honors convention. Makes T the "correct" lead from
T+K — establishes the suit AND signals to partner.

**Code mapping**: New ledger key
`Bot._partnerStyle[partner].toptouchSignal` increment when
partner plays T → marks K likely held. Already noted as "not
yet wired" in `decision-trees.md` and `signals.md`.
**DEFERRED — Fzloky-tier feature.**

### Coverage gaps remaining

After 44-transcript scan, these specific items still LACK video
evidence:
- Trick-1 *opening* T lead (not in Tahreeb-return context)
- Broken-suit (e.g., A + J no intermediate) lead conventions
- "Tenor lead (low trump)" with J+9 no side-Aces — current
  opening-leads.md stub claim is unconfirmed by any transcript

---

## Source video log

| Source | Title | Date processed | Sections informed |
|---|---|---|---|
| `02_partner_after_tahreeb` | كيف تروح لخويك اذا هرب لك في البلوت | 2026-05-04 | Tahreeb-return lead-card decision tree; adjacent-to-T anti-rule |
| `05_baloot_predictions_general` | التوقعات في البلوت بشكل عام | 2026-05-08 | Touching-honors inference (T→K, K→Q, Q→J) |
| `06_faranka_in_sun` | ترانكا في الصن | 2026-05-08 | Anti-establishing on 3+-card-with-A; Faranka conditions |
| `08_smart_move` | الحركة الذكية | 2026-05-08 | "9 of trump = AKA-equivalent"; deceptive overplay (J-sacrifice) |
| `09_most_essential_tahreeb` | اكثر تهريب تحتاجه في البلوت | 2026-05-04 | Strong-card timing (round-end deferral) |
| `13_predict_trick` | توقع الحله | 2026-05-08 | Non-Ace lead implies ~90% no Ace held |
| `15_kaboot_detailed` | الكبوت في البلوت | 2026-05-08 | Hokm Kaboot worked example: lead J twice |
| `18_when_to_aka` | متى تقول اكا | 2026-05-04 | AKA-call preconditions; bare-Ace implicit AKA |
| `20_control_game` | تمسك اللعب | 2026-05-04 | «مسك اللون» (holding the suit); pos-3 hold-back |
| `42_play_hokm_basics` | اساسيات لعب الحكم | 2026-05-08 | AKA-relief mechanics |
