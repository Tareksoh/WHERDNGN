# D-RT-25 — Tahreeb Cross-Round Signal Accumulation (Red-Team)

Track D, v0.10.2 review. Companion to D-RT-12 (bait-ledger persist) and
audit_v0.9.0/46 (bait-ledger exploit). Targets `style.tahreebSent` —
the only Saudi-convention signal store that is **already** correctly
round-scoped per the v0.9.2 #46 fix, but whose lifecycle, persistence
flow, and consumer pipeline still admit several adversarial paths.

**Verdict: tahreebSent is ROUND-SCOPED on the write/storage axis (no
cross-round accumulation in normal play). HOWEVER, three secondary
exposures are confirmed exploitable:** (a) `/reload` mid-round
preserves the partial in-round signal log (correctly), but the
session-restore type guard does NOT validate inner-list contents — a
hand-edited SavedVariables payload can inject ghost signals that
survive into the live round; (b) game-end → game-start has NO
explicit `tahreebSent` wipe — it relies on `ResetStyle` rebuilding the
whole `_partnerStyle` from `emptyStyle()`, and `ResetStyle` only fires
when `roundNum == 1`, which is contingent on caller side advancing the
counter correctly; (c) within a single round, the receiver's
opp-avoid pipeline reads a single-event Bargiya hint with the same
weight as a confirmed multi-event signal, allowing one well-timed
deceptive A-discard to suppress an entire suit's lead-set for the
balance of that round (intra-round, not cross-round, but worth
flagging in the same axis).

The headline cross-round seasoning attack from #46-style does NOT
apply to tahreebSent — the round-scope reset blocks it. But the
lifecycle is more fragile than the file comment suggests, and the
intra-round amplification is the real residual risk.

---

## 1. Lifecycle determination — write site, reset site, persist site

### 1.1 Write site (`Bot.lua:564-621`)

```
if not wasIllegal and leadSuit and cardSuit ~= leadSuit
   and contract and style.tahreebSent then
    ... priorWinner == R.Partner(seat) ...
        list = style.tahreebSent[cardSuit]
        if list then
            ... lenAtAce capture (Ace+lenInSuit, host-only) ...
            list[#list + 1] = C.Rank(card)
        end
end
```

Append-only; one entry per qualifying off-suit discard. No bound on
list length, no de-dup, no decay. Storage is keyed
`style.tahreebSent[cardSuit] = { ranks... }` with optional
`list.lenAtAce` numeric scalar attached as a non-array field on the
table.

### 1.2 Reset site (`Bot.lua:141-173`, the `Bot.ResetMemory` block)

```lua
if Bot._partnerStyle then
    for s = 1, 4 do
        local style = Bot._partnerStyle[s]
        if style then
            if style.tahreebSent then
                style.tahreebSent = { S = {}, H = {}, D = {}, C = {} }
            end
            ...
```

`Bot.ResetMemory()` is called from `Net.HostStartRound()` line 1800
**every** round (including round 1), and from the redeal handler
(`Net.lua:1764`). So the round-scope reset is **unconditional** on
new-round-start. The block resets the `tahreebSent`, `baitedSuit`,
and `topTouchSignal` sub-tables explicitly, leaving the
game-scope counters (bels/triples/fours/gahwas/leadCount/aceLate/...)
intact.

**Critical detail:** the reset replaces the table with
`{ S = {}, H = {}, D = {}, C = {} }`. This **drops** any
`list.lenAtAce` scalar that was attached to the previous round's
sub-list. Correct for round-scope semantics (the lenAtAce was
captured against round-N hand sizes). No bug here.

### 1.3 Persist site (`State.lua:269-276`, `364-366`)

```lua
botModuleState = {
    partnerStyle = B.Bot._partnerStyle,
    memory       = B.Bot._memory,
    r1WasAllPass = B.Bot.r1WasAllPass,
}
```

The entire `_partnerStyle` table — INCLUDING the in-round
`tahreebSent` sub-tables — is bundled into `WHEREDNGNDB.session.bot`
on every state-mutation save. On `RestoreSession()`, the v0.9.2 #54
type-guard checks `type(sess.bot.partnerStyle) == "table"` but does
NOT recursively validate inner contents.

### 1.4 Game-start vs round-start clear

