# D-RT-23 — Multi-Qaid / Concurrent Takweesh Race Audit

**Track:** D — Red-team
**Targets:** `Net.LocalTakweesh`, `Net._OnTakweesh`, `Net._OnTakweeshOut`,
`Net.HostResolveTakweesh`, `State.ApplyPlay`, `State.ApplyRoundEnd`
**Files:** `Net.lua` lines 2071–2339, `State.lua` lines 1197–1298, 1463–1466
**Status:** v0.10.2 HEAD

## Threat model

Takweesh (Qaid) is a one-shot, host-resolved early-termination call. It
relies on:

1. **Host serialization** — only the host runs `HostResolveTakweesh`; all
   non-host calls travel via `MSG_TAKWEESH` and are processed in
   wire-arrival order on the host's main thread.
2. **Phase guard** — every entry point has `if S.s.phase ~= K.PHASE_PLAY
   then return`. `S.ApplyRoundEnd` (called inside `HostResolveTakweesh`)
   sets `s.phase = K.PHASE_SCORE` (State.lua:1466) **before** any
   subsequent broadcast or re-entry path can fire.
3. **Single-pass `.illegal` marking** — the offender mark is stamped at
   `S.ApplyPlay` time (State.lua:1212–1265) and is permanent on the
   trick record.

Concurrency-relevant code:

```lua
-- Net.lua:2071-2076
function N.LocalTakweesh()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not S.s.localSeat or not S.s.contract then return end
    broadcast(("%s;%d"):format(K.MSG_TAKWEESH, S.s.localSeat))
    if S.s.isHost then N.HostResolveTakweesh(S.s.localSeat) end
end
```

```lua
-- Net.lua:2079-2089
function N._OnTakweesh(sender, callerSeat)
    if fromSelf(sender) then return end
    if not callerSeat then return end
    if S.s.phase ~= K.PHASE_PLAY then return end
    if not authorizeSeat(callerSeat, sender) then return end
    if S.s.isHost then N.HostResolveTakweesh(callerSeat) end
end
```

The phase check at line 2083 is the single load-bearing guard for every
race scenario below.

---

## Scenario 1 — Two opps simultaneously call Takweesh on the same play

**Repro:** Seat 1 plays an illegal card. Seats 2 and 4 (opps of seat 1)
both press the Takweesh button within ~50ms of each other on different
clients.

**Wire trace (host-perspective):**

1. Seat 2 client: `broadcast(MSG_TAKWEESH;2)` → addon-msg queue.
2. Seat 4 client: `broadcast(MSG_TAKWEESH;4)` → addon-msg queue.
3. Host's `_OnTakweesh` fires for whichever frame arrives first (arbitrary
   server ordering). Say seat 2 wins.
4. Host enters `HostResolveTakweesh(2)`: scans tricks, finds offender,
   applies score, calls `S.ApplyRoundEnd` which sets `s.phase =
   K.PHASE_SCORE` (State.lua:1466).
5. Host then `broadcast(MSG_TAKWEESH_OUT;2;1;1;...)` (Net.lua:2317).
6. Seat 4's frame arrives. `_OnTakweesh` runs on host. Phase check at
   Net.lua:2083 fires: `S.s.phase ~= K.PHASE_PLAY` → return. **Drop.**

**Feasibility: SAFE.** First-call wins by wire-arrival order; the second
caller gets no banner (their `_OnTakweeshOut` mirror only fires on
non-hosts who receive the broadcast — they receive seat 2's outcome,
not their own). Idempotent.

**Tie-breaker fairness:** RTT-dependent. The seat with shorter latency to
the host wins credit for the catch. This is **Saudi-rule-neutral** —
both opps are on the same team (R.TeamOf(2) == R.TeamOf(4)), so the
team scoring outcome is identical regardless of who "called". The only
visible asymmetry is the `caller` field in the result struct (used for
the banner name), and the dropped caller's UI shows the winner's name.

**However:** if seats 2 and 4 are on DIFFERENT teams (impossible in
2v2 partner-axis layout — Saudi rule mandates partners face across, so
opps of seat 1 are exactly the seats on the OTHER team), this would
matter. **Not feasible** in the current 4-seat partner layout.

