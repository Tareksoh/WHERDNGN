# D_RedTeam_audit.md — v0.10.7 cross-cutting red-team / regression audit

**Codebase:** `C:\CLAUDE\WHEREDNGN\` at v0.10.7 (commit `3a70423`).
v0.10.5 (`47a886c`), v0.10.6 (`2b82091`), v0.10.7 (`3a70423`) all
sit on top of v0.10.4 (`44cf99d`).
**Scope:** across-files concerns — state-corruption attacks, hostile
peer wire injection, `C_Timer.After` race conditions, cross-version
compat, recent-changes regression risk, idempotency under wire-
replay, doctrinal consistency. Builds on `review_v0.10.0/REVIEW.md`
+ `review_v0.10.2/REVIEW_v0.10.2.md` + sub-tracks; prior findings
cited as "**prior**", not re-litigated.
**Verdict:** **1 HIGH structural regression** (v0.10.6 redeal-stuck
recovery is dead code via TRANSIENT_FIELDS collision), **1 MED spec/
code mismatch** (last-trick-win cue scope), **1 MED UX leak** (resync
replay fires v0.10.7 cues for old events), 4 smaller MED findings,
3 LOW. No new CRIT.

---

## 1. Executive summary

| Sev | ID | Site | Synopsis |
|---|---|---|---|
| **HIGH** | RT07-01 | `State.lua:211` + `WHEREDNGN.lua:227` + `Net.lua:2497` | v0.10.6 redeal-stuck-recovery is structurally dead. `redealing` is in `TRANSIENT_FIELDS`, so `s.redealing` is `nil` after `RestoreSession`. Both PLAYER_LOGIN and LocalPause-resume recovery branches gate on `s.redealing` and never fire across `/reload`. The user-reported scenario the fix was meant to address ("paused mid-redeal + /reload") still soft-locks. |
| MED | RT07-02 | `State.lua:1425` + `CHANGELOG.md:50` | `SND_LAST_TRICK_WIN` cue fires on **every** local-won "obvious" trick, not just trick 8. CHANGELOG wiring section explicitly says `#tricks == 8`; code has no such gate. Filename `last_trick_win.ogg` becomes misleading if intentional. |
| MED | RT07-03 | `State.lua:1307, 1320, 1391, 1425` | Resync-replay UX leak: v0.10.7 cues fire on every replayed `MSG_PLAY` / `MSG_TRICK` during `_OnResyncRes` reconstruction. Rejoiners hear sound flood for already-finished tricks. `_OnTrick` doesn't even take a `replayFlag` arg. |
| MED | RT07-04 | `State.lua:1625, 390` | `s.sweepTrackAnnounced` reset only in `ApplyStart` and `reset()`. NOT reset by `ApplyRoundEnd` or `ApplyResyncSnapshot`. Defense-in-depth gap. |
| MED | RT07-05 | `Net.lua:870` | `_OnContract` accepts `bidder` field with no range check. Spoofed `bidder=5` writes corrupted contract; downstream silent-mask via `R.TeamOf(5)="B"` and `(5 % 4)+1 = 2`. **Prior** at `review_v0.10.4_ship_readiness.md` "B-Net-02 H1/H2"; re-flag. |
| MED | RT07-06 | `Net.lua:1541` | `_OnRound` accepts `nil` numeric fields without guard. `s.cumulative.A = nil` silently corrupts score state. |
| MED | RT07-07 | `Bot.lua:794-831` | v0.10.6 `hokmMinShape` Lever C admits weak mardoofa pairs. `count == 2 + hasSideAce` doesn't verify the 2nd trump is a high mardoofa partner (J+9 or J+A trump per source); admits `J+7+side-A` etc. |
| LOW | RT07-08 | `WHEREDNGN.lua:227` + `Net.lua:2497` | If RT07-01 is fixed, dual-path recovery is verified safe via `B._redealGen` gen-token guard — no double-fire. |
| LOW | RT07-09 | `Net.lua:1652-1684` | Trick-resolve 2.2s timer has no captured "trick token". Theoretical race: Reset + new round + 4 rapid plays within 2.2s could let an old timer resolve a new trick. Not reachable in practice. |
| LOW | RT07-10 | `docs/strategy/decision-trees.md` | Stale "(not yet wired)" markers (sunMinShape mardoofa, Ashkal allow-list). Already noted **prior**, no new drift. |

