# Signals and partner conventions — Tahreeb, Tanfeer, Bargiya, AKA

> **For operational rules see [`decision-trees.md`](./decision-trees.md)
> Sections 6, 8, 9, and 11.** This file is the *prose* explanation —
> background, examples, and source provenance. Apply the rules
> from decision-trees.md; understand them from this file.

## What this file informs

- `Bot.PickAKA` — AKA call decision (Bot.lua:1686)
- `pickFollow` AKA-receiver convention (H-5 from v0.5.1)
- `Bot.OnPlayObserved` — style-ledger writes (Bot.lua:267)
- **NEW**: `pickFollow` Tahreeb / Tanfeer / Bargiya signal
  encoding-and-reading (currently not wired, ~30 rows in
  decision-trees.md Section 8)

---

## 1. Tahreeb (تهريب) — the central Saudi convention

**Tahreeb** is *the* partnership-coordination convention in Saudi
Baloot. Every discard played while partner is winning a trick must
encode a directional preference for some suit. There is no neutral
discard — silent discards are read as Tahreeb signals whether or
not you intended them to be.

### The five "forms" (video #1)

The introductory video enumerates five formal patterns:

1. **Same-suit top-down** — high then lower in same suit = "I do
   NOT want this suit." (نفس اللون عكس الشكل)
2. **Cross-color top discard** — high of opposite-color suit = "I
   refuse via opposite color." (عكس اللون)
3. **Two-card same-suit refusal** — both cards of one suit dumped,
   partner reads "wanted suit = whatever's left."
4. **Bargiya (برقية, "telegram")** — discard the **Ace** of a suit
   = "I have the slam in this suit, lead it!" Strongest possible
   positive signal.
