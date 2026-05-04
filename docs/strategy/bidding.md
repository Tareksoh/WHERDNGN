# Bidding strategy — Hokm vs Sun vs Ashkal vs Pass

> **For operational rules see [`decision-trees.md`](./decision-trees.md)
> Section 1.** This file is the *prose* explanation — background,
> hand-strength heuristics, source provenance.

## What this file informs

- `Bot.PickBid(seat)` — main bid picker (Bot.lua:725)
- `Bot.PickAshkal(seat)` — partner-of-Hokm-bidder Sun-conversion
  decision (Bot.lua, threshold `K.BOT_ASHKAL_TH = 65`)
- `BotMaster.PickPlay` — ISMCTS sampler conditions on bid type;
  the sampler's hand distribution must align with bidding-implied
  patterns

---

## The bidder-team / defender-team asymmetry

Saudi Baloot has a **failed-bid penalty asymmetry** that drives all
bidding strategy:

| Contract | Failed-bid penalty (raw) |
|---|---|
| **Hokm** | **16 raw** to defender team |
| **Sun** | **26 raw** to defender team (×2 multiplier already factored) |

So **Sun is ~63% riskier** than Hokm on a failed bid. This is the
single biggest reason Saudi convention is to **default to Hokm**
when the hand is borderline. Source: video #25 + video #26 both
emphasize this asymmetry as the key bidder-mindset rule.

---

## Hokm (حكم) bidding

### Minimum hand to bid Hokm (canonical)

Per video #26:

> "أقل شي عشان تشتري الحكم يكون عندك الولد، وقطعة مثلا مردوفة معاه، ومعاك إكا وحدها."
>
> "The minimum to bid Hokm: J of trump (الولد) + one cover card in
> trump (مردوفة) + one side-suit Ace."

That's a 3-card minimum: **J + 1 trump + 1 side-Ace**. With these
three you can:
- Win the trump-J trick
- Use the cover trump for ruffing or trump-pull
- Cash one side-Ace for an off-trump trick

### Trump-count tiers

| Trump count | Speaker's framing | Action |
|---|---|---|
| 0-2 trumps | "ضعيف" (weak) | Pass |
| 3 trumps incl. J | Minimum threshold | Bid Hokm |
| 4 trumps | "أحلى وأحلى" (better and better) | Bid Hokm confidently |
| 5+ trumps | Al-Kaboot candidate | Bid Hokm + plan for sweep |

### When Hokm is preferred over Sun (borderline hand)

- Trump suit has J + 1 cover (مردوفة) — Sun lacks the trump anchor
- 1-2 side Aces but uneven distribution — Sun would punish weak suits
- Score state: behind in cumulative — defaulting to Hokm minimizes
  failed-bid loss (16 vs 26 raw)
- 4+ trumps but only 1 side Ace — trump-heavy hand is Hokm territory

### When NOT to bid Hokm (anti-triggers)

- No J of trump + no 9 of trump (no top-2 trump anchor)
- 4+ Aces with weak trump — should be Sun instead
- Trump suit has only 1-2 cards (no cover)
- "سراء ملكي" override: hand has K+Q meld stronger than the trump
  position would justify — different decision rules apply

---

## Sun (صن) bidding

### Minimum hand to bid Sun (canonical)

Per video #25:

> "أقل شيء لازم يكون عندك إكة وحدة، والأفضل تكون مردوفة"
>
> "Minimum: at least 1 Ace, preferably mardoofa (Ace + Ten same suit)."

The **A+T mardoofa** pattern (إكة مردوفة) is the canonical Sun-bid
trigger. The Ten "covers" the Ace — opponents can't easily tear
through your boss because the T trails behind it.

### Sun-strong hand patterns

- **2 Aces (one mardoofa)** — typical Sun bid territory
- **3 Aces (any distribution)** — Sun-strong, almost always Sun-bid
- **Carré of Aces (الأربع مئة)** — 200 raw × 2 = 400 effective; mandatory Sun
- **Long suit (4+ cards) without Aces** — actually weak in Sun;
  long suits without anchors lose to opp's higher cards

### When Sun is preferred over Hokm

