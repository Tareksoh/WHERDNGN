# D-RT-29: Over-Trump and Partner-Winning Relief Edge Cases

## Scope

Red-team `R.IsLegalPlay` (`Rules.lua:89-210`) and `R.CurrentTrickWinner`
(`Rules.lua:34-59`) for misbehaviour in:

- Over-trump enforcement (must overcut if you can)
- Partner-winning shortcut (you never have to over-trump partner)
- Trump-ruff requirement (void in led + has trump → must trump,
  unless partner is winning)
- v0.10.2 M4 AKA-receiver relief (lifts must-ruff for AKA receiver)

Findings are scenario-traced through code with line citations. Severity
flags **BUG** when behaviour diverges from Saudi convention or from the
function's stated contract; **NIT** for inconsistencies that don't
change legality outcomes; **OK** for cases that pass.

## Key reference data

`K.RANK_TRUMP_HOKM` (`Constants.lua:50`):
```
{ ["7"]=1, ["8"]=2, ["Q"]=3, ["K"]=4, ["T"]=5, ["A"]=6, ["9"]=7, ["J"]=8 }
```
So in Hokm trump: **J(8) > 9(7) > A(6) > T(5) > K(4) > Q(3) > 8(2) > 7(1)**.

`K.RANK_PLAIN` (`Constants.lua:51`):
```
{ ["7"]=1, ["8"]=2, ["9"]=3, ["J"]=4, ["Q"]=5, ["K"]=6, ["T"]=7, ["A"]=8 }
```
Note: in non-trump suits, J=4 (mid-rank); only in trump is J the boss.

Partner pairing (`Rules.lua:16-21`):
- 1↔3, 2↔4. Team A = {1,3}, Team B = {2,4}.

`R.CurrentTrickWinner` semantics (`Rules.lua:34-59`): if any trump
has been played in the trick, eligibility = `IsTrump`; otherwise
eligibility = `Suit == leadSuit`. The off-lead-suit non-trump cards
are silently dropped from contention.

---

## Scenario 1 — Trump-led, partner just trump-ruffed (impossible by construction, but probe partner-shortcut)

**Setup:** Trump = H. Trick: `{1=AS, 2=??}`. Seat 1 leads non-trump (AS).
Wait — this scenario ("trump-led, partner just trump-ruffed") is
contradictory: trump-led means leadSuit = trump = H, so any subsequent
trump play is following suit, not ruffing. Re-interpret as:

**Re-stated:** Trump = H. Trick: `{1=KH, 2=AH}`. Seat 1 (partner of seat 3)
led the trump suit; seat 2 (opp) over-trumped with AH. Seat 3's hand
includes JH (overcuts AH) and 7H (cannot overcut). Question: must seat 3
overcut their own partner-led-but-now-losing trump?

**Trace through `R.IsLegalPlay("7H", {7H,JH}, trick, hokm(H), 3)`:**
- Line 100: `leadSuit = "H"`, `cardSuit = "H"`.
- Line 124-127: `hasLead = true` (have H cards) → enter line 128 branch.
- Line 129: cardSuit == leadSuit, pass must-follow.
- Line 137: HOKM and leadSuit(H) == trump(H) → enter overcut block.
- Line 138: `CurrentTrickWinner` over `{KH(rk4), AH(rk6)}` →
  trumpPlayed = true; AH wins at rank 6 → seat 2.
- Line 139: `R.Partner(3) == 1`. curWinner = 2. 1 != 2 → no shortcut.
- Line 142-148: highest = max(4, 6) = 6.
- Line 149-154: hand has JH (rk 8) > 6 → canOvercut = true.
- Line 155: card = 7H, TrickRank(7H) = 1, 1 <= 6 → return false, "must overcut".

**Verdict: OK.** Seat 3 must overcut with JH even though partner led the trump.
This is correct: partner-winning shortcut requires partner to be the
*current* winner, not just the leader. Partner having led the trick
does not exempt seat 3 once partner has been over-trumped.

---

## Scenario 2 — Partner trump-led, current winner IS partner (over-trump-partner shortcut)

**Setup:** Trump = H. Trick: `{1=JH, 2=7H}`. Seat 3 (partner of 1) is to play.
Seat 1's JH (rk 8) is currently winning. Seat 3 has `{AH, 8H}` — both trumps.

**Trace through `R.IsLegalPlay("8H", {AH,8H}, trick, hokm(H), 3)`:**
- Line 100: `leadSuit = "H"`. cardSuit = "H".
- Line 124-127: hasLead = true.
- Line 137: HOKM and leadSuit == trump → overcut block.
- Line 138: `CurrentTrickWinner`: trumpPlayed = true; ranks JH=8, 7H=1 →
  best = JH at seat 1.
- Line 139: `R.Partner(3) == 1`. curWinner = 1 → match. Return true.

