# B-Bot-03: pickFollow AKA-receiver branch (post-v0.10.2 M4 LIVE)

## Scope verified

- AKA-receiver branch in `pickFollow`: `Bot.lua:2493-2558` (comment
  block 2493-2545, executable gate 2546-2558).
- The branch is now LIVE per v0.10.2 M4 — `R.IsLegalPlay`
  (`Rules.lua:89-210`) was patched to accept an optional 6th arg
  `akaCalled = {seat, suit}` and exempt the AKA-receiver from
  must-trump-ruff (`Rules.lua:115-121` compute, line 175 apply).
- `legalPlaysFor` (`Bot.lua:1600-1614`) passes live `S.s.akaCalled`
  through, so the canonical `void+has-trump+AKA-active` case now
  has non-trump cards in `legal`, so the `discards` filter has live
  content and the branch fires meaningfully.
- Pre-v0.10.2 verdict from `xref_X2_aka.md` B1 / `36_video18_aka.md`
  was "structurally dead". v0.10.2 changelog claim that the branch
  is now LIVE is structurally correct.

## Findings

### F1 [SEVERITY: low / cosmetic]: implicit-AKA branch comment is technically right but easy to misread

- **Where:** `Bot.lua:2540-2545` — the comment claims "Implicit-AKA
  case (bare-Ace lead) doesn't reach the legality layer because
  the relief there hinges on `S.s.akaCalled` (only set on explicit
  MSG_AKA). The implicit branch here still fires only when the
  seat has lead-suit cards (partner-winning shortcut keeps
  legality permissive)".
- **Issue:** the parenthetical "still fires only when the seat has
  lead-suit cards" is misleading. The actual fall-through path for
  implicit-AKA + void-in-led + has-trump is:
  - `Rules.lua:166-169` partner-winning shortcut FIRES (because
    `R.CurrentTrickWinner` returns partner — partner led the bare
    Ace and is currently winning). So `legal` for the implicit-AKA
    receiver DOES include non-trump discards even without the M4
    `akaCalled` param.
  - Pre-v0.10.2 this was already true: the partner-winning shortcut
    in `R.IsLegalPlay` (lines 166-169) has always permitted any
    card when partner is winning. The implicit-AKA branch was NOT
    dead pre-v0.10.2; only the EXPLICIT branch was dead.
- **Impact:** none on behaviour — the executable code is correct.
  The cosmetic risk is that a future reader trusting the comment
  might assume "void implicit-AKA receiver gets non-trump cards in
  legal because of the partner-winning shortcut" carries through to
  EXPLICIT AKA after an opp over-ruffs. It does not — explicit AKA
  is the only path that survives an opp over-trump (M4 relief), and
  even that only if `partnerWinning` is checked at the heuristic
  layer (which line 2547 does, suppressing the branch entirely).
- **Confidence:** high.

### F2 [SEVERITY: medium]: AKA-on-T trick lock (J-067 part 1) still NOT implemented

- **Where:** `Rules.lua:34-59` — `R.CurrentTrickWinner`. No
  reference to `s.akaCalled` or AKA-as-substitute-for-Ace.
- **Issue:** Per `xref_X2_aka.md` B5, J-067 has TWO parts:
  - Part 1: AKA on T substitutes T for the Ace, so the trick is
    "locked" — partner takes regardless of who plays higher.
  - Part 2: receiver is exempt from must-trump-ruff.
- v0.10.2 closed Part 2 (the relief in `R.IsLegalPlay`). Part 1 is
  STILL NOT implemented — `R.CurrentTrickWinner` resolves trick
  winner purely by trump-rank/lead-suit-rank with NO consultation
  of `s.akaCalled`. An opp can still over-trump partner's AKA'd T
  and take the trick legally — the bot's response (M4 relief)
  prevents it from being COMPELLED to ruff in that scenario, but
  doesn't prevent the trick from being taken by the opp.
