# 44 — Multi-bid Frame Ordering (Net.lua + State.lua, HEAD = v0.7.2)

## TL;DR

**Bidding is host-authoritative.** `S.HostAdvanceBidding` (State.lua:1501) is gated by `if not s.isHost then return end`, so non-host clients **never compute their own contract** — they only ingest `MSG_CONTRACT` from the host (Net.lua:825-831 has `fromHost(sender)` check). This eliminates almost every cross-client desync risk in items #1, #4, #5. Items #2 (idempotence) and #3 (AFK pass) have one real defect each.

## Per-question findings

### 1. WoW addon channel ordering (FIFO?)

WoW addon messages over PARTY/RAID are FIFO **per sender** but interleave arbitrarily across senders. Two clients may see Player A's bid before Player B's bid in opposite orders.

**Impact: NONE for contract resolution** — clients don't run `HostAdvanceBidding`. Their `s.bids[seat]` is informational (used for voice cue suppression at State.lua:866-871 and for `PreemptEligibleSeats` at State.lua:1693-1718). On non-host clients these reads happen *after* the contract has already been resolved by host, so ordering across clients of `s.bids[]` doesn't affect outcomes — contract arrives via `MSG_CONTRACT`.

### 2. `s.bids[seat]` write idempotence

Three guard layers — all correct:
- `_OnBid` rejects re-bids: `if S.s.bids and S.s.bids[seat] ~= nil then return` (Net.lua:817)
- `S.ApplyBid` early-returns identical re-applies: `if s.bids[seat] == bid then return end` (State.lua:850) — explicitly so the "بَسْ" voice cue doesn't double-fire.
- `_HostTurnTimeout` re-checks before AFK-passing: `if S.s.bids[seat] ~= nil then return` (Net.lua:3240)

**Verdict: SAFE.** No second-write override possible. Resync flows whisper a snapshot, not MSG_BID replays, so no replay-vs-live race here.

### 3. AFK during bid — host synthesizes pass

**DEFECT** (low-severity UI/state inconsistency, not a desync):

In `_HostTurnTimeout` (Net.lua:3225-3243), host calls `S.ApplyBid(seat, PASS)` then `N.SendBid(seat, PASS)`. The broadcast goes out from the host's character name. On non-host clients, `_OnBid` (Net.lua:809-823) calls `authorizeSeat(seat, sender)` (line 819).

For an AFK **human** seat: `authorizeSeat` (line 634-651) requires `info.name == nsender`. Since sender is the host (not the human seat owner), **the check fails and clients silently drop the synthesized PASS**. Clients' `s.bids[seat]` for that AFK player remains `nil`.

**Mitigating factor:** The very next thing host does is `N._HostStepBid()` which advances or broadcasts `MSG_CONTRACT`. Contract finalization is host-authoritative and accepted by clients via `fromHost`, so the round still resolves identically. The visible artifact: clients never see "بَسْ" voice/UI for the AFK player and `PreemptEligibleSeats` on a non-host won't include the AFK seat in pre-empt rights.

**Recommended fix:** Add a `fromHost(sender)` bypass to `_OnBid` mirroring the pattern in `_OnDouble`/`_OnTriple` flows (which already accept host-relayed bot bids for the same reason — see Net.lua:638-640's `info.isBot` branch). Either teach `authorizeSeat` to accept `fromHost` for any seat during a turn-timeout window, OR have `_HostTurnTimeout` send an explicit replay-flagged MSG_BID frame (mirrors the play-replay convention at Net.lua:1293-1322).

### 4. "First non-pass wins for HOKM" — different first-seen on different clients?

State.lua:1595 (`elseif btype == K.BID_HOKM and not winning then`) and 1615 (round 2 same logic). Decision happens in `HostAdvanceBidding`, **host-only**. Other clients accept the host's `MSG_CONTRACT` verbatim.

**Verdict: NO DESYNC POSSIBLE.** Even if client A receives Hokm-Spades first and client B receives Hokm-Hearts first, neither client decides — both wait for host's `MSG_CONTRACT(bidder, type, trump)` and apply it via `S.ApplyContract` (State.lua:979). The idempotence guard there (lines 988-993) ensures a stray duplicate doesn't reset escalation flags.

### 5. Sun-overcall round 2 — Sun-overcalls-Hokm winner identity

`HostAdvanceBidding` round-2 branch (State.lua:1607-1614) iterates the bid order; first direct Sun bid wins, beating any earlier Hokm. **Host-only.**

The post-Hokm 5s overcall window (Net.lua:1107-1200) is also host-resolved: `_HostResolveOvercall` calls `S.FinalizeOvercall` then broadcasts `MSG_OVERCALL_RESOLVE` AND a fresh `MSG_CONTRACT` (line 1187-1188). Clients receiving `MSG_OVERCALL_RESOLVE` call `S.FinalizeOvercall` locally on their own (possibly out-of-order) decision set — but that result is then overwritten by the trailing `MSG_CONTRACT`.

**Minor concern:** between `_OnOvercallResolve` (Net.lua:1096) and the subsequent `MSG_CONTRACT` arrival, a client briefly holds a contract whose mutation came from THEIR local decision set (which may differ from host's view if `MSG_OVERCALL_DECISION` frames arrived out of order). Window is one frame at most; UI doesn't paint between addon-message dispatch on the same `CHAT_MSG_ADDON` event.

**Verdict: NO PERSISTENT DESYNC.** Authoritative `MSG_CONTRACT` re-broadcast guarantees convergence. Could be tightened by having clients skip the local `FinalizeOvercall` and just clear `s.overcall` (since host's MSG_CONTRACT already conveys the result), but current behavior is correct.

## Summary

| Item | Status |
|------|--------|
| 1. Channel ordering | Safe — host-authoritative |
| 2. Bid idempotence | Safe — three guard layers |
| 3. AFK pass synthesis | **Defect**: client `_OnBid` rejects host-relayed PASS for human seats due to `authorizeSeat` (Net.lua:819). Functional desync masked by host's MSG_CONTRACT broadcast; UI/voice/preempt-eligibility minor inconsistency. |
| 4. First-Hokm tie-break | Safe — clients don't decide |
| 5. Sun-overcall identity | Safe — host re-broadcasts MSG_CONTRACT after FinalizeOvercall |

Single-defect file: **AFK-pass `authorizeSeat` rejection at Net.lua:819** when host synthesizes a pass for an AFK human seat.