**Verdict: OK.** Partner-winning shortcut fires at line 139-141. Seat 3 may
play any trump (8H, AH, or anything else of suit H). They are NOT forced
to overcut partner's already-winning JH. This matches existing test
`test_rules.lua:310-316`:
```
local hand = {"AH","8H"}
local t = trick("H", {1,"JH"}, {2,"7H"})
assertTrue(R.IsLegalPlay("8H", hand, t, hokm("H"), 3),
           "Hokm trump led: partner winning, no overcut requirement")
```

---

## Scenario 3 — Lead non-trump, partner ruffed, seat must follow if has lead (must-follow takes precedence)

**Setup:** Trump = H. Trick: `{1=AS, 2=8H}`. Seat 3 (partner of 1) is to play.
Lead = S. Seat 2 ruffed with 8H. Seat 3's hand: `{KS, 7C}`.

**Trace through `R.IsLegalPlay("7C", {KS,7C}, trick, hokm(H), 3)`:**
- Line 100: leadSuit = "S". cardSuit = "C".
- Line 124-127: hasLead = true (have KS) → line 128 branch.
- Line 129: cardSuit("C") != leadSuit("S") → return false, "must follow suit".

**Verdict: OK.** Must-follow-suit takes precedence over partner-winning relief.
Even though seat 3's partner is *currently losing the trick* (seat 1's AS
was over-ruffed by seat 2's 8H), seat 3 still must play KS because they
have a spade. The partner-winning shortcut at line 167 is unreachable
(only reached when `hasLead == false`).

**Re-trace with seat 3 hand `{7C, 9D}` (void in S):**
- Line 124-127: hasLead = false → skip line 128 block.
- Line 162: not Sun → skip.
- Line 166: `CurrentTrickWinner`: trumpPlayed = true (8H is trump).
  Eligibility = IsTrump. AS is not trump → ineligible. 8H rk = 2 → best.
  Returns seat 2.
- Line 167: `R.Partner(3) == 1`, curWinner = 2 → no match.
- Line 175: akaRelief = false (no AKA passed) → skip.
- Line 178-181: hand has no trump → hasTrump = false.
- Line 182: return true (no trump, any card OK).

**Verdict: OK** when seat 3 is void of both lead and trump. Without trump,
any discard is legal. If seat 3 had a trump (e.g., `{7H, 9D}`), the
trace continues:
- Line 184: card 9D is not trump → return false, "must trump".

So a void seat-3 with trump must ruff over their partner-ruined-by-opp. **Correct
under Saudi rule** (partner-winning shortcut requires partner to be
*currently* winning, not just to have led).

---

## Scenario 4 — Multi-trump played; highest trump rank wins (verify CurrentTrickWinner ranks correctly)

**Setup:** Trump = S. Trick: `{1=AS, 2=9S, 3=JS}`.
Plain ranks for S would be A=8, 9=3, J=4 — but as trump, ranks are A=6, 9=7, J=8.
So JS should win, then 9S, then AS.

**Trace `R.CurrentTrickWinner` over `{AS, 9S, JS}` with hokm(S):**
- Line 40: trumpPlayed scan → all three are trump → trumpPlayed = true.
- Line 45-57: for each play:
  - AS: eligible (IsTrump). TrickRank = 6. bestRank = 6, bestSeat = 1.
  - 9S: eligible. TrickRank = 7. 7 > 6 → bestSeat = 2.
  - JS: eligible. TrickRank = 8. 8 > 7 → bestSeat = 3.
- Returns 3.

**Verdict: OK.** Trump-rank ordering applies inside `TrickRank` via
`K.RANK_TRUMP_HOKM` lookup at `Cards.lua:107-114`. JS correctly wins
even though plain rank A > J.

---

## Scenario 5 — `canOvercut` precondition: only when LEAD is trump

**Audit claim:** The line 137-158 over-trump-following-suit block fires
ONLY when `leadSuit == contract.trump`. If lead is non-trump and seat
follows non-trump suit, no over-trump check applies.

**Trace lead=H non-trump, trump=S:** Trick: `{1=AH, 2=??}`. Seat 2 has `{KH, 7H}`
— must follow with H, but no over-trump check among non-trump cards.

- Line 100-101: leadSuit = "H", cardSuit = "H".
- Line 137: `leadSuit == contract.trump` → "H" == "S" → false → SKIP overcut block.
- Line 159: return true (any H card legal).

**Verdict: OK.** Saudi rule: must-follow does not require beating the
current winner *unless* the suit is trump. A seat following a non-trump
trick can underplay freely (no "must beat" enforcement). This matches
Belote/Belote-derived games: the over-trump rule applies on trump
tricks only.

**However, FLAG NIT:** The off-lead trump-ruff path at line 187-208
DOES enforce overcut on non-trump-led tricks once the seat is ruffing.
That is: void + has trump + partner not winning → must trump → must
overcut prior trump if possible. So overcut enforcement is split
across TWO blocks (line 137-158 for "lead is trump, follow", line
198-208 for "void, trumping in"). This is correct but the logic is
duplicated and could drift if maintained inconsistently. **Already
flagged in `B-Rules-01`** as latent risk.

