# Opening leads — trick 1 strategy

> **Stub — populate from YouTube transcripts.**

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

> **TODO from videos:** when do Saudi pros lead 9 of trump first
> vs J? Is the 9-lead a "mistake" tier or a real strategy?

---

## Hokm contracts — defender leads (after bidder loses trick 1)

If bidder loses trick 1, the trick winner leads trick 2. Defender
team in this position should:

- Lead a side-suit Ace if held (forced bidder discard).
- Lead a low non-trump in a suit where partner is strong (signal
  reading via play observation).
- Avoid leading trump back into bidder.

> **TODO from videos:** the "AKA setup" lead — defender leads a
> non-trump card hoping partner will AKA-call. Capture the
> conditions.

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

> **TODO from videos:** Sun leading is technically rich. Capture
> what Saudi commentators say about "establishing" suits in Sun.

---

## Cross-contract: when leading from a non-bidder seat

After trick 1 (in any contract), the leader rotates to whoever won
the previous trick. Leading from a defender position:

- Read the contract: in Hokm, force trump expenditure. In Sun, build
  long suits.
- Read partner's signals: if partner played a high card on bidder's
  earlier lead, they're showing strength in that suit.

> **TODO from videos:** "lead the boss" rule — when defender holds
> the highest unplayed in a non-trump suit, leading it is "free
> points" if no opponent can ruff. Capture cases where Saudi pros
> deviate from this rule (e.g., when partner-coordination reads
> demand a different lead).

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

## Source video log

| Source | Title | Date processed | Sections informed |
|---|---|---|---|
| `02_partner_after_tahreeb` | كيف تروح لخويك اذا هرب لك في البلوت | 2026-05-04 | Tahreeb-return lead-card decision tree |
| `09_most_essential_tahreeb` | اكثر تهريب تحتاجه في البلوت | 2026-05-04 | Strong-card timing |