---

## 2. RT07-01 (HIGH) — v0.10.6 redeal-stuck recovery is dead code

**Sites:**
- `State.lua:209-211` — `TRANSIENT_FIELDS = { ..., redealing = true, ...}`
- `State.lua:259-262` — `S.SaveSession` skips fields in `TRANSIENT_FIELDS`
- `State.lua:315-316` — `S.RestoreSession` wipes `s` then overlays only `sess.state`
- `WHEREDNGN.lua:227-241` — PLAYER_LOGIN recovery branch (gates on `s.redealing`)
- `Net.lua:2497-2507` — `LocalPause` resume recovery branch (gates on `s.redealing`)

### Trace

1. Host enters redeal: `_HostRedeal:1798` → `S.ApplyRedealAnnouncement(N)` sets `s.redealing = {nextDealer=N, ts=...}`.
2. The 3s `C_Timer.After` body (`Net.lua:1825-1828`) is scheduled with `B._redealGen = thisGen`.
3. User pauses → `S.s.paused = true`. The 3s timer fires while paused → `_HostExecuteRedeal` bails on `S.s.paused`.
4. User `/reload`s.
5. `S.SaveSession` runs. Loop: `for k, v in pairs(s) do if not TRANSIENT_FIELDS[k] then snap[k] = v end end`. Since `TRANSIENT_FIELDS.redealing == true`, the field is **NOT** persisted into the snapshot.
6. PLAYER_LOGIN fires. `S.RestoreSession`: `for k in pairs(s) do s[k] = nil end` (line 315) then `for k, v in pairs(sess.state) do s[k] = v end` (line 316). **`s.redealing` ends up `nil`** because `sess.state.redealing` is `nil` (not in snap).
7. `WHEREDNGN.lua:227` predicate: `if s.redealing and B.Net and B.Net._HostExecuteRedeal and ... then`. **FALSE** because `s.redealing` is nil. **Branch skipped.**
8. User unpauses. `LocalPause(false)` enters resume path. `Net.lua:2497`: `elseif S.s.redealing and (S.s.phase == K.PHASE_DEAL2BID or S.s.phase == K.PHASE_DEAL1) then`. **FALSE** because `s.redealing` is nil. **Branch skipped.**
9. State sits frozen at `phase ∈ {DEAL2BID, DEAL1}` with no recovery — the exact user-reported soft-lock.

### Why the bug wasn't caught

`tests/run.py` only loads `Rules.lua + Cards.lua + Constants.lua` (rules harness) and `State.lua + Bot.lua` (state_bot harness). `Net.lua` and `WHEREDNGN.lua` are NOT loaded. The recovery code lives in those untested files. The "412/412 still pass" gating doesn't exercise the cross-`/reload` recovery flow. Same root cause as the v0.10.4 SWA pause-recovery defects.

### Verified across versions

- v0.10.4 (`44cf99d`) — `redealing = true` in TRANSIENT_FIELDS, recovery code absent.
- v0.10.5 (`47a886c`) — same.
- v0.10.6 (`2b82091`) — recovery code added at `WHEREDNGN.lua:227` and `Net.lua:2497`. **`redealing = true` still in TRANSIENT_FIELDS at `State.lua:211`.** v0.10.6 did NOT touch State.lua at all (`git diff 47a886c 2b82091 --name-only` shows: Bot.lua / CHANGELOG.md / Net.lua / WHEREDNGN.lua / tests/test_state_bot.lua — State.lua absent).
- v0.10.7 (`3a70423`) — same.