---

## Scenario 6 — 9 vs A in Hokm trump rank (J=8 > 9=7 > A=6 > T=5)

**Setup:** Trump = D. Trick: `{1=AD}`. Seat 2 has `{9D, 7D}`. Trump-led, must
follow, partner = 4 (not in winning seat). AD is currently winning at
rank 6.

**Trace `R.IsLegalPlay("7D", {9D,7D}, trick, hokm(D), 2)`:**
- Line 137: HOKM, leadSuit(D) == trump(D) → enter overcut block.
- Line 138: CurrentTrickWinner: trumpPlayed = true; AD rk 6 → bestSeat = 1.
- Line 139: Partner(2) == 4. curWinner = 1 → no match.
- Line 142-148: highest = 6 (from AD).
- Line 149-154: hand has 9D (rk 7 in trump). 7 > 6 → canOvercut = true.
- Line 155: card = 7D, rk = 1. 1 <= 6 → return false, "must overcut".

**Verdict: OK.** 9 of trump *does* beat A of trump in Hokm (the
Saudi-specific rank order). Seat 2 must play 9D, not 7D. This is one
of the "Saudi-specific rules" called out in `CLAUDE.md`:
> 9 of trump is rank 7 (second-highest)…

**Sub-check: seat 2 has only `{AD, 7D}` (no overcut possible):**
- Line 149-154: AD rk 6, 7D rk 1. Neither > 6 → canOvercut = false.
- Line 155: skip the false branch.
- Line 159: return true. Both AD and 7D legal (any trump).

So **AD can underplay against itself** in this hand (impossible at
table — only one AD exists — but the logic is hand-state-relative).
Underplay/discard freely once overcut impossible. **Correct.**

---

## Scenario 7 — AKA relief overrides partner-not-winning

**Setup:** Trump = H. Trick: `{1=AS, 2=8H}`. Seat 3 (partner of 1) is to
play. Seat 1 called AKA on S; banner = `{seat=1, suit="S"}`. Seat 3 hand
= `{7H, 9D}` (has trump, void in S).

Seat 1 led AS (the AKA-anchor). Seat 2 (opp) ruffed with 8H. Now seat 3
must play; without AKA they would be forced to ruff.

**Trace `R.IsLegalPlay("9D", {7H,9D}, trick, hokm(H), 3, {seat=1,suit="S"})`:**
- Line 100: leadSuit = "S".
- Line 116-121: akaCalled passed; akaCalled.seat=1; Partner(3)=1 → match;
  akaCalled.suit("S") == leadSuit("S") → match; HOKM → match.
  → akaRelief = true.
- Line 124-127: hasLead = false (no S in hand) → skip line 128 block.
- Line 162: not Sun → skip.
- Line 166: CurrentTrickWinner → 8H ruffed AS, seat 2 wins.
- Line 167: Partner(3)=1, curWinner=2 → no shortcut. (Partner did
  lead the AKA card but got over-ruffed.)
- Line 175: akaRelief = true → return true.

**Verdict: OK.** AKA-receiver relief correctly fires AFTER partner-winning
shortcut fails (line 167) and BEFORE must-trump (line 184). 9D is
discardable freely. Aligns with Saudi convention "AKA receiver is
exempt from must-ruff after AKA call on led suit" (J-066/J-067 part 2).

**Sub-check: receiver has lead-suit (must-follow takes precedence over AKA relief):**
Hand = `{KS, 7H, 9D}`, same trick.
- Line 124-127: hasLead = true (have KS).
- Line 129: cardSuit("D") != leadSuit("S") → return false, "must follow suit"
  (when querying card = 9D).
- Line 137: HOKM but leadSuit(S) != trump(H) → skip overcut block.
- Line 159: return true (when querying card = KS).

So receiver MUST play KS even with AKA-relief active. **Correct under
Saudi rule** — see existing finding `B-Rules-01` F3 confirming this is
intended; comment at `Rules.lua:113-114` is misleading but logic is
right. **Latent comment-fix already documented; not a new finding here.**

---

## Scenario 8 — Specific trace: trick `{1=KH, 2=8H, 3=AH}`; seat 4 has 9H

**The prompt's specific trace request.** Trump = H. Hand of seat 4: `{9H}`.

**Trace `R.IsLegalPlay("9H", {9H}, trick, hokm(H), 4)`:**
- Line 100: leadSuit = "H", cardSuit = "H".
- Line 124-127: hasLead = true (9H is H).
- Line 129: cardSuit == leadSuit → pass must-follow.
- Line 137: HOKM, leadSuit(H) == trump(H) → enter overcut block.
- Line 138: `CurrentTrickWinner({KH,8H,AH}, hokm(H))`:
  - trumpPlayed = true.
  - KH rk 4 → bestSeat=1, bestRank=4.
  - 8H rk 2 → 2 < 4, skip.
  - AH rk 6 → 6 > 4 → bestSeat=3, bestRank=6.
  - returns 3.
