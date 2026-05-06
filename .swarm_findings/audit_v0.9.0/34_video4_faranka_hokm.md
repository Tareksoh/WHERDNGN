# Audit 34 — Video #04 (Faranka in Hokm) re-verify @ HEAD v0.9.0

**Source transcript:** `docs/strategy/_transcripts/04_faranka_in_hokm_extracted.md`

## 1. Exception #3 wording — confirmed

Transcript table row (line 16) and Section 4 trigger #3 (line 58):

> "you hold trump-9 + trump-J; trump-J has been led/played earlier in
> the round (i.e., the J is already gone from the pool) so your 9 is
> now top trump"
> "The trump-J is already played/dead and your 9 is now the top live trump"

Wording confirms: **#3 fires when J is dead AND we hold the 9** —
the 9 must be the new top live trump. Code at `Bot.lua:2658-2667`
matches: gates on `S.HighestUnplayedRank(contract.trump) == "9"`
AND a hand-scan for the trump-9. Correct.

## 2. S.HighestUnplayedRank trump-rank fix — verified

`State.lua:1294-1323`. Two ordered tables: `AKA_ORDER` (plain
A>T>K>Q>J>9>8>7) and `TRUMP_HOKM_ORDER` (J>9>A>T>K>Q>8>7).
`HighestUnplayedRank(suit)` auto-detects whether `suit ==
s.contract.trump` AND `s.contract.type == K.BID_HOKM`, then walks
the trump order. When J is unplayed it returns "J"; once J is in
`s.playedCardsThisRound`, it returns "9". Exception #3 trigger is
mathematically tight — fires iff J is dead (boss-trump shifts to 9).
The v0.8.5 fix is correct and load-bearing.

## 3. Anti-rule "pos-4 trump-9 only + opp Faranka'd" — NOT explicitly wired

CHANGELOG.md line 1180 (test-coverage row 8) marks this rule as
"ALIGNED" but **only by emergent behavior**: the standard winners-
branch (`Bot.lua:2606-2611`) puts the 9 in `winners` when it can
take, and absent a Faranka-trigger fire, lowest-of-winners selects
the 9. There is no dedicated pos-4 / opp-Faranka'd-J-over-trumped
guard. Risk: if Exception #2 (myTrumpCount==2) ever fires
simultaneously (the 9-only case has trumpCount=1 so it doesn't),
the bot would take a non-winner. Currently safe because
Exception #2 needs ==2 trumps, but the safety is incidental, not
defensive. Status: **functionally aligned, structurally NOT wired.**

## 4. Doc drift — CONFIRMED

`docs/strategy/decision-trees.md` Section 10 (lines 246-254). Every
Hokm row still ends with `(not yet wired)`:

- L246 default no-Faranka — wired in v0.8.4 → still says "not yet wired"
- L248 exception #2 (2 trumps) — wired v0.8.4 → still "not yet wired"
- L249 exception #3 (J-dead) — wired v0.8.5 → still "not yet wired"
- L250 exception #4 (bidder + opp void) — wired v0.8.4 → still "not yet wired"
- L252 anti-rule (J+8 vs opp-bidder Q-lead) — wired v0.8.4 → still "not yet wired"

Doc-drift confirmed across 5 rows. Exceptions #1 (Kaboot pursuit)
and #5 (partner extra trump) and the pos-4 9-cover anti-rule
remain genuinely unwired and the marker is correct for those.

## Verdict

Code: correct. Tests: 330/330 (per CHANGELOG v0.9.1). Doc: drifted.