The v0.10.6 fix author intended `s.redealing` to survive `/reload` (the comment at `WHEREDNGN.lua:218-226` says: *"the timer is gone and `s.redealing` is still set with no recovery path"*) but did not remove it from TRANSIENT_FIELDS. The two changes are incompatible.

### LocalPause-only path (no /reload)

The LocalPause-resume path **DOES** work in the no-`/reload` case (pause + unpause within one running session): `s.redealing` lives in the running `s` table and is not affected by SaveSession/RestoreSession. So a transient pause-during-redeal followed by un-pause WITHOUT `/reload` recovers correctly. Only the cross-`/reload` case is broken.

The user report explicitly involves `/reload`: *"i paused and did /reload, i came back after reload to the bidding round with no buttons and it froze."* So the intended canonical scenario is exactly the broken one.

### Fix shape

Surgical: remove `redealing = true` from `TRANSIENT_FIELDS` at `State.lua:211`. The original "stale banner that never auto-dismisses" rationale is now defended by the recovery code itself (it re-arms a fresh 3s `C_Timer.After`, then `_HostExecuteRedeal` → `S.ApplyStart` clears the flag at round start).

Alternative: persist `nextDealer` separately as a non-transient `s.pendingRedealNextDealer` field, leave `redealing` (the banner display struct) transient. Recovery branches read the persistent field.

### Severity rationale

HIGH: this defeats a v0.10.6 user-reported-bug fix. Real-game impact: the exact soft-lock the user reported is back. Test coverage gap means it would only resurface via another player report.

---

## 3. RT07-02 (MED) — `SND_LAST_TRICK_WIN` cue not gated to trick 8

**Sites:** `State.lua:1425-1497`; `CHANGELOG.md:46-50`.

The CHANGELOG wiring section says: *"`State.lua` `S.ApplyTrickEnd` (sweep-track + last-trick-win): when `#tricks == 8` AND `winner == localSeat`, fire SND_LAST_TRICK_WIN."* The actual code has NO `#tricks == 8` gate:

```lua
if B.Sound and B.Sound.Cue and s.localSeat and winner == s.localSeat
   and s.lastTrick and s.lastTrick.plays then
    -- ... obvious-criteria check (pos-4, boss-of-suit-with-trump-out,
    --     boss-of-trump) ...
    if obvious then B.Sound.Cue(K.SND_LAST_TRICK_WIN) end
end
```

The CHANGELOG **table summary** at line 20 conversely says: *"Local seat plays a card that's GUARANTEED unbeatable by remaining seats (option 3c). Pos-4 win OR boss-of-suit with trump pool exhausted OR boss-of-trump."* — this is a per-play criterion with no trick-8 mention. The TABLE is consistent with the code; the WIRING blurb is internally inconsistent with the table.

**Two interpretations:**
- CHANGELOG wiring blurb correct → add `if #s.tricks == 8 then` gate. Behaviour: cue fires only on round-final.
- Code intentional → cue fires on every guaranteed-unbeatable play. Filename `last_trick_win.ogg` reads as "the last trick I won" (the latest), not "trick 8". Audio file content needs to fit any-trick context (no "round over!" semantics).

Recommend resolving with user; default reading is "table is canonical, code is intentional, filename is sloppy". Severity MED because UX-quality, not correctness.

---

## 4. RT07-03 (MED) — Resync-replay UX leak: v0.10.7 cues fire for old events

**Sites:**
- `State.lua:1307` — `SND_CARD_PLAY` in `ApplyPlay`
- `State.lua:1320-1334` — `SND_TRUMP_CUT` in `ApplyPlay`
- `State.lua:1378-1383` — `SND_TRICK_WON` in `ApplyTrickEnd`
- `State.lua:1391-1401` — `SND_SWEEP_TRACK` in `ApplyTrickEnd`
- `State.lua:1425-1497` — `SND_LAST_TRICK_WIN` in `ApplyTrickEnd`
- `Net.lua:1413-1510` — `_OnPlay` HAS `replayFlag` but doesn't gate cues
- `Net.lua:1512-1539` — `_OnTrick` does NOT take a `replayFlag` arg