- Line 139: Partner(4)=2. curWinner=3 → no match → continue.
- Line 142-148: scan trick for highest trump rank: max(4, 2, 6) = 6.
- Line 149-154: scan hand for trump > 6:
  - 9H rk 7. 7 > 6 → canOvercut = true.
- Line 155: card = 9H, TrickRank = 7. 7 <= 6? No (7 > 6). Skip false branch.
- Line 159: return true.

**Verdict: OK.** Seat 4's 9H is legal (it overcuts the AH at rank 6 with
rank 7). The prompt's claim was "verify code returns 'must overcut'
forcing 9H" — this is correct in the sense that **9H is the only legal
play**: any non-overcutting trump (e.g., 7H, 8H if seat 4 also had them)
would return false with "must overcut". The 9H itself is legal *because*
it overcuts. The "must overcut" is the *forcing rule*, not the rejection
message for 9H.

**Sub-check: seat 4 hand `{9H, 7H, 8H}` (give other trump options):**
- Same trace through line 154: canOvercut = true (because of 9H).
- Query card = 7H: rk 1, 1 <= 6 → return false, "must overcut".
- Query card = 8H: rk 2, 2 <= 6 → return false, "must overcut".
- Query card = 9H: rk 7, 7 > 6 → return true (line 159).

Correct: only 9H is legal. **9 of trump beats Ace of trump** is
exercised through `K.RANK_TRUMP_HOKM[9]=7 > K.RANK_TRUMP_HOKM[A]=6`.

---

## Scenario 9 (Bug probe) — Off-suit lead, partner is winning, AKA banner stale-but-still-set, receiver tries to discard with non-trump

**Goal:** Probe AKA-relief + partner-winning interaction (F5 from
B-Rules-01: redundant gate ordering).

**Setup:** Trump = H. Trick: `{1=AS}`. Seat 2 to play (opp of 1).
Then trick advances: `{1=AS, 2=7S, 3=KS}`. Seat 3 (partner of 1) follows
with KS, partner now winning. Seat 4 (opp of 1) is void in S, has trump.

Now consider seat 1 had previously called AKA on S. Banner =
`{seat=1, suit="S"}`. Seat 4 is the opp, NOT the receiver. Partner(4)=2,
not 1. AKA relief is for receiver (partner of caller).

Hand of seat 4 = `{9H, 7C}`. Trying to discard 7C.

**Trace `R.IsLegalPlay("7C", {9H,7C}, trick, hokm(H), 4, {seat=1,suit="S"})`:**
- Line 116-121: akaCalled.seat=1; Partner(4)=2 → 2 != 1 → akaRelief = false. **Correct: opps don't get relief.**
- Line 124-127: hasLead = false (no S in `{9H,7C}`).
- Line 166: CurrentTrickWinner over `{AS,7S,KS}`. trumpPlayed = false (none are trump).
  Eligibility = (suit == leadSuit "S"): AS rk 8, 7S rk 1, KS rk 6.
  Best = AS at seat 1 (rank 8 > 6 > 1).
  Wait — KS rk 6, AS rk 8 in plain. AS wins. bestSeat = 1.

  **WAIT.** Does seat 3's KS beat seat 1's AS? In plain: A=8 > K=6 → AS wins.
  Re-stated trick is `{1=AS, 2=7S, 3=KS}` — so the partner-winning
  scenario doesn't actually arise with KS, because AS beats KS.
- Line 167: Partner(4)=2, curWinner=1 → no match.
- Line 175: akaRelief = false → skip.
- Line 178-181: hasTrump = true (9H).
- Line 184: card 7C is not trump → return false, "must trump".

**Verdict: OK.** Opp seat 4 must ruff. AKA banner does NOT spuriously
extend relief to opps.

**Sub-check (receiver path, partner actually winning):**
Trick `{1=AS, 2=7S, 3=anything-low-S}`. Seat 4 is partner-of-2, NOT the
receiver. Let's reframe: Seat 1 calls AKA on S. Banner = `{seat=1, suit="S"}`.
Receiver = seat 3. Trick = `{1=AS}` only — partner just led the AKA card.
Seat 2 plays 7S (forced to follow). Seat 3 to play. Hand = `{9H, KS, 7C}`.

This is the natural "AKA called, partner just led AKA boss, opp under-followed,
receiver to play." Receiver hasLead = true (KS).

- Line 124-127: hasLead = true.
- Line 129: cardSuit("S") = leadSuit("S") for KS → pass must-follow.
  But cardSuit("H") != "S" for 9H → return false, "must follow suit".
- Line 137: leadSuit(S) != trump(H) → skip overcut.
- Line 159: return true (KS is fine).

Receiver must play S (KS), AKA-relief does not lift must-follow (correct).