- The M4 changelog comment at `Rules.lua:108-110` claims "the
  10-substitutes-for-Ace semantic (J-067 part 1) collapses to the
  same rule — whichever AKA card is in play, partner's team treats
  the trick as locked." This is **incorrect** as a Saudi-rule
  reading. Source #18 (txt lines 26-44) explicitly distinguishes:
  - "اذا تلعبت الاكه خلاص" (once the Ace has been played, the T
    becomes the next-boss). The T is then SAID-AKA-ON, and per the
    Saudi convention partner's team treats it as the boss for the
    purpose of the rest-of-suit discipline.
  - The "trick lock" semantics — meaning the OPPONENTS are barred
    from over-trumping a properly-AKA'd lead — is asserted in
    Source J's J-067 but the v0.10.2 implementation only honors it
    on the receiver's side, not the opponents' side.
- **Impact:** moderate. The visible bot misbehaviour is rare
  (depends on opp tier — only opp bots that would otherwise be
  forced to over-trump a partner's AKA'd 10 by their must-trump
  rule). If `R.IsLegalPlay`'s opp-side path also exempted them
  from must-trump-ruff under partner's AKA, the bug would be tighter.
  But the canonical Saudi rule is closer to "AKA at the table is a
  *partnership* convention; opps can still legally cut" — so v0.10.2
  is functionally correct under the **convention** reading and only
  drops the rarer **trick-lock** reading. Recommend documenting the
  reading-choice in `Rules.lua:108-110` instead of claiming the
  semantics "collapse to the same rule".
- **Confidence:** high on the implementation gap; medium on the
  rule-interpretation question (J-067 wording is genuinely
  ambiguous between "convention" and "lock").

### F3 [SEVERITY: low]: receiver-side has no doubled-contract / late-game / risk-tolerance gating

- **Where:** `Bot.lua:2546-2558` — the `if Bot.IsAdvanced() and
  contract.type == K.BID_HOKM and contract.trump and trick.leadSuit
  and partnerWinning and (explicitAKA or implicitAKA) then` gate.
- **Issue:** Source #18 G18-10 (txt lines 156-162) describes
  risk-tolerance for the AKA *sender* — "بدايه الجيم لسه عوافي او
  انتم مره فوق والخصم تحت وطبعا اللعب طبيعي مش دبل" (early game
  comfortable, you're way ahead, opp far behind, AND of course
  regular play not doubled). v0.10.2 L3 wired the
  doubled-contract guard on the SENDER (`Bot.lua:3332`).
- The RECEIVER side here does NOT inspect `S.s.contract.doubled`
  or `trickNum`. Is this a gap?
  - **Argument for symmetric guard:** if the sender suppresses AKA
    in doubled hands, then any AKA banner that DOES arrive in a
    doubled hand is suspect (came from a non-bot or an older bot
    or a buggy peer). The receiver could prudently ruff anyway.
  - **Argument against:** false-AKA detection (M3) is the
    correct place to flag a suspect AKA, not the receiver. Once
    `S.ApplyPlay` validates and clears `s.akaCalled` on detection,
    the receiver simply won't see `explicitAKA = true`. The M3
    layer renders a receiver-side guard redundant.
- **Verdict:** the asymmetry is defensible. M3 false-AKA detection
  is the host-side validation; the receiver trusts the (cleared
  or not) banner. No bug; just an asymmetry worth documenting.
  Adding a receiver-side `S.s.contract.doubled` guard would
  actively hurt — a legitimate doubled-hand AKA from a human
  partner who hasn't read the L3 convention would be ignored,
  costing the trick.
- **Confidence:** medium. Worth noting in design doc but not a
  defect to fix.

### F4 [SEVERITY: low]: pos-3 vs pos-4 AKA-receiver behaviour identical — no source-derived differentiation

- **Where:** `Bot.lua:2546-2558` — the gate references neither
  `pos` nor `lastSeat`.