**Round-start clear (every round, including round 1):** via
`Bot.ResetMemory()`, the explicit `tahreebSent =
{ S = {}, ... }` block (`Bot.lua:161-163`).

**Game-start full rebuild:** `ResetStyle()` (`Bot.lua:256-258`)
calls `emptyStyle()` which re-creates `tahreebSent` from scratch
along with all game-scope counters. Fired from
`Net.HostStartRound()` line 1804-1806 ONLY when `roundNum == 1`.

So the game-start path actually does **two** clears in sequence:
`ResetStyle()` rebuilds the entire ledger, then `ResetMemory()` (the
function call earlier on line 1800) re-runs the round-clear logic
which is now harmless because `tahreebSent` was just recreated.
Order: line 1800 (`ResetMemory`), line 1804-1806 (`ResetStyle` if
roundNum==1). On round 1, `ResetMemory` clears `tahreebSent` first
(operating on the OLD `_partnerStyle` if it survived from the
previous game), THEN `ResetStyle` allocates a fresh
`_partnerStyle`. Net effect on round 1: `tahreebSent` is empty.
**Lifecycle determination: round-scoped, with a redundant double-clear
on game-start that is benign.**

---

## 2. Cross-round seasoning attack — DOES NOT APPLY

The v0.9.2 #46 fix correctly closed this axis for both `baitedSuit`
and `tahreebSent`. The round-clear at line 161-163 wipes the entire
per-suit list before the receiver consults it in round N+1. An
adversarial Ace-discard in round 1 cannot survive into round 2's
`tahreebClassify` consumer because:

1. `tahreebSent[cardSuit]` is a fresh `{}` empty list at the start of
   round 2 (`Bot.lua:162`).
2. `tahreebClassify` (`Bot.lua:1638-1701`) bails on `#signals == 0`
   returning `nil`.
3. The receiver (`Bot.lua:1860-1922`) treats `cls == nil` as no
   signal: no pref, no avoid.

**Cross-round seasoning attack feasibility: NIL.** Round-scope is the
canonical fix and it's correctly wired here.

This is the ONLY axis where the file comment ("clear per-round so
signals from a previous round don't leak into receiver inference",
`Bot.lua:243-247`) is actually load-bearing — and it holds.

---

## 3. /reload mid-round persistence — PARTIAL EXPLOIT

### 3.1 Normal /reload behavior (host bot)

When the host /reloads mid-round:

1. `M4` save fires on every state mutation. The most recent save
   contains the live `_partnerStyle` including
   `tahreebSent[suit] = { ranks... }` for the current in-round
   discard log.
2. PLAYER_LOGIN fires `RestoreSession`. Type-guard at
   `State.lua:364-366` validates
   `type(sess.bot.partnerStyle) == "table"` and assigns.
3. The in-round `tahreebSent` log is restored verbatim. Receiver in
   the next decision sees the correct log — this is the INTENDED
   behavior.

This is correct: a /reload mid-round should not amnesia the bot's
in-round signal observations.

### 3.2 Hand-edited SavedVariables — INJECT ATTACK

The v0.9.2 #54 type-guard only validates the **outer** table type,
not the inner suit lists or rank entries. SavedVariables can be
tampered with on the user's local disk:

```
WHEREDNGNDB.session.bot.partnerStyle[1].tahreebSent.S = {"A", "T"}
WHEREDNGNDB.session.bot.partnerStyle[1].tahreebSent.S.lenAtAce = 5
```

Attacker scenario: a user wanting to manipulate their own
saudi-master tier bot (sandbox / training mode) — or a remote
attacker with file-write to `WTF/Account/.../SavedVariables/` —
seeds a confirmed-bargiya signal pre-round-start. On the first
`pickLead` decision after restore:

1. `signals.S = {"A","T"}` and `signals.S.lenAtAce = 5`.
2. `tahreebClassify({"A","T"})` with `lenAtAce = 5`:
   - `signals[1] == "A"` → enter Bargiya branch.
   - `(signals.lenAtAce or 0) >= 5` → return `"bargiya"` (no
     2-event cover-grade gate even consulted).
3. Receiver loop (`Bot.lua:1879-1885`): `score = 3`, sets
   `tahreebPrefSuit = "S"`.
4. Bot leads lowest Spade (`Bot.lua:1930-1944`).

OR, if injected as opp signal (seat 2, opponent of seat 1 host):