**Now reframe to reach AKA relief gate:** Trick = `{1=AS, 2=8H}`
(seat 2 over-ruffed AS with 8H trump). Seat 3 to play. Hand = `{9H, 7C}`.
- Line 116-121: akaRelief = true.
- Line 124-127: hasLead = false (no S).
- Line 166: CurrentTrickWinner. trumpPlayed = true (8H). Eligibility = IsTrump.
  AS not trump → ineligible. 8H rk 2 → bestSeat=2.
- Line 167: Partner(3)=1, curWinner=2 → no match.
- Line 175: akaRelief = true → return true. **Discard freely.**

**Verdict: OK.** F5's "ordering verification" check passes: when
partner is winning (curWinner=1), line 167 fires first and returns
true; AKA-relief at line 175 is irrelevant. When partner is NOT
winning (curWinner=2 after over-ruff), line 167 falls through and
line 175 fires. The two reliefs are layered correctly — partner-winning
takes precedence (broader applicability), then AKA-relief catches
the post-over-ruff case.

---

## Scenario 10 (Bug probe) — Off-suit lead, void receiver, AKA banner says wrong-suit (stale)

**Setup:** Trump = H. Banner = `{seat=1, suit="C"}` (AKA was called on C
last trick or prior; State.lua should have cleared but assume race).
Current trick = `{1=AS, 2=8H}`. Seat 3 hand = `{9H, 7D}`.

**Trace `R.IsLegalPlay("7D", {9H,7D}, trick, hokm(H), 3, {seat=1,suit="C"})`:**
- Line 116-121: akaCalled.suit("C") != leadSuit("S") → akaRelief = false.
- Line 124-127: hasLead = false.
- Line 166: CurrentTrickWinner = 2 (8H ruff).
- Line 167: Partner(3)=1, curWinner=2 → no match.
- Line 175: akaRelief = false → skip.
- Line 178-181: hasTrump = true.
- Line 184: card 7D is not trump → return false, "must trump".

**Verdict: OK.** Stale-suit AKA banner does not bleed into a different
suit's lead. The `akaCalled.suit == leadSuit` gate at line 118 is
the safeguard. Already covered by `test_rules.lua` Q.7.

**FLAG NIT (already in B-Rules-01 F4):** No defensive
`akaCalled.suit ~= contract.trump` guard. If the banner is somehow set
to `{seat=1, suit="H"}` (= trump) and trump is led — relief gate fires:

**Sub-trace: stale AKA on trump. Banner `{seat=1, suit="H"}`. Trick `{1=KH, 2=AH}`.
Seat 3 hand `{JH, 7C}`.**
- Line 116-121: akaCalled.suit("H") == leadSuit("H"), HOKM, partner match
  → akaRelief = true.
- Line 124-127: hasLead = true (JH is H) → enter line 128.
- Line 129: pass must-follow (JH is H).
- Line 137: leadSuit == trump → enter overcut block.
- Line 138: CurrentTrickWinner returns seat 2 (AH rk 6).
- Line 139: Partner(3)=1, curWinner=2 → no shortcut.
- Line 142-148: highest = 6.
- Line 149-154: JH rk 8 > 6 → canOvercut = true.
- Line 155: query 7C — not legal (must follow). Query JH: rk 8 > 6 → return true.

**Wait — the akaRelief gate is computed but never checked in the line
128-159 block.** It's only consulted at line 175 (the void-but-has-trump
path). So when leadSuit = trump, the AKA-relief is irrelevant
structurally. The over-trump enforcement still fires.

**Verdict: OK** for trump-led even with stale trump-suit banner. The
F4 concern is theoretical — it would need TWO bugs (stale banner +
suit-equals-trump) to manifest, AND on a trump-led trick the AKA-relief
gate isn't actually consulted. **F4 is even softer than B-Rules-01
suggested.** Still, defensive guard remains good hygiene.

---

## Scenario 11 (Bug probe) — Lead is trump, partner is winning, but partner-winning shortcut at line 139-141 evaluated BEFORE canOvercut precondition

**Setup:** Trump = H. Trick: `{1=AH, 2=7H}`. Seat 3 (partner of 1) to play.
Seat 3 hand: `{JH, 8H, 7D}`.

**Trace 8H:**
- Line 137: HOKM, leadSuit(H) == trump → enter.
- Line 138: CurrentTrickWinner: AH rk 6 wins, bestSeat=1.
- Line 139: Partner(3)=1 → match → return true.

Doesn't matter that JH would overcut. Partner-winning shortcut wins
because it's checked BEFORE canOvercut.

**Verdict: OK.** Correct: you never have to over-trump partner. Matches
the test at `test_rules.lua:310-316`.

**Sub-check NIT:** What if seat 3 plays a non-trump card? Hand `{JH, 7D}`,
query card = 7D.
- Line 129: cardSuit("D") != leadSuit("H") → return false, "must follow suit".

So the partner-winning shortcut at line 139-141 does NOT lift must-follow.
Seat 3 must play SOME trump, just not necessarily an overcut. Correct.

---

## Scenario 12 (Bug probe) — Off-suit lead + multiple-trump-played + partner is winning highest trump + receiver tries to underplay