- 3+ Aces in hand (the 26-vs-16 risk premium pays off)
- Mardoofa A+T in 2+ suits
- Even distribution across suits (no one suit "weak")
- Active meld project (sequence-of-5 from one suit, etc.)

### When NOT to bid Sun (anti-triggers)

- Only 1 Ace and no T to cover it (vulnerable)
- Strong trump but weak side suits — Hokm is the right home
- Score state: ≥100 cumulative — Bel-100 gate disables defender Bel,
  but you're now also under Bel-fear from defenders past 100 — wait
- Lots of Q/J/8/7 with no Aces — pure-junk hand, pass

### Sun-Mughataa (الصن المغطى) — the "covered Sun"

Per video #25: a **Sun-Mughataa** is a Sun bid where the bidder
holds A+T mardoofa as the cover anchor. The "covered" framing
emphasizes the safety: even if the A is captured, the T still wins
the next round of the suit. Bot threshold should treat
A+T mardoofa as a strength bonus distinct from raw Ace count.

---

## Ashkal (أشكال) bidding

### Eligibility (rule of game, not heuristic)

**Only the dealer + the dealer's LEFT-side seat can call Ashkal.**
Per video #31:
> "Dealer + يسار الموزع only. RIGHT (يمين) and ACROSS (أمام) cannot."

