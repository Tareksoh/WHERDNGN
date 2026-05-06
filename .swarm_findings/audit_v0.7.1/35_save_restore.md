# Save/restore round-trip audit — State.lua (HEAD v0.7.2)

## Mechanism
- `S.SaveSession` (L250) — PLAYER_LOGOUT (also fires on /reload). Skips IDLE/LOBBY/GAME_END. Shallow-copies `s` minus `TRANSIENT_FIELDS` (L191). Tags `{ts, owner, state}`.
- `S.RestoreSession` (L271) — PLAYER_LOGIN. TTL 1h (L274). Owner-name guard (L280). Hard-wipes `s` then overlays. v0.2.0 upgrader scrubs `redoubled` / `belrePending` / "redouble" phase. Defaults `hand/bids/tricks/meldsByTeam/meldsDeclared/cumulative/seats`. Rebuilds `playedCardsThisRound` from tricks (L317-327).
- `WHEREDNGN.lua` PLAYER_LOGIN (L137-237) re-arms: SendLobby, MaybeRunBot, StartTurnTimer, StartBelTimer (DOUBLE/TRIPLE/FOUR/GAHWA), `_HostStepPlay` re-fire on stuck 4-play trick, StartLocalWarn (incl. preempt). Cleared on `S.Reset` (L122-125).

## Targeted scenarios

1. **Mid-trick /reload.** `s.trick` (leadSuit, plays) and `s.tricks` are non-transient → restore intact. `s.turn`/`s.turnKind` restored. Host re-arms StartTurnTimer for human turn (WHEREDNGN.lua L164). `localPlayedThisTrick` correctly transient (L205). **OK** — except (gap below) clients learn live state only via resync req that's gated on `IsInGroup()`.

2. **Mid-bid /reload.** `s.bids` persists. **GAP A**: host re-`SendLobby` but **never re-broadcasts MSG_BID for the recorded bids**. Non-host peers who /reloaded depend solely on MSG_RESYNC_RES replay (Net.lua L4xx). If a client /reloaded but `IsInGroup()` is false at the 2s `maybeRequestResync` (PLAYER_ENTERING_WORLD), they sit with their RestoreSession-only view forever — no automatic re-request later.

3. **PHASE_DOUBLE.** `belPending` (L56) is **NOT in TRANSIENT_FIELDS** → restored. Host re-arms StartBelTimer (WHEREDNGN.lua L176-188). **GAP B (minor)**: StartBelTimer arms a fresh full window even if 25s of a 30s window already elapsed pre-/reload — defenders effectively get a longer window than non-reloaders. Acceptable.

4. **Mid-SWA /reload.** `swaRequest` non-transient (comment L225-230). **GAP C (CRITICAL)**: WHEREDNGN.lua L171-189 re-arms **only** Bel/Triple/Four/Gahwa timers. There is **no SWA timer re-arm**. The 5s C_Timer.After at Net.lua L2569 dies with the session and the request hangs forever (or until manual resolution / round end). Host /reload mid-SWA = soft-lock unless an opponent presses Accept/Deny/Takweesh.

5. **Mid-overcall /reload (v0.7.0).** `s.overcall` is **not listed in TRANSIENT_FIELDS** → restored. **GAP D (CRITICAL)**: WHEREDNGN.lua PLAYER_LOGIN never re-arms `_HostResolveOvercall` (the 5s C_Timer.After at Net.lua L1143). On host /reload mid-PHASE_OVERCALL, the table soft-locks — no fallback resolves the window if not all seats decide. (Resync replay at Net.lua L394-402 covers re-joining clients but the host-side timer is gone.)

6. **Score / style ledger.** `s.cumulative` persists (non-transient). **GAP E**: `Bot._partnerStyle` is module-level, **not in `s`** → wiped to nil on every /reload. M3lm/Fzloky/Saudi-Master tiers lose all in-game partner reads. `Bot.ResetStyle` only fires at round 1 (Net.lua L1710), so post-/reload rounds run with nil `_partnerStyle` until lazy-init via `emptyStyle()` — losing accumulated counters silently. Same issue for `Bot._memory`, `Bot.r1WasAllPass`. Should be either (a) snapshotted into `s._partnerStyle` for save, or (b) WHEREDNGNDB-mirrored.

7. **WHEREDNGNDB tampering.** RestoreSession defends against: missing `session`, missing `ts`, stale ts, owner mismatch, missing `state`. **GAP F**: no type checks on `sess.state` itself, on inner tables (`contract`, `tricks`, `seats`), or `state.phase`/`state.gameID`. A hand-edited `seats[1] = "string"` or non-table `tricks` crashes downstream (`#s.tricks`, `s.seats[turn].isBot`). The L297 `if s.contract` block assumes table. `reset()` itself does pcall-guard `WHEREDNGNDB` (L74) but `RestoreSession` does not.

## Other observations
- `lastGameID` cleared on `S.Reset` (L123) but **not** on RestoreSession's owner-mismatch return → cross-character `lastGameID` survives, so character B's PLAYER_ENTERING_WORLD will still fire `maybeRequestResync` for character A's gameID. Harmless (host won't recognize the requestor) but noisy.
- `pendingPreemptContract` is correctly non-transient and preempt restoration is well-handled (preemptEligible + StartLocalWarn re-arm).
- `hostDeckRemainder` correctly non-transient (comment L193-198).
