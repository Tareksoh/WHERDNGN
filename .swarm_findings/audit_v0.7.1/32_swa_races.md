# 32 — SWA Permission-Flow Race Audit (Net.lua, v0.7.2 HEAD)

**Verdict:** Most races handled defensively, but **3 real bugs** (1 medium, 2 low). Disconnect cleanup absent; a pause-during-fire window exists; bot-SWA path lacks pause re-arm.

## 1. PAUSE arrives mid-window, AFTER `C_Timer.After` fires but BEFORE `HostResolveSWA` completes
**Race exists but benign.** `_OnSWAReq` timer (2571–2607) checks `S.s.paused` near the *top*, not atomically wrapped around the resolve. If `paused` flips to true between line 2598 (`req` fetch) and 2606 (`HostResolveSWA`), resolution proceeds during a paused state. `HostResolveSWA` itself has no `S.s.paused` guard (2740–2742 only checks isHost/contract/phase). Outcome: SWA scoring happens during pause, then `MSG_PAUSE` arrives at clients with phase already SCORE — clients ignore the pause but the round is decided. **Low severity** (Lua is single-threaded; `MSG_PAUSE` cannot interleave inside the timer callback). The pause-resume re-arm (2569–2596) is correct because `paused` is checked synchronously.

## 2. TAKWEESH counter while SWA timer pending
**Handled correctly.** `HostResolveTakweesh` line 2050 explicitly nils `S.s.swaRequest`. The pending 5-sec timer's caller-match guard (`req.caller ~= seat`) at 2599 makes it a no-op. Phase moves to SCORE so even the late-firing timer's `phase ~= PHASE_PLAY` check (2600) catches it. **Note:** `HostResolveTakweesh` does not call `CancelTurnTimer`-style cancellation of the SWA timer itself — relies on guards. Acceptable but two checks deep.

## 3. Two opponents send accept simultaneously
**Handled.** `req.responses[responder] ~= nil` idempotence guard at 2624. Both writes succeed; the second invocation increments `accepts` and triggers resolve. Lua is single-threaded so genuine simultaneity reduces to message-queue ordering. No double-resolve risk because `S.s.swaRequest = nil` (2682) precedes `HostResolveSWA`; even a 3rd late accept hits the `not req` early-return at 2621.

## 4. Caller LEAVES mid-window — timer cleanup
**Bug — no cleanup path.** Grep shows no leave/disconnect handler in Net.lua (only line 2046 mentions "leaves stale" in a comment). If the caller disconnects, the host's pinned `mySeat`/`pinnedHand` closure (2418–2452) still fires at T+5s, decoding a hand for an absent seat. `HostResolveSWA` proceeds against `hostHands[callerSeat]` (still authoritative on host), validates, and resolves. **Functionally correct but eerie**: a disconnected caller still wins/loses. No real corruption — host's hostHands is the snapshot, not driven by client liveness. **Low severity.**

## 5. /reload mid-SWA
**Persistence intentional.** State.lua 225–230 documents `swaRequest` is NOT in TRANSIENT_KEYS — survives /reload. **However:** the *timers* (LocalSWA's `C_Timer.After` and `_OnSWAReq`'s) are NOT persisted; on host /reload they vanish. Restored `swaRequest` becomes immortal until: (a) an opponent presses Accept/Deny/Takweesh, (b) phase changes, or (c) `ApplyStart` clears it. **Medium severity** — host /reload during a pure-bot SWA window with bots already auto-accepted leaves the request alive forever (vote count is 2 but `accepts >= 2` only checks on a fresh `_OnSWAResp`, never re-evaluated on restore). Bot game with host reload mid-SWA = soft-lock.

## 6. Bot SWA path race (3853–3911)
**Bug — no pause re-arm.** Unlike `_OnSWAReq` (2571) and `LocalSWA` (2424), the bot-initiated SWA timer at 3896 has only `if S.s.paused then return end` (3898) — pause causes the timer to silently drop the resolve, with **no re-arm on resume**. `LocalPause`'s resume branch (2287–2326) does not pump pending SWA timers. Bot SWA called → host pauses → host resumes → bot's SWA hangs forever (until phase change). **Medium severity** (bot SWA is rare; typically ≤3 cards left).

**Most critical (top 3):** (1) Bot-SWA timer drops on pause without re-arm, (2) Host /reload mid-SWA loses timer leaving `swaRequest` immortal, (3) No disconnect cleanup for departing caller (cosmetic only).
