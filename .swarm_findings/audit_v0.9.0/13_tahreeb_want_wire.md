# Audit v0.9.0 — Tahreeb "want" sender arm wire

**Verdict: WIRED CORRECTLY.** CHANGELOG claim is accurate.

## Source location
`C:/CLAUDE/WHEREDNGN/Bot.lua` v0.9.0 (commit 9c32c50), lines 2485–2520, inside
the `pickFollow` partner-winning discard branch under
`Bot.IsM3lm() and voidInLed and Bot.IsBotSeat(R.Partner(seat))`.

## Behavior verified

1. **Detects A or T of side suit (≥3 cards):** Loop over `{S,H,D,C}`,
   reads `bySuit[su]`. Gate: `#cards >= 3` AND any card with
   `C.Rank(c) == "A" or "T"`. (Bot.lua:2498–2506.)

2. **First discard = LOWEST non-winner:** Builds `lows` by filtering out
   ranks A and T, then `return lowestByRank(lows, contract)`. (Bot.lua:2509–2517.)
   This is the inverse of T-4 (LARGER first); the prior code path emitted
   no ascending-sequence opener at all.

## Edge analysis

3. **Multiple side-suit A holdings:** First-match wins via the fixed
   `{"S","H","D","C"}` iteration order (line 2498). Bot returns from the
   FIRST suit that satisfies (≥3 cards) ∧ (holds A or T); any later
   qualifying suits are silently skipped this trick. Acceptable —
   subsequent discards in another A/T suit will still produce
   ascending sequences if that suit comes up later, just without the
   priority boost.

4. **A in trump (Hokm):** Excluded correctly. The `bySuit` builder at
   lines 2461–2468 skips entries where
   `contract.type == K.BID_HOKM and su == contract.trump`, so trump
   suits never enter the iteration. Sun has no trump, so all four
   suits are eligible there (correct).

5. **Conflict with T-4 dontwant arm:** No conflict. Want-arm requires
   `#cards >= 3`; T-4 requires `#cards == 2`. Mutually exclusive on a
   per-suit basis. Want arm is also placed BEFORE T-4 in code order
   (line 2497 comment confirms), so any A/T-bearing 3+-suit short-
   circuits via `return` before T-4 is reached.

   Bargiya (Sun only, A-of-≥2-suit) at lines 2470–2483 fires FIRST and
   short-circuits. In Sun with A+cover (#=2), Bargiya wins. With
   A+≥2-cover (#≥3), Bargiya still wins (returns on first A match),
   pre-empting want. This is intentional: Bargiya is the strongest
   single-event invite.

6. **Receiver classification of ascending sequence:** Verified live in
   `tahreebClassify` (Bot.lua:1484–1519). Loop at line 1511 detects
   monotonic ascending via `K.RANK_PLAIN` and returns `"want"`
   (line 1516). Receiver consumer in `pickLead` (lines 1655–1668)
   weights `cls == "want"` with score 2 and writes to `tahreebPrefSuit`,
   triggering the lead-low-in-pref-suit return at lines 1703–1717.
   Previously dead path now lit by sender output.

## Notes

The phrase "FIRST discard event from that suit" is implicit: the want
arm fires only on the first encounter (when ≥3 cards remain). On
subsequent discards from the same suit, the suit may have dropped to 2
cards, at which point T-4 takes over and emits the larger card —
which is naturally HIGHER than the lowest non-winner already played,
sustaining the ascending pattern receiver decodes as "want".
