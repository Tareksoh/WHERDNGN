# AKA-receiver edge-case hunt (Bot.lua HEAD v0.7.2)

Receiver code lines: Bot.lua:2192-2225 (explicit + implicit branch).
PickAKA sender: Bot.lua:2836-2883. State: State.lua:1339-1346 (set), 1238 (clear at trick-end), 749/478/110 (clear at round/reset). Net path: Net.lua:2945-2966 (`_OnAKA`) and 2236-2250 (`LocalAKA`).

## Findings

### 1. Explicit AKA called on lead, partner then plays NON-Ace
Bot.PickAKA only fires when `#trick.plays == 0` (Bot.lua:2839) AND on a non-Ace lead (line 2864: `if r == "A" then return nil`). Partner cannot "play non-Ace" — they're announcing on their own lead, which is the card just registered. **Not exploitable via bot path.** Human path (`N.LocalAKA`) requires `S.LocalAKAcandidate()` confirms the local hand still holds the boss, but does NOT verify a card was just played or even a lead. Edge 1 mostly safe via bot, but human-driven path can desync (see #3).

### 2. Bare-Ace lead + explicit AKA both fire
Receiver code (Bot.lua:2201): `if not explicitAKA and ...` — implicit branch only fires when explicit is FALSE. **Mutually exclusive, no double-fire.** And `Bot.PickAKA` rejects rank=A leads (line 2864), so a bot will never broadcast AKA on a bare Ace. A human leading bare Ace and clicking AKA simultaneously sets explicit, suppressing implicit branch — same outcome regardless. Safe.

### 3. AKA called AFTER lead via late MSG_AKA — RETROACTIVE BUG (latent)
`N.LocalAKA` (Net.lua:2236) and `_OnAKA` (Net.lua:2945) impose NO `#trick.plays == 0` gate. A human can press the AKA button after their partner has played 2nd/3rd. `S.ApplyAKA` sets `s.akaCalled = {seat, suit}` at any moment during PHASE_PLAY. The receiver re-evaluates `S.s.akaCalled` on every Bot.PickPlay call — so a 4th-position bot deciding mid-trick will see the freshly set explicit AKA and suppress its ruff retroactively. **In multi-round / async settings the banner can also race the trick-end clear (State.lua:1238) if MSG_AKA arrives during ApplyTrickEnd**; akaCalled would persist into next trick on the receiver's client. No timestamp/trick-id is bound to the AKA frame.

### 4. Bare-Ace lead + partner NOT-winning — SUPPRESS DOES NOT FIRE (correct gate)
Implicit-AKA gate at Bot.lua:2204 requires `partnerWinning`. If 2nd-seat opp ruffed the bare Ace, `partnerWinning` is false, branch skipped. Receiver falls through to ruff/normal logic. **Correct.** But note the implicit detector reads `trick.plays[1]` (the ORIGINAL lead) not the current top, so detection of "partner led bare A" is preserved; the `partnerWinning` veto saves it.

### 5. AKA cleared between tricks — TRICK-END only (audit risk)
`s.akaCalled = nil` lives at State.lua:1238 inside `ApplyTrickEnd`, plus reset paths (lines 110, 478, 749, 1238). **NOT cleared on trick-1 mid-flight or by a new lead.** Combined with #3, a stale AKA from trick N could leak into trick N+1 if `ApplyTrickEnd` fails to run (e.g., resync mid-trick). Replay frame at Net.lua:434-437 re-broadcasts `s.akaCalled`, locking the stale state in.

### 6. AKA + SWA interaction
`N.LocalAKA` only checks `S.s.paused` and `phase==PHASE_PLAY`. `swaRequest` does NOT pause AKA. A pending SWA vote window with AKA fired simultaneously is allowed. No cross-validation. Low impact (cosmetic banner overlap in UI), but no logic conflict in receiver.

### 7. Cross-team AKA spoof
`_OnAKA` (Net.lua:2957) calls `authorizeSeat(seat, sender)` so an opponent cannot forge AKA "from" the partner seat — but they CAN legitimately call AKA on their OWN team. Receiver gate at Bot.lua:2193 `akaCalled.seat == R.Partner(seat)` filters out opponent seats. **Safe.** But: if seat numbering is corrupted (host reload mid-game), a bot whose `localSeat` was reassigned could mis-resolve `R.Partner(seat)`. Out of scope for this branch.

## Verdict
**2 latent bugs found** (Edge 3 retroactive late-AKA + Edge 5 stale akaCalled across resync). Edges 1,2,4,6,7 are correctly handled. The receiver gate is robust to spoofing and to mismatched signals; the gap is purely temporal — nothing binds an AKA frame to a specific trick id.
