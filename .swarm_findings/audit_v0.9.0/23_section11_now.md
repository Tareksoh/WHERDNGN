# 23 — Section 11 Re-audit @ HEAD (v0.9.0/v0.9.1)

**Commit:** 83717be (v0.9.1, one ahead of v0.9.0; no Section-11 deltas)
**File:** `docs/strategy/decision-trees.md:258-271` (8 rules)

## Per-rule verdicts

| # | Rule | Site | Verdict |
|---|---|---|---|
| 1 | Sun K/T 2nd-pos losing-follow → void | `Bot.lua:340-376` | **WIRED v0.7.2.** Sets `mem.void[leadSuit]` after lost K/T follow in Sun. Reads `S.s.contract`, `S.s.trick.plays`, dual-checks `theirRank in {K,T}` and `lost`. Local-scoped `s_trick`, no NameError. |
| 2 | Hokm trump-high-dump → opp short on trump | — | **DEFERRED.** No `trumpHighDump` ledger key in `Bot.lua:209` `emptyStyle()` or anywhere else. CHANGELOG line 1062 confirms deferred. |
| 3 | Pigeonhole pin (all-but-one void in trump) | `BotMaster.lua:285-318` | **WIRED v0.5.22.** Reads `B.Bot._memory[s].void[trump]`, builds `trumpEligible`, pins all unseen-trump → `meldPins[u] = pinSeat` when `#trumpEligible == 1`. |
| 4 | Sun-bidder partner → A/K concentration | `BotMaster.lua:111-127` (`getPartnerCards` Sun branch) | **WIRED v0.6.1.** `desire["A"..s]=8`, `desire["K"..s]=4` for all suits when `contract.type==K.BID_SUN`. |
| 5 | Tahreeb'd low → partner has A/J elsewhere | — | **DEFERRED.** No `tahreebSuspect[suit]` key. CHANGELOG line 1064 confirms. |
| 6 | Touching-honors gate (partner not winning) | — | **NOT WIRED.** No `winnerSeatSoFar`-team predicate gating reads. |
| 7 | Convention-adherence calibration | — | **NOT WIRED.** No `conventionAdherence` counter. |
| 8 | Bait-detected ledger (J on partner-winning) | WRITE `Bot.lua:487-499`, READ `Bot.lua:1785-1801` | **WIRED v0.8.2.** WRITE increments `style.baitedSuit[cardSuit]` after `R.CurrentTrickWinner(prevTrick)==R.Partner(seat)` & played J. READ in M3lm pickLead sets `fzlokyAvoidSuit` (skips trump, no override of prior avoid). Sound. |

## Touching-honors family (Section 6 rules 1-4, v0.9.0) — STILL BROKEN

`Bot.lua:442` predicate: `if not wasIllegal and contract and trick and trick.plays and #trick.plays >= 2 and style.topTouchSignal then`.

`Bot.OnPlayObserved` at line 313 declares `local trickPlays` (line 396) but **NO `local trick`**. Confirmed via grep — only `local trick = S.s.trick` exists at line 3027 (different function `pickFollow`). At line 442, `trick` is global → `nil` → predicate short-circuits false. **WRITE branch is dead; `topTouchSignal` ledger always empty `{}`.**

READ at `BotMaster.lua:445-472` is structurally correct (weight 60 nextDown, broke clears A/T/K/Q/J) but reads dead ledger → no-op.

v0.9.1 commit (`git diff v0.9.0..HEAD -- Bot.lua`) only patches A-2 (Ashkal K-block) and AKA precondition (f); the topTouchSignal NameError is **untouched**. No regression test added.

**Trivial fix:** insert `local trick = S.s.trick` near line 396 alongside `trickPlays`, OR change line 442 to `S.s.trick and S.s.trick.plays`.

## Six-factor opp-Tanfeer (video #19)

**STILL MISSING.** No `tanfeerWeight` symbol in any `.lua` file. `signals.md:126-136` documents the 6 factors (suit-rank, trick #, opp's lead-history, score, bidder identity, partner-tanfeer interaction) but no ledger keys, no reader. Doc-side gap remains; same status as audit_v0.7.1 item 11.

## Summary

- **WIRED & sound:** rules 1, 3, 4, 8 (4 of 8)
- **WIRED but dead (NameError):** Section 6 touching-honors family (v0.9.0 regression)
- **NOT WIRED:** rules 2, 5, 6, 7; six-factor opp-Tanfeer