- **Source #18 review:** the txt says "خويك في هذه الحاله مش مجبر
  يدق بالحكم" (your partner is not obliged to ruff in this case)
  in both pos-3 (txt ~lines 70-80) and pos-4 contexts. The video
  does NOT describe a position-aware variant of receiver behavior
  — both seats simply discard low when partner is the AKA caller
  and is currently winning.
- **Verdict:** no differentiation in source = no differentiation
  in code is correct. No defect.
- **Confidence:** high.

### F5 [SEVERITY: low]: discard selection is `lowestByRank` of all non-trump — does NOT preserve highest non-trump for future suit-Ace contention

- **Where:** `Bot.lua:2549-2557` — `discards = {legal non-trump}`,
  return `lowestByRank(discards, contract)`.
- **Issue:** Source #18 (txt lines 47-48) says "اي ورقه بعدها تكون
  كبيره تعرفها بالاكه" — "any card you flag with AKA is the boss
  of its suit" (i.e. the AKA-receiver should be DUMPING low cards).
  The receiver's job is to dump a "useless" card per Source #18
  and `signals.md` Section 4. `lowestByRank(discards)` picks the
  lowest TRICK-RANK non-trump, which is a 7 if available.
- **However:** this picks the lowest by trick-rank, not face-value.
  The trick-rank ordering for non-trump in Hokm is `7,8,9,J,Q,K,T,A`
  — so 7 is lowest, T is high (rank 6 in non-trump-Hokm), A is
  highest. That is correct for Hokm semantics — a 7 is genuinely
  the most dispensable non-trump card.