### Defect

During resync (rejoiner / cross-`/reload` state recovery), the host whispers `MSG_PLAY` and `MSG_TRICK` frames in turn-order to reconstruct the round. Receivers' `_OnPlay` / `_OnTrick` handlers call `S.ApplyPlay` / `S.ApplyTrickEnd` for each. These Apply functions fire SOUND CUES regardless of replay context.

`_OnPlay` at line 1500 correctly gates `Bot.OnPlayObserved` on `not isReplay` — but the cues at `S.ApplyPlay:1307` (rustle) and `1320-1332` (trump-cut) fire unconditionally. `_OnTrick` doesn't even take a replayFlag. So a rejoiner whose snapshot covers mid-round hears:
- 8 rapid card-rustles (one per replayed play)
- 1+ trump-cut sounds for replayed Hokm cuts
- 1+ trick-won pings for tricks the local seat already won
- 1 sweep-track sound if trick 3 was a sweep-pursuit
- 0..N last-trick-win sounds for past obvious-wins

The `Sound.lua` 0.10s SFX-throttle collapses identical-cue replays but cross-cue fires layer (different soundIds = different `lastFire[soundId]` slots).

### Fix shape

Plumb `isReplay` through `S.ApplyPlay` and `S.ApplyTrickEnd`:
- Add optional `isReplay` param.
- `_OnPlay` already computes `isReplay`; pass it through.
- `_OnTrick` needs `replayFlag` added (mirror v0.10.4 E1/E2 shape).
- Inside the apply functions, gate every `B.Sound.Cue(...)` on `not isReplay`.

Severity MED: UX-only, no correctness/desync risk. Resync is rare in practice but the v0.10.7 cues amplify the existing rustle-flood.

---

## 5. RT07-04 (MED) — `s.sweepTrackAnnounced` not reset by ApplyRoundEnd / ApplyResyncSnapshot

**Sites:** `State.lua:121, 796` (sets), `State.lua:1625-1710` (ApplyRoundEnd, no reset), `State.lua:390-542` (ApplyResyncSnapshot, no reset).

The `s.sweepTrackAnnounced` flag is reset only on `ApplyStart` (round-start) and `reset()`. NOT reset by:
- `S.ApplyRoundEnd` — round end transitions to `PHASE_SCORE`; if `ApplyStart` doesn't fire (corrupted state, partial restore), the flag persists.
- `S.ApplyResyncSnapshot` — the wire snapshot doesn't include the field; the snapshot doesn't wipe it either. So a rejoiner's restored value persists.

Crucially, the flag is NOT in `TRANSIENT_FIELDS`, so it persists across `/reload` via `RestoreSession`. In normal flow `ApplyStart` fires on every new-round MSG_START, which clears it. The bug is reachable only if `ApplyStart` is somehow skipped (orphan PHASE_SCORE state, dropped MSG_START frame). Defense-in-depth.

**Recommendation.** Add `s.sweepTrackAnnounced = nil` at `S.ApplyRoundEnd` start (defensive) and at `S.ApplyResyncSnapshot:526-536` (alongside the existing transient clears).

---

## 6. RT07-05 (MED) — `_OnContract` accepts out-of-range bidder

**Sites:** `Net.lua:870-876`; `State.lua:1030-1059`.

`_OnContract`'s only validation: `if not bidder or not btype then return end`. No range check on `bidder`. A trusted host (`fromHost` passes) sending `MSG_CONTRACT;5;H;X` writes `s.contract.bidder = 5`. Downstream:
- `R.TeamOf(5)` returns "B" (default branch).
- `(5 % 4) + 1 = 2` for next-seat math (silent off-by-one).
- `S.s.seats[5]` is `nil`; `authorizeSeat(5, ...)` rejects.