1. Same classification chain → `cls == "bargiya"`.
2. Opp-avoid loop (`Bot.lua:1906-1922`): `tahreebAvoidSet["S"] = true`.
3. Bot avoids leading Spades for the rest of the round.

### 3.3 Surviving the round-reset boundary

The injection only survives one round — round-end calls
`Bot.ResetMemory()` on the next `HostStartRound`, wiping
`tahreebSent`. **But the round-1 effect is already done** — the bot
made one or more biased decisions before the wipe. Across many
rounds with re-injection between each round, the attacker can
season every individual round's decisions.

### 3.4 Feasibility rating

**LOW-MEDIUM.** Requires file-write access to local SavedVariables.
Saudi-Baloot is a private addon (no public lobby), and SavedVariables
are owner-controlled. The realistic threat model is:
1. **Self-tampering for testing/debugging** — benign, expected.
2. **Multi-account/shared-PC** — another user on the same Windows
   account writing to WTF before launching WoW.
3. **Malicious third-party tool** — addon manager or "cheat helper"
   that writes to SavedVariables with bot-influencing payloads.

(3) is the realistic attack surface. The tooling exists for other
Lua-driven game state stores.

### 3.5 Recommendation

Add structural validation in `RestoreSession` for the
`tahreebSent` sub-tables:

```lua
-- After type-checking partnerStyle (line 364-366), before assignment:
for s = 1, 4 do
    local seatStyle = sess.bot.partnerStyle[s]
    if type(seatStyle) == "table" and type(seatStyle.tahreebSent) == "table" then
        for _, suit in ipairs({"S","H","D","C"}) do
            local list = seatStyle.tahreebSent[suit]
            if type(list) ~= "table" then
                seatStyle.tahreebSent[suit] = {}
            else
                -- Drop entries that aren't valid rank strings
                local clean = {}
                for _, r in ipairs(list) do
                    if K.RANK_PLAIN and K.RANK_PLAIN[r] then
                        clean[#clean+1] = r
                    end
                end
                -- Cap length: 8 tricks/round × max 4 off-suit discards
                -- per seat = 8 hard upper bound. Anything > 8 is
                -- malformed.
                while #clean > 8 do clean[#clean] = nil end
                -- Validate lenAtAce: integer 0..8 or nil.
                if list.lenAtAce ~= nil
                   and (type(list.lenAtAce) ~= "number"
                        or list.lenAtAce < 0
                        or list.lenAtAce > 8) then
                    list.lenAtAce = nil
                else
                    clean.lenAtAce = list.lenAtAce
                end
                seatStyle.tahreebSent[suit] = clean
            end
        end
    end
end
```

The same pattern applies to `baitedSuit` (numeric, 0..8) and
`topTouchSignal` (per-suit table). This is a defense-in-depth
hardening, not a bug fix per se.

---

## 4. Game-end → game-start ledger reset — WEAK PATH

### 4.1 The "new game" detection

`Bot.ResetStyle()` is called ONLY from `Net.lua:1804-1806`, gated
by `roundNum == 1`. There is no `Bot.OnGameEnd` callback. The
contract:

- Round 1 → `roundNum == 1` → `ResetStyle` fires.
- Round N > 1 → `ResetMemory` only.
- Round 9+ in a 7-round game (impossible? depends on score chain) —
  there's no internal "game ended" event consulted; the host UI
  decides when to start a new game vs continue.

The `S.s.roundNumber` counter is incremented by the host on each
`HostStartRound`. If the host UI decides "this is round 1 of a new
game" but advances `roundNumber` from `S.s.roundNumber + 1` instead
of resetting to 0 first, `roundNum` becomes the OLD-game-N + 1 and
`ResetStyle` does NOT fire.

### 4.2 Where roundNumber resets

Searching for `roundNumber = 0`:

(scan-bound by reading State.lua and Net.lua and finding only
`roundNumber = roundNumber + 1` style increments + the
`if S.s.roundNumber == 0 then dealer = 1` initial-game branch at
`Net.lua:1791-1796`)

The game-end → roundNumber-reset flow is implicit. It depends on:
- `S.Reset()` being called between games, which zeroes
  `roundNumber` along with everything else.
- OR the user explicitly going through "Quit game → New game" UI
  that calls `S.Reset()`.

### 4.3 The exploit window