- **Refinement opportunity:** there's a sub-case where the
  receiver should preserve a high non-trump in a suit they're
  *long in* (Tahreeb invitation) and dump from a singleton OTHER
  non-trump suit. e.g. if seat 4 holds `{7H, A♠, K♣, Q♣, J♣}` with
  trump = D, partner AKAs on H, current discards = {7H, A♠, K♣, Q♣,
  J♣}. `lowestByRank` returns 7H. But 7H IS the lead suit (seat
  was not void; the branch wouldn't fire) — so this case doesn't
  arise.
- The branch only fires when `legal` already has non-trump cards.
  In the canonical case (void in led suit + has trump + AKA),
  `legal` post-M4 is `{trumps, all non-trump}` from `IsLegalPlay`.
  `discards` filters trumps out. `lowestByRank` over the remainder
  picks the lowest-by-trick-rank — which is what Saudi convention
  prescribes: the worst non-trump card.
- **Verdict:** matches Saudi convention. No defect.
- **Confidence:** high.

### F6 [SEVERITY: low]: `S.s.akaCalled` is read once per `pickFollow` call (live state) — M3 false-AKA clearing IS correctly observed

- **Where:** `Bot.lua:2512-2514` — `local explicitAKA = S.s.akaCalled
  and S.s.akaCalled.seat == R.Partner(seat) and S.s.akaCalled.suit ==
  trick.leadSuit`.
- **M3 path:** `S.ApplyPlay` (`State.lua:1238-1264`) clears
  `s.akaCalled = nil` on false-AKA detection BEFORE the play is
  inserted into the trick log. Subsequent `pickFollow` invocations
  on the next seat read fresh state.
- **Verdict:** correct. The receiver's branch evaluates live state
  per call. There is no caching of `explicitAKA` across calls.
- **Confidence:** high.

### F7 [SEVERITY: trivial]: implicit-AKA precondition uses `trick.plays[1]` (lead) — verified all preconditions correct

- **Where:** `Bot.lua:2521-2532`.
- Conditions checked (all required for `implicitAKA = true`):
  1. `not explicitAKA` — explicit takes precedence (correct).
  2. `contract.type == K.BID_HOKM` — Hokm only (matches Source #18
     "اول شرط لازم اللعب يكون حكم").
  3. `contract.trump and trick.leadSuit` — null guards (correct).
  4. `trick.leadSuit ~= contract.trump` — non-trump only (matches
     Source #18 "تقول اكا على الاوراق غير الحكم").
  5. `partnerWinning` — partner is current winner (matches Source
     #18 "كانك قلت عليها اكه" the bare-Ace is implicitly the boss).
  6. `trick.plays and trick.plays[1]` — there's at least a lead.
  7. `lead.seat == R.Partner(seat)` — the LEADER is partner
     (correct, matches Source #18 "خويك يلعب اوراق العشره").
  8. `C.Rank(lead.card) == "A"` — lead was bare Ace.
  9. `C.Suit(lead.card) == trick.leadSuit` — sanity (always true
     in any valid trick).
- **Critical note:** condition 7 anchors on `trick.plays[1]` — the
  *first* play. Per `xref_X2_aka.md` and `36_video18_aka.md`, this
  is correct. A partner who FOLLOWS with an Ace (not LEADS it) is
  NOT signaling implicit AKA — they're constrained by must-follow.
- **Verdict:** all preconditions correct. The pre-v0.10.2 audit
  finding (`50_aka_implicit_overruff.md`) verified the
  `partnerWinning` precondition correctly fails after an opp
  over-trumps partner's bare-Ace lead. Still holds in v0.10.2.
- **Confidence:** high.

### F8 [SEVERITY: low]: `Bot.IsAdvanced()` gate suppresses AKA-relief for Basic-tier bots

- **Where:** `Bot.lua:2546` — `if Bot.IsAdvanced() and ...`.
- **Issue:** Basic tier bots (default — `WHEREDNGNDB.advancedBots`
  unset) bypass this branch entirely. They fall through to default
  pickFollow logic, which (post-v0.10.2 M4) now has non-trump cards
  in `legal` and may pick one anyway — but the branch's specific
  intent (lowest non-trump discard, preserve trump) is bypassed.
- **Impact:** Basic bots play randomly from the legal list. Under
  M4 this set includes non-trump options when AKA is active, so
  the Basic bot will sometimes correctly discard, sometimes
  incorrectly ruff. Only an issue if Basic-tier-bots appearing in
  AKA scenarios is a target use-case (typically not — Basic is for
  testing).
- **Verdict:** consistent with the rest of the file. No defect.
- **Confidence:** high.

### F9 [SEVERITY: low]: `s.akaCalled` from a stale prior trick — verified cleared at `S.ApplyTrickEnd`

- **Where:** `State.lua:1327` — `s.akaCalled = nil` inside
  `S.ApplyTrickEnd`. Called when trick has 4 plays (line 1306).
- **Verdict:** banner is per-trick. Receiver's `explicitAKA` check
  in the next trick correctly evaluates to `false`. No stale-flag
  hazard.
- **Confidence:** high.

## Cross-reference verification

Per task brief:
- **`xref_X2_aka.md` B1** ("AKA receiver-relief is functionally
  dead code") — RESOLVED by v0.10.2 M4. `R.IsLegalPlay` now passes
  AKA through (`Rules.lua:115-121, 175`). `legalPlaysFor` reads
  `S.s.akaCalled` and forwards it (`Bot.lua:1607-1610`). Confirmed
  via test pins `tests/test_rules.lua:1107-1156` (Section Q,
  8 pins, all pass per `python tests/run.py` 360+/360+).
- **`xref_X2_aka.md` B2** ("False AKA = Qaid not implemented") —
  RESOLVED by v0.10.2 M3. `S.ApplyPlay` (`State.lua:1238-1264`)
  validates against `playedCardsThisRound` and marks the play
  `.illegal=true, .illegalReason="false AKA"`, clearing
  `s.akaCalled`.
- **`xref_X2_aka.md` B3** ("Doubled-contract conservatism missing
  in Bot.PickAKA") — RESOLVED by v0.10.2 L3. `Bot.lua:3332` —
  `if S.s.contract and S.s.contract.doubled then return nil end`.
- **`xref_X2_aka.md` B4** (trick-1 skip philosophy) — UNCHANGED in
  v0.10.2. Still cosmetic / philosophical.
- **`xref_X2_aka.md` B5** ("AKA-on-10 trick lock not implemented")
  — STILL NOT IMPLEMENTED. See F2 above. M4 partially addresses
  the cited rule (the receiver-relief side, J-067 part 2) but does
  NOT touch `R.CurrentTrickWinner` (J-067 part 1).
- **`12_touching_honors.md`** — touching-honors WRITE bug (NameError
  on `trick`) is unchanged in v0.10.2; that's a separate issue from
  the AKA-receiver branch and not in scope for B-Bot-03.

## Verdict

**The v0.10.2 M4 claim — "AKA-receiver branch in `Bot.lua` is now
LIVE" — is structurally correct.**

The branch was previously dead in the canonical (void+has-trump)
case because `R.IsLegalPlay` filtered non-trumps out of `legal`
before the discard filter could fire. v0.10.2 patches
`R.IsLegalPlay` to honor AKA (Rules.lua:115-121, 175) and
`legalPlaysFor` to forward live `S.s.akaCalled` (Bot.lua:1607).
The `discards` filter at `Bot.lua:2549-2554` now has live content
for the canonical case, and `lowestByRank` correctly picks the
lowest non-trump (preserving trump for later).

**Remaining gaps (none blocking the M4 claim):**
1. **F2:** AKA-on-T trick lock (J-067 part 1) is still NOT
   implemented in `R.CurrentTrickWinner`. The M4 comment at
   `Rules.lua:108-110` claiming "the 10-substitutes-for-Ace
   semantic collapses to the same rule" is misleading — it
   implements the receiver-relief side only, not the trick-lock
   side. Recommend documenting the reading-choice; rule
   interpretation is genuinely ambiguous, but the comment claim is
   overstated.
2. **F1:** Implicit-AKA branch comment at `Bot.lua:2540-2545` is
   technically right but misleading on the legality fall-through
   reasoning. Cosmetic only.
3. **F3:** No receiver-side doubled/late-game guard. Defensible
   asymmetry — M3 false-AKA detection is the correct host-side
   validation, and adding a receiver-side guard would actively
   hurt legitimate doubled-hand AKAs from human partners.

All 9 findings are LOW or MEDIUM severity; none are blockers and
none invalidate the v0.10.2 M4 claim. The branch behaves correctly
in the canonical case (void + has-trump + explicit AKA on led
suit) and degrades gracefully when partner is over-trumped (gate
on `partnerWinning` short-circuits the branch).

## Confidence

**High confidence** on:
- F1 (cosmetic comment misread of partner-winning fall-through).
- F2 (AKA-on-T trick lock still not implemented — verified by
  absence in `Rules.lua:34-59` and confirmed by absent
  `s.akaCalled` reference).
- F4 (no pos-3/pos-4 differentiation in source).
- F5 (lowestByRank correctly matches Saudi "dump useless" rule).
- F6 (live state per call, M3 clearing observed).
- F7 (all 9 implicit-AKA preconditions correct).
- F8 (IsAdvanced gate consistent with rest of file).
- F9 (stale-flag handling clean).
- Cross-reference items B1-B4 resolved per claims; B5 still open
  per F2.

**Medium confidence** on:
- F2 rule-interpretation question (J-067 wording ambiguous between
  "convention" and "trick-lock" readings; the `Rules.lua:108-110`
  comment's claim "collapses to the same rule" is at minimum
  documentation-wrong, possibly behaviour-wrong depending on which
  Saudi-rule interpretation is canonical).
- F3 doubled-contract asymmetry (defensible but not formally
  documented in code).