**Recommendation: NO ACTION.** First-call wins is the correct semantic;
the phase-guard idempotence is sufficient. **One nit:** consider
broadcasting `MSG_TAKWEESH_OUT` with the original caller's seat so the
losing caller's banner doesn't briefly show "no result yet" — currently
the loser's banner just goes straight to seat 2's result via the
mirror at Net.lua:2109–2116, which is correct anyway.

---

## Scenario 2 — Player commits ANOTHER illegal play during Takweesh resolution

**Repro:** Seat 1 plays illegal card A. Seat 2 calls Takweesh. Mid-host-
resolution, seat 3 (a bot or fast human) tries to play illegal card B.

**Wire trace:**

1. Host enters `HostResolveTakweesh(2)`. Synchronous Lua call.
2. **No yield point exists in `HostResolveTakweesh`** — it scans tricks,
   computes scores, calls `S.ApplyRoundEnd` (which sets phase to SCORE
   immediately), `S.s.trick = nil` (Net.lua:2274), then broadcasts.
3. WoW's addon-message dispatch is **single-threaded on the main
   thread** — no `MSG_PLAY` can interleave with `HostResolveTakweesh`'s
   execution body.
4. After `HostResolveTakweesh` returns, any queued `MSG_PLAY` from seat
   3 hits `_OnPlay` (Net.lua:1375) → phase check at line 1379 (`if S.s.phase
   ~= K.PHASE_PLAY then return`) → drop.

**Feasibility: SAFE.** Lua coroutine semantics + WoW's single-threaded
event dispatch make this a non-race in practice. The phase transition
inside `HostResolveTakweesh` is atomic from the wire's perspective.

**Edge case: bot-driven.** `MaybeRunBot` (Net.lua:3984+) is gated by
`if not S.s.isHost then return end` and `if S.s.phase ~= K.PHASE_PLAY
then return` (line 3996). Re-entry from a stale `C_Timer.After` callback
is correctly guarded.

**Recommendation: NO ACTION.** The synchronous-resolution invariant
holds.

---

## Scenario 3 — Player calls Takweesh on a LATER play before earlier resolution finishes

**Repro:** Seat 1 plays illegal in trick 3. Before anyone catches it,
the round continues to trick 5 where seat 3 plays another illegal. Now
both opps press Takweesh nearly simultaneously.

**Wire trace:**

This degenerates into Scenario 1 with the additional twist that the
scan loop (Net.lua:2150–2159) walks `S.s.tricks` in order:

```lua
local foundIllegal
for _, t in ipairs(S.s.tricks) do
    foundIllegal = scanIllegal(t.plays)
    if foundIllegal then break end
end
```

The **first** illegal play encountered wins. So even though the caller
intended to nail the trick-5 violation, the scan returns the trick-3
illegal (whichever was earlier). The caller's caught-card banner will
show the trick-3 card, not the trick-5 one.

**Feasibility: COSMETIC ISSUE ONLY.** The penalty is correctly applied
and the offending team correctly loses — but the banner attributes the
catch to the wrong card/seat if both teams have illegal plays in
different tricks.

**Wait — re-reading:** the scan is filtered by `R.TeamOf(p.seat) ~=
callerTeam` (Net.lua:2152). So the caller's own team's illegals are
ignored. Only opp-team illegals are reportable. This means:

- If seat 1 (team A) is illegal in trick 3, seat 3 (team B) is illegal
  in trick 5, and seat 2 (team A) calls Takweesh: scan finds seat 3's
  trick-5 violation (the only opp-team illegal). Correct.
- If seat 3 (team B) is illegal in trick 3, seat 1 (team A) is illegal
  in trick 5, and seat 2 (team A) calls Takweesh: scan finds seat 3's
  trick-3 violation. Correct.
- **Cosmetic mismatch case:** if the caller pressed the button
  intending to catch a SPECIFIC card but an earlier same-team-of-
  offender illegal exists, the first-found wins. Not a correctness bug.

**Recommendation: NO ACTION.** The scan order is deterministic and
correct under the per-team filter.

---

## Scenario 4 — Cross-Takweesh: A Takweeshes B, B counter-Takweeshes A

This is the headline race. Phase1-H referenced "wrong Qaid REVERSES
against caller" — i.e. an unsuccessful Takweesh costs the caller's team.
Two players on opposite teams pressing Takweesh simultaneously creates
a coupled outcome.

