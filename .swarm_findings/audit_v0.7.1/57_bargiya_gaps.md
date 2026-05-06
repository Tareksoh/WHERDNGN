# 57 — Bargiya 2-flavor + Receiver Phase-Split Gaps (v0.7.2 HEAD)

## 1. Deferred state confirmed (Bot.lua:1407-1416)

`tahreebClassify()` collapses both Bargiya flavors into a single
`"bargiya"` return string:

```
-- Per video #14 there are two semantic flavors of Bargiya (invite vs
-- defensive shed), but for receiver-side action we treat both as
-- "lead-this-back" — the worst case is leading partner's strong
-- suit, which is still a reasonable play. Defer the
-- invite-vs-shed disambiguation to a future patch with better
-- hand-shape inference.
if signals[1] == "A" then return "bargiya" end
```

Note: lines 1334-1339 in the prompt actually contain the unrelated
`holdsBeloteThusFar` helper. The Bargiya defer-comment lives at
**1410-1415**; the audit appears to cite stale line numbers.

## 2. Impact of conflating the two flavors

The receiver branch at Bot.lua:1610-1623 leads our LOWEST card in
the Bargiya'd suit, regardless of which flavor sent the signal.

- **Flavor (a) "come-to-me invite"** — sender is محشور بلون واحد
  with 5+ cards stuck in one suit. Sender holds the suit's top
  cover; receiver leading low IS correct.
- **Flavor (b) "defensive shed"** — sender threw the Ace to deny
  opp tempo, NOT because they hold the rest. They may be void or
  near-void after the discard. Receiver leading that suit lets the
  OPP win cheaply; worse, if receiver has the Ace's natural
  follower (K/T) they expose it for opp ruff/over-take.

**Concrete waste-Aces scenario:** receiver holds A-x in the
Bargiya suit, partner threw their A as a defensive shed. Current
code leads receiver's low x → opp wins with K → next round opp
leads same suit → receiver's A is now drawn under, value spent
without partner cover. A real flavor-(b) read would have receiver
HOLD that suit and lead elsewhere.

## 3. Receiver phase-split — branch + state, not just a gate

Per video #14 the rule is: ≤4 cards → lead immediately; ≥5 cards
→ burn 1-2 own tricks first to avoid handing tempo back early.

A pure card-count gate (`#hand <= 4`) is the entry condition, but
the **action** for the ≥5 branch is not "do nothing" — it's
"select a different lead candidate from your own holdings, then
cycle back to the bargiya'd suit on a later trick." That requires:

- A new lead branch above line 1610 that, when `#hand >= 5` and
  `tahreebPrefSuit` is set, falls THROUGH to the existing
  Fzloky/Advanced lead heuristics instead of forcing the Bargiya
  return.
- Per-round state to remember "I owe partner a Bargiya return in
  suit X" so the bot doesn't permanently abandon it. `S.s.style`
  already has the `tahreebSent` table per seat; a parallel
  `tahreebOwed[suit]` flag on the receiver-side style entry would
  do it (cleared when receiver eventually leads the suit, or at
  round-end alongside `tahreebSent` in Bot.lua:150-151).

So: **new code branch + ~1 new state field**, not a one-liner.

## 4. Test coverage

`grep -n bargiya tests/` returns hits only in `test_state_bot.lua`,
and those are sender-side (T-1 Bargiya emit, line 829) plus a
Section-9 N-3 reference (line 975). **Zero tests pin
receiver-side Bargiya flavor distinction or phase-split behavior.**
A regression test added now would lock in the current
single-flavor behavior; new tests must precede the fix.
