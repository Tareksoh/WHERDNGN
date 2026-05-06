# Faranka divergence audit (Sun vs Hokm) — v0.7.2

**Scope:** decision-trees.md Sections 5 + 10 vs `Bot.lua` `pickFollow`. HEAD = v0.7.2.

## 1. Sun pos-4 Faranka branch is correctly Sun-only

**`Bot.lua:2227-2280`** — the Faranka branch is hard-gated on
`contract.type == K.BID_SUN` (line 2251):

```lua
if contract.type == K.BID_SUN and lastSeat and partnerWinning
   and trick.leadSuit
   and R.TeamOf(seat) == R.TeamOf(contract.bidder) then
```

**Verdict: CORRECT.** Hokm cannot reach this branch. The
`K.BID_SUN` check is the *only* entry guard, so a Hokm contract
falls through to the AKA-receiver block (already gated to
`K.BID_HOKM` at 2213) and then the generic smother at 2282.
No Hokm contract can ever execute the cover-duck logic.

## 2. The 5 Hokm Faranka exceptions are NOT wired (by design)

Cross-checked against decision-trees.md L242-254 (Hokm Faranka
sub-table). All 5 exceptions are marked `(not yet wired)` in the
doc and confirmed absent from `Bot.lua`:

| # | Exception | Status |
|---|---|---|
| 1 | Pursuing Al-Kaboot | NOT-WIRED |
| 2 | Only 2 trumps total | NOT-WIRED |
| 3 | J dead, 9 is new top | NOT-WIRED |
| 4 | Bidder + opp trump exhausted | NOT-WIRED |
| 5 | Partner shown extra trump | NOT-WIRED |

**Verdict: CORRECT-by-design.** The default-NO is satisfied by
omission: there is no `if shouldDuckTrump then` path in
`pickFollow`. The winners-branch (Bot.lua:2369-2467) always picks
the cheapest winner; the loser-branch falls through to
`lowestByRank` (Bot.lua:2596). The bot *structurally cannot*
voluntarily duck trump, so anti-rules #7 + #8 are also satisfied
trivially. Matches finding 10's verdict.

## 3. J-trump deceptive overplay is a SEPARATE rule, not Faranka

The J-of-trump sacrifice (decision-trees.md L109, Section 4
rule 5) is `pickFollow.deceptiveOverplay`, **not** Hokm Faranka:

- **Faranka** = pos-4 ducking with cover-card while partner is
  winning. Goal: capture two tricks via re-entry.
- **Deceptive overplay** = sacrificing J of trump (الولد) when
  *we* would win anyway. Goal: suppress opp re-pull of trump.

These are orthogonal. Section 4 rule 5 is `(not yet wired)` —
neither Sun nor Hokm variant exists in `Bot.lua` (grep
`deceptiveOverplay` returns 0 implementation hits, only ledger-
read references at Bot.lua:208, 433, 1685-1708). **No conflict
with the no-Hokm-Faranka stance.**

## 4. Section 5 vs Section 10 contradictions

**None found.** Section 10's Sun sub-table (L236-240) explicitly
defers full pos-4 rules to Section 5 ("See Section 5"). The
overlap is intentional cross-reference, not duplication.
Section 5's 9 rules and Section 10's 3-row Sun sub-table agree
on the Definite rule (A+cover Faranka) and the two NOT-WIRED
rules (Al-Kaboot pursuit, score-flip).

## Verdict

Faranka divergence is clean: Sun branch correctly tier-gated,
Hokm exceptions intentionally omitted, J-trump overplay is a
separate (deferred) rule. No action needed.