**Repro:** Seat 1 (team A) plays a legal card that team B claims is
illegal. Seat 2 (team B) calls Takweesh on it. *Before* seat 2's frame
reaches the host, seat 1 (team A) suspects seat 2's partner of a prior
violation and counter-calls Takweesh.

**Wire trace:**

1. Seat 2 client: `broadcast(MSG_TAKWEESH;2)`.
2. Seat 1 client: `broadcast(MSG_TAKWEESH;1)`.
3. Host receives in arbitrary order. Say seat 2 first.
4. `HostResolveTakweesh(2)` runs. Scans for opp-team illegals (team A
   plays). Finds none (seat 1's play was legal). `foundIllegal = nil`.
   Branch at Net.lua:2175: `winnerTeam = oppTeam` (i.e. team A wins —
   the **wrong-Qaid reversal**). `addB = 0; addA = 26 (Sun) or 16
   (Hokm)`. Phase → SCORE. Round terminates.
5. Seat 1's frame arrives: `_OnTakweesh` → phase check fires → drop.

**Outcome:** Seat 2's wrong Qaid awards the round to team A. Seat 1's
intended Takweesh (which would have caught a real seat-3 illegal) is
**silently dropped**.

**This is a REAL exploit surface.** Consider:

- Team A plays an illegal card.
- Team B presses Takweesh — but team B's frame is delayed (lag, party-
  channel contention).
- Team A's player, **noticing they made an illegal play**, presses
  their OWN Takweesh first as a deflection. Their wrong-Qaid
  REVERSES against them — but their team would have lost anyway from
  the legitimate B-call, so the punishment is the same.
- **However:** if team A's Takweesh is well-timed AND finds an
  unrelated team-B illegal earlier in the round, team A wins on the
  first-call-wins rule, and team B's legitimate Takweesh never runs.

**Concrete attack:**