**Setup:** Trump = H. Trick: `{1=AS, 2=KH, 3=JH}`. Seat 1 led AS; seat 2
(opp) ruffed with KH; seat 3 (partner of 1) over-ruffed with JH.
Seat 4 (opp of 1, partner of 2) to play. Hand: `{7H, 9D}`.

**Trace 7H:**
- Line 100: leadSuit = "S".
- Line 116-121: no akaCalled → akaRelief = false.
- Line 124-127: hasLead = false.
- Line 166: CurrentTrickWinner: trumpPlayed = true. KH rk 4, JH rk 8 →
  best = JH at seat 3.
- Line 167: Partner(4)=2, curWinner=3 → no match.
- Line 175: akaRelief = false.
- Line 178-181: hasTrump = true (7H).
- Line 184: card is trump → pass.
- Line 187-193: highestTrumpRank from trick = max(4, 8) = 8.
- Line 199-204: scan hand for trump > 8: 7H rk 1 → no. canOvercut = false.
- Line 205-208: skip.
- Line 209: return true.

**Verdict: OK.** Seat 4 cannot overcut JH (no card > rank 8 since J is
the boss); 7H is the only trump and it's legal as a forced
under-trump. Saudi convention: when you can't overcut, any trump
suffices; you're forced into a losing ruff but that's by-design.

**Edge: what if seat 4 has only `{7H, 7D}` and the under-trump ruff
"throws away" the trick — is that correct?**
Yes. The rule is "must trump if void in lead, even if you can't beat
the current winner." This is the cardinal Belote-derived rule; the
Saudi `Rules.lua:177-209` correctly enforces it.

---

## Scenario 13 (Bug probe) — Partner just led trump, no over-trump yet, seat is to play with weak trump (ducking allowed?)

**Setup:** Trump = H. Trick: `{1=KH}`. Seat 2 (opp of 1) to play. Seat 2
hand: `{7H, 8H}`.

Question: can seat 2 duck under partner... wait, seat 2 is OPP of 1.
This is the standard "trump-led, opp follows weak."

**Trace 7H:**
- Line 137: HOKM, leadSuit(H) == trump → enter.
- Line 138: CurrentTrickWinner over `{KH}`: trumpPlayed = true, KH rk 4 →
  bestSeat=1.
- Line 139: Partner(2)=4, curWinner=1 → no match.
- Line 142-148: highest = 4.
- Line 149-154: 7H rk 1, 8H rk 2 — neither > 4 → canOvercut = false.
- Line 155: skip false branch.
- Line 159: return true.

**Verdict: OK.** Seat 2 may play 7H or 8H (any trump). Correct: no
overcut available, so under-trump is permitted. Matches existing test
`test_rules.lua:289-296`.

---

## Scenario 14 (Bug probe) — Trick winner ambiguity if `bestRank == -1` (defensive: no eligible cards)

**Setup:** Trump = H. Trick: `{1=AS, 2=KD}` (lead = S, no spades after lead,
no trump). `R.CurrentTrickWinner`:
- trumpPlayed = false.
- Eligibility = (suit == "S"). KD ineligible. AS rk 8 → bestSeat=1.
- Returns 1.

**Sub-trace abuse: trick = `{1=AS, 2=KD}` and `leadSuit` is set to "C"
(corrupted state from a peer):**
- trumpPlayed = false.
- Eligibility = (suit == "C"). Neither matches.
- bestRank stays at -1. bestSeat stays nil. Returns nil.

Then in IsLegalPlay (caller path):
- Line 166: curWinner = nil.
- Line 167: `nil and …` → false. Skip shortcut.

**Verdict: OK.** Defensive: nil curWinner does NOT crash (`nil and …`
short-circuits). Continue to must-trump enforcement. But a hostile
peer who could spoof `trick.leadSuit` could potentially manipulate the
partner-winning shortcut by making it never fire — but that just makes
the code stricter on the sender, not looser. **No exploitation
vector.**

---

## Scenario 15 (Bug probe) — Bug reproducer: seat 4 has TH, KH, 9H against trick `{1=AS, 2=AH}`. Must seat 4 over-trump 8H? AH? What's the precise threshold?

**Setup:** Trump = H. Trick: `{1=AS, 2=AH}`. Seat 4 (opp of 1, partner
of 2) to play. Hand: `{TH, KH, 9H}`.

Wait — seat 2 over-trumped with AH and is **partner of seat 4**. So
this is the "partner ruffed; receiver doesn't have to over-trump partner"
case in the void+trump path.

**Trace 7H — wait, no 7H in hand. Trace KH:**
- Line 100: leadSuit = "S".
- Line 124-127: hasLead = false.
- Line 166: CurrentTrickWinner: trumpPlayed = true. AS ineligible (not trump).
  AH rk 6 → bestSeat=2.
- Line 167: Partner(4)=2, curWinner=2 → match → return true.

**Verdict: OK.** Seat 4 may discard ANY card (KH, TH, 9H, or even a
non-trump non-S if they had one). Partner-winning shortcut on void
path correctly fires. Matches existing test `test_rules.lua:273-279`.