If a user flow exists where game-end transitions directly to
new-game-start WITHOUT `S.Reset()`, then:

1. `roundNumber` is left at e.g. 7 (last round of previous game).
2. `HostStartRound` increments to 8.
3. `roundNum == 1` check fails — `ResetStyle` does NOT fire.
4. `ResetMemory` still fires (every-round), so `tahreebSent` /
   `baitedSuit` / `topTouchSignal` ARE cleared.
5. But the **game-scope** counters (`bels`, `triples`, `fours`,
   `gahwas`, `gahwaFailed`, `sunFail`, `aceLate`, `leadCount`)
   leak from the previous game.

For `tahreebSent` specifically: **no leak** — the round-clear at
`Bot.lua:161-163` runs every round including the misidentified
"round 8" at game-2-start. The other counters DO leak, which is the
actual concrete bug here, but it's outside this finding's scope (see
also D-RT-12 on `baitedSuit` lifecycle which addressed this from
another angle).

### 4.4 Feasibility for tahreebSent

**NIL for cross-game tahreeb leak**, because the round-reset is
unconditional and runs even in the broken roundNum-not-reset path.

But: if a future change ever moves the `tahreebSent` clear inside
the `roundNum == 1` gate (or piggybacks it on `ResetStyle`),
this exploit unlocks. The current decoupling (round-clear in
`ResetMemory`, game-clear via `emptyStyle()`-rebuild in `ResetStyle`)
is what makes tahreeb safe.

### 4.5 Recommendation

Add a unit test pinning the invariant:

```lua
-- test_bot_signals.lua or test_state_bot.lua addition:
-- "Game-end leak guard: tahreebSent must be empty at the start of
--  any new-game round 1 even if roundNumber was not reset to 0."

Bot.ResetStyle()
Bot._partnerStyle[2].tahreebSent.S = {"A","T"}  -- season
S.s.roundNumber = 7  -- end of previous game
Net.HostStartRound()  -- treats this as roundNumber=8, NOT round 1
-- After: tahreebSent[2].S MUST be empty even though ResetStyle was skipped.
assert(#Bot._partnerStyle[2].tahreebSent.S == 0,
       "round-reset must clear tahreebSent unconditionally")
```

This pins the decoupling so a future cleanup that "consolidates" the
two reset paths can't silently regress this.

---

## 5. Adversarial signal sequence — round-1 misleading round-2

**NOT APPLICABLE** to tahreebSent specifically, because round-2 starts
with empty lists. The round-1 sequence cannot reach the round-2
classifier.

However, the **bidder/escalation game-scope counters** DO leak from
round 1 to later rounds. A round-1 deceptive Bel from an opp seat
stays in `_partnerStyle[opp].bels` for the rest of the game, which
the M3lm tier reads via `styleBelTendency`. That's a separate
finding (out of scope here).

Within a single round, the attack vector is the same as the v0.9.2
#46 root cause but focused on Tahreeb instead of Bait:

1. T1: opp seat 2 wins, opp seat 4 throws an off-suit Ace as
   "tahreeb" (forced by being void).
2. The recorder fires (correctly per spec — partner of seat 4 was
   winning), records `tahreebSent[2].S = {"A"}` with `lenAtAce = N`.
3. Receiver (host bot) in T2's pickLead reads cls = "bargiya"
   or "bargiya_hint" depending on lenAtAce, marks
   `tahreebAvoidSet["S"] = true`.
4. Bot avoids leading Spades for trick 2-8.

This **is** intra-round amplification, but it's the intended
behavior — the receiver is supposed to honor opp signals. The
exploit only works if the attacker can engineer the "I'm void in
the led suit AND my Ace is on top of partner-winning state"
constraint, which is hard to set up deliberately.

**Feasibility rating: LOW.** The forced-discard scenario in the
write site is unavoidable per the rules — Tahreeb-spec says ANY
off-suit discard while partner is winning IS a Tahreeb signal.
There's no way to filter "forced void" from "voluntary signal" at
the write site without the receiver knowing the sender's hand.