1. Bidder (team A) makes an illegal play in trick 5.
2. Defender (team B) presses Takweesh.
3. Team A's partner (seat 3) — knowing team A also has an unflagged
   illegal earlier (e.g. team B's seat 4 played an off-suit when they
   had the lead suit in trick 2, both team A and the host missed it,
   but team A's bot/script DID notice it) — presses Takweesh.
4. Whichever frame arrives first wins. If seat 3 wins, team B's seat-4
   trick-2 violation is caught, team A scores 26/16, team B's
   legitimate Takweesh never runs. **Team A escapes their own
   illegal play AND scores.**

**Feasibility: HIGH.** Wire arrival order is RTT-dependent and not
controllable by the player, but a determined adversary on a low-
latency connection vs. a high-latency one has a real advantage.

**Severity: MEDIUM.** Requires the attacking team to actually have a
caught-able opp violation — which limits the exploit to cases where
both teams have illegal plays AND the attacker spots the opponent's
violation faster than the opponent spots the attacker's. Not a free
exploit.

**Mitigation options:**

- **(a) Reject Takweesh after own illegal flagged.** If
  `s.tricks[*].plays[*].illegal == true` for `R.TeamOf(callerSeat)`,
  refuse the call. Saudi rule: a team cannot Qaid-call while they
  themselves have an outstanding illegal. **Risk:** silent rejection
  is confusing; needs a chat message. Also: who decides the order in
  which illegals were committed? If seat 1's illegal was trick 5 but
  seat 4's was trick 2, seat 1 should still get to call.
- **(b) Resolve all queued Takweesh frames in a single batch.**
  Buffer for ~200ms, then pick the winner deterministically (e.g.
  caller with the earliest-found valid catch wins; otherwise
  first-arrived). Adds latency to the legitimate case.
- **(c) Document as known race.** First-call-wins is consistent with
  Saudi tournament practice: the first player to physically slap the
  table claiming Qaid wins. RTT-driven outcomes mirror reaction-time
  outcomes in physical play.

**Recommendation: (c) DOCUMENT.** Saudi tournament play already has
this race in physical form; the network version preserves the same
semantics. Add a comment near `LocalTakweesh` explaining that
RTT-determined first-call-wins is intentional. **Do NOT** add option
(a) without a Saudi-rule citation that supports it — would be a
divergence from the table-game model.

---

## Scenario 5 — Race during HostResolveTakweesh — MSG_PLAY arrives during resolution

Already covered in Scenario 2: **NO race possible** due to single-
threaded WoW main-thread event dispatch. `HostResolveTakweesh` is a
synchronous Lua function with no yield points (no `coroutine.yield`,
no `C_Timer.After` callbacks that re-enter state). The phase
transition at `S.ApplyRoundEnd` (State.lua:1466) is atomic from the
wire's perspective.

**Recommendation: NO ACTION.**

---

## Scenario 6 — Concurrent illegal plays — two seats both illegal

**Repro:** Seat 1 (team A) plays illegal. Seat 3 (team B) plays illegal
in a later trick. Now seat 2 (team B) calls Takweesh.

**Wire trace:**

`HostResolveTakweesh(2)` scans for `team A` illegals (opp team of
caller). Finds seat 1's. **Seat 3's own-team illegal is invisible to
the scan** (filtered by Net.lua:2152: `R.TeamOf(p.seat) ~= callerTeam`).

Score: team B (caller's) wins, team A (offender's) loses melds (M1
arbitration: offender team forfeits melds, Net.lua:2216–2218).

**Feasibility: NORMAL.** Working as designed.

**Subtle case:** what if seat 4 (team B) ALSO calls Takweesh after
seat 2? Phase guard at Net.lua:2083 drops it. **Idempotent.**

**Edge case: false-AKA chain.** If seat 1 announces AKA on hearts then
plays a non-boss heart (Net.lua state at State.lua:1238–1265, illegal
mark with `illegalReason = "false AKA"`), AND `s.akaCalled` is cleared
by the marking (State.lua:1257), then if seat 1 also plays an off-suit
on a later trick, the off-suit play is no longer aka-relevant (akaCalled
nil) but COULD be flagged illegal for follow-suit violation. Both
illegals stamp on `s.tricks[*].plays[*]`. The Takweesh scan returns
the FIRST one (false AKA), and the `illegalReason` field correctly
identifies it.

**Recommendation: NO ACTION.**

---

## Scenario 7 — Takweesh during Qaid window — second illegal act

If seat 1 plays illegal A in trick 3, and seat 2 plays illegal B in
trick 5 (same-team illegals from team A's perspective if seat 1 and
seat 2 are partners, but seat 1+2 are OPPONENTS in 2v2 — actually seat
1+3 are partners, seat 2+4 are partners). Re-framing:

- Seat 1 (team A) plays illegal A in trick 3.
- Seat 3 (team A — partner) plays illegal B in trick 5.
- Seat 2 (team B) calls Takweesh.

The scan walks `s.tricks` in order, finds seat 1's trick-3 illegal
first (Net.lua:2152: `R.TeamOf(p.seat) ~= callerTeam` matches, since
team A is opp to team B). `foundIllegal = trick3.plays[seat=1]`.
Banner: caller=2, offender=1, card=A. Penalty: 26/16 to team B.

**Seat 3's trick-5 illegal is never reported.** This is correct: only
ONE penalty per round. The earlier offense wins (sticky).

**Feasibility: NORMAL.** Matches Saudi rule (one Qaid per round; the
catch ends the round).

**Recommendation: NO ACTION.**

---

## Scenario 8 — Per-trick vs per-round Takweesh state clearing

Where is `s.takweeshResult` set/cleared?

- **Set:** Net.lua:2109 (mirror on receivers), Net.lua:2276/2285 (host).
- **Cleared:**
  - `S.Reset()` at State.lua:114 — full game reset.
  - `S.ApplyStart` at State.lua:806 — at the next round's start.
  - Snapshot replay path at State.lua:526.

**No per-trick clear.** This is correct: `takweeshResult` is a round-
end banner, set once at end-of-round. It survives the entire SCORE
phase and clears at the next ApplyStart.

**However:** the Takweesh path goes through `S.ApplyRoundEnd` (sets
phase to SCORE) but **does not clear `s.akaCalled`, `s.swaResult`,
`s.swaRequest`** (only `s.swaRequest` is cleared in
`HostResolveTakweesh` at Net.lua:2144). Cross-check:

- `s.akaCalled` — cleared by `S.ApplyStart` at State.lua:805
  ("takweesh / SWA banners cleared at next round"). Good.
- `s.swaResult` — cleared by `S.ApplyStart`. Good.
- `s.lastRoundResult` — explicitly cleared in `HostResolveTakweesh`
  at Net.lua:2273. Good.

**Subtle issue:** if a Takweesh fires DURING an active SWA permission
window (the 5-second auto-approve C_Timer.After at Net.lua:4040+),
the Takweesh path nils `swaRequest` but the deferred timer body at
Net.lua:4059+ still fires after the round has ended. Need to check
that timer's phase guard.

Looking at MaybeRunBot's SWA guard (Net.lua:4006: `if S.s.swaRequest
and S.s.swaRequest.caller then return`) and the SWA resolution path
(typically in `HostResolveSWA` which I haven't read here), there's a
phase-check pattern throughout. The C_Timer.After bodies in
`MaybeRunBot` (Net.lua:3987+) all start with `if S.s.phase ~=
K.PHASE_PLAY then return end` checks.

**Feasibility:** likely SAFE based on the consistent pattern, but
warrants a dedicated audit (D-RT-13 already covers SWA permission
race; the cross-check with Takweesh is captured here).

**Recommendation:** verify all `C_Timer.After` callbacks that touch
`swaRequest` post-Takweesh have a phase-check guard. **Already
captured** in D-RT-13_swa_permission_race.md per the directory listing.

---

## Scenario 9 — Forge attack — wrong Takweesh accusation

**Repro:** Attacker (any seat) sends a malformed `MSG_TAKWEESH`
naming a different seat:

```
broadcast("MSG_TAKWEESH;3")  -- attacker is seat 1, claims seat 3 called
```

**Wire trace:**

1. Host receives at `_OnTakweesh(sender=attacker, callerSeat=3)`.
2. Authority check at Net.lua:2087: `if not authorizeSeat(3, sender)
   then return end`.
3. `authorizeSeat` (Net.lua:661) checks: is seat 3 a bot? (host signs
   for bots only). Is seat 3 human? (then sender must equal seat 3's
   stored name). Attacker's name ≠ seat 3's name → **REJECT.**

**Feasibility: BLOCKED.** Authority gate is correct.

**Edge case: attacker IS the host.** A malicious host can call
`HostResolveTakweesh(any seat)` directly and broadcast
`MSG_TAKWEESH_OUT` with arbitrary fields. **Out of scope** —
host-trust is the project's threat model (per CLAUDE.md and D-RT-08
trust-asymmetry-audit).

**Edge case: replay attack.** Sniffing a previous `MSG_TAKWEESH;3`
frame and re-broadcasting it. Authority gate still rejects — the
sender field is set by WoW's chat layer per-message and not under
attacker control via `SendAddonMessage`. Cross-realm mismatches are
handled by `normSender`. **BLOCKED.**

**Recommendation: NO ACTION.** Authority gating is sufficient.

---

## Scenario 10 — Wire timing — host order globally consistent?

WoW's `C_ChatInfo.SendAddonMessage` to the `PARTY` channel is delivered
in-order to each receiver, but **not** in a globally-synchronized order
across senders. Two non-host senders can have their messages observed
in different relative orders by different receivers.

**However:** Takweesh resolution is HOST-AUTHORITATIVE. Only the host's
view of the order matters for the score outcome. Receivers see:

1. Their own outgoing `MSG_TAKWEESH` (filtered by `fromSelf`).
2. Other peers' `MSG_TAKWEESH` (no-op on non-hosts — Net.lua:2088 only
   triggers HostResolveTakweesh `if S.s.isHost`).
3. Host's authoritative `MSG_TAKWEESH_OUT` and `MSG_ROUND` broadcasts.

**Receiver consistency:** every receiver's `s.takweeshResult` is set
from `_OnTakweeshOut` (Net.lua:2109–2123), which is gated by
`fromHost(sender)` (Net.lua:2093). So all non-hosts see the same
outcome the host computed — no divergence possible.

**Host's own view:** host's `_OnTakweesh` is called only for OTHER
peers (its own `LocalTakweesh` short-circuits at Net.lua:2076,
calling `HostResolveTakweesh` directly without going through the
wire). So host order = host's processing order = canonical order.

**Feasibility: GLOBALLY CONSISTENT.** No divergence risk.

**Recommendation: NO ACTION.**

---

## Summary table

| # | Scenario | Feasibility | Severity | Recommendation |
|---|---|---|---|---|
| 1 | Two opps simultaneous Takweesh, same play | First-call-wins, RTT-tied | None | No action — idempotent |
| 2 | Illegal play during resolution | Not possible (sync Lua) | None | No action |
| 3 | Takweesh on later play before earlier resolves | Cosmetic only | None | No action — scan order is correct |
| 4 | Cross-Takweesh A↔B | **HIGH** if both teams have illegals | MEDIUM | **Document** as RTT-determined first-call-wins (matches Saudi physical-table semantics) |
| 5 | MSG_PLAY during HostResolveTakweesh | Not possible (sync Lua) | None | No action |
| 6 | Two seats both illegal, same team | Normal flow | None | No action |
| 7 | Takweesh during Qaid window (second illegal) | Normal — sticky to first illegal | None | No action |
| 8 | Per-trick vs per-round state clearing | Per-round semantic correct | None | Verify SWA timer cross-cut (D-RT-13) |
| 9 | Forge attack | Blocked by authorizeSeat | None | No action |
| 10 | Wire timing global consistency | Host-authoritative; consistent | None | No action |

---

## Findings

**Zero correctness bugs found.** The Takweesh path is well-protected by:

- Phase-guard idempotence at `_OnTakweesh` (Net.lua:2083) and
  `HostResolveTakweesh` (Net.lua:2129).
- Atomic phase transition via `S.ApplyRoundEnd` (State.lua:1466) in a
  synchronous Lua call with no yield points.
- Host-authoritative resolution (no non-host computes Takweesh
  outcomes).
- `authorizeSeat` blocking forged calls.
- Single-threaded WoW main-thread dispatch eliminating MSG_PLAY ↔
  Takweesh interleaving.

**One documentation gap (Scenario 4):** the cross-Takweesh race where
team A and team B both press Takweesh — first-call-wins by RTT — is a
real exploit surface for a determined opponent on a low-latency link,
but matches Saudi physical-table convention (first to slap wins). The
penalty/reversal rules in `HostResolveTakweesh` (Net.lua:2174–2218)
correctly handle the wrong-Qaid case by awarding handTotal to the opp
team. **Recommend** adding a comment near `LocalTakweesh` documenting
this as intentional.

**One cross-cut concern (Scenario 8):** Takweesh-during-SWA timer
cleanup. Already captured in `D-RT-13_swa_permission_race.md` per the
file inventory. No new finding — referencing for completeness.

**Constants worth noting:**

- `K.HAND_TOTAL_SUN = 130`, `K.HAND_TOTAL_HOKM = 16` (per audit
  v0.9.0/04). Penalty awards correctly multiply by `mult` derived from
  contract escalation chain (Net.lua:2185–2190).
- Offender team meld forfeit (M1 arbitration v0.10.1) is correctly
  applied at Net.lua:2216–2218 (zero offender melds, keep winner's
  own).
- Belote (rb3haa) +20 raw is independent and applies regardless of
  Qaid winner (Net.lua:2224–2251, K.MELD_BELOTE).

---

## Audit confidence

- **Code-coverage:** read all of `LocalTakweesh`, `_OnTakweesh`,
  `_OnTakweeshOut`, `HostResolveTakweesh` (Net.lua:2071–2339); read
  `S.ApplyPlay` illegal-marking (State.lua:1192–1298); read
  `S.ApplyRoundEnd` and reset/start flows (State.lua:100–126,
  510–540, 805–807, 1463–1500); read dispatch tag-decode and
  authority helpers (Net.lua:560–678, 1375–1472).
- **Cross-references:** `audit_v0.9.0/28_rules_aka_swa_takweesh.md`
  (NOT `30_qaid_vs_kasho.md` — that file is at
  `docs/strategy/_transcripts/30_qaid_vs_kasho_extracted.md`),
  `D-RT-13_swa_permission_race.md`, `D-RT-16_version_skew.md` (cites
  M4 client mismatch as cause of wrong-Qaid penalties under
  cross-version play — separate concern).
- **Not audited here:** Bot-driven Takweesh decision logic
  (`B.Bot.PickTakweesh` at Net.lua:4011) — that's a strategy-tier
  concern, not a race concern.
