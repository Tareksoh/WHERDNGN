# 32 — Video 14 Bargiya Re-verify vs v0.9.0 HEAD

## Verdict: PARTIAL — sender 2-flavor MIS-MAPPED; receiver phase-split NOT-WIRED

## 1. Does v0.9.0's wire actually distinguish invite vs defensive shed?

**No — not reliably.** The classifier (Bot.lua:1495-1530) decides flavor
by **observed event count** (`#signals >= 2`), not by **sender hand-shape**.
But the speaker's invite vs shed distinction is a **sender-hand-shape**
property at the moment of the discard:

- **Invite ("come-to-me")** = sender holds سوا-grade behind A (T+J/Q
  cover) + 5+ cards in suit ⇒ *محشور بلون واحد*.
- **Defensive shed ("شرد بالاكة")** = sender tracked partner-void or
  opp-strength in X and dumps A to deny opp.

Both fire as a **single discard event** in the wire. The "≥2 events"
gate the classifier uses promotes to `bargiya` only after a *second*
discard event in the same suit appears — which may never happen, and
when it does it's coincidence, not flavor signal. **The wire's `bargiya`
vs `bargiya_hint` axis is "confirmed-by-followup vs single-event", NOT
"invite vs shed".** Receiver-side scoring (3 vs 1) is therefore a
confidence-tier, not a flavor-tier as CHANGELOG framing implies.

## 2. Speaker actually says 5+ ⇒ invite, otherwise shed?

**No.** Speaker's rule 2 (transcript:16) gates *early-Bargiya timing*
on محشور بلون واحد (5+ in one suit). Rule 4 (transcript:18) defines
defensive shed as a **tracker-driven** decision (partner void / opp
about to capture A), independent of card-count. The two flavors are
**not distinguished by ≥5-cards** — they are distinguished by **sender
intent**: cover-held invite vs deny-opp shed. Both can occur with 5+
cards.

## 3. محشور بلون واحد ≡ ≥2 events?

**No — not equivalent.** محشور بلون واحد is a **sender-side
hand-shape** (5+ in one suit, short sides) used as a **fire-early**
trigger. `#signals >= 2` is a **receiver-side observation count** of
discards already played. They live on different sides of the protocol
and on different timelines. The classifier has no access to sender's
hand at the point of classification, so it cannot encode the speaker's
distinction.

## 4. Receiver phase-split status?

**NOT-WIRED.** Speaker rules 8-9 (transcript:27-28) require:
`tricksRemaining ≤ 4 ⇒ lead immediately; ≥ 5 ⇒ burn 1-2 own tricks
first`. Grep for `tricksRemaining` in Bot.lua = 0 hits in the
Bargiya-pref code path (Bot.lua:1660-1686). Receiver scoring
unconditionally returns `best = su` regardless of phase. **Confirmed
gap.** Original audit doc (14_bargiya_2flavor.md) does not mention
phase-split at all — it audited only the classifier split.

## Anti-trigger guards (rules 14-15)

Sender path (Bot.lua:2481-2494) requires `#cards >= 2` (Ace + 1 cover)
but does **NOT** check rules 14 (partner-not-winning — gated upstream
via partner-winning discard branch, OK) or 15 (≥4 cards + strong
continuation — NOT WIRED, would burn strong suits). Rule 15 is a real
gap.

## Recommended follow-ups

- Add receiver phase-split: gate `bargiya`-pref lead on
  `S.s.tricksRemaining` (or equivalent hand-size proxy).
- Rule-15 anti-Bargiya guard: reject A-discard in `pickFollow` when
  `#hand[suit] >= 4` AND `holdsContinuation(suit)`.
- Rename CHANGELOG framing: `bargiya` vs `bargiya_hint` is
  **confidence-tier** (multi-event vs single-event), not flavor-tier.

## Files
- C:/CLAUDE/WHEREDNGN/Bot.lua:1495-1530 (classifier)
- C:/CLAUDE/WHEREDNGN/Bot.lua:1660-1686 (receiver pref, no phase gate)
- C:/CLAUDE/WHEREDNGN/Bot.lua:2481-2494 (sender Bargiya, no rule-15)
- C:/CLAUDE/WHEREDNGN/.swarm_findings/audit_v0.9.0/14_bargiya_2flavor.md
