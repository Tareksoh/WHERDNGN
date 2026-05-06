# B-Bot-05: Tahreeb signal recorder + classifier (post-v0.10.2 M7)

## Scope verified

- **Recorder (Tahreeb section):** `Bot.lua:564-623`. Discard-while-
  partner-winning detection unchanged from v0.9.x. New M7 hook at
  `Bot.lua:606-618` captures `list.lenAtAce` for the FIRST signal
  in a suit when it is an Ace AND `S.s.isHost` AND
  `S.s.hostHands[seat]` exists.
- **Classifier:** `tahreebClassify` at `Bot.lua:1638-1701`. New
  `signals.lenAtAce >= 5` short-circuit at `Bot.lua:1664-1666`
  promoting straight to `"bargiya"`. Existing `>=2 events +
  cover-grade` gate kept as fallback (`1667-1681`).
- **Receiver scoring (partner side):** `Bot.lua:1860-1893` (note:
  prompt's "1660-1710" range refers to pre-v0.10.0 line numbers;
  actual span is now 1840-1929). Weights:
  `bargiya=3, want=2, bargiya_hint=1`.
- **Receiver scoring (opp avoid):** `Bot.lua:1894-1922`. Marks
  `bargiya | want | bargiya_hint` for opp-avoid (the v0.9.3 #58
  fix is preserved).
- **Round reset:** `Bot.lua:157-172` rebuilds
  `tahreebSent = { S={}, H={}, D={}, C={} }` per-round. The
  `lenAtAce` field disappears with the round — no cross-round
  bleed.
- **Test pin:** `tests/test_state_bot.lua:1798-1825` exercises
  both the M7 promotion path (`{ "A", lenAtAce = 5 }` → bargiya
  beats H-want=2) and the no-`lenAtAce` fallback (single A →
  bargiya_hint loses to H-want).

## Findings

### F1. Cross-client divergence in `lenAtAce` capture — accepted, with caveat

The capture is correctly gated `S.s.isHost and S.s.hostHands and
S.s.hostHands[seat]` (`Bot.lua:607`). On non-host clients
`hostHands` is `nil` (`State.lua:49`), so they record the rank
list without `lenAtAce`. Their `tahreebClassify` then falls
through the cover-grade path; a single-event A signal returns
`bargiya_hint` instead of `bargiya`.

**Why this is fine in normal operation:** Bot decision dispatch is
host-gated (`Net.lua:3552-3553` — `MaybeRunBot` returns on
non-host). Bot.PickPlay therefore runs only on host, where
`lenAtAce` is present. Non-host classification mismatch is inert.

**Latent risk (medium-low):**
1. **Host migration not implemented today.** `s.isHost = true` is
   only set at lobby creation (`State.lua:612`); no mid-game
   handoff exists. If host-migration is ever added, the new host's
   `tahreebSent` will lack `lenAtAce` for any prior-trick Bargiya
   signal, silently demoting genuine invitations to `_hint`. The
   cover-grade fallback at `Bot.lua:1667-1681` will fire only if a
   second event has been recorded — by post-migration trick this
   may not be true.
2. **Non-host BotMaster simulators.** BotMaster does not directly
   read `tahreebSent` (verified — no hits for `tahreebSent` in
   `BotMaster.lua`), so the simulator/rollout path is unaffected.
   Confidence-confirmed: not a regression vector.
3. **The 50-agent playtest replay guard** (`Net.lua:1455-1463`)
   already skips `OnPlayObserved` on replay frames during resync,
   so a rejoiner won't spuriously re-fire the recorder. Good.

**Verdict on F1:** Correct as designed for the single-host model.
The asymmetry should be documented if host-migration is ever
contemplated.

### F2. Threshold `lenAtAce >= 5` matches source

The threshold corresponds to "محشور بلون واحد" (cornered in one
suit). Source check:

- **Source video #14 @ 00:11:48-00:11:54** (verbatim per
  `n1FBrNNVUAA_14_bargiya_ace_tahreeb.ar-orig.srt:2541-2573`):
  *"محشور بلون واحد او بلونين ومنه مثلا مردوفه بشيء صغير"* —
  no numeric threshold given inline.
- **Source B Rule 9** (`source_B_bargiya_discover.md:90-93`):
  exemplifies "5 cards or more in one suit."
- **Source B Rule 4**: early-game = each player ≥5 cards (a
  different threshold — total hand size, not length-in-suit).