Compare to D-RT-12 (`baitedSuit`): same false-positive class, but
`baitedSuit` is multi-round (under the OLD pre-#46 wiring), making
it strictly worse. tahreebSent is only intra-round, so even a
forced-void false positive only contaminates 7 tricks max.

---

## 6. Confidence ramp 90% / 100% across round boundaries

Source-B Rule 1/2: "Bargiya = ~90% confidence, strongest convention
in Baloot." Source-A Rule 7: "Two-event small-to-big = 100%."

**Across-round confidence ramp does NOT exist** in the current
code, because each round starts empty. The classifier output is:

- Round 1 first trick where opp seat throws Ace + lenAtAce=5 →
  `"bargiya"` confidence-3.
- Round 2 first trick: signals.S = {} → `nil` confidence-0.

The receiver does not maintain a cross-round confidence accumulator
for tahreeb. (For game-scope counters like `aceLate` or `leadCount`,
there IS a multi-round accumulation, but those feed sampler
biasing, not signal classification.)

**Cross-round 90%/100% ramp feasibility: NIL.** The round-scope
reset is the load-bearing mechanism preventing this. Removing it
(or accidentally not running it) would unlock this — see § 4.5
test recommendation.

---

## 7. pickLead opp-avoid pipeline reading stale ledger

### 7.1 Stale-within-round window

The receiver runs at the start of every pickLead call
(`Bot.lua:1860-1929`). The opp-avoid loop iterates seats 1-4 and
for each opp reads `_partnerStyle[opp].tahreebSent[suit]`. There's
NO age check or freshness consideration — a tahreeb signal from
trick 1 still influences the receiver at trick 8 of the same round.

This is intra-round persistence (correct per spec — Saudi
convention is "the signal stands for the round") but creates a
window where an opp can deliberately **early-season** the receiver:

- T1 opp throws A♠ tahreeb (lenAtAce=6, confirmed bargiya).
- T2-T8: bot's `tahreebAvoidSet["S"] = true` for the rest of the
  round.

The opp could even be void in spades at T1 entirely by design (e.g.
a 6-card hand including 0 spades) and was forced to off-suit. The
classifier can't distinguish forced from voluntary, and the
v0.10.2 M7 lenAtAce gate (single-A → bargiya when lenAtAce >= 5)
makes this WORSE — it means the host-side recorder confirms a
"strong" bargiya from a single forced Ace play.

### 7.2 lenAtAce computation correctness

Recorder at `Bot.lua:606-617`:

```lua
if C.Rank(card) == "A" and #list == 0
   and S.s.isHost and S.s.hostHands and S.s.hostHands[seat] then
    local preLen = 0
    for _, c in ipairs(S.s.hostHands[seat]) do
        if C.Suit(c) == cardSuit then
            preLen = preLen + 1
        end
    end
    list.lenAtAce = preLen + 1
end
```

`preLen` counts how many cards of `cardSuit` the seat holds AFTER
ApplyPlay removed the played Ace. The `+ 1` adds back the Ace
itself, giving "length-in-suit including the Ace at signal time."
For a forced-void player (no other spades), `preLen = 0`,
`lenAtAce = 1`. The classifier requires `>= 5` to fire the canonical
bargiya path, so a forced single-Ace play does NOT trigger the
canonical bargiya — it falls to the 2-event cover-grade path, which
also won't fire on a single event.

So the M7 lenAtAce path is safe against forced-void senders.
**However**, a seat with e.g. {A♠, 9♠, 8♠, 7♠} (4 cards, lenAtAce=4)
who voluntarily off-suits the A♠ as a defensive shed is mis-classified
as `bargiya_hint` (single A, lenAtAce < 5, no second event). That's
the correct conservative classification — this is fine.

The exploit window is narrow: a seat with ≥5 spades who deliberately
plays the Ace voluntarily as a defensive shed (rather than as an
invitation) would be mis-classified as confirmed `bargiya`. But Saudi
convention says ≥5 cards in suit + voluntary A-discard IS the
canonical invitation, so this is a definitional alignment, not a
bug.

### 7.3 Feasibility rating

**MEDIUM** for intra-round amplification of a single deceptive A
discard. The attack costs the opp one Ace, and gains them one suit
locked-out for 7 tricks. Net positive for opp if Ace was unlikely
to take a trick anyway.

But this is the *intended* behavior of a Tahreeb signal — the
receiver SHOULD avoid leading the opp's invited suit. The only
"exploit" is that humans can play around this in a way that bots
can't (humans use additional context: tempo, prior trumping
patterns, body language). Bot-side, the intra-round avoid is correct
per Saudi-master spec.