**Mitigation existing.** Trust model: only the host can send MSG_CONTRACT (`fromHost(sender)` gate). The actual host wouldn't set bogus bidder if running this same code (bidder comes from valid `_OnBid` flow).

**Fix shape (defense-in-depth).** Add `if bidder < 1 or bidder > 4 then return end` at `Net.lua:874`.

Already noted in `review_v0.10.4_ship_readiness.md` deferred items (B-Net-02 H1/H2). **Re-flag prior**.

---

## 7. RT07-06 (MED) — `_OnRound` accepts `nil` numeric fields without guard

**Sites:** `Net.lua:1541-1546`; dispatcher at `Net.lua:577-579`.

```
N._OnRound(sender, tonumber(fields[2]), tonumber(fields[3]),
           tonumber(fields[4]), tonumber(fields[5]), sweep, bidderMade)
```

If wire payload has garbage (e.g., `fields[2] = "garbage"`), `tonumber` returns `nil`. `_OnRound` body:
```
if fromSelf(sender) then return end
if not fromHost(sender) then return end
if S.s.isHost then return end
S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)
```

No nil-guards. `S.ApplyRoundEnd:1626-1627` unconditionally sets `s.cumulative.A = totA`. If `totA == nil`, `s.cumulative.A` becomes `nil`. Downstream consumers mostly defend (`s.cumulative.A or 0` patterns), so this is silent state corruption rather than a crash. Score panel would render 0/0 after a corrupted MSG_ROUND.

**Fix shape.** At `_OnRound` entry: `if not addA or not addB or not totA or not totB then return end`.

Severity MED: silent state corruption, no crash; host presumed honest.

---

## 8. RT07-07 (MED) — `hokmMinShape` Lever C admits weak mardoofa pairs

**Sites:** `Bot.lua:794-831` (v0.10.6 line 829: `if count == 2 and hasSideAce then return true end`).

Source-canonical R2: *"أقل شي عشان تشتري الحكم: الولد + مردوفة معاه + إكا واحدة"* — *"minimum to buy Hokm: J of trump + ONE other trump (mardoofa with the J) + ONE Ace on the side."* The "other trump" is implicitly a HIGH trump that pairs with the J (in Saudi Hokm rank, the canonical mardoofa is J+9; J+A-trump is also strong).

The new clause checks only `count == 2 and hasSideAce`. A hand `{J♠, 7♠, A♥, ...}` matches: count(♠)=2 (J+7), hasJ=true, hasSideAce=true. But `J+7` is NOT a Saudi mardoofa.

**Effect.** False-positive expansion. The CHANGELOG's 200k-trial Monte Carlo "~19.23% of random hands" is the LOOSE check; the canonical-strict check (J+9 or J+A only) would be ~5-10% of random hands.

**Fix shape (deferred to v0.10.8 if telemetry confirms over-bidding).** Strict check:
```lua
if count == 2 and hasSideAce then
    local hasMardoofaPartner = false
    for _, c in ipairs(hand) do
        local r, su = C.Rank(c), C.Suit(c)
        if su == suit and (r == "9" or r == "A") then
            hasMardoofaPartner = true; break
        end
    end
    if hasMardoofaPartner then return true end
end
```

Severity MED: bot bidding looser than canonical pattern. v0.10.7+ telemetry will surface the rate.

---

## 9. RT07-08 (LOW) — Redeal recovery double-fire (post-RT07-01 fix)

**Threat model.** Assume RT07-01 is fixed (`redealing` becomes persistent). Verify no double-fire across the dual-recovery paths.

- **Case A.** User paused at `/reload`, restored as paused. PLAYER_LOGIN branch SKIPS (`not s.paused` predicate fails). User unpauses → LocalPause-resume arms timer with gen=N+1. Single timer pending. **Safe.**
- **Case B.** User NOT paused at `/reload`. PLAYER_LOGIN arms timer with gen=N+1. LocalPause-resume doesn't fire (no pause→unpause transition). Single timer pending. **Safe.**
- **Case C.** PLAYER_LOGIN arms gen=N. User pauses (no cancel). User unpauses → LocalPause-resume arms gen=N+1. Old gen=N timer fires → `thisGen ~= B._redealGen` → bails. New gen=N+1 timer fires → executes. **Safe.** The gen-token guard works correctly.