- **R4 reaudit recommendation** (`reaudit_R4_bargiya_tahreeb.md:
  304-322`): "`signals[1].lenAtPlay >= 4` (sender محشور in this
  color at signal time — they retained 4+ side cards in the suit
  **after** dropping their Ace)."

The recorder stores `preLen + 1` (`Bot.lua:617`) — i.e. the
**pre-discard** length-in-suit including the Ace. R4's
recommendation uses **post-discard residual length**. So:

| Interpretation | M7 stored value | M7 gate (`>=5`) means | R4 recommendation (`>=4` residual) means |
|---|---|---|---|
| Pre-discard (incl. Ace) | `lenAtAce` | sender held 5+ in suit incl. Ace = 4+ side cards after | sender held 5+ in suit incl. Ace = 4+ side cards after |

The two interpretations produce **the same predicate**: M7's
`lenAtAce >= 5 (pre)` is mathematically equivalent to R4's
`lenAtPlay >= 4 (post)`. The numeric value matches the canonical
source rule. **Verdict on F2: correct threshold, correct
arithmetic.**

(There is also a self-consistency check between the inline comment
"sender held 5+ in this suit AT THE MOMENT of the Ace discard"
[`Bot.lua:1654-1655`] and the actual stored value: the comment
describes pre-discard semantics, which matches `preLen + 1`.
Documentation and code agree.)

### F3. Backward-compat with raw rank-string entries — handled

Pre-M7 fixtures and (potential) saved replays may have
`tahreebSent[suit] = { "A" }` with no `lenAtAce` field. The
classifier handles this safely:

```lua
if (signals.lenAtAce or 0) >= 5 then
```

The `or 0` defaults to zero, the `>= 5` test fails, control falls
through to the cover-grade path. Single-A signals classify as
`bargiya_hint`, identical to v0.9.x. The test at
`tests/test_state_bot.lua:1822-1825` explicitly pins this
fallback. **Verdict on F3: backward-compatible. No fixture or
saved-state migration required.**

### F4. `bargiya_hint` weight = 1 with no محشور proxy — correct under M7

The receiver weight ordering at `Bot.lua:1879-1882` is
`bargiya=3 > want=2 > bargiya_hint=1`. Pre-M7, this ordering was
itself the source of FN: a true 5+-card invite (محشور) classified
as `bargiya_hint` (1) was beaten by an unrelated 2-event "want"
(2) in another suit.

Post-M7 the FN is closed at the **classifier**, not the weight
table — genuine محشور signals are routed to `bargiya` (3), and
the residual `bargiya_hint` cases are exactly what they should
be: end-game stranded-Ace defensive sheds (Source B Rule 3) or
non-host clients (F1). For these, weight 1 — i.e. *consider but
let other signals dominate* — is the safe conservative default.
**Verdict on F4: correct.**

### F5. Two-event escalation under M7 — still correct

The cover-grade path (`Bot.lua:1667-1681`, requires 2nd event
≥ rank-T) is preserved as a parallel route to `bargiya`. Cases
where it still wins:

- Non-host clients (F1) where `lenAtAce` is missing but a 2nd
  event has accumulated.
- A genuine 4-card-in-suit invite (محشور threshold not met)
  followed by a true cover-grade discard. Source B Rule 9 frames
  the threshold as "1 OR 2 colors" with examples of "5+", but
  4-card-in-suit + early-trick + receiver-تك could still be a
  legitimate invite. The 2nd-event cover-grade path catches these.

There is one subtle interaction: if `lenAtAce >= 5` AND a 2nd
A-suit discard with `r2 >= T` arrive, the M7 short-circuit fires
first (line 1664) and the cover-grade check at 1667 is dead-code
for that case. Functionally fine — both paths return `"bargiya"`.

**Verdict on F5: still correct, no regressions.**

### F6. Asymmetric opp-avoid (Bot.lua:1894-1922) — correct