This translates to bidPositions 3 and 4 in State.lua's bidding
order — same as the current `S.HostAdvanceBidding` enforcement at
State.lua:1464-1487. **Verify:** the existing comment says "3rd and
4th players in turn order"; confirm this maps to dealer + dealer's-
left in actual seat geometry (not dealer + dealer's-right).

### Ashkal trigger conditions

You should call Ashkal when ALL of:
- Hand is **Sun-bid-eligible** (≥1 Ace, preferably A+T mardoofa,
  OR a 50/100 meld)
- Bid-up card (the trump-suit indicator from round 1) is
  **small-to-mid rank**: 7, 8, 9, J, Q, or singleton-T-without-A
- Your own hand has **stack-draw advantage** in non-trump suits
  (multiple high cards in 2+ suits) that would benefit from no-trump play

### Ashkal anti-triggers

Do NOT Ashkal if:
- Bid-up card is **A** of a suit (you'd lose the Ace into Sun
  with no protection)
- Bid-up card is **K** that would complete a sequence in your hand
- Bid-up card is **T** when you also hold the A in that suit
  (mardoofa already exists; Hokm preserves it)
- You have a meld project that requires Hokm trump-suit
- You hold 3+ Aces (just bid Sun directly, not Ashkal)

### Ashkal threshold tier

`K.BOT_ASHKAL_TH = 65` corresponds to the "1-mardoofa marginal" tier
per video #31. Behavior:
- Strength < 65 → pass (let partner have Hokm)
- 65-84 → Ashkal-eligible (convert to Sun via partner)
- 85+ → bid direct Sun (skip Ashkal, claim contract yourself)

The 85-pivot from Ashkal to direct Sun is **not yet wired** in the
current bot.

---

## Pass discipline

### Round 1 — first lap

Per video #25 R20: **first-lap pass discipline** — most beginners
over-bid in round 1. The Saudi rule of thumb: when in doubt, pass
in round 1 to see what other players do; round 2 has more info
about the table.

This rule is **currently not wired** — `Bot.PickBid` evaluates
strength with no round-1-conservative bias.

### Round 2 — terminal

Round 2 forces a bid (else round dies in re-deal). At this point
the bidder must commit on hand strength alone. Speaker emphasizes:
- Pass in round 2 only if the hand is genuinely below the Hokm
  3-card minimum
- Otherwise bid the strongest available contract

### Per-position bidding bias

| Position | Bias |
|---|---|
| 1st (dealer+1) | Widest range, can bid weak Hokm to keep partner in |
| 2nd | Narrower; bidding here implies stronger hand than 1st |
| 3rd | Can call Ashkal if partner-of-Hokm-bidder |
| 4th (dealer) | Terminal in round 1; pass = round dies |

---

## Score-state landmarks (from video #25)

Cumulative-score milestones that affect bidding decisions:

| Score | Effect |
|---|---|
| 100 | **Bel-gate floor** (Sun) — team ≥101 forbidden from Bel; team <100 may Bel |
| 120-vs-90 | **Bel-fear band** — defender at 90 is dangerously close to a Bel-doubled penalty if they Bel |
| 140-152 | **Endgame zone** — defender Bel-willingness up; bidder caution up |
| 152 | Match win |

Bot's `scoreUrgency` (Bot.lua:588) and `matchPointUrgency`
(Bot.lua:619) partially encode this.

---

## Source video log

| Source | Title | Date processed | Sections informed |
|---|---|---|---|
| `07_baloot_strategies` | استراتيجيات البلوت | 2026-05-04 | Bidding goal-discipline (make-or-sweep) |
| `25_when_bid_sun` | متى تشتري صن | 2026-05-04 | **Sun-bid heuristics: A+T mardoofa minimum, 26-vs-16 asymmetry, score landmarks** |
| `26_when_bid_hokm` | متى تشتري حكم | 2026-05-04 | **Hokm-bid heuristics: J+مردوفة+إكا minimum, trump-count tiers, "أحلى وأحلى"** |
| `27_how_to_bid_basics` | كيف تشتري في البلوت | 2026-05-04 | Auction protocol (round 1 vs round 2, Ashkal seat eligibility, pass etiquette) |
| `28_bid_rules` | قوانين الشراء | 2026-05-04 | Bid-rule cross-check (5 rules verified — see `saudi-rules.md`) |
| `31_ashkal_detailed` | شرح الاشكل بالتفصيل | 2026-05-04 | **Ashkal triggers (bid-up card analysis); 65/85 threshold pivot; dealer-LEFT seat eligibility** |

---

## Rule-correctness items — verification results

Video #28 surfaced 5 procedural rules. Cross-checked against
`State.lua` `S.HostAdvanceBidding` (line 1406) and `Net.lua`
`N._SunBelAllowed` (line 68). **4 of 5 already implemented:**

| # | Rule | Status |
|---|------|--------|
| 1 | Sun-over-Sun: later direct Sun does NOT reassign declarer | ✓ State.lua:1441-1444 |
| 2 | Hokm→Sun upgrade (Sun overcalls Hokm in either round) | ✓ State.lua:1488 + 1500-1507 |
| 3 | Round-2 Hokm cannot reuse the originally-flipped suit | ✓ State.lua:1509-1513 |
| 4 | Auto-convert-to-Sun if Hokm bidder forgets trump | ✗ UI-prevented; defensive fallback could be added |
| 5 | "Once passed, cannot Ashkal later" | ✓ Naturally enforced (per-round-one-bid + round 2 bans Ashkal) |
| BONUS | Bel-100 Sun gate (video #11) | ✓ Net.lua:68-76 (`N._SunBelAllowed`) |

Video #31 surfaced one **likely rule discrepancy** that needs
verification:

- Video #31 says Ashkal is eligible only for **dealer + dealer's
  LEFT (يسار الموزع)** — explicitly forbidding dealer's right
  (يمين) and across (أمام).
- Current code at State.lua:1468 enforces `bidPosition >= 3`. In
  the bidding order `{ dealer+1, dealer+2, dealer+3, dealer }`:
  - bidPosition 1 = `dealer+1` = **dealer's LEFT** (CCW)
  - bidPosition 3 = `dealer+3` = **dealer's RIGHT**
  - bidPosition 4 = `dealer`
  - So `>= 3` allows **dealer's RIGHT + dealer** (positions 3, 4)
- Video #31 implies the correct restriction is positions **1 + 4**
  (dealer's LEFT + dealer), NOT 3 + 4.
- **Two possibilities:**
  1. The current code is wrong and should change to `bidPosition == 1
     OR bidPosition == 4` (or equivalently, by deriving from
     `S.s.dealer` directly).
  2. Saudi convention has regional variation; the existing code's
     citation of "نظام لعبة البلوت الأساسي" reflects a different
     valid convention.
- **Recommended action:** confirm with a second Saudi source
  before changing code. If a fix is warranted, refactor to
  `R.IsAshkalEligible(seat)` derived from `S.s.dealer` rather than
  hard-coded bid-position number.