Verified safe post-RT07-01 fix.

---

## 10. RT07-09 (LOW) — Trick-resolve 2.2s timer no gen-token

**Sites:** `Net.lua:1652-1684`.

The 2.2s body has phase + `#plays >= 4` staleness guard but no captured trick-token (unlike `B._redealGen` for the 3s redeal timer). Theoretical race: `/baloot reset` + new round + 4 rapid plays within 2.2s → old timer's body finds `phase == PLAY` and `#plays >= 4`, resolves the new trick. Not reachable in practice (HostStartRound + bidding > 2.2s wall time).

**Fix shape (defense-in-depth).** Add `B._playGen` token bumped at Reset, captured in the timer body.

---

## 11. Cross-cutting analysis

### 11.1 State-corruption attack matrix

Hand-edit attacks on `WHEREDNGNDB`: covered exhaustively in `D-RT-14` (prior). All 11 vectors DEFENDED via type guards. **No new findings v0.10.4-v0.10.7.**

Hostile peer wire injection: covered in `D-RT-15` (prior). v0.10.4 E1/E2 AKA wire guards remain solid post-v0.10.7. v0.10.5 scoring helpers (`R.IsBeloteCancelled`, `R.GameEndWinner`, `K.AL_KABOOT_REVERSE`) are scoring-internal — no new wire surface. v0.10.6 (`hokmMinShape`, `TH_SUN_BASE`) bot-internal. v0.10.7 cues client-local.

Two NEW wire-validation gaps from this cycle: RT07-05 (`_OnContract` bidder) and RT07-06 (`_OnRound` numeric fields).

### 11.2 C_Timer.After race-condition matrix

Audited 19 `C_Timer.After` sites in `Net.lua` + 5 in `State.lua`:

| Site | Re-arm? | Stale check? | Notes |
|---|---|---|---|
| `Net.lua:814` (PLAYER_LOGIN _HostStepPlay re-fire) | n/a | phase + plays | Safe |
| `Net.lua:1244, 1250` (overcall timeout) | YES (recursive) | phase | **v0.9.0 M1**; safe |
| `Net.lua:1667` (trick resolve 2.2s) | NO | phase + plays | RT07-09 LOW |
| `Net.lua:1825` (redeal 3s) | n/a | gen-token | Safe (`B._redealGen`) |
| `Net.lua:2503` (LocalPause redeal re-arm) | NO direct | gen-token | DEAD per RT07-01 |
| `Net.lua:2627, 2651, 2663, 2779, 2792, 2808, 4144, 4184, 4196` (SWA chain) | YES (recursive) | caller | **v0.10.3** fix; safe |
| `Net.lua:2715, 2839` (SWA-deny toast 3s) | n/a | caller match | Safe |
| `Net.lua:3689..3909` (Bot bel/triple/four/gahwa) | NO | phase | Safe; double-schedule is ApplyDouble-idempotent |
| `Net.lua:4040, 4091` (Bot bid/play delay) | NO | turn | Safe |
| `State.lua:152` (redeal banner 3.5s clear) | n/a | nextDealer match | Safe |
| `State.lua:826, 2065` (Awal/Thany 0.5s) | n/a | none | Harmless (Sound.Cue) |
| `State.lua:876` (meldHoldUntil 5.05s) | n/a | none | Harmless (UI.Refresh) |

Timer hygiene is solid post-v0.10.3 SWA refactor; only RT07-01 (broken) and RT07-09 (theoretical) open.

### 11.3 Cross-version compat (v0.10.2 ↔ v0.10.7)