The opp-avoid set marks `bargiya | want | bargiya_hint` (the
v0.9.3 #58 fix). M7 changes the partner-side score ordering but
does NOT change opp-avoid set membership. The asymmetry (mark
even `bargiya_hint` from opps; do not mark `bargiya_hint` from
partner via the `score > bestScore` gate) is intentional —
defensive denial is conservative, partner pref is selective.

**M7-specific check:** post-M7 the canonical 5+ signal classifies
as `bargiya` on host. On non-host (which doesn't dispatch bots
anyway), it'd classify as `bargiya_hint` — but the opp-avoid set
already includes `bargiya_hint`, so the defensive read is robust.
**Verdict on F6: correct under M7.**

### F7. Phase-conditional SWA prior (Source B Rules 6/7) — NOT wired

Source B Rules 6 and 7 distinguish:
- **End-game Bargiya** (each player ≤4 cards) → strong SWA prior
  for partner; receiver should dash.
- **Early-game Bargiya** (each player ≥5 cards) → partner may
  have just a single long suit; receiver should eat 1-2 first.

The current classifier returns the same `"bargiya"` token for
both phases. The receiver-side `pickLead` at `Bot.lua:1930-1944`
reads `tahreebPrefSuit` and returns the lowest card in that suit
unconditionally, with no game-phase or each-player-card-count
gate. Source B Rule 17 numeric thresholds (eat ≤1/≤2/≤3 by
partner-hand-size 5/6/7) are not represented anywhere reachable
from this code path.

**Verdict on F7: known gap, out of scope for M7.** M7's design
explicitly closes the *classification axis* FN (محشور invitation
demoted to hint); the *phase-conditional SWA prior* is a
separate, downstream-of-classification question. Source B Rule 9
is the M7 axis fix; Rules 6/7/17 are receiver-action refinements
not addressed in v0.10.2. Recommend a follow-up issue
**B-Bot-XX_phase_conditional_bargiya** for the receiver-action
side.

### F8. Sender awareness (Source B Rule 5) — single source of truth

Source B Rule 5: "sender ledger doesn't re-fire on receiver
pass." Verified: the recorder fires only at `OnPlayObserved`
(`Net.lua:1462`, `Net.lua:2053`, `Net.lua:3447`), driven by
ApplyPlay events, not by receiver re-classification. There is no
separate sender-ledger that could re-fire when the receiver
changes its read. The ledger is pure event-stream-append. M7
adds one more field (`lenAtAce`) at append-time but does not
change the append semantics. **Verdict on F8: correct.**

### F9. Per-trick dynamic inference (Source B Rules 36/42) — partial

Source B Rule 36 ("recompute hypotheses every trick") and Rule 42
("paired flip-and-update on Tahreeb/Tanfeer reclassification")
require receiver-side re-evaluation when later events arrive.
Current behavior:

- `pickLead` calls `tahreebClassify` *afresh* on every PickPlay
  invocation (`Bot.lua:1872`, `Bot.lua:1913`). So the classifier
  output IS recomputed per-decision — **good**.
- The `signals` array grows monotonically as `OnPlayObserved`
  appends. Hint→bargiya promotion happens automatically when the
  cover-grade gate fires on event #2 (or earlier under M7 if
  `lenAtAce` was set on event #1).
- **The hint→bargiya promotion does NOT depend on per-trick
  re-evaluation** because each PickPlay re-classifies from
  scratch. There is no cached `cls` field that could go stale.

**Latent gap (Rule 42 prior-flip):** when a partner play is
INITIALLY recorded as a Tanfeer-only event but later evidence
flips the interpretation to Tahreeb, no separate Tahreeb event is
appended. The recorder is hard-wired to "discard while partner
winning" → Tahreeb; otherwise → not Tahreeb. The cross-direction
case (Source B Rule 35: same physical card = Tahreeb to receiver
+ Tanfeer to opponent simultaneously) is not split into two
ledger entries.

**Verdict on F9: M7 is consistent with per-trick recompute.
Rule 42 cross-direction is out of M7 scope — flag for downstream.
Not a regression.**

### F10. Edge case — ApplyPlay timing relative to OnPlayObserved

`S.ApplyPlay` (`State.lua:1293-1297`) removes the played card
from `hostHands[seat]` before returning. `OnPlayObserved` is then
called from `Net.lua:1462` AFTER `ApplyPlay`. The recorder
correctly accounts for this with `preLen + 1` (`Bot.lua:617`)
to recover the pre-discard length. Verified via line trace.

One self-check: if the played card is somehow NOT in
`hostHands[seat]` at ApplyPlay time (e.g., desync), the
`table.remove` is a no-op (`State.lua:1294-1296` guards with
`if c == card`). In that case `preLen + 1` would be 1 too high
(post-remove length didn't actually decrement). This is a
pre-existing State invariant; not an M7-introduced fault.
**Verdict on F10: correct under invariant; no new fault.**

## Cross-checks against other reports

- **`reaudit_R4_bargiya_tahreeb.md` recommendation 1** (recorder
  schema change to `{rank, lenAtPlay, trickNum}`): M7 took the
  *minimal* form — only `lenAtAce` added, only on first-Ace, kept
  ranks as strings. R4's full schema (with `trickNum` for
  game-phase) is NOT implemented. The phase-conditional axis
  (F7) is therefore not actionable from the current ledger.
- **`reaudit_R4_bargiya_tahreeb.md` recommendation 2**
  (classifier promotion paths): M7 implemented the
  `lenAtPlay >= 4`-equivalent path (`lenAtAce >= 5` pre-discard).
  The trick-3 boundary path (`trickNum <= 3 AND ≤2 distinct
  suits visible`) is NOT implemented — would require trickNum
  capture in the ledger.
- **`reaudit_R4_bargiya_tahreeb.md` test pin**: the recommended
  fixture matrix (lines 351-356 of R4) is partially implemented
  in `tests/test_state_bot.lua:1798-1825`. The negative-case
  defensive-shed test (`{rank="A", lenAtPlay=2, trickNum=7}` →
  bargiya_hint) is NOT separately pinned; current code would
  classify it as `bargiya_hint` because `lenAtAce<5` and there's
  no second event, but no test enforces that.

## Verdict

**M7 close: CORRECT.**

The محشور 5+-card axis is the canonical Source B Rule 9 axis.
The implementation:
1. Captures pre-discard length-in-suit at the moment of the
   first-Ace signal — host-side only (only client where
   `hostHands` is non-nil), gated by `#list == 0` so it can't
   accidentally overwrite.
2. Compares the captured length to 5 — equivalent to R4's
   recommended ≥4-residual threshold; matches Source B Rule 9's
   "5+ in one suit" example.
3. Promotes to `"bargiya"` (score 3) immediately, beating any
   2-event "want" (score 2) in another suit.
4. Falls back to the existing cover-grade gate when `lenAtAce`
   is absent (non-host, legacy fixtures, or signals starting
   with non-A), preserving v0.9.x behavior.
5. `bargiya_hint` weight = 1 is now correctly reserved for
   genuine ambiguous cases (end-game stranded Ace, non-host
   clients), where weight 1 is the conservative-correct
   defensive read.
6. The opp-avoid asymmetry (v0.9.3 #58) is unchanged and still
   correct — `bargiya_hint` from opps is treated as avoid (since
   defensive denial is conservative).

**Known gaps not addressed by M7 (out of scope, recommend
follow-up):**

- **F7 phase-conditional SWA prior**: receiver-action timing
  (eat ≤1/≤2/≤3 by partner hand size, dash-immediately
  end-game) is not wired. Source B Rules 6/7/17.
- **F9 Rule 42 cross-direction**: partner's discard-on-opp-trick
  is not dual-classified.
- **F1 host-migration**: not currently a deployed scenario but a
  latent risk if added; new host's pre-migration `lenAtAce` data
  is lost.
- **Trick-number capture**: R4's recommended `trickNum` field
  was not added; blocks future phase-conditional refinements
  (F7).

## Confidence

**HIGH** on M7 close correctness.

- The threshold arithmetic verified two independent ways (M7 stored
  pre-discard length + ≥5 gate = R4 recommended post-discard
  length + ≥4 gate). The `preLen + 1` adjustment correctly
  matches `ApplyPlay`-then-`OnPlayObserved` ordering.
- Backward-compat verified by reading the `or 0` default and
  checking the test fixture at `tests/test_state_bot.lua:1822-1825`.
- Cross-client semantics verified: bot dispatch is host-gated, so
  non-host divergence is inert in normal operation.
- The opp-avoid set still includes `bargiya_hint` (v0.9.3 #58
  preserved), so non-host clients defending against opp signals
  remain robust even without `lenAtAce`.
- Source video #14 @ 00:11:48-00:11:54 SRT verbatim matches the
  محشور axis rationale; no numeric threshold inline at that
  passage but Source B Rule 9 distillation supports 5+.

**MEDIUM** on assessment of the gaps (F7, F9, F1).

- F7 (phase-conditional) is documented in source but the
  receiver-side action thresholds are numeric (eat-count by
  partner-hand-size) and would need their own dedicated work.
  M7's choice to defer is reasonable.
- F1 host-migration is hypothetical — current code has no
  migration path and the failure mode is conservative
  (silently demote to `_hint`, which means weight 1 instead of
  3, which means partner pref is *under*-emphasized rather than
  spuriously fired).
- F9 Rule 42 needs a recorder schema change (dual-event split or
  reclassification flag) which the user-flagged minimum-change
  M7 explicitly avoided.
