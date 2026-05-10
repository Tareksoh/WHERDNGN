# 46_tahreeb_advanced — extracted notes

**Source:** YouTube video — "تهريب البلوت | الجزء الثاني (متقدم) — كيف
تفهم خويك بدون ما يهرب لك"
**URL:** https://www.youtube.com/watch?v=9XZiypVhr0A
**Channel:** زات | ZAT (same as videos #43 and #45)
**Slug:** 46_tahreeb_advanced
**Topic:** Tahreeb (تهريب) advanced — 5 explicit Tahreeb rules + 7
implicit-signal rules + 5 Hokm-specific signal rules. The speaker
notes "this video applies 80% of the time, sometimes partner is
just trying to win the trick (تكبير) not actually signal."

---

## Part 1: Five Tahreeb (تهريب) rules

### TR-1: Single-suit-discard → wants OPPOSITE color (NEW vs current code)
**Speaker (lines 26-32):** "If partner discards a SHAPE (suit),
it's a sign they want the OPPOSITE color."
- Discard ♦ (red) → wants ♠/♣ (black)
- Discard ♥ (red) → wants ♠/♣ (black)
- Discard ♠ (black) → wants ♥/♦ (red)
- Discard ♣ (black) → wants ♥/♦ (red)

**Current code:** `tahreebClassify` returns `"dontwant"` for
single-T/K discards (v3.0.2) and `"want_hint"` for single-7/8/9
(v3.0.3). The receiver's score table treats `"dontwant"` as a
suit-to-AVOID. **It does NOT actively suggest the opposite color.**

**Gap:** color-inversion suggestion missing. When a bot receives a
`"dontwant"` signal in (say) ♦, it correctly avoids ♦ but doesn't
prefer ♠/♣ over ♥. Per the speaker's rule, leading the SAME color
(♥) is just as bad as leading ♦.

### TR-2: Two same-color discards → wants OTHER color
**Speaker (lines 34-44):** "If partner discards TWO suits of the
same color, you understand they want the other color."
- Discard K♥, then 7♥ → wants ♠ or ♣
- Three same-color discards confirm

**Current code:** `tahreebClassify` looks at signals **per suit**.
Two K♥-then-7♥ discards both go into `tahreebSent.H` (descending
sequence → `"dontwant"` H). The code does NOT correlate **across
suits of the same color**.

**Gap:** cross-suit color tracking not implemented. The bot misses
the "two reds → wants black" inference.

### TR-3: Same-color follow-discard variant
**Speaker (lines 46-56):** "If you played a suit and partner
discards a SAME-COLOR-DIFFERENT-SUIT, they're saying 'come the
OTHER color.'"
- You played ♦, partner discards ♥ (same red) → wants black
  (♠ or ♣)

**Same gap as TR-2** — cross-suit color tracking absent.

### TR-4: Bottom-up vs top-down (already implemented)
**Speaker (lines 58-87):** "Bottom-up sequence (7→8→J of ♠) =
wants ♠. Top-down (T→J→9→7 of ♠) = doesn't want ♠."

**Current code:** `tahreebClassify` ascending → `"want"`,
descending → `"dontwant"`. ✓ **Matches.**

### TR-5: Single-A → SWA pending → IMMEDIATE lead-back
**Speaker (lines 89-104, very emphatic):** "If partner discards a
كَكَّة (Ace), STOP THE GAME and don't eat. Even if you have 70
eats. STOP and go back with that suit. Partner ALWAYS has SWA."

Then: "Lead the BIGGEST PIECE of that suit so partner's SWA
benefits maximally" — partner can claim more remaining tricks.

**Current code:** Bot.lua:2903-2914 has the `tahreebPrefFlavor ==
"bargiya"` phase-split which **defers** the lead-back when
handSize >= 5 (mid-opening). Per signals.md §3:

> Endgame (≤4 cards): lead the Bargiya'd suit immediately.
> Opening / mid-round (≥5 cards): burn 1-2 of your own tricks
> first to set up the eventual lead-back.

**Discrepancy with video #46:** the speaker says **always
immediate**, no phase-split. This is another house-rule variation
(الجلسة).

**Conservative interpretation:** signals.md was sourced from
multiple videos #14, #19; video #46 from a different speaker
(ZAT). Both reasonable. Document as a known variation; default
to current phase-split behavior.

---

## Part 2: Seven implicit-signal rules

### IM-1: Lead-as-strong-suit-signal
**Speaker (lines 122-137):** "If you're FIRST to play, lead a card
in your STRONG SUIT. Partner reads this as 'this is your suit, I'll
return it.'"

**Current code:** `pickLead` heuristics pick from longest non-trump
suit, but this isn't an EXPLICIT signal that partner reads. Partner
doesn't track "what was your first-lead suit?" as a distinct memory
key.

**Gap:** partner's first-led suit not tracked as a style-ledger
signal. We have `topTouchSignal` and `weakHandSignal` but not
`firstLedSuit`.

### IM-2: Smother for partner-led
**Speaker (lines 140-144):** "Partner first-led suit X. You play
your BIGGEST piece in X to force opp to take or you take."

**Current code:** `forceOwnInitiative` flag (Bot.lua:3844+) +
pickFollow smother branches. ✓ **Partial coverage.**

### IM-3: Remember partner's first-led suit
**Speaker (lines 146-156):** "If anyone first-leads a suit, that's
their strength. Track it. Lead back."

**Same gap as IM-1.** Partner's first-led suit recall absent.

### IM-4: AKA receive — context-aware T-give
**Speaker (lines 158-171):**
- **Start-of-round:** Partner leads A♥ → you play T♥ (so partner
  continues eating)
- **Mid-round:** Partner leads A♥ → you play T♥ (signals "I want
  this same suit again")

**Current code:** `Bot.PickAKA` + pickFollow H-5 receiver
convention. The bot DOES play T-receive on partner's bare-A lead.
**But** doesn't differentiate start-vs-mid-round behavior.

**Gap:** context-aware AKA-receive response (mid-round T-play
should also flag the suit as wanted-back).

### IM-5: Sun on the ground card (UNCLEAR translation)
**Speaker (lines 172-175):** "If partner SUNS on the card on the
ground from the start, you understand the suit they want."

This translation is unclear — "صن" might mean "took/captured" or
the contract Sun. Likely a specific take-pattern. Skipping for
now; need clarification.

### IM-6: Win-by-following = doesn't want that suit
**Speaker (lines 176-178):** "If partner wins your shape (suit)
by FOLLOWING (not AKA-claiming), they don't want that suit. Else
they'd have AKA'd it."

**Current code:** v0.10.0 R6 fix at Bot.lua:540-610 interprets
partner's high-rank play under partner's-A-led as touching-honor
signal. **Different rule** — this video's IM-6 is about partner
winning a trick by following high WITHOUT AKA, which signals
"I don't have a strong hand here, I just took what was easy."

**Gap:** "no-AKA-implies-no-strong-hand" inference absent.

### IM-7: ANTI-PATTERN — never sacrifice card adjacent to T
**Speaker (lines 179-182, very emphatic):** "NEVER sacrifice the
7♦ when you hold 7♦ + T♦. If opp plays A♦, you're FORCED to give
T anyway. So keep both — sacrifice from a different suit."
- Example: K♥+T♥ → don't sacrifice K (will lose T to opp's A)
- Example: Q♥+T♥ → don't sacrifice Q
- Example: 7♦+T♦ → don't sacrifice 7

**Current code:** v1.4.3 has `tPlusNineDoubletonSuit` exclusion
at Bot.lua:3818-3839 — but only for the SPECIFIC "9 from T+9
doubleton" case. The video's rule is BROADER: never sacrifice
ANY card adjacent to a held T (in suit) when the suit is short.

**Gap:** anti-rule needs broader coverage. Currently:
- ✓ T+9 doubleton: don't lead 9 (covered)
- ✗ T+7, T+8, T+J, T+Q doubletons: should also not sacrifice
  the lower card

---

## Part 3: Five Hokm-specific rules

### HK-1: Partner-of-Hokm-bidder drops high non-trump on bidder's quarte
**Speaker (lines 184-185):** "If partner is bidder Hokm-X, partner
plays T-of-X as a quarte (sacrifice). You drop your A or top
non-trump so partner's J/9 trump can later win the high cards."

**Current code:** Faranka heuristics partial. Not specifically
gated as "support partner's quarte-sacrifice."

**Gap:** explicit partner-bidder support rule.

### HK-2: Repeat suit when partner ruffs
**Speaker (lines 186-188):** "Opp is bidder Hokm-X. You led suit
Y. Partner ruffed with trump-X. Repeat Y so partner ruffs again,
draining bidder's trump."

**Current code:** v1.0.0 Cluster 2 F4 at Bot.lua:3764-3796
(partner-void-suit ruff setup) — leads LOW from partner-void
suit on FIRST lead. Doesn't explicitly REPEAT after observed
ruff.

**Gap:** post-ruff suit-repeat heuristic absent.

### HK-3: Bidder-partner J+9-trump sacrifice
**Speaker (lines 189-191):** "Partner is bidder Hokm-trump-X. You
have J + 9 of trump-X. Play 9-of-trump as a sacrifice — keeps J
alive for partner."

**Current code:** Bot.lua:5645-5655 handles consecutive trumps:
when winners are all trump and consecutive → highest. Otherwise
lowest. Not specifically the bidder-partner-side rule.

**Partial coverage.** ✓ Lowest of consecutive trumps wins anyway,
which matches the rule's spirit (preserve J for partner).

### HK-4: DON'T FARANKA when holding A + middle (NO TRUMP support)
**Speaker (lines 192-201):** "WARNING — in Hokm, if you Faranka,
likely lose your A. Example: A+Q♦, opp leads K♦. If you Faranka
Q (hoping partner has cover), opp's trump-9 ruffs. You lose Q
AND eventually A."

**Current code:** v0.7.x / v0.8.x Faranka anti-triggers at
Bot.lua:4380-4396, 4905-4982. ✓ **Implemented.**

### HK-5: Bidder DON'T tahreeb singleton/short-suit cards
**Speaker (lines 203-211):** "Bidder Hokm: don't tahreeb your
short suit. It reveals your void to opp; they'll lead that suit
and force partner to ruff, draining trump."

**Current code:** v1.4.4 Tahreeb sender requires no A AND no T
(avoids strong suits). **Doesn't gate on "is bidder?"** — bidder
can still tahreeb a weak short suit.

**Gap:** bidder-side restraint absent.

**Counter-side (defender exploit):** lead bidder's-void suit when
known to drain trump. Our void inference exists but exploit isn't
specifically wired.

---

## Summary: gaps in current code

| Rule | Severity | Type | Status |
|---|---|---|---|
| TR-1: Color-inversion suggestion | HIGH | Receiver | **MISSING** |
| TR-2: Cross-suit color tracking (2-discards) | MEDIUM | Receiver | **MISSING** |
| TR-3: Same-color follow-discard | MEDIUM | Receiver | **MISSING** (subset of TR-2) |
| TR-4: Bottom-up/top-down classify | — | Receiver | ✓ DONE |
| TR-5: Single-A → immediate lead-back | LOW | Receiver | **HOUSE-RULE VARIANT** (signals.md disagrees) |
| IM-1: Lead-as-strong-suit | MEDIUM | Sender + Receiver | **MISSING** |
| IM-2: Smother for partner-led | — | Receiver | ✓ DONE |
| IM-3: Remember partner's first-led suit | MEDIUM | Receiver | **MISSING** |
| IM-4: AKA-receive context-aware | LOW | Receiver | **PARTIAL** |
| IM-5: Sun-on-ground card (unclear) | — | — | **NEEDS CLARIFICATION** |
| IM-6: Win-by-follow → doesn't want | LOW | Receiver | **MISSING** |
| IM-7: Adjacent-to-T anti-rule (broader) | MEDIUM | Sender | **PARTIAL** (only T+9 wired) |
| HK-1: Partner-of-Hokm-bidder sacrifice support | LOW | Receiver | **MISSING** |
| HK-2: Repeat suit after partner ruff | MEDIUM | Sender | **MISSING** |
| HK-3: Bidder-partner J+9 sacrifice | — | Sender | ✓ PARTIAL (covered by lowest-consecutive) |
| HK-4: Don't Faranka A+middle (Hokm) | — | Sender | ✓ DONE |
| HK-5: Bidder don't tahreeb short suit | LOW | Sender | **MISSING** |

**Top-3 actionable gaps for v3.1.2 or later:**

1. **TR-1: Color-inversion** (Receiver-side). When tahreebClassify
   returns `"dontwant"` or `"want_hint"`, the receiver's score
   table should also boost the OPPOSITE-COLOR suit (suggesting
   `tahreebPrefSuit` to lead). Surgical addition to the score
   loop in pickLead.

2. **IM-7: Adjacent-to-T anti-rule (broader)**. Extend
   `tPlusNineDoubletonSuit` to cover T+7, T+8, T+J, T+Q
   doubletons. Surgical: extend the existing exclusion check.

3. **TR-2/TR-3: Cross-suit color tracking**. Add a
   `colorBalance` ledger key tracking which color partner has
   discarded. After 2+ same-color discards, mark the OTHER
   color as preferred. More involved but high-leverage for
   bot-to-bot signaling fidelity.

Lower-priority (deferred):

4. IM-1 + IM-3: first-led-suit memory + sender-side strong-suit
   lead encoding
5. HK-2: post-ruff suit-repeat heuristic
6. HK-5: bidder-don't-tahreeb-short-suit gate
7. TR-5: revisit signals.md phase-split if user adopts immediate-
   lead-back convention

---

## Notes on translation / unclear segments

- "صن على الورقها اللي بالأرض" (line 173) — best-guess "took on
  the card from the ground" but possibly Sun-contract specific.
  Skip until clarified.
- The speaker's "80% rule" (lines 9-12) — sometimes partner is
  just trying to win the trick (تكبير) without signaling intent.
  Bots reading these signals should weight them by **tier and
  context** — Saudi-Master rolls them in via ISMCTS, lower tiers
  could over-fit if every discard becomes a signal.