### 7.4 Recommendation

Consider attaching a `firedTrickNum` to the signal entry so
late-round opp signals (trick 6+) get weighted lower than early-
round signals. Source-B Rule 3 explicitly distinguishes early-game
(>=5 cards remaining) from end-game (<=4 cards) in Bargiya
invite-vs-shed classification. The current code does not consult
trick number in the receiver.

This is also flagged in the R4 reaudit (`reaudit_R4_bargiya_tahreeb.md`
section 3, items 1+2 of recommended fixes) — capture `trickNum` at
write site, gate at classifier on game-phase. **The reaudit's
recommendation is not yet implemented** and would close this
intra-round amplification window for the late-trick case.

---

## 8. Summary table

| Axis | Lifecycle | Exploit feasibility | Status |
|---|---|---|---|
| 1. Cross-round seasoning (R1 → R2 leak) | Round-scoped via line 161-163 | NIL | CORRECT |
| 2. /reload mid-round restore | Persisted via M4 | LOW (correct behavior) | CORRECT |
| 3. /reload + hand-edit SavedVariables | No inner-list validation | LOW-MEDIUM | DEFENSE-IN-DEPTH GAP |
| 4. Game-end → game-start without S.Reset | ResetMemory always fires | NIL for tahreeb | DECOUPLING-DEPENDENT |
| 5. Adversarial R1 signal misleading R2 | Blocked by round-clear | NIL | CORRECT |
| 6. Cross-round 90/100% confidence ramp | No accumulator | NIL | CORRECT |
| 7. Intra-round opp-avoid amplification | No age/freshness | MEDIUM | RESIDUAL BY DESIGN |

Three of the seven listed risks (1, 5, 6) are blocked specifically
by the v0.9.2 #46 round-scope reset — that fix is doing more work
than its commit message claimed. (4) is blocked by the same
mechanism but only because the reset is decoupled from `ResetStyle`;
a future "consolidation" refactor could regress it.

(2) is correct intended behavior. (3) is a defense-in-depth gap (low
realistic threat). (7) is a known design gap noted in the R4
reaudit, not yet fixed; it's intra-round only and consistent with
Saudi spec.

---

## 9. Recommendations (prioritized)

1. **Pin the lifecycle invariant in tests** (P1 — cheap, high-value).
   Add the test from § 4.5 to `tests/test_state_bot.lua` ensuring
   `tahreebSent` is cleared on round-start regardless of game-end
   state. Prevents a future refactor from accidentally moving the
   reset inside the `roundNum == 1` gate.

2. **Recursive structural validation in RestoreSession** (P2 —
   defense-in-depth). § 3.5 patch. Caps list length, validates rank
   strings, validates lenAtAce range. Same pattern applies to
   `baitedSuit` and `topTouchSignal`.

3. **TrickNum capture at write site** (P3 — closes residual intra-
   round amplification window). Tracked separately under the R4
   reaudit recommended fix #1; should be done together with the
   bargiya hand-shape axis fix.

4. **Document the lifecycle invariant** (P3 — process). The file
   comment at `Bot.lua:243-247` says "reset per round so signals
   from a previous round don't leak into receiver inference," but
   doesn't surface that this is the LOAD-BEARING mechanism for
   blocking three separate exploit classes (cross-round seasoning,
   confidence ramp, R1→R2 misdirection). Strengthen the comment to
   reflect the security-relevance of the round-scope decoupling.

---

## 10. Confidence

**HIGH** on the lifecycle determination (round-scoped, correctly
wired via `ResetMemory` line 161-163, persisted via M4, restored
with outer-table type guard only).

**HIGH** on items 1, 5, 6 being blocked by the round-scope reset.

**MEDIUM** on item 3 feasibility (depends on threat model — file-
write access to local SavedVariables; existing similar threats for
other Lua-driven game state stores make this realistic for
multi-account/shared-PC scenarios).

**MEDIUM** on item 4 — the "game-end without S.Reset" path is
hypothetical; depends on UI flow not audited here. Even if it
exists, tahreebSent specifically does NOT leak because the
round-clear runs unconditionally. The recommendation is purely
preventive.

**HIGH** on item 7 being intentional design (consistent with Saudi-
master spec for intra-round signal honoring), with a known unfixed
late-trick refinement noted in the R4 reaudit.