This means TH and 9H could be discarded — even though both could
overcut AH (TH rk 5 < AH rk 6, so TH does NOT overcut, but 9H rk 7
> 6 and would overcut). But seat 4 is **not required to** play 9H
because partner is winning. **Correct Saudi rule: you never have to
over-trump partner.**

---

## Scenario 16 (Bug probe) — Sun contract: no trump, partner-winning shortcut (no over-trump rule applies)

**Setup:** Sun contract. Trick: `{1=AS, 2=KS}`. Seat 3 (partner of 1)
to play. Hand: `{TS, 9S}`.

Sun: A=8, T=7, K=6, Q=5, J=4, 9=3, 8=2, 7=1.

**Trace TS:**
- Line 100: leadSuit = "S", cardSuit = "S".
- Line 116-121: contract.type == BID_SUN → akaRelief = false (HOKM gate).
- Line 124-127: hasLead = true.
- Line 129: pass must-follow.
- Line 137: contract.type != HOKM → skip overcut block.
- Line 159: return true.

**Verdict: OK.** Sun has no trump, no over-trump rule. TS is legal
even though it doesn't beat the current winner AS. Saudi rule for
Sun: must-follow only. Matches `Rules.lua:163` (`if contract.type ==
K.BID_SUN then return true end`).

**Sub-check: Sun + void in lead-suit → free discard:**
Hand = `{KH, 9D}`, trick `{1=AS}`.
- Line 124-127: hasLead = false.
- Line 162: contract.type == BID_SUN → return true.

Anything legal. **Correct.**

---

## Scenario 17 (Bug probe) — Verify that lead-suit follow does NOT enforce overcut for non-trump leads even if the seat ruffs

**Setup:** Trump = H. Trick: `{1=AS, 2=??}`. Seat 2 hand `{KS, 7H}`.
Trying to play 7H (ruff before void).

- Line 100: leadSuit = "S", cardSuit("7H") = "H".
- Line 124-127: hasLead = true (KS in hand).
- Line 129: cardSuit("H") != leadSuit("S") → return false, "must follow suit".

**Verdict: OK.** Saudi rule: you cannot voluntarily ruff if you have
the lead suit. Must-follow takes precedence even when you have a
"better" card via trump. Correct enforcement.

---

## Scenario 18 — Edge: seat with only `{7H}` in trump-led trick where current winner is `JH` (partner). Forced to play impossible-overcut card.

**Setup:** Trump = H. Trick: `{1=JH}`. Seat 3 (partner of 1) hand `{7H, 9D}`.

**Trace 7H:**
- Line 137: HOKM, leadSuit == trump → enter.
- Line 138: CurrentTrickWinner: JH rk 8 → bestSeat=1.
- Line 139: Partner(3)=1 → match → return true.

**Verdict: OK.** Partner-winning shortcut fires. 7H legal even though
it's a "wasted" trump under partner's JH. (Strategy doc: would prefer
seat 3 to throw a non-trump if possible to save trump for later, but
seat 3 has 9D — a non-trump — so they CAN play 9D… wait,  no, they
can't because line 129 requires they follow if they have the lead suit.
Seat 3 has 7H = lead suit = H, so must follow with 7H or any other H.)

Subtle: 9D path:
- Line 129: cardSuit("D") != leadSuit("H") → return false, "must follow suit".

So 7H is forced. **Correct.**

---

## Scenario 19 (Subtle) — `R.IsLegalPlay` partner-winning shortcut requires `seat` to be non-nil; what if seat is nil (caller bug)?

**Setup:** Same as Scenario 2 but caller passes `seat = nil`.

- Line 139: `curWinner and seat and R.Partner(seat) == curWinner` → seat is nil → short-circuits to false. Shortcut never fires.

**Verdict: OK.** Defensive coding: nil seat does not crash. The
`seat and …` guard at line 139 (and at line 167) prevents `R.Partner(nil)`
from being called. `R.Partner(nil)` would itself return nil (no branch
matches in `Rules.lua:16-21`), and `nil == curWinner` would be false
unless curWinner also nil — but then the upper guard would short-circuit.

**FLAG NIT:** If a caller fails to pass `seat`, the function silently
applies maximum-strict semantics (no partner-winning relief, no
AKA-relief gate). This is "fail-safe" behaviour — better to over-restrict
than under-restrict. But callers who forget `seat` get silent
mis-evaluation rather than a crash. Already a soft latent bug; not
critical.

---

## Scenario 20 (Bug probe) — Receiver has lead-suit AND partner-just-trump-ruffed; relief vs must-follow priority

**Setup:** Trump = H. Trick: `{1=AS, 2=8H}` (partner led S, opp ruffed
with 8H). Seat 3 (partner of 1) hand = `{KS, 7H}`. Receiver has S.
AKA = `{seat=1, suit="S"}`.