- **v0.10.3 wire-tag** dual-emit `"!"`/`"?"` still active. Eligible to drop in v0.11.0.
- **v0.10.4 E1/E2 AKA guards.** Defensive; older clients sending malformed AKA get rejected by newer hosts. Safe in both directions.
- **v0.10.5 K.AL_KABOOT_REVERSE = 88.** Score change but transmitted via `MSG_ROUND` totals — receivers don't re-derive scoring → no desync. UX-consistency only (mixed-version players see different "expected" totals).
- **v0.10.5 R.IsBeloteCancelled / R.GameEndWinner.** Shared helpers replace inline duplicated logic. Wire transmits TOTALS only; mixed-version games converge to host's authoritative result. Clean.
- **v0.10.6 hokmMinShape / TH_SUN_BASE / redeal recovery.** Bot-internal + host-internal. Zero wire surface change.
- **v0.10.7 sound cues.** Client-local audio. Zero wire surface.

Open compat risk (carried, **prior**): v0.10.4 X5 fix produces different `s.meldsByTeam` for Hokm-Carré-A. Mixed-version games hosted by pre-v0.10.4 silently lose 100-meld for 4-Aces-Hokm rounds; hosted by v0.10.4+ correctly score. No new mitigation since v0.10.4 ship.

### 11.4 Idempotency under wire-replay

**Replay-aware handlers** (correct): `_OnMeld`, `_OnPlay`, `_OnAKA` (all gate authority + `Bot.OnPlayObserved` on replayFlag).

