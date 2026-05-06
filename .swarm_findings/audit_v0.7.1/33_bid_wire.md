# 33 — Bid-phase wire-protocol audit (HEAD = v0.7.2, Net.lua)

Targets: `MSG_BID` / `MSG_BID_CARD` (`MSG_BIDCARD`) / `MSG_PREEMPT_PASS`
/ `MSG_OVERCALL_*` / `MSG_CONTRACT`, plus `_HostStepBid`,
`S.HostAdvanceBidding`, `S.HostBeginRound2`.

## 1. Round-1 → Round-2 transition (DEAL_PHASE "2")
**Clean.** Host: `S.HostBeginRound2()` clears `s.bids = {}` and sets
`bidRound = 2` (State.lua:1668-1669) BEFORE `N.SendDealPhase("2")`
(Net.lua:1539). Receivers' `_OnDealPhase` mirrors both writes
(Net.lua:761-764). Order is host-broadcasts-DEAL("2") → host-broadcasts
TURN(first,bid). Receivers process `_OnDealPhase` first because
broadcast order is preserved per-channel; on the rare reorder, the
new TURN seat is in `bidRound=2` and `s.bids` is empty either way.
**No reset of `bidCard`** — both phases reuse the same flipped card
(by Saudi rule), so this is correct.

## 2. preemptOnAce → Sun-overcall phase coherence
**Cannot collide by construction.** `_HostStepBid`'s `"contract"`
branch evaluates the pre-empt window FIRST (Net.lua:1470-1510, only
fires for `bidRound==2 + BID_SUN + Ace`); only if pre-empt does NOT
open does `_HostBeginOvercallWindow` run (Net.lua:1520, gated to
`type==BID_HOKM` at line 1114). Sun-overcall is Hokm-only — no overlap
window with the Sun-Ace pre-empt. PHASE transitions: pre-empt ⇒
`PHASE_PREEMPT`; overcall ⇒ `PHASE_OVERCALL` set inside
`S.BeginOvercall`. Each gates its own handler (Net.lua:992, 1065).

## 3. AFK timeout during bid
**Host advances; bot impersonation does not occur.** `StartTurnTimer`
arms only for non-bot seats (per host docstring; Net.lua:148, 3304).
On expiry, `_HostTurnTimeout(seat,"bid")` re-checks turn/dedupe,
calls `S.ApplyBid(seat,PASS)` + `N.SendBid` + `_HostStepBid`
(Net.lua:3239-3243). The auto-PASS originates from the host's
`broadcast`, so `sender == hostName`. **Risk:** receivers' `_OnBid`
calls `authorizeSeat` (Net.lua:819). For a HUMAN seat this returns
false (sender=host, expected=seat owner) — meaning the auto-PASS
**applies on the host but the broadcast is rejected by every other
client**. Other clients then learn the seat passed only via the
subsequent host TURN/CONTRACT broadcasts and never see `s.bids[seat]`
populated until `_OnDealPhase("2")` clears the table anyway. UI bid-
strip on remotes will be missing that PASS entry until the next deal.
Severity: minor cosmetic desync, not state-breaking. **Recommend:**
add a host-replay flag to MSG_BID (parallel to MSG_MELD's replayFlag
pattern at Net.lua:1306) bypassing `authorizeSeat` when host signs
for an AFK'd human.

## 4. /reload mid-bid (WHEREDNGNDB.session)
**Persisted correctly.** `s.bids` is not in `TRANSIENT_FIELDS`
(State.lua:191-248), so `SaveSession` snaps it. `RestoreSession`
defaults it to `{}` only if missing (State.lua:308). `bidCard`,
`bidRound`, `dealer`, `phase`, and `pendingPreemptContract` /
`preemptEligible` are also non-transient (explicit comment at
State.lua:240-247). Cross-character guard on `sess.owner` (line 280)
+ 1-hour TTL (line 274) sound. **Edge:** if non-host /reloads, the
restored `s.isHost = false`-on-resync (line 442) only fires AFTER
MSG_RESYNC_RES; the brief window between `RestoreSession` and
resync arrival, the client trusts its own restored bids. Acceptable —
host's broadcasts overwrite via `_OnBid`/`_OnDealPhase`.

## 5. Concurrent dual-bid (host accept-first / reject-second)
**Defended.** All three layers dedupe on `s.bids[seat] ~= nil`:
`LocalBid` (Net.lua:1737), `_OnBid` (line 817), and `S.ApplyBid` itself
(State.lua:850). Bot dispatch in `MaybeRunBot` re-checks at fire-time
inside the `pcall` (Net.lua:3781). The bid timer is also cancelled in
`_OnBid` (line 821). A human-clicks-just-as-bot-fires race: the
human's `LocalBid` runs first locally → `ApplyBid` writes the seat →
host broadcasts → receivers (including the bot's host-side scheduled
callback) all see the populated entry and skip. **Order matters:**
`LocalBid` calls `ApplyBid` then `SendBid` then `_HostStepBid`
(Net.lua:1740-1742) — apply-then-broadcast is consistent with
`_OnBid`. No double-step.

## 6. Authorization (`authorizeSeat`)
**Sound.** Net.lua:634-651: bot seat ⇒ require `sender == hostName`;
human seat ⇒ require `sender == info.name` (with normalization). A
non-host who sends a forged MSG_BID for a bot seat is rejected
because `nsender ~= hostName`. A host CAN sign for a human seat
(see issue #3 above) — in that case the message is correctly rejected
by other receivers. The single bypass is the explicit replay-flag
pattern in `_OnMeld`/`_OnPlay`/`_OnAKA`, not present in `_OnBid`.

## Summary
No state-corrupting races found. One cosmetic gap: AFK auto-PASS
for a human seat broadcasts a host-signed MSG_BID that other
clients reject via `authorizeSeat`, leaving the bid-strip missing
that entry until R2 clears. Add a replay-flag bypass to MSG_BID for
parity with MSG_MELD.