5. **Bottom-up same-suit** — low first, higher next = "I want this
   suit (and don't have its Ace)." Substitute for Bargiya when no
   Ace held.

The video #1 author explicitly tells viewers: **don't memorize
the names — memorize the examples.** The 5-form list is a
taxonomy for teaching; the underlying rule is:

> **High-then-lower in a suit = "no, not this one."
> Low-then-higher in a suit = "yes, this one."
> Ace alone = "yes, and I'm the slam."**

### Reliability calibration (video #9)

A single Tahreeb event is **~70% reliable** — the receiver should
treat it as a hint, not a certainty. Receiver's prior on first
Tahreeb:

- 70% → partner wants the *opposite-color, opposite-shape* suit
- 25% → partner wants *same-color, other-shape*
- 5% → partner wants the suit you started in

A **second Tahreeb** in the same suit (continuing direction) raises
reliability to **~90%**. Two-trick confirmation is the
disambiguation mechanism.

The video #10 author says the **small-to-big two-discard pattern is
"100% reliable"** when fully expressed across two tricks. Treat
this as the *strongest* form.

### Receiver discipline (video #9)

Critical rule: when you, as Tahreeb-receiver, follow the next
trick, **never play your absolute lowest card**. The video author
calls this the "**biggest mistake in Baloot**" (أكبر غلط في
البلوت). Why: opponents will read your low card as "no strength
here," equalize/jam the trick, and your top cards get isolated.
Always play **second-lowest or middle-rank** to preserve
re-entry.

### The Tahreeb-return decision tree (video #2)

When partner Tahreeb'd, your lead-back depends on **your length in
the candidate return suit**:

| Your holding in return suit | Lead-back |
|---|---|
| Bare T (singleton) | Lead the T immediately |
| T + 1 side; partner is **Sun bidder** | Lead the side card (NOT T) — Sun bidders' strength concentrates differently |
| T + 1 side; partner is NOT Sun bidder | Lead the T — Tahreeb principle dominates |
| T + 2+ sides | Lead LOW (8 or 9), preserve T as re-entry |
| 3+ cards without T (e.g. K + low + low) | Lead LOW (8/7); leading K gives away the trick if opp has A |

**Anti-pattern:** never lead the card *adjacent* to a doubled T
(don't lead the 9 if you hold T+9, don't lead 8 if T+8). Telegraphs
the T to opponents, who duck (تفرنك) to scoop it later.

---

## 2. Tanfeer (تنفير) — the parent class

> **Major taxonomic refinement (video #12 vs earlier video #03):**
> Video #12 establishes that **Tanfeer is the umbrella term** for
> any throw-away discard played when you're not leading and the
> trick will be decided by someone else's card. **Tahreeb is the
> intent-bearing subset** of Tanfeer — a Tanfeer that deliberately
> encodes a directional preference.
>
> "Every Tahreeb is a Tanfeer, but not every Tanfeer is a Tahreeb."
>
> The earlier (video #03) framing of Tanfeer as a niche corner-case
> was about *interpretation priors* (lean-Tahreeb when reading
> partner) — that's a reading heuristic, not the mechanic.

### When Tahreeb interpretation applies (partner winning)

- The suit you discard is one you do NOT want partner to lead back.
- Direction encoding (top-down = refuse, bottom-up = want) carries
  the message.

### When Tanfeer-positive applies (opponent winning)

- The suit you discard IS one you DO want returned (positive).
- Inverse meaning because there's no point hiding strength via
  negative signaling once opp already won.

### Six-factor opponent-Tanfeer reading (video #19)

When **opponent** Tanfeers (you're observing), provisionally
assume they hold K/T of the discarded suit. Confidence scales with:

1. Lateness in hand (later = stronger inference)
2. Rank of discarded card (higher = more deliberate)
3. Same-suit repetition (multiple Tanfeers same suit = strong signal)
4. Cross-opp redundancy (both opps Tanfeering same suit)
5. Cancelled by later switch to different suit
6. Bidder identity (Sun-bidder-opp's Tanfeer is weaker; non-bidder-opp
   Tanfeer is stronger)

Ace-discard is the special-case Bargiya — opp claims SWA in that suit.

### Why the inversion?

When opponent already won the trick, there's no point hiding
strength via "negative discard" — they got the trick anyway. So
the channel reverses: instead of pointing AWAY from your strong
suit, you point AT it.

### The default rule (video #3)

When trick-owner is **uncertain** (50/50, 45/45/10, anything not
near-certain), **default to Tahreeb semantics**, not Tanfeer.
Speaker explicit:

> "تهريب اقوى من تنفير وقاعده تهريب تمشي معاك اكثر."
> "Tahreeb is stronger than Tanfeer and applies more often."

Tanfeer only applies when opponent-winning is near-100% certain.

### Tanfeer applied as a read

The Tanfeer convention also applies to opponents. If an opponent
performs a Tanfeer-style discard on your win-trick, recognize that
their partner will likely lead that suit back — so DON'T lead it
yourself; treat it as a suit to *avoid*.

---

## 3. Bargiya (برقية) — "the telegram"

A special form of Tahreeb: discarding the **Ace** of a suit on
partner's winning trick.

### Two semantic flavors (video #14 refinement)

Bargiya has **two distinct meanings** distinguished by hand shape
and game phase:

**(a) Come-to-me invite** — "I have the slam in this suit. Lead
it back on your next opportunity." Triggered when you're محشور
بلون واحد (cornered in one suit, holding 5+ cards there) and need
to set up the back-end SWA.

**(b) Defensive shed** (شرد بالاكة) — "Denying the opp a chance to
capture the Ace later by spending it now." Triggered when you
otherwise can't protect the Ace through to a winning trick.

### Receiver phase-split

When you receive a Bargiya, your response depends on game phase:

- **Endgame (≤4 cards in your hand):** lead the Bargiya'd suit
  immediately.
- **Opening / mid-round (≥5 cards):** burn 1-2 of your own tricks
  first to set up the eventual lead-back. Don't surrender the
  initiative immediately.
- **Void in the Bargiya'd suit:** lead it anyway — partner expects
  you to attempt regardless.

### Anti-triggers (do NOT Bargiya)

- Partner is NOT currently winning the trick.
- You hold ≥4 cards in the suit and have continuation options
  beyond the Ace.
- Opp is winning the trick (it's a Tanfeer-positive context, not
  a Bargiya).

---

## 4. AKA (إكَهْ) — the explicit signal

AKA is the **only formally-named partner signal** in Saudi Baloot,
distinct from the implicit Tahreeb/Tanfeer/Bargiya conventions.
The caller asserts: "I hold the highest unplayed card in suit X."

Mechanics already covered in v0.5.1's H-5 fix:
- AKA on a non-trump suit in Hokm — partner suppresses the forced
  ruff if caller is winning the trick.
- AKA at trick-1 or trick-2 is the strongest read; later AKA is
  sometimes a bluff.

**Touching-honors signaling** (video #5) — when partner plays a
card in response to your winning lead, the played card implies the
**next-higher rank** is in partner's hand:

| Partner played | Infer partner holds |
|---|---|
| T (Ten) | K (Shayeb) |
| K | Q (Bint) |
| Q | J (Walad) |
| Low (7/8) | **NO** higher ranks in this suit |

This is the AKA-receiver convention generalized — partner uses
**minimum-sufficient touching-honor** as the implicit signal.

---

## 5. Implicit position-based reads (video #5)

### Inverse dump conventions — contract-conditioned

When you must follow suit but are losing the trick:

- **Sun (off-trump) losers** dump **HIGHEST**. "If they had a
  smaller they'd play it."
- **Hokm (trump) losers** dump **LOWEST**. "If they had a bigger
  they'd save it."

These are **opposite rules in opposite contexts** — a critical
Saudi Baloot quirk. When extracting reads from observed plays,
condition on contract type and led-suit-vs-trump.

### Trump count (Hokm)

Counting trumps across the round is *fundamental* in Hokm. When
5 of 8 trumps are visible and your team holds 0, all 3 remaining
**must** be in one opponent's hand (pigeonhole). The bot's
sampler can extend H-1 J/9-pin logic to pin all remaining trumps
when forced.

### Length signals

When two opponents play low cards on the same trick (e.g., O1 plays
7, O2 plays 8 of suit), **the seat that played LOWER is more
likely longer in the suit**. Players with length-and-strength dump
their lowest first.

---

## 6. Counter-signals — reading the opponent

Style-ledger keys WHEREDNGN currently tracks:

- `triples` — opponent's tendency to call Bel x2.
- `gahwaFailed` — opponent has failed a Gahwa before.
- `sunFail` — opponent has failed a Sun bid before.

**Proposed new keys** (from video extractions, not yet wired):

- `tahreebSignal[partner][suit]` — direction of last 1-2 discards
  per suit per partner.
- `tahreebSuspect[partner][suit]` — partner has signaled wanting
  this suit (low discard observed).
- `trumpHighDump[seat]` — opponent over-spent trump (signals trump
  shortness).
- `toptouchSignal[partner][suit]` — partner played a card implying
  next-higher rank in same suit.
- `conventionAdherence[partner]` — rolling counter of Tahreeb /
  touching-honors convention violations; downgrades read confidence
  for partners who play loose.
- `baitDetectedBy[seat]` — opp has shown the deceptive-overplay
  bait once; same-round repeat less likely to land.

### Per-partner trust calibration

Video #5 explicitly notes: "predictions presume good convention
adherence on both sides." For a beginner-tier partner, downgrade
all touching-honors / Tahreeb reads. The
`conventionAdherence[partner]` ledger is the operational
mechanism.

---

## 7. Convention priority (video #8)

When multiple conventions apply simultaneously, the priority is:

1. **Partner's Tahreeb signal** — always honor; this is the
   partnership channel.
2. **Touching-honors** read — apply when applicable.
3. **Faranka / deceptive-overplay** — opportunistic; defer to
   Tahreeb when both apply.

The bot's `pickFollow` decision flow should consult signals
**before** any deceptive-overplay logic.

---

## Source video log

| Source | Title | Date processed | Sections informed |
|---|---|---|---|
| `01_tahreeb_beginners` | شرح التهريب في البلوت للمبتدئين | 2026-05-04 | Sections 1, 6, 8 (the five forms, Bargiya, beginner reliability) |
| `02_partner_after_tahreeb` | كيف تروح لخويك اذا هرب لك في البلوت | 2026-05-04 | Section 1 (return-suit decision tree by length) |
| `03_tahreeb_vs_tanfeer` | حالة بين التهريب والتنفير في بلوت | 2026-05-04 | Section 2 (interpretation priors) |
| `05_baloot_predictions_general` | التوقعات في البلوت بشكل عام | 2026-05-04 | Section 4 (touching-honors), Section 5 (inverse dump conventions, trump count) |
| `09_most_essential_tahreeb` | اكثر تهريب تحتاجه في البلوت | 2026-05-04 | Section 1 (70/25/5 prior, receiver discipline, "biggest mistake" rule) |
| `10_tahreeb_small_to_big` | تهريب من صغير لكبير في البلوت | 2026-05-04 | Section 1 (small-to-big as strongest two-discard form) |
| `08_smart_move` | حركه ذكيه في البلوت | 2026-05-04 | Section 7 (priority ordering: Tahreeb > deceptive-overplay) |
| `12_tanfeer_explained` | شرح التنفير في البلوت ؟ - تهريب الخصم | 2026-05-04 | Section 2 (Tanfeer parent class, Tahreeb subset taxonomy) |
| `13_predict_trick` | توقع الحلَّة | 2026-05-04 | Section 5 (trick-prediction algorithm — feeds Tahreeb/Tanfeer disambiguator) |
| `14_bargiya_ace_tahreeb` | تهريب الاكة في البلوت — البرقية | 2026-05-04 | Section 3 (Bargiya 2-flavor split, receiver phase-split, anti-triggers) |
| `18_when_to_aka` | متى تقول اكة في البلوت | 2026-05-04 | Section 4 (AKA-call preconditions, implicit-AKA bare-Ace lead) |
| `19_discover_via_tahreeb` | اكتشف اوراق خصمك من خلال التهريب | 2026-05-04 | Section 2 (six-factor opponent-Tanfeer reading) |

---

## Open questions for future videos

- **AKA cancellation** — under what conditions does a partner's
  Tahreeb cancel a prior AKA call? Not addressed in current videos.
- **Trump signaling beyond touching-honors** — Hokm-specific
  conventions for signaling trump length without spending trump.
- **Counter-Tahreeb** — when can opponents read a partnership's
  Tahreeb pattern and exploit it? Video #4 mentions opp-side
  "tafranak" but doesn't extend to systematic counter-reading.
- **Signal-suit assignment** — the "opposite-color / opposite-
  shape" mapping is mentioned across videos but never formally
  defined. What's the precise mapping? Spades ↔ Hearts? Or color
  vs shape?