**Replay-blind handlers** (apply state without replay-flag awareness): `_OnTrick` (RT07-03), `_OnRound`, `_OnContract`, `_OnDouble/Triple/Four/Gahwa`, `_OnHand`, `_OnBidCard`, `_OnTurn`. All except `_OnTrick` are guarded by idempotent state checks (`if S.s.contract.doubled then return end`, etc.) so re-applying is safe. The non-idempotent stat counters (`WHEREDNGNDB.history` row append in `S.ApplyRoundEnd`; `B.Bot._partnerStyle.bels++` in `OnEscalation`) are NOT reachable via replay because:
- `MSG_ROUND` is not re-broadcast on resync (host's `SendResyncRes` whispers snapshot + bidcard + melds + tricks + in-flight plays + hand only).
- `OnEscalation` is reached only from `_OnDouble/Triple/Four/Gahwa` which short-circuit on idempotent guards before reaching it.

**Verified safe** for non-idempotent stats. RT07-03 is the only outstanding replay concern (UX cues fire spuriously).

### 11.5 Test-coverage gaps for Net.lua / BotMaster.lua

`tests/run.py:25-28` only loads `Rules.lua + Cards.lua + Constants.lua` and `State.lua + Bot.lua`. **`Net.lua` and `BotMaster.lua` have ZERO behavioural test coverage.** This gap is the proximate cause of RT07-01 (the v0.10.6 redeal fix shipped untested).

**Top behavioural paths needing test coverage** (priority by recent-bug clustering):

1. `N.LocalPause` resume path — RT07-01, v0.10.3 SWA refactor, v0.10.6 redeal.
2. `N._HostStepPlay` 2.2s timer interactions — RT07-09.
3. `N._OnResyncRes` + replay — RT07-03 cue replays, gen-token interactions.
4. `N._OnContract` / `N._OnRound` — wire-validation gaps RT07-05, RT07-06.
5. `N.HostResolveTakweesh` / `N.HostResolveSWA` — Qaid scoring with v0.10.5 helpers.
6. `BotMaster.PickPlay` — ISMCTS + akaCalled propagation (v0.10.3 fix #5).

Test-harness gap acknowledged in `review_v0.10.4_ship_readiness.md` deferred items — **prior**. Re-flag because v0.10.6 redeal-stuck fix is the canonical example of "Net.lua bugs land only in production."

---

## 12. Doctrinal / source-canonical consistency

- **Reverse Al-Kaboot (v0.10.5):** `saudi-rules.md` updated to reflect `K.AL_KABOOT_REVERSE = 88` + bidder-led-trick-1 gate. Doc/code consistent.
- **v0.10.6 hokmMinShape Lever C:** `decision-trees.md` Section 1 covers J anchor + A+T mardoofa shape. The new `count == 2` clause matches R2 in spirit but loosens "9 mardoofa or A trump" specifically — see RT07-07. No explicit "R2 minimum" row in the doc; recommend adding for v0.10.8 doc cycle.
- **v0.10.5 Belote-cancellation team-level rule:** `saudi-rules.md` still describes same-player form (pre-v0.9.0 M5). Stale; **prior** flag in `review_v0.10.2/§4.3`.
- **v0.10.7 sound cues:** no doc treatment. CHANGELOG line 50 mismatch — RT07-02.
- **"(not yet wired)" stale markers:** RT07-10. Confirmed stale post-v0.10.6: `decision-trees.md:47` (sunMinShape mardoofa wired at `Bot.lua:841-857`); `:53` (Bel-fear bias wired at `Bot.lua:1294-1298`); `:61-63` (Ashkal allow-list wired at `Bot.lua:1302-1394`). Recommend doc-pass to remove stale markers.
- **Glossary line refs:** no new drift in v0.10.4-v0.10.7.

---

## 13. Backlog snapshot

Carried from `review_v0.10.4_ship_readiness.md`, unchanged through v0.10.7:
D-RedTeam-01 E4 (T-AKA trick-locking), B-Net-02 H1/H2 (forced-flag dead branches; RT07-05 partial closure), B-State-02 H1 (`S.ApplyBid` value validation), Bargiya FN→FP swing, B-Bot-06 F-01/F-02 (L07 cascade fail at M3lm+), Bot.lua:1336/1366 dead-code redundancy, Bargiya inner-discriminator axis flip, ISMCTS akaCalled-respecting sample pool, `S.s.swaDenied` UI banner read, Sun-Mathlooth-K pos-4 smother gate, **Net.lua + BotMaster.lua test-harness gap**.

NEW for v0.10.7 cycle:
- **RT07-01** (HIGH) — redeal recovery dead via TRANSIENT_FIELDS collision
- RT07-02 (MED) — last-trick-win cue scope (doc/code mismatch)
- RT07-03 (MED) — resync replay UX leak (v0.10.7 cues)
- RT07-04 (MED) — `sweepTrackAnnounced` not reset by ApplyRoundEnd / ApplyResyncSnapshot
- RT07-05 (MED) — `_OnContract` bidder out-of-range (re-flag of B-Net-02 H1/H2)
- RT07-06 (MED) — `_OnRound` nil-numeric guard
- RT07-07 (MED) — `hokmMinShape` Lever C weak mardoofa admission
- RT07-09 (LOW) — trick-resolve 2.2s timer no gen-token

---

## 14. References

- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` — v0.10.0 → v0.10.7 entries.
- `.swarm_findings\review_v0.10.0\REVIEW.md` — phase-1 source-of-truth review.
- `.swarm_findings\review_v0.10.2\REVIEW_v0.10.2.md` — phase-2 multi-track audit.
- `.swarm_findings\review_v0.10.2\REVIEW_v0.10.4_ship_readiness.md` — pre-v0.10.4 ship readiness.
- `.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-14_savedvars_attack.md` — savedvars hand-edit defenses.
- `.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-15_wire_malformed.md` — wire-malformed handler audit.
- `.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-16_version_skew.md` — cross-version compat baseline.
- `.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-32_pause_timer_race.md` — pause-timer races.
- `C:\CLAUDE\WHEREDNGN\State.lua:193-249` — `TRANSIENT_FIELDS` table (RT07-01 root cause).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua:130-241` — PLAYER_LOGIN init + restore + recovery.
- `C:\CLAUDE\WHEREDNGN\Net.lua:2468-2540` — `LocalPause` resume + recovery.