**Trace 7H:**
- Line 116-121: akaRelief = true.
- Line 124-127: hasLead = true (KS).
- Line 129: cardSuit("H") != leadSuit("S") → return false, "must follow suit".

**Trace KS:**
- Line 124-127: hasLead = true.
- Line 129: cardSuit == leadSuit → pass.
- Line 137: leadSuit(S) != trump(H) → skip overcut block.
- Line 159: return true.

**Verdict: OK.** AKA-relief does NOT lift must-follow. Receiver must
follow with KS even though banner is up. This is correct (Saudi:
AKA only relieves must-trump-ruff, not must-follow-suit) and matches
B-Rules-01 F3 (comment-correctness issue, not a code bug).

---

## Summary table

| # | Scenario | Outcome | Severity |
|---|----------|---------|----------|
| 1 | Trump-led, partner just trumped | Must overcut | OK |
| 2 | Partner trump-led, partner winning | No overcut required | OK |
| 3 | Off-trump lead, partner ruffed, has lead suit | Must follow first | OK |
| 4 | Multi-trump, highest rank wins | Highest trump-rank wins | OK |
| 5 | canOvercut precondition: lead must be trump | Skipped on non-trump lead | OK (NIT: dual-block duplication) |
| 6 | 9 vs A in Hokm | 9 (rk 7) > A (rk 6) → must overcut A with 9 | OK |
| 7 | AKA relief overrides partner-not-winning | Discard freely | OK |
| 8 | KH/8H/AH trick, seat 4 has 9H | 9H legal (overcut) | OK |
| 9 | AKA-relief + partner winning interaction | Both gates correct, line 167 takes precedence | OK |
| 10 | Stale-suit AKA banner | Filtered by suit==leadSuit gate | OK (F4 NIT remains) |
| 11 | Lead trump, partner winning, must follow | Partner-shortcut + must-follow both fire | OK |
| 12 | Off-suit lead, multi-trump, no overcut | Forced under-trump | OK |
| 13 | Trump-led, opp follows, no overcut | Any trump OK | OK |
| 14 | Corrupt leadSuit nil curWinner | Defensively nil-safe | OK |
| 15 | Partner over-trumped, void receiver, no overcut needed | Discard freely | OK |
| 16 | Sun: no over-trump | Pass through | OK |
| 17 | Trump in hand but lead suit also held: cannot voluntarily ruff | Must follow | OK |
| 18 | Forced partner-following with low trump | OK | OK |
| 19 | Caller forgets seat arg | Fails-safe to strict | OK (NIT: silent over-restriction) |
| 20 | AKA + receiver has lead-suit | Must-follow takes precedence | OK |

---

## Bugs / divergences found

**No new bugs.** R.IsLegalPlay correctly enforces:
1. Must-follow-suit (highest precedence)
2. Within trump-led-must-follow: partner-winning shortcut → over-trump
3. Within void: partner-winning shortcut → AKA-relief → must-trump → over-trump

The two-level over-trump enforcement (line 137-158 follow-suit-trump-led
vs. line 187-208 void-and-ruffing) is duplicated logic but not buggy.

**Confirmed already-known issues (not new):**
- B-Rules-01 F1: BotMaster.PickPlay:830 omits akaCalled (HIGH).
- B-Rules-01 F2: HostValidatePlay/GetLegalPlays omit akaCalled (MEDIUM).
- B-Rules-01 F3: Comment at Rules.lua:113-114 misleading.
- B-Rules-01 F4: No `akaCalled.suit ~= contract.trump` defensive guard.
  This RT-29 confirms F4 is even softer than B-Rules-01 suggested:
  on trump-led tricks the akaRelief gate isn't consulted (line 175 only
  fires from the void path), so a stale-trump-suit banner doesn't
  manifest. F4 still good hygiene but less urgent.
- B-Rules-01 F5: Test gap for AKA + lead==trump combinations.

**Specific trace verification (prompt's Scenario 8):**
Trick `{1=KH, 2=8H, 3=AH}`, trump=H, seat 4 with 9H — code returns
**true** for 9H (legal, the only legal play). Any other trump
(7H, 8H if held) returns false with "must overcut". The "must overcut"
rule correctly forces seat 4 to play 9H. The wording "verify code
returns 'must overcut' forcing 9H" is satisfied: the rule forces 9H
by rejecting alternatives.

---

## Confidence

HIGH on all 20 scenario traces. Each was walked through with cited
file:line references against `Rules.lua` r-state at lines 89-210
(R.IsLegalPlay) and 34-59 (R.CurrentTrickWinner). Constants verified
at `Constants.lua:50-51`. Cards.TrickRank verified at `Cards.lua:107-114`.

No exploitable misbehaviour was uncovered in over-trump or relief
logic itself. The previously-flagged risks (B-Rules-01) are real but
each is bounded by an upstream layer: either State.lua's M3 wipe,
the suit==leadSuit gate, or the precedence ordering of the 3-tier
relief stack (must-follow > partner-winning > AKA-relief > must-trump).
