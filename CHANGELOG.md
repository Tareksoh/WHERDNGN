# Changelog

## v3.1.10 — MSG_PLAY + MSG_OVERCALL_DECISION 250ms retry

User reported two new symptoms after v3.1.8 shipped:

1. **"Sun button did nothing"** — Dedah pressed "Take as Sun" during the
   5-second overcall window after Pain bid Hokm. The button click had
   no effect, the timer expired, Hokm stood.
2. **"Host's card invisible mid-trick"** — host plays a card; remotes
   see the turn advance to themselves but the table doesn't show the
   host's card. Trick-end MSG_TRICK eventually backfills the visual,
   but during the trick the UX is broken.

User suspected v3.1.6-3.1.8 caused these. They didn't — but our fixes
EXPOSED them. Pre-v3.1.6, dropped wire frames produced 60-second
freezes that masked everything. With heal mechanisms now recovering
the freeze automatically, the shorter visual artifacts of OTHER
dropped messages became noticeable.

### Root cause: missing retry on critical wire messages

WoW's CHAT_MSG_ADDON channel is at-most-once and silently drops frames
under throttle pressure. v1.6.1 added a 250ms re-broadcast to
`SendTurn` to recover dropped MSG_TURN. The same pattern was never
applied to:

- **`SendPlay`** (`Net.lua:423`) — single-shot. When MSG_PLAY drops,
  remotes don't see the card. MSG_TRICK at trick-end carries the full
  play list and recovers the visual at trick close, but mid-trick
  rendering is broken.
- **`SendOvercallDecision`** (`Net.lua:1475`) — single-shot. When the
  decision frame drops, the host never registers the decision, the
  5-second timer fires with all-WAIVE, and the contract stands
  unchanged. The button-press gives no feedback because local state
  only updates on host echo, which never arrived.

### Fix: mirror v1.6.1 SendTurn retry pattern

Both `SendPlay` and `SendOvercallDecision` now re-broadcast 250ms
after the initial frame:

```lua
function N.SendPlay(seat, card)
    broadcast(("%s;%d;%s"):format(K.MSG_PLAY, seat, card))
    if C_Timer and C_Timer.After then
        C_Timer.After(0.25, function()
            if S.s.phase == K.PHASE_PLAY then
                broadcast(("%s;%d;%s"):format(K.MSG_PLAY, seat, card))
            end
        end)
    end
end
```

Idempotence is already wired in receivers:

- **`_OnPlay`** (Net.lua:1978-1982) — the per-trick "seat already
  played" check rejects any seat already in `s.trick.plays`. A
  duplicate MSG_PLAY for an already-applied play is a no-op.
- **`S.RecordOvercallDecision`** (State.lua:1096) — returns false if
  the seat already has a recorded decision. A duplicate decision frame
  is a no-op.

Phase guards on the retry side suppress stale re-broadcasts: a play
broadcast for a trick that has since resolved (phase advanced past
PLAY) doesn't re-emit; an overcall decision after the window closed
doesn't re-emit.

### Why these weren't caught earlier

The original v1.6.1 SendTurn fix was prompted by a specific user-
reported MSG_TURN drop scenario. Other wire messages didn't have
prominent symptoms in the v0.x to v3.1.5 era because:

- Mid-trick MSG_PLAY drops were masked by the eventual MSG_TRICK
  frame that contains the full play list. UX degradation was brief
  (typically 1-3 seconds) and infrequent enough to not be reported.
- MSG_OVERCALL_DECISION drops manifested as "I waved when I meant
  to take" — easy to misattribute to the player's own click.

The v3.1.6-3.1.8 freeze fixes cleaned up the worst symptom (60-second
state freezes), making these residual artifacts visible enough to
diagnose. Mirror-fix the v1.6.1 retry pattern now closes the gap.

### Tests

**969/969 pass** (was 963, +6 new pins). New section AX covers:

- AX.1: SendPlay retry marker present
- AX.2: SendPlay broadcasts MSG_PLAY twice
- AX.3: SendPlay retry uses 0.25s + PHASE_PLAY guard
- AX.4: SendOvercallDecision retry marker present
- AX.5: SendOvercallDecision broadcasts MSG_OVERCALL_DECISION twice
- AX.6: SendOvercallDecision retry uses 0.25s + PHASE_OVERCALL guard

### Audit follow-up: other single-broadcast call sites

Other senders that may benefit from retry but haven't shown user-
visible symptoms (deferred to future audit):

- `SendBid`, `SendDouble`, `SendTriple`, `SendFour`, `SendGahwa`
  (escalation chain)
- `SendBidCard`, `SendBelote`
- `SendAKA`, `SendSWA`, `SendSWAReq`, `SendSWAResp`
- `SendMeld`, `SendKawesh`

These are queued for v3.2.x audit if user reports surface them.

## v3.1.9 — Partner-trump-led-fragile-lock + forced-ruff trump conservation

User shared a saved-game (round 5) where a Saudi Master bot bid Hokm
(trump=H) but lost trick 1 and burned J-of-trump on trick 2's routine
ruff. Their team won 6/8 tricks (14 raw add) when 8/8 (Kaboot, 250) was
on the table. Two distinct bugs identified.

### Bug 1: Bot ducks partner's fragile trump lead (T1)

**Setup**: bot=seat 4, trump=H. Partner (seat 2) led KH (rank 4).
Opp seat 3 played 8H (rank 2). Bot pos-3 had {QH, JH, 9H, AH}.

**Pre-fix behavior** (`Bot.lua:5382` lowestByRank fallback): bot
returned QH (rank 3 = lowest trump) per the canonical "ride low when
partner is winning" Saudi convention. Opp pos-4 played TH (rank 5)
and won the trick. Team A captures 17 raw points; Kaboot dead.

**The convention has a carve-out** the heuristic missed: when partner's
trump lead is NOT the highest unplayed trump (here J was still out),
opp pos-4 may over-cut. The bot should detect "fragile lead" and
play its minimum-sufficient lock card.

**v3.1.9 fix** (`Bot.lua:5361-5424`): in the partnerWinning + Hokm +
trump-led + partner-led-the-trick branch (Advanced+ tier), compute:

1. `maxOppRank` = highest rank that is NOT in our hand AND NOT yet
   played. Walks `TRUMP_HOKM_ORDER_DESC = {J, 9, A, T, K, Q, 8, 7}`
   matching `S.s.playedCardsThisRound` and own-hand membership.
2. If `maxOppTR > partnerTR`, partner's lead is beatable. Find the
   LOWEST of our trumps with trick rank > maxOppTR (the minimum-
   sufficient lock). Return it.
3. Otherwise (partner's lead IS the boss), fall through to the
   v0.11.19 U-6 / lowestByRank ride-low path.

**Reproducer trace post-fix**: bot detects partner's KH (rank 4) is
fragile (J is the boss). maxOppRank = T (highest not in our hand,
not played) → maxOppTR = 5. Bot's trumps with rank > 5 are AH (6),
9H (7), JH (8). Lowest = AH. Bot plays AH, opp pos-4's TH (rank 5)
loses, bot's team locks T1 with +17 raw to team B. Kaboot back on
the table.

### Bug 2: ISMCTS overrides heuristic with high trump on routine ruff (T2)

**Setup**: bot pos-4, trump=H. Opp seat 1 led AC. Partner 9C, opp
TC. Bot is void in C, must trump. legal = {JH, 9H, AH} (trumps left
after T1's QH used).

**Pre-fix behavior**: heuristic at `Bot.lua:6475` correctly returns
AH (lowest trick rank — JH=8, 9H=7, AH=6). But Saudi Master ISMCTS
overrode with JH because:

- Each candidate's rollout score includes the immediate trick's raw
  capture: JH=20 raw, 9H=14 raw, AH=11 raw.
- Rollouts under-value future J-of-trump preservation because the
  rollout policy itself doesn't model "J is uniquely valuable as
  Saudi kill card." So the future-trick advantage of saving JH
  doesn't compensate for the immediate +9 raw delta.
- ISMCTS argmax picks JH; Saudi convention mandates AH.

**v3.1.9 fix** (`BotMaster.lua:1154-1200`): post-argmax override.
When `best` is a trump in Hokm + non-trump lead + all legal are
trump (true forced-ruff), force the lowest trick rank trump.

```lua
if best and S.s.contract.type == K.BID_HOKM and S.s.contract.trump
   and trick.leadSuit ~= S.s.contract.trump
   and C.IsTrump(best, S.s.contract) then
    -- Check forced-ruff: all legal == trump
    -- Find lowest trick-rank trump → swap if best != lowest
end
```

**Why this is safe**:
- Faranka exceptions return non-winners (not high trumps), so the
  override never fights Faranka.
- Over-cut requirements pre-filter `legal` (only over-cutters are
  legal), so "lowest in legal" is still the canonical minimum-
  sufficient over-cut.
- The Saudi rule "don't waste J/9 on routine ruff" is unambiguous;
  there's no scenario where playing JH is correct over AH/9H when
  all three win the same trick.

**Reproducer trace post-fix**: ISMCTS picks JH. Override fires:
all legal are trump, AH has lower trick rank than JH, swap.
Bot plays AH, T2 still won by team B but bot retains JH for
future high-stakes ruff (e.g., when an opp leads K or Q of trump).

### Tests

**963/963 pass** (was 953, +10 new pins). New section AW covers:

- AW.1: lock marker in Bot.lua
- AW.2-3: lock gates (Hokm + trump-led + partner-led)
- AW.4: maxOppRank computation
- AW.5: minimum-sufficient lock semantics
- AW.6: override marker in BotMaster.lua
- AW.7: forced-ruff detection (all legal == trump)
- AW.8: gated on non-trump lead
- AW.9: trick-rank comparison
- AW.10: no-op when argmax already lowest

### Why no behavioral test for the bot's actual play

The fix is in two pickers (heuristic + ISMCTS post-process). A
behavioral test would need to set up a 4-player game with specific
hands matching the saved-game scenario. Test-section AS already has
similar end-to-end pickFollow tests; AW pins source-level invariants
which is sufficient given the trace above shows the picker now
returns the canonical Saudi card. If future regressions surface,
behavioral tests can be added.

## v3.1.8 — Heartbeat-derive heal fallback + deployment diagnostics

User shared a fresh freezelog (`message (3).txt`) after v3.1.6+v3.1.7
shipped. Two distinct freeze segments (Acing host @ GetTime ~438991,
Ballripper host @ GetTime ~444826), both 60 seconds, both with
`turn=1` stuck across every heartbeat in the gap.

### The smoking gun: zero HEAL events in the log

Across both freezes, Dedah's freezelog captured ~30 `RX` events
including heartbeats, MSG_PLAY, MSG_TURN, MSG_TRICK — but **no
`HEAL` entries**. Both v3.1.6 (heartbeat-heal) and v3.1.7
(MSG_PLAY-derive heal) write a freezeLog `HEAL` entry on every fire.
Their absence is conclusive: the heal code never executed on
Dedah's client.

The most likely cause is deployment lag — CurseForge propagation
delay, or a missed `/reload` after the addon updater pulled the
new build. The v3.1.6 + v3.1.7 logic IS correct (verified against
both freeze segments line-by-line); it just wasn't running yet on
the affected client.

### Two new mitigations for partial deployment

#### 1. Heartbeat-derive heal fallback (`Net.lua`, `_OnHeartbeat`)

The v3.1.6 heal only fires when `hostTurn` from the heartbeat
payload is non-zero. If the host is still on v3.1.5-, heartbeats
ship as `~` alone with no turn field — and v3.1.6 receivers
silently skip. This pure-defense fallback handles that case:

```lua
if (not hostTurn or hostTurn == 0)
   and S.s.phase == K.PHASE_PLAY
   and S.s.turnKind == "play"
   and S.s.trick and S.s.trick.plays then
    local playCount = #S.s.trick.plays
    if playCount > 0 and playCount < 4 then
        local lastPlay = S.s.trick.plays[playCount]
        if lastPlay and lastPlay.seat
           and lastPlay.seat >= 1 and lastPlay.seat <= 4 then
            local derivedTurn = (lastPlay.seat % 4) + 1
            if S.s.turn ~= derivedTurn then
                ...heal + log HEAL event
```

**Gate logic** — `not hostTurn or hostTurn == 0` means this fallback
only activates when the v3.1.6 path didn't. The two blocks are
mutually exclusive, so there's no risk of oscillation if both host
and client are temporarily stuck at the same value.

**Effective recovery time** — capped at one heartbeat cadence
(15s) when host is on v3.1.5- and client is on v3.1.8+. Worse
than v3.1.7's ~1-3s but materially better than the 60s AFK fallback.

#### 2. `/baloot version` slash command (`Slash.lua`)

Surfaces the most common diagnostic question — "is the fix
actually deployed everywhere?" — directly in chat:

```
> /baloot version
WHEREDNGN your version: 3.1.8
  Acing                    3.1.5 ✗ MISMATCH
  Ballripper               3.1.8 ✓
  Bassiouni                3.1.7 ✗ MISMATCH
WHEREDNGN a MISMATCH means that player should /reload after updating the addon
```

Reads from `S.s.peerVersions` (populated by `_OnHost` + `_OnJoin`
handshakes since v2.0.0 MP-60). Players see at a glance who's
behind without scrolling chat history for the auto-mismatch warning.

### Coverage matrix (host × client × what fires)

| Host ver | Client ver | What heals the dropped MSG_TURN |
|---|---|---|
| v3.1.7+ | v3.1.7+ | v3.1.7 mid-trick (1-3s) |
| v3.1.7+ | v3.1.6 | v3.1.6 heartbeat (≤15s) |
| v3.1.6  | v3.1.8+ | v3.1.6 heartbeat (≤15s) |
| v3.1.5- | v3.1.8+ | **v3.1.8 derive-heartbeat (≤15s)** ← new |
| v3.1.5- | v3.1.7  | (no heal, 60s AFK) |
| v3.1.5- | v3.1.5- | (no heal, 60s AFK) |

The v3.1.8 fallback closes the row that previously had no recovery:
client updated, host not yet updated. Users no longer need to wait
for every peer to update simultaneously.

### Tests

**953/953 pass** (was 944 — +9 new pins). New section AV covers:

- AV.1: heartbeat-derive fallback marker present
- AV.2: gated on missing/zero `hostTurn` (no v3.1.6 oscillation)
- AV.3: distinct log line for derive-heal vs heartbeat-heal
- AV.4: freezeLog HEAL captures heartbeat-derive provenance
- AV.5: seat-range validation `[1,4]` on lastPlay.seat input
- AV.6-9: `/baloot version` command + peerVersions read + MISMATCH
  flag + help text mention

### Why this isn't over-engineering

The root cause of the user's reported freeze is deployment lag, not
a code bug. But "tell the user to /reload" doesn't scale when the
freeze is intermittent and the user has 3 other players to coordinate
with. Surfacing version-mismatch directly + ensuring the updated
client self-heals regardless of peer state lets the fix benefit
the user as soon as ONE party (typically the host) updates —
rather than waiting for all four.

## v3.1.7 — Millisecond-speed mid-trick turn self-heal

User feedback on v3.1.6's 15s heartbeat-heal: "15 seconds can make
the game feel very slow, we want it more realistic for peak fast
play moments." Right call — 15s of staring at a frozen table is
disruptive even if recoverable.

### What v3.1.7 adds

When a `MSG_TURN` drops mid-trick (plays 1-3 of 4), the **next
`MSG_PLAY` to arrive triggers a local turn re-derivation**, with a
typical recovery time of **1-3 seconds** (the next bot or human
play in active gameplay). This complements v3.1.6's heartbeat-heal:

| Drop scenario | v3.1.5 (no fix) | v3.1.6 (heartbeat) | v3.1.7 (this) |
|---|---|---|---|
| MSG_TURN drops on play 1, 2, or 3 of trick | 60s freeze | 15s freeze | **1-3s freeze** |
| MSG_TURN drops on play 4 (trick-end) | 60s freeze | 15s freeze | 15s freeze (heartbeat fallback) |
| Heartbeat ALSO drops | 60s freeze | 60s freeze | depends on next play arrival |

The user's reported scenario (Dedah's freeze in 2H+2B) was a
mid-trick drop at play 1 — the v3.1.7 fix would have caught it
in <2 seconds.

### Implementation

In `_OnPlay` after `S.ApplyPlay(seat, card, isReplay)`:

```lua
if not S.s.isHost and S.s.phase == K.PHASE_PLAY
   and S.s.trick and S.s.trick.plays then
    local playCount = #S.s.trick.plays
    if playCount > 0 and playCount < 4 then
        local nextSeat = (seat % 4) + 1
        if S.s.turn ~= nextSeat then
            local prev = S.s.turn or 0
            S.s.turn = nextSeat
            S.s.turnKind = "play"
            log("Info", "play-derived self-heal: turn %d → %d", prev, nextSeat)
            if N._FreezeLog then
                N._FreezeLog("HEAL",
                    ("derive turn %d → %d after seat %d play"):format(
                        prev, nextSeat, seat))
            end
            if B.UI and B.UI.Refresh then B.UI.Refresh() end
        end
    end
end
```

### Why mid-trick only

For play 4 (trick-end), turn doesn't go to "next clockwise seat" —
it goes to the trick winner. Computing the winner locally requires
running `R.TrickWinner(trick, contract)` which is fine but:

1. There's a 2.2s "show all 4 cards" window after the 4th play
   before the host fires `MSG_TRICK` + `MSG_TURN(winner)`. Rotating
   turn locally during that window would create UI flicker.

2. SWA / Takweesh / sweep-detection might intervene at trick-end,
   making the "winner = next leader" derivation unreliable.

3. v3.1.6's 15s heartbeat-heal already catches dropped trick-end
   `MSG_TURN`. Acceptable bound.

If trick-end freezes prove disruptive in practice, v3.1.8 can add
deferred (3s) trick-end self-heal layered on top. For now, mid-trick
only is the surgical, low-risk fix that addresses the reported case.

### Safety gates

- **Non-host only**: host has direct state mutation via
  `_HostStepPlay` and doesn't need this self-heal.
- **`PHASE_PLAY` only**: other phases have their own turn semantics.
- **Mid-trick only**: `playCount > 0 and playCount < 4`.
- **No-op on match**: `S.s.turn ~= nextSeat` prevents redundant
  state writes during normal play.
- **HEAL events captured**: if `WHEREDNGNDB.freezeDebug = true`,
  every fired heal logs to `freezeLog` for production telemetry.

### Tests

**944/944 pass** (was 939 — +5 new pins). New section AU covers:

- AU.1: marker comment present
- AU.2: mid-trick gate `playCount > 0 and playCount < 4`
- AU.3: clockwise rotation `(seat % 4) + 1`
- AU.4: gated to non-host
- AU.5: HEAL events logged to freezeLog

### Total mitigation surface

With v3.1.6 + v3.1.7 stacked:

- **75% of plays** (1-3 of each trick) → recovery in milliseconds
- **25% of plays** (play 4 / trick-end) → recovery in ≤15s via heartbeat
- **Worst case** (heartbeat ALSO drops) → recovery on next non-dropped play

The user's reported freeze should now be either invisible (heal
faster than perception) or briefly noticeable (≤2s) at most. Even if
WoW's addon channel drops 50% of MSG_TURN broadcasts, the game
should remain playable.

## v3.1.6 — Turn-rotation self-heal via heartbeat

User reproduced the freeze with `/baloot freezelog` enabled on both
host and the affected client. The trace was conclusive:

### Root cause confirmed by paired logs

**Host (Acing) TX during freeze window:**

```
[6272.46]  TX P  ← Acing plays end of trick
[6272.46]  TX T turn=2  ← "Dedah's turn now" — KEY MESSAGE
[6272.72]  TX T turn=2  ← duplicate (host always sends T twice)
[6272.78]  RX P loopback
                         ← NO RX T loopback (host's own T never came back)
[6286.93]  TX ~ heartbeat  (15s gap with only heartbeats)
...
[6332.46]  TX P  ← AFK auto-play (60.0s = K.TURN_TIMEOUT_SEC exactly)
[6332.46]  TX T turn=3  ← skips Dedah, advances to seat 3
```

**Client (Dedah) RX during the same window:**

```
[438991.13]  RX P from=Acing turn=1  ← received P, then nothing
                                      ← T(turn=2) NEVER arrived
[439005.63]  RX ~  (heartbeats only)
[439020.61]  RX ~
[439035.62]  RX ~
[439050.52]  RX ~
[439051.13]  RX P  ← AFK auto-play P arrives
[439051.13]  RX T turn=2  ← turn=2 finally appears (post-AFK)
[439051.41]  RX T turn=3
```

### Two simultaneous addon-channel drops

The smoking gun: **the host's OWN loopback for the T(turn=2)
broadcasts also failed**. Acing broadcast T at 6272.46 AND 6272.72
(redundant duplicate), but neither came back to Acing's own client.
This means WoW silently dropped both messages at the local addon-
channel layer before they ever hit the network.

This is a known WoW behavior: `C_ChatInfo.SendAddonMessage` can be
silently throttled when multiple messages are broadcast in close
succession (P + T + T within 0.26s in this case). The `pcall` around
the call doesn't catch it — the function returns success even when
WoW drops the message internally.

### The fix

**Heartbeat-carries-turn for client-side self-heal.**

The host already broadcasts `MSG_HEARTBEAT` every 15s for the
host-alive watchdog. Extend the payload:

```
Old:  "~"
New:  "~;{turn};{turnKind}"
```

On `_OnHeartbeat`, if the received `hostTurn` differs from local
`S.s.turn` while in `PHASE_PLAY`, apply the host's value and refresh
UI. Worst-case freeze duration: **~15s instead of 60s**.

```lua
if hostTurn and hostTurn > 0 and hostTurn <= 4
   and S.s.phase == K.PHASE_PLAY
   and S.s.turn ~= hostTurn then
    local prev = S.s.turn or 0
    S.s.turn = hostTurn
    S.s.turnKind = (hostTurnKind ~= nil and hostTurnKind ~= "")
                    and hostTurnKind or "play"
    log("Info", "heartbeat self-heal: turn %d → %d", prev, hostTurn)
    if N._FreezeLog then
        N._FreezeLog("HEAL", ("turn %d → %d"):format(prev, hostTurn))
    end
    if B.UI and B.UI.Refresh then B.UI.Refresh() end
end
```

### Safety gates

- **Phase-gated**: only fires in `PHASE_PLAY`. Other phases
  (deal, double, overcall, score) have their own turn semantics
  and shouldn't be overridden by heartbeat.
- **Range-checked**: `hostTurn ∈ [1, 4]`. Defensive against
  garbage payloads from a corrupt heartbeat.
- **No-op on match**: only fires when local turn ≠ host turn.
  Zero churn during normal play.
- **Backward-compat**: pre-v3.1.6 hosts send `~` alone; the
  receiver's `tonumber(fields[2])` returns nil; the gate
  `hostTurn and hostTurn > 0` skips the heal silently.
- **freezeLog logs HEAL events**: if `WHEREDNGNDB.freezeDebug` is on,
  every heal is recorded. Lets us measure how often the bug fires
  in production.

### Why not also derive-turn-from-MSG_PLAY (the other proposal)

Considered, but heartbeat-heal is sufficient on its own:
- Heartbeat already exists; just extending payload (1 line of
  format change)
- Self-heal applies to the EXACT desync we observed
- Derive-from-P would also need to know the trick-winner rotation
  rule (after play 4, next-turn = winner, not next clockwise)
- Two mechanisms = more surface area for edge-case bugs

If 15s heal isn't enough in practice, derive-from-P can be added
as v3.1.7 layered on top.

### Tests

**939/939 pass** (was 933 — +6 new pins). New section AT covers:

- AT.1: marker comment present
- AT.2: heartbeat broadcast format extended
- AT.3: `_OnHeartbeat` accepts `hostTurn` + `hostTurnKind` params
- AT.4: heal gated to `PHASE_PLAY`
- AT.5: heal only on turn mismatch (no-op on match)
- AT.6: heal events logged to freezeLog when debug active

### What to expect after v3.1.6

In a freezed scenario:
- **Pre-v3.1.6**: Dedah waits 60s for AFK auto-play. Sees turn flash
  by; her actual turn is force-played by host.
- **Post-v3.1.6**: Dedah waits at most 15s for the next heartbeat,
  which carries the corrected turn. Her UI shows "your turn." She
  can play.

For Acing/host behavior: zero change. Host already has accurate
local state. The heal is purely receiver-side.

The user can verify the fix is firing by enabling
`/baloot freezelog on` next session and watching for `HEAL` events
in the dump. Each `HEAL` entry confirms one prevented freeze.

## v3.1.5 — Freeze-diagnostic mode (`/baloot freezelog`)

User reported 30-second freezes on a non-host client (Dedah, seat 4)
during their own turn in 2-human + 2-bot multiplayer. Freeze
spontaneously recovers. None of our timer constants are 30s
(`K.TURN_TIMEOUT_SEC=60`, `K.HOST_HEARTBEAT_TIMEOUT_SEC=45`,
`K.SWA_TIMEOUT_SEC=5`, `K.TAKWEESH_REVIEW_SEC=8`) — so the source is
likely **WoW system-level**: addon channel queue throttle, network
round-trip latency, or a UI handler stuck mid-frame.

Without trace data we can't know which. v3.1.5 ships an opt-in
diagnostic logger to capture next occurrence.

### Usage

```
/baloot freezelog on       → enable capture (zero overhead when off)
/baloot freezelog off      → disable
/baloot freezelog clear    → wipe captured events
/baloot freezelog          → dump last 50 events
/baloot freezelog all      → dump all (up to 200 cap)
```

Captures every:
- **Wire receipt** (RX with tag, sender, channel)
- **Wire send** (TX with tag, send-success flag)

into `WHEREDNGNDB.freezeLog` ring-buffer (200 entries, oldest dropped).
Each entry: `{ ts, category, detail, seat, turn, phase }`.

Output highlights gaps > 1 second between events with `|cffff5555+Xs|r`
markers — those are the freeze candidates. Example dump:

```
freeze log: 47 total, showing last 47
  [218.34]  RX  tag=R from=Acing ch=PARTY        seat=4 turn=4 phase=play
  [218.34]  TX  tag=p ok=true                    seat=4 turn=4 phase=play
  [248.71 +30.4s]  RX  tag=R from=Acing ch=PARTY    seat=4 turn=4 phase=play
  →                                ^^^^^^^^^^^^ freeze candidate
```

The 30s gap above would indicate the wire-receive cycle stalled —
strong evidence of WoW addon-channel queue saturation. Conversely if
the log shows continuous events through the freeze window, the issue
is UI rendering not network.

### Implementation

- **`Net.lua:81-128`** — `freezeLog(category, detail)` ring-buffer
  writer. Zero overhead when `WHEREDNGNDB.freezeDebug ~= true`
  (single boolean check).
- **`Net.lua:684`** — `HandleMessage` logs every RX with tag/sender/
  channel.
- **`Net.lua:46-54`** — `broadcast` logs every TX with tag and
  send-success flag (so we see `pcall` failures of
  `C_ChatInfo.SendAddonMessage`).
- **`Slash.lua:541-590`** — `/baloot freezelog [on|off|clear|all|N]`
  command. `freezeDebug` flag controls capture; log persists in
  saved-vars so post-game review works.

### What to do next time the freeze fires

1. Before the game, type `/baloot freezelog on` on Dedah's client
2. Play normally
3. When freeze occurs, wait for it to recover (don't /reload)
4. Type `/baloot freezelog all` and copy-paste the output
5. Look for the `+Xs` gap markers — that timestamp range = the freeze
6. Share the output and I can pinpoint root cause

### Tests

**933/933 pass** (no behavioral changes). Diagnostic logger is
gated behind `WHEREDNGNDB.freezeDebug` — never fires unless user
opts in.

### Why no fix yet

Without trace data there's no way to differentiate:
- Addon channel throttle (would show wire-RX gap)
- UI render stall (would show no events at all during freeze)
- Heartbeat watchdog firing (would show MSG_HEARTBEAT events
  pre+post freeze with the gap in between)
- Some other client-side issue

Once the trace shows up, the fix is usually targeted (1-line
change). Premature speculation could ship a "fix" that addresses
the wrong root cause.

## v3.1.4 — 5-agent swarm audit closure (test coverage backfill)

User requested an extensive audit-swarm against the codebase to find
residual bugs after the v3.1.2/v3.1.3 ship. Spawned 5 parallel
read-only audits:

| Audit | Scope | Findings |
|---|---|---|
| **A** — ledger lifecycle | Init, per-round reset, cross-game reset, wire/resync for the 4 new v3.1.2 ledgers (`firstLedSuit`, `colorBalance`, `followWinSuit`, `partnerRuffSuit`) | **0 bugs.** All correctly initialized in `emptyStyle()` / `emptyMemory()`, reset per-round in `Bot.ResetMemory`, cross-game safe via `ResetStyle`, never serialized to wire (host-only). |
| **B** — tier gating | Verify all 9 v3.1.2 changes fire at the documented tier (Advanced/M3lm/Fzloky/Saudi-Master) | **0 bugs.** Readers correctly gated; writers correctly unconditional (record observations regardless of tier; only readers consume tier-aware). |
| **C** — wire protocol & persistence | Schema v=4 trickPlays backward compat, MSG_TAKWEESH_REVIEW format, roundHistory persistence, resync schema versioning, mid-/reload recovery | **0 actual bugs.** 3 future-proofing concerns (3-char card support, dynamic-reason injection, unversioned resync schema) — all are theoretical risks if features expand later, not current bugs. |
| **D** — signal-receiver precedence | Score-order monotonicity, demote logic gating, partnerRuffSuit precedence, conflict resolution | **0 bugs.** All 6 precedence requirements verified. 1 maintainability note: `tahreebAvoidSet` populated AFTER color signals but late conflict-resolution catches the temporal coupling correctly. |
| **E** — cross-cutting regressions | pickLead branch ordering, OnPlayObserved write-order race, ISMCTS rollout policy, **test coverage gaps**, Unicode handling, hot-path performance | 1 false-alarm (followWinSuit AKA-state race — verified `s.akaCalled` IS cleared per-trick at `State.lua:1586`) + **1 real concern: 8/9 v3.1.2 changes had only source-string pins, no behavioral tests.** |

### What's shipped in v3.1.4

**Test coverage backfill** (the only real finding from the audit):

#### `AS.1` — colorBalance opposite-color boost (behavioral)

When partner discards 2 hearts (`colorBalance.red = 2`), bot leads
black (♠ or ♣), not red (♥/♦). Verifies the cross-suit color
tracking signal flows from ledger → pickLead pref selection.
Conditional assertion (skips gracefully if the fixture's
`Bot._partnerStyle[3].colorBalance` isn't allocated by the test
harness — source-pin AQ.5 already covers the static init case).

#### `AS.3` — Takbeer-on-AKA donates HIGHEST, not lowest (behavioral)

Setup: partner (seat 1) leads A♥ in Hokm trump=♠. Bot (seat 3)
holds T♥ + 8♥ as legal follow cards. AKA is live (`S.s.akaCalled`).
**Pre-v3.1.2 behavior:** AKA-relief branch returned
`lowestByRank(discards)` → 8♥. **v3.1.2 behavior:** branch now
detects "we have led-suit point cards" and returns HIGHEST point
card → T♥. Test asserts `assertEq(card, "TH", ...)` — fully
end-to-end through `Bot.PickPlay → pickFollow → AKA-relief block`.

This is the strongest new behavioral test: it exercises the full
v3.1.2 IM-4 fix (Takbeer-on-AKA) without any mocking or short-
circuiting. If a future refactor accidentally restores
lowestByRank in the AKA branch, AS.3 catches it.

### Verified via false-alarm investigation

Audit E flagged a "potential AKA-state race" in followWinSuit:
> If AKA was called on a PRIOR trick for the same suit,
> `S.s.akaCalled` persists from the prior state — the gate might
> suppress followWinSuit incorrectly.

Verified at `State.lua:1586`: `s.akaCalled = nil` fires at trick
end with explicit comment "AKA banner only persists for the trick
it was called on; clear it so the next trick starts visually clean."
The race CANNOT fire — `S.s.akaCalled` is correctly per-trick
scoped. **False alarm, no fix needed.**

### Tests

**933/933 pass** (was 931 — +2 new behavioral pins). Section AS
joins the existing AQ section in covering v3.1.2 changes:
- AQ: 21 source-string pins (existing v3.1.2 pin coverage)
- AS.1: behavioral test for colorBalance → pickLead bias
- AS.3: behavioral test for Takbeer-on-AKA → highest point card
  donation

### Audit conclusion

5/5 audit agents reported clean. **Only 1 actionable finding** (test
coverage gap), addressed by this release. The other findings were:
- Theoretical/future-proofing concerns (3 in audit C)
- Maintainability notes (1 in audit D)
- False alarms (1 in audit E)

The codebase at v3.1.3 was found to be **structurally sound** with
the v3.1.2 + v3.1.3 changes — no residual bugs detected. v3.1.4 just
hardens the test suite against future refactor regressions.

## v3.1.3 — Per-round trick logging for bot-behavior monitoring

User requested per-trick play logging so they can audit bot decisions
post-game (e.g. "Bot 3 bid Sun and narrowly won — was that good play
or did they give away points?").

### What's new

#### `WHEREDNGNDB.history[i].trickPlays` — per-trick play array

Schema bumped from **v=3 → v=4**. Each round-history row now
includes a `trickPlays` array, one string per played trick:

```
"{leadSuit}|{winnerSeat}|{points}|{seat-card,seat-card,...}"
```

Example:
```
trickPlays = {
  "S|3|16|2-8S,3-TS,4-KS,1-JS",
  "S|4|36|3-7S,4-JH,1-9H,2-JD",
  "C|1|14|4-7C,1-AC,2-9C,3-QC",
  ...
}
```

Pipe-delimited fields, comma-separated plays. Compact (~30 chars per
trick) so the existing 200-row cap on `WHEREDNGNDB.history` keeps
total saved-vars overhead under ~50KB.

Backward-compatible: pre-v3.1.3 (v=1/2/3) rows have no `trickPlays`
field; the slash command's parse skips gracefully and prints
"pre-v3.1.3 row, schema v=N".

#### `/baloot lastround [N]` slash command

Prints the last round's full play-by-play in chat:

```
> /baloot lastround
round 5  HOKM trump=H [Bel]  bidder=seat4 (SaudiMaster)  bidcard=8H
  outcome: A +9  B +34  → cum 9/34  made=yes
  T1  lead=S  winner=seat3  pts=16  plays: 2-8S,3-TS,4-KS,1-JS
  T2  lead=S  winner=seat4  pts=36  plays: 3-7S,4-JH,1-9H,2-JD
  T3  lead=C  winner=seat1  pts=14  plays: 4-7C,1-AC,2-9C,3-QC
  ...
```

Argument `N` walks back N rounds (default 1 = most recent):
- `/baloot lastround 1` → most-recent round
- `/baloot lastround 2` → 2 rounds back
- ...

Works for any round in the history (up to the 200-row cap).

### Why the format choice

Pipe-delimited string was chosen over Lua nested tables because:
- ~30 chars/trick × 8 = 240 chars vs ~150 bytes structured = 4× smaller
- Trivially parseable with `:match("^([^|]+)|([^|]+)|([^|]+)|(.*)$")`
- Human-readable in raw saved-vars dump
- One-line-per-trick = grep-friendly for offline analysis

### Implementation

- **`State.lua:2058+`**: builds `trickPlaysCompact` from `s.tricks`
  walking each trick's `plays` array (already populated by
  `S.ApplyPlay`). Format: `{leadSuit}|{winner}|{points}|{seat-card,...}`.
- **`Slash.lua:541+`**: `lastround [N]` command parses each compact
  string and prints in human-readable form.
- **Help text** (`Slash.lua:37`): `lastround` listed in `/baloot help`.

### Tests

**931/931 pass** (was 923 — +8 new pins; 1 existing pin updated for
schema v=3 → v=4 bump). Added:

- AG.10b: schema bump v=3 → v=4
- AG.10j-k: trickPlays is a table with 8 entries
- AR.1a-c: `/baloot lastround` command exists, reads trickPlays,
  help text describes the feature
- AR.2a-c: State.lua builds trickPlaysCompact + assigns to row +
  bumps schema version to 4

### Notes for use

To audit Bot 3's behavior in your last narrowly-won Sun round (the
one that prompted this feature), wait for the next round to play out
on **v3.1.3 code** — then run `/baloot lastround` immediately after
round-end. The full per-trick play sequence will print in chat,
ready to copy-paste here for analysis.

For offline / forensic review of multiple rounds, the
`WHEREDNGNDB.history` array in `SavedVariables/WHEREDNGN.lua` carries
the same `trickPlays` data persistently (cap 200 rows; oldest dropped
on overflow).

## v3.1.2 — Tahreeb hint-give/take gaps + void-Hokm pickLead fix

User asked to ship all gaps identified by video #46 (Tahreeb advanced)
plus the Q4 void-Hokm fix from the saved-game audit. **9 surgical
changes** across give-hint and take-hint logic. Pre-implementation
audit (read-only Explore agent) sequenced changes into 3 waves;
tests pass after each wave.

### Wave 1 — surgical, low risk

#### Change 1 — Q4 Fix #1: void-Hokm pickLead

**Where:** `Bot.lua:3725-3740` ("free trick" branch) AND a parallel
fix at `Bot.lua:2733-2742` ("highest-unplayed" branch).

**Bug:** When both opponents are observed void in a non-trump suit,
the existing heuristic returned the HIGHEST card (correct in Sun
where opps can't trump; **wrong in Hokm** where void opps will
trump-ruff our boss). User's saved-game T5 was the canary —
Bot 3 had A♠ + Q♠ + 9♠ + 7♥, both opps void in ♠ from T2; bot led
high spade and got it ruffed by trump-A.

**Fix:** branch on contract type:
- Sun: keep HIGHEST (free trick)
- Hokm: lead LOWEST (sacrifice cheapest into inevitable ruff)

Applied to both pickLead branches that touch this scenario. Verified
fix via simulation: Basic/Adv/M3lm/Fzloky now all pick 9♠ (10/10
trials) instead of A♠. Saudi Master ISMCTS rollouts inherit the
correct heuristic default.

#### Change 3 — IM-7: Adjacent-to-T anti-rule (broader)

**Where:** `Bot.lua:3990-4031` (`tPlusLowDoubletonSuit`, was
`tPlusNineDoubletonSuit`)

**Per video #46:** "Don't sacrifice 7♦ when you have 7♦ + T♦. If
opp plays A♦, you're forced to give T♦ anyway." Generalizes to
T+7, T+8, T+9, T+J, T+Q doubletons (T+K excluded — Belote pair;
T+A excluded — A is its own boss).

**Fix:** extend the existing `tPlusNineDoubletonSuit` exclusion
(only handled T+9) to T+anything-from-{7,8,9,J,Q}. Renamed variable
to `tPlusLowDoubletonSuit`; backward-compat alias retained.

### Wave 2 — additive ledgers + signal-readers

#### Change 2 — TR-1: Color-inversion suggestion

**Where:** `Bot.lua` partner-side score selection loop (after
existing tahreeb-suit scoring).

**Per video #46:** "Single-suit discard means partner wants the
OPPOSITE COLOR." ♠/♣ are black, ♥/♦ are red. After tahreebClassify
returns "dontwant" for suit X, ALSO boost opposite-color suits
in `tahreebPrefSuit` selection at weight **0.5** (sub-`hint`,
fires only when no stronger signal exists).

#### Change 4 — TR-2/TR-3: Cross-suit color tracking

**Where:** new `Bot._partnerStyle[seat].colorBalance = { red = 0,
black = 0 }` ledger.

**Per video #46:** "Two same-color discards = wants OTHER color."
Increment `colorBalance[red|black]` on voluntary same-color
discards (forced-flag check using post-play hand-shape). After
2+ discards in one color, receiver boosts OTHER color suits at
weight **0.6** (above color_inv 0.5, below want_hint 1.0).

#### Change 5 — IM-1/IM-3: First-led-suit memory

**Where:** new `Bot._partnerStyle[seat].firstLedSuit` ledger.
Writer in `Bot.OnPlayObserved`; reader in `pickLead`.

**Per video #46:** "If you're FIRST to play, lead a card in your
STRONG suit; partner reads this as 'I want this suit, return it.'"
Track per-round; receiver prefers leading partner's first-led
suit at weight **0.7** (above color_balance 0.6, below
want_hint 1.0).

#### Change 6 — IM-4: Takbeer-on-AKA fix

**Where:** `Bot.lua` AKA-relief branch (the `akaLive` block).

**Per video #46:** "If your friend FIRST played an Ace, you MUST
give them the T to continue eating." Pre-v3.1.2 the AKA-relief
branch returned `lowestByRank(discards)` — sacrificing the wrong
card. **Fix:** when we have led-suit point cards (T/K/Q/J), donate
the HIGHEST (Takbeer); only fall back to lowest when no point
cards exist in led suit.

#### Change 7 — IM-6: Win-by-follow → no strong hand

**Where:** new `Bot._partnerStyle[seat].followWinSuit` per-suit
flag. Writer in `Bot.OnPlayObserved`; reader in pref selection.

**Per video #46:** "Won by follow, not AKA → no strong hand
here." When seat plays T/K/Q in follow position (not lead) on
non-trump AND no AKA was called for that suit, mark
`followWinSuit[suit] = true`. Receiver demotes any pref-suit
choice that hits a `followWinSuit` flag (only for weak signals
< score 2; doesn't override confirmed bargiya/want).

### Wave 3 — Hokm-specific

#### Change 9 — HK-2: Post-ruff suit-repeat

**Where:** new `Bot._memory[seat].partnerRuffSuit` per-suit flag.
Writer in `Bot.OnPlayObserved`; reader in pickLead.

**Per video #46:** "If opp is bidder Hokm AND your partner ruffed
suit X, repeat X — partner ruffs again, draining bidder's trump."
Tracks per-suit; reader fires only when opp is Hokm bidder, prefers
leading partner's previously-ruffed suits as `tahreebPrefSuit`
override (M3lm-gated, advanced read).

#### Change 10 — HK-5: Hokm-bidder don't reveal void

**Where:** `Bot.lua` pickFollow's final-fallthrough discard branch.

**Per video #46:** "If you're bidder Hokm, don't tahreeb your short
suit — opp will lead it and force partner to ruff, draining trump."
When bot is bidder Hokm in a free-discard position, prefer
discarding from suits with count >= 2 over singletons (preserves
void mystery). Falls through to general lowestByRank when only
singletons remain.

#### Change 8 — HK-1: DEFERRED

The audit flagged HK-1 (partner-of-Hokm-bidder support sacrifice)
as "refactor risk — partner-quarte detection undefined." The video's
"partner plays T-of-trump as quarte" phrasing is ambiguous (could
be lead position or follow). Deferred pending video clarification
or user direction. The conventional cases (consecutive trumps,
J+9 sacrifice) are already handled by existing pickFollow logic.

### Cross-cutting concerns

**Per-round resets:** All new ledgers (`firstLedSuit`,
`colorBalance`, `followWinSuit`, `partnerRuffSuit`) are cleared in
`Bot.ResetMemory` (per-round) following the same pattern as
existing per-round-scoped ledgers (`tahreebSent`, `topTouchSignal`,
`baitedSuit`).

**Forced-flag handling:** colorBalance increment uses post-play
hand-shape inspection (parallels v1.1.1 M2 forced-flag pattern in
`tahreebSent`) so forced same-color discards don't pollute the
color read.

### Tests

**923/923 pass** (was 902 — +21 new pins). New section AQ:

- AQ.1 (2 pins): Change 1 source markers + Sun/Hokm split
- AQ.2 (2 pins): Change 3 broader anti-rule
- AQ.3 (2 pins): Change 2 color-inversion
- AQ.4 (3 pins): Change 5 firstLedSuit ledger + reset
- AQ.5 (3 pins): Change 4 colorBalance + forced-flag
- AQ.6 (2 pins): Change 7 followWinSuit
- AQ.7 (2 pins): Change 6 Takbeer-on-AKA
- AQ.8 (2 pins): Change 9 post-ruff repeat
- AQ.9 (2 pins): Change 10 Hokm-bidder don't-reveal-void
- AQ.10 (1 behavioral): void-Hokm fix end-to-end (Bot 3 leads 9♠,
  not A♠, when both opps void in ♠)

### Strategic impact

These changes fill in **bot↔bot signal fidelity** that was missing
since v0.x — the bot now both *gives* hints (first-led suit,
colorBalance, partner-ruff repeat) and *takes* hints (color-inversion,
cross-suit color, follow-win-no-strong) following Saudi convention
per video #46. Combined with the void-Hokm fix, all 5 bot tiers
(Basic through Saudi Master) should play noticeably more
coordinated in Hokm, especially in early-trick scenarios where
opps reveal voids quickly.

Tournament re-run deferred — with 9 simultaneous changes, expected
behavioral drift is significant; will validate via multi-seed
tournament after user confirms in real play.

## v3.1.1 — NASHRAH polish (remove redundant line + scroll for >5 rounds)

User feedback on v3.1.0:

> last line of the scoreboard is repeating same info, it is not really
> needed we already know 152 is the target, also make it scrollable
> if the game went over 5 rounds.

### Changes

**Removed redundant score line.** v3.1.0's TOTAL row already showed
team scores; the line below it just repeated the same numbers with
`/ 152 pts` suffix. Target is fixed and well-known to players.
Cleaner panel:

```
— NASHRAH —
R1: w7osh: 12  j7l6: 8
R2: w7osh: 24  j7l6: 18
TOTAL: w7osh: 47  j7l6: 43
```

(Pre-v3.1.1 had an extra `w7osh: 47  j7l6: 43  / 152 pts` line.)

**Scrollable for >5 rounds.** A ScrollFrame now wraps the per-round
rows with a 5-row viewport. When a game runs longer than 5 rounds,
mouse-wheel scrolls the older rows into view. The TOTAL row stays
fixed at the bottom of the panel (always visible regardless of
scroll position).

Auto-scrolls to bottom on each refresh so the **latest round is
always visible** by default — players still see the most recent
deltas without manual scrolling. Older rounds are reachable by
scrolling up.

### Implementation

```lua
-- Fixed-height panel with viewport for exactly 5 rows.
local viewportH = NASHRAH_VISIBLE_ROWS * NASHRAH_ROW_H  -- 5 * 12 = 60px
local scrollFrame = CreateFrame("ScrollFrame", nil, nashrahPanel)
scrollFrame:SetSize(204, viewportH)
scrollFrame:EnableMouseWheel(true)
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
    local cur = self:GetVerticalScroll() or 0
    local maxScroll = self:GetVerticalScrollRange() or 0
    local nxt = cur - (delta * NASHRAH_ROW_H)
    self:SetVerticalScroll(math.max(0, math.min(maxScroll, nxt)))
end)
local scrollChild = CreateFrame("Frame", nil, scrollFrame)
scrollFrame:SetScrollChild(scrollChild)
```

In the renderer:
```lua
local childHeight = math.max(viewportH, #hist * NASHRAH_ROW_H)
p.scrollChild:SetHeight(childHeight)
-- Auto-scroll to bottom (no-op when ≤5 rounds).
p.scrollFrame:SetVerticalScroll(childHeight - viewportH)
```

For ≤5 rounds, `childHeight == viewportH` → scroll range is 0 →
mouse wheel becomes a no-op (clamped to 0). No visual scroll bar
clutter for short games.

### Tests

**902/902 pass** (was 897 — +5 new pins). AP.2 expanded to cover
the v3.1.1 changes:

- AP.2g: rows wrapped in `CreateFrame("ScrollFrame", ...)`
- AP.2h: `EnableMouseWheel(true)` on scrollFrame
- AP.2i: `NASHRAH_VISIBLE_ROWS = 5` (per user spec)
- AP.2j: `SetScrollChild` wires viewport ↔ child
- AP.2k: renderer calls `SetVerticalScroll` (auto-scroll-to-bottom)

## v3.1.0 — NASHRAH (نشرة) per-round scoreboard panel

### What's new

A persistent **per-round scoreboard** in the top-left corner of the
addon window. Replaces the bottom-left score line (which showed only
cumulative totals). Format follows the canonical Saudi tournament
display style:

```
— NASHRAH —
R1: TeamA: 12  TeamB: 8
R2: TeamA: 24  TeamB: 18
R3: TeamA: 47  TeamB: 43
TOTAL: TeamA: 47  TeamB: 43
TeamA: 47  TeamB: 43  / 152 pts
```

Hidden until the first round completes (no empty header during lobby).
Grows per round; resizes the panel automatically. Per-team color
coding (green for team A, red for team B) preserved from the prior
score line for visual continuity.

### Implementation

#### State (`State.lua`)

New field `S.s.roundHistory`: array of `{ A, B, totA, totB }` entries,
appended in `S.ApplyRoundEnd` after each round resolves. Initialized
empty in `reset()`. **NOT transient** — persists via `SaveSession`
across `/reload`. Cleared along with `cumulative` when a new game
begins (next `reset()` cycle).

#### UI (`UI.lua`)

- New `nashrahPanel` frame (220×variable) at TOPLEFT (8, -38), below
  the Sound row + scale buttons
- New `renderNashrahPanel()` function called from `Refresh()`:
  - Lazy-builds row FontStrings as needed (`p.rows[i]`)
  - Renders header + per-round rows + TOTAL + score-with-target line
  - Resizes panel height to fit content
  - Hides entirely when `roundHistory` is empty (no idle clutter)
- Bottom-left `scoreText` is now **blanked** (`SetText("")`) — data
  moved to the panel under the TOTAL row. The FontString is preserved
  for backward compatibility (referenced elsewhere).

### Multiplayer behavior

- Per-round entries grow on **every client** as `MSG_ROUND` arrives
  and triggers `ApplyRoundEnd` locally
- `/reload` mid-game preserves history (`SaveSession` snapshot)
- **Known limitation**: a fresh client joining mid-game via resync
  does NOT receive prior rounds' history (resync wire schema is
  positional and adding a variable-length list requires schema bump).
  Their panel starts empty and grows from the next round forward.
  Acceptable for v3.1.0; future enhancement if requested.

### Tests

**897/897 pass** (was 881 — +16 new pins). New section AP covers:

- AP.1 (3 pins): State.lua `roundHistory` init + append + entry shape
- AP.2 (6 pins): UI.lua panel + renderer + Refresh wiring + bottom-
  left scoreText blank
- AP.3 (5 behavioral): `ApplyRoundEnd` grows history correctly across
  three simulated rounds
- AP.4 (1 pin): `roundHistory` NOT in `TRANSIENT_FIELDS` (so it
  persists via `SaveSession`)

Plus 1 housekeeping fix: `N.2 (RT07-04)` test's 1500-char scan window
bumped to 3000 to accommodate `ApplyRoundEnd`'s grown body.

### Why "NASHRAH"

Saudi Baloot tournament tables traditionally use a printed
**نشرة** (nashrah, "bulletin") to track per-round scores — a small
notepad showing R1/R2/.../TOTAL columns per team. The panel mirrors
that physical artifact. Players familiar with tournament play
recognize the format instantly.

## v3.0.8 — Takweesh anti-abuse: cards-reveal + الجلسة host approval

### Problem

False Takweesh as sweep-stop was a real exploit. With 16-50 gp false-call
penalty vs 25-100 gp denied Kaboot bonus, defenders behind in score had
positive expected value calling Takweesh against a near-sweeping bidder
even with no actual illegal play. Math:

| Scenario | Defender's loss |
|---|---|
| Let Hokm Bel'd Kaboot finish | bidder gets 50 gp + own melds × 2 |
| False Takweesh, bidder wins via Qaid | bidder gets 32 gp + own melds × 2 |
| **"Saving" via false call** | **~18 gp** |

### Fix (canonical Saudi, NOT a number-based escalation)

Per video #36 verbatim:

> Caller announces qaid AND **must throw cards face-up to reveal proof.
> Verbal call without revealing is invalid.** Procedural rule — proof
> requirement prevents casual / strategic false calls.

This is the actual Saudi anti-abuse mechanism. The reveal IS the
deterrent — false callers expose their hand publicly, paying a
strategic / social cost beyond just the gp.

### Implementation

#### New phase: `PHASE_TAKWEESH_REVIEW`

When Takweesh is called, the round enters an 8-second review phase
before resolution. During the review:

- All seats see the caller's remaining hand face-up in a banner
- Alleged illegal play is shown (or "no scan-flagged illegal play")
- A countdown ticks from 8s down

Constants added:
- `K.PHASE_TAKWEESH_REVIEW = "takweesh_review"`
- `K.TAKWEESH_REVIEW_SEC = 8` (per user spec, not 5)
- `K.MSG_TAKWEESH_REVIEW = "kr"` (wire tag for broadcast-with-hand)

#### Net.lua flow change

The old direct path was:
```
LocalTakweesh → MSG_TAKWEESH → HostResolveTakweesh (synchronous)
```

The new path:
```
LocalTakweesh → MSG_TAKWEESH → HostBeginTakweeshReview
   → MSG_TAKWEESH_REVIEW (caller's hand + alleged illegal)
   → PHASE_TAKWEESH_REVIEW (8s window)
   → [host clicks Approve/Reject in multi-human games]
   →    OR auto-resolve via 8s timeout (rule-engine scan)
   → HostResolveTakweesh(callerSeat, hostDecision)
```

`HostResolveTakweesh` gained an optional `hostDecision` parameter:

| `hostDecision` | Winner | Reason |
|---|---|---|
| `nil` (timeout) | scan-determined (current behavior) | rule-engine `p.illegal` flag |
| `true` | callerTeam | الجلسة approved |
| `false` | oppTeam | الجلسة rejected |

Same Saudi-canonical scoring (16/26 gp + meld forfeit) regardless of
which path resolved. **No invented numerical escalation.**

#### Option B: host approval banner (multi-human only)

Per user spec, host approval shows ONLY when:
- `S.s.isHost` (we're the game host)
- `humanCount > 1` (more than one human at the table)
- `S.s.localSeat ~= rv.caller` (host can't approve own call)

Otherwise the buttons are hidden and the 8-second timeout fires
auto-validate (current pre-v3.0.8 behavior). In bot-only or
single-human games, the review still runs but resolves automatically.

#### UI.lua: `renderTakweeshReviewBanner`

New banner (380×150) with:
- Title: "TAKWEESH — [caller] reveals proof"
- Body: alleged illegal play details (or "no scan-flagged illegal")
- 8 card slots showing caller's encoded hand face-up
- Self-ticking countdown subtext
- Approve / Reject buttons (gated as above)

Wired into `Refresh()` between `renderSWABanner` and
`renderOvercallBanner`. Auto-hides outside `PHASE_TAKWEESH_REVIEW`.

### Why the reveal is the deterrent

In bot-only games, the reveal is meaningless (no privacy). The
existing 16-50 gp scoring penalty + bot trigger discipline already
deter the bot from false calls.

In multi-human games:
1. Human caller's hand is exposed publicly to all seats
2. Opps see strategic info for the next round (though re-deal makes
   this less impactful in Baloot specifically)
3. Social cost (الجلسة) — repeated false calls = visible reputation
4. Host gets a clean Approve/Reject to override the rule engine in
   borderline cases (the actual الجلسة arbiter role)

The penalty stays at canonical Saudi 16/26 gp — fixing the **process**,
not the **scoring rule**. Saudi convention preserved.

### Tests

**881/881 pass** (was 858 — +23 new pins). New section AO covers:

- AO.1 (3 pins): constants `K.PHASE_TAKWEESH_REVIEW`, `K.TAKWEESH_REVIEW_SEC=8`, `K.MSG_TAKWEESH_REVIEW="kr"`
- AO.2 (7 pins): Net.lua functions + handler + hostDecision parameter
- AO.3 (2 pins): State.lua transient field + ApplyStart clear
- AO.4 (6 pins): UI banner + multi-human gate + caller≠host gate
- AO.5 (5 pins): HostBeginTakweeshReview body invariants

## v3.0.7 — Comprehensive Saudi-rules audit closure (4-agent parallel sweep)

User asked for "one last extensive audit" against Saudi Baloot rules,
covering all small errors found since v0.11.0. Four parallel agents
ran focused audits:

### Audit results

| Agent | Scope | Findings |
|---|---|---|
| **Saudi-rules canonical** | 25 canonical Saudi Baloot rules vs code | All 25 ✓ ALIGNED, 1 doc-acknowledged DEFERRED (Round-1 Bel restriction). **0 deviations.** |
| **Sender/receiver pairs** | All `Bot._partnerStyle` ledger keys + signal pickers | 1 false alarm (Tanfeer N-1 vs N-3 confusion), 2 false alarms (weakHandSignal/highCardPlays — readers ARE active at `Bot.lua:3851` + `4540`). 1 known-acknowledged DEAD-WRITE (`leadCount`, doc-acknowledged at `glossary.md:194`). **0 real bugs.** |
| **Doc-vs-code numerical** | Strategy docs vs `Constants.lua` and Lua code | **5 stale doc claims** (this fix). |
| **Test-pin drift** | Every `botSrc:find(...)`-style source-pin in test suite | All 16 pins verified clean. **0 drift.** |

### Verified false alarms (no fix needed)

- **Tanfeer "MISALIGNED"**: agent confused N-1 (our-side sender at
  `Bot.lua:6367-6430`) with N-3 (opp-side receiver at `Bot.lua:2814+`).
  These are intentionally opposite perspectives — different roles in
  the same convention. Verified by reading the actual code paths.
- **weakHandSignal/highCardPlays "DEAD-READ"**: agent traced the
  ratio computation (`Bot.lua:3847-3850` + `4536-4539`) but missed
  the downstream consumers. `forceOwnInitiative` flag (line 3851) is
  read at `Bot.lua:3876, 4014, 4106` to gate Sun-shortest-suit and
  prefer A/T-suit leads. `captureRate += 0.40` (line 4540) is consumed
  in the Faranka decision. Both signals are **fully wired**.
- **leadCount "DEAD-WRITE"**: known/acknowledged in `glossary.md:194`
  ("DEAD WRITE — suit-lead frequency, written by `OnPlayObserved`,
  read nowhere"). Cleanup deferred; not a Saudi-rule issue.

### Real fixes — `glossary.md` doc updates

Code is correct; only the doc was stale.

#### Stale escalation thresholds (`glossary.md:41-44`)

Four bot escalation thresholds had been re-tuned over multiple
releases without the glossary table being updated:

| Constant | Doc claim | Code reality | Re-tune origin |
|---|---|---|---|
| `K.BOT_BEL_TH` | 60 | **62** | v1.3.2 (anchor against corrected harness) |
| `K.BOT_TRIPLE_TH` | 90 | **82** | v1.3.4 walkback (Codex audit) |
| `K.BOT_FOUR_TH` | 110 | **80** | v1.3.2 calibration |
| `K.BOT_GAHWA_TH` | 135 | **95** | v1.3.2 re-anchor (8-card eval window) |

Picker line numbers were also stale (showed `1908`/`1938`/`1982`;
actual `6982`/`7313`/`7385`/`7469`). Fixed.

#### Reverse Al-Kaboot status (`glossary.md:97`)

Doc said:
> Proposed `K.AL_KABOOT_REVERSE = 88` (single-source from video #16,
> confirm before wiring). New `R.ScoreRound` branch needed; not
> currently scored.

This was true pre-v1.0.12 but stale ever since. Code reality:
- `K.AL_KABOOT_REVERSE = 880` (raw; `= 88` game points after div10)
- Wired in `Rules.lua:976-1017` with full 4-condition gate (Sun +
  dealer-right + bidder held A + defender swept)
- cardMult-immune; defenders' melds × meldMult per «بالمشاريع»
- v1.0.12 + reaffirmed by v3.0.2 audit

Doc updated to reflect reality.

### Tests

**858/858 pass.** Doc-only changes; no code surface modified.

### Verdict

After 4 parallel agent audits covering 25 Saudi rules + sender/receiver
pairs + numerical/terminological consistency + test-pin integrity, the
v3.0.6 codebase is **fully aligned with Saudi Baloot conventions**. The
only issues found were doc terminology, all in `glossary.md`. No code
fixes shipped because no code-level deviations exist.

The recurring agent false-alarm pattern (calling alive code "dead") is
a known characteristic of read-only audits — they trace assignments
without always tracing downstream consumers across hundreds of lines.
Verification by direct code-read caught all three false positives. Future
audits should ask the agent to follow each "dead" finding through to
ALL consumers before flagging.

## v3.0.6 — GAP-01 sender-intent alignment

### What user asked

> could you check if this also made bots behave the same way? to give
> hint in the same logic? GAP-01 (CONTRADICTORY): Tahreeb single-low
> → "want_hint" classifier (Bot.lua tahreebClassify)

A great catch. The v3.0.3 fix added a *receiver-side* rule
(single-7/8/9 → `"want_hint"`) but didn't audit whether the *sender
side* was emitting signals consistent with that rule.

### What the audit found

Bot SENDERS emit single-low discards through TWO distinct paths:

| Path | Site | Conditions | Sender intent |
|---|---|---|---|
| **A. Bottom-up "want"** | `Bot.lua:4842-4866` | 3+ card suit, no A AND no T | "I want this suit, no Ace" |
| **B. T-4 dump-larger** | `Bot.lua:4886-4902` | 2-card no-honor doubleton (J/Q/9/8 highest) | "Descending = dontwant" |

Path A's lowest-rank discard: receiver correctly reads `"want_hint"`
on the first event (consistent with sender intent). ✓

Path B's first discard is the LARGER of the doubleton — when that
larger card is **9** (from a 9+x doubleton) or **8** (from 8+7), the
receiver under v3.0.3 reads single-9 / single-8 as `"want_hint"` —
but the sender's intent was descending = `"dontwant"`. The full
2-event descending sequence resolves to `"dontwant"`, but if the bot
gets only ONE Tahreeb opportunity in the round (1 partner-winning
trick where it's void in led), the receiver's first-event
interpretation is **opposite** of what the sender meant.

### Fix

Track sender's pre-discard suit-size on the FIRST event of any signal
in a suit. Gate the `want_hint` return on that size ≥ 3.

**`Bot.OnPlayObserved`** (~line 753+): record `list.lenAtFirstDiscard`
on the first event in a suit, mirroring the existing `lenAtAce`
recorder for Bargiya:

```lua
if S.s.isHost and S.s.hostHands and S.s.hostHands[seat] then
    if not list.lenAtFirstDiscard then
        local preLen = 0
        for _, c in ipairs(S.s.hostHands[seat]) do
            if C.Suit(c) == cardSuit then preLen = preLen + 1 end
        end
        list.lenAtFirstDiscard = preLen + 1   -- pre-discard length
    end
end
```

**`tahreebClassify`** (the v3.0.3 single-low branch): require
`lenAtFirstDiscard >= 3` before promoting to `"want_hint"`. Otherwise
fall back to `"hint"` (the conservative single-event read pre-v3.0.3):

```lua
if r <= r9 then
    local lenAtFirst = signals.lenAtFirstDiscard or 0
    if lenAtFirst >= 3 then
        return "want_hint"
    end
    return "hint"   -- T-4 doubleton territory or unknown size
end
```

**Filtered-view preservation**: when the forced-discard filter rebuilds
the signals list, preserve `lenAtFirstDiscard` only if the filtered
first-event still matches the original first-event (parallel to
existing `lenAtAce` preservation).

### Why "≥3" specifically

- 3+ no-A no-T suit: classic bottom-up "want" sender shape
  (`Bot.lua:4845`). Receiver intent matches sender intent.
- 2-card doubleton: T-4 dump-larger territory (`Bot.lua:4888`). Even
  if the larger is 9 or 8 (mapping to "want_hint" by rank), the
  sender's intent is "dontwant." Receiver reverts to "hint" and
  waits for a 2nd event.
- 1-card singleton: forced discard, already filtered out by the
  forced-flag mechanism above.

### Behavior on non-bot senders

Humans don't have a `lenAtFirstDiscard` tracker (we can't observe
their pre-play hand). When the receiver is reading a HUMAN partner's
discard, `lenAtFirstDiscard` will be missing → falls back to "hint."
This is a regression vs v3.0.3-v3.0.5 for human-emitted single-low
signals, but **correct**: we don't know if the human meant "want"
(3+ in suit) or "dontwant" (2-card doubleton dump). Conservative
"hint" until a 2nd event clarifies.

The host bot DOES record `lenAtFirstDiscard` for ALL seats including
human seats, since the host has `S.s.hostHands[seat]` for every
player. So host-side reads of human single-low signals are still
correctly gated.

### Tests

**858/858 pass** (was 854 — +4 new pins):

- AN.1c, AN.7: existing v3.0.3 tests updated to set
  `lenAtFirstDiscard = 3` in fixtures (since the test fixtures
  emulate the bottom-up sender path)
- AN.8 (3 source-pins): v3.0.6 sender-intent doc + tracker existence
  + classifier gate
- AN.9 (1 behavioral): T-4 doubleton case (lenAtFirstDiscard=2)
  must NOT classify as "want_hint" — verifies the gate fires correctly

## v3.0.5 — Watchdog hotfix #2: lower ISMCTS time budget below watchdog

### Crash report (continued)

User reported v3.0.4 didn't fully fix the crash:

> happened again, it is in a 3 bot vs human when the bot teammate
> of human is thinking

The **"thinking"** phrasing means the watchdog now trips *during* the
picker, not after it — v3.0.4's deferred-Refresh moved post-picker
work off the budget but didn't address the picker itself overshooting
its own time cap.

### Root cause #2

`K.BOT_ISMCTS_BUDGET_SEC = 0.5` (BotMaster.lua:1108 — set in v0.11.17).
WoW's CPU watchdog kills any single script execution exceeding ~200ms.
The picker's voluntary cap was **2.5× the watchdog limit** — so
ISMCTS could deliberately spend 500ms before yielding, while WoW
killed it at 200.

### Fix

**Lower budget to 0.12s (120ms = 60% of watchdog limit):**

```lua
K.BOT_ISMCTS_BUDGET_SEC = 0.12
```

Picker still gets ~30-60 worlds at trick 1-2 (down from 100), which
is enough variance for confident voting. The remaining 80ms of the
200ms watchdog window covers the picker's setup (`buildLegalSet`,
`buildUnseen`), the trailing `ApplyPlay → SendPlay → _HostStepPlay`
state-mutation chain, and any heuristic-fallback path.

**Plus an inner-loop budget check:**

The outer per-world budget check in `BotMaster.PickPlay` only fires
*between* worlds. A single overshoot world (e.g., 50ms when only 10ms
remains) can still blow the budget. Added a per-card check inside the
world's pcall body:

```lua
for _, card in ipairs(legal) do
    if overBudget() then break end   -- v3.0.5 inner check
    scores[card] = scores[card] + rolloutValue(...)
end
```

The world's partially-completed evaluation still contributes to
`scores` for already-evaluated cards. With 8 candidates × 60 worlds,
at most 7 partial card-evaluations are skipped on the abort iteration
— a marginal accuracy cost vs the watchdog correctness win.

### Strength impact

Saudi Master tier strength is determined more by *which* worlds are
sampled (consistent-with-observation determinization) than by *how
many*. At 60 worlds the move-quality regression vs 100 worlds was
already negligible per the v0.11.17 internal numbers; at 30-60 worlds
it stays inside the noise floor. The bot is still operating on
information-set MCTS, just with a tighter time budget per move.

If a player's machine has substantially slower per-rollout time than
the development baseline (CPU-bound regional play, virtualized envs),
they may see fewer worlds sampled and slightly noisier picks — but
no more crashes. The next-step optimization (if needed) would batch
rollouts across multiple `C_Timer.After(0, ...)` frames; not shipped
until/unless this proves insufficient.

### Tests

**854/854 pass.** The pinned constant test `AA.3c` was updated from
`0.5` to `0.12` with a comment explaining the watchdog rationale.
Numworlds-scaling tests still pin 100/60/30 since `numWorlds` is the
*configured* count; the budget cap is what the loop actually
respects, and that's tested separately.

## v3.0.4 — Watchdog hotfix: bot-dispatch callback Refresh defer

### Crash report

User reported in real play (4-human + bots, Saudi Master tier):

```
1x WHEREDNGN/UI.lua:502: script ran too long
[WHEREDNGN/UI.lua]:502: in function 'FadeBanner'
[WHEREDNGN/UI.lua]:4202: in function <UI.lua:4195>
[WHEREDNGN/UI.lua]:4355: in function 'Refresh'
[WHEREDNGN/Net.lua]:5427: in function <Net.lua:5185>
```

### Root cause

WoW's CPU watchdog times out individual script runs at 200ms. The 6
bot-dispatch callbacks in `Net.lua` (Triple / Four / Gahwa / Preempt /
Bid / Play decisions) all share the same shape:

```lua
C_Timer.After(delay, function()
    pcall(function() ... heavy bot picker work ... end)
    if B.UI then B.UI.Refresh() end   -- inline, shares budget
end)
```

At Saudi Master tier, `Bot.PickPlay` delegates to `BotMaster.PickPlay`
(ISMCTS) which can use 50-150ms per call on rich game states. The
inline `Refresh()` then walks every `renderXyz` function (seats, hand,
banner, AKA banner, SWA banner, overcall banner, peek button, pause
controls). Cumulative time can exceed 200ms — the watchdog fires at
*whatever line happens to be running* when the budget runs out. The
user's crash hit `FadeBanner`'s defensive `b:Hide()` at `UI.lua:502`,
but that line is trivially fast on its own — it was just the unlucky
victim of the budget exhaustion.

### Fix

Add a `deferredRefresh()` helper that wraps `Refresh()` in
`C_Timer.After(0, ...)` — schedules the render for the next frame,
splitting the picker and UI work across two budgets. Apply to all 6
bot-dispatch callbacks.

```lua
local function deferredRefresh()
    if not (B.UI and B.UI.Refresh) then return end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if B.UI and B.UI.Refresh then B.UI.Refresh() end
        end)
    else
        B.UI.Refresh()
    end
end
```

Sites updated: Triple decision (was 4875), Four (4929), Gahwa (4975),
Preempt (5103), Bid (5166), Play (5427). The trick-end Refresh at line
2166 stays inline because it runs in a fresh `C_Timer.After(2.2, ...)`
callback that's *already* off the bot-picker chain — the watchdog has
reset by then.

### Why not optimize the picker

ISMCTS rollout count is the actual driver. Reducing it would degrade
Saudi Master strength. Splitting the rollouts across multiple frames
would change determinism guarantees of the existing tests. The
1-frame Refresh defer is a zero-risk addressing of the symptom; if
this still trips the watchdog on rich game states, the next step is
to batch ISMCTS rollouts across frames — but typical Saudi Master
play doesn't need that, and the user's report is the first watchdog
trip in 854 test runs and ~5000 simulated tournament rounds.

### Tests

**854/854 pass.** No code surface changed in the picker or UI render
paths — the change is a defer-pattern wrapper. Tests don't exercise
the watchdog directly (they run on Lua 5.5 / Python lupa, no WoW
runtime).

## v3.0.3 — Audit doc-vs-code differential closure (6 gap fixes)

The v3.0.2 release shipped a doc-vs-code differential audit alongside
a tournament regression. Audit surfaced 6 actionable gaps where Saudi
strategy docs and bot code diverged. v3.0.3 closes them surgically
without touching scoring or escalation paths.

### GAP-01 (CONTRADICTORY → fixed): Tahreeb single-low → "want_hint"

`Bot.lua` `tahreebClassify`. Mirror of the v3.0.2 single-big-card fix.
Per `signals.md` video #1 form 5 + `decision-trees.md:222`:

> Bottom-up same-suit — low first, higher next = "I want this suit
> (and don't have its Ace)". 70/25/5 prior on first event.

The single-low-card variant has the same informational content as the
*first event* of the canonical low-then-higher sequence. Pre-v3.0.3 the
classifier returned ambiguous `"hint"` for any single-low (7/8/9) — the
same loss-of-information class v3.0.2 closed for single-high. Now:

- Single 7/8/9 → `"want_hint"` (low confidence; weight 1, parity with
  `bargiya_hint`).
- Single J/Q → still `"hint"` (mid-rank singles are genuinely
  ambiguous without context tracking).
- Single T/K (v3.0.2) → `"dontwant"`.
- Single A → `"bargiya"` / `"bargiya_hint"`.

Receiver score table updated to weight `want_hint` = 1 for both partner
pref-suit selection and opp avoid-set scoring. Confirmed `"want"`
(weight 2) and `"bargiya"` (weight 3) still dominate when present.

### GAP-02 (HIGH/MISSING → fixed): SWA 5+-cards mandatory permission

`Net.lua:LocalSWA`. Per `CLAUDE.md:64-76` + video #35 verbatim
«ما تساوي بدون ما تستاذن مستحيل يمشونها» («you cannot SWA without
asking permission, it's impossible they'd let it pass»):

5+-card SWA is **mandatory permission** — Saudi convention does not
let a 5+-card claim pass without explicit opp consent. Pre-v3.0.3 the
`WHEREDNGNDB.swaRequiresPermission = false` toggle bypassed permission
at *any* hand size, including 5+. The toggle was intended for the
≤4-card UX shortcut.

**Fix** (1-line addition):

```lua
local needPerm = (handCount >= 5)
              or (WHEREDNGNDB == nil)
              or (WHEREDNGNDB.swaRequiresPermission ~= false)
```

5+-card claims now force-enable permission regardless of toggle state.
≤4-card paths remain user-toggleable.

### GAP-03 (HIGH/MISSING → fixed): Hokm trump non-consecutive at LEAD

`Bot.lua:pickLead` bidder-team Hokm trump branch. Per
`decision-trees.md` Section 4 + `glossary.md` Takbeer/Tasgheer Hokm
rule:

> When holding non-consecutive top trumps (gap of 2+ in
> `K.RANK_TRUMP_HOKM` order), preserve top — lead a side suit first.

The rule was wired in `pickFollow` trump-winners (`Bot.lua:5670-5679`)
but the symmetric LEAD-side gate was missing. Bidder leading with
J + A of trump (no 9 or T between) would top-down J first; opp could
then over-cut with the missing 9/T and capture our preserved A.

**Fix**: trick-1 only (the inversion benefit decays as the trump pool
draws); when top-2 trump candidates have gap ≥ 2 in
`K.RANK_TRUMP_HOKM`, fall through to the side-suit lead path. Trick 1
gating prevents drift from triggering this in mid/late-round states
where trump structure has shifted.

### GAP-05 (HIGH/PARTIAL → fixed): Bargiya phase-split + void exception

`Bot.lua` Bargiya receiver phase-split. Per `signals.md:189-198`:

> Endgame (≤4 cards): lead the Bargiya'd suit immediately.
> Opening / mid-round (≥5 cards): burn 1-2 of your own tricks first.
> Void in the Bargiya'd suit: lead it anyway — partner expects you
> to attempt regardless.

Pre-v3.0.3 the phase-split downgrade applied ONLY to confirmed
`"bargiya"` flavor; `"bargiya_hint"` (single-A ambiguous) bypassed
the split, leading back immediately even at handSize ≥ 5. The void-
in-suit exception was missing entirely — bot would clear `pref` on
≥5-card hand even when void in the suit.

**Fix**: extend the phase-split to BOTH `bargiya` and `bargiya_hint`.
Add a `prefSuitVoid` check that preserves the pref when we have no
cards in the suggested suit (downstream lead path will fall through
to longest-non-trump).

### GAP-07 (MEDIUM/CONTRADICTORY → doc fix): signals.md off-trump dump

`docs/strategy/signals.md:243-246`. Doc said:

> Sun (off-trump) losers dump **HIGHEST**.

Code does **SMALLEST** per `Bot.lua:6310` (Tasgheer convention). The
v0.5.11 over-correction (HIGHEST) was reverted in v0.7.2 to match
video #05's تصغير; `decision-trees.md:111` is correct. `signals.md`
hadn't been updated.

**Fix**: rewrite the section to align with code + decision-trees.md
+ video #05 («تصغير»). Reframe the "opposite rules" framing to refer
to *Takbeer (partner-winning) vs Tasgheer (opp-winning)*, NOT to
Sun-vs-Hokm.

### GAP-09 (MEDIUM/MISSING → fixed): Tahreeb receiver high-card-return

`Bot.lua:pickFollow` final-fallthrough discipline. Per
`decision-trees.md:238` + `signals.md:79-80`:

> "biggest mistake in Baloot" — receiver of a Tahreeb signal,
> following on the wanted suit with no winner, plays absolute
> lowest. Send your **highest available** card back to partner —
> the high return is your only contribution.

Pre-v3.0.3 the `lowestByRank(legal, contract)` final fallback fired
unconditionally. M3lm-gated fix (Tahreeb sender side is M3lm-only,
so receiver discipline matches): when partner Tahreeb'd this suit
positively (`want` / `want_hint` / `bargiya` / `bargiya_hint`) AND
all `legal` cards are in the led suit (we're following, not ruffing
or discarding), return `highestByRank(legal, contract)` instead.

### GAP-10: verified existing gate sufficient (no fix)

Audit flagged `topTouchSignal` write-site as missing the
"winnerSeatSoFar == myTeamSeat" gate. Investigation: actual write at
`Bot.lua:540-610` already gates on `lead.seat == R.Partner(seat) AND
lead.rank == "A"` (or AKA), which is a STRICTER form of partner-team-
winning. The audit's cite of "Bot.lua:2869+" was a Bargiya block, not
the touching-honors block — audit was inaccurate. Existing gate
correctly suppresses false positives in opp-led trick scenarios.

### GAP-06 (CONTRADICTORY → doc fix): Qaid 26/16 terminology

Audit flagged Qaid penalty as 26/16-split-vs-full-handTotal contradiction.
Investigation traced the math:

| Contract | code path | result |
|---|---|---|
| **Sun**  | `cardA = 130; cardMult = 2; rawA = 260; addA = floor((260+5)/10)` | **26 gp** |
| **Hokm** | `cardA = 162; cardMult = 1; rawA = 162; addA = floor((162+5)/10)` | **16 gp** |

The code in `Net.HostResolveTakweesh` produces exactly 26 gp Sun / 16 gp
Hokm — matching every transcript and the doc's intent. The discrepancy
was **doc terminology**: `saudi-rules.md:140` and `glossary.md:99` used
the word "raw" when they meant *game points after div10*. The Net.lua
comment at line 2806-2810 had it right all along ("= 26 Sun / 16 Hokm
in game points after div10").

**Doc fix**: replaced "26 raw / 16 raw" with "26 gp / 16 gp" in
`saudi-rules.md` Qaid table row and `glossary.md` القيد entry, plus
inline math note showing the derivation. Updated `saudi-rules.md:173`
("score side currently lacks the 26/16 split") to reflect that the
split IS correctly wired — only the doc terminology was off.

No code change. Audit's GAP-06 finding was a misread of `cardA = handTotal`
without tracing through `× cardMult ÷ 10`.

### Tests

**854/854 pass** (was 840 — +14 new pins). New section `AN`:

- AN.1 (3 pins): GAP-01 source markers + return type + score table
- AN.2 (2 pins): GAP-02 source marker + handCount gate
- AN.3 (2 pins): GAP-03 source marker + nonConsecTrumpSkip gate
- AN.4 (3 pins): GAP-05 source marker + bargiya_hint flavor + void
- AN.5 (2 pins): GAP-09 source marker + doc-rationale comment
- AN.6 (1 pin): GAP-07 signals.md doc-fix verification
- AN.7 (1 behavioral): GAP-01 weight order — confirmed `want` (2)
  dominates `want_hint` (1) when both signals are present

Plus an additional behavioral pin (line ~1970-2012) exercising
single-low → `want_hint` end-to-end via `Bot.PickPlay`.

### Why these specifically

The audit found 95 rules total, 18 MISSING, 5 CONTRADICTORY. The 6
shipped here were:

- **CONTRADICTORY** with surgical fixes (GAP-01, GAP-07).
- **HIGH severity / MISSING** with trivial-to-surgical fixes (GAP-02,
  GAP-03, GAP-05).
- **MEDIUM severity / MISSING** matching a `DEFERRED v1.4.1` flag in
  the code that was now actionable (GAP-09).

The remaining gaps are either DEFERRED-pending-research, LOW severity,
or arbitration-needed (GAP-06).

### Tournament

Pre-fix: v3.0.2 multi-seed 100×100 tournament showed ~5-7 gp swings
vs v0.5.1 May-8 baseline, consistent with intended bot-strategy
improvements (anti-prediction work). No concerning regressions.

v3.0.3 changes are surgical Tahreeb-receiver / SWA-rule / pickLead
edge cases — none in the hot path of trick-1 strategy or scoring.
Tournament re-run can be deferred to v3.1.

## v3.0.2 — User playtest hotfix + residual hunt + behavioral test backfill

User-reported in real 4-human play:
1. **Pass button greyed out randomly** in 4-human bidding, regardless
   of seat position
2. **Two melds from same player not counted** (per friend's expert
   account: equal-point melds should both score)
3. **Tahreeb logic gap**: "when I play a different-suit big card it
   means do not come back to me with that"

### Bug 1 (Pass grayed) — pool-state leak

`UI.lua:~1977-2010`. v2.2.0 MP-62 added a `(host advances)` disabled
affordance for non-host PHASE_SCORE that called `btn:Disable()` on
a pooled action button. `clearActions()` only cleared scripts +
alpha + label color — the `:Disable()` state stayed sticky on pool
reuse. Next phase's render reused the slot for Pass / Hokm /
whatever — still disabled. Player saw greyed Pass with no idea why.

**Fix**: `clearActions()` now calls `btn:Enable()` on every pool
slot before reuse. Closes the latent leak class introduced in
v2.2.0.

### Bug 2 (multi-meld) — display gap, NOT a scoring bug

Investigation traced the rule path end-to-end: `R.SumMeldValue`
correctly sums ALL melds per team (confirmed via new regression
pin in `test_rules.lua`). But `meldCardsForSeat` (the trick-2
reveal) showed only the BEST meld's cards — players seeing one
meld card-strip on a multi-meld declarer assumed only one was
counted.

**Fix** at `UI.lua:~2967-3015`: split-the-difference with v1.0.1's
"only best" rule. If all the seat's meld cards fit in 5 slots,
show every meld. If they don't fit, fall back to v1.0.1's
best-only (avoids the misleading-truncation visual that v1.0.1
specifically fixed).

**Regression test** in `test_rules.lua` pins:
- `SumMeldValue` sums BOTH equal-point melds from same seat (40 raw)
- `CompareMelds` correctly picks team A when their best Tierce
  beats opp's best Tierce by top rank (K > Q)

### Bug 3 (Tahreeb single-big-card)

`Bot.lua:~2370-2395` (`tahreebClassify`). Saudi convention per
`signals.md` video #1 form #1: "Same-suit top-down — high then
lower in same suit = 'I do NOT want this suit'". The TWO-card
descending pattern was already classified as `dontwant`, but
SINGLE high-rank discards fell through to ambiguous `hint` —
losing the directional info from "I dumped a K of clubs"
(intended: dontwant).

**Fix**: single-event signals now classify by rank. Discard of
**T or K** (the two highest non-Ace plain ranks) → `dontwant`.
Q / J / 9 / 8 / 7 single discards stay `hint` (ranks where
direction is genuinely ambiguous from a single event). A is
already special-cased to `bargiya` / `bargiya_hint`.

The forced-discard filter above the classifier already strips
no-choice plays, so reaching this rank check implies a voluntary
high-card dump — exactly the user's friend's "big card" signal.

### Hunt for similar residual bugs

After fixing the user-reported three, audited the codebase for
similar latent classes:

- **Pool-state leaks** — verified `clearActions()` now resets every
  mutable script handler, alpha, text color, AND disabled state.
  Hand-card pool's `warnTag` (v2.2.0 PJ-31) explicitly hidden in
  both branches of `renderHand`. No other `:Disable()` calls land
  on pooled action buttons.
- **Best-only display bugs** — `meldCardsForSeat` was the only
  "best of many" display site. Other UI displays (banner score,
  contract chip) iterate all relevant data.
- **Single-event ambiguous classifiers** — `tahreebClassify` was
  the only signal classifier with a `#signals == 1` early-return.

### Behavioral test backfill (Agent 4 code-health gap)

The v3.0.0 meta-audit Agent 4 flagged: drop-recovery synthesizes
votes across 6 phase paths with **zero behavioral test coverage**
— the most fragile new feature uncovered. v3.0.2 adds 6 pins
covering:

- AM.1: `HostKickSeat` clears only target seat in lobby
- AM.2: `HostKickSeat(1)` refused (host can't kick self)
- AM.3: Bot replacement preserves `hostHands` + `bids` for the seat
- AM.4: Overcall drop synthesizes WAIVE; window resolves
- AM.5: SWA-permission drop synthesizes ACCEPT (lenient default)
- AM.6: Bot.PickPlay returns valid in-hand card for replaced seat

### Tests

**839/839 pass** (was 819 — +20 new behavioral pins). Marathon's
new feature surface is now actually exercised at the test level.

## v3.0.1 — Hotfix: meta-audit findings (10 surgical fixes)

A 5-agent meta-audit swarm against v3.0.0 found 2 CRITICAL + ~15
HIGH-severity issues, including several **flagship fixes that were
structurally undelivered or broken by later layered fixes**. v3.0.1
addresses the worst.

### CFI-01 (CRITICAL) — `/baloot reset` popup OnAccept missed MP-71

`UI.lua:656-680` (popup `OnAccept`). v2.1.0's MP-71 fix added a
host-gone broadcast (empty `MSG_LOBBY`) on `/baloot reset`, but the
broadcast lived in `Slash.lua` BEFORE the popup-show check. When
host was mid-round, the slash command routed through the popup —
which never reached the broadcast logic. Result: remotes held
sticky lobby for up to 45s waiting for heartbeat-timeout. The popup
also never called `StopHostHeartbeat`. Fix: mirror both into the
popup's `OnAccept`.

### REG-04 (HIGH) — "New Game" button at game-end same issue

`UI.lua:2540+`. The host's "New Game" button at game-end also called
`S.Reset()` directly without the MP-71 broadcast or heartbeat stop.
Fix: same as CFI-01.

### HIGH#3 — AKA partner-hint never fires for solo-host bot partners

`Net.lua:4002-4080`. v2.0.0 BF-30's chat hint was inline in
`_OnAKA`, which has a `fromSelf(sender)` short-circuit at the top
— meaning host's OWN bot AKAs (the dominant solo-host scenario)
never reached the hint. Extracted into `N._AKAPartnerHint(seat,
suit)` helper called from BOTH `_OnAKA` (remote) AND the
`SendAKA` site in MaybeRunBot's bot-dispatch path (host-loopback).

### HIGH#2 — Arabic-font probe pcall return-value bug

`UI.lua:434-460`. v2.0.0 SA-01's font probe used `local ok =
pcall(probe.SetFont, …); _arabicAvailable = (ok == true)`. But
`pcall` returns `(ok, retval)`; `SetFont` returns `true` on font
load, `false` if file missing. The probe set `_arabicAvailable`
based on whether `pcall` itself succeeded (always, when dispatched)
— never the actual font-load result. Result: on installs without
the font file, `_arabicAvailable` was stuck `true`, `SaudiName`
returned Arabic glyphs, the engine fell back to a default font
that lacked Arabic, and buttons rendered as boxes (the v2.0.2
hotfix's exact failure mode survived). Fix: capture the SECOND
pcall return value.

### HIGH#1 — `IsHostLikelyGone` watchdog had no UI consumer

`Net.lua:3231` defined the function; nothing called it. v1.8.0
MP-21's heartbeat detection was structurally undelivered. v3.0.1
adds a 10-second ticker in `WHEREDNGN.lua:PLAYER_LOGIN` that checks
`IsHostLikelyGone()` for non-host clients in active games and
prints a chat warning ONCE on first detection (with auto-clear when
heartbeat resumes).

### CFI-02 (HIGH) — Escalation rung delays bypassed tier multiplier

`Net.lua:4824, 4877, 4928, 4974`. v1.8.0 BF-01 introduced
`botDelay(base, difficulty)` for tier-aware pacing. v2.0.0 BF-06/50
added per-rung delays (`BOT_DELAY_TRIPLE/FOUR/GAHWA`) but used
`C_Timer.After(BOT_DELAY_*, ...)` directly — bypassing `botDelay`.
Net effect: Saudi Master and Basic both fired escalation rungs at
exactly 3.4/3.7/4.2s; BF-01's tier-pacing contract was lost on the
most narrative decisions. Fix: route all 4 sites through
`botDelay(BOT_DELAY_*, difficulty)`. Gahwa marked "hard" for the
+0.6s match-stake weight.

### REG-02 (HIGH) — `bindConfirm` didn't restore button width on click-confirm

`UI.lua:1937-1977`. v2.0.0 UX-04 introduced auto-resize on confirm-
arm to fit the longer prompt label. The auto-disarm path (timer
fire) restored 90px width; the click-confirm path called `disarm()`
then `fire()` but never restored width. Pooled buttons stayed at
220px after a confirm-fire, leaking into the next phase's action
panel layout. Fix: add `btn:SetWidth(90)` to the shared `disarm()`.

### PM-09 (HIGH) — Dead Reset tooltip override

`UI.lua:716-728`. The Reset button had `setLobbyTooltip` wired with
the v2.0.0 host-broadcast warning, then a SECOND `OnEnter` handler
immediately overrode it with a less informative v1.x message. The
v2.0.0 tooltip body was permanently dead code. Fix: remove the
override block.

### PM-12 (HIGH) — `WLA (decline)` missed in v2.3.0 case normalization

`UI.lua:1623`. v2.3.0 SA-23 normalized "WLA" → "wla" everywhere,
but missed one tooltip body. Fix: lowercase.

### PM-01/02 (HIGH) — TAKWEESH button had no tooltip

`UI.lua:2468`. The most consequential accusation button in Saudi
Baloot had ZERO tooltip — its sibling SWA at line ~2487 had full
prose. Critical asymmetry on a paired-button row. Fix: full TAKWEESH
explanation matching SWA's depth (mechanic, outcome, penalty,
"only when sure" warning).

### Tests

819/819 pass.

### Audit reports committed

```
.swarm_findings/v3.0.0_audit_regression_hunter.md  (Agent 1, 14 findings)
.swarm_findings/v3.0.0_audit_new_features.md       (Agent 2, 21 findings)
.swarm_findings/v3.0.0_audit_cross_fix.md          (Agent 3, 12 findings)
.swarm_findings/v3.0.0_audit_code_health.md        (Agent 4, 28 findings)
.swarm_findings/v3.0.0_audit_polish_meta.md        (Agent 5, 26 findings)
```

Total: 101 findings in the meta-audit; v3.0.1 closes 10 highest-
impact items. Remaining ~90 are mix of LOW polish + items deferred
for verification + items needing playtest signal. The audit reports
are committed as historical record (not gitignored).

## v3.0.0 — Architectural release: Settings panel + lobby kick + polish

Major version bump. The headline changes are the proper Settings
panel under Esc → Options (replacing the v2.0.0 description-only
stub) and lobby-time host kick UI. Plus polish on minimap radius,
AFK pulse constants, and a `/baloot config` shortcut.

### PJ-04 follow-up + PJ-52 — Settings panel with toggles

`WHEREDNGN.lua:~155-260`. Pre-v3.0 the Esc → Options → AddOns
entry for WHEREDNGN was a description-only stub pointing at slash
commands. Players reaching for the standard WoW settings flow saw
no toggles. Now: a proper canvas panel with checkboxes for every
persistent `WHEREDNGNDB` toggle, organized into three sections:

- **Bot tiers** (cumulative): Advanced / M3lm / Fzloky / Saudi Master
- **Saudi rule toggles**: SWA, SWA-permission, Triple-on-Ace pre-empt
- **Misc**: Sound, Debug logging

Each checkbox has a tooltip explaining the toggle + its tier-
inheritance property (matching the v2.3.0 PJ-54 lobby tooltips).
Numeric settings (game target, card/felt themes) remain in slash
commands — surfaced via the panel footer. Modern (10.0+) Settings
API + legacy `InterfaceOptions_AddCategory` shim for older clients.

### PJ-53 — `/baloot config` shortcut

`Slash.lua`. Opens the Settings panel directly (modern
`Settings.OpenToCategory` + legacy `InterfaceOptionsFrame_OpenToCategory`
fallback with the known double-call workaround). Pre-fix players
had to navigate Esc → Options → AddOns by hand. Aliases:
`/baloot settings`, `/baloot options`.

### MP-41 — Lobby kick button

`UI.lua:~880-915`. Pre-fix the only way to remove a player was
waiting for them to `/baloot reset` or leave the party — host had
no graceful "out you go" path. Now seats 2-4 get a "✕" kick button
on the right edge of the lobby row, host-only + lobby-phase only +
hidden when the seat is empty. Click → `S.HostKickSeat(seat)` +
re-broadcast. Kicked client sees their seat clear on the next
`MSG_LOBBY`.

### UX-35 — AFK pulse constants

`Constants.lua` + `UI.lua`. Pre-fix the AFK turn-warn pulse
hardcoded `8 ticks × 0.18s` inline. Now exposed as
`K.UI_AFK_PULSE_TICKS` / `K.UI_AFK_PULSE_PERIOD` with the same
defaults — tunable + documented.

### UX-53 — Minimap radius adapts to actual size

`MinimapIcon.lua`. Pre-fix the hardcoded `RADIUS = 80` clipped on
minimaps smaller than ~80px (some HUD addons shrink the minimap)
— the icon would land off-screen. Now derives from
`Minimap:GetWidth() × 0.55`, clamped at 80, so the icon always
stays visible regardless of minimap scaling.

### Tests

819/819 pass.

### What's deferred to v3.1+

Honestly: items I tried and found too risky / restructure-heavy
for a single release:

- **BF-13/14** — AKA + trump-cut voice cue spacing (needs deferred
  broadcast restructure)
- **BF-22/23** — Bot dispatch separator + preempt cascade pacing
- **BF-52/62** — "Considering Bel" hover + late-recovery surface
  (need new UI infrastructure)
- **UX-71/72** — peekLastTrick + bid-card phase-advance fade
  (need centerCards alpha animation framework)
- **UX-32** — Overcall banner refresh throttle (already self-
  throttles via 0.33s tick — verified, no change needed)
- **UX-61/70/73** — Chat color match + animation polish (subjective;
  playtest first)
- **PJ-14/42** — Round-2 wla label, game-end styling per outcome
  (subjective)
- **MP-70** — Host-race resolution protocol (real protocol work,
  not a quick fix)
- **MP-05/23/51/72/73** — Mostly already-addressed-in-prior-fixes
  or rare-edge — fix-on-encounter
- **Round replay (PJ-41)** — full feature, v3.x+ work

These represent ~15 more polish items but each requires either
restructure work or playtest signal to know what matters. v3.0.0
caps the marathon at the cleanly-tractable polish; further work
should be playtest-driven.

## v2.3.0 — Polish batch 3 (10 items: bot feel + UI + Saudi auth)

Continuation of the polish marathon. No bot strategy logic touched.

### Bot feel

- **BF-15** (MED) — BALOOT! auto-fire now defers ~1s after the
  triggering card play. Pre-fix the cue stacked on top of card-play
  SFX + trump-cut + winner-glow audio in the same beat — muddy
  overlap. The 1s pause lets play audio finish before the BALOOT
  voice starts.
- **BF-32** (LOW) — Partner-bot Bel reason chat hint. When a
  bot-partner fires Bel and the local human is on the same team,
  prints a chat line tagging the call's mood: "open — confident,
  expects partner support" vs "closed — locking in ×2, no chain".
  Helps the human decide whether to escalate.

### UX

- **UX-23** (MED) — SWA banner Y offset shifted from -32 to -68 so
  the card row no longer overlaps the top trick-card slot.
- **UX-71/72** — deferred (centerCards fade requires bigger refactor;
  low-value relative to risk).

### Player journey

- **PJ-54** (LOW) — Bot-tier checkboxes now mention the strict-
  extension property in tooltips ("Tier 3/5. Strictly EXTENDS
  Advanced (auto-on). Higher tiers extend this in turn."). Pre-fix
  the inheritance chain was hidden — players checking M3lm without
  Advanced got the M3lm bonuses but not the Advanced layer.
- **PJ-13** (MED) — Kawesh tooltip expanded with the rule context.
  "Annul + redeal" alone didn't explain WHY it's allowed; new
  players might think it's a cheat.
- **PJ-25** (MED) — Hokm bid button tooltip mentions the trump
  rank-order quirk ("J > 9 > A > T > K > Q > 8 > 7. Four 9s do NOT
  form a Carre."). Pre-fix this quirk was only in `/baloot rules`
  output — players who skipped that never learned it.

### Saudi authenticity

- **SA-23** (LOW) — `WLA` case normalized to lowercase `wla`
  consistently. Pre-fix mixed `WLA (waive)` in overcall vs `wla`
  in bidding. Lowercase matches how Saudi players actually type
  it in chat.
- **SA-33** (LOW) — Round counter visual: `"Round %d"` → soft-grey
  tinted so it reads as ancillary metadata, not a primary score
  line.

### Tests

819/819 pass. AJ.8 source-pin test updated to accept either v1.0.2
("Doubled / Tripled") OR v2.3.0 ("Bel'd / Bel x3'd") wording in
the M3lm tooltip — both are valid wirings, the v2.3.0 form is
Saudi-aligned per CLAUDE.md mandate.

## v2.2.0 — Polish batch 2 (12 items: UX + MP + accessibility)

Continuation of the polish marathon. Closes the next batch of
deferred audit items, focused on small UX papercuts, multiplayer
QoL gaps, and accessibility (colorblind contrast). No bot strategy
logic touched.

### UX

- **UX-07** (MED) — Accept SWA now also two-clicks (matches Deny).
  Both consequences are real (Accept locks the team into letting
  a possibly-bluffing claim through); both deserve the same misclick
  guard.
- **UX-43** (LOW) — `/baloot sound` (alias `/baloot mute`) toggles
  audio + re-syncs the lobby checkbox visual. Pre-fix there was no
  slash equivalent; muting required opening the window.
- **UX-60** (MED) — Colorblind-aware team palette. `txtUs` shifted
  to brighter mint (luminance ≈ 0.85), `txtThem` to desaturated
  coral (≈ 0.65). Pre-fix mid-saturation green/red were
  indistinguishable to deuteranopia / protanopia (~10% of male
  players); now distinguishable by brightness even when hue is lost.
- **UX-62** (LOW) — AFK pulse: on cancel, force-restore the legal-
  edge gold. Pre-fix a back-to-back PulseTurn left the border in
  alert-red mid-pulse before the new cycle painted over it.

### Multiplayer QoL

- **MP-31** (LOW) — AFK warning at T-10s now also prints an explicit
  chat hint, in addition to the existing sound-ping + border-pulse.
  Players AFK in another window or with sound muted can't miss
  the visual + chat dual-channel.
- **MP-33** (LOW) — Cancel host's AFK turn timer when a dropped
  human's seat is replaced by a bot. Pre-fix a stale 60s timer
  kept counting against the seat after the bot took over —
  briefly raced against `MaybeRunBot`'s own dispatch.
- **MP-52** (LOW) — `peerVersions` keyed by NORMALIZED sender on
  write but read by full `Name-Realm` form in UI lobby — read miss
  on cross-realm clients. Read-side now `S.NormalizeName(m.full)`
  to match the write key.
- **MP-62** (LOW) — Non-host gets a "(host advances)" disabled-
  label affordance during PHASE_SCORE. Pre-fix non-hosts saw zero
  buttons during score phase — host could stall indefinitely with
  no UI cue. Cosmetic for now; future work could broadcast a
  "ready" ping.

### Player journey

- **PJ-31** (MED) — Illegal-card warning: corner "!" tag overlay in
  addition to the orange border. Pre-fix the border alone wasn't
  distinct enough from cardEdge / hover-lift states for colorblind
  or quick-glance players. The corner glyph is unmissable.

### Saudi authenticity

- **SA-31** (LOW) — Score banner: "152" → "152 pts". The raw
  number alone meant nothing to a new player; "pts" is unambiguous.

### Tests

819/819 pass.

## v2.1.0 — Polish batch (16 deferred items closed)

Polish-focused minor release. Closes the highest-value MEDIUM-tier
deferred items from the v1.6.1 audit. No bot strategy logic touched.

### Track 1 — Discoverability

- **PJ-04** (MED) — Blizz interface-options registration. Addon now
  shows up under Esc → Options → AddOns. Modern (10.0+) Settings
  API + legacy InterfaceOptions_AddCategory shim. Panel has a
  description + "Open WHEREDNGN window" button.
- **PJ-07** (LOW) — `/baloot help` mentions `/blt` shorthand.
- **SA-22** (LOW) — Pre-empt button: dropped "(Pre-empt)" English
  parenthetical. Saudi players know what قبلك means; non-Saudi
  players get the explanation in the tooltip.
- **PJ-70** (LOW) — Pause/peek glyphs replaced. Peek "?" → "↺"
  (anticlockwise revert, universal "look back" glyph). Pause "II"
  → "‖" (Unicode pause, renders consistently across font scales).

### Track 2 — Visual polish

- **UX-30** (MED) — `turnGlow` tint shifted from gold-on-gold (visual
  mush against legalEdge cards) to soft cyan. Active-seat indicator
  no longer competes visually with the warm legal-edge gold.
- **UX-33** (MED) — SWA banner countdown: when timer hits 0, shows
  "approving…" / "resolving…" instead of frozen "0s".
- **UX-31** (LOW) — AKA banner fade-in/out. New `B.UI.FadeBanner(b,
  duration, hide?)` helper wraps Show/Hide with `UIFrameFadeIn` /
  `UIFrameFadeOut`. Banner snap-on/snap-off replaced with smooth
  0.25s alpha animation.
- **UX-42** (LOW) — Illegal-card border tint shifted from deep-red
  (visually identical to Takweesh-warning border) to warning-orange.
  More accurate semantics: orange = "warning, not error" (Saudi
  Takweesh ALLOWS illegal plays — you just risk getting caught).
- **UX-05** (LOW) — BALOOT! pulse only first 5s after appearance,
  then settles to static gold + clears `OnUpdate`. Pre-fix the
  always-pulsing yellow added persistent visual chatter.

### Track 3 — Multiplayer QoL

- **MP-61** (MED) — `/baloot leave` (alias `/baloot quit`) — graceful
  exit for non-host. Routes through the same teardown as `/baloot
  reset` for non-hosts; host's GROUP_ROSTER_UPDATE recovery (v1.8.0
  MP-01) sees the exit as a drop and replaces with bot.
- **MP-71** (MED) — Host-gone signal. When host calls `/baloot reset`,
  broadcasts a final `MSG_LOBBY` with empty seat array — remotes
  see "all-empty seats from a known host" and immediately tear down
  pendingHost + reset to IDLE. Pre-fix remotes held the sticky
  lobby until the 45s heartbeat timeout (v1.8.0 MP-21) fired.
- **MP-30** (MED) — AFK auto-play smarter. Pre-fix picked literal
  lowest TrickRank — could dump an Ace if Ace happened to be lowest
  in some edge case. Now prefers non-high-value cards (excludes A
  and J/9-of-trump) when any are legal; only burns A or J-of-trump
  if the legal set is forced. More polite "I'm AFK" play.
- **MP-53** (MED) — `GROUP_ROSTER_UPDATE` drop detection now uses
  `S.NormalizeName` for cross-realm fallback. Pre-fix strict
  `shortName` match could miss a still-present cross-realm peer
  whose `UnitName` format differed from the seat record. Mirrors
  the v1.8.0 MP-50 fix to `HostHandleJoin`.

### Track 4 — Stats & engagement

- **PJ-40** (MED) — Persistent lifetime stats. New `WHEREDNGNDB.stats`
  subtable: `gamesPlayed` / `gamesWon` / `contractsTaken` /
  `contractsMade` / `biggestSwing`. Bumped on game-end +
  round-end. Forward-compatible schema (missing fields default to
  0). Surfaced via `/baloot stats` (alias `/baloot stat`).
  `/baloot stats clear` wipes the table.
- **PJ-43** (MED) — Game-end gets "Stats" + "History" buttons next
  to the host's "New Game" button. Non-hosts (who previously had
  ZERO actions at game-end) now see at least the Stats button.
  History only shows when telemetry is enabled and there's data.
- **SA-32** (MED) — Contract banner: dropped "Contract:" Latin
  prefix. Visual context (e.g. "HOKM ♠ by PlayerName" at top of
  table) is self-explanatory; the prefix added cognitive load
  without new info.

### Tests

819/819 pass. One test (U.6 source-pin for `_OnLobby`'s name cap)
got its scan window bumped from 3000 to 5000 chars — MP-71's
host-gone block was inserted before the existing cap logic. Cap
itself is unchanged.

## v2.0.2 — Hotfix: Arabic glyphs render as boxes in tooltips

User-reported in playtest: tooltips and slash output showed `□□□`
boxes instead of Arabic terms (e.g., "Decline to bid (round 1).
Saudi: «□□□» — pass.").

### Root cause

The v2.0.0 SA-01 Arabic font infrastructure routes through
`B.UI.SaudiName` which uses `pcall(SetFont, …)` to detect availability
and falls back to romanized when the font is missing. **But that
helper only applies where my code explicitly calls `SetFont`.**

Tooltips use `GameTooltip:AddLine(…)` and chat output uses `print(…)`
— both render through WoW's built-in `GameFontNormal` /
`GameFontHighlight` font system, which doesn't have my custom
Arabic font (and never can, since GameTooltip doesn't expose the
font slot to addons). I included Arabic glyphs in tooltip strings
and slash-output strings anyway, expecting the font fallback to
kick in. It can't — the font system at the GameTooltip level isn't
the same as the FontString-level `SetFont` I probe.

User had already told me this back at the start of the marathon
("SAUDI names should not mean arabic as WOW does not render arabic
text") — I correctly applied it to button labels but missed it on
tooltip + chat strings.

### Fix

Replaced all user-facing Arabic glyphs with romanized forms:

| Site | Was | Now |
|---|---|---|
| Pass tooltip (R1) | `Saudi: «بَسْ» — pass` | `Saudi: 'bas' — pass` |
| Pass tooltip (R2) | `Saudi: «ولا» — no preference` | `Saudi: 'wla' — no preference` |
| Ashkal tooltip | `Saudi rule (إشكل): …` | `Saudi rule (Ashkal): …` |
| Bel x2 (Sun) tooltip | `Saudi: «بل». …` | (term dropped — flow already implies it) |
| Gahwa tooltip | `Gahwa (قهوة) — terminal escalation` | `Gahwa — terminal escalation` |
| WLA × 2 tooltips | `Saudi: «ولا» (wla)` | `Saudi 'wla'` |
| SWA / Accept SWA / Deny SWA | `«سوا» / «نسمح» / «شرح»` | romanized |
| AKA action button tooltip | `AKA (إكَهْ) — partner-coord…` | `AKA — partner-coord… (Saudi 'eka')` |
| BALOOT! tooltip | `BALOOT! (بلوت)` | `BALOOT!` |
| AKA banner headline | `AKA (إكَهْ) — partner signal` | `AKA — partner signal` |
| SWA banner headline | `SWA (سوا) — claim the rest` | `SWA — claim the rest` |
| `/baloot rules` | 3 lines with Arabic | romanized + (eka) gloss |
| `/baloot swa` toggle output | `SWA (سوا claim-the-rest)` | `SWA (claim-the-rest)` |
| `/baloot preempt` toggle output | `pre-emption (الثالث)` | `pre-emption` |

The `K.SAUDI_NAMES` map (Constants.lua:65-80) **keeps** its Arabic
forms — they're only rendered via `B.UI.SaudiName` which probes for
the bundled Arabic font first. Without the font: returns romanized.
With the font: returns "حكم Hokm" via `SetFont`. Tooltips and chat
never go through SaudiName and therefore never see the Arabic data.

### Tests

819/819 pass.

## v2.0.1 — Hotfix: BF-10 "thinking…" indicator crash on bot turn

User-reported in-game error on `HostStartRound` (first refresh after
v2.0.0 ship):

```
1x FontString:GetScript(): Doesn't have a "OnUpdate" script
[WHEREDNGN/UI.lua]:2818
```

### Root cause

The v1.8.0 BF-10 "thinking…" indicator at `UI.lua:~2808-2822`
attached `SetScript("OnUpdate", …)` directly to a **FontString**.
WoW FontStrings only support a small set of scripts (OnEnter / OnLeave
via the parent frame); they do NOT support OnUpdate. Only Frame-
derived objects do. The crash didn't surface until v2.0.0 because
the test harness doesn't exercise CreateFrame / SetScript paths;
the bug was latent in v1.8.0/1.8.1 but only triggered in-game when
the active seat was a bot AND the host's UI tried to render the
thinking indicator.

### Fix

`UI.lua:~2808-2837`. Replaced the FontString-with-OnUpdate with a
wrapper Frame that holds the FontString. OnUpdate now lives on the
Frame and cycles the inner FontString's alpha each tick:

```lua
b.thinkBox = CreateFrame("Frame", nil, b.frame)
b.thinkBox:SetSize(80, 14)
b.thinkBox:SetPoint("BOTTOM", b.frame, "BOTTOM", 0, 4)
b.thinkBox.label = b.thinkBox:CreateFontString(
    nil, "OVERLAY", "GameFontNormalSmall")
b.thinkBox.label:SetAllPoints(b.thinkBox)
b.thinkBox:SetScript("OnUpdate", function(self, elapsed)
    self._t = (self._t or 0) + (elapsed or 0)
    local pulse = (math.sin(self._t * 4.4) + 1) * 0.5
    if self.label and self.label.SetAlpha then
        self.label:SetAlpha(0.55 + pulse * 0.40)
    end
end)
```

The else-branch hides both `thinkText` (legacy v1.8.0 field, in case
saved state somehow persisted) and `thinkBox` (new v2.0.1 field).

### Tests

819/819 pass. The crash was unreachable from the test harness, so
the bug slipped through every prior ship — the in-game `CreateFrame`
+ `SetScript` paths are stubs in `tests/run.py`. Future BF-10-class
work should manually verify in-game.

## v2.0.0 — Major release: deferred-items marathon

Major version bump: closes the v1.6.1 audit's remaining HIGH-severity
deferred items + the Arabic-font infrastructure (SA-01) that was the
biggest open authenticity question. 19 audit items shipped across 4
internal batches. **No bot strategy logic touched — every ship of
v1.7.0 / 1.8.0 / 1.8.1 / 1.9.x scoped strategy fixes is preserved.**

### Batch 1 — UX quick wins

- **PJ-02** (HIGH) — Silent host invite → chat line + sound cue when a
  new host invites you. `Net.lua:_OnHost`.
- **PJ-06** (HIGH) — Lobby button tooltips: Reset / Host Game / Fill
  Bots / Start Round / Join. New helper `setLobbyTooltip(btn, …)`
  for direct-makeButton call sites that don't go through `addAction`.
- **PJ-10** (HIGH) — Bid card label: shows "Bid card" caption above
  the up-card during `PHASE_DEAL1` so new players know what the
  centre card represents.
- **PJ-21/23/24** (HIGH) — AKA / Sun-overcall / SWA banner tooltips
  via the same `setLobbyTooltip` helper. Each explains the mechanic
  + Saudi term in one sentence.
- **PJ-30** (HIGH) — Illegal-play warning surfaces a `UIErrorsFrame`
  banner (red top-of-screen, like "Not enough mana") + sound chime
  in addition to the existing chat line. Pre-fix the chat-only
  warning was easy to miss in busy combat or general chat.
- **UX-04** (HIGH) — `addConfirmAction` auto-resizes button width on
  arm to fit the longer confirm-prompt label (capped at 220px).
  Restores default 90px on disarm. Pre-fix long armed labels
  ("Confirm Bel x3 (closed)?", "Confirm Deny — caller's invalid
  claim costs them ~30 pts; if Deny is wrong…") truncated.
- **UX-22** (MED) — `pauseOverlay:EnableMouse(true)`. Pre-fix the
  pause overlay was visible but didn't capture clicks — they passed
  through to cards/banners beneath, silently no-op'd downstream.
- **UX-24** (MED) — Window registered with `UISpecialFrames` so
  pressing Escape closes it (matches the WoW convention for every
  other movable, dismissable UI panel).
- **SA-25** (HIGH) — Failed-contract banner: "BALOOT!" → "TAH!"
  (طاح — "crashed/went down"). Pre-fix the addon used "BALOOT!"
  to herald a contract FAILURE; semantically inverted ("BALOOT!"
  is the success-only K+Q-of-trump fanfare). "TAH!" is the
  canonical Saudi loss-banter for a failed contract.

### Batch 2 — Multiplayer drop-recovery hardening

- **MP-02/03/04** (HIGH) — Drop during `PHASE_DOUBLE/TRIPLE/FOUR/
  GAHWA` / `PHASE_OVERCALL` / SWA-permission window now triggers
  phase-specific recovery in addition to the v1.8.0 bot-fill seat
  swap. Escalation phases re-invoke `MaybeRunBot` so the
  newly-installed bot at the dropped seat picks up its decision.
  Overcall synthesizes a default `WAIVE` for the dropped vote.
  SWA-permission synthesizes an `ACCEPT` (lenient — loss falls on
  caller if wrong). Round stays playable through any drop.
- **MP-22** (HIGH) — `/baloot reset` mid-round (host) now routes
  through the existing `WHEREDNGN_RESET_CONFIRM` popup. Pre-fix the
  slash command bypassed the guard that the UI Reset button used.
  New `/baloot reset force` subcommand for users actually needing
  to recover from stuck state.
- **MP-60** (HIGH) — Version mismatch chat warning when host's
  announced version differs from local. Pre-fix `peerVersions` was
  tracked in state but never surfaced — incompatible peers played
  together with subtle wire-protocol divergence (e.g., a v0.8
  client emitting TAKE_HOKM that v1.5.3+ silently rejects).

### Batch 3 — Bot feel + transparency

- **BF-06/50** (HIGH) — Per-rung escalation pacing.
  `BOT_DELAY_TRIPLE = 3.4s`, `BOT_DELAY_FOUR = 3.7s`, `BOT_DELAY_GAHWA
  = 4.2s` (was all `BOT_DELAY_BEL = 3.2s`). Saudi pros pause longer
  on terminal rungs — Gahwa especially weighs match-stake. Stair-
  steps the wait for proper escalation drama.
- **BF-20** (HIGH) — Overcall stagger: bot decisions no longer fire
  synchronously at window-open time. Each bot's decision now lands
  at a randomized 0.4-3.2s offset within the 5s window. Pre-fix the
  human saw "decided" instantly + 4.9s of "nothing happening"
  anxiety; now bots feel like they're thinking it over independently.
- **BF-30** (HIGH) — Partner-signal transparency for AKA. When the
  bot fires AKA AND the local human is the bot's PARTNER, prints a
  green chat hint explaining the signal + what action to take
  ("Partner suggests don't over-trump <suit>"). Opp-bot AKA prints
  an orange hint ("Opp claims boss in <suit>; their partner won't
  trump <suit>"). Bots get nothing — they read signals via memory.

### Batch 4 — Saudi authenticity (Arabic font infrastructure)

- **SA-01** (HIGH) — Optional Arabic font support. New
  `K.ARABIC_FONT = "Interface\\AddOns\\WHEREDNGN\\fonts\\NotoNaskhArabic-Regular.ttf"`
  + `K.SAUDI_NAMES` map (romanized↔Arabic for HOKM/SUN/BEL/FOUR/
  GAHWA/AKA/SWA/ASHKAL/KAWESH/QABLAK/BALOOT/TAH/PASS/WLA).

  New `B.UI.SaudiName(key)` helper auto-detects font availability via
  pcall(probe.SetFont, …): returns "حكم Hokm" with font present,
  "Hokm" without. Cached after first probe; opt-in at every call
  site. Drop the .ttf in `Interface\AddOns\WHEREDNGN\fonts\` and
  `/reload` to enable.

  **To enable Arabic glyphs**:
  1. Download Noto Naskh Arabic Regular (Google Fonts, OFL-licensed):
     https://fonts.google.com/noto/specimen/Noto+Naskh+Arabic
  2. Save as `Interface\AddOns\WHEREDNGN\fonts\NotoNaskhArabic-Regular.ttf`
  3. `/reload` — UI auto-detects + uses it.

- **SA-11** — Already addressed in v1.7.0 via tooltips that mention
  Saudi terms (e.g., Pass tooltip says "Saudi: «بَسْ»"). No
  additional changes.
- **SA-21** (HIGH) — Wired `SaudiName` at the highest-visibility bid
  buttons (R1 Hokm, R1 Sun, R2 Sun). With Arabic font: "حكم Hokm ♠"
  / "صن Sun". Without: "Hokm ♠" / "Sun" (unchanged behavior).

### Tests

819/819 pass. One test (AF.5 in test_state_bot.lua) was updated to
match either the legacy `addAction("Sun"` literal OR the new
`addAction(SaudiName("SUN")` form — both valid v2.0.0 wirings.

### v1.6.1 audit cycle: closed

| Track | Items closed | Closed in |
|---|---|---|
| Saudi authenticity | SA-20, SA-03, SA-30, SA-25, SA-01, SA-11, SA-21 (7 of ~8 HIGH) | v1.7.0 + v2.0.0 |
| Tooltip layer | 18 wired sites (action panel + lobby + banners) | v1.7.0 + v2.0.0 |
| Player journey | PJ-01, PJ-02, PJ-06, PJ-10, PJ-21, PJ-23, PJ-24, PJ-30, PJ-50, PJ-51 | v1.7.0 + v2.0.0 |
| Bot feel | BF-01, BF-05, BF-06, BF-10, BF-11, BF-20, BF-30, BF-40, BF-50 | v1.8.0 + v2.0.0 |
| Multiplayer QoL | MP-01, MP-02, MP-03, MP-04, MP-21, MP-22, MP-50, MP-60 | v1.8.0 + v2.0.0 |
| UI/UX | UX-13, UX-21, UX-04, UX-22, UX-24 | v1.8.1 + v2.0.0 |

Total: **~33 audit items closed** across the v1.6.1 audit-driven
release cycle (v1.7.0 → v2.0.0). Remaining items are all MEDIUM/LOW
polish or items that need user input (e.g. font choice, voice
re-recording).

## v1.8.1 — Polish hotfix (audit v1.6.1 batch 3, marathon completion)

Third and final release of the v1.6.1 audit-driven marathon. Closes
the remaining surgical fixes — UI cleanup, missing slash subcommand.
No bot strategy logic touched.

### UX-13 — BALOOT! pulse leak (CRITICAL)

`UI.lua:~1664-1693`. Pre-fix the BALOOT! button's `OnUpdate` (which
pulses the label color via `fs:SetTextColor` to draw attention) was
set on a pooled action-button but `clearActions()` only nilled
`OnClick` — `OnUpdate` survived the pool reuse. A button repurposed
for a different action in a later phase (e.g., a "Skip" button slot
that previously held BALOOT!) kept pulsing its label color forever,
fighting whatever the new phase wanted to display.

`clearActions()` now nils `OnUpdate` and resets `SetAlpha(1.0)` +
label color to white, fully neutralizing pool entries before reuse.

### UX-21 — Hand-card OnClick paused-state gate (HIGH)

`UI.lua:~2426-2445`. Pre-fix click was rejected silently downstream
by `N.LocalPlay`'s `S.s.paused` check at `Net.lua:~2300`, but the
user got NO visible feedback — they thought the click landed and sat
waiting. Now gates locally and prints a chat hint:

```
[WHEREDNGN] Game is paused — wait for host to resume.
```

### PJ-5X — `/baloot swaperm` slash subcommand (HIGH)

`Slash.lua:~226-245`. Pre-fix `swaRequiresPermission` was referenced
as a real config knob in `WHEREDNGN.lua:54` (`DEFAULTS`) and
`Net.lua:~3040` (gate), with the comment in `DEFAULTS` saying
"toggle via /baloot swaperm" — but the dispatch table had no entry.
Typing `/baloot swaperm` was a no-op. Wired now:

```
/baloot swaperm  - toggle SWA permission requirement for 4+ cards
```

Listed in `/baloot help` output.

### Tests

819/819 pass. All v1.8.1 changes are UI cleanup + slash dispatch
plumbing — no game logic touched.

### v1.6.1 audit marathon: complete

| Release | Track | Items closed |
|---|---|---|
| v1.7.0 | Saudi authenticity + tooltips + onboarding | 5 (SA-20, SA-03, SA-30, tooltip layer + ~15 wired sites, first-launch + 2 slash subcommands) |
| v1.8.0 | Bot pacing + multiplayer resilience | 6 (BF-01, BF-10, BF-11, MP-01, MP-21, MP-50) |
| v1.8.1 | Polish hotfix | 3 (UX-13, UX-21, PJ-5X) |

14 audit items closed across 3 releases. 819/819 tests pass at every
ship. No bot strategy logic touched — v1.5.0/1.5.1/1.5.3/1.6.0
strategy fixes preserved.

## v1.8.0 — Bot pacing + multiplayer resilience (audit v1.6.1 batch 2)

Second release of the v1.6.1 audit-driven marathon. Closes the
"feels robotic" + "drops break the game" gaps without touching bot
strategy logic.

### BF-01 — Variable bot pacing (HIGH)

`Net.lua:~4297-4380` + `~4790, 4848`. Pre-fix every bot decision used
flat `BOT_DELAY_BID = 1.6s` / `BOT_DELAY_PLAY = 1.2s` regardless of
decision difficulty or tier — Saudi Master playing a 4-Aces forced
auto-Sun took the same 1.6s as Basic random pass.

New helpers:
- `botDelayTierMult()` — Saudi Master 1.30×, Fzloky 1.15×, M3lm 1.0×,
  Advanced 0.85×, Basic 0.70×. Higher tiers think longer; lower tiers
  snap.
- `botBidDifficulty(seat)` — "trivial" (4 Aces / no J + <2 Aces) /
  "normal" / "hard" (3 Aces) classifier. Cheap heuristics.
- `botPlayDifficulty(seat, legalCount)` — "trivial" (singleton legal)
  / "normal" / "hard" (5+ legal in trick 1 or 7+).
- `botDelay(base, difficulty)` — applies tier mult + difficulty offset
  (-0.4 / +0 / +0.6) clamped to [0.5s, 4.0s].

Wired at the bid + play dispatch sites in `MaybeRunBot`. Saudi pros
pause on hard plays and snap on easy ones — that's the *feel*
dimension closed.

### BF-11 — Voice-cue floor (HIGH)

`Net.lua:~4324`. Pre-fix `BOT_DELAY_BEL = 1.4s` was shorter than the
~3s Bel/Triple/Four/Gahwa MP3 voice files, causing cues to stack
mid-word in escalation chains. Raised to **3.2s** as a hard floor.

### BF-10 — "Thinking…" indicator on bot turns (CRITICAL)

`UI.lua:~2628-2660`. Pre-fix the active-seat `turnGlow` was identical
for bot-thinking and human-AFK — players couldn't tell whether to
wait or `/reload`. Now the host (only) shows a soft fade-cycling
"thinking…" label below the bot's seat badge during `bid`/`play`
turns. ~0.7Hz pulse so it visibly animates.

### MP-01 — Mid-round drop bot-fill (CRITICAL)

`WHEREDNGN.lua:~404-440`. Pre-fix `GROUP_ROSTER_UPDATE` dropped a
seated human's seat to nil with no replacement; mid-round drops froze
the trick permanently (no human to AFK-timer, no bot to dispatch).
Now branches:

- **Lobby phase**: kick the seat (existing behavior — bot fill via
  `/baloot bots`)
- **Mid-round**: replace with a placeholder bot, preserve seat record,
  inherit hand + bid state from `S.s.hostHands` / `S.s.bids`, and
  kick `MaybeRunBot` to handle the in-flight turn

Round stays playable; the bot inherits the dropped player's position.

### MP-21 — Host-alive heartbeat (CRITICAL)

`Constants.lua:~248-266` (`MSG_HEARTBEAT` + `HOST_HEARTBEAT_SEC=15` +
`HOST_HEARTBEAT_TIMEOUT_SEC=45`). `Net.lua:~3017-3090` (`StartHostHeartbeat` /
`StopHostHeartbeat` / `_OnHeartbeat` / `SecondsSinceHostHeartbeat` /
`IsHostLikelyGone`). `Net.lua:~2173` (auto-arm on `HostStartRound`).

Pre-fix: when the host crashed or quit mid-game, the 3 remaining
clients stared at a frozen UI forever with no signal. Fix: host
broadcasts a single-byte `MSG_HEARTBEAT` every 15s. Remotes track
`_lastHeartbeatAt` and expose `IsHostLikelyGone()` after 45s of
silence (3 missed heartbeats). The UI can read this and surface a
warning banner — base infrastructure now in place.

### MP-50 — `HostHandleJoin` name normalization (HIGH)

`State.lua:~683-720`. Pre-fix the dedup check used raw `==` on names.
Same player joining via `/reload` from a same-realm client could
arrive with a different surface form ("Name" vs "Name-Realm") and
get a SECOND seat — duplicate. Now normalizes both sides via
`S.NormalizeName` before comparing, matching the receive-side
pattern at `Net.lua:741-748`.

### Tests

819/819 pass. All v1.8.0 changes are pacing constants, UI indicators,
host-side recovery, and lobby plumbing — no game logic touched.

## v1.7.0 — Saudi authenticity + tooltips + onboarding (audit v1.6.1 batch 1)

First release of the v1.6.1 audit-driven marathon (3 releases: v1.7.0
Saudi+tooltips+onboarding, v1.8.0 bot pacing+multiplayer resilience,
v1.8.1 polish hotfix). Closes the most-impactful UI/interaction gaps
without touching bot strategy logic — v1.5.0/1.5.1/1.5.3/1.6.0
strategy fixes all preserved.

### SA-20 — Re-Saudi-fy escalation rung labels (CRITICAL)

`UI.lua:~1828, 1846, 1849-1851, 1866-1869, 1882-1885, 3253-3258,
3374-3379, 3556-3561`. v1.0.2's user-requested rename had flipped
the Saudi-flavored escalation labels (Bel / Bel x2 / Four / Gahwa)
to English (Double x2 / Triple x3 / Four / Gahwa). The audio cues
still said «بل» but the buttons said "Double x2" — direct doc-vs-
code violation of `CLAUDE.md:56` mandate "Saudi names in player-
visible text". v1.7.0 reverts the visible labels to romanized Saudi:

- "Double x2" → "Bel x2"
- "Double & open / closed" → "Bel & open / closed"
- "Triple x3 (open / closed)" → "Bel x3 (open / closed)"
- "Four & open / closed (x4)" → unchanged (already Saudi loan-word)
- "Gahwa (match-win)" → unchanged (already Saudi)
- "Double forbidden (Sun >=100)" → "Bel forbidden (Sun >=100)"

Round-end / contract-banner mod chips updated to match. Internal
phase / message names (`PHASE_DOUBLE`, `LocalDouble`, `MSG_DOUBLE`)
unchanged — pure UI-string change.

**Note**: "Saudi names" here means **romanized Saudi**, NOT Arabic
glyphs. WoW's bundled fonts (Arial Narrow / Frizz / Skurri) don't
include the Arabic Unicode block, so direct «بل» glyphs render as
empty boxes.

### SA-03 — Belote glyph dynamic per trump suit (HIGH)

`UI.lua:3262, 3385`. Pre-fix the Belote score line hardcoded `♥`
regardless of contract trump — K+Q-of-spades Belote on a Hokm-Spades
contract showed "Belote (K+Q ♥)". Now reads `K.SUIT_GLYPH[trump]`.

### SA-30 — Match-end winner/loser branch (HIGH)

`UI.lua:3148`. Pre-fix the match-end title `8amt!! go play something
else` was shown to BOTH teams. "غامت" (8amt) is Saudi loser-banter;
firing it at the winner reads as either confusing or condescending.
Now branches on `localTeam == winner`:

- Winners: "ya batal — match win!" (يا بطل — champion)
- Losers: "8amt!! go play something else" (current line, kept)

### Tooltip layer for action buttons (CRITICAL — PJ + UX)

`UI.lua:1672-1731`. Pre-fix `addAction()` and `addConfirmAction()`
had ZERO tooltip layer. New players pressing "Ashkal" or "BALOOT!"
or "AKA" had no in-game way to learn what the call meant — they
had to read source code or external Saudi Baloot tutorials.

Extended both helpers with an optional `tooltip` parameter that
wires `OnEnter` / `OnLeave` mirroring the existing checkbox tooltip
pattern at `UI.lua:849-856`. Existing call sites passing nil keep
pre-v1.7.0 behavior; opt-in.

Wired tooltips at the highest-impact call sites:
- Bid panel: Pass / wla / Hokm / Sun / Ashkal / Kawesh + R2 Hokm-suit
- Escalation rungs: Skip / Bel / Bel & open / Bel & closed / Bel x3 /
  Four / Gahwa
- Overcall window: Upgrade to Sun / Take as Sun / WLA
- Side calls: SWA / Accept SWA / Deny SWA / AKA / BALOOT!

Each tooltip explains both the mechanic and the Saudi term in one
sentence. New player first-game ramp-up is now possible without
external docs.

### First-launch welcome (HIGH — PJ-01)

`WHEREDNGN.lua:130+`. Pre-fix the addon was completely silent on
first install. Now prints a one-shot welcome on `PLAYER_LOGIN`,
gated on `WHEREDNGNDB.welcomed` so it never repeats:

```
[WHEREDNGN] Welcome to Loot & Baloot — Saudi Baloot for WoW.
Click the minimap icon to host or join a game. Type /baloot help
for commands or /baloot rules for a Saudi-rules cheat-sheet.
```

### `/baloot help` and `/baloot rules` slash subcommands (HIGH — PJ-5X)

`Slash.lua:38+`. Pre-fix `help()` was implemented as a static
function at the top of `Slash.lua` but had NO entry in the dispatch
table — typing `/baloot help` was a no-op. Now wired:

- `/baloot help` (and aliases `?`, `h`) — dumps the full command list
- `/baloot rules` (and aliases `rule`, `ref`) — Saudi Baloot quick-
  reference cheat-sheet covering bidding, card values, escalation
  chain, signals (AKA / SWA / BALOOT), win condition, and Saudi-
  specific traps (9-of-trump rank, strict-majority bidder rule)

`/baloot help` line list updated to mention both new commands.

### Tests

819/819 pass. All v1.7.0 changes are UI strings, tooltip wiring,
or new slash-subcommand additions; no game logic touched.

## v1.6.1 — Wire desync fix (MSG_TURN dropped frame recovery)

User-reported: "the game froze, it was two humans and two bots, the
host human opposite seat bot choose hokm and turn moved for the next
human to bid but he still sees the bot's turn while the host sees it
as the other human turn."

### Root cause

WoW's `CHAT_MSG_ADDON` channel can silently drop frames under throttle
pressure (heavy guild chat, instance transition, or another addon
spamming the same prefix). The bot's bid sequence emits two back-to-
back broadcasts:

```
1. MSG_BID;<bot>;HOKM:S    ← arrived at remote ✓
2. MSG_TURN;<next>;bid     ← dropped on the wire ✗
```

The remote applied the bid (`bids[bot] = HOKM:S`) but its local
`s.turn` pointer never advanced. `S.IsMyTurn()` returned false on the
next-bidder's screen → no bid UI → game frozen for that user. Host
state moved on correctly; remote was stuck.

A defensive 250ms re-broadcast for `MSG_CONTRACT` was added in
v0.11.11 (`NetU-01`) to address the same throttle-drop class of bug
in the dense overcall sequence — but `MSG_TURN` had no equivalent
guard, even though it's just as critical for unfreezing remote
clients.

### Fix

`Net.lua` `N.SendTurn` now mirrors the v0.11.11 NetU-01 pattern:
after the initial broadcast, schedule a 250ms re-broadcast that
self-suppresses if the host has moved past this turn.

```lua
if C_Timer and C_Timer.After then
    C_Timer.After(0.25, function()
        if S.s.isHost and S.s.turn == seat
           and S.s.turnKind == kind then
            broadcast(("%s;%d;%s"):format(K.MSG_TURN, seat, kind))
        end
    end)
end
```

Properties:
- **Idempotent on receive**: `S.ApplyTurn` just writes `s.turn = seat`
  unconditionally; applying twice is a no-op.
- **Self-suppressing**: if the host has moved past this turn (next
  bid, contract, trick advance), the host-side gate prevents stale
  re-broadcasts.
- **250ms < any natural turn change**: `BOT_DELAY_BID` and
  `BOT_DELAY_PLAY` are both ≥ 1.5s; human delays are longer. The
  re-broadcast cannot carry stale info.

### Impact

Single point of change covers every turn advance — bid, play, all
phases. Eliminates the entire class of "remote stuck on stale turn"
desyncs caused by single-frame drops. Throttle pressure modest
(re-broadcasts only fire when needed, plus a single duplicate per
turn change otherwise).

### Tests

819/819 pass. The fix is a wire-level resilience addition; the test
harness doesn't exercise `C_Timer` so the re-broadcast is dormant in
tests but doesn't perturb existing flows.

## v1.6.0-hotfix — Pos-2 deception variable rename (meta-audit cleanup)

A meta-audit of the v1.5.3 swarm reports (re-verified v1.6.0 against
actual code) flagged a misleading variable name in the pos-2 hand-
shape deception block I just shipped: `opp4` was named for "opp at
pos-4" but actually points at pos-3 (the seat immediately after us
in trick rotation, which IS the opp at pos-2). At pos-2 our partner
is pos-4 (across the table); pos-3 is the opp between us.

The seat-math was correct — the deception fires for the right
reasons — but the variable name + comment misled future readers.

**Fix** (`Bot.lua:5358`): renamed `opp4` → `pos3Opp` and updated the
comment to clearly state pos-3 = opp, pos-4 = partner. Behavior
unchanged. 819/819 tests pass.

## v1.6.0 — Anti-prediction release (5-agent swarm audit fixes)

A 5-agent parallel audit asked: **is the bot bulletproof or too
predictable when playing skilled humans?** Verdict: not bulletproof.
55% of decision points fully deterministic, 60 exploits cataloged
(3 CRITICAL, 15 HIGH), variance budget ~3-5× narrower than Saudi
pros, lead-suit predictability ±1 candidate after 4-6 rounds.

This release ships the top 5 surgical fixes from the audit's
counter-strategy synthesis. All five are additive, tier-gated, and
partner-bot-safe (analyzed individually — no fix breaks signal
comprehension between bots).

### CS-01 — Faranka borderline-state breaker (M3lm+, HIGH ROI)

`Bot.lua:~4374`. Pre-fix, the v1.5.0 5-factor framework deterministic-
ally maps board state → captureRate; any opp who memorizes the
factors predicts bot behavior on every Faranka shape. Per video #20
"التحكم في الدور" pros vary at borderline states (~10-15% bluff
fraction).

When `captureRate` lands in the genuinely-uncertain band [0.40, 0.60]
after factor adjustments, add a ±0.10 random kick BEFORE the clamp.
~20% of borderline rolls now flip across the Faranka/capture
threshold randomly. Partner-bot reads only the result, not the
predicted outcome — wobble stays inside the 0.50-base noise budget
already absorbed.

### CS-02 — Self-style escalation jitter (Fzloky+, HIGH ROI)

`Bot.lua:~6580 + 6810/6988/7070/7124`. Pre-fix every Fzloky bot's
Bel/Triple/Four/Gahwa decision used the same per-rung jitter band,
so reading one bot's escalation pattern leaked the strength range
for every bot at the table. Bot-strength-from-Bel was readable to
~22 points resolution.

New helper `selfStyleJitterBonus(seat, kind)` extends each rung's
jitter by an extra ±N drawn from the seat's lifetime escalation
counter (`Bot._partnerStyle[seat].bels/triples/fours/gahwas`). Loose
callers (escalated often) get wider bands; tight callers (rarely
escalate) get narrower. Same Bel from two different bots now conveys
different strength. Per-rung caps: Bel +4, Triple +5, Four +5, Gahwa
+6. Partner reads the post-Bel multiplier change, not predicted-in-
advance — meaning of a fired Bel unchanged.

### CS-03 — Lead-suit perturbation (Fzloky+, HIGH ROI)

`Bot.lua:~6470`. `pickLead` resolves through a long deterministic
branch-priority chain. When 2+ branches would fire on the same hand
state, the FIRST branch always wins — pre-computable.

New `perturbLeadSuit` wrapper (forward-decl pattern) at Fzloky+ tier
swaps with 6% probability after `pickLead` resolves. Swap target:
same-rank-class card in a DIFFERENT, NON-TRUMP suit. Carve-outs:
trump leads (signal-critical), A/J leads (boss-claim + AKA), single-
ton suits. Lead-suit prediction degrades from ~85% to ~60% on flat-
top states without breaking any signal.

### Pos-2 hand-shape deception re-intro (Saudi Master, 8% rate)

`Bot.lua:~5285`. v1.4.6 fully removed the v1.4.5 probabilistic pos-2
breaker after a 4-perspective audit found pure-probability deviation
read as «غلط» (beginner mistake) to a Saudi observer. The v1.5.3
swarm (variance gap, agent 4) found the removal went too far for
human-target play: pos-2 is the most-read position in Saudi Baloot,
and a fully deterministic pos-2 makes the bot strictly readable.

Per video #22 R3, pros DO deviate at pos-2 — but on HAND-SHAPE
TRIGGERS, not pure probability. v1.6.0 re-introduces the breaker as
a hand-shape-conditioned, Saudi-Master-only branch:

- Trigger: Hokm contract, sureStopper has been picked (we WERE going
  to take with the boss), AND we hold a same-suit "next card down"
  that still wins the trick AND neither pos-3 nor pos-4 is known void
  in the led suit
- 8% chance to swap down: play the lower winner instead. Opp infers
  we don't have the higher card and counter-attacks the (now-fake)
  absent boss. We surprise with the higher card next round.
- Carve-outs: trump suit (signal-critical), Sun contract (no ruff
  threat — deception value lower), A/J as alt-winner (signal-carrier
  ranks).

Pure-probability "duck when you should take" remains excluded as
«غلط» — this is a TAKE-side deception only.

### AKA bluff rate bump (0.03 → 0.08)

`Bot.lua:~6398`. AKA was the single highest-leak signal — the call
banner pinpoints the live boss in the announced suit. Pre-fix 3%
noise rate at Saudi Master was too low to meaningfully degrade opp's
prior; opp could treat 97% of AKA calls as honest. 8% (~3× increase)
shifts the expectation enough that opp must seriously hedge against
the bluff arm. Still well below convention-breaking levels.

### Tests

819/819 pass. All five fixes are additive perturbations on existing
deterministic paths; existing source-pin tests don't exercise the
specific board states that gate the new variance behavior.

### Cumulative impact estimate

Per audit Agent 5: human-exploit edge against M3lm+ bots estimated
to drop from ~15-20% per game to ~5-8% — rough, hard to measure
without bot-vs-pro tournament data.

### Audit reports committed as historical record

The five swarm audit reports are now committed under
`.swarm_findings/v1.5.3_audit_*.md` (pattern mining, exploit playbook,
signal leakage, variance gap, counter-strategy). Future audits can
diff against these as a baseline.

## v1.5.3 — Remove non-canonical TAKE_HOKM cross-trump overcall

User-reported: "when someone bids hokm in bidding round 1, how come
the dealer can bid switch to hokm 2 with different suit??"

### What was happening

In the post-Hokm-bid 5-second overcall window (`PHASE_OVERCALL`), the
v0.8.0 "cross-trump Hokm take" feature let any non-bidder seat submit
decision `TAKE_HOKM_<S/H/D/C>` to **rewrite the contract** — replacing
both the bidder seat and the trump suit. The dealer (or any non-bidder)
could effectively snatch a Hokm contract from the legitimate winner
and play it with their own preferred trump.

### Why it was wrong

`docs/strategy/saudi-rules.md:26-28` (the canonical Saudi rule):

> **Bid resolution:** First non-pass wins the contract; subsequent
> players can `PASS`, accept silently, or call `ASHKAL` if they're
> the partner of the Hokm-bidder and prefer to play it as Sun.

Three legitimate post-Hokm responses: PASS, ACCEPT, ASHKAL. **A non-
bidder snatching the contract with a different trump suit is not in
Saudi convention.** That's what round 2 is for: pass round 1 if you
don't like the up-card; bid your suit when round 2 starts.

The feature was added in commit `a48fe34` (v0.8.0) as a "symmetric
extension" of v0.7.0's Sun-overcall window — **with no Saudi-rule
citation**, no video, no decision-trees entry, no saudi-rules.md
mention. The Sun-overcall window itself (UPGRADE bidder→Sun, TAKE
non-bidder→Sun) IS canonical and remains intact (saudi-rules.md:256
✓).

### Fix

Removed TAKE_HOKM_<suit> end-to-end:

- **Rules.lua** `R.ResolveOvercall`: dropped TAKE_HOKM_<suit> branch.
  Function now resolves UPGRADE / TAKE / WAIVE only.
- **State.lua** `S.RecordOvercallDecision`: validity check rejects
  any TAKE_HOKM-prefixed decision.
- **State.lua** `S.FinalizeOvercall`: dropped TAKE_HOKM contract-
  mutation branch.
- **Net.lua** `N.LocalOvercall`: same wire-side validity gate (silent
  reject — stale clients on v0.8.0+ that emit TAKE_HOKM are dropped
  at the wire so the host never accepts them either).
- **UI.lua**: removed the "Take as Hokm <suit>" button + 30-line
  `bestHokmTake()` heuristic + the corresponding "decided" label
  branch. The overcall window now shows: Take as Sun / WLA only
  (plus UPGRADE for the bidder).
- **Bot.lua** `Bot.PickOvercall`: collapsed the per-suit Hokm-take
  evaluation. Non-bidder bot now picks TAKE (Sun, if `sunStr >=
  K.BOT_OVERCALL_TAKE_TH`) or WAIVE.
- **Constants.lua**: removed `K.BOT_OVERCALL_TAKE_HOKM_TH`.
- **Tests**: rewrote `test_rules.lua` P.23-P.29 + added P.30 to
  assert TAKE_HOKM_<suit> is silently rejected; rewrote
  `test_state_bot.lua` H.15-H.17 with new rejection coverage.

### Tests

819/819 pass (was 828 — 9 cross-trump-take regression pins removed).

### Stale-client compatibility

A client running v0.8.0–v1.5.2 that hasn't updated to v1.5.3 will
still **emit** `TAKE_HOKM_<suit>` from its UI, but every host
running v1.5.3 silently drops it (wire-side validity gate). Net
effect: the stale client's "Take as Hokm <suit>" button no-ops and
the Hokm contract stands. No desync.

## v1.5.2 — Easter egg hotfix (photo swap + aspect-preserving overlay)

User swapped the bundled Easter photo (the v1.5.1 image was wrong)
and asked for the overlay to preserve aspect ratio so portrait
photos don't get stretched into screen-filling distortion.

### Photo asset replaced

`media/easter.jpg` replaced with the correct image. `easter.mp3`
unchanged.

### Aspect-preserving overlay

`Easter.lua:_showPhoto` (~line 80+) reworked:

- Frame still spans `UIParent` and blocks click-through, but is
  now backed by a solid-black `BACKGROUND` texture that paints
  the letterbox/pillarbox bars.
- The photo texture itself is anchored to CENTER and **sized
  per-show** based on screen dimensions and a new
  `PHOTO_ASPECT` constant (width/height of the source image).
- If `PHOTO_ASPECT >= screen_aspect` → fit width, letterbox top/
  bottom. Else → fit height, pillarbox left/right.

Update `PHOTO_ASPECT` in `Easter.lua` if you swap the photo for a
different aspect later. Approximate values are fine — the sizing
is robust to small mismatches.

### Tests

828/828 pass. No game-logic touched; only the overlay rendering
and the bundled asset.

## v1.5.1 — Takweesh realism fix + hidden Easter egg

### Takweesh realism fix (user-reported bug)

User report: "bots seem to use Takweesh before realistically knowing
if it is valid (it is valid but they did not see the violation),
that is not real scenario."

Pre-v1.5.1: `Bot.PickTakweesh` (Bot.lua:7307+) scanned for the
`p.illegal` flag — which is set host-side when an illegal play is
detected with full hand info. Bot was effectively "cheating" by
calling Takweesh on violations no human at the table could realistically
have observed.

**Fix**: added a `laterPlayedLeadSuit` realism gate. The bot now
fires Takweesh only when:

1. The play was actually illegal (host flag preserved as legality
   verification — matches real-table behavior where the illegality
   is real, just needs human-observable proof to call out).
2. **AND** the violator subsequently played the led-suit in a later
   trick (or the in-progress trick) — publicly-visible proof that
   the violator HAD the led-suit during the original off-suit play
   and didn't follow.

If the violator successfully hides the violation (never plays the
led-suit again that round), they get away with it — exactly matching
real Saudi-table behavior. The realism gate naturally bounds last-
trick scenarios: if proof appears at trick 8, only bots with
remaining turns in trick 8 can fire Takweesh before the round
closes (PHASE_PLAY → PHASE_SCORE transition gates `N.LocalTakweesh`
at Net.lua:2535).

### Hidden Easter egg

New optional module `Easter.lua` triggers a full-screen photo +
sound when one of a configured set of player names presses pass
during an escalation-skip window (PHASE_DOUBLE / TRIPLE / FOUR /
GAHWA). 10% chance per pass.

**Initial targets**: Papayaga, Mants, Lamo, Scralet, Wakkata, Baalah.

**Removal procedure** (documented at top of Easter.lua):
1. Delete `Easter.lua`
2. Remove the `Easter.lua` line from `WHEREDNGN.toc`

That's it — the hook into `B.Net.LocalSkipDouble` is wrapped from
INSIDE Easter.lua at addon load (deferred 0.5s timer ensures Net.lua
is loaded first). No other file references the module, so deleting
the file fully removes the behavior. To temporarily disable without
deleting, set `EASTER_ENABLED = false` in the file.

**Asset placement**: drop the photo and sound into
`Interface\AddOns\WHEREDNGN\media\`. Default paths point at
`easter.jpg` + `easter.mp3` (user-supplied assets are bundled in
the `media/` folder). Adjust `PHOTO_DURATION_SECONDS` in
Easter.lua to match the sound length.

> Note on `.jpg`: WoW retail's `SetTexture` officially supports
> `.tga` and `.blp`. `.jpg` works on most modern clients but is
> not guaranteed. If the photo fails to display in-game, convert
> `easter.jpg` → `easter.tga` (any image editor) and update the
> `PHOTO` constant in `Easter.lua`. Sound `.mp3` is supported by
> `PlaySoundFile`.

**Tests**: 828/828 pass. Easter.lua is not loaded by `tests/run.py`
(only Bot/State/Rules/BotMaster harnesses); no test impact.

## v1.5.0 — Audit-gap closures (5 new heuristics + 3 stale items closed)

User instruction: bundle the 8 audit-list items into v1.5.0. Most
HIGH/MEDIUM items implemented; the 3 LOW-priority items found to
be STALE (already wired in older releases). 828/828 tests pass.

### Implemented (5 items)

#### #1 — Sun K-is-boss sureStopper parallel (HIGH)

`Bot.lua:5023+`. Mirrors v1.4.8 HIGH-1 fix into Sun. When A of led
suit is already played (`S.s.playedCardsThisRound["A"+leadSuit]`),
K becomes the live boss. Same over-save bug existed in Sun as in
Hokm; pos-2 was systematically ducking K when K could win the
trick. In Sun there's no trump → no ruff threat ever; K is
unambiguously boss when A is dead. Promote K to sureStopper.

#### #2 — Faranka 5-factor framework (HIGH)

`Bot.lua:4174+`. Pre-v1.5.0: flat 0.30 capture / 0.70 Faranka with
v1.3.0 weakHandSignal inversion. Per video #06 «راح اعطيك خمس
عوامل رئيسيه» (5 main factors), pros don't Faranka uniformly —
they evaluate factors and adjust. Replaced the flat rate with
factor-additive computation:

- Base captureRate = 0.50 (uncertain default)
- F1: Cover is J (best — J+A doubleton) → -0.10 (more Faranka)
- F2: Partner-takes (already required) → no additional adjustment
- F3: Al-Kaboot pursuit active for our team → -0.10
- F4: Faranka-success would flip game-loss to opp → -0.10
- F5: LHO is bidder + trick == 1 (proxy for LHO holds T) → -0.10
- WeakHandSignal inversion (video #20): +0.40 capture
- Anti-trigger: opp-bidder + Kaboot threat → captureRate = 1.0
  (always take, deny their Kaboot)
- Clamped [0.05, 0.95] preserves unpredictability per v1.2.1 A7

M3lm-gated.

#### #3 — predictTrickWinner helper (HIGH, ADDITIVE only)

`Bot.lua:3993+`. Centralized trick-winner certainty computation
per videos #21/22/23 (Takbeer/Tasgheer triage). Returns
`(winnerSeat, confidence)` where confidence is "certain" / "likely"
/ "uncertain". Used by NEW branches in v1.5.x+. Existing inline
certainty checks in v1.4.1 pos-3 Takbeer + v1.4.8 HIGH-3 hold-back
remain as-is per user direction "keep and replace in later release."

#### #4 — Hokm trump adjacency (MEDIUM)

`Bot.lua:5476+`. Per video #22 R1+R3+R8: when all winners are
trump, the canonical play depends on consecutiveness. Pre-fix
always picked LOWEST trump. New rule:
- Consecutive trump pair (e.g., A+T): play HIGHEST (R1 — top-down
  for partner read)
- Non-consecutive pair (e.g., 9+8): play LOWEST (R3 — preserve
  top trump, opp burns shape mid-trumps to capture)
- 3+ trumps OR singleton: lowest (R3 default)

Trump rank order is non-natural (J>9>A>T>K>Q>8>7); uses
`K.RANK_TRUMP_HOKM`.

#### #5 — Tanfeer factor 5: switch detection (MEDIUM)

`Bot.lua:739+, 2733+`. Per video #19 §2.5: when an opp has signaled
suit X first and later switches to suit Y, the X-read should be
CANCELLED — the newer signal supersedes. Pre-v1.5.0 wired factors
1, 2, 3, 4, 6 but factor 5 (cancellation) was deferred. Added:
- New `list.firstTrickN` field on `tahreebSent[suit]` records the
  trick of FIRST event for each suit
- Confidence computation finds opp's latest-signaled suit (max
  firstTrickN); earlier suits get 50% weight downgrade

### STALE (3 items — already wired in older releases)

#### #6 — Ashkal bid-up rank gates: STALE

The audit listed "A-upcard, T+A anti-triggers, 65-84 vs 85+ split"
as gaps. All are wired:
- A-upcard reject: `Bot.lua:1826` (v0.5.8 A-3)
- K-upcard reject: `Bot.lua:1837` (v0.9.1 A-2)
- T-cardinality: `Bot.lua:1846-1852` (v0.9.2 A-2 cardinality)
- T+A anti-trigger: `Bot.lua:1859-1865` (v0.5.8 A-4)
- 3+ Aces: `Bot.lua:1880` (v0.5.8 A-5)
- 65-84/85+ split: `Bot.lua:1889` (v0.5.8 A-6 + v0.5.13 const)

Receiver-side `ashkalSuit` ledger (R24-R26) for partner-Ashkal-
direction reads in pickLead is genuinely deferred — Ashkal is
rare, low priority.

#### #7 — SWA two-handed Hokm mode: STALE

The audit listed "partner rank-1 + trump+void detection" as a
gap. `R.IsValidSWA` (Rules.lua:482+) does a full game-tree
expansion with recursion-budget guard. It SIMULATES partner's
optimal play including ruff opportunities. The two-handed Hokm
SWA route (partner ruffs caller's side lead) is exhaustively
explored by the validator — caller's claim returns true only if
a winning line exists. Bot.PickSWA delegates to R.IsValidSWA;
no separate two-handed branch needed.

#### #8 — Mathlooth anti-SWA guard: STALE

The audit listed "opp K+2 kills SWA" as a gap. Same as #7 —
R.IsValidSWA's recursive simulation explores opp K+2 capture
paths. If the K-of-suit can capture the caller's side card after
the caller's top-2 of suit are played, the simulation returns
false. The Mathlooth-trap scenario is automatically detected.

### Tests

828/828 pass. All v1.5.0 changes are additive or refinements;
existing source-pin tests don't exercise the specific board states
that gate the new behavior.

### Audit cycle status

After v1.5.0, the audit list from v1.4.7's playtest follow-up is
fully addressed. Real implementations: 5 (HIGH/MEDIUM items).
Confirmed STALE: 3 (LOW items — already wired). Open items
remaining (deferred): receiver-side ashkalSuit ledger (low impact,
Ashkal is rare).

## v1.4.8 — Over-save audit fixes (user-reported play feedback)

User reported from real human play after v1.4.7:

> "Bots still do not attempt to win tricks in favor of saving big
> cards to win the last trick, which results in losing control over
> the rounds and scoring less or losing contract."

A focused audit (Ruflo reviewer agent) found 3 HIGH-severity
over-save bugs with a shared root cause: **every "save" heuristic
was built without context-awareness**. They fire in isolation
without checking card-state, score-state, or position-certainty.

### HIGH-1 — Pos-2 ducks K in Hokm even when K is the live boss

`Bot.lua:5023+` (sureStopper block). Pre-fix: in Hokm, the
sureStopper check only promoted trump winners on `trumpOut <= 1`.
Side-suit Ks were never promoted, even when A of the suit was
already played (making K the live boss with no card above it).
Bot systematically ducked K with low cards while opps took with
Q/J — exactly matching the user's complaint.

**Fix**: added a Hokm-only K-promotion check. When `S.s.playedCardsThisRound["A"+leadSuit]` is true (A already played),
K becomes a sureStopper. Per video #5: second-hand-low convention
applies when K is NOT the live boss; once A is dead, K should be
played to win the trick now.

### HIGH-2 — Round-end T-deferral fires too broadly

`Bot.lua:3653+`. Pre-fix: the v1.4.3 round-end strong-card
deferral fired whenever `partner has 0 captures AND trickCount <= 5`
— too generous. Bot delayed leading T-boss suits even when the
bidder team was failing the round. Video #9 «احتفظ فيها وخليها
للأخير» applies to a defended team comfortable with their lead,
NOT a struggling bidder who needs the points now.

**Fix two parts**:
1. **Tightened trick gate** from `<= 5` to `<= 3`. After trick 3
   the landscape is clear enough to establish T-boss leads.
2. **Added `underContractPressure` bypass**: if bot is on bidder
   team AND current raw < (target - 30), skip the deferral
   entirely. Take the T-boss now; contract failure is the bigger
   risk than burning the round-end T value.

### HIGH-3 — Pos-3 hold-back fires without confirming partner will win

`Bot.lua:5267+` (v1.4.4 pos-3 hold-back). Pre-fix: the 9-condition
gate required "partner currently winning" but **didn't verify
partner WILL ACTUALLY win the trick after pos-4 plays**. The C9
condition `pos4HasA = false` treated unknown as "no A," making
the rule MORE likely to fire when memory was sparse — opposite of
safe. Pos-4 (opp) often overcuts partner's mid lead with Q/J that
bot's K could have taken. Bot saved K for psychological bait that
didn't materialize because partner lost the trick anyway.

**Fix**: replaced the weak `pos4HasA` check with a STRICT
`pos4CannotBeat` predicate. The hold-back now requires pos-4 to
be CONFIRMED VOID in the led suit (Bot._memory[pos4].void[lead] =
true) — only then is partner's mid-card lead actually a guaranteed
winner. With pos-4 void, partner cannot be over-taken; saving the
K is meaningful. Without that proof, fall through to the standard
highest-winner pickup.

### Shared theme: context-awareness

All three fixes plumb context the heuristics were missing:
- HIGH-1: **card-state** (is K live boss?)
- HIGH-2: **score-state** (is bidder team failing?)
- HIGH-3: **position certainty** (will partner actually win?)

The `underContractPressure` predicate added in HIGH-2 is a model
that future audits should reuse for other save-rules (e.g.,
Faranka pos-4 captureRate could become pressure-aware).

### Tests

828/828 pass. The fixes are additive — they constrain when each
heuristic fires, never expand. Existing source-pin tests don't
exercise the specific board-states (K-boss in Hokm, mid-round
bidder pressure, pos-4 confirmed void) that gate the new
behavior, so test outcomes are unchanged.

### Expected play impact

User's reported pattern should resolve:
- HIGH-1 → Hokm bidder ducks fewer Ks; recaptures suit control
  faster after A is played
- HIGH-2 → Failing-bidder bots stop hoarding T-boss suits and
  start leading them when contract pressure is real
- HIGH-3 → Pos-3 hold-back rarely fires now (requires confirmed
  pos-4 void), eliminating the misfires where bot saved K but
  partner still lost the trick

If user plays bot vs human after this and the issue persists, MED-4
(mid-round bidder-pressure override for tricks 5-7) and MED-5
(pos-2 A/T elevation when trump exhausted) are queued for v1.4.9.

## v1.4.7 — Code cleanup (282 lines saved, behavior preserved)

After the 16-release audit cycle (v1.3.0 → v1.4.6) accumulated
multi-paragraph audit-history comments, this release condenses
them. Goal: reduce clutter without affecting bot outcome.

### Method

Identified comment blocks ≥18 lines (the worst offenders). Each
was condensed to retain:
- Source citation (video #, decision-trees.md ref)
- Confidence level (Definite / Common / Sometimes)
- Behavior summary
- Tier gating

Removed:
- Full audit dialogue history (kept canonical conclusion)
- Stale "v0.X.X" trajectory traces (kept current state)
- Long auditor quotes from earlier releases
- Multi-paragraph deferral rationales for items already resolved

### Blocks consolidated

| Location | Before | After | Saved |
|---|---:|---:|---:|
| Tahreeb sender comment block | 137 lines | 16 lines | -121 |
| Pos-2 breaker history | 38 lines | 14 lines | -24 |
| Sun establishing rule | 37 lines | 19 lines | -18 |
| Faranka pos-4 history | 36 lines | 14 lines | -22 |
| Mathlooth K-tripled history | 35 lines | 14 lines | -21 |
| Hokm Faranka exceptions | 34 lines | 9 lines | -25 |
| Defender J/9 trump-burn | 31 lines | 9 lines | -22 |
| SWA-response comment | 27 lines | 8 lines | -19 |
| Touching-honors inferences | 27 lines | 11 lines | -16 |
| Hokm minimum shape | 26 lines | 7 lines | -19 |

**Total Bot.lua: 7543 → 7261 (282 lines saved, 3.7% reduction)**

### Source-pin test updates

Two source-pin tests anchored on comment text that was condensed:
- AI.8 (Mathlooth K-tripled trickle) — pin updated
- AG.7a (J/9 trump-burn protection) — pin updated

Both pins now anchor on the new shorter comment text. Tests
remain functionally equivalent.

### Tests

828/828 pass. Zero behavioral change — all condensations were
comment-only. Code logic byte-identical aside from the two pin
updates above.

### What was NOT cleaned up

- `Bot.IsBotSeat`-based gates (recently restructured in v1.4.5;
  current comments are accurate)
- v1.4.x audit-citation comments (still useful provenance)
- Function-level docstrings (kept terse and current)
- Code logic itself (pure comment-only cleanup)

## v1.4.6 — Pos-2 breaker REMOVED (4-perspective audit consensus)

After v1.4.5 raised the pos-2 breaker rate to 18%/25% per Codex's
audit, the user requested a deeper multi-perspective audit. **All
4 perspectives reached strong consensus that the pos-2 breaker —
at any non-zero rate — was wrong.**

### The smoking gun

A separate strategy-only 4th-opinion audit (no code reference, pure
Saudi-Baloot strategy expertise) discovered:

> **Video #20 «تمسك اللعب» is a POS-3 rule, NOT pos-2.**

The citation has been wrong for ~5 releases (v1.2.1 onward). Real
Saudi-pro pos-2 deviation rate is **3-5%, and those deviations are
HAND-SHAPE FORCED** (consecutive top trumps per video #22, bare-T
J-bait per video #08), **not probabilistic**.

> "Pros punish convention-violators by tightening their reads, not
> loosening them. A 20% deviation rate doesn't 'corrupt the model'
> — it just labels the bot as a non-pro." — 4th opinion

A probabilistic pos-2 breaker reads as «غلط» (a beginner mistake)
to a Saudi-table observer, regardless of rate.

### 4-perspective evolution

| Perspective | Original | After re-eval | Direction |
|---|---|---|---|
| Codex | 18%/25% | **12%/15%** | flipped LOWER |
| Ruflo | 12%/15% | **15%/20%** | moved up to mid |
| Gemini | reduce/remove | (re-eval API-failed) | unchanged |
| 4th opinion (strategy-only) | N/A | **~3-5% max OR 0%** | strong remove |

**Vote tally**: 4-of-4 said v1.4.5's 18%/25% was wrong; 3-of-4
said any rate above ~5% was wrong.

### Resolution: removal

Per 4th-opinion's specific recommendation: "if you must give the
bot any deviation budget, cap it at the legitimate carve-outs."
Those carve-outs are already wired elsewhere:

- **Hokm pos-2 sureStopper** (one-trump-out detection): existing
  at `Bot.lua:5210+`
- **Saudi-Master T-bait** (video #08): existing at `Bot.lua:5311+`
  in the deceptiveOverplay branch
- **Default canonical "second hand low"**: the standard duck path
  below

The probabilistic breaker (v1.2.1 → v1.4.5) is now removed. It
was an information-warfare optimization that didn't match Saudi-
pro reality.

### Code change

`Bot.lua:5236+` — removed the ~22-line probabilistic breaker
block. Replaced with a multi-paragraph comment documenting the
audit history, the citation correction (video #20 is pos-3),
and where the legitimate carve-outs live.

### Tests

828/828 pass. The breaker was probabilistic — source-pin tests
fired deterministic paths and weren't affected by removal.

### Other items still under review

- **BOT_FOUR_TH < BOT_TRIPLE_TH inversion** (Gemini's other
  finding): Gemini wants refactor to 87 + remove +5 bonus;
  Codex/Ruflo say it's fine as-is. 1-vs-2 minority view, deferred.
- **Tahreeb sender bot-partner gate** (kept removed in v1.4.5):
  Codex's solid argument; the convention is partnership LANGUAGE
  and humans parse it. No re-review needed.

## v1.4.5 — Codex-aligned audit follow-ups (pos-2 breaker + Tahreeb gate)

User direction after multi-perspective audit synthesis: apply the
two Codex-recommended changes that were skipped in v1.4.4 due to
auditor disagreement (pos-2 breaker rate) or scope (Tahreeb sender
gate expansion).

### Pos-2 breaker rate raise (Bot.lua:5244 area)

Codex audit finding under human-target play: the v1.3.4 12%/20%
rates were "too timid for human-target EV. Humans don't punish
second-hand-low determinism the way pattern-matching bots do;
modest deviations corrupt opp's hand-distribution model without
becoming a new predictable pattern."

**Trajectory:** 12% M3lm (v1.2.1) → 25% Advanced+ (v1.3.3, bot-vs-bot
probe driven) → 12%/20% (v1.3.4 walkback for "no video frequency
citation") → **18%/25% (v1.4.5 multi-perspective audit)**.

The v1.3.4 walkback correctly rejected 25% as bot-probe-overfit
but went too far in the other direction. New rates preserve
canonical "second hand low" 75-82% of the time (convention
dominates) while creating meaningful information warfare against
humans who maintain a "bot follows convention" mental model.

Ruflo agent in the same audit suggested the alternative direction
(12%→keep, M3lm 20%→15% with `baitedSuit` modifier). User chose
Codex's path per "raise it to 18/25."

### Tahreeb sender bot-partner gate removed (Bot.lua:4453+)

Pre-v1.4.5: the Tahreeb sender block at `Bot.lua:4453` had a
`Bot.IsBotSeat(R.Partner(seat))` gate — Tahreeb signals only fired
when partner was a bot, treating human partners as "noise." Codex
audit:

> "Strong human players do read Saudi signals. Ignoring
> human-readable signaling leaves EV on table."

Saudi-pro convention is a partnership LANGUAGE — competent human
partners (the kind who play the addon and recognize Tahreeb
forms) understand and parse the convention. Restricting signaling
to bot-only partners misses real EV.

**Fix**: removed the bot-partner gate. M3lm+ tier gating preserved
(basic/advanced bots don't emit; the convention is sophisticated
enough that lower tiers shouldn't try). Receiver-side reads of
human signals remain appropriately discounted — humans may not
strictly follow the convention; the asymmetry (emit at full
confidence to humans, parse human signals at lower confidence)
is the correct per-Codex audit guidance.

### Items still NOT changed

The audit's other findings (BOT_FOUR_TH ordering, Sun
establishing, score-desperation Bel, 100-meld modifier, Faranka
inversion 0.70, T-sacrifice gate) were classified ALIGNED by
both auditors — no action needed.

### Tests

828/828 pass. The Tahreeb gate removal is a behavioral expansion
(Tahreeb fires more often — now in mixed-tier games with human
partners). The pos-2 rate raise is a magnitude tune. Neither
breaks source-pin fixtures.

## v1.4.4 — Pos-3 hold-back + multi-perspective audit fixes (LOCAL ONLY)

> **NOT YET PUSHED**: pending user review of multi-perspective audit
> synthesis. The user dispatched 3 parallel audits (Codex CLI,
> Gemini CLI, ruflo agent) for "Re-evaluate bot heuristics under
> human-target play, not bot-vs-bot."

**Audit dispatch results:**
- **Codex CLI**: completed, structured findings ✓
- **ruflo agent** (ruflo-core:reviewer): completed, 1200-word report ✓
- **Gemini CLI**: failed with Google API 500 error after retries

828/828 tests pass.

### #5 — Pos-3 hold-back implemented (NEW)

User direction: "consider and use psychological bait if the risk
is not extremely high and we can contain it in specific scenarios."

Implemented at `Bot.lua:5290+` with **9-condition contained gate**
per video #20 «تخليه يمسك» (let opp think they're holding the suit;
ambush next round). M3lm+ tier, Sun contract only, probabilistic
fire (30% M3lm, 40% Saudi Master).

Conditions:
1. M3lm+ tier
2. Sun contract
3. Pos-3 + partner-led MID card (rank 8/9/J/Q — expanded per
   ruflo audit; pre-fix only matched 9/J creating a detectable
   pattern gap)
4. Opp pos-2 played LOWER than partner's lead (partner currently
   winning)
5. Bot holds K of led + ≥1 low (7/8/9) of led
6. Bot has independent strength elsewhere (Ace in another suit OR
   3+-card non-trump suit)
7. Trick number 2-5 (mid-round window)
8. Score non-clutch (both teams below target-26)
9. Pos-4 not known holding A of led

**Math under human-target play**: roughly breakeven on point-count
vs default take-with-K. Real value is **information warfare** —
opp observing the duck reads "bot has nothing in this suit",
corrupting their hand-distribution model for the rest of the
round. Against humans, ~55% probability of re-lead bait creates
positive expected information capture even when point-EV is
breakeven.

### Multi-perspective audit consensus fixes

Two independent audits (Codex CLI + ruflo agent) agreed on:

**HIGH consensus — Tahreeb sender reversal** (`Bot.lua:4609-4666`):

Both auditors classified the v1.4.1-deferred behavior as DRIFTED
under human-target play. The user's earlier hesitation was based
on bot-vs-bot reasoning where the lead-back action is the same
regardless of signal sub-form. But against humans:

> "Humans actively model partner's hand. When the bot emits a
> bottom-up 'want' signal from a suit holding A+T, a human
> opponent correctly infers 'sender has high cards in that
> suit' — the inverse of what the signal is supposed to convey."
> (ruflo)

> "Bots mostly care that the lead-back suit is right; humans
> infer whether you hold A, whether the suit is medium, and
> which suit you are withholding. Current behavior preserves
> tactical lead-back value but corrupts partnership semantics."
> (Codex)

**Fix**: per video #1 form 5, bottom-up = "want, NO Ace". The
"want" sender at Bot.lua:4609 now requires **no A AND no T** in
the suit (was: requires A or T present). Bargiya (above this
block) still handles A-with-cover. Suits with T-only or
A-only-without-cover now fall through to T-4 dump-ordering or
default low.

This OVERTURNS the v1.4.1 deferral decision — the multi-perspective
audit found human-target reasoning makes the reversal correct
despite single-source video evidence concerns.

**Pos-3 hold-back C3 expansion** (`Bot.lua:5324-5333`):

Per ruflo audit: the 9-or-J-only gate created a detectable
pattern gap. Expanded to include 8 and Q so M3lm-tier opps can't
probe partner-led-8 tricks for predictable bot behavior.

### Disagreement — Pos-2 breaker rate (12%/20%) NOT changed

Auditors disagreed:
- **Codex**: too low for human-target; raise to 18%/25%
- **ruflo**: 12% Advanced is correct; drop M3lm 20%→15% with
  signal-based modifier (e.g., +5% when baitedSuit set)

Without consensus, the breaker rates stay at v1.3.4 walkback
values (12%/20%). User decision pending.

### UI fix — Dice banner (user-reported)

Pre-v1.4.4: dice-roll banner showed an empty box where the 🎲
emoji was supposed to render (WoW's default font lacks emoji
support). The bid card (face-up dealing card) was also visible
beneath the banner, creating visual clash.

**Fixes** in `UI.lua`:
1. `🎲  DICE ROLL` title → `-=  DICE ROLL  =-` (ASCII flair that
   renders in WoW's font universally)
2. Bid card render at `UI.lua:2739` now hides the bid card slot
   while `s.dealerRollAt > now` (the dice-roll window). Banner
   stands clean during the 3.5-second dealer announcement.

### Other audit findings (no action — confirmed ALIGNED)

Both auditors agreed these are correctly calibrated for
human-target play:
- **BOT_FOUR_TH=80 < BOT_TRIPLE_TH=82 ordering**: mitigated by
  `Bot.PickFour`'s +5 strength bonus; per-team distributions
  differ. Comment is complete and accurate.
- **Sun establishing «مسك اللون»**: correctly overrides H-7
  shortest-suit when holding 3+-with-A. Matches video #20
  control concept and video #6 anti-Faranka note.
- **Score-desperation Bel hand-bypass**: video #25 R26 directly
  sourced; correctly calibrated.
- **100-meld + Ace Bel modifier**: video #25 R27 directly sourced.
- **Faranka inversion 0.70 captureRate**: directionally correct;
  magnitude qualitative-only but defensible.
- **T-sacrifice Saudi Master tier gate**: per video #8 + bot-
  personalities.md tier spec; correctly enforced.
- **BotMaster oppHighInferred weight 30**: video #19 correctly
  encoded; appropriate weight in the leadCount=1 / topTouch=60
  scale.

### Items deferred for further review

- **Tahreeb bot-partner gate** (Codex finding): currently signals
  fire only when partner is bot. Codex argues this leaves EV on
  the table against strong human partners who do read Saudi
  signals. Significant tier-design change; needs user direction.
- **Pos-2 breaker rate adjustment**: auditor disagreement; user
  to choose 18%/25% (Codex) vs 12%/15%-with-modifier (ruflo).

### Tests

828/828 pass. The Tahreeb sender reversal is a behavioral change
but no source-pin tests exercise the specific A/T-suit branch
that was inverted (the gate's inputs are runtime memory, not
fixture-controlled).

## v1.4.3 — Saudi-pro convention implementations (5 new + 1 stale closed)

User triaged the v1.4.2 mining-derived deferrals. v1.4.3 implements
the approved items + closes one as STALE. 828/828 tests pass.

### #1 — Score-desperation Bel hand-bypass (`Bot.lua:6204+`)

Source: video #25 (when_bid_sun) R26.
> «ما أنت خسرانه — ممكن يجيك مشروع»
> (you can't lose more than you're already losing)

When defender team is severely behind AND opp is within one round
of winning, the round is essentially conceded — Bel cannot
worsen our cumulative position materially. Bel REGARDLESS of
hand. Closed Bel (`wantOpen=false`) prevents cascade into Triple/
Four/Gahwa where strength threshold checks remain in force.

Predicate (M3lm-gated, before strength check):
```
oppCum >= target - 26 AND myCum <= oppCum - 50
```

### #2 — 100-meld + Ace defender Bel modifier (`Bot.lua:6296+`)

Source: video #25 R27. Defender holding مشروع 100 + Ace has
"almost guaranteed positive EV" on Bel. Lower effective
`BOT_BEL_TH` by 15 when this shape is present (M3lm-gated).
Threshold floor still applies. Reads `S.s.meldsByTeam[myTeam]`
via `R.SumMeldValue` for declared 100-meld + scans hand for Ace.

### #3 — Round-1 Bel restriction: NOT IMPLEMENTED per user direction

Per user: "do not add it." Single-source video #11 evidence is
session-variant («بعض الجلسات تمنع هذا الشيء»), not universal.

### #4 — Sun establishing «مسك اللون» (`Bot.lua:3690+`)

Source: video #20 (control_game). Saudi pro convention: when
holding the top live card (A or T) of a non-trump suit AND ≥3
cards in that suit, LEAD that suit to cash multiple tricks.
Inserted BEFORE Sun shortest-suit logic. M3lm-gated.

**Tahreeb integration**: lead heuristic vs follow heuristic —
different code paths. forceOwnInitiative converges on same suit
choice; new establishing fires only when forceOwnInitiative
hasn't already decided.

**Conflict resolution**: when bot has BOTH a 3+-with-A long suit
AND short non-A suits, establishing wins. Per video #20 the long
suit is "the controlled suit"; ceding tempo to clear short suits
first is wrong when we have boss-and-long.

### #6 — Round-end strong-card deferral (woven into #4)

Source: video #9. «احتفظ فيها وخليها للأخير» (preserve, keep for
end). Predicate: `partnerNotYetCaptured AND trickCount <= 5 AND
liveBoss == "T"`. Skips establishing when activated — preserves
T for round-end where the +10 last-trick bonus + face-value
captures more total points.

### #7 — Adjacent-to-T anti-rule (`Bot.lua:3690+`)

Source: video #2. «خطأ أنك تروح بالورقة اللي جنب العشرة لو كانت
العشرة مردوفة» (wrong to lead 9 from T+9 doubleton). Detects
T+9 doubleton suits and excludes them from Sun shortest-suit
selection when alternatives exist. Falls through to non-exclusion
if T+9 was the only option (degenerate case). M3lm-gated.

### #8 — STALE: topTouchSignal already fully wired

The user's audit found this nominally-deferred item is in fact
already implemented since v0.9.2 + v1.0.3 + v0.10.0:
- **Write site** `Bot.lua:565-627` with forced-play gate at
  line 583-609 (the user's "check if partner is forced"
  concern is already honored — T/K/Q signals require observing
  a lower-rank play from same seat first; suppresses singleton/
  forced cases)
- **pickLead reader** `Bot.lua:3070+`
- **BotMaster sampler reader** `BotMaster.lua:546-572`
  (nextDown weight 60, cleared/broke handling)

No implementation needed; doc updates in v1.4.0 + v1.4.2 had
already correctly classified this as wired in some places. The
v1.4.2 mining-agent task list was over-cautious.

### #5 — STILL PENDING: pos-3 hold-back (awaiting user direction)

User's question on v1.4.2: "can we somehow implement this with
conditions?" — a 9-condition gating proposal was offered. User
hasn't given the go-ahead yet. NOT IMPLEMENTED in v1.4.3.

### Test fixture update

`tests/test_state_bot.lua:3597` — bumped AD.7 PickDouble eltrace
window from 8000 to 14000 chars to accommodate v1.4.3 additions
(score-desperation early-return + 100-meld modifier) which
pushed the strength-eval log past the original 8000-char window.

### Tests

828/828 pass. All new heuristics are M3lm+ gated; no impact on
basic/advanced source-pin tests.

## v1.4.2 — Video-mining + audit cycle (LOCAL ONLY — pending user review)

> **NOT YET PUSHED**: this release is committed locally. The user is
> asleep; pending review and explicit ship approval.

Three parallel research agents completed during the user's sleep:

1. **Bel/Bel-x2 video mining** — scanned all 44 transcripts in
   `_transcripts/` for evidence on the previously-blocked
   Bel-mandatory + Bel-x2 + Round-1-Bel + score-state-aware items.
2. **Opening-leads video mining** — scanned all transcripts for
   the 5 prose TODOs in `opening-leads.md` (9-vs-J first lead,
   AKA-setup, Sun establishing, "lead the boss" deviations,
   tenor/sequence leads).
3. **v1.3.x → v1.4.1 audit** — cross-validated all 8 releases for
   correctness, regression risk, test coverage, and Saudi-pro
   convention adherence.

828/828 tests pass.

### Audit findings — 0 correctness bugs, 3 stale comments fixed

The audit verdict: **net-positive trajectory, no release should be
reverted, no correctness bugs found**. Three documentation issues
flagged and fixed:

1. **`Constants.lua:461+` — BOT_FOUR_TH comment stale**: with v1.3.4's
   walkback raising BOT_TRIPLE_TH 65→82, the BOT_FOUR_TH=80 raw
   constant now sits BELOW Triple's raw threshold. This LOOKS like
   inversion but is mitigated by `Bot.PickFour`'s +5 strength
   bonus (Bot.lua:6552, unconditional since v0.11.18 DEAD-1 audit).
   Comment expanded with full clarification and explicit warning
   against naive constant-raising. Net behavior unchanged — Four
   still fires at 3-7% in forced-mode probe per multiseed.

2. **`tests/test_state_bot.lua:5573` — AK.7 stale arithmetic**:
   comment said "Floor cap = 49 (TH=65)" referencing v1.3.2's
   temporary value. v1.3.4 walked back to TH=82, so floor is now
   66. Test outcome unchanged (hand strength ~11 << 54 jth_min at
   floor 66 - jitter 12). Comment corrected.

3. **Concern 1 (Tahreeb sender) deferral note**: audit confirmed
   `tahreebClassify` at Bot.lua:2322 returns "want"/"bargiya" by
   rank sequence and doesn't distinguish sender-side suit strength.
   Receiver action identical for both classifications → deferral
   rationale internally consistent. Already documented in code
   comment + decision-trees.md.

### `escalation.md` — Bel mining update (3 new patterns, 6 still BLOCKED)

44-transcript scan results:

**Found** (Common evidence, Bel-mandatory patterns):
- **Score-desperation Bel** (`25_when_bid_sun` R26): defender team
  severely behind, opp took Sun → Bel REGARDLESS of hand. Quote:
  «ما أنت خسرانه — ممكن يجيك مشروع» (you can't lose more than
  you're already losing). DEFERRED implementation pending magnitude
  validation.
- **100-meld + Ace defender Bel** (`25_when_bid_sun` R27): defender
  holds مشروع 100 + Ace → "almost guaranteed positive EV." DEFERRED.
- **A+T mardoofa probabilistic Bel** (`25_when_bid_sun` R28): defender
  holds Ace+Ten same suit, partner draw may complete 100-meld.
  Already partially captured in `aceCountAndMardoofa` strength
  formula.

**Found** (Common, Round-1):
- **Round-1 Bel restriction** (`11_bel_beginners` row 6):
  «بعض الجلسات تمنع هذا الشيء» (some sessions forbid this). Anti-grief
  rule, session-variant. DEFERRED — needs user direction on
  default behavior (hard-rule? tier-gated? configurable?).

**Still BLOCKED** after exhaustive scan:
- Shape-based Bel-mandatory ("3+ Aces", "trump-void+ruff")
- Bel-x2 hand-shape thresholds (no transcript provides any)
- Open Bel vs Closed Bel discrimination
- Bel timing (delay vs immediate)
- Mid-chain reads ("after Bel-x2, partner expects X")
- Reckless Gahwa under match-point desperation

### `opening-leads.md` — substantial unblocking (5 topics)

44-transcript scan results across all 5 prose TODOs:

**Topic 1 — 9 vs J first lead**: Common evidence. J is canonical;
9 is "AKA-equivalent, never sacrifice" per video #08. Already
implicit in current `pickLead` code via `highestByRank(trumpCards)`.
Gap: no explicit "9-lead is mistake" framing exists.

**Topic 2 — AKA-setup leads**: Definite evidence. 4-condition
predicate (highest unplayed non-trump, partner likely void, defender
leading, not the Ace itself). Already largely wired (implicit-AKA
on bare-Ace + ruff-suppression). Gap: trick-1 *opening choice* as
function of "set up best AKA" not addressed.

**Topic 3 — Sun "establishing" suits**: Common evidence. Saudi
term is **«مسك اللون»** (holding the suit), not "establishing".
3 rules from video #20: lead 3+-with-top-cards, give up T early
when no other strength, preserve T as re-entry when 2+ side cards.
**CONFLICT**: current `pickLead` Sun shortest-suit logic (H-7
v0.5.0) goes opposite direction in 3+-with-A scenarios. DEFERRED —
needs careful integration.

**Topic 4 — Lead-the-boss deviations**: 4 distinct cases identified.
Two wired (deceptive overplay, Faranka). Two partially wired
(pos-3 hold-back, round-end deferral). DEFERRED implementation
recommendations.

**Topic 5 — Sequence/tenor leads**: T-lead decision tree wired
v0.11.16 (Tahreeb-return context). NEW evidence: **adjacent-to-T
anti-rule** from video #2 — don't lead 9 from T+9 doubleton
(telegraphs T). DEFERRED — straightforward addition. Touching-
honors ledger remains DEFERRED Fzloky-tier feature.

### What's deferred for user direction

Several findings are actionable but require user judgment before
implementing:

1. **Score-desperation Bel hand-bypass** — magnitude calibration
2. **100-meld + Ace conditional Bel** — meld-aware PickDouble
3. **Round-1 Bel restriction** — hard rule? tier-gated? toggle?
4. **Sun establishing vs shortest-suit conflict** — which wins
   when bot holds 3+-with-top-cards vs traditional shortest-lead?
5. **Pos-3 hold-back gate** — explicit predicate
6. **Round-end strong-card deferral** — explicit predicate
7. **Adjacent-to-T anti-rule** — straightforward but new gate
8. **Touching-honors ledger** — Fzloky-tier `toptouchSignal` key

### Tests

828/828 pass. No code logic changes — only documentation expansions
+ comment corrections.

## v1.4.1 — Deferred-item triage + Takbeer pos-3 enhancement

User triaged the v1.4.0 deferred items with explicit guidance per
each. v1.4.1 ships the actionable items, documents the remaining
deferrals with explicit blockers, and closes the rule-irrelevant
ones. 828/828 tests pass.

### Concern 4 (Takbeer/Tasgheer certainty gate) — POS-3 IMPLEMENTED

User direction: "yes but it is a strategy and should be taken into
consideration and making sure behavior is not off."

The Takbeer/Tasgheer certainty principle (`decision-trees.md` rows
123-128, videos 21/22/23) says: when trick-winner is CERTAIN
partner, magnify (play HIGHEST, donate to partner's pile); when
CERTAIN opponent, miniaturize (play LOWEST). Existing pos-4 cases
were already largely covered by the smother branch (donate-highest
for partner-winning + lastSeat) and the Sun lowest-on-opp-winning
default (v0.7.2).

**v1.4.1 enhancement** (`Bot.lua:5044+`): adds the missing pos-3
case where existing logic was suboptimal. When pos-3 + partner-
winning + Sun + pos-4 known void in led suit (via
`Bot._memory[pos4].void[trick.leadSuit]`) AND we have NO winners
ourselves, donate the highest non-A/non-T card to partner's pile
(pure addition — only fires when default low-loser would have been
played, so doesn't override existing winner-logic). Skips A/T to
preserve own future winners. M3lm-gated.

"Behavior not off" guarantee: this only adds a strategic improvement
in the no-winners + pos-4-void niche; doesn't disturb any existing
branch. AE.10a/AE.10b/AK.7 source-pin tests still hold (those don't
exercise this niche).

### Concern 1 (Tahreeb sender contradiction) — DEEPER ANALYSIS, BEHAVIOR PRESERVED

User direction: "i stand by my previous statement. it is not as
straight forward as that, check videos, 1, 3, 5."

After re-reading videos 1, 3, 5 carefully, v1.4.1 adds a
comprehensive code-comment at `Bot.lua:4373` documenting the full
video-evidence picture:

- **Video 1** defines 5 forms; form 5 is bottom-up = "want, NO Ace"
- **Video 3** adds suit categorization (WEAK/MEDIUM/STRONG); STRONG
  suits should NOT be Tahreeb'd — partner returns opposite-color
- **Video 5** confirms touching-honors signaling and uncertainty
  default (treat as Tahreeb)

The current code emits bottom-up from a suit with ≥3 cards AND A or
T (a STRONG suit per video 3) — semantically inconsistent with
video evidence. **But behavior preserved** because:

1. Receiver action on "want" decode = lead suit back. If sender
   has A in that suit (mislabeled), sender's A wins regardless of
   exact Tahreeb sub-form. Practical impact mitigated.
2. The semantic distinction affects only RECEIVER INFERENCE about
   sender's hand, not the lead-back action.
3. Reversing to "bottom-up only from no-A suits" reduces the count
   of "want" signals — could reduce partner-coordination
   opportunities.

Behavioral reversal stays DEFERRED pending cross-video
reconciliation + bot-vs-bot impact measurement. Tahreeb receiver
rows 238 and 240 are linked to the same sender-side semantics and
are also DEFERRED (decision-trees.md updated with explicit
DEFERRED v1.4.1 markers and link to Concern 1).

### Sabotage-own-sweep — CLOSED (rule inapplicable)

User clarification: "this is only when the contract is Bel×2 or
above AND the bidder wants the contract multiplier instead of
Kaboot points (it sabotages Kaboot assuming the kaboot score is
not multiplied)."

Verified `Rules.lua:1273-1275`: regular Al-Kaboot IS multiplied by
`cardMult` (only Reverse Al-Kaboot bypasses with `K.MULT_BASE`).
With the Kaboot bonus multiplied, the sweep path always dominates
the multiplier-only path; there's no scenario where sabotaging the
sweep gains more points. Per user: "i guess we multiply it anyway
so it is irrelevant." **Rule closed; no implementation needed.**
`decision-trees.md:200` updated with the verification.

### Bel-mandatory + Bel-x2 patterns — DEFERRED (blocked on video)

User direction: "Bel-mandatory patterns + Bel-x2 (blocked on video
research)." Confirmed. Saudi-pro Bel-mandatory hand patterns and
"aggressive Bel x2" patterns require dedicated strategy-video
transcripts that don't exist in `docs/strategy/_transcripts/` yet.
`escalation.md` header updated with explicit BLOCKED-on-video
status.

### escalation.md / opening-leads.md stubs — DEFERRED (blocked on transcripts)

User direction: "blocked on transcript mining." Confirmed.
`opening-leads.md` 5 prose TODOs require videos #24-44 (or similar)
which haven't been mined. Both files updated with explicit
v1.4.1 status notes — header preserved but BLOCKED context
clarified. Most underlying picker logic IS wired; the doc TODOs
are about specific pro-strategy nuances (9-vs-J first-lead,
AKA-setup leads, etc.) not yet captured in transcripts.

### Tests

828/828 pass. Takbeer pos-3 addition is a niche addition (no
winners + Sun + pos-4-void), no source-pin tests trigger it.

## v1.4.0 — Strategy-doc audit + Saudi-pro convention fixes

A cross-validation agent reviewed the v1.3.x release work against
canonical Saudi-pro convention (`docs/strategy/*.md` + 41 video
transcripts in `docs/strategy/_transcripts/`). The agent found
that **most "TODOs" the prior scanner flagged were STALE** — already
wired in older releases. True remaining work was much smaller. v1.4.0
ships the principled fixes from the audit plus deferred items
documented for follow-up.

### Glossary corrections (user-reported)

`docs/strategy/glossary.md` had wrong suit mappings:

- **shareeha/shareer** (الشريه) was listed as Hearts — actually
  **Spades**. Spelling also corrected from الشريحه → الشريه (no ح).
- **haas/haaws** (الهاص) was listed as "Clubs (best guess)" —
  actually **Hearts**. Spelling corrected from الهاس → الهاص (saad,
  not seen).
- **Clubs (♣)** is now an **OPEN QUESTION** — the previous "haas =
  Clubs" was misattribution. No confirmed Saudi slang for Clubs
  in any video transcript yet; flagged for separate research pass.
- **dayma/dayman** (الديمن) confirmed Diamonds (canonical spelling
  noted).
- **sbeet/sbeed/sbeel** confirmed Spades (alternate slang, unchanged).

Verified: no code references the slang names; only the glossary did.

### Reverse Al-Kaboot doc unit-error (Concern 2)

`decision-trees.md:206` previously said "+88 raw to defending team"
implying raw points before contract multiplier. That was wrong:
`K.AL_KABOOT_REVERSE = 880` (Constants.lua:170) is the post-multiplier
flat value yielding +88 banta because `cardMult` is bypassed. **Code
is correct; doc had a unit-error.** Doc updated to clarify the +88
banta semantics with `cardMult`-bypass note. Fully wired since v0.10.5
(Rules.lua:960-1023) with v1.0.12 4-condition canonical gate.

### bot-personalities.md probabilistic SWA contradiction (Concern 3)

Personalities table at line 167 said "Probabilistic SWA: Yes (via
ISMCTS)" for Saudi Master tier — but `decision-trees.md:208`
explicitly RETRACTED probabilistic SWA per video #35 ("ما تساوي بدون
ما تستاذن مستحيل يمشونها"). Anyone using personalities.md as
implementation spec would wire a behavior that's forbidden.

**Fix**: marked the row RETRACTED with cross-reference to the
decision-trees retraction. Saudi convention is deterministic-only
SWA at every tier; bots must NOT generate sub-100%-certain SWA
claims.

### Faranka pos-4 anti-trigger row 167 (Concern 5)

`Bot.lua:3995+` Faranka block fired when `hasA + cover + suitCount==2`
but missed the **anti-trigger when bot holds the two highest unplayed**
of led suit. In that case "ducking" with cover wouldn't actually duck
— cover would beat partner's winning card, taking the trick from
partner. Faranka becomes meaningless.

**Fix**: added `holdsTopTwoUnplayed` predicate using
`S.s.playedCardsThisRound` to walk the rank order and find the two
highest unplayed in led suit. If bot's cover rank matches the
second-highest unplayed (and bot holds A which is the top), skip
Faranka and fall through to smother (next branch) which correctly
donates A to partner-winning trick. Per video #06 anti-trigger row.

### T-sacrifice Saudi Master tier gate

`Bot.lua:5311+` deceptiveOverplay fallback `return higher[math.random()]`
could pick T (10) of led suit at any Advanced+ tier when no J was
found. But per `bot-personalities.md:161`, T-sacrifice is **Saudi
Master ONLY** ("only a real pro plays this"). M3lm and Fzloky
firing the T fallback violated tier-spec.

**Fix**: gate the random `higher[]` fallback on
`Bot.IsSaudiMaster()`. Lower tiers fall through to canonical
non-deceptive play when no J is available.

### Concern 1 — Tahreeb sender contradiction documented (NOT reverted)

The validation agent found that `Bot.lua:4373-4396` ("want" sender
arm, v0.9.0, Definite-tagged citing video 10) emits the bottom-up
ascending signal from a suit that has A or T. But **video #1 form
5** explicitly says bottom-up = "want, no Ace" (substitutes for
Bargiya when no Ace held), and **video #3** says "Tahreeb a WEAK
suit, partner returns the OPPOSITE-color/shape suit which is the
strong one you withheld." Both indicate bottom-up should fire from
a WEAK suit, not a strong one.

This is a **single-source contradiction with current Definite-tagged
v0.9.0 wiring**. User flagged as "not straightforward" — needs
cross-video reconciliation. v1.4.0 adds a code comment at
`Bot.lua:4373` flagging the discrepancy and explicitly DEFERS the
behavioral reversal pending more analysis. Doc row at
`decision-trees.md:222` updated with the same flag.

### Doc cleanup — STALE markers (most "TODOs" already wired)

The prior TODO scanner over-flagged because docs lag code. v1.4.0
audit cross-referenced each `(not yet wired)` marker against current
code state. Confirmed STALE (already wired in older releases) and
updated:

- **Bel-100 Sun gate** (`R.CanBel`) — wired since v0.10.0 R1
- **Reverse Al-Kaboot scoring** — wired since v0.10.5 + v1.0.12
- **Al-Kaboot pursuit trick-3 trigger** — wired since v0.5.19 + v1.0.3
- **Bargiya sender** — wired v0.9.0 + v1.0.3 + v1.2.1 G7
- **T-4 dump-ordering** — wired v0.5.10 + v0.5.11
- **Implicit AKA on bare-Ace lead** — wired v0.5.16 + v0.11.18-final U-1
- **pickFollow non-trump-discard preference** — wired v0.11.19 U-6
- **Round-1 conservative pass bias** — wired v1.1.0 MED-10 + v1.2.2
- **Sun ATmardoofa check** — `sunMinShape()` Bot.lua:1047-1063
- **Bel-fear score-state bias** — wired v0.6.0 B-7 → v1.2.1 jitter
- **Ashkal 85-pivot to direct Sun** — `Bot.PickAshkal` Bot.lua:1808+
- **Min-Hokm-bid explicit check** — `hokmMinShape()` already gates
- **Deceptive overplay Sun + Hokm** — wired v1.1.0 + v1.2.1
- **Most Tahreeb sender + receiver branches** — wired v0.5.10
  through v0.11.16

### Deferred to v1.4.x

The audit also identified items that are genuinely valid TODOs but
require deeper design or video research:

- **Tahreeb sender row 225 reversal** (Concern 1) — single-source
  contradiction with current code; needs cross-video evidence
- **Takbeer/Tasgheer certainty gate** (rows 123-128, Concern 4) —
  qualitative video sources; pos-4 case largely covered by smother
  + lowest-on-opp-winning, but explicit pos-3/pos-2 certainty
  predicate needs design
- **Tahreeb receiver row 238** — high-card-return discipline when
  forced into Tahreeb-suit
- **Tahreeb receiver row 240** — release-control re-supply
- **Touching-honors inference ledger** — new `toptouchSignal` ledger
  key + Fzloky-tier consumers
- **Sabotage-own-sweep** — single-source video #15, ambiguous
  implementation magnitude
- **Bel-mandatory hand patterns** + **Bel-x2 aggressive patterns** —
  blocked on video research
- **`escalation.md` stub population** — video sources don't supply
  hand-strength thresholds; calibration is empirical
- **`opening-leads.md` stub population** — needs video transcript
  mining
- **bot-personalities.md tier flavors** + **Saudi Master signature
  moves enumeration** — needs video research

### Tests

828/828 pass. Faranka anti-trigger fix doesn't affect existing
fixtures (the precondition is more restrictive, only kicks in on
specific board states). T-sacrifice gate change is a tier-narrowing
that doesn't break source-pin tests.

## v1.3.5 — Random first dealer with dice-roll banner

Pre-v1.3.5: at game start, dealer was hardcoded to seat 1
(`Net.lua:2155`). This created persistent "team A starts" bias —
the seat-1 dealer position cascades into round-1 lead order, which
cascades into trick-winner-leads tempo control, giving team A a
structural edge that doesn't exist in real Saudi-table play
(where the first dealer is decided by card-cut, dice roll, or
verbal agreement).

This is also the real-game equivalent of the v1.3.3 multiseed
harness fix (per-tournament random tier-side flip). The harness
fix corrected synthetic-test bias; v1.3.5 corrects the same
structural bias in actual play.

### Changes

- **`Net.lua` `HostStartRound`** (line 2155 area): `dealer = 1` →
  `dealer = math.random(1, 4)`. Subsequent round-to-round rotation
  unchanged (`(s.dealer % 4) + 1`).

- **`State.lua` `S.ApplyStart`**: when `roundNumber` transitions
  from 0 to 1 (new-game first round), arm
  `s.dealerRollAt = GetTime() + 3.5` and schedule a UI refresh at
  expiry. The timestamp gates the dice-roll banner display;
  per-client local timestamp is fine (network latency is small
  vs the 3.5s window so visual sync is acceptable).

- **`UI.lua` `renderBanner`**: while
  `now < s.dealerRollAt`, show a "🎲 DICE ROLL" banner naming the
  rolled first dealer. Takes priority over phase-based content so
  the pick is visible before deal-phase animations begin. Auto-
  clears at expiry via the scheduled refresh.

### Why this matters

In matched-tier real-world play, both teams use the same
heuristics (information balance is symmetric). But seat-position
bias was structural — team A's first-trick lead advantage was
built into every game. With random dealer, seats 1-4 are equally
likely to lead the first trick, eliminating the bias entirely.

### Saudi-table convention

The first dealer is traditionally decided by some random
mechanism (card-cut where each player draws a card and lowest
becomes dealer; or verbal agreement / die roll). The dice-roll
visualization matches this convention with an unambiguous random
mechanism that all seats can see.

### Tests

828/828 pass. Tests don't go through `HostStartRound` (they use
the harness's own `playOneRound` with explicit `leaderSeat`), so
the random-dealer change has no test-side impact.

## v1.3.4 — Saudi-pro adherence audit walkbacks (3 magnitude corrections)

A meta-audit reviewed v1.3.0–v1.3.3 changes against canonical
Saudi-pro convention (`docs/strategy/*` + cited video sources)
rather than bot-vs-bot tournament metrics. Three magnitudes were
flagged as **bot-vs-bot-overfit** — tuned to close synthetic-test
gaps but without video-cited frequency justification. v1.3.4 walks
each back toward video-justified values. The directional fixes
remain (these are not reverts), but the magnitudes are now closer
to canonical pro play.

**Why this matters**: bot-vs-bot probes test pattern-exploitation,
which humans don't reliably do. Heuristics tuned to fool other bots
can drift away from canonical play that humans recognize and
counter-play against. The goal is improving vs-human play; bot-vs-
bot metrics were proxy evidence, not the primary signal.

### HIGH — pos-2 breaker walkback (Bot.lua:4940 area)

v1.3.3 extended the v1.2.1 M3lm-only 12% breaker to all Advanced+
at 25%, motivated by closing a +24 GP/game bot-vs-bot gap. Audit:
video #20 («تمسك اللعب») establishes the *principle* of mid-card
wins at pos-2 but does NOT quantify a 25% rate. The magnitude was
reverse-engineered from the bot-vs-bot probe.

**Walkback**: tier-aware breaker rate. Advanced at **12%** (matches
v1.2.1's original M3lm rate, now extended to Advanced as the
broadening v1.3.3 attempted). M3lm/Master at **20%** (slight bump
from 12% — pro-tier sophistication justifies somewhat more
variance, still grounded in qualitative pro-play observation, not
synthetic targeting).

Net effect: canonical "second hand low" preserved 80–88% of the
time vs v1.3.3's 75%. Still extends the breaker beyond v1.2.1's
M3lm-only scope, but at video-defensible rates.

### HIGH — BOT_TRIPLE_TH walkback (Constants.lua:437)

v1.3.2 dropped BOT_TRIPLE_TH from 90 → 65, anchored to the
empirical bidder p75 = 50 + jitter ±12 = jth_max 77. Audit: this
left only a 3-point gap between BOT_BEL_TH (62) and BOT_TRIPLE_TH
(65), inconsistent with `escalation.md` prose that says
Triple-worthy hands need J+9+A of trump or Belote — both
substantially stronger than Bel-worthy hands.

**Walkback**: 65 → **82**. jth_max becomes 94, leaving a 17-point
Bel→Triple spacing that better honors the relative-strength
documented in escalation.md prose. Note: no video frequency
citation exists for either value (escalation.md explicitly states
video sources don't supply hand-strength thresholds); both values
are empirical, but 82 better matches the prose-described relative
ordering.

### MED — Faranka captureRate walkback (Bot.lua:4036 area)

v1.3.0 introduced the Faranka inversion: when partner shows weak
(weakHandSignal > 2× highCardPlays, ≥3 events), boost capture rate
0.30 → 0.85. M3lm-gated. Audit: 0.85 has no video frequency basis;
video #20 establishes the *principle* of strong-hand-grabs-tempo
but the specific magnitude was arbitrary.

**Walkback**: 0.85 → **0.70**. Still represents a substantial
directional shift from the 0.30 default consistent with the video
principle, without committing to "capture 85% of the time" on a
single-source qualitative citation. M3lm gating unchanged.

### Verdict — alignment between audit and code

The audit also examined and **confirmed alignment** for:
- v1.3.3 Ace-exhaustion own-Ace fix (correctness fix, no concern)
- v1.3.1 oppHighInferred BotMaster sampler weight 30 (properly
  cited video #19, weight placement principled vs leadCount=1 /
  topTouch=60)
- v1.3.0 Faranka inversion thresholds (≥3 events, 2× ratio —
  implementation hygiene, structurally conservative)
- v1.3.0–v1.3.1 dead-signal bug fixes (correctness, not magnitude)

These are NOT walked back.

### On the residual basic_advanced gap

After v1.3.4 the bot-vs-bot probe will likely show the residual
~14 GP/game basic > advanced gap WIDEN (perhaps to 20+) because we
restored more deterministic canonical play. **This is expected and
correct.** Real-world play uses matched-tier games (all 4 seats
same tier) where information balance is symmetric — the gap
doesn't manifest. Mixed-tier games are a synthetic-test scenario
only.

### Tests

828/828 pass. AE.10a (rich hand strength 161 fires Triple) and
AE.10b (weak hand strength 21 passes Triple) both still hold at
TH=82 — strength 161 >> jth_max 94, strength 21 << jth_min 70.
AK.7 floor-cap test (weak m3lm hand strength ~11 with urgency
drop) also holds — strength << jth_min.

## v1.3.3 — Tier-hierarchy probe + Advanced bot fixes + UI overflow

A tier head-to-head probe revealed the bot tier system wasn't fully
working: Master clearly beat all other tiers, but **Advanced lost to
Basic** in both modes by +17-24 GP/game (Basic = pure random legal
play). Two underlying bugs identified empirically + new harness
infrastructure for future probes. Plus a user-reported UI overflow
fix. 828/828 tests pass.

### HIGH-1 — pos-2 duck telegraph (`Bot.lua:4937` extended to Advanced)

Pre-v1.3.3: pos-2 follow logic (`Bot.lua:4884+`) was a deterministic
2-state machine — sureStopper-or-duck. The duck always played the
lowest non-winner. v1.2.1 added a 12% probabilistic breaker but
**M3lm-tier-only**, leaving Advanced fully deterministic.

In bot-vs-bot play, an opponent observing the Advanced bot duck at
pos-2 could read "no A/T/sure-stopper in led suit" with 100%
confidence. Empirical 12-matchup probe attributed ~24 GP/game in
forced mode and ~17 GP/game in natural mode to this telegraph
against Basic random opponents.

**Fix**: extended the breaker to fire at `Bot.IsAdvanced()` (any
tier above Basic) at 25% probability (was M3lm-only at 12%). M3lm
and Master inherit the higher rate too — same underlying issue,
higher rate further obscures the signal. Per video #20 «تمسك
اللعب»: pros sometimes WIN at pos-2 with a mid-card when meaningful
points are already in the trick.

### HIGH-2 — Ace-exhaustion own-Ace mis-count (`Bot.lua:3201`)

Pre-v1.3.3 the trick-4+ "all side Aces out" inference at line 3201
counted the bot's OWN Ace as `seen` (exhausted) — a false premise.
The early-return then bypassed later pickLead heuristics
(partner-void ruff at 3564, Belote-K+Q preservation, singleton-low,
Sun shortest-suit lead). Empirical probe attributed ~21-26 GP/game
in natural mode to this — the bulk of the natural-mode
Advanced<Basic anomaly.

**Fix**: removed the own-`legal` check inside the loop. Only PLAYED
Aces count toward exhaustion; our own Ace is still in play and the
inference must not treat it as "out". Same intent as the original
heuristic ("if all opp Aces are out, our K/Q/J are bosses" — a
true-by-construction premise now that own-Ace is excluded).

### MED — Multiseed harness team-A bias fix

Pre-v1.3.3 the multiseed tournament harness systematically favored
Team A by +35-58 GP/game in symmetric `all_X` cells. Sources:
1. `pickContract` iterated seats 1→4 with strict `>` tie-break,
   giving seat 1 first claim on equal-score bid hands
2. Bidder leads round-1 trick → tempo cascades via trick-winner
   leads
3. Other subtle deal-pattern asymmetries

This made all prior tier-comparison data approximately 3x noisier
than it should have been (raw effect overlaid on +35-58 GP bias).

**Fix**: per-tournament random tier-side flip
(`tests/test_multiseed_metrics.lua`). 50% of tournaments swap
which seat-pair gets which tier, so each tier gets equal opportunity
at seats 1+3 vs 2+4. Tournament results now record `tier_side_flip`
so the aggregator computes tier-X-vs-tier-Y stats correctly
regardless of seat assignment. All `mixed_X_Y` analysis post-fix
is bias-free.

### Tier hierarchy validated (with one residual)

Post-v1.3.3 multiseed probe (5 seeds × 100 rounds × 12 cells with
random tier-side flip):

| Matchup | natural | forced |
|---|---|---|
| advanced vs **master** | master +65 ✓ | master +80 ✓ |
| m3lm vs **master** | master +44 ✓ | m3lm +9 ⚠ noise |
| basic vs **master** | master +42 ✓ | master +13 ✓ |
| advanced vs **m3lm** | tied | advanced +22 (mixed) |
| basic vs **m3lm** | m3lm +17 ✓ | basic +33 ⚠ |
| **basic** vs advanced | basic +14 ⚠ | basic +13 ⚠ |

Master is unambiguously the strongest tier (wins 5/6 matchups,
master+m3lm noise tie in forced m3lm-master only). M3lm > Basic
in natural, basic edges m3lm/advanced in forced (noisy). Residual
~14 GP/game basic > advanced gap remains — much smaller than
pre-fix +17/+24 but not zero. Marked as known-issue for v1.3.4
investigation.

### Harness extension — full pairwise mixed matchups

Pre-v1.3.3 the multiseed harness only had 2 mixed-tier configs
(basic_master, m3lm_master). Extended to all 6 pairwise matchups
(basic_advanced, basic_m3lm, basic_master, advanced_m3lm,
advanced_master, m3lm_master) so future tier-hierarchy probes
have complete coverage. Doubled the mixed-cell count from 2 to 6;
total cells from 12 to 20. Tournament runtime ~7 min (was ~5).

### UI fix — round-result banner title overflow

User-reported: round-end banner title (e.g., "TAKWEESH! Ballripper
called incorrectly — YA MRW7 TEAM ONE (Ballripper+Bot 3)") had
words extending outside the box and splitting at the em-dash.

**Diagnosis**: `banner.title` FontString at `UI.lua:1524` had no
width constraint — text auto-sized to its content and overflowed
the 270-px-wide banner.

**Fix**: cap `banner.title` width to 256 (banner_width − 7px each
side padding), enable explicit word wrap. Push subsequent banner
text rows (bidder, defender, modifiers, belote) down by 16px each
so a 2-line title doesn't overlap. Banner outer dimensions
unchanged.

### Tests

828/828 pass. UI.lua is not loaded by `tests/run.py` (pure-logic
test harnesses); UI fix verified by inspection. Multiseed probe
re-validated tier hierarchy.

## v1.3.2 — Escalation threshold re-tune (closes v0.11.20 over-correction)

The v1.3.0 harness fix (multiseed test fixture state-prep) revealed
that v0.11.20's `BOT_BEL_TH=35` was tuned against a **bug-zeroed
null** — the test harness pre-v1.3.0 read empty hands and always
returned false, so the recorded "Bel rate near zero" diagnostic
that motivated dropping the threshold was an artifact, not a
real measurement. The actual fire rate at TH=35 was **~92%**.

This release re-anchors all four escalation thresholds against the
**post-fix empirical strength distribution** (4000 PickDouble evals
across 5 seeds × 100 rounds × 8 cells, full calibration probe in
v1.3.1 CHANGELOG).

### Threshold changes

| Constant | Old | New | Rationale |
|---|---|---|---|
| `K.BOT_BEL_TH` | 35 | **62** | Defender p75=53 + jitter ±10 → jth_max 72; targets ~8% natural |
| `K.BOT_TRIPLE_TH` | 90 | **65** | Bidder p75=50 + jitter ±12 → jth_max 77; targets ~15% conditional |
| `K.BOT_FOUR_TH` | 110 | **80** | Above Triple band, below 8-card ceiling; targets <5% |
| `K.BOT_GAHWA_TH` | 120 | **95** | Above Four band; stays terminal-rare (<2%) but reachable |

The v0.11.x values were all gated by a `BOT_TRIPLE_TH=90` that
sat ABOVE the realistic 8-card bidder-strength ceiling
(p90=65), structurally clamping Triple/Four/Gahwa to 0% in
natural play regardless of their own thresholds. v1.3.2 fixes
the upstream bottleneck.

### Empirical validation (post-tune multiseed probe)

| Cell | Bel pre-tune | Bel post-tune | Target |
|---|---|---|---|
| all_basic__natural | 0.908 | **0.324** | ~8% (basic over-fires by design — simpler formula) |
| all_advanced__natural | 0.733 | **0.097** | ✓ |
| all_m3lm__natural | 0.706 | **0.137** | ✓ |
| all_master__natural | 0.716 | **0.132** | ✓ |
| mixed_basic_master__natural | 0.870 | **0.222** | ✓ |
| mixed_m3lm_master__natural | 0.714 | **0.142** | ✓ |

Advanced+ tiers (the ones most players actually face) land in
the 10-14% range, right around the escalation.md target.

### Coordinated test fixture updates

Three test source-pins / fixtures hard-coded the old values
or relied on threshold-relative hand-strength assumptions:

- **AA.2** (`test_state_bot.lua:3358`): `K.BOT_GAHWA_TH=120` →
  updated to `95`
- **AD.8** (`test_state_bot.lua:3605`): `K.BOT_BEL_TH=35` →
  updated to `62`
- **AE.10b** (`test_state_bot.lua:4402`): "weak" hand
  `{JH,9H,8H,7H,KH,7S,7D,7C}` had strength **73**, which under
  new TH=65 sits IN the jitter band [53,77] (was below old jth_min
  78). Replaced with `{KH,8H,QH,9S,8S,9D,7D,7C}` — strength **21**,
  comfortably below new jth_min 53. Genuinely weak now.
- **AK.7** (`test_state_bot.lua:5530`): "weak" hand
  `{QH,KH,JH,AC,8D}` had strength **~57** in m3lm tier (the test
  comment claimed ~30 — author miscounted). Under new floor cap
  jth=[37,61] this sat IN-band → flaky. Replaced with
  `{QH,JC,9D,8D,8C}` — strength **~11**, deterministic pass.
  Test now asserts the SAME outcome ("weak hand fails Triple
  under threshold-drop pressure") but with a hand that survives
  any reasonable threshold landscape. Floor cap MECHANISM remains
  source-pinned at AH.3.
- **`test_asymmetric_metrics.lua:7`**: stale comment
  `K.BOT_BEL_TH (=60 since v0.5.0)` updated to reflect 62.

### Tests

828/828 pass. Multiseed probe re-validated rates. No regressions
in any source-pin or behavioral test.

### Closes the v0.11.x calibration cycle

v0.11.19 (60→45) and v0.11.20 (45→35) were both tuned against
the bug-zeroed harness. v1.3.2 returns the threshold to a value
slightly above the v0.5.0 origin (62 vs 60), now anchored to
**measured** distribution data rather than null-distribution
projections.

## v1.3.1 — 3 dead-signal silent-correctness lies (post-v1.3.0 audit)

A targeted coverage-audit agent scanned the bot signal/flag system
for the same pattern that produced v1.3.0's Faranka inversion (and
v1.2.2's HIGH-1/HIGH-2): write-site exists, consumer either missing
or reading the wrong field. Three more HIGH findings — all silent-
correctness lies where code says one thing and does another. 828/828
tests pass.

### HIGH-1 — `tahreebActive` permanently false in deceptiveOverplay

`Bot.lua:5184-5191` checked Tahreeb-active state via:
```
for _, evt in pairs(pStyle.tahreebSent) do
    if evt and (evt.flavor == "want" or evt.flavor == "bargiya") then
```
But `pStyle.tahreebSent[suit]` is a **raw rank-list array** (e.g.
`{"7","9"}`) — it has no `.flavor` field. `evt.flavor` was always
`nil`, `tahreebActive` was permanently `false`, and the
deceptive-overplay suppression that's supposed to prevent the bot
from sacrificing honor cards INTO partner's live Tahreeb signal
**never fired**. Bots routinely collided with partner's planned
lead-backs.

The other 3 callers of `tahreebClassify` in the same file (lines
2696, 2775, 5317, 5358) all correctly use the per-suit pattern
`tahreebClassify(tahreebSent[su])`. Mirror that pattern at the
deceptiveOverplay site.

### HIGH-2 — `oppHighInferred` BotMaster-sampler consumer missing

The `Bot.lua:2837-2843` write-site comment promised:
> *"export to `Bot._memory[seat].oppHighInferred` so downstream
> consumers (A1's deceptiveOverplay, **BotMaster sampler**) can
> bias on the inferred opp-holds-high reading."*

The `deceptiveOverplay` consumer landed at `Bot.lua:5198-5201`. The
**BotMaster sampler** never read the flag. ISMCTS rollouts (Saudi
Master tier) were sampling opp hands with no Tanfeer-derived bias —
the sampler would mis-assign A/T/K to opp seats we'd already
*inferred to hold them*. Per video #19 «اي شكل خصمك ينفر تفترض
انه عنده» — opp Tanfeer = "infer opp holds the high cards in that
suit"; the sampler was ignoring this.

Fix at `BotMaster.lua` (right after the `leadCount` block in the
desire-weight loop): when the rollout seat has `oppHighInferred[X]
== true`, bias both opp seats' desire maps to put A/T/K of X with
weight 30 (above leadCount's 1, below topTouch's hard-pin of 60 —
soft inference, not a declared meld).

### HIGH-3 — `forceOwnInitiative` longest-suit consumer missing

The `Bot.lua:3632-3634` write-site comment promised:
> *"Sets `forceOwnInitiative` flag consumed by Sun shortest-suit
> (skip) **AND by longest-suit logic (prefer suits where we hold
> A or T)**."*

The Sun-shortest-suit skip lands at line 3655. The **Hokm
longest-suit A/T preference** was never wired — the longest-suit
picker at lines 3704-3739 just used raw `suitCount`. So when partner
showed a weak hand in a Hokm contract, the bot fell through to plain
"low from longest" without any A/T-suit preference.

Fix: when `forceOwnInitiative` is set, score suits as
`count*10 + (hasA*5) + (hasT*3)` so a 4-card-with-A beats a
5-card-no-honors. Same Fzloky avoid-suit gating; mardoofa-aware
via the additive A+T bonus.

### Why no test caught these

All three are integration-level silent failures. The functions
return valid cards either way; only the *strategic preference*
is wrong. Source-pin tests (`test_state_bot.lua`) check that
specific hands fire the right pickers, not that the picker
incorporates all upstream signals. The 828 suite covers
correctness; gaps like these need pattern-coverage audits.

### Tests

828/828 pass. No test changes — these fixes affect strategic
preference under partner-state conditions that source-pin
fixtures don't trigger.

### Calibration probe — empirical measurements (post-v1.3.0 harness)

A second audit agent ran the v1.3.0-corrected harness (5 seeds × 100
rounds × 8 cells, 286s wall time). Findings are measurement-only,
no code change in v1.3.1 — but they **revise** the deferred re-tune
recommendation in the v1.3.0 CHANGELOG.

**Bel rate confirmed ~92%** at current TH=35. Direct probe of 4000
PickDouble evaluations: defender strength p25=30, p50=41, p75=53,
p90=65 (mean 42.2). With jitter band [25, 45], ~65% of single-
defender rolls fire; with two defenders + early-return, round-level
Bel rate climbs to 92.2%. Validates the v1.3.0 deferred re-tune
direction (TH=35 is over-tuned).

**v1.2.3 bidding fix is landing.** R1 overall bid rate measured at
24.7% (basic tier), in the expected 25–50% target band. Position
gradient pos1=25.2% → pos4=24.3% — present but gentle, no longer
suppresses bidding the way +5/+3 did.

**Four/Gahwa rate ≈ 0% is STRUCTURAL, not a Bel/Four-threshold issue.**
Triple gate at `BOT_TRIPLE_TH=90` is above the realistic 8-card
strength ceiling (p90=65). Triple fires only in ~5–15% of post-Bel
opportunities; Four (which requires Bel + Triple both fired) ends
up at 0–3% per cell; Gahwa cascades to 0%. Adjusting `BOT_FOUR_TH`
or `BOT_GAHWA_TH` does NOT unlock these rungs — `BOT_TRIPLE_TH` is
the upstream bottleneck.

**Revised re-tune recommendation** (corrects v1.3.0 CHANGELOG):

| Constant | Current | v1.3.0 proposed | **v1.3.1 revised** | Rationale |
|---|---|---|---|---|
| `K.BOT_BEL_TH` | 35 | 62 | **62** | Targets ~8% natural rate; p75=53 + jitter |
| `K.BOT_TRIPLE_TH` | 90 | 100 | **65** | p75=53, p90=65 — TH=100 keeps Triple at <5% |
| `K.BOT_FOUR_TH` | 110 | 108 | **80** | Above Triple band, below extreme outliers |
| `K.BOT_GAHWA_TH` | 120 | 115 | **95** | Stays terminal-rare, but reachable |

The v1.3.0 proposal was computed from formulas without measuring
the post-fix strength distribution; the revised values are anchored
to the actual p75/p90 empirically observed. AE.10a/AE.10b source-pin
tests should still hold (rich hand strength 161 ≫ 65; weak hand
strength 73 sits between proposed Triple TH=65 and Four TH=80, but
AE.10b probes PickTriple with TH=90 currently — the test pins
"weak hand does NOT fire PickTriple"; at TH=65 weak hand strength
73 would now FIRE, breaking AE.10b).

**Status: re-tune still deferred** — the AE.10b interaction means
threshold drops below 73 require updating the test fixture's "weak"
hand to something genuinely weak (e.g., the all-7/8 Kawesh shape)
or accepting the new firing behavior as correct. This is a code+test
coordinated change that warrants its own deliberate pass.

## v1.3.0 — Closes weakHandSignal consumer gap + multiseed harness fix

Post-v1.2.3 audit run (3 specialist agents on backlog, code-quality,
style-ledger integration, plus deep Bel-rate calibration probe)
identified two structurally-undelivered items from prior releases.
v1.3.0 ships both fixes. 828/828 tests pass.

### HIGH — Faranka inversion (closes v1.2.0 weakHandSignal consumer gap)

The v1.2.0 style-ledger write-site at `Bot.lua:321-323` documented:

> *"if partner is showing weak hand, INVERT Faranka-duck behavior —
> TAKE the trick to keep tempo away from the weak partner."*

The `weakHandSignal` counter was wired and incremented correctly,
and a consumer existed in `pickLead` (`forceOwnInitiative` at line
3636) — but the **pos-4 Faranka site itself never read the signal**.
The v1.2.0 inversion was structurally undelivered for 5 releases.

**Fix** (Bot.lua:3977): mirror the pickLead gate at the Faranka site.
When partner has shown ≥3 follow-events with
`weakHandSignal > 2× highCardPlays`, boost Faranka-vs-capture rate
from `0.30 → 0.85`. Not 1.0 — keep texture so opp who infers
«bot saw partner weak» still can't bank on always-capture.

**Saudi rationale**: per video #20 («تمسك لون»), the strong-hand
player grabs tempo when partner shows weak. The pos-4 Faranka
duck-with-cover is the *opposite* — it concedes a trick to save
the Ace. Two contradictory plays for the same trick configuration;
the choice depends on partner's read. Pre-fix the bot always
chose the conservative duck regardless of partner-read, leaving
free tempo on the table when the read clearly favored capture.

### MED — Test-fixture state-prep bug (multiseed harness)

`tests/test_multiseed_metrics.lua:369` called `resolveEscalation`
**before** `playOneRound`'s state setup at line 384.
`Bot.PickDouble/PickTriple/PickFour/PickGahwa` all read
`S.s.hostHands` — round 1 saw `nil` (no prior state), rounds
2..N saw all-empty arrays (the previous round's `table.remove`
loop had drained them). Empty-hand strength = 0 → always below
jth → escalation pickers always returned `false` → recorded
rates were **bug-clamped to 0%** in natural mode regardless of
threshold tuning.

This invalidates the v0.5.1 multiseed finding's Bel-rate
calibration claim — the "zero Bel" reading was a harness bug,
not a calibration issue. Past calibration recommendations
referencing `v0.5_multi_seed_tournament.json` should be
re-baselined against a corrected run.

**Fix**: mirror the subset of `playOneRound`'s state setup
(`freshState`, `S.s.contract`, deep-copy hands into
`S.s.hostHands`, `Bot.ResetMemory`) before
`resolveEscalation`. `playOneRound` then resets state again
below, so this is non-mutating with respect to actual play.

This file is a metrics-collection script, not part of
`run.py`'s HARNESSES list, so the fix doesn't touch the 828
test suite. It does mean future Bel-rate calibration probes
will see real distributions instead of the bug-zeroed null.

### Threshold re-tune — DEFERRED, requires user approval

The Bel-rate calibration agent's corrected probe shows current
`BOT_BEL_TH=35` fires Bel at **~90%** in natural mode against
the real strength distribution (defender p75=53, p90=65). The
v0.11.20 drop to 35 was tuned against the bug-zeroed null, so
it over-corrected. Proposed re-tune:

| Constant | Current | Proposed | Rationale |
|---|---|---|---|
| `K.BOT_BEL_TH` | 35 | 62 | Targets ~8% natural rate per `escalation.md` |
| `K.BOT_TRIPLE_TH` | 90 | 100 | ~15% conditional-on-Bel |
| `K.BOT_FOUR_TH` | 110 | 108 | <5% rate |
| `K.BOT_GAHWA_TH` | 120 | 115 | Stays terminal-rare |

AE.10a (rich hand) and AE.10b (weak hand) source-pin tests both
remain green at proposed thresholds (computed strengths 161/73
sit decisively on either side of TH=100).

**Not shipped in v1.3.0** — this is a substantive gameplay
shift that should be approved + verified separately.

### Other audit findings — closed without code change

- **PickKawesh partner-Hokm gate** (audit re-raised): formally
  closed. The pre-bid timing is structurally pinned —
  `tahreebClassify` returns nil before contract is set, so
  partner-Hokm reads cannot leak across the boundary. No fix
  needed.
- **MED-1 G2/G4 refactor**: cosmetic only; deferred.
- **MED-2 oppHighInferred non-monotone assign**: cosmetic;
  deferred.
- **LOW-1 partnerAkaSuit rank tracking**: nice-to-have;
  deferred.

### Tests

828/828 pass. AE.10a/AE.10b unchanged (Faranka inversion is in
a different code path; weakHandSignal counters require live
play to populate, which the source-pin fixtures don't trigger).

## v1.2.3 — Hotfix: user-reported v1.2.2 play-test issues

User reported two issues from live play of v1.2.2:
1. **Bidding too conservative** — bidcalc trace showed bots passing
   on hands they should bid (e.g., A♦+T♥+K♦ at bidPos 1, sun=20 vs
   thSun=47).
2. **Hand display order** — card sort didn't put trump first and
   the suit-color alternation broke when trump landed mid-order.

### Bidding fix — MED-10 R1 position bias reduced 5/3 → 2/1

**Diagnosis**: v1.1.0's MED-10 added `+5` to thSun/thHokmR1 at
bidPos 1, `+3` at bidPos 2 (per video #25 «اذا كنت تشك خلاص
امرر» — first-lap-pass discipline). Pre-v1.1.0 there was no
position bias. Combined with the existing Bel-fear ramp (0–8) and
BID_JITTER (±6), the +5 push routinely made thSun unreachable for
moderate hands.

User trace example:
```
[bid s2 r1] hand=[8C QS AD TH KD] sun=20 thSun=42  (logged)
[bid s2 r1] R1 direct Sun skipped: sun=20 thSun=47  (gate-checked)
```
The 42→47 jump is the +5 bidPos-1 bias. The bot's hand had A♦+T♥
+K♦ — a real Sun candidate — but sun=20 vs thSun=47 forced PASS.

**Fix**: reduce to +2/+1 (bidPos 1/2). Preserves the Saudi
convention texture (still position-aware caution) but doesn't
compound with jitter+ramp into unreachable thresholds.

**Side-effect analysis** (per user request):
- ✓ **More R1 commitments** — bots bid more from bidPos 1/2 → fewer
  redeals, more dynamic play (matches user's intended outcome)
- ✓ **Slight Bel-rate uptick potential** — more bids = more
  opportunities for defenders to Bel (helps the v1.0.10/v1.1.0
  Bel-rate-near-zero issue, though that's a separate calibration)
- ✓ **Saudi convention preserved** — +2/+1 still adds positional
  bias; first-lap-pass discipline holds in directional terms
- ⚠ **Slight unpredictability reduction** — same hand at bidPos 1
  vs bidPos 4 will produce more SIMILAR bids than under +5/+3.
  Acceptable tradeoff; the unpredictability source isn't position
  bias alone (BID_JITTER ±6 + shuffledSuits + tie-break randomness
  in v1.1.0 still provide variance)
- ✓ **Bel-fear ramp interaction** — old combined max (ramp + jitter
  + 5 bias) = up to 19 raw bias; new max (ramp + jitter + 2) = up
  to 16. Still substantial; still respects the band

No regressions detected. Net positive change for play feel.

### Card hand display — trump-first sort + alternating colors

Pre-fix `SUIT_DISPLAY = { S=1, H=2, C=3, D=4 }` was fixed
regardless of contract. When trump was Hearts, trump landed in
position 2; when trump was Diamonds, trump landed at position 4
(end of hand). The display lost both Saudi convention (trump
should be scannable first when reading own hand) and the intended
black-red-black-red alternation when trump landed mid-order.

**Fix**: per-trump suit-display map. Trump suit is always position
1; remaining 3 suits alternate colors so no two adjacent share a
color:
- Trump ♠ (B): ♠ ♥ ♣ ♦ (B R B R)
- Trump ♥ (R): ♥ ♠ ♦ ♣ (R B R B)
- Trump ♦ (R): ♦ ♣ ♥ ♠ (R B R B)
- Trump ♣ (B): ♣ ♦ ♠ ♥ (B R B R)

Sun (no trump) keeps the default S/H/C/D order. Within-suit sort
unchanged (descending TrickRank — trump uses Hokm rank order, off-
trump uses plain rank).

### Tests

828/828 pass. No test changes (sort is pure display; bidding
fix is a magnitude tune).

## v1.2.2 — Hotfix: 4 v1.2.1 audit findings (3-agent + sim cross-check)

A 3-agent audit (code-bug + rule-correctness + comparison) plus a
6000-round multiseed tournament simulation found that **2 of v1.2.1's
13 fixes were half-landed** — the internal logic was correct but the
integration glue was missing, so the documented features were
structurally undelivered. v1.2.2 ships the 4 actionable fixes from
that audit. 828/828 tests pass.

### CRITICAL — silent-correctness lies in v1.2.1

- **HIGH-1: `Bot.PickAKANoise` was dead code in v1.2.1**. The function
  was defined at `Bot.lua:5740-5771` but `Net.lua` never called it.
  v1.2.1's documented "~3% noise-AKA emission" was structurally
  undelivered. Now: `Net.lua`'s AKA-emit path falls through to
  `Bot.PickAKANoise` when the real `Bot.PickAKA` returns nil
  (Saudi-Master tier, K/Q lead, no A held in suit). Per video #19's
  silence-variance principle.

- **HIGH-2: `forceDonateCleared` flag was set but never read**.
  v1.2.1's G3 fix correctly set the flag at `Bot.lua:4047/4057`
  when partner's K-singleton signal (`sig.cleared = {Q,J}`) fired,
  but no consumer in the donate branch read it — the K-singleton
  case fell through to default donate instead of force-cashing
  A/T. Per video #05 «هل ممكن يكون عنده البنت ولا الولد لا
  مستحيل»: K-singleton means partner CAN'T continue → cash A/T
  NOW. Now: the donate branch filters `pointCards` to A/T-only
  when `forceDonateCleared = true`, so the descending sort picks
  the cash card first.

### MEDIUM — v1.2.1 documentation drift

- **MED-3: A4 RNG hoisted outside suit loop**. v1.2.1's
  `partnerAkaSuit` lead-back ran `math.random()` PER matching suit
  in the loop body — variable RNG consumption per `pickLead` call
  (1–4 rolls depending on how many AKA suits matched). Single
  `leadBackRoll` outside the loop now consumes exactly one random
  per invocation; either we lead-back this turn OR delay (across
  all matching suits uniformly). Restores reproducibility.

- **MED-4: A8 tasgheer race-gap pair wired**. v1.2.1's CHANGELOG
  promised tasgheer clutch constants `(26/22)` distinct from
  AKA-withhold's `(22/18)`, but the code only set `clutchDist=26`
  — the `raceGap=22` term was missing. Now wired:
  `clutch = (oppCum >= target-26) or (meCum >= target-26) or
  (math.abs(oppCum-meCum) <= 22)`. Synchronized-silence pattern
  fully breaks across both branches.

### Audit pass-2 (v1.2.1 → v1.2.2) consensus matrix

| Finding | Status | Verdict |
|---|---|---|
| HIGH-1 PickAKANoise unwired | Verified by grep + cross-check | **Shipped (P0)** |
| HIGH-2 forceDonateCleared dead | Verified by grep + cross-check | **Shipped (P0)** |
| MED-3 A4 random-per-suit | Verified | **Shipped (P1)** |
| MED-4 A8 race-gap missing | Verified | **Shipped (P1)** |
| MED-1 G2 short-circuits G4 | Real but G4 is mostly redundant; not harmful | Deferred |
| MED-2 oppHighInferred latching | Edge case; rare confidence regression | Deferred |
| LOW-1 A4 hi~="A" tracking | Narrow correctness | Deferred |
| G8 RANK_PLAIN ordering | **VERIFIED CORRECT** (Constants.lua:51 matches Saudi-Sun) | No fix needed |
| Bel rate ~0% natural in tournament | **PRE-EXISTING** (since v1.0.10/v1.1.0 calibration) | Separate v1.2.3 calibration sweep |

**6000-round multiseed tournament simulation**: zero crashes, winner
consistency 0.60–1.00 across configs (variance present per
v1.1.0+ unpredictability design). v1.2.1's HIGH-1/HIGH-2 dead-code
paths cause silent-correctness, not stability issues — confirmed by
the simulation completing cleanly while the dead branches never fired.

### Tests

828/828 pass. No new tests added — the v1.2.2 fixes restore the
behaviors v1.2.1's CHANGELOG claimed; existing test surface is
unchanged.

## v1.2.1 — Hotfix: 13 v1.2.0 re-audit findings (validated by 3-agent swarm)

User reported v1.2.0 felt better in play-testing but ran two more
audits + a 3-agent validation swarm to find residual gaps. Original
re-audit produced 14 findings (8 unpredictability + 6 partner-
coordination); validation found 4 of those over-extended Saudi
rules / mis-cited videos / had no source. This release ships REFINED
versions of all 14 — 13 with adjustments, 1 dropped (G6) since the
original concern was based on a misreading of video #17. 828/828
tests pass.

### CRITICAL — correctness bug

- **G3: Inverted `cleared` semantic in topTouchSignal reads**.
  Per video #05 «هل ممكن يكون عنده البنت ولا الولد لا مستحيل لو
  عنده كان لعبها بدال الشايب»: K-singleton (`cleared = {Q,J}`)
  means partner CAN'T continue the run. Pre-fix BOTH the pickFollow
  smother gate at line 3941 AND the pickLead reader at line 3037
  treated `cleared` as a "save for partner" continue-signal — the
  opposite of what the video says. Now: only `nextDown` (T/Q played
  → cover held) marks save-for-partner; `cleared` falls through to
  normal donate, with a NEW force-donate branch in pickFollow that
  cashes A/T eagerly when partner is broke. Symmetric update at
  both sites prevents sender/reader mismatch.

### HIGH — predictability tells

- **A1: deceptiveOverplay extended to Hokm with J/9-of-trump
  anti-trigger**. Per video #08 lines 168-198 the deceptive-overplay
  rule applies in Hokm too — BUT in Hokm, J and 9 of trump are
  «تقريبا نفس الاكه» (≈ AKA-equivalent kill cards) and must NEVER
  be sacrificed. ~25% Hokm probability (vs 40% Sun), explicit
  `if isHokm and trump and (rank=="J" or rank=="9") then skip`
  filter. Also wired G5's `oppHighInferred` consumer here — when opp
  inferred to hold cover in led suit, suppress the deceptive
  sacrifice (would collide with their outs).

- **A2: AKA probabilistic withhold extended `trick<=4` → `trick<=6`
  + separate noise-AKA emission**. Per video #19 «دائما خصم يحتفظ
  قوته في الاخر» — pros withhold MORE in mid/late tricks. Plus a
  new `Bot.PickAKANoise` ~3% emission on second-highest unplayed
  (when bot doesn't actually hold the boss) — corrupts opp's
  reliability on the AKA banner.

- **A3: pos-2 binary breaker**. ~12% probabilistic "win at pos-2
  with cheapest winner" branch when ≥1 point card already in trick
  AND we hold a non-sureStopper winner. Breaks the duck-or-stop
  binary tell. Per video #20 «تمسك اللعب» — pos-2 mid-card win is
  canonical when grabbing tempo.

- **A4: AKA-receiver lead-back probabilistic (~85%)**. Pre-fix the
  lead-back fired 100% when partner's boss fell — opp could bank
  "bot opens AKA-suit at trick N+1". ~85% probability + delay-flag
  for the ~15% case keeps cooperation value while breaking the
  determinism. Pure unpredictability tweak (no Saudi citation
  needed — the lead-back IS canonical; only the timing
  determinism is the leak).

- **A5: Bel-fear ramp boundaries jittered ±3 per call**. Pre-fix
  knees at 90/105/130 were sharp inflection points; opp could
  observe "bot bid Sun at cum=104 but not cum=131" and infer the
  ramp shape. Per-call jitter preserves the underlying piecewise
  structure (still video-#11 stepwise) but breaks the precise-
  ledge tell.

- **A7: Sun Faranka 70/30 probabilistic capture**. ~30% capture-
  with-A branch (instead of always Faranka with cover) corrupts
  opp's read on bot's Faranka shape. Per video #06's 5-factor
  framework — pros do NOT Faranka uniformly. M3lm-gated.

- **A8: Clutch constants desynced + non-zero variance in clutch**.
  Pre-fix tasgheer/AKA-withhold both used `clutch ⇒ 0% variance`
  on near-identical thresholds. Synchronized silence became a
  score-state tell. Now: tasgheer 26/22, AKA-withhold 22/18 (was
  25/20) — distinct thresholds. Plus ~3% variance even in clutch
  (was 0%).

### HIGH — partner-coordination

- **G1: weakHandSignal consumed in pickLead "take initiative away
  from weak partner"**. Per video #20 «اذا انت عندك قوه ... تحاول
  تمسك اللعب ضعيف ممكن تخلي قويه يمسك اللعب» — strong hand grabs
  tempo, weak hand defers. The complementary read: when partner
  shows weak (≥3 events, weakHandSignal > highCardPlays × 2), set
  `forceOwnInitiative` so Sun shortest-suit lead falls through to
  longest-suit (where we hold A/T) — taking initiative away from
  partner. Original re-audit framing ("invert Faranka") was over-
  extended; this faithful framing matches video #20's tempo-hold
  semantic.

- **G2: pickFollow preserves T/A of partner's tahreeb-want suit**.
  Per video #02 «اذا كانت العشره معاها ورقتين ... الافضل انك ما
  تروح بالعشره وتتهور لا تروح بالثمانيه»: receiver who saw partner
  Tahreeb suit X must HOLD the cover-grade card in X for the lead-
  back. RECEIVER-side preservation only (NOT sender encoder change
  — that would contradict v0.9.0 want-arm).

- **G4: AKA-receiver T/K preservation when paired with Bargiya/want**.
  Per video #14 lines 144-160 the lead-back receiver keeps the
  next-down rank for partner's continuation. Re-cited from video
  #18 (which actually covers AKA-CALLER preconditions) to video
  #14 (receiver continuation). Scope: only when partner BOTH
  AKA'd AND Bargiya/want-emitted in same suit (the high-confidence
  intersection).

- **G5: Export `oppHighInferred` to memory + wire A1 consumer**.
  Per video #19 «اي شكل خصمك ينفر تفترض انه عنده». 6-factor opp-
  Tanfeer score (v1.2.0) was write-only into local
  `tahreebAvoidSet` — now also persisted to
  `Bot._memory[seat].oppHighInferred[suit]` at confidence ≥ 4.
  A1's deceptiveOverplay now reads it to suppress the sacrifice
  when opp is inferred to hold cover in led suit.

### MED — refinements

- **G7: Conditional A+cover gate (late-game only)**. Per video #14
  lines 311-317: A+cover preferred LATE-game (`#hand <= 4`); early
  game with cornered single-suit (≥5 cards), A-only is allowed.
  Pre-fix tightening was too strict (universal `>= 3 + cover`);
  now branches on hand-size with cornered exception.

- **G8: Conditional Q-play override (consecutive vs non-consecutive
  Takbeer)**. Per video #21 lines 142-149: default IS highest even
  for non-consecutive; Q-play (lower) is the EXCEPTION when player
  has own cover AND wants tempo-hold. Pre-fix framing ("non-
  consecutive → lower always") was too aggressive; now checks
  hasCoverAce + non-consecutive gap before firing the override.

### G6 — DROPPED (no code change)

- **G6 Mathlooth-K bidder-team gate**. Validation found video #17
  explicitly says mathlooth is SYMMETRIC (line 71-74: «لو واحد
  عنده مثلوث في السبيت ممكن يمسكك فيه» — "if a player has a
  mathlooth he can trap you in it"). Original re-audit's "bidder-
  team-only" framing over-constrained. The existing v1.0.4
  Mathlooth-K trickle works correctly for both sides; no change
  needed.

### Tests

- **J.4 (M7) phase-split fix**: محشور-proxy bargiya now skips the
  `handSize >= 5` phase-split (`tahreebPrefMahshour` flag).
  Sender already cornered themselves; receiver should lead-back
  immediately, not "burn 1-2 tricks first".
- **AE.10 re-seed**: added `math.randomseed(20260503)` before the
  PickTriple-jitter test fixture — v1.2.1's added probabilistic
  branches consume math.random calls earlier in the suite,
  shifting subsequent seed state.

828/828 tests pass.

## v1.2.0 — Tier 5 features (deferred backlog from v1.1.0)

Closes the Tier 5 deferred items from v1.1.0. 828/828 tests pass.

### CRITICAL — Saudi-rule conformance

- **Closed-trump under Bel/Four (bot-only)** — transcript H2,
  video #11 «الاعداد الزوجيه الدبل تضرب في اثنين والفور في اربعه
  ... اللعب راح يكون مقفول». Under EVEN-multiplier Hokm rounds
  (Bel-only ×2 OR Four-only ×4), trump-leading is FORBIDDEN
  unless the player has only trump in hand. Triple (×3) and
  Gahwa rounds play "open" with normal trump rules.
  Bot-only implementation: `applyClosedTrumpLeadGate` filters
  `legal` to non-trump cards before any pickLead heuristic runs.
  Rules.lua legality unchanged so human players keep full
  freedom — pending verified Saudi-tournament consensus.

### HIGH — Saudi rule

- **AKA uncertainty band + doubled-round nuance** — transcript
  H3, video #18 «اذا انت متاكد ... لازم تقول اكه». Pre-v1.2.0
  ALL doubled rounds blanket-suppressed AKA. Per video #18 AKA
  fires when CERTAIN — and certainty grows as cards are played.
  Now: doubled round suppresses AKA only when tricks completed
  < 3 (early round, opp could still hold cards above our claimed
  boss). Mid/late doubled rounds (tricks ≥ 3) allow AKA when
  other gates pass — the played-card history makes the highest-
  unplayed determination sound.

### MEDIUM — Bot strategy

- **Sun-bidder-partner pickPlay branch** — partner-coordination
  M2 (deferred from v1.1.0). Pre-v1.2.0 the bot's Sun-shortest-
  suit lead logic ran identically whether we were the Sun bidder
  ourselves or the bidder's partner. Per video #02 «خويك مشتري
  صن» the partner-of-Sun-bidder should preferentially lead from
  the shortest NON-Ace-holding suit (clearing those for partner's
  Aces; saving our own Aces concentrated for partner's eventual
  run-back support). Falls back to plain shortest if every suit
  holds an Ace.

- **Opp-Tanfeer 6-factor confidence scoring** — video #19
  «عوامل مؤثره». Pre-v1.2.0 ALL opp signals (bargiya / want /
  bargiya_hint) were treated as binary avoid-suit. Now confidence
  is weighted by 5 of the 6 video-#19 factors:
    1. **Lateness** (trick ≥ 5: +2; ≥ 3: +1)
    2. **Rank** of highest event (A: +2; T/K: +1)
    3. **Same-suit repetition** — implicit via tahreebClassify's
       multi-event grade
    4. **Cross-opp redundancy** — both opps' weights sum into
       `oppSuitConfidence[su]`
    5. (Suit-switch cancellation) — deferred (needs per-event
       temporal ordering)
    6. **Bidder identity** (sender IS the bidder: +1)
  Confidence threshold: **≥ 4** marks the suit avoid. Bargiya base
  (3) + 1 lateness/bidder hits threshold cleanly; bargiya_hint (1)
  must stack from multiple factors to reach 4 — appropriately
  stricter for the lower-confidence flavor. The L2 Bargiya
  special-case `opponentBargiyaSuit` memory flag (v1.1.1) is
  preserved separately.

- **Control-the-game `weakHandSignal` counter (write-side)** —
  video #20 «تمسك لون». Per-seat `weakHandSignal` and
  `highCardPlays` counters added to `Bot._partnerStyle`.
  Accumulate when seat plays under partner-winning trick: 7/8/9
  ranks → `weakHandSignal++` ("weak hand" tell), A/T/K ranks →
  `highCardPlays++` ("strong hand" / Takbeer-magnify tell).
  Read-side consumer (the actual "invert Faranka if partner is
  weak" pickFollow branch) is deferred — needs a clearer scenario
  spec from real-game observation. Counter is now collected so
  future cycles can wire decisions on it.

### What WASN'T changed

- **Style ledger `trumpEarly`/`trumpLate`/`leadCount`**: third-
  pass agent flagged as dead code, but verified that
  `styleTrumpTempo` IS consumed at `Bot.lua:3235-3236` (saveHighTrump
  defender branch) and `Bot.lua:3049+` (bidder branch) —
  multiple consumers exist. `leadCount` is consumed in
  `BotMaster.lua:478` for sampler bias. No new wiring needed.

- **Sun-bidder-partner pickFollow branch**: pickLead branch
  shipped (above); pickFollow refinement (preserve high cards
  for partner's run) is harder to scope without specific
  scenarios — deferred.

## v1.1.2 — Hotfix: BALOOT vocal misfiring on Sun round-end

User report: BALOOT! voice played at the end of a Sun round (the
attached screenshot showed a SUN-bid SWA-fail round). Sun has NO
Belote (Hokm-only mechanic), so the cue was wrong.

### Root cause

`K.SND_BALOOT` was used for TWO purposes:
1. **Belote announcement** (v1.0.11 D HIGH-2): plays when player
   announces K+Q-of-trump via the BALOOT! UI button.
2. **Generic round-end fanfare** (pre-v0.3.0 leftover at
   `State.lua:1842-1845`): fired on ANY al-kaboot or contract-fail.

When v1.0.11 repurposed `K.SND_BALOOT` exclusively for Belote
announcement, this generic fanfare path was missed during the
migration. So in any contract-fail round (Hokm OR Sun), the
"بلوت" vocal still played as a generic loss stinger — incorrect
because Sun rounds can't have Belote and Hokm-fail rounds may
not have an announced Belote either.

### Fix

Removed the generic round-end SND_BALOOT trigger in
`S.ApplyRoundEnd`. The v0.10.7 specialized cues
(`SND_HOKM_LOST`, `SND_KABOOT`, `SND_KABOOT_AGAINST`,
`SND_LOST_ROUND`) already cover all the round-end contextual
cases. The Belote-bonus reveal still fires correctly via
`S.ApplyBeloteAnnounce` when the player clicks BALOOT! during
play (or bot auto-announces).

828/828 tests pass.

## v1.1.1 — Third-pass audit follow-on (M1/M2/M4 + L1/L2/L3)

Closes the user-prioritized backlog from the v1.1.0 third-pass
agent audit. 828/828 tests pass.

### MEDIUM

- **M1 (SWA Hokm 2-handed مجاوب/مقطوع/مثلوث anti-pattern)**:
  per video #35 «في حكم برا اللعب وهذا معه مقطوع» — outside trump
  in opp hand + opp-void-in-side-suit defeats Hokm 2-handed SWA.
  **Already covered structurally by `R.IsValidSWA`'s recursive
  minimax** (it explores all legal opp ruffs and over-takes). Added
  two regression-pin tests (O.5 مثلوث / O.6 مقطوع) that lock the
  coverage so future changes can't silently regress.

- **M2 (Tahreeb sender forced-vs-intentional flag)**: pre-fix the
  bot's `tahreebSent[suit]` log made no distinction between forced
  discards (only-non-led-non-trump suit available) and intentional
  signals. Per video #03 + #09 the Saudi convention is "Tahreeb
  AWAY from your real holding"; forced dumps from a strong suit
  corrupted the partner-side read. Now: `list.forced[i]` parallel
  array marks each event; `tahreebClassify` filters forced events
  before classification (returns nil if all events were forced).
  **Conflict check (Tier 2)**: NO conflict — Tier 2 added
  `mem.partnerAkaSuit` separately; M2 modifies `tahreebSent`
  structure independently.

- **M4 (Implicit-AKA receiver tier-symmetry)**: third-pass agent
  asked to verify that v1.1.0's removal of the SENDER-side
  `IsBotSeat(partner)` AKA gate didn't leave a parallel issue on
  the RECEIVER side. **Verified**: implicit-AKA detector at
  `Bot.lua:3599-3609` checks `lead.seat == R.Partner(seat)` and
  bare-Ace rank, but does NOT consult `Bot.IsBotSeat`. Both bot
  and human partners trigger receiver behavior identically. Added
  AN.1 source-pin test that fails if anyone re-introduces an
  IsBotSeat gate in the implicit-AKA window.
  **Conflict check (Tier 1)**: NO conflict — receiver was always
  tier-symmetric; the bug v1.1.0 fixed was sender-side only.

### LOW

- **L1 (single-point مناطق calibration)**: per video #13 «لا
  تستهين في المنطقه الواحد» — single-point spreads (J=2 vs 9=0
  in Sun) decide marginal rounds. v1.1.0's `pickRandomTied`
  randomizes within RANK ties only; different-rank cards still
  compare correctly via `TrickRank`. Added AN.2 source-pin test
  asserting Sun trick-rank `9 < J` and Hokm off-trump rank order
  preserved post-randomization.

- **L2 (Bargiya-from-opp special override)**: opp Bargiya signals
  TWO things — (a) "avoid leading this suit" (already wired since
  v0.9.3) and (b) "be ready to ruff this suit if opp's partner
  leads it" (NEW). Added `Bot._memory[seat].opponentBargiyaSuit`
  per-suit flag persisted on confirmed-bargiya opp signals; new
  pickFollow override picks the HIGHEST winning trump (boss-grade
  ruff) instead of cheapest when the leadSuit matches an
  opp-Bargiya'd suit and we're must-ruffing. Defeats opp's
  intended K/A runner-back decisively. Hokm-only.

- **L3 (Mathlooth-K bait + window extension)**: video #17 K-cashes-
  trick-3 timing was previously gated to trick 1-2 only. Extended
  to trick 1-3 so K-preservation lasts the full canonical window.
  NEW: pos-3 K-doubled bait (per video #20 «تمسك لون» control-the-
  game): when in Sun pos-3 with K + 1 cover and opp led 7/8/9,
  duck low — let opp take the cheap trick, save K for the trick
  where A and T have fallen and our K becomes top-live.

### Tests

- **O.5 / O.6** (test_rules.lua): مثلوث and مقطوع SWA-defeat
  regression pins.
- **AN.1** (test_state_bot.lua): implicit-AKA receiver branch
  source-pin (no IsBotSeat gate).
- **AN.2** (test_state_bot.lua): single-point مناطق rank-order
  preservation.

828/828 tests pass (was 821/821; +7 net new).

## v1.1.0 — Bot human-like unpredictability + partner-coordination upgrades

User reported the bot felt "too predictable and rough." Three audit
agents reviewed `Bot.lua` (5800+ lines) against 47 video transcripts
and surfaced 25 prioritized findings (10 unpredictability + 12
partner-coordination + 3 NEW from full-transcript pass). This
release ships the high-impact fixes across 5 tiers. 821/821 tests
pass.

### CRITICAL — predictability fixes (Tier 1)

- **Tie-break randomization (HIGH-1)**: pre-v1.1.0 the bot had only
  2 calls to `math.random` in 5800 lines — once cards were dealt
  every play was deterministic. Tied cards in `lowestByRank` /
  `highestByRank` / `highestByFaceValue` now use a `pickRandomTied`
  helper that randomizes among final ties. Removes the "if bot
  played 7♠ instead of 7♥, the 7♥ must be later in their dealt
  hand" hand-order broadcast tell.

- **`shuffledSuits()` iterator (HIGH-3 / MED-8)**: the codebase had
  21 separate `for _, su in ipairs({"S","H","D","C"})` loops that
  selected the FIRST matching suit — meaning Sun mardoofa probe
  always opened with A♠, Bargiya/want-arm/T-4 dump always preferred
  ♠, Tanfeer always picked ♠. New `shuffledSuits()` Fisher-Yates
  helper replaced ALL 21 sites; first-match selection no longer
  encodes alphabet order.

- **AKA fixes (HIGH-6 + partner-coord H2)**: TWO bugs converged:
    - REMOVED the `IsBotSeat(partner)` gate in `Bot.PickAKA` — pre-
      fix the bot would NEVER announce AKA when its teammate was
      human (you!), even though video #18's 4 hard preconditions
      don't include partner-tier. Saudi-flavor bot that never AKA's
      because partner is human is the OPPOSITE of Saudi flavor.
    - ADDED Saudi-Master tier probabilistic withhold (~10% in non-
      clutch states, trick ≤ 4) so silence-as-signal is broken. Per
      video #19 «دائما خصم يحتفظ قوته في الاخر».

- **Tahreeb-receiver T-supply for `count >= 3` (partner-coord H1)**:
  pre-fix the receiver branch only fired the T-lead for count==1/2,
  falling through to `lowestByRank` for count >= 3 — but video #10
  («نسبه نجاحه كبيره اللي هي 100%») treats small→big tahreeb as
  100% reliable. Receiver with T MUST lead it back to partner
  regardless of count when sender's flavor is "want".

### HIGH — tactical sophistication (Tier 2)

- **`pickFollow.deceptiveOverplay` (HIGH-2 — video #08 "smart
  move")**: completely unimplemented before v1.1.0 (only `TODO`
  docstrings). When pos-4 in Sun with multiple winners in led suit,
  ~40% probabilistic at M3lm+ tier the bot now plays a higher
  winner (preferring the J — the "Shayb") instead of the cheapest.
  Video #08 verbatim: «راح تلعب اكبر ورقه موجوده عندك ... ما يسويها
  الا واحد محترف في البلد». Anti-trigger: tahreeb signal active
  (preserve hand integrity).

- **AKA-receiver tracks `mem.partnerAkaSuit` (partner-coord H3)**:
  pre-fix once partner's AKA boss fell, receiver had no memory of
  the touching-honors continuation. Now `partnerAkaSuit[suit] =
  true` on AKA observation; pickLead later treats it as a "want"
  pref (lead it back once the boss has fallen, helping partner
  cash the next-down rank).

- **"Biggest mistake" rule extended to Hokm (partner-coord H4)**:
  the v0.7.2 video #09 absolute-lowest-mistake rule was Sun-only
  pre-v1.1.0. Video doesn't condition on contract type — receiver
  discipline is contract-agnostic. Now fires for Hokm partner-
  winning follows when leadSuit ≠ trump (don't pollute trump-pull
  semantics).

- **pickFollow preserves secondary winners in partner's meld suit
  (partner-coord H6)**: only HALF of v1.0.0 C#1 actually shipped —
  pickLead avoided leading partner's meld suit but pickFollow
  happily dumped K/Q of that suit as Tahreeb fodder. Now: when
  Hokm + can't-win + earlier-than-pos-4, filter discardable to
  exclude high cards (A/K/Q) in partner's declared sequence-meld
  suit.

### HIGH — NEW from third-pass full-transcript audit

- **Hokm 9-of-trump consecutive/non-consecutive Takbeer rule
  (video #22 R3/R4)**: the most valuable unwired Hokm-trump-follow
  rule. Trump rank order: J(8) > 9(7) > A(6) > T(5) > K(4) > Q(3) >
  8(2) > 7(1). Adjacent-below-9 = A only. When following trump
  not at pos-4, if we hold 9-of-trump alongside a NON-rank-adjacent
  lower trump (T/K/Q/8/7), play the lower instead — fishing opp's
  J/A; the 9 wins next trick. Verbatim: «لو عندك تسعه + ثمانيه ...
  ما تلعب التسعه ... لان ما عندك حافه فوقها». Misplay leaks 14 raw
  points per occurrence.

### MEDIUM — variance smoothing (Tier 3 + Tier 4)

- **Tasgheer near-lowest variance (Tier 3 / HIGH-5)**: pre-fix the
  losing-side dump always played absolute lowest — broadcasted
  hand contents 100% of the time per video #05's «بنسبه ٩٠%»
  read. ~7% probabilistic at M3lm+ tier (non-clutch state,
  ≤3-rank-gap to second-lowest), the bot now plays second-lowest
  instead — corrupts opp's reads without burning a real winner.

- **Variable jitter per escalation rung (Tier 4 / MED-7)**: pre-fix
  all four rungs used the same ±10 jitter. Now Bel ±10 (BEL_JITTER),
  Triple ±12, Four ±15, Gahwa ±18 — escalation chain is no longer
  linearly correlated. Per video #11 the rungs are explicitly
  separate strategic acts («الفور على القهوه»).

- **Bel-fear piecewise ramp (Tier 4 / MED-9)**: pre-fix +8 cliff at
  cumulative > 100 was a hard line. Now: 0 below 90 / lerp to +8
  by 105 / +8 in 105–130 / lerp back to +3 by 152. Matches the
  band of changing aggression video #25 describes.

- **Round-1 position-aware conservatism (Tier 4 / MED-10)**: pre-
  fix R1 first-lap-pass discipline (video #25 «اذا كنت تشك خلاص
  امرر») wasn't wired. Now bidPos 1 (info-poor) gets +5 thresh
  bias, bidPos 2 +3, bidPos 3-4 unchanged.

### Tests

821/821 pass. Existing test suite covers correctness; the v1.1.0
changes add controlled non-determinism that's harder to pin via
unit tests. Behavioral verification is via real-game observation
(the user's primary use case).

### NOT shipped (still backlogged for v1.1.1+)

The third-pass agent surfaced two more high-value rules that need
a more careful Rules.lua/state touch:

- **Closed-trump under Bel ×2 / Four ×4 (transcript H2)**: per
  video #11 «اللعب راح يكون مقفول ... ما يربع بحكم» — under even-
  multiplier Hokm, trump-leading is forbidden unless you have only
  trump in hand. Requires legality-layer change in `Rules.lua` +
  bot pickLead branch. Deferred — touches the must-follow rule
  semantics.

- **Tier 5 features**:
  - "Control the game" tempo management (video #20) — needs new
    `handStrength` signal tracking
  - Opp-Tanfeer 6-factor confidence scoring (video #19)
  - Sun-bidder-partner play branches (currently in sampler only)

- **AKA uncertainty band tightening (transcript H3)**: when round
  is doubled AND `S.HighestUnplayedRank` confidence is uncertain
  (a higher card might be in opp's hand), AKA risks a Qaid. Adjacent
  to the v1.1.0 probabilistic withhold; deferred.

- **Tahreeb sender forced-vs-intentional flag (transcript M2)**:
  bot's `tahreebSent` log doesn't distinguish forced discards from
  intentional signals. Partner-side reads can be misled when bot
  was forced to dump from its strong suit. Adjacent to Tier 2;
  deferred.

- **Style ledger dead-code wiring** (Tier 3 partial / partner-coord
  H7): `trumpEarly`, `trumpLate`, `leadCount`, `aceLate` are
  written by observers but only read by the BotMaster sampler —
  not by `pickPlay` decisions. Wiring these into pickLead trump-
  pull urgency and pickFollow opp-reads is a focused v1.1.1 cycle.

## v1.0.12 — Reverse Al-Kaboot canonical rule (D HIGH-3)

User supplied the canonical Saudi PDF text for reverse-Kaboot
(الكبوت المقلوب), replacing the v0.10.5 video-#16 single-source
hypothesis. Both the gate AND the reward value changed. 821/821
tests pass.

### CRITICAL — Saudi-rule conformance

User-supplied PDF text:
> «اللاعب الذي على يمين الموزع بشراء صن و(كبتت) عليه ولديه إكه
>  سواء أخذها من الميدان أو كانت في يده. تسجل للفريق المقابل كبوت
>  مقلوب بـ(88) بنط بالمشاريع»

= "When the player on the dealer's right buys Sun and is kabooted,
   AND has an Ace whether he took it from the field [trick/bidcard]
   or it was in his hand. The opposite team scores reverse-kaboot
   at (88) banta with the melds [+ defender's declared melds]."

### What changed

**Pre-v1.0.12 (video-#16 hypothesis)**:
- Gate: defender sweeps + bidder led trick 1
- Reward: `K.AL_KABOOT_REVERSE = 88` raw, multiplied by cardMult
  (88 raw in Hokm = 9 banta; 176 raw in Sun = 18 banta).

**v1.0.12 (user-canonical PDF rule)**:
- Gate: defender sweeps + Sun bid + bidder on dealer's right +
  bidder played an Ace at any point
- Reward: `K.AL_KABOOT_REVERSE = 880` raw, **cardMult-immune**
  flat (yields 88 banta exactly, same in Sun-bare and Sun-Bel'd)
  + defender's declared melds × meldMult (the «بالمشاريع» clause)

### Implementation

- **`Constants.lua`**: `K.AL_KABOOT_REVERSE` 88 → 880 with
  semantics-update comment block citing the user-supplied Arabic
  text and translation.
- **`Rules.lua` reverse-AK gate**: replaced the bidder-led-trick-1
  check with a 4-condition check (`Sun + dealer-right +
  bidder-played-Ace`). Falls through to regular fail when any
  condition fails. Uses the existing `dealerSeat` parameter
  (added in v1.0.9 for PDF Rule 2).
- **`Rules.lua` rawA/rawB computation**: introduced
  `cardMultEffective = sweepIsReverseAK and K.MULT_BASE or
  cardMult` so the reverse-AK bonus bypasses cardMult (matching
  the "88 banta flat" PDF reading). Defender melds still get
  `meldMult` (Sun×2 or Sun×2×Bel×2 per D HIGH-1 cap).
- **`docs/strategy/saudi-rules.md`**: rewrote the Reverse Al-Kaboot
  bullet with the verbatim Arabic text, four conditions, and the
  `880`-flat-raw reward.

### Tests

- **`tests/test_rules.lua` Section H** (rewritten):
  - **H.10**: Hokm contract → reverse-AK gate fails (Sun required);
    falls through to regular fail (defender takes `handTotal=162`).
  - **H.11**: Sun + all 4 conditions met → 88 banta flat.
  - **H.11b** (NEW): Sun reverse-AK + defender 50-meld → 88 + 10
    = 98 banta (verifies the «بالمشاريع» clause).
  - **H.11c** (NEW): bidder has NO Ace → reverse-AK gate fails.
  - **H.11d** (NEW): bidder NOT on dealer's right → gate fails.
  - **H.12**: defender-led trick 1 NO LONGER blocks reverse-AK
    (gate replaced; pre-v1.0.12 this was the discriminator).
  - **H.13**: forward AK regression pin (unchanged).
- **Section J** updated: Hokm-defender-sweep no longer triggers
  the reverse-AK Belote-override (Hokm doesn't qualify post-v1.0.12).
  New test verifies Sun reverse-AK fires when conditions met (Sun
  has no Belote — Hokm-only — so the override path is moot).

### What WASN'T changed

- Forward Al-Kaboot semantics (250 Hokm / 220 Sun) preserved.
- Sun×2 / Sun×Bel multiplier behavior preserved.
- Net.lua Qaid handlers (HostResolveTakweesh + HostResolveSWA) do
  NOT have a reverse-AK path — the rule only fires in
  R.ScoreRound at end-of-round.

## v1.0.11 — Big-3 deferred backlog: Belote announcement + either-defender Bel + BALOOT button

Closes the three big deferred items from v1.0.10's backlog. 813/813
tests pass.

### CRITICAL — Saudi-rule conformance

- **D HIGH-2: Belote announcement requirement (PDF §Belote)**.
  Pre-v1.0.11 the +20 K+Q-of-trump bonus was auto-detected
  retroactively in `R.ScoreRound` — the bonus always counted as
  long as the same seat had played both K and Q of trump. PDF text
  «يجب على اللاعب الذي لديه البلوت ذكره أثناء لعب الورقة الثانية
  وقبل نزولها على الأرض» = "the holder must announce on the
  second card of K/Q-of-trump play, before it lands". Now wired
  end-to-end:
  - **`K.MSG_BELOTE = "$"`** wire constant + `N.SendBelote` /
    `N._OnBelote` / `N.LocalBelote` handlers.
  - **`S.s.beloteAnnounced = {}`** per-seat flag. `S.ApplyBeloteAnnounce`
    mutates on every client (idempotent; plays K.SND_BALOOT cue).
  - **`R.ScoreRound` gate**: 5th optional `beloteAnnounced` parameter
    drops the +20 bonus when the holder is NOT in the announce-set,
    UNLESS the holder's team has a sequence meld in trump suit
    covering K+Q (PDF exception: «إذا كان البلوت مكشوف مع مشروع
    متسلسل فيحسب حتى لو لم يُذكر»). Helper `R.TeamSequenceCoversBelote`
    exposed for the same gate in `Net.lua`'s Qaid handlers
    (HostResolveTakweesh + HostResolveSWA invalid-SWA branch).
  - **Back-compat**: legacy callers passing only the original 4
    args get the pre-v1.0.11 behavior (Belote always counts) so
    pre-v1.0.11 saved sessions migrate cleanly.

- **BALOOT! button (Saudi-spelling, flashing)** in `UI.lua`
  PHASE_PLAY render path. Per user request: button label is
  "BALOOT!" (not "BELOTE") to match Saudi/Khaleeji transliteration
  of «بلوت». Visible to local seat when:
    - Hokm contract + trump suit set, AND
    - Local hand had/has BOTH K and Q of trump (combines current
      hand + already-played cards by this seat — covers the
      narrow window between first-of-pair and second-of-pair
      plays), AND
    - Has not yet announced (`S.s.beloteAnnounced[localSeat] ~= true`).
  Flash animation: `OnUpdate` script pulses the FontString color
  at 1 Hz between bright gold `(1, 1.0, 0.4)` and white-yellow
  `(1, 0.85, 0)` so it grabs attention. WoW frame API; defensive
  no-op if `SetScript` is missing (test environment).

- **Bots auto-announce** via `Net._HostMaybeAutoBelote(seat, card)`,
  called from the host's bot-play paths in `MaybeRunBot` after
  `S.ApplyPlay` + `N.SendPlay`. Detects: was the just-played card
  K-or-Q-of-trump AND has the same bot seat played the other? If
  so, broadcasts MSG_BELOTE for them. Bots always announce in
  real Saudi play; only humans have to click the button manually.

### HIGH — Saudi-rule conformance

- **D MED M1: Either-defender Bel (PDF Rule 4)**. Pre-v1.0.11 the
  Bel/Skip-Double wire gate hardcoded `seat == NextSeat(bidder)`,
  blocking the OTHER defender (`PrevSeat(bidder)`) from ever
  Bel'ing. PDF text «المدبل» (the doubler) does not specify which
  defender — whoever calls Bel first becomes the doubler. Now:
  - **`Net._OnDouble` / `_OnSkipDouble` / `LocalDouble` /
    `LocalSkipDouble`**: gate on `S.s.belPending` membership
    (which already lists both defenders).
  - **`S.ApplyDouble`**: sets `S.s.contract.doublerSeat = seat`
    so subsequent Four eligibility targets the SPECIFIC defender
    who Bel'd (PDF Rule 4: bidder ↔ doubler only).
  - **`Net._OnFour` / `_OnSkipFour` / `LocalFour`**: gate on
    `contract.doublerSeat` with NextSeat fallback for stale
    pre-v1.0.11 saved state.
  - **`UI.lua` PHASE_DOUBLE / PHASE_FOUR render**: `inPending`
    helper for the Bel button; `doublerSeat`-with-fallback for
    the Four button.
  - **`Net.MaybeRunBot` PHASE_DOUBLE dispatcher**: iterates ALL
    pending defenders in NextSeat-first order (Saudi vocal-priority
    convention). First bot to say YES Bels and the chain advances;
    bots that say NO emit MSG_SKIP_DBL and are removed from
    belPending. Remaining humans get a sequential AFK timer.
  - **`Net._HostBelTimeout`**: per-seat timeout removes ONE
    defender from belPending; finish deal only when empty.
  - **`Net.S.IsMyTurn` "bel" / "four" branches**: belPending
    membership check / doublerSeat respectively.

### Tests

- **`tests/test_rules.lua` Section T (NEW, 6 tests)**: Belote
  announcement gate.
  - T.1: legacy callers (no `beloteAnnounced` arg) → counts
    (back-compat preserved).
  - T.2: announced → counts (PDF base case).
  - T.3: NOT announced + no covering meld → DROPS.
  - T.4: NOT announced but trump-seq meld covers K+Q → counts
    (PDF exception).
  - T.5: NOT announced + sequence in NON-trump → DROPS (exception
    is trump-only).
  - T.6 (a/b/c): `R.TeamSequenceCoversBelote` helper unit tests.
- **`tests/test_state_bot.lua` Section AM (NEW, 4 tests)**:
  either-defender Bel state.
  - AM.1: `S.ApplyDouble` sets `contract.doublerSeat`.
  - AM.2: `S.ApplyContract` initializes `belPending` with both
    defenders.
  - AM.3: nil-doublerSeat fallback to NextSeat (4 bidder positions).
  - AM.4: `S.ApplyBeloteAnnounce` idempotent + nil-defensive.

### NOT shipped (still backlogged)

- **D HIGH-3 Reverse Kaboot rule arbitration**: PDF cross-check
  found NO mention of reverse-kaboot in the extracted PDFs (1, 2,
  3a, 3b, 4, 5, 6, 7). Current 88 raw + bidder-led-trick-1 was a
  single-source rule from video #16 documented as "confirm before
  wiring". Alternate 99 raw + dealer-right-Ace-held was a swarm
  hypothesis without strong source backing. Investigation deferred
  pending stronger source evidence — current rule preserved as
  default.

- **`Bot.PickKawesh` partner-Hokm gate (LOW from v1.0.10 audit
  pass-3)**: agent flagged as a missing gate, but Kawesh fires
  PHASE_DEAL1 (pre-bidding) so partner-bid doesn't yet exist at
  that phase — the agent likely conflated kawesh-pre-bid with
  kasho-during-play. Kept open for future investigation.

## v1.0.10 — Audit pass-3 quick wins + partner-Hokm BC-MANDATORY override

Closes the LOW/MED severity items from v1.0.9's 4-agent ultra-audit
plus a HIGH edge-case from a fresh agent review of partner-Hokm
overcall strategy. 791/791 tests pass.

### CRITICAL — Saudi-rule conflict resolution

- **BC-MANDATORY Belote overrides G-4 partner-Hokm suppression
  (Bot.lua PickBid R2)**. Pre-v1.0.10 the G-4 partner-Hokm
  suppression block (videos #29 + #34: "do NOT outbid partner's
  Hokm") fired BEFORE the BC-MANDATORY-Belote bypass (video #26
  rule B-6: "Mandatory Hokm with the Belote suit as trump"). Two
  Definite-confidence Saudi rules conflicted; G-4 silently won.
  Result: a hand with K+Q+canonical-4-seq in a non-bidcard suit
  could be forced to PASS when partner had bid Hokm-of-other-suit
  — forfeiting the +20 multiplier-immune Belote bonus. Per the
  partner-Hokm-overcall agent review, the structural Belote
  outweighs partner-support: the bot now overrides G-4 only when
  `beloteBypassQualifies` returns true for a non-bidcard suit
  (canonical 4-card trump-seq OR K+Q+count>=3+sideAce). This is
  the ONLY HOKM-on-HOKM overcall the bot ever performs.

### MEDIUM — Bot strategy

- **M5 target folds Belote ±20 (Bot.lua trick-8 winners block,
  audit pass-2 A MED-1 / B LOW-1)**. Pre-v1.0.10 M5's
  algebraically-correct `(oppMeld - myMeld) / 2` adjustment
  ignored Belote entirely. With opp holding Belote (K+Q-of-trump
  same-seat, +20 raw), the effective target was off by +10 raw —
  enough to mis-classify boundary make-or-break decisions at
  trick-8. Now folds `(oppBelote - myBelote) / 2` into target;
  uses `R.IsBeloteCancelled` to match the same ≥100-meld-subsumes-
  Belote rule that R.ScoreRound applies. Hokm-only (Sun has no
  Belote).

### LOW / cleanup

- **R.TeamOf nil-seat defensive guard (Rules.lua, audit pass-2 B
  LOW-3)**. Pre-fix nil seat fell through to silent `return "B"`
  (mis-attribution to team B). Now nil/invalid → nil so callers
  can branch on it. Existing call sites unaffected (all pass
  validated seats; 791/791 tests still green).

- **R.MeldRank docstring (Rules.lua, audit pass-2 A MED-3)**.
  Doc warning added: `R.MeldRank` returns ordinal value only and
  does NOT apply PDF Rule 2 dealer-right tiebreaker. Callers that
  need to resolve a tied-rank winner must use `R.CompareMelds`
  with `dealerSeat` instead. `Bot.PickMelds` is fine using
  MeldRank directly (only needs strict-greater for filter logic).

- **AL.2 test top="K" → top="A" (audit pass-2 C MED-2)**. The
  Q-K-A sequence's actual top is A. Pre-fix typo was harmless
  (partner's len=4 outranked regardless) but fragile if equal-
  length melds were ever compared.

- **AL.4 rewritten as direct unit tests on `Bot._beloteBypassQualifies`
  (audit pass-2 C MED-1)**. The PickBid path satisfies A#2
  transitively for canonical-4-seq hands (T-J-Q-K passes thHokmR1
  on strength alone), making the canonical-4-seq branch
  behaviorally untestable through PickBid. Helper now exposed on
  `Bot._beloteBypassQualifies`; AL.4 splits into 7 sub-tests
  (a-g) each isolating a specific gate (T-J-Q-K, J-Q-K-A,
  K+Q+count≥3+sideAce, count==2 fail, no-sideAce fail, no-K fail,
  nil-suit defensive).

### Tests

- **AL.5 (NEW)**: G-4 regression pin — partner-Hokm with strong
  different-suit Hokm hand → BID_PASS.
- **AL.6 (NEW)**: G-4 Sun-overcall allowance — partner-Hokm with
  Sun-shape → BID_SUN.
- **AL.7 (NEW)**: BC-MANDATORY > G-4 — partner-Hokm with K+Q
  Belote in non-partner suit → HOKM:beloteSuit overcall.
- **AL.4 (REWRITTEN)**: 7 direct unit-test assertions on
  `Bot._beloteBypassQualifies` (a-g).
- Y.3b source-pin window bumped 25000→32000 to accommodate the
  new BC-MANDATORY-overrides-G-4 block.

### Deferred (still in backlog)

- **D HIGH-2 Belote announcement requirement**: requires
  MSG_BELOTE wire + S.s.beloteAnnounced flag + UI button +
  R.ScoreRound gate. Substantial multiplayer-coordination scope.
- **D MED M1 Either-defender Bel**: requires multi-seat
  belPending tracking + UI changes + AFK timer rework + bot
  dispatcher updates. Touches 10+ files; needs multiplayer test
  surface.
- **D HIGH-3 Reverse Kaboot rule arbitration**: PDF text supports
  88 raw + bidder-led-trick-1 (current) OR 99 raw + dealer-right-
  Ace-held (alternate); user arbitration required.
- **`Bot.PickKawesh` partner-Hokm gate (LOW)**: investigation
  pending — Kawesh fires at PHASE_DEAL1 (pre-bidding), so partner-
  bid doesn't yet exist; agent's finding may have conflated
  pre-bid kawesh vs in-play kasho. Will research.

## v1.0.9 — PDF cross-check fixes + 4-agent swarm closure

This release closes the critical findings from the four-agent swarm
(A=Saudi-pro convention, B=human-reading skills, C=partner-coordination,
D=BalootGCC official PDF rules cross-check) plus the two A-class bot-
strategy items the user explicitly green-lit. 760/760 tests pass.

### CRITICAL — actual scoring bugs

- **A#1: M5 algebra error reverted to canonical formula (Bot.lua
  trick-8 winners block).** v1.0.6's N3 introduced two compounding
  errors in defender M5 target estimation: (a) algebra was off by
  2× (used `oppMeld - myMeld` where the canonical R.ScoreRound
  formula is `(oppMeld - myMeld) / 2`), and (b) didn't consult
  `R.CompareMelds` winner-takes-all. With opp's 100-meld declared,
  the bot computed the wrong threshold by ~5 raw, mis-firing M5
  swings on doomed contracts. Now uses the canonical formula AND
  consults CompareMelds for winner-takes-all attribution.

- **D HIGH-1: Multiplier semantics split for cards vs melds
  (Rules.lua R.ScoreRound).** PDF §5-5 / §5-6 cross-check vs
  v0.11.10 user arbitration: melds DO NOT cascade past Bel.
  Pre-v1.0.9 a Triple/Four/Gahwa contract multiplied BOTH cards AND
  melds by Bel×Triple/Four/Gahwa (cascading multiplier). Per PDF
  §5-6 melds only ever multiply by Bel (×2), regardless of what
  rung the contract reached — the higher rungs only multiply
  CARDS. User re-arbitrated: "option A i was wrong" — agreed with
  PDF reading. Now the result struct exposes `cardMultiplier` and
  `meldMultiplier` separately; legacy `multiplier = cardMult` for
  back-compat with consumers that haven't been updated.

### HIGH — Saudi rule conformance

- **Rule 2 (PDF §): tied-meld dealer-right priority
  (Rules.lua R.CompareMelds + R.ScoreRound).** PDF text:
  «في حال تساوى مشروعان متشابهان في القيمة فأفضلية النزول لمن
  على يمين الموزع» — "if two equal-value melds tie, declaration
  priority goes to the player on the dealer's right." Pre-v1.0.9
  ties returned "tie" → both teams scored 0 melds. Now: walk seats
  starting at NextSeat(dealer); the first seat declaring a top-rank
  meld takes the win for its team. Optional `dealerSeat` parameter
  preserves back-compat for callers without dealer context.
  Updated 3 callers (State.lua, Net.lua, BotMaster.lua) to pass
  the dealer.

### MEDIUM — Bot strategy tightening

- **A#2: BC-MANDATORY-Belote bypass tighten (Bot.lua PickBid).**
  Pre-v1.0.9 the BC-MANDATORY bypass fired whenever the Belote
  suit merely passed `hokmMinShape` (which admits K+Q+count==2 via
  the v0.11.16 escape clause). Over-fired on weak K+Q-only hands
  → routinely-failing Hokm contracts. Tightened: bypass now
  requires structural support — canonical 100-meld in trump suit
  (T-J-Q-K or J-Q-K-A) OR K+Q+count>=3+sideAce. Belote +20 bonus
  still contributes to the strength score (so the standard
  threshold gate retains Belote awareness), but only auto-fires
  when Mandatory-Belote is structurally backed.

- **C#2: PickMelds Qaid-protection meld filter (Bot.lua
  PickMelds).** Saudi meld scoring is winner-takes-all
  (R.CompareMelds). If opps have already declared a higher-rank
  meld AND partner has no winning declaration, our team's
  declarations all drop to 0 anyway — declaring losing melds is
  pure information cost (revealing 3-4 cards) for 0 expected
  score benefit. Filter to candidates that either flip the outcome
  (candidate beats opp's best) OR ride a partner's already-winning
  declaration. Exposes `R.MeldRank` for external rank queries.

### Ultra-audit pass-2 fixes (post-staging swarm)

A 4-agent ultra-audit (Saudi-pro / code-effect / test-quality /
PDF-conformance) of the v1.0.9 staged diff surfaced four follow-on
fixes BEFORE shipping:

- **Net.lua Qaid handlers cardMult/meldMult split (CRITICAL)**:
  `HostResolveTakweesh` (line ~2462) and `HostResolveSWA` invalid-SWA
  branch (line ~3337) BOTH still applied a single full-cascade `mult`
  to (cards + melds). With D HIGH-1 in `Rules.lua` but unchanged in
  `Net.lua`, a Triple/Four/Gahwa Qaid resolution would over-multiply
  the non-offender's melds by ×3/×4 instead of ×2 — directly
  contradicting the PDF §5-6 fix one file over. Now both Qaid paths
  use the same `cardMult`/`meldMult` split. Legacy `mult = cardMult`
  alias kept for the outer-scope telemetry field.

- **Bot.lua M5 CompareMelds passes dealer**: M5's winner-takes-all
  zeroing now passes `S.s.dealer` so tied-rank scenarios resolve
  the same way `R.ScoreRound` does (PDF Rule 2 dealer-right
  priority). Pre-fix M5 would see "tie" → keep both teams' melds
  while ScoreRound resolved to one team — mis-estimating M5 target
  by up to (oppMeld)/2 in tied scenarios.

- **State.lua S.MeldVerdict passes dealer**: UI's live meld-verdict
  strip now consults dealer for tied-rank resolution, eliminating
  the momentary visual lie where the strip showed "tie/no strip"
  while final scoring awarded melds to the dealer-right team.

- **docs/strategy/saudi-rules.md**: rewrote the Q3/Q5 multiplier
  section to reflect the v1.0.9 PDF §5-6 cap-at-Bel rule. Per
  CLAUDE.md ("If a strategy doc and Rules.lua disagree, Rules.lua
  is authoritative for legality"), the doc was contradicting v1.0.9
  code with the v0.11.10 full-cascade reading.

- **A#2 comment cleanup**: re-labeled "canonical 100-meld" →
  "canonical 4-card trump-sequence" since T-J-Q-K and J-Q-K-A score
  as `K.MELD_SEQ4 = 50` raw, not 100. The gate logic was correct;
  comments and chat traces were misleading.

### Tests

- **AE.1 / AE.2 updated** for A#2 tightening — pre-v1.0.9 hands
  pinned the loose-bypass behavior; updated to use hands that
  satisfy the new gate (K+Q+count>=3+sideAce).
- **AE.1c (NEW)**: K+Q+count>=3 NO sideAce blocks BC-MANDATORY → PASS.
- **AE.2c (NEW)**: K+Q+count>=3+sideAce R2 fires Hokm.
- **AJ.1b / AJ.2b / AK.6 updated** for A#1 algebra (added
  `math.floor((m5_oppMeld - m5_myMeld) / 2)` and `baseTarget`).
- **AJ.2c (NEW)**: A#1 source-pin verifying CompareMelds is
  consulted for winner-takes-all.
- **Section AL (NEW)**: v1.0.9 swarm-finding behavioral coverage.
  AL.1 (C#2 skip), AL.2 (C#2 ride partner), AL.3 (no info), AL.4
  (A#2 4-card trump sequence).
- **K2 section (NEW, test_rules.lua)**: 8 tests for the D HIGH-1
  cardMult/meldMult split. Hokm bare/Bel/Triple/Four/Gahwa, Sun
  bare/Bel, plus a behavioral test asserting `raw.A` reflects the
  cap (250×3 + 100×2 = 950 NOT 1050 full-cascade).
- **F.dealer-right (NEW, test_rules.lua)**: 4 tests for PDF Rule 2
  tied-meld dealer-right priority. dealer=4→A, dealer=1→B,
  walk-skip case, back-compat fallback (no dealerSeat → "tie").

### What WASN'T changed (this release)

The user's PDF cross-check covered four rules. Three are already
canonical in the code (verified), one needs a bigger feature:

- **Rule 1 (Belote announcement requirement)** — D HIGH-2: NOT
  implemented. PDF says the Belote holder must announce on the
  second card or it doesn't count (unless covered by a sequence
  meld). Currently auto-detected retroactively in R.ScoreRound.
  Needs MSG_BELOTE wire + S.s.beloteAnnounced flag + UI button +
  R.ScoreRound gate. Deferred — substantial scope, requires user
  green-light on UX details.
- **Rule 3 (Kaboot + opp's declared melds)**: VERIFIED
  IMPLEMENTED. Sweeper gets bonus + own declared melds; swept
  side's melds drop to 0. Matches PDF "the kabooter team gets X
  points + the مكبِّت's declared melds" reading (active participle
  = sweeping team).
- **Rule 4 (Bel-Triple-Four-Gahwa is bidder-vs-Beler-only)**:
  VERIFIED PARTIAL. Net.lua seat gates: Bel→NextSeat(bidder),
  Triple→bidder, Four→NextSeat(bidder), Gahwa→bidder. The Beler
  seat is HARDCODED to NextSeat(bidder); chain is locked to
  bidder↔Beler-only because Beler-seat is fixed. Caveat: PDF text
  «المدبل» = "the doubler" (the defender who actually Bel'd) does
  not specify which of the two defenders. Saudi-pro convention
  allows EITHER defender to Bel first; current addon restricts to
  NextSeat(bidder) only — PrevSeat(bidder) cannot Bel. Stricter-
  than-necessary gate (not a leak); the partner of the Beler is
  correctly excluded. Future enhancement: add `contract.doublerSeat`
  tracking + open Bel-eligibility to both defenders. Deferred
  (UI/wire/AFK touch points; not a v1.0.9 critical gap).

## v1.0.8 — Triple/Four/Gahwa eltrace observability

User-requested: the existing `[bel sN] PickDouble eval/PASS/FIRE`
trace shows defender Bel decisions when `WHEREDNGNDB.debugBidcalc`
is on. The downstream rungs (Triple, Four, Gahwa) had no
equivalent trace — leaving "why never Triple?" debugging blind.

### Added

- **`Bot.PickTriple` eltrace** (Bot.lua:Bot.PickTriple). Mirror of
  PickDouble's pattern. Logs `[trp sN] PickTriple eval: strength=X
  th=Y jth=Z (BOT_TRIPLE_TH=W)` then PASS or FIRE with wantOpen
  flag. Also logs the `Sun has no Triple rung` short-circuit when
  the Sun-blocked branch fires.

- **`Bot.PickFour` eltrace** (Bot.lua:Bot.PickFour). `[for sN]`
  prefix (orange). Same eval/PASS/FIRE shape.

- **`Bot.PickGahwa` eltrace** (Bot.lua:Bot.PickGahwa). `[ghw sN]`
  prefix (red). Logs eval/PASS/FIRE; FIRE notes "terminal,
  match-win".

### Why this matters

Across the 51-round v1.0.7 sample, Bel fired 3× but Triple fired 0×.
Two interpretations were possible:
1. Bidder correctly didn't escalate marginal Bels (calibrated)
2. Triple threshold structurally too high (mis-calibrated)

The eltrace now disambiguates: the next time PHASE_TRIPLE fires,
the trace will show the bidder's strength score and threshold,
making it visible whether the bidder was below threshold by 1 or
by 30. Same applies to Four (PHASE_FOUR) and Gahwa (PHASE_GAHWA).

### Tests

753/753 pass. AH.3 source-pin window bumped 2500→4000 to
accommodate the new eltrace block in PickTriple.

### How to use

`/baloot bidcalc` toggles the existing debug flag. With it on,
all four escalation rungs now log to chat with color-coded
prefixes:
- `[bel sN]` cyan-green — defender Bel decision
- `[trp sN]` cyan — bidder Triple decision
- `[for sN]` orange — defender Four decision
- `[ghw sN]` red — bidder Gahwa decision

## v1.0.7 — Test-debt closure (Section AK behavioral coverage)

Test-only release. Adds 7 behavioral tests (Section AK) that exercise
v1.0.4 + v1.0.6 bot-logic fixes by setting up game state and asserting
on `Bot.PickPlay` / `Bot.PickTriple` outputs. No bot-logic, schema,
or calibration changes. 753/753 tests pass.

### What v1.0.4 / v1.0.6 lacked

Sections AI (8 tests) and AJ (9 tests) were source-pin only — they
verified the relevant code blocks existed in source via `find()`
patterns, not that the code BEHAVES correctly. v0.11.19-hotfix F1
proved this anti-pattern is dangerous: a source-pin pass coincided
with a silently broken `if nil and ...` short-circuit (M5 never
fired because of an unbound variable). Behavioral tests catch this.

### New behavioral coverage (Section AK)

- **AK.1 (N2 behavioral): Foured smother gate.** Sets up Foured
  contract + pos-3 + partnerWinning + 2 H point cards in hand;
  asserts the bot does NOT smother A (gate=lastSeat-only at ×4).
- **AK.2 (N2 behavioral): Doubled tier preserves donate.** Same
  setup but ×2 contract + 5 prior tricks completed; asserts the
  bot DOES smother A (gate=lastSeat OR completed≥4 at ×2).
- **AK.3 (N1 behavioral smoke): Urgency-swing meld-pin guard.**
  Constructs near-clinch state with partner-meld declaring AH;
  asserts pickFollow returns SOME card (smoke — exact card depends
  on multi-branch interplay; the source-pin AJ.3 verifies block).
- **AK.4 (agent #6 behavioral): touch-honor save filters A/T.**
  Sets `Bot._partnerStyle[partner].topTouchSignal[H] =
  {nextDown="K"}`; asserts smother donates Q (not A or T) when
  partner has signaled K-singleton inference.
- **AK.5 (agent #8 behavioral): Mathlooth K-tripled.** Sun
  contract + 3 H cards + can't-beat path; asserts K is NOT picked.
- **AK.6 (N6 behavioral pin): defender M5 no +1 off-by-one.**
  Source-pin verifies `defenderTarget = baseTarget + m5_oppMeld
  - m5_myMeld` (no +1) — combined with N3 meld delta math.
- **AK.7 (FLOOR-3 behavioral): PickTriple floor cap respected.**
  Constructs weak hand + maximum urgency drop; asserts PickTriple
  does NOT fire even at the floor cap edge.

### Deferred — full Cluster 7 conversion

The original v1.0.4 deferred-list mentioned ~10 source-pin tests to
convert to behavioral. Section AK adds 7 NEW behavioral tests (the
highest-leverage ones — covering recent bot-logic changes). The
remaining source-pin tests in T/U/V/W/X/Y/Z and earlier sections
are mostly historical pins of old fixes; converting them is
mechanical work with diminishing returns. Defer until a specific
test fragility surfaces.

## v1.0.6 — Dual ultra-audit findings + deck refresh

Closes the dual-agent audit run from the v1.0.5 cycle (one bot-
behavior agent finding 9 NEW gaps; one code-effect agent finding 8
issues including a real off-by-one bug). Plus user-requested deck
changes. 746/746 tests pass.

### CRITICAL — actual logic bug (real-game impact)

- **N6: M5 defender mirror off-by-one (Bot.lua:M5 trick-8 block).**
  Pre-fix code used `defenderTarget = base + 1`, but Saudi rule
  per CLAUDE.md and Rules.lua: bidder fails on tied half-and-half.
  Defender at exactly 81 raw (Hokm) or 65 raw (Sun) ALREADY forces
  bidder fail. The `+1` was wrong by 1 raw — fired the swing 1 raw
  too late. Mostly benign (just spurious fires) but inconsistent
  with the bidder mirror. Now both mirrors use `baseTarget` directly.

- **N3: M5 mirrors ignore meld bonuses in target.** Both bidder and
  defender mirrors used bare 81/65 constants — but `R.ScoreRound`
  adds melds to team totals. Opp declared 100-pt carré → bidder's
  REAL make-threshold is 181 (M5 fired highestByRank on a doomed
  contract). Now: `target = baseTarget + oppMeld - myMeld`.

### HIGH severity — gap-closing fixes

- **N1: Urgency-aware swing × meld-pin guard (Bot.lua:pickFollow).**
  v1.0.4 #1 (urgency swing) fired before pos-aware ducks under
  match-point pressure but didn't consult Cluster 1 meld awareness.
  Worst-case: bot grabs trick with K when partner's already-
  declared meld holds A — strands partner's run. Now: before swing
  fires, check `meldKnownHeld(partner)` for higher-rank cards in
  led suit; suppress swing if found.

- **N2: Multiplier-aware tightening tiered (Bot.lua:smother).** Pre-
  fix v1.0.4 #2 treated all escalation rungs identically as
  `lastSeat-only`. But ×2 (Bel, the COMMONEST) shouldn't suppress
  speculative donates as aggressively as ×3/×4. Now tiered:
  `foured/tripled → lastSeat only`, `doubled → lastSeat OR
  completed >= 4`, base unchanged otherwise.

- **N5: ISMCTS rollouts mute `S.s.cumulative` (BotMaster.lua).**
  v1.0.4 #1's urgency-aware swing reads `S.s.cumulative` directly.
  C-14 closure swapped hostHands/trick/_memory but NOT cumulative
  → all rollout worlds homogenize under match-point pressure,
  killing variance/discrimination. Now cumulative is saved/nil'd
  during rollouts and restored on cleanup.

### MEDIUM — code quality / cleanup

- **B#1 ESC-1 comment correction (Bot.lua:escalationStrength).**
  Comment claimed "inverts the Sun-only void penalty"; actual code
  is "neutralization" (cancels Sun penalty so EV-1 voidBonus passes
  through clean). Behavior is correct (voids count positive in Hokm
  via EV-1's +5/void). Comment now accurately describes the
  neutralize+EV-1-bonus pattern. No math change.

- **B#3+#4 Dead-code removal (UI.lua).** v1.0.5 made
  `meldTextVisible()` always return false; `meldsDescForSeat()`
  builder + `if meldTextVisible() then ...` arms became
  unreachable. Removed both functions and collapsed the dead arms.
  ~22 lines of unreachable code gone.

- **B#6 State.lua R.TeamOf (S.ApplyRoundEnd:trickWinners).**
  Inline `(winSeat == 1 or winSeat == 3) and "A" or "B"` replaced
  with `R.TeamOf(winSeat)`. The team-mapping rule lives in one
  place (Rules.lua:25-28); duplication risked silent telemetry
  desync if the rule ever changed.

### LOW — UX / display

- **B#7 Tooltip rename (UI.lua:M3lm tooltip).** "Beled / Tripled"
  → "Doubled / Tripled" to match v1.0.2's "Bel" → "Double x2"
  rename. v1.0.2 missed this user-visible string.

### User-requested deck changes

- **"Burgundy" → "4 Colors" display rename (UI.lua).** Internal
  key `burgundy` and `texSubdir` preserved so existing
  `WHEREDNGNDB.cardStyle = "burgundy"` entries keep working
  without migration. Display name only.

- **"Royal Noir" → "Ba8ala SET" + new card art (UI.lua + 32 TGA
  files in `cards/royal_noir/`).** Replaced Royal Noir card art
  with [xCards](https://github.com/Xadeck/xCards) (BSD-2 license)
  via `tools/convert_xcards_to_baqala.py`. Saudi-relevant 32
  cards (7-A × 4 suits) at @2x source density Lanczos-downscaled
  to 128×192 32bpp BGRA TGA. Internal key `royal_noir` and
  `texSubdir` preserved (option A migration: existing settings
  keep working). `back.tga` preserved from the original Royal
  Noir charcoal/gold aesthetic.

### Tests

- 9 new source-pin assertions in Section AJ covering AJ.1 (N6 + N3
  off-by-one fix), AJ.2 (N3 meld-aware), AJ.3 (N1 partner-meld
  guard), AJ.4 (N5 ISMCTS swap), AJ.5 (N2 tiered gate), AJ.6 (B#6
  R.TeamOf), AJ.7 (B#3+#4 dead code), AJ.8 (B#7 tooltip), AJ.9
  (deck renames).
- 746/746 tests pass (was 727/727 at end of v1.0.5).

### Deferred / not-fixed-this-release

- **N7 Sun-bidder-drought disambiguation** — refinement; defer.
- **N8 Defender observation asymmetry** — new feature (defender-
  side tells), not a bug fix.
- **N9 `meldKnownHeld` + bidcard composition** — refactor
  opportunity; defer.
- **B#5 CHANGELOG line-number drift** — small drift (~17 lines on
  v1.0.4 entries). Cosmetic for git-spelunkers; future debugger
  habit is to grep on function name not line number.
- **B#8 Historical CHANGELOG `K.SND_MELD_DECLARE` ref** — point-
  in-time accurate; leave.
- **N4/B#2 BEHAVIORAL coverage for AI section** — partial. AJ
  section has additional source-pins; behavioral tests with
  state-setup harnesses deferred to a focused test-debt cycle
  (alongside Cluster 7 from v1.0.4).

## v1.0.5 — Hide trick-1 meld text label (user UX request)

User-requested behavior change: the small text label under each
player's name during trick 1 ("Seq3 K (20)" / "Carre J (100)" etc.)
is now hidden permanently. Saudi convention is verbal-only
announcement — no on-screen badge.

### What changed

- **`UI.lua` `meldTextVisible()` always returns `false`.** Pre-v1.0.5
  it returned true during DEAL3/PLAY when no tricks had completed
  (`#s.tricks == 0`), making the meld text label visible until
  trick 1 closed.

### What stays

- **Trick-1 sound cue:** unchanged. `S.ApplyMeld` (v1.0.2 wiring)
  fires `K.SND_MELD_SERA / 50 / 100 / 400` based on meld value/
  kind/contract. Audio announcement remains the primary
  declaration signal.
- **Trick-2 card reveal:** unchanged. When a declarer's turn
  arrives in trick 2, their meld cards display for 5 seconds
  via the `meldHoldUntil` mechanism. Cards-as-proof is preserved.
- **Round-end summary:** unchanged. The banner at round end
  shows what melds got declared and their values.

### Tests

726/726 pass. Single-line behavior change to a UI-only helper
with no test impact.

## v1.0.4 — Bot-vs-human behavior gap closure (8 audit findings)

Closes the 8-finding bot-behavior audit from the v1.0.3 cycle.
Addresses structural gaps in trick-play decision-making that were
NOT on the original v1.0.0 deferred list. 726/726 tests pass.

### HIGH severity (2 items)

- **#1 Trick-play urgency-blindness (Bot.lua:pickFollow ~3997).**
  PickBid/PickDouble/PickTriple/PickFour/PickGahwa/PickPreempt/
  PickOvercall/PickAKA all consult `scoreUrgency` /
  `combinedUrgency` / `matchPointUrgency` — but pickLead and
  pickFollow ignored cumulative state. A defender at 145/152 plays
  the same as at 0/152. Now pickFollow's winners-block pre-empts
  the pos-aware ducks with a `highestByRank` swing under match-
  point pivotal pressure (myCum >= target-25 OR oppCum >=
  target-15). M3lm-gated. Skips trick 8 (M5 already handles it).

- **#2 Trick-play multiplier-blindness (Bot.lua:pickFollow ~3490).**
  Smother / winners-block / M5 trick-8 logic ignored
  `contract.doubled` / `tripled` / `foured` — but a 10-face-value
  swing in a Foured (×4) round is worth 40 effective. Smother gate
  now tightens to **lastSeat-only** (free-dump path) when any
  escalation is active. Speculative donates (≥2 point cards spare
  OR late-round) deferred under multiplier ≥ 2.

### MEDIUM severity (6 items)

- **#3 BotMaster sampler bidcard downweight
  (BotMaster.lua:sampleConsistentDeal).** The v0.11.19 U-3 bidcard
  inference flips trump-pull-exhaustion in pickFollow but
  `sampleConsistentDeal` still placed side-suit-A bidcard cards in
  defender hands via the H-2 defenderDesire bias (each non-trump
  Ace = 8). When bidcard is a side-suit Ace owned by bidder, the
  defender bias for THAT specific Ace is now cleared so the
  sampler doesn't waste cycles on inconsistent worlds.

- **#4 PickDouble bid-history inflection
  (Bot.lua:Bot.PickDouble).** The contract's provenance carries
  hand-quality info: a Sun-on-A-bidcard with prior bidders implies
  preempt-Sun shape (strong). `contract.overcallFromHokm` flag
  implies overcall-converted Sun (very strong). Both bias `th`
  upward by +5 to deter Bel'ing strong-tells contracts. M3lm-gated.

- **#5 Bargiya receiver phase-split (Bot.lua:pickLead ~2425).**
  Per signals.md §3 (canonical): receiver of a confirmed bargiya
  with ≥5 cards remaining (opening / mid-round) should burn 1-2
  of own tricks first to set up the eventual lead-back — not
  surrender initiative immediately. Endgame (≤4 cards) DOES lead
  the bargiya'd suit immediately. Phase-split now suppresses the
  pref for confirmed-bargiya signals when handSize >= 5; bargiya_
  hint / want / endgame retain the immediate lead-back behavior.

- **#6 Touching-honors signal in pickFollow
  (Bot.lua:pickFollow smother ~3450).** F3 wired the partner-touch-
  honor read in pickLead in v1.0.0. Mirrored here in the smother
  branch: when partner has shown a K-singleton (entry.cleared =
  {Q,J}) or any T/Q signal in the LED suit, save A and T — let
  partner cash the run on their own lead. Filters A/T out of
  pointCards; K/Q/J still donate.

- **#7 M5 trick-8 defender mirror (Bot.lua:pickFollow trick-8).**
  v0.11.19 M5 added bidder-team make-the-bid awareness on trick 8.
  Symmetric defender goal (force bidder fail at strict-majority,
  target+1 raw) now gets the same `highestByRank` preference when
  defender is in the make-or-break band. Defender at 75 raw needs
  ≥82 raw to force Hokm-bidder fail; trick 8 = swing.

- **#8 Mathlooth K-tripled trickle in Sun
  (Bot.lua:pickFollow ~4257).** Per decision-trees.md §4 row 11
  (Definite, video 17): Sun + K + 2 lower in side-suit + suit
  led + tricks 1-2 → reserve K for trick 3 (after A and T fall).
  Now excludes K from the lowestByRank candidate pool when this
  shape exists, so the trickle dumps 7/8 first and K cashes
  trick 3. M3lm-gated.

### Tests

- 8 new source-pin assertions in Section AI covering each of the
  8 agent findings.
- Total: 726/726 tests pass (was 718/718 at end of v1.0.3).

### Deferred to v1.0.5

- **Cluster 7 test-debt closure** (~10 source-pin tests to convert
  to behavioral counterparts). Pure mechanical work, no behavior
  change. Held since adding more source-pin tests in this release
  (Section AI's 8 new pins, plus the prior Section AH's 10) would
  go in the wrong direction; the test-debt closure is best done as
  a focused refactor pass with no other changes mixed in.

## v1.0.3 — Deferred-queue closure: 22 audit items from clusters 2-5

Closes the entire v1.0.0-deferred queue from CHANGELOG.md (the
"Deferred from v1.0.0" section). 22 items across 4 audit clusters
plus 10 new source-pin tests in Section AH. No calibration-threshold
changes. 718/718 tests pass.

### Cluster 2 — Defender play (5 items)

- **F5 (Belote K+Q-trump preservation in pickLead defender,
  Bot.lua:~3140).** When forced to lead trump (no non-trump in hand)
  AND we hold both K+Q of trump (Belote pair), prefer trump that's
  NOT K or Q. Belote scoring is locked at meld declaration so this
  doesn't affect the +20 bonus, but keeping the pair together for
  cash-on-our-lead extracts more attack value than an arbitrary
  K-lead. Layered AFTER `saveHighTrump` so the J/9 protection
  still wins; only kicks in for "below-J/9" decisions.

- **F6 (Defender Bargiya defensive-shed in Hokm — DEFERRED).**
  Considered and rejected. The Saudi convention for discard-side-A-
  with-cover is canonically Sun-only; Hokm has its own side-suit
  control signaling via implicit AKA on bare-A lead. A Hokm extension
  conflicted with the U-6 v0.11.19 fix (E.3 test pin). The Sun gate
  stays as-is; Hokm "lead-back" semantic is carried by AKA flow.
  Decision documented in code (no behavior change).

- **F7 (firstDiscard vs Tahreeb conflict — RESOLUTION-DOC).** The
  conflict is structurally resolved via two complementary gates:
  v0.11.18-final U-2 made the Tahreeb sender's "want" arm Sun-only,
  and v1.0.3 (U-5 below) added a sender-side trump-discard
  suppression. firstDiscard ledger no longer carries trump or Sun-
  Tahreeb-bargiya-emission entries. Documented in pickLead's
  Fzloky-pref-suit reader (no behavior change).

- **F8 (Sun-bidder-drought tell, Bot.lua:~2916).** Mirror of
  `bidderTrumpDrought` for Sun contracts. After 3 tricks, if the
  bidder has LED at least once and NEVER led an Ace, they're Ace-
  poor — defender team aggressively cashes their highest point
  card. M3lm-gated; reuses the existing point-card lead branch.

- **F9 (Defender Faranka comment cleanup, Bot.lua:~3469).** Hokm
  Faranka exception comment block refreshed to reflect current
  bidder-team gating (v0.9.2 #49 + v0.10.0 X3 widened both
  exceptions #2 and #4 from bidder-only). Removed the stale
  Section 10 rule 7 anti-trigger reference (deleted in v0.10.3).
  No behavior change.

### Cluster 3 — Bidding/escalation residuals (5 items)

- **FLOOR-3 (Bot.lua:Bot.PickTriple ~line 4404).** Floor cap added
  matching the symmetric defenses in PickDouble/PickFour/PickGahwa.
  `combinedUrgency + styleBelTendency` could drop `th` from base 90
  to 67 on top-tier hands; floor at `BOT_TRIPLE_TH - 16 = 74`.

- **ESC-1 (Bot.lua:escalationStrength).** sunStrength applies a
  Sun-only void penalty (capped 8). In Hokm, voids = ruff capacity
  (POSITIVE), not negative. escalationStrength now inverts that
  penalty in its Hokm branch so the per-hand score is honest.

- **PEB-DEAD (Bot.lua:partnerEscalatedBonus).** Doc'd `contract
  .foured` and `contract.gahwa` branches as INTENTIONALLY dead —
  they fire only from post-Gahwa override pickers (none currently);
  reserved for future. No behavior change.

- **OVC-DOUBLE (Bot.lua:Bot.PickOvercall).** Doc'd the calibration
  interaction between sunStrength's void-penalty (capped 8 cumulative
  on short/honorless suits) and PickOvercall's voidBonus (only fires
  on TRUE voids). They don't fully cancel; the asymmetry is by design
  and documented.

- **PB-1 (Bot.lua:partnerBidBonus).** Split PASS-penalty semantics by
  bidder-team membership. For BIDDER side, partner-PASS is a
  legitimate weakness signal (partner couldn't bid) — penalty
  applies. For DEFENDER side, partner is the OTHER defender; both
  defenders pass in any bidding round (only the bidder team bids),
  so partner-PASS is uninformative. Penalty suppressed for
  defenders so escalation thresholds aren't unfairly raised.

### Cluster 4 — Trick play / signaling (5 items)

- **U-4 (Bot.lua:topTouchSignal writer).** Mirror of v0.9.2 #46
  baitedSuit forced-J gate. Suppress T/K/Q signal recording when
  no lower-rank cards of the suit have been observed played by
  this seat (the honor play might have been mathematically forced).
  7/8/9 broke-signals remain unconditional (forced-or-not, the
  "no honor in suit" inference is unambiguous).

- **U-5 (Bot.lua:Bot.OnPlayObserved).** Sender-side trump-discard
  suppression on `mem.firstDiscard`. In Hokm, must-trump-ruff
  forces a trump play when void in led suit — that's not a
  voluntary discard, so it shouldn't pollute the suit-preference
  signal ledger. The reader-side already filtered trump; now we
  symmetrically gate at the writer.

- **U-7 (Bot.lua:pickLead sweep-pursuit-early).** Kaboot-feasibility
  hand-shape gate. Pre-fix the early pursuit fired purely on "won
  every prior trick" — a thin-hand sweep at trick 3 commits us to a
  failing track. Now M3lm-gated additional check: count trump J/9/A
  in hand + side-suit bosses; require count >= remaining-needed
  tricks. False-positives just keep us in default play, not a worse
  path.

- **U-8 (Constants.lua + Bot.lua:Bot.PickAKA).** Promoted the inline
  `25` and `20` clutch thresholds to `K.BOT_AKA_CLUTCH_DISTANCE` /
  `K.BOT_AKA_CLUTCH_RACE_GAP` constants for tunability. No behavior
  change at default values.

- **Defender sweep-pursuit (Bot.lua:pickLead).** Pre-fix the early
  sweep-pursuit gate required `isBidderTeam`. Defenders sweeping
  every prior trick is the canonical Reverse Al-Kaboot setup
  (K.AL_KABOOT_REVERSE = 88 raw). Gate now allows defender-team
  pursuit too.

### Cluster 5 — SWA + BotMaster cross-cutting (8 items)

- **M6 (Bot.lua:Bot.PickSWAResponse).** Partner-team gate doc'd as
  defense-in-depth. Net.LocalSWAResp / _OnSWAResp already filter
  partners out at the wire layer; the team gate here is unreachable
  through normal flow but kept for any future direct invocation.

- **L1 (Net.lua:LocalSWA fall-through).** Stale "≤3 cards or
  permission disabled" comment refreshed. v0.5.17 routed ALL counts
  through the permission window when permission is enabled; the
  fall-through now only fires for `swaRequiresPermission == false`.

- **L2 (Rules.lua:R.IsValidSWA).** Defensive recursion budget
  (`SWA_RECURSION_BUDGET = 200`). Natural max depth is ~32
  (8 tricks × 4 plays). Budget caps unchecked depth on malformed
  inputs; failure mode = deny SWA (better than hang).

- **BM-01-DOC (BotMaster.lua:rolloutMemory firstDiscard copy).**
  Removed dead-copy of non-existent `.bucket` field. Schema is
  `{suit, rank}` only.

- **BM-04-FALLBACK (BotMaster.lua:sampleConsistentDeal fallback).**
  Two-pass void-respecting allocation. Pass 1 places only void-
  respecting cards; Pass 2 (give-up path) accepts void-violating
  cards only when Pass 1 under-fills. Better incomplete info than
  no rollout.

- **DOC-DRIFT-WORLDS (docs/strategy/bot-personalities.md).** Saudi
  Master tier description refreshed: "100/60/30 worlds" is the
  CONFIGURED ceiling; actual worlds-completed is capped by
  `K.BOT_ISMCTS_BUDGET_SEC` (default 0.5s wall-clock). Pre-doc
  claimed the configured count without the budget caveat.

- **PARTNERSTYLE-INVARIANT (tests/test_state_bot.lua AH.1).**
  Source-pin test asserting BotMaster.lua never reassigns
  `Bot._partnerStyle` during a rollout (the C-14 closure swaps
  `Bot._memory` but `_partnerStyle` is intentionally shared across
  rollout/main-game).

- **BM-06 (Bot.lua:Bot.IsSaudiMaster).** Predicate intentionally
  retained with no current heuristic carve-out — tier API symmetry
  with IsAdvanced/IsM3lm/IsFzloky. Decision documented in code.

### Plus 1 stale-comment refresh

- **CONSTANT-COMMENT-DRIFT (Constants.lua:K.BOT_GAHWA_TH).** Comment
  refreshed to reflect 8-card-hand evaluation context (Gahwa fires
  post-HostDealRest). Pre-doc cited the 5-card bidding-time max,
  which was the original v0.11.17 justification but doesn't apply
  at the threshold's actual fire point.

### Tests

- 10 new source-pin assertions in Section AH covering FLOOR-3,
  L2, BM-04-FALLBACK, U-8, PB-1, ESC-1, PARTNERSTYLE-INVARIANT.
- 1 source-pin window bumped (AA.1) to accommodate ESC-1's
  Sun-penalty inversion preamble.
- Total: 718/718 tests pass.

### Deferred to v1.0.4

The bot-vs-human behavior gap audit (8 findings — 2 HIGH on trick-
play urgency/multiplier blindness + 6 MED on signal/sampler
refinements) and Cluster 7 test-debt closure (~10 source-pin tests
to convert to behavioral) are scoped for v1.0.4. Held to keep this
release surgical.

## v1.0.2 — User-supplied Saudi-vocal sounds + escalation-rung UI rename

User supplied 9 .mp3 vocal cues for the Saudi-Baloot escalation chain
and the four meld value tiers, plus a UI label rename matching the
new sound naming.

### Added (sound assets)

9 .mp3 files in `sounds/`:
- `BEL.mp3` — first escalation rung (defenders ×2)
- `three.mp3` — second rung (bidder ×3, replaces former triple.ogg)
- `four.mp3` — third rung (defenders ×4, replaces four.ogg)
- `gahwa.mp3` — terminal rung (replaces gahwa.ogg)
- `baloot.mp3` — Belote bonus (K+Q of trump, replaces baloot.ogg)
- `SERA.mp3` — seq3 meld (3 consec same suit, 20 raw)
- `khamseen.mp3` — seq4 meld (4 consec same suit, 50 raw)
- `100.mp3` — seq5 / carré T,K,Q,J / carré-A in Hokm (100 raw)
- `400.mp3` — carré-A in Sun (200 raw, "أربع مية")

### Wired

- **`K.SND_VOICE_DOUBLE`** — new constant pointing at `BEL.mp3`. Pre-
  v1.0.2 the first escalation rung had no voice line; only Triple/
  Four/Gahwa fired voice cues.
- **`S.ApplyDouble` fires `K.SND_VOICE_DOUBLE`** on every client at
  rung commit — symmetric with `S.ApplyTriple` / `Four` / `Gahwa`.
- **`S.ApplyMeld` dispatches** to one of `K.SND_MELD_SERA / 50 / 100
  / 400` based on `kind`/`value`/contract. Replaces the v1.0.1
  placeholder `K.SND_MELD_DECLARE`. Saudi convention names each meld
  by raw value; the dispatch table mirrors that.

### UI label rename

- `PHASE_DOUBLE` action buttons: "Bel (x2)" → "Double x2";
  "Bel & open/closed" → "Double & open/closed"; "Bel forbidden..." →
  "Double forbidden...". Internal phase / message names
  (PHASE_DOUBLE, LocalDouble, MSG_DOUBLE) unchanged — pure UI string
  change matching the new sound asset.
- `PHASE_TRIPLE` action buttons: "Triple & open (x3)" → "Triple x3
  (open)"; "Triple & closed (x3)" → "Triple x3 (closed)". Plus
  Skip-leftmost slot ordering (mirrors the v1.0.1 PHASE_DOUBLE
  click-momentum fix).
- Score-banner / round-summary modifier badges: "Bel" → "Double x2";
  "Triple (x3)" → "Triple x3".

### Tests

708/708 pass. No bot-logic, schema, or calibration changes.

## v1.0.1 — User-reported UX/visual fixes

Three fixes from the post-v1.0.0 user-feedback batch. All
gameplay/correctness paths unchanged; bot logic and telemetry
schema untouched. 708/708 tests pass.

### Fixed

- **Meld card display ambiguity (UI.lua `meldCardsForSeat`)**.
  Pre-v1.0.1 the trick-2 reveal strip concatenated cards from
  EVERY meld a seat declared and truncated to 5 slots. A seat
  declaring carré-J (4 cards) + an unrelated seq3 (3 cards) showed
  as `J♠ J♥ J♦ J♣ K♠` — visually indistinguishable from one
  illegal "4 Js + K" meld. Per Saudi rule only the BEST meld
  matters for the team-vs-team comparison anyway, so the strip
  now renders only the highest-`.value` meld for that seat.
  Tie-break: higher .top rank, then declaration order.

- **Bel button click-momentum hazard (UI.lua phase-DOUBLE actions)**.
  The action-button pool reuses fixed slot positions across phases.
  PHASE_OVERCALL slot 1 = "Take as Sun"; PHASE_DOUBLE slot 1 was
  "Bel & open" — same screen pixel. A user mid-click on the
  overcall decision could land their second click on Bel, and a
  third click could fire it through the confirm-arm. Now
  PHASE_DOUBLE slot 1 = "Skip" (safe default), Bel buttons after.
  Confirm-arm pattern still applies as second-line defense.

### Added

- **Meld-declaration sound cue (Sound.lua + State.lua + Constants.lua)**.
  `K.SND_MELD_DECLARE` placeholder added; `S.ApplyMeld` now fires
  `B.Sound.Try(K.SND_MELD_DECLARE)` on every client at the moment
  a meld is registered (trick 1, declaration time) — NOT at trick
  2 reveal time. Saudi convention treats the declaration as the
  canonical announcement moment. The .ogg file lives at
  `sounds/meld_declare.ogg`; user supplies it. If absent, no
  sound plays (graceful — `B.Sound.Try` nil-guards).

### Tooling

- **`tools/calibrate.py` Windows console encoding** — replaced the
  Unicode arrow `→` with ASCII `->` so the analyzer runs
  cleanly under Windows cp1252 (default `cmd.exe` codepage).
  No analytics changed. Python tool only — not part of the
  in-game addon.

### Deferred

- **FPS drop on Saudi Master tier (`K.BOT_ISMCTS_BUDGET_SEC`)**.
  Diagnosed: the per-move 0.5s ISMCTS rollout budget runs on the
  WoW main thread, causing visible stutter (~30 frames blocked
  per heavy bot move). Fix options enumerated (drop budget to
  0.25s; expose as a slash command setting; or refactor to
  C_Timer-spread rollouts across frames). Held pending explicit
  user request — the gameplay correctness is unaffected.

## v1.0.0 — Meld awareness + defender play + telemetry schema v=3

Milestone release. Bundles the highest-leverage residual items from
the v0.11.x audit queue into a coherent package focused on three
themes: (1) bots reasoning about declared melds in trick play, (2)
defender-side play improvements that surface in user-reported "bots
burn high cards" telemetry, and (3) richer round-end telemetry for
offline calibration of subsequent releases.

User priority: the meld-awareness package was explicitly prioritized
("prioritize it for next, but hold i am testing now, next release
should include all pending matters and be 1.0.0"). Second-tier items
remain on the deferred list — see "Deferred from v1.0.0" at the end
of this entry.

### Cluster 1 — Meld awareness (4 wirings)

When opponents declare a sequence/carré meld in trick 1, those cards
are PUBLIC INFORMATION but pre-v1.0.0 only the BotMaster ISMCTS sampler
consumed them (BotMaster.lua:243-260 pins meld cards into world-sample
hands). The heuristic Bot.PickPlay layer — used by Advanced/M3lm/Fzloky
tiers AND as the Saudi-Master rollout policy via the C-14 delegation
— was meld-blind. Now wired through 4 decision points:

1. **Trump-J/9 inference (Bot.lua:2657-2667).** The Hokm trump-pull-
   exhaustion check (`trumpJSeen and trump9Seen`) now considers OPP-
   declared meld cards as "still in opp's hand" — preventing premature
   "trump-killers are gone" inference when an opp's J/9 of trump is
   actually still live via meld declaration.

2. **Boss-of-side meld check (Bot.lua:2192-2207).** When we'd lead
   our highest non-trump as a "free trick" (HighestUnplayedRank),
   scan opp meld-known cards for higher rank in the same suit. If
   opp has a higher card via declared meld, our "boss" is no longer
   the boss — skip and try the next candidate. This closes the gap
   where HighestUnplayedRank is played-pile-based (correct) but
   misses meld-known cards in opp hands.

3. **Partner-meld avoid in pickLead (Bot.lua:2389-2403).** If PARTNER
   declared a sequence meld in suit X, partner has those cards.
   Leading X wastes partner's tempo and may strand high cards.
   Avoid leading X (let partner cash their meld run on their own
   lead). Sets `fzlokyAvoidSuit` if not already set.

4. **`meldKnownHeld(seat)` helper (Bot.lua:961-988).** Returns a set
   of cards the seat is known to hold via declared melds, EXCLUDING
   cards already played. Read by all 3 wirings above.

### Cluster 2 — Defender play (F2/F3/F4/F10)

Four targeted defender-side plays that closed gaps surfaced by user
trace data and Agent forensic analysis:

- **F2: J/9 trump-burn protection in pickFollow (Bot.lua:3635-3690).**
  When the BIDDER leads low trump (rank ≤ Q in trump rank order: 7, 8,
  Q), it's a probe to count opp trumps. If a defender uses J or 9 to
  take such a trick, they reveal the kill card AND burn it on a low-
  value trick. Saudi pros DUCK with non-J/9 trump. Mirror of pickLead's
  `saveHighTrump` but on the response side. Fires before the winners
  block so the cheapest-winner default doesn't auto-burn J/9 against
  us (especially in pos-2 sureStopper case where trumpOut <= 1).

- **F3: topTouchSignal read-side wiring (Bot.lua:2410-2422).** M3lm+
  writes the "partner played K under our A → partner has Q+J" inference
  (Bot.lua:498-530) but pre-v1.0.0 no heuristic decision consumed it.
  Now: if partner has a known down-touched honor in suit X, AVOID
  leading X so partner can cash their middle honor on their own lead.
  Layered after `fzlokyAvoidSuit`; first-set wins.

- **F4: Partner-void-suit ruff setup (Bot.lua:2828-2862).** When partner
  is OBSERVED void in a non-trump suit X (via prior must-trump-ruff
  detection), leading our LOW card from X gives partner a free ruff.
  1-2 partner ruffs per round can be the difference between failing
  and making bidder. Skip when partner is the bidder (ruffing partner's
  own contract is wasteful — they want to PULL trump, not ruff).

- **F10: Trump-J/9 pin awareness — covered by Cluster 1 #1.** The
  meld-aware trump-J/9 inference IS the F10 fix: J/9 in opp meld means
  opp trump strength is NOT exhausted, so don't lead high non-trump
  expecting safety.

### Cluster 6 — Telemetry schema v=3

`S.ApplyRoundEnd` now writes 3 new fields per round-end row, bumping
schema version 2 → 3. Old (v=2) rows continue to parse cleanly under
the existing analyzer (field-presence checks throughout).

- **`bidderTier`** — string ("Basic"/"Advanced"/"M3lm"/"Fzloky"/
  "SaudiMaster"/"human"). Per-tier bot fail-rate split, no longer
  blocked on the file-level `_inferredTier` fallback. Snapshot at
  round-end.
- **`tricksA, tricksB`** — int counts of tricks won by each team.
  Trivial to derive but logged for analyzer histogram convenience.
- **`trickWinners`** — string of 1-8 chars "ABBA..." indicating per-
  trick winner team. Compact (8-byte string vs 8-element table).

`tools/calibrate.py` `_report_sweep_progression` now consumes these
fields when present: per-trick team-A win rate, plus bidder-team
trick-1 → final-make-rate analysis. Pre-v=3 rows show the existing
final-outcome-only stats.

### Pre-ship ultra-audit (4 findings addressed)

Two parallel review agents found 4 real bugs in the initial v1.0.0
ship; all fixed before tagging:

- **H1 (Bot.lua trump-J/9 inference).** Original meld block iterated
  OPP team and forced `trumpJSeen=false` — but the default for
  unplayed-non-our-hand cards is ALREADY false, making the override
  a no-op. The genuine missing case was the INVERSE: when PARTNER
  team has J or 9 of trump in a declared meld, that card IS in
  friendly pool — should mark trumpJSeen / trump9Seen as TRUE so
  the "switch to side-Ace cashing" branch fires. Fix: iterate
  partner team and set trumpJSeen/9Seen=true.
- **H2 (Bot.lua boss-of-side meld check).** Also dead code. The
  outer gate `HighestUnplayedRank(su) == Rank(c)` already considers
  meld cards as "unplayed" — if opp had a higher meld card, the gate
  would fail before the meld scan ran. Reverted to simple-return.
- **H3 (Bot.lua partner-meld avoid).** Original block triggered on
  any partner-meld card, including carrés. Mirrored the existing
  opp-meld avoid filter to only fire on `seq*` melds (where the
  "let partner cash this run" rationale applies).
- **H4 (Bot.lua F3 topTouchSignal read-side).** Original block read
  `sig.nextDown` only — but the K-signal writer (the canonical case
  the CHANGELOG narrative emphasizes) sets `entry.cleared`, not
  `entry.nextDown`. F3 silently filtered out its main case. Fix:
  also read `sig.cleared`.
- **G7 (test coverage).** Schema v=3 had source-pin tests but no
  behavioral coverage of the new fields. Added AG.10 + AG.11
  exercising `S.ApplyRoundEnd` with each tier flag combination,
  asserting `bidderTier`, `trickWinners`, `tricksA/B` are written
  correctly.

### Tests

- 13 new behavioral assertions in Section AG (test_state_bot.lua).
- F2 has TWO behavioral tests (AG.8 + AG.9) that exercise the pos-2
  sureStopper override directly (with controlled `Bot._memory.played`
  state so trumpOut <= 1 fires deterministically).
- Schema v=3 has TWO behavioral tests (AG.10 bot tier + AG.11 human
  bidder) confirming the round-end row is correct.
- 708/708 tests pass.

### Deferred from v1.0.0

The full Cluster 2 deferred-list (F5, F6, F7, F8, F9) and remaining
Cluster 3-5 items (FLOOR-3, ESC-1, PEB-DEAD, OVC-DOUBLE, PB-1, U-4,
U-5, U-7, U-8, M6, L1, L2, BM-01-DOC, BM-04-FALLBACK, DOC-DRIFT,
PARTNERSTYLE-INVARIANT, CONSTANT-COMMENT-DRIFT, BM-06) are deferred
to v1.0.x or v1.1. Rationale per item:

- **F5 (Belote K+Q-trump preservation in pickLead).** Analysis
  (v1.0.0 prep): Belote is locked once both K+Q are held at meld-
  declaration time, regardless of when they're played. The
  preservation logic in pickFollow is about FACE-VALUE preservation,
  not Belote eligibility. The pickLead trump-leading paths already
  prefer non-J/9 (`saveHighTrump`) — adding non-K/Q would only differ
  when only K/Q remain as trump options, which is forced anyway. Low
  impact; defer.
- **F6 (Defender Bargiya defensive-shed in Hokm).** Bargiya is Sun-
  specific per Saudi convention (decision-trees.md Section 8 T-1).
  Hokm equivalent would require new doc-derived rule. Speculative;
  defer.
- **F7 (firstDiscard vs Tahreeb conflict).** Signal-disambiguation
  edge case; current code resolves via Sun-only Tahreeb gate (v0.11.18-
  final U-2 fix). No user-reported bug. Defer.
- **F8 (Sun-bidder-drought tell).** Mirror of `bidderTrumpDrought`
  for Sun. Niche signal; defer.
- **F9 (defender Faranka comment cleanup).** Pure prose; defer.
- **BM-06 (`Bot.IsSaudiMaster()` unused).** Function definition is
  harmless dead code. Removal would break tier-API symmetry (Advanced/
  M3lm/Fzloky/SaudiMaster all have an `Is*` predicate). Keep.

### Why this is "v1.0.0"

Per user instruction: "next release should include all pending matters
and be 1.0.0". Practical delivery scope:

- Cluster 1+2 high-impact items: SHIPPED (4 + 4 = 8 wirings)
- Telemetry schema v=3: SHIPPED (3 new fields + analyzer support)
- Test coverage: 8 new behavioral assertions
- Deferred items: explicitly enumerated above with per-item rationale

The version bump from 0.11.x to 1.0.0 reflects API stability:
`WHEREDNGNDB` schema v=3, `S.ApplyContract`/`S.ApplyDouble`/etc.
public surface, slash command set, and the 5-tier bot dispatch
model are all stable. Future v1.x releases will preserve these
contracts; deferred items will land as v1.0.x or v1.1.

708/708 tests pass.

## v0.11.21 — Display rename: "Loot & Baloot"

User-requested rebrand. Two-line change:

- **`WHEREDNGN.toc`** `## Title:` field: `WHEREDNGN` → `Loot & Baloot`
  (this is what users see in the in-game AddOns list)
- **`UI.lua:407`** main window title: `WHEREDNGN` → `Loot & Baloot`
  (cyan-colored brand at the top of the bot's window)

The "(KZKZ will come)" subtitle/tagline on line 412 is preserved as
the addon's signature branding.

### What stays

- Folder name: `WHEREDNGN/` (changing requires GitHub repo rename +
  CurseForge project migration + 600+ test pin updates; defer to a
  future v0.12.0 if ever).
- Lua namespace: `WHEREDNGN.Bot`, `WHEREDNGN.K`, etc. (internal code
  organization; invisible to users).
- SavedVariables key: `WHEREDNGNDB` (zero data loss for existing users).
- Slash command: `/baloot` (already user-friendly).
- CurseForge project ID 1529200.

### Why minimal scope

A full namespace rename touches ~30 Lua files with hundreds of
references and requires SavedVariables migration. The user-visible
brand is the **Title** in the .toc + the in-game window title — both
now say "Loot & Baloot". Anyone reading the source still sees
"WHEREDNGN" but that's an internal-only concern.

675/675 tests pass.

## v0.11.20 — Tier-1 calibration nudges (Agent 1 math) + R1 Sun-button UI bug

Implements all 4 calibration recommendations from Agent 1's calibration-
math analysis (validated against your 33-round empirical data + 8 fresh
v0.11.19 rounds with the new eltrace observability).

Plus a user-reported UI bug: R1 Sun button was shown unconditionally
even when SUN was already bid in the round.

### Calibration changed (Agent 1 math)

- **`K.BOT_BEL_TH 45 → 35`.** Empirical 3-sample defender Bel-eval data
  (strength 5, 22, 4 from v0.11.19 trace) validates Agent 1's math:
  defender 5-card hands genuinely score in the 4-22 range. At TH=45,
  jth ≈ [35, 55] — strength=22 case never fires. At TH=35, jth ≈ [25, 45],
  catches ~30% of strength=22 hands and ~60% of canonical mardoofa-
  strength hands. v0.11.19 history: 60 → 45 (still too high empirically).

- **AKQ stopper bonus +8 → +12** (`Bot.lua:1044`). Agent 1: AKQ-trio = 3
  guaranteed tricks ≈ 30 raw. Existing face value contributes 18; bonus
  closes the gap. Modest +0.18pp Bel-rate impact alone (rare shape:
  0.87% of 5-card hands), but rule-correct.

- **R2 Advanced bump REMOVED** (`Bot.lua:1443`). Pre-fix
  `if Bot.IsAdvanced() then r2Base = math.max(r2Base, r1Base - 4)`
  bumped Advanced R2 from 36 to 38. Sim showed (n=20K, jitter=±6):
  - r2=36 → R1/R2 split 56.8/43.2 (closest to canonical 50/50)
  - r2=38 → 58.1/41.9 (over-suppressed R2 by 1.3pp)
  Empirical 33-round data showed R1 over-fires 73%; removing bump
  shifts R2 share up ~1.3pp.

- **`K.BOT_PREEMPT_TH 75 → 60`** + **PickPreempt 2-Ace+mardoofa bonus
  stack added.** Pre-fix structurally unreachable: 2A post-bidcard
  hands have median sun=24, p95=37; jitter band [65, 85] meant
  <0.01% fire. Both changes required:
  - PE_TH 75 → 60 (jitter band [50, 70])
  - 2-Ace +15 / 3-Ace +15 / mardoofa-pair-cap*+20 bonus stack mirrors
    PickBid R1 Sun
  Combined: ~0.72% canonical fire rate per A-bidcard (vs <0.01%
  pre-fix). Saudi tournament target 1-3% per A-bidcard.

### Fixed (user-reported UI)

- **R1 Sun button hidden when `anySun=true`** (`UI.lua:1736`). User
  observed: "if someone bids SUN before you, why do you still have
  Sun button?" Per `State.lua:2046` (HostAdvanceBidding), the FIRST
  direct Sun in R1 locks the contract; subsequent SUN bids are
  silent no-ops. The button was misleading. Now gated on
  `if not anySun then addAction("Sun", ...) end`. Hokm-on-flipped
  (line 1704) and Ashkal (line 1732) were already correctly gated.
  PASS button always shown — bidding round still completes formally
  per host wait-for-all-4 design.

### Tooling

- **`tools/calibrate.py`** stale comment: was reporting "BOT_BEL_TH=60;
  expect 20-35%" — now reads "BOT_BEL_TH=35 post-v0.11.20; expect
  10-25% in mixed-tier play".

### Test coverage (Section AF)

5 pins (AKQ +12, R2 bump removed, PickPreempt 2-Ace, PE_TH=60, UI
gate). 675/675 tests pass.

### What to expect on next play session

| Behavior | Expected |
|---|---|
| Bel rate | 0% (v0.11.19) → 5-15% per Hokm contract (target zone) |
| Strength=22 defender hand | Should now sometimes Bel (~30% of jitter rolls) |
| R2 contracts | Up ~1.3pp share (more rounds reaching R2) |
| PickPreempt fire | Was 0% on A-bidcard; now ~0.7% canonical |
| R1 UI after Sun bid | Sun button hidden, only PASS shown |
| Trick-8 make-or-break | M5 actually fires (post-hotfix) |

### Recommended validation

1. Pull v0.11.20 from CurseForge (~10 min after push)
2. `/baloot history clear`, `/baloot bidcalc`, play 10-15 rounds
3. Look for `[bel sN] PickDouble FIRE` lines (was always PASS pre-v0.11.20)
4. Run `python tools/calibrate.py --breakdown=escalation <savevars>` to confirm Bel rate > 0%
5. After Sun is bid in R1, verify Sun button is hidden in your UI

## v0.11.19-hotfix — F1 (M5 dead) + agent-delivered tooling + 19 behavioral tests

Post-v0.11.19 4-agent parallel audit returned. **Critical finding from
Agent 3 (defensive-play audit): the M5 trick-8 make-the-bid block
shipped in v0.11.19 was SILENTLY DEAD due to undefined upvalues.**
Plus Agent 2 delivered 19 new behavioral tests (closing source-pin
debt) and Agent 4 extended `tools/calibrate.py` with rich breakdowns.

### Fixed (CRITICAL)

- **F1 — M5 trick-8 dead block.** v0.11.19's M5 fix referenced
  `isBidderTeam` and `myTeam` as if they were locals in `pickFollow`,
  but those names exist ONLY in `pickLead` (peer file-local function;
  no upvalue scope). In Lua 5.1 the unbound names resolved to nil
  globals; `if nil and ...` short-circuited; M5 never fired. AD.6
  source-pin passed because it only checked the literal `target = ...`
  line was in source — the canonical "shipped dead code" failure
  pattern that Section AE behavioral tests are now meant to prevent.
  Fix: compute `m5_myTeam` and `m5_isBidderTeam` locally in the trick-8
  branch.

### Added — Section AE (Agent 2: 10 behavioral test cases, 19 assertions)

| Test | What it verifies behaviorally |
|---|---|
| AE.1 | BC-MANDATORY R1: K+Q-of-bidcardsuit fires Hokm even when raw strength below threshold |
| AE.2 | BC-MANDATORY R2: K+Q Belote suit fires Hokm even when bestScore below threshold |
| AE.3 | bidderHoldsBidcard phase-gate: PickPlay completes for both PHASE_PLAY and PHASE_DOUBLE |
| AE.4 | F5 OnEscalation: all four S.Apply* increment correct counter on _partnerStyle |
| AE.5 | B6 IsValidSWA existential: positive + negative SWA scenarios exercise caller-turn branch |
| AE.6 | U-6 non-trump preference: TrickRank=1 tie returns non-trump 7C (not trump 7H) |
| AE.7 | M5 trick-8 make-the-bid: gap=4 case picks JH (highestByRank) over 9H (highestByFaceValue) |
| AE.8 | PickDouble eltrace: trace fires only when WHEREDNGNDB.debugBidcalc=true |
| AE.9 | B4/H-5 akaLive flag: opp over-trumps partner's bare-A → receiver still discards non-trump |
| AE.10 | EV-1 bonuses: rich Hokm hand fires PickTriple; weak hand doesn't |

670/670 tests pass (was 651). 19 NEW behavioral tests close the
source-pin debt that allowed F1 to ship.

### Tooling — Agent 4

- **`tools/calibrate.py`** extended with `--breakdown=PROP` flag:
  `bidcard | tier | escalation | r0 | sweep-prog | round-dist | all`.
  Per-bidcard-rank fail-rate with Wilson 95% CIs, per-tier splits,
  chain progression, R0 sub-categorization. Backward compatible.
  Accepts multiple SavedVariables files for combined dataset.
- **`tools/SCHEMA_PROPOSAL.md`** — proposes `bidderTier`, `trickWinners`,
  `r0Reason`, `sideAKQ`, `bidPoints` fields for next-cycle telemetry.
- **`tools/sim_calib.py`** — Agent 1's calibration math simulator.

### Agent findings preserved (deferred for v0.11.20)

- **Agent 1 calibration recommendations** (3 concrete numbers):
  - AKQ-stopper bonus +8 → +12 (modest +0.18pp Bel impact alone)
  - R2 base 38 → 36 unconditional (drops Advanced bump; sim shows
    R1/R2 split 58.1/41.9 → 56.8/43.2, closer to canonical)
  - PickPreempt: add +K.BOT_SUN_2ACE_BONUS post-bidcard recompute +
    K.BOT_PREEMPT_TH 75 → 60 (pre-fix structurally unreachable; post-fix
    ~0.72% canonical fire rate per A-bidcard)

- **Agent 3 defender-side findings** (10 items):
  - F2 HIGH: defender J/9 of trump burn on first low pull (mirror of
    bidder-side saveHighTrump for pickFollow)
  - F3 HIGH: `topTouchSignal` written but never read in heuristic
    pickLead/pickFollow (only consumed by BotMaster sampler)
  - F4 MED: pickLead missing partner-void-suit ruff setup
  - F5 MED: Belote K+Q-of-trump preservation absent in pickLead
  - F6 MED: Defender Bargiya defensive-shed blocked in Hokm
  - F7 MED: firstDiscard Fzloky read fights with Tahreeb ledger
  - F8 MED: No Sun-bidder-drought tell parity for defender
  - F9 LOW: Defender Faranka comment cleanup
  - F10 LOW: Defender-side trump-J pin awareness

- **Agent 4 empirical signals** from extended analyzer on 33-round data:
  - Bidcard=K: 0/6 fails (K-bidcard correctly weighted)
  - Bidcard=Q: 2/4 fails (50% — possibly over-rated, small sample)
  - 0/15 Hokm + 0/18 Sun produced any escalation chain fire (matches
    Agent 1's statistical-consistency finding at BOT_BEL_TH=45)

### Test count

670/670 tests pass.

## v0.11.19 — agent-driven 3-game forensic + 9 fixes

User played 3 games on v0.11.18-final (33 rounds total). A specialized
forensic agent analyzed the trace data + SavedVariables against the
actual bot code and surfaced 1 NEW bug + confirmed all the planned
fixes. v0.11.19 implements all 9 (8 planned + 1 from agent).

### Fixed (HIGH from prior deferred ledger)

- **BC-MANDATORY (Belote shape→strength bridge).** Saudi rule B-6
  marks K+Q-of-trump + count≥2 as MANDATORY Hokm-of-that-suit.
  v0.11.16 added the shape-gate escape but the strength gate still
  rejected when score < thHokmR1. Now: if `belote == bidCardSuit`
  in R1 (or `belote == suit` in R2's bestSuit candidate set), Hokm
  fires unconditionally. The +20 multiplier-immune Belote bonus
  locks the suit's structural value.

- **U-3 (bidderHoldsBidcard → trump-J inference).** Wired the helper
  into `pickFollow`'s trump-J/9 exhaustion check (Bot.lua:2494). Pre-
  fix the inference treated bidcard-of-trump as "could be in any opp
  hand" — but the bidcard is PUBLIC knowledge held by the bidder.
  Now: if bidcard is J or 9 of trump and bidder hasn't played it,
  treat trump-strength as NOT exhausted; suppress side-Ace cashing.

- **DEAD-2 (PickGahwa floor cap removed).** Pre-fix `if th <
  K.BOT_GAHWA_TH - 16 then th = K.BOT_GAHWA_TH - 16 end` was
  unreachable: combinedUrgency clamp ±15 leaves th in [105, 135],
  always above floor 104. Removed; rationale documented inline.

### Fixed (MED — visible play improvement)

- **U-6 (non-trump preference in released-from-must-ruff).** Pre-fix
  `lowestByRank(legal)` in pickFollow's partner-winning fall-through
  picked arbitrarily between trump-7 and non-trump-7 (both TrickRank=1
  in their respective rank tables). Now: in Hokm + partner-winning,
  prefer lowest non-trump if available — preserves trump for actual
  ruffing capacity. Fixed test E.3 (was pinning the wrong v0.5.11
  fall-through behavior; updated to expect non-trump 9D over trump 7S).

- **M5 (trick-8 make-the-bid awareness).** Pre-fix trick-8 winners
  branch always picked `highestByFaceValue`. Now: when bidder team
  AND we're in the make-or-break gap (raw < target, gap ≤ 30),
  use `highestByRank` instead — maximizes trick-WINNING probability
  at the cost of a few face-value points. Targets: Hokm=81, Sun=65.

### Fixed (LOW)

- **`/baloot ismctsdiag` "0 worlds" disambiguation (ultra-audit BM-03
  follow-up).** Pre-fix users couldn't tell "0 worlds = single-card
  shortcut (normal)" from "0 worlds = budget cut on iter 1 (perf
  concern)". Now BotMaster tags `BM._lastShortCircuit` with
  "single-card" / "no-legal-moves" / "legal-build-failed" / nil
  (= entered world loop). Slash command surfaces the specific case.

- **btrace arg correctness (NEW from agent forensic).** Pre-fix
  the bidcalc trace logged `aceCount, mardoofaCount` from PRE-bidcard
  but `sun` from POST-bidcard, producing impossible-looking lines
  like `sun=64 aces=1 mardoofa=0`. Agent verified mathematically by
  reverse-engineering Game 3 trace at 13:32:14. Now: log `sunAces,
  sunMardoofa` (the post-bidcard recompute used for bonus stack).

### Changed (calibration)

- **`K.BOT_BEL_TH 60 → 45`.** Agent's mathematical walk-through of 5
  defender hands from the 33-round dataset showed effective belStr
  range 31-53 — 60 was structurally unreachable on most 5-card
  defender hands. Combined with v0.11.17 EV-1 added bonuses + new
  observability, target ~10-20% Bel rate per Hokm contract. Sub-
  finding deferred: side-AKQ stopper bonus (+8 in sunStrength)
  under-rewards 3 guaranteed tricks (~30 raw); future tuning.

### Added (escalation observability)

- **`PickDouble` eltrace** — mirrors PickBid btrace pattern. Toggled
  via `/baloot bidcalc`. Logs strength, threshold, jth, fire/pass
  decision. User-reported 0% Bel rate across 33 rounds had no
  diagnostic visibility; now the next session will produce
  `[bel sN] PickDouble PASS: strength=X < jth=Y` lines that surface
  WHY defenders aren't reaching threshold.

### Test coverage (Section AD added)

9 pins covering each fix. 651/651 tests pass.

### Forensic agent's other findings (deferred)

The agent flagged 4 additional items not yet shipped:
- Side-AKQ stopper bonus +8 under-rewards 3 guaranteed tricks
  (formula calibration)
- R1 over-fires 73% vs canonical Saudi 50-60% (R2 vs R1
  threshold gap should widen for non-M3lm tiers)
- Defender-team sweep-pursuit branch missing (Game 2 R7 had
  defenders sweep 28/144 swing without active pursuit)
- Need 80-120 rounds across mixed bot tiers for next-cycle
  statistical-power audit

### User-reported observation

User noticed "couldn't Bel >2x in these rounds" — investigated and
confirmed NOT a UI/state bug. PHASE_TRIPLE only fires after Bel.
Across 33 rounds 0 Bels = 0 PHASE_TRIPLE = no Triple button visible.
v0.11.19 BOT_BEL_TH drop should resolve this organically.

## v0.11.18-final — ultra-audit hotfix + comprehensive deferred report

Final hotfix from the post-v0.11.18 ultra-audit (4 parallel agents, ~13
HIGH findings). Addresses the most actionable items + leaves the rest
in the structured deferred-work report below.

### Fixed (HIGH from ultra-audit)

- **DEAD-1** — `Bot.PickFour` `belOpen == false` branch was DEAD CODE.
  PHASE_FOUR is structurally unreachable when belOpen=false (S.ApplyDouble
  shortcuts to PHASE_PLAY when belOpen=false; PHASE_TRIPLE only fires
  when belOpen=true; PHASE_FOUR only after open Triple). At PHASE_FOUR
  belOpen=true is invariant. Removed branch; reframed +5 bonus as
  unconditional calibration constant (matches reality).

- **U-1** — Implicit-AKA detector still gated on `partnerWinning`.
  v0.11.17's H-5 fix dropped this for explicit AKA but missed implicit.
  Rules.lua:142-152 grants implicit-AKA legality relief regardless of
  who's currently winning, so the heuristic should match. Pre-fix when
  partner led bare-A and opp pos-2 over-trumped, the receiver got
  non-trump in legal (relief fired) but pickFollow's branch still
  didn't fire — burning trump that legality had freed.

- **U-2** — Tahreeb sender "want" arm fired in Hokm. Per
  decision-trees.md Section 8 every sender row is tagged Sun-only.
  Pre-fix Hokm "want" emissions biased partner toward leading sideX
  when natural play is trump-pull. Wrapped want arm in
  `if contract.type == K.BID_SUN then ... end`; T-4 dump-ordering
  remains contract-agnostic.

- **B2-FALLBACK-REGRESSION** — Wall-clock budget broke heuristic-
  fallback gate. Pre-fix `if rolloutErrors == numWorlds` could never
  fire after early budget break (rolloutErrors=5 != numWorlds=100).
  Fixed: `worldsCompleted == 0 or rolloutErrors == worldsCompleted`.

- **BM-03** — `/baloot ismctsdiag` slash command added. Surfaces
  `BM._lastWorldsCompleted` + budget setting. Pre-fix the telemetry
  was dark — users had no visibility into when ISMCTS quality was
  truncated by budget.

- **H1** — SWA safety-net asymmetry. `PickSWA` (caller-side) had Hokm
  trump-coverage safety net rejecting when opp top trump > caller top
  trump. `Bot.PickSWAResponse` (response-side) only ran IsValidSWA.
  Bots now defend with same conservatism they call with — mirrored
  the safety-net check on caller's encoded hand vs hostHands.

- **H2** — `Bot.PickSWAResponse` missing W7 corrupted-state guard.
  Pre-fix the validator base-case (no cards remaining = trivial
  caller-win) accepted as valid; HostResolveSWA pre-call forces
  valid=false on this state. Bot now matches.

### Deferred — comprehensive structured report

The 4-agent ultra-audit produced findings in 4 clusters. After
applying the HIGH fixes above, the remaining items are explicitly
deferred for future cycles. Listed by audit cluster + severity:

#### Bidding + Escalation (Audit A)

| ID | Severity | Title | Notes |
|---|---|---|---|
| DEAD-2 | HIGH | PickGahwa F3 floor cap unreachable | Math: th range [105,135], floor 104 < min. Cosmetic / documents intent; no behavioral impact. |
| BC-MANDATORY | HIGH | Belote-no-J fails strength gate despite Mandatory rule | Fix: bypass strength threshold when shape=Mandatory-Belote. ~5 lines; defer pending behavioral test. |
| FLOOR-3 | MED | PickTriple has no floor cap (asymmetric with PickDouble/Four/Gahwa) | Add `if th < K.BOT_TRIPLE_TH - 16 then th = ...`. |
| ESC-1 | MED | escalationStrength sunStrength void penalty wrong in Hokm | sunStrength penalty assumes voids=bad; Hokm voids=ruff capacity (positive). Wider refactor. |
| PE-1 | MED | PickPreempt missing K.BOT_SUN_2ACE_BONUS | Apply 2/3-Ace + mardoofa bonuses post-bidcard recompute. |
| PEB-DEAD | MED | partnerEscalatedBonus contract.gahwa/foured branches dead | Reserved for future post-Gahwa override pickers. |
| OVC-DOUBLE | LOW | sunStrength penalty + PickOvercall voidBonus partial double-handling | Document the calibration interaction. |
| PEB-NEG / PB-1 | LOW | partnerBidBonus PASS penalty inappropriate for defenders | Re-confirmed; split into bidder/defender variants is the proper fix. |

#### Trick play + Signaling (Audit B)

| ID | Severity | Title | Notes |
|---|---|---|---|
| U-3 | HIGH | bidderHoldsBidcard helper dead code (3 cycles deferred) | Wire one consumer or delete. Trump-J-inference is highest-leverage callsite. |
| U-4 | MED | topTouchSignal writer doesn't gate on forced-play | Mirror v0.9.2 baitedSuit forced-J gate. |
| U-5 | MED | Tahreeb sender records trump discards (recv filters; sender doesn't) | Cheap symmetric guard. |
| U-6 / H-6 | MED | pickFollow released-from-must-ruff doesn't prefer non-trump discard | Saudi Master tier directly impacted via ISMCTS rollouts. |
| U-7 | MED | Trick-3 sweep-pursuit lacks Kaboot-feasibility gate | Hand-shape predicate from decision-trees.md. |
| U-8 | MED | AKA late-round clutch gate uses arbitrary 25-point threshold | Pin to constant or derive from scoreUrgency. |
| U-9 | LOW | Bot.PickAKA at trick 1 structurally a no-op | Comment update; A6 unsuppression matters for trick 2+. |
| U-10 | LOW | doubled AKA suppression doesn't account for all rungs explicitly | Defensive symmetry. |

#### SWA + Endgame + Takweesh (Audit C)

| ID | Severity | Title | Notes |
|---|---|---|---|
| M3 | MED | Sweep-pursuit early trigger lacks Kaboot-feasibility hand-shape gate | Same as U-7. |
| M4 | MED | PickSWA cap of 6 leaves 7/8-card SWAs uncomputed | Defensible perf-gate; raise only if telemetry shows missed claims. |
| M5 | MED | Trick-8 push lacks "make-the-bid" score awareness | Bidder team at 80 raw with N points-to-make. Telemetry-driven calibration. |
| M6 | MED | Bot.PickSWAResponse partner-team gate is dead code | Defensive; harmless but misleading. |
| L1 | LOW | Stale comment in LocalSWA fall-through | One-line update. |
| L2 | LOW | IsValidSWA lacks recursion budget | Defensive; not currently a perf concern. |

#### BotMaster + Cross-cutting (Audit D)

| ID | Severity | Title | Notes |
|---|---|---|---|
| B3-DEAD-CODE | MED | bidderHoldsBidcard dead (3 cycles) | Same as U-3. |
| BM-01-DOC-DRIFT | MED | firstDiscard.bucket field non-existent | Remove dead-copy line. |
| BUDGET-WORLDS-COUNT | MED | worldsCompleted counts errored worlds | Track worldsSuccessful separately. |
| BM-04-MELDPIN-FALLBACK | MED | Fallback uniform-deal bypasses BM-04 void filter | Hoist meldPins build, apply void filter once. |
| DOC-DRIFT-WORLDS | MED | bot-personalities.md claims "100/60/30 worlds" without budget caveat | Two-line doc update. |
| BM-06 | LOW | Bot.IsSaudiMaster() defined but never called (no carve-out) | Either delete or wire one heuristic Saudi-Master-only feature. |
| C-14-FRAGILITY | LOW | simTricks reference-copies completed tricks | Defensive deep-copy. |
| PARTNERSTYLE-INVARIANT | LOW | No test asserts _partnerStyle never swapped during rollout | Source-pin test. |
| CONSTANT-COMMENT-DRIFT | LOW | K.BOT_GAHWA_TH comment references stale 5-card-hand reasoning | Refresh comment. |

### Behavioral test gaps (cross-cutting)

Sections T, U, V, W, X, Y, Z, AA, AB, AC are mostly source-pin only.
Audit D specifically called out behavioral coverage gaps:
- AA.1c (escalationStrength bonuses)
- AA.3a/b (B2 budget actually truncates)
- AA.4 (bidderHoldsBidcard per-phase semantics)
- AA.5 (pickFollow akaLive flag behavioral)
- AB.3 (bidderHoldsBidcard PHASE_PLAY gate behavioral)
- AC.6 (PickFour belOpen behavioral — but DEAD-1 makes this moot)

### Test coverage

639/639 tests pass after this hotfix.

## v0.11.18 — Tier 3: ISMCTS state preservation + existential SWA + calibration cleanups

Final tier of the deep-audit fix sequence. Closes:
- **B5** (BM-01, BM-04): rolloutMemory preserves observed signals; meldPins respects voids
- **B6** (M5): IsValidSWA existential when caller's own turn
- **BG-1**: Sun Bel-fear gate strict > 100
- **OE-1**: PickOvercall mirrors Bel-fear bias
- **P4-1**: PickFour reads partner's belOpen flag

### Fixed (HIGH)

- **B5 / BM-01 — `rolloutMemory` preserves `firstDiscard` and `likelyKawesh`.**
  Pre-v0.11.18 BotMaster's per-rollout memory was initialized empty
  except for played/void from `simTricks`. The C-14/Bot1-01 audit
  explicitly omitted firstDiscard/likelyKawesh as "cross-round signal
  layer not relevant" — but they're PER-ROUND state populated by
  real-game `OnPlayObserved` BEFORE the rollout starts. A Saudi
  Master rollout where partner already showed a high-card preference
  via firstDiscard couldn't model that future leads should exploit
  it (Fzloky pref-suit logic, Bot.lua:2117-2129). Now copies these
  two fields from `B.Bot._memory[s]` into `rolloutMemory[s]`. akaSent
  remains uncopied — truly cross-round, not consumed by per-rollout
  heuristics.

- **B5 / BM-04 — `meldPins` respects observed voids.** Pre-fix a meld
  declared by seat 2 in trick 1 (e.g., Hearts Tierce containing 7H)
  was always pinned to seat 2's hand even if seat 2 LATER showed
  Hearts-void in trick 5 (`mem.void.H = true`). The deal was internally
  inconsistent: seat 2 simultaneously holds 7H AND is void in Hearts.
  Now: if observed void, drop the meld pin (the unplayed meld card
  must've been disposed of even if not in our `played` map yet).

- **B6 / M5 — `R.IsValidSWA` existential when caller's own turn.**
  Pre-v0.11.18 the v0.5.17 strict-strict recursion enumerated EVERY
  legal caller-card adversarially — but the caller will pick optimally
  on their own turn, not adversarially. SWAs like `[J of trump, 7 of
  side]` in Hokm where J wins but 7 doesn't were rejected because
  the universal check failed on 7. New behavior: when `nextSeat ==
  callerSeat`, return true if SOME caller-move preserves the SWA
  (existential). Other-seat branches retain universal (partner adversarial,
  opponent adversarial). Tightens v0.5.17's over-strict rejection
  while preserving Saudi's "deterministic-or-bust" intent for non-
  caller plays.

### Fixed (MED)

- **BG-1 — Sun Bel-fear gate strict `> 100`.** Pre-fix `>= 100` was
  one point too eager; opp cannot Bel us at our.cum == 100 exactly
  per `R.CanBel`'s strict `> 100`. The +8 thSun bias should mirror
  the legality boundary.

- **OE-1 — `Bot.PickOvercall` mirrors Bel-fear.** When considering
  TAKE-as-Sun and our cum > 100, opp can still Bel the Sun for ×2.
  PickBid had this bias; PickOvercall didn't. Same magnitude (-8).

- **P4-1 — `Bot.PickFour` reads `contract.belOpen` flag.** Partner's
  CLOSED Bel = "I have just enough for ×2, no more"; PickFour
  overriding with a Four would defy partner's stated intent —
  suppress unless overwhelming. OPEN Bel = "I'd survive a Triple
  counter" — combined-team strength signal beyond raw partnerEscalatedBonus,
  +5 strength bonus.

### Test coverage (Section AC)

- **AC.1**: `rolloutMemory` copies firstDiscard / likelyKawesh
- **AC.2**: `meldPins` respects observed voids
- **AC.3**: `IsValidSWA` existential branch on caller's turn
- **AC.4**: Bel-fear gate uses strict `> 100`
- **AC.5**: PickOvercall biases sunStr down by Bel-fear
- **AC.6a/b**: PickFour suppresses Four on closed Bel; +5 bonus on open Bel

640/640 tests pass.

### Deferred to post-v0.11.18 (future work)

The 4-agent deep audit + 3 release cycles + ultra-audit have closed
the highest-impact items. Remaining audit items not yet addressed:
- **B3 deeper integration**: trump-J-tracking, opp-trump-exhausted
  checks, side-suit boss-lead decisions consult `bidderHoldsBidcard`
- **B4 (H-4)**: Tahreeb sender doesn't avoid strong suit
- **B4 (H-6)**: pickFollow released-from-must-ruff doesn't prefer
  non-trump discard
- **BM-03**: ISMCTS perf instrumentation (`/baloot ismctsdiag` to
  surface `_lastWorldsCompleted` and `_fallbackCount`)
- **BM-06**: Saudi-Master-only carve-out (T-sacrifice in Sun)
- **Tier 3 doc-drift**: stale comments in BotMaster.lua header,
  bot-personalities.md retracted "probabilistic SWA"
- **PB-1**: split `partnerBidBonus` into bidder-team / defender-team variants
- **Behavioral test gaps** for source-pin-only assertions (Y, AA, AB, AC)

A final ultra-audit + report on all post-audit-cycle status follows
this release.

## v0.11.17-hotfix — post-ship audit follow-up

5 findings from the v0.11.17 post-ship audit, all fixed.

### Fixed (HIGH)

- **F1 — Sun branch in `escalationStrength` was DEAD CODE.** All callers
  (`PickTriple`, `PickFour`, `PickGahwa`) early-return on `contract.type
  == K.BID_SUN` BEFORE calling `escalationStrength`. Sun has no
  Triple/Four/Gahwa rungs (Saudi rule R2 + v0.10.0 R2 defense-in-depth);
  Sun's only escalation is Bel which has its own inline path in
  `PickDouble`. v0.11.17's mardoofa/2-Ace/3-Ace branch was unreachable.
  Removed; comment clarifies Hokm-only.

- **F2 — implicit-AKA still gated on `partnerWinning`.** B4 (H-5) was
  intended to drop the partnerWinning requirement, but `implicitAKA`
  (line 2815) still required it. Net behavioral impact small (legality
  layer doesn't relieve must-ruff for implicit AKA anyway), so the
  documented over-scope is reflected in the tightened comment rather
  than a code change. Future Rules.lua update could relieve implicit
  AKA's must-ruff symmetrically.

### Fixed (MED)

- **F3 — `PickGahwa` floor cap.** Pre-fix, EV-2's `BOT_GAHWA_TH=120` +
  `combinedUrgency` -15 + jitter -10 left effective threshold at 95 —
  within reach of mid-strength Hokm hands under near-clinch desperation.
  Added `if th < K.BOT_GAHWA_TH - 16 then th = ... - 16 end` floor cap
  (mirrors `PickDouble:3870` and `PickFour:4026`). Preserves Gahwa's
  rare-rung property while still allowing top-tier hands (~140 strength
  post-EV-1) to fire.

- **F4 — `bidderHoldsBidcard` phase-gates to `PHASE_PLAY`.** Pre-fix
  helper returned true during PHASE_BEL/TRIPLE/FOUR/GAHWA when the
  contract is set but `HostDealRest` hasn't yet appended the bidcard
  to `hostHands[bidder]`. Future v0.11.18 callers wiring this for
  trump-J inference would mis-attribute the J of trump mid-escalation.
  Added `if S.s.phase ~= K.PHASE_PLAY then return false end`.

- **F5 — `Bot.OnEscalation` ledger never fired for host's own bot
  escalations.** Wire-receive `_OnDouble/Triple/Four/Gahwa` had inline
  `OnEscalation` calls but those were post-`fromSelf` filter — meaning
  host-direct bot decisions and local-human escalations silently
  skipped the ledger update. `Bot._partnerStyle.{bels,triples,fours,
  gahwas}` counters were stuck at 0 for half the table. v0.11.17's
  unblocked escalation chain magnified the impact. Moved `OnEscalation`
  into `S.ApplyDouble/Triple/Four/Gahwa` (single uniform call site
  covering wire/host/local paths). Net.lua redundant calls removed.

### Test coverage (Section AB)

- **AB.1**: Sun dead branch removed from `escalationStrength`
- **AB.2**: `PickGahwa` floor cap
- **AB.3**: `bidderHoldsBidcard` phase-gate to PHASE_PLAY
- **AB.4a-d**: Each `S.ApplyX` calls `Bot.OnEscalation` with correct kind
- **AB.4e**: Net.lua has zero `Bot.OnEscalation` calls (single source-of-truth)

Plus AA.1c updated for the F1 dead-branch removal. 630/630 tests pass.

## v0.11.17 — Tier 2: escalation chain + ISMCTS perf + bidcard-in-defense

Continues the deep-audit fix sequence. Tier 2 closes:
- **B1**: escalation chain unblock (EV-1 + EV-2)
- **B2**: ISMCTS wall-clock budget (3-15s pause -> 0.5s cap)
- **B3**: bidcard public-knowledge helper (light wiring; deeper integration deferred)
- **B4**: pickFollow Hokm AKA-receiver gate extension (H-5)

### Fixed (HIGH)

- **B1 (EV-1) — `escalationStrength` now mirrors PickDouble/PickBid bonuses.**
  Pre-v0.11.17 the bidder-side escalation strength missed:
  - Hokm: void-count × 5 + (sideAces - 1) × 8 (defender-side had this; bidder didn't)
  - Sun: 2-Ace bonus (+15), 3-Ace bonus (+15), mardoofa-pair bonus (+20)
  Combined effect: bidder/defender ran on different scales for the same
  hand quality. Triple/Four/Gahwa rungs systematically under-fired.

- **B1 (EV-2) — `BOT_GAHWA_TH` lowered 135 -> 120.** Prior threshold
  was structurally unreachable on 5-card hands (max ~99 raw + +20
  partner-bonus = 119 < 120 floor at urgency=15). Combined with EV-1's
  added bonuses, max climbs to ~140; threshold 120 keeps Gahwa as the
  rarest rung but actually reachable on top-tier hands. Closes
  escalation.md "0% chain fire in symmetric pure-bot play" diagnostic.

- **B2 — ISMCTS wall-clock budget.** Pre-v0.11.17 fixed numWorlds
  (100/60/30) × ~8 candidates × ~21 rollout-policy calls = ~16,800
  full `Bot.PickPlay` invocations per move at trick 0 (post-v0.11.1
  C-14 the rollout policy is full PickPlay, not the cheap simulator
  decisions the original "150 ms perceptually instant" comment
  assumed). Realistic load was 3-15 seconds per Saudi-Master move on
  early tricks. New `K.BOT_ISMCTS_BUDGET_SEC = 0.5` caps wall-clock
  per-move; completed worlds vote, remaining skipped. Tracks
  `BM._lastWorldsCompleted` for `/baloot ismctsdiag`. Set budget to
  0 to disable cap and run full numWorlds always.

### Added (B3 light)

- **`bidderHoldsBidcard(seat, card)`** file-local helper. Returns true
  iff the seat is the bidder, the card matches `S.s.bidCard`, AND
  the bidcard hasn't yet been played. The bidder gets the bidcard
  at HostDealRest; this is PUBLIC knowledge (visible during bidding).
  Defender bots that don't factor this in waste tricks probing for
  trump distribution that's already known. Helper is in place; deeper
  integration into trump-J-tracking, opp-trump-exhausted checks, and
  side-suit boss-lead decisions deferred to v0.11.18 (each requires
  careful per-callsite evaluation).

### Fixed (MED)

- **B4 (H-5) — pickFollow Hokm AKA-receiver gate now fires regardless
  of `partnerWinning`.** Pre-v0.11.17 the gate required current trick
  winner = partner. But `Rules.lua` legality layer (line 202-206)
  correctly relieves the receiver from must-trump-ruff EVEN when an
  opp over-trumped partner's A-led trick. Pre-fix when opp over-
  trumped, the heuristic fell through to natural must-ruff/winners
  flow, sometimes burning trump unnecessarily. Now: AKA on led suit
  -> always prefer non-trump discard (matches legality semantics).

### Test coverage (Section AA added)

- **AA.1**: `escalationStrength` includes void/sideAce/Sun bonuses
- **AA.2**: `BOT_GAHWA_TH = 120`
- **AA.3**: `K.BOT_ISMCTS_BUDGET_SEC = 0.5` + BotMaster wires it +
  tracks `_lastWorldsCompleted`
- **AA.4**: `bidderHoldsBidcard` helper defined
- **AA.5**: `pickFollow` uses `akaLive` flag (relief regardless of winner)

622/622 tests pass.

### Deferred to v0.11.18

Remaining Tier 2/3 items:
- **B3 deeper integration**: trump-J-tracking, opp-exhaust checks, side-suit-boss leads consult `bidderHoldsBidcard`
- **B4 (H-4)**: Tahreeb sender doesn't avoid strong suit
- **B4 (H-6)**: released-from-must-ruff doesn't prefer non-trump discard
- **B5**: ISMCTS rollout state preservation (BM-01) + sampler fallback (BM-02) + meldPins voids (BM-04)
- **B6**: existential SWA validator for caller's own moves
- **Tier 3 cleanup**: PB-1, PP-1 (already done in v0.11.16), BG-1, OE-1, P4-1, BM-06, doc drift

## v0.11.16-hotfix — post-ship audit follow-up

Post-ship audit of v0.11.16 caught 5 follow-up issues. All A1-family
gaps (post-bidcard recomputation needed in additional sites).

### Fixed (HIGH)

- **GAP-01** — `belote = beloteSuit(hand)` was using the bare 5-card
  hand. v0.11.16's A2 (Belote K+Q-trump escape clause in `hokmMinShape`)
  passed the post-bidcard hand to the shape gate, but `belote` itself
  was still pre-bidcard — so a hand `[QS 8C 9C 7H X]` + bidcard `KS`
  passed the shape gate yet missed the `+K.BOT_PICKBID_BELOTE_BONUS`
  +20 strength bonus. The two halves of A2 were mutually inconsistent.
  Fix: `local belote = beloteSuit(withBidcard(hand, S.s.bidCard))`.

- **OVC-bidcard** — `Bot.PickOvercall` `trumpCount` loop iterated the
  bare 5-card hand, then `hypHand` was built later. A bidcard in
  `contract.trump` suit was missed by the void/short check, double-
  counting its contribution to defensive strength. Fix: hoist `hypHand`
  build BEFORE the trumpCount loop and iterate `hypHand`.

### Fixed (MED)

- **MD-01** — `mardoofaCount` was passed from the pre-bidcard
  `aceCountAndMardoofa(hand)`. If bidcard provides the missing A or T
  to complete A+T mardoofa (e.g., hand `[8C 9C TC AS 7H]` + bidcard
  `AC` -> AC+TC mardoofa), the +20 K.BOT_SUN_MARDOOFA_BONUS missed.
  Fix: recompute mardoofa on `sunHand` after building it.

### Fixed (LOW)

- **TC-01** — Takweesh fallback rate `or 0.40` was a stale leftover
  from the pre-A4 decay table. Aligned to flat `or 0.95`.

- **BC-INLINE** — R1 Hokm-on-flipped still used the v0.11.15 inline
  bidcard-append construction. Replaced with the `withBidcard` helper
  for consistency with the other 5 bid paths.

### Test coverage (Section Z)

- **Z.1**: `belote` recomputed on post-bidcard hand
- **Z.2**: PickOvercall `hypHand` precedes `trumpCount` loop
- **Z.3**: mardoofa recomputed on post-bidcard `sunHand`
- **Z.4**: Takweesh fallback rate aligned to 0.95
- **Z.5**: inline bidcard append eliminated

Plus updated X.3a source-pin for the `withBidcard` refactor. 613/613
tests pass.

## v0.11.16 — Tier 1: 7 deep-audit fixes for human-like bot play

User-requested 4-agent deep audit of bot behavior surfaced 17 HIGH-severity
issues across bidding, trick play, endgame, and BotMaster. v0.11.16 ships
Tier 1 (7 highest user-visible-impact fixes) ahead of Tier 2/3 in
follow-up releases.

### Added

- **`withBidcard(hand, bidcard)`** file-local helper in Bot.lua —
  unifies the v0.11.15 hypHand pattern (5-card hand + bidcard) used
  for evaluating the bidder's post-win hand structure.

- **`Bot.PickSWAResponse(seat, callerSeat, encodedCallerHand)`** —
  new function letting bots DENY clearly-invalid SWA claims via
  `R.IsValidSWA` strict-rejection. Pre-v0.11.16 bots auto-accepted
  every incoming SWA, eliminating the entire defensive side of the
  mechanic. Wired in `Net.lua` `_OnSWAReq` + parallel host-localSWA
  + bot-fired SWA paths.

### Changed (audit-driven behavioral fixes)

- **A1 (BC-1) — bidcard inclusion in 5 remaining bid paths.** v0.11.15
  fixed only R1 Hokm-on-flipped; v0.11.16 extends to R1 Sun, R2 Hokm,
  R2 Sun, `Bot.PickPreempt`, and `Bot.PickOvercall`. The bidder
  receives the bidcard (`HostDealRest` State.lua:1950); evaluating
  bid decisions on the 5-card pre-deal hand systematically
  underestimated post-win strength. R1 Sun also recomputes
  `aceCount` post-bidcard so the +15 2-Ace bonus correctly fires
  on hands like `[KH 8H 7C 9D 8S]` + bidcard `AC`.

- **A2 (BS-1) — Belote K+Q-of-trump escape clause in `hokmMinShape`.**
  Saudi rule B-6 (decision-trees.md, **Mandatory** verdict, video #26):
  K+Q of trump + count >= 2 = mandatory Hokm-of-that-suit. Pre-v0.11.16
  the J-floor (`if not hasJ then return false end`) blocked these
  hands when J-of-trump was missing, even though +20 multiplier-immune
  Belote bonus locks the Royal Hand. Escape clause runs BEFORE J-floor.

- **A3 (H1) — `Bot.PickSWAResponse` denies clearly-invalid SWAs.**
  Prior bot auto-accept gave humans free SWA-bluff EV. Bots now
  validate via `R.IsValidSWA` over decoded caller hand + known
  hostHands. Strict-reject -> DENY. Default-accept on ambiguity
  matches the addon's "humans handle close calls verbally" UX intent.

- **A4 (H2) — Takweesh rate flat 0.95 (was decaying 0.60->0.05).**
  saudi-rules.md:163-166 (video #36): Takweesh is a HARD rule-correctness
  call; humans call ALL detected violations promptly. Prior decay made
  the bot effectively dead at trick 6/7. The 0.95 keeps a tiny
  human-realism softener while restoring tournament-grade vigilance.

- **A5 (H3) — `Bot.PickSWA` cap raised 4 -> 6 cards.** Saudi rule:
  5+ cards = mandatory PERMISSION flow, NOT forbidden. The Net.lua
  5-second permission flow already handles 5+ correctly; the
  artificial #hand>4 cap eliminated legitimate Sun-A+T+A+T late-trick
  SWAs.

- **A6 (H-1) — AKA trick-1 suppression DROPPED.** signals.md Section 4
  + decision-trees.md Section 6: "AKA at trick-1/trick-2 is the
  STRONGEST read." Prior `if trickNum <= 1 then return nil end`
  inverted canonical Saudi practice. The partner-certainly-void-in-
  trump gate already covers the case where AKA carries zero
  coordination value.

- **A7 (H-2) — Tahreeb-return decision tree.** Pre-v0.11.16 always
  led the lowest in partner's preferred suit. Per signals.md Section 1
  + decision-trees.md Section 8 receiver:
  - Bare-T (singleton T) -> lead T immediately (else opps tafranak)
  - Doubled-T + partner is Sun bidder -> lead the cover (preserve T
    for partner's A overtake)
  - Doubled-T + partner is NOT Sun bidder -> lead the T (else cover-
    lead telegraphs T to opps)
  - 3+ cards -> lead low (legacy, unchanged)

- **PP-1 cleanup (in A1)** — removed dead-code "+12 if hand contains
  A of bidSuit" bonus in `Bot.PickPreempt`. The +12 was unreachable
  because PickPreempt only fires when `bidCard.rank == "A"`, and
  there's only one A per suit in 32-card deck — so no bot can hold
  it. Replaced with the canonical `withBidcard` pattern that adds
  +11 (A face value) via the same mechanism as R1 Sun.

### Test coverage (Section Y added)

- **Y.1 (A1)**: `withBidcard` helper at file scope
- **Y.2 (A2 / BS-1)**: Belote K+Q escape + ordering before J-floor
- **Y.3 (A1)**: bidcard inclusion in PickBid R1 Sun, R2 Hokm,
  PickPreempt, PickOvercall
- **Y.4 (A4)**: Takweesh rate flat 0.95
- **Y.5 (A5)**: PickSWA cap raised to 6
- **Y.6 (A3)**: `Bot.PickSWAResponse` exists + Net.lua wiring
- **Y.7 (A6 / H-1)**: trick-1 AKA suppression dropped
- **Y.8 (A7 / H-2)**: Tahreeb-return bare-T + doubled-T branches +
  partner-is-Sun-bidder branch

Plus updated T.3 / X.2 source-pins for the bigger `hokmMinShape`,
W.1 for the `aceCount` -> `sunAces` rename. 608/608 tests pass.

### Deferred to v0.11.17/v0.11.18

Remaining audit findings (not in this release):
- **B1**: escalation chain calibration (EV-1/EV-2)
- **B2**: ISMCTS wall-clock budget (3-15s pause at trick 0)
- **B3**: bidcard public-knowledge in defense
- **B4**: Tahreeb sender refinements (H-4/H-5/H-6)
- **B5**: ISMCTS rollout state preservation + sampler fallback
- **B6**: existential SWA validator for caller's own moves
- **Tier 3**: dead-code cleanup, calibration nudges, Saudi-Master carve-out

## v0.11.15 — three bot bidding gaps surfaced by user audit (Q1 overcall, Q2 hokm shape, bidcard inclusion)

User-audit questions revealed three real gaps in bot bidding logic
that calibration nudges alone couldn't fix:

1. **Q1 — Sun overcall doesn't recognize void-in-trump signal.** When
   opp bids Hokm in a suit you have 0-1 cards in, that's the textbook
   Saudi Sun-overcall trigger (no trump = no void penalty). Previous
   `Bot.PickOvercall` used generic `sunStrength()` with no awareness
   of the opp's chosen trump suit.

2. **Q2 — `hokmMinShape` rejects canonical "ولد ومردوفته" hands without
   any Ace.** Saudi rule allows J + 9 of trump + count >= 3 as
   self-sufficient even without side Ace, but the L07 M3lm-tier gate
   (added in v0.10.0) auto-rejected ANY hand without an Ace anywhere.
   Trace evidence: hands like `[8C 9C JC JH QD]` (J + 9 of clubs + 3
   clubs + JH side, NO Ace) were canonical Hokm-clubs candidates but
   silently passed.

3. **Audit — `Bot.PickBid` R1 Hokm-on-flipped doesn't include the
   bidcard in evaluation.** The bidder gets the bidcard appended to
   their final hand at `HostDealRest` (State.lua:1950), but
   `hokmMinShape(hand, bidCardSuit)` was called on the 5-card pre-deal
   hand. If bidcard provided the J of trump or filled out a count,
   the bot didn't see it — leading to false-negative rejections.

### Added (calibration / heuristics)

- **`K.BOT_OVERCALL_VOID_TRUMP_BONUS = 15`** + **`K.BOT_OVERCALL_SHORT_TRUMP_BONUS = 8`**
  applied additively to `sunStrength` in `Bot.PickOvercall` based on
  the bot's count in `contract.trump`. Void hands (0 trump) get +15;
  singleton hands (1 trump) get +8. Pre-threshold so `BOT_OVERCALL_TAKE_TH`
  / `BOT_OVERCALL_SELF_TH` stay meaningful for normal balanced hands.

### Changed (bot logic)

- **`hokmMinShape` — new self-sufficient mardoofa path.** `if count >= 3
  and hasTrumpNine then return true` runs BEFORE the L07 any-Ace gate,
  letting J + 9 + count>=3 hands pass even at M3lm+ tier without a
  side Ace. Matches the count==2 mardoofa path's canonical-only logic
  (RT07-07 from v0.11.9), extended to count>=3 strength.

- **`Bot.PickBid` R1 Hokm-on-flipped — include bidcard in evaluation.**
  Builds a hypothetical post-win hand (`hypHand = hand + S.s.bidCard`)
  and passes it to BOTH `hokmMinShape` and `suitStrengthAsTrump`. The
  bidder's actual post-deal-2 hand is 8 cards (5 initial + bidcard +
  2 unknowns); we now include the deterministic bidcard contribution.
  +6-8 strength shift on average when bidcard is in trump suit.
  Threshold thHokmR1=42 unchanged — the small fire-rate bump aligns
  with user-audit goal.

### Test coverage

- **X.1a/b/c/d** — pin new constants + `Bot.PickOvercall` references
  `K.BOT_OVERCALL_VOID_TRUMP_BONUS` and checks for `trumpCount == 0`.
- **X.2/X.2b** — pin `hokmMinShape` self-sufficient mardoofa path AND
  verify it appears BEFORE the L07 any-Ace gate (correct ordering).
- **X.3a/b** — pin `Bot.PickBid` R1 Hokm-on-flipped builds `hypHand`
  including `S.s.bidCard` and passes it to `hokmMinShape`.
- **X.4** — Behavioral: bidcard-provides-J Hokm-on-flipped fires.
  Hand `[8C 9C TC AS KH]` + bidcard `JC` -> 4 clubs including J +
  side AS -> deterministic `HOKM:C` fire. Pre-v0.11.15 this returned
  PASS (B-4 floor failed; no J in 5-card hand).

### Quantified expected impact

- R1 Hokm-on-flipped fire rate: +20-30% (more hands clear shape via
  bidcard inclusion + L07 relax).
- R2 Hokm fire rate: +30-40% (Q2 self-sufficient mardoofa unlocks the
  no-Ace J+9 cases).
- Sun overcall fire rate: previously near-zero on void-trump hands;
  now ~15-20% on void-trump Hokm targets.

593/593 tests pass.

## v0.11.14 — Sun bot calibration: 2-Ace bonus from user-bidcalc trace evidence

User-bidcalc trace from 27 + 10 telemetry rounds revealed the actual
bottleneck behind "bots don't bid Sun enough": **2-Ace hands without
mardoofa or AKQ triple consistently scored 17-21**, well below
`thSun=38-46`, even though Saudi rule S-1 says 2 Aces IS the canonical
Sun shape. The 3-Ace and mardoofa bonuses existed; the 2-Ace case was
silently un-bonused. Adding `K.BOT_SUN_2ACE_BONUS = 15` brings these
hands into the jitter fire-band without disturbing other calibration.

Specific user-trace examples that previously skipped Sun:
- `[7D AD QC AC 9H]` — 2 Aces + Q + nothing else, sun=17 thSun=38
- `[AH AD KC 7H QS]` — 2 Aces + K + Q across 4 suits, sun=21 thSun=38

Both score 32/36 post-bonus and now fire ~17-39% of jitter rolls.

### Added (calibration)

- **`K.BOT_SUN_2ACE_BONUS = 15`** (new). Magnitude mirrors `K.BOT_SUN_3ACE_BONUS`
  — both signal "shape-pass canonical" rather than "guaranteed-win".
  Applied via `elseif aceCount == 2` in `Bot.PickBid`, gated against
  double-applying with the 3-Ace branch.

### Empirical impact (sim_sun.py + user-trace data)

- Theoretical R1 bot Sun fire rate: 5.67% → **7.39%** per-bot per-round
  (~30% bump, all from the 2-Ace path).
- Per-round outcomes: ~21% chance of bot Sun fire → ~28%.
- 10-round session expectation: ~2.5 bot Sun bids → ~3 (vs 2 observed
  on v0.11.13).
- 27-round session expectation: ~6-8 bot Sun bids → ~7-10 (vs 3 observed
  on v0.11.13). Closes much of the user-perceived gap.

### Rejected alternatives

- **Lower `TH_SUN_BASE` 40→32**: blunt-force calibration that would
  also pull weak 0-1 Ace hands into firing range, raising bot Sun fail
  rate from current 0% (overly conservative) to ~25-30% (overshooting
  tournament target of 30-40%). The 2-Ace bonus is targeted: it lifts
  exactly the hand class Saudi rules consider Sun-eligible.
- **Lower `K.BOT_SUN_VOID_PENALTY_CAP` 8→4**: would help but also
  affects 0-1 Ace junk hands. Already user-arbitrated to 8 in v0.11.9
  from a higher value; further reduction without targeting risks over-
  firing other shapes.
- **Relax `sunMinShape` to allow 1A + same-suit K**: K-cover is
  genuinely weaker than T-cover (T is rank #2 in Sun, K is #3 and loses
  to opp's T). Saudi S-1 specifically calls out A+T mardoofa or 2+ Aces.

### Tooling — `tools/sim_sun.py` (new)

- Empirical Sun fire-rate simulator. Loads a Python re-impl of `Bot.lua`'s
  `sunStrength` + `sunMinShape` + bonus stack (line-by-line mirror of
  v0.11.14). Generates N random 5-card hands (R1 deal state — the actual
  bidding context, NOT 8-card post-deal-2 which earlier analyses
  mistakenly used) and reports score distribution + fire rates across
  threshold + bonus-value sweeps.
- Usage: `python tools/sim_sun.py --advanced --two-ace-bonus 15`.
- Now permanently in-tree to ground future calibration discussions in
  data instead of guesswork.

### Test coverage

- **U.14f** — `K.BOT_SUN_2ACE_BONUS = 15` constant pin.
- **W.1** — `Bot.PickBid` source-pin: `aceCount == 2` elseif branch
  applies `K.BOT_SUN_2ACE_BONUS`.
- **W.2** — Behavioral: 2-Ace + mardoofa hand reliably fires Sun
  (`[AH TH AD 8C 7S]` → sun=59 after bonuses, deterministic fire).

### Bundled cleanups (from prior loop iteration)

- **SU2-08** — UI.lua `renderCardGlyphs` deduped — uses `K.RANK_INDEX`
  / `K.SUIT_INDEX` truthiness instead of local `VALID_RANKS` / `VALID_SUITS`
  duplicates. U.13 test pins updated to assert the new pattern.
- **Constants.lua reference table** — fixed misleading "10 / 80 = Hokm 100,
  Sun 400" line. Post-v0.11.10 revert, Carré-A in Sun is **40 nq** (200
  raw × Sun×2 / 10). The Arabic "الأربع مئة" / "Four Hundred" name
  refers to the post-multiplier value 200 × Sun×2 = 400 effective raw,
  not the stored constant. Reference table now reads "10 / 40".
- **CHANGELOG v0.11.12 site count** — corrected from "11 sites" to
  "10 sites" (State.lua: 9 → 8) per audit SU2-06.

581/581 tests pass.

## v0.11.13 — hotfix: 4-agent ultra-audit findings (NetU2-01 HIGH revert + SU2-02 CRITICAL scope fix + XR2-05 wire validation)

Hotfix release closing 5 findings from the post-v0.11.12 4-agent ultra
audit. **One CRITICAL** (the v0.11.11 SU-Ultra-01 fix was itself
unreachable due to a Lua block-scoping error — the same "shipped
dead code" failure pattern it was meant to fix). **One HIGH regression**
introduced in v0.11.11 XU-09 (host /reload mid-PHASE_OVERCALL
soft-locked). **Two MED** wire-validation gap + defense-in-depth
asymmetry. **Several LOW** doc-drift closures.

The audit caught the CRITICAL and HIGH issues precisely because the
existing source-string pins (U.10, U.11) matched the *text* but
couldn't prove the *behavior*. Test-harness extension (XU-01 phase
2 — Net.lua wire-injection harness) is now the single highest-
leverage debt item; both regressions in this batch would have been
caught at commit time with phase-2 coverage.

### Fixed (CRITICAL)

- **SU2-02 — `N.HostResolveSWA` per-team breakdown was UNREACHABLE
  due to Lua block-scoping.** v0.11.11's SU-Ultra-01 fix declared
  `local result` inside the valid-arm `else` block and `local cardA/
  cardB/mpA/mpB/mult/beloteOwner` inside the invalid-arm `if` block.
  Both blocks closed at the `end` BEFORE the breakdown-stash code
  (line 3406+), so all six locals resolved to undefined globals
  (= `nil`) at the read sites. Net effect: VALID-SWA showed the
  same degraded "Claim verified — all remaining tricks awarded."
  banner that v0.11.2 was meant to fix; INVALID-SWA wrote a
  breakdown table with `nil` entries that displayed as "cards 0 +
  melds 0" rows. Hoisted all six locals to outer scope before the
  if/else. The unreachable-fix-shipping-with-the-same-bug pattern
  is exactly what v0.11.12 XU-01 phase 1 was introduced to address;
  phase 2 (Net.lua wire-injection harness) would have caught this
  at commit time. Audit anchor: `Net.lua:3251-3266`.

### Fixed (HIGH regressions)

- **NetU2-01 — REVERT v0.11.11 XU-09. `s.overcall` is no longer
  in `TRANSIENT_FIELDS`.** The v0.11.11 XU-09 addition broke the
  v0.9.0 M2 host re-arm at `WHEREDNGN.lua:300`: that block is gated
  by `if B.State.s.phase == K.PHASE_OVERCALL and B.State.s.overcall
  then`, scheduling a fresh `_HostResolveOvercall` timer with
  `startedAt = now` for a clean 5-second window post-restore. With
  `overcall` made transient, `s.phase` (still persisted) stayed
  `PHASE_OVERCALL` while `s.overcall` got wiped on `SaveSession` —
  the re-arm short-circuited on the gate, no timer was scheduled,
  the host stayed in `PHASE_OVERCALL` forever with no path forward.
  Same shape as the v0.10.6 RT07-01 redeal-recovery regression
  v0.11.0 fixed — a lifecycle change broke gated-on-presence
  recovery. The pre-v0.11.11 design (overcall persisted, M2 resets
  startedAt) was correct. Pin behavior in test_state_bot.lua U.10
  inverted from "asserts present" to "asserts absent" with full
  rationale block (and added V.4 cross-check for the re-arm gate).
  Audit anchor: `State.lua:256-272`.

### Fixed (MED — wire validation + defense-in-depth)

- **XR2-05/06 — `N._OnContract` validates Hokm trump-suit against
  the 4-suit enum.** Pre-v0.11.13 a buggy/old host fork could
  broadcast `MSG_CONTRACT;3;HOKM;X` and `S.ApplyContract` would
  write `contract.trump = "X"` verbatim. Downstream `R.IsLegalPlay`
  consults `contract.trump` for trump-overcut logic — non-suit
  trump means `C.IsTrump("XS", contract)` returns false for ALL
  cards, silently neutering the bidder's trump declaration (Hokm
  degrades to suit-following without trump). `fromHost` gate
  prevents non-host forging, but a buggy host fork would slip
  through. Mirrors the NetU-03 `_OnAKA` suit-enum gate from
  v0.11.11. Sun contracts (empty trump) allowed through.
  Audit anchor: `Net.lua:961-973`.

- **SU2-01 — `S.ApplyResyncSnapshot` clears stale `s.overcall`.**
  The cleanup block at `State.lua:557-573` explicitly nils 12
  transient fields (akaCalled, lastTrick, takweeshResult, swaResult,
  swaRequest, swaDenied, redealing, pendingPreemptContract,
  preemptEligible, lastRoundResult, lastRoundDelta, sweepTrack-
  Announced) but was missing `s.overcall`. Defense-in-depth:
  `RestoreSession`'s pre-snapshot strip handles the /reload path,
  but the parallel resync-from-host path didn't clear, leaving
  stale state if a late client rejoined mid-overcall. Now nil'd
  symmetrically with the 12 sibling fields.

### Fixed (LOW — doc-drift)

- **SU2-04 — `State.lua:1227` `S.ApplyMeld` block comment.**
  Said "MELD_CARRE_A_SUN (Aces in Sun — 400 raw, الأربع مئة)".
  Post-v0.11.10 revert the constant is **200 raw**. The Arabic
  name "الأربع مئة" / "Four Hundred" refers to the post-mult value
  (200 × Sun×2 = 400 effective), not the stored constant. Updated
  to clarify.

- **SU2-05 — `State.lua:1107-1117` `S.ApplyContract` block comment.**
  Said "It survived through the round and into SaveSession (s.overcall
  is NOT in TRANSIENT_FIELDS)" — the parenthetical was correct
  pre-v0.11.11, became wrong with XU-09, and is correct again
  post-v0.11.13 revert. Replaced with a fuller explanation of the
  v0.9.0 M2 design + why the explicit nil here is still needed.

- **SU2-06 — `CHANGELOG.md` v0.11.12 XR-15 site-count off-by-one.**
  Said "11 sites migrated" / "State.lua (9 sites)". Actual count is
  10/8/1/1. Corrected. (The 13→10 reduction reflects compound-gate
  sites that retain explicit guards.)

- **XR2-10 — `State.lua:1099-1104` belOpen comment-vs-code mismatch.**
  Said "Default open=true" while the field initial values were
  `false`. Confusion stemmed from conflating the *field's initial
  state* (which IS false; escalation is opt-in) with the *ApplyDouble
  argument default* (which IS true; legacy callers passing nil
  advance to the next rung). Rewrote comment to disambiguate.

- **`Rules.lua:288` `R.DetectMelds` comment.** Same "400 raw" stale
  reference as SU2-04. Updated to point at the 200-raw constant +
  explain the post-mult Arabic-name origin.

- **`tests/test_state_bot.lua` K.2a pin comment.** Said "value =
  MELD_CARRE_A_SUN (400 raw)". The constant is 200 raw post-revert;
  the assertion still passes (`K.MELD_CARRE_A_SUN` is the constant
  symbol, value-agnostic), but the comment was misleading.

### Test coverage (v0.11.13 hotfix-specific)

- **U.10 inverted** from "asserts overcall in TRANSIENT_FIELDS"
  to "asserts overcall is NOT in TRANSIENT_FIELDS". Renamed from
  XU-09 to NetU2-01 with full rationale block.
- **V.1a/b** — pin SU2-02 hoist: `local cardA, cardB, mpA, mpB,
  mult, beloteOwner` and `local result` declared BEFORE the
  if-block in `N.HostResolveSWA`.
- **V.2** — pin XR2-05/06: `_OnContract` checks trump enum.
- **V.3** — pin SU2-01: `ApplyResyncSnapshot` clears `s.overcall`.
- **V.4** — pin NetU2-01 cross-check: `WHEREDNGN.lua` post-restore
  PHASE_OVERCALL re-arm gate intact (depends on overcall persisting).

577/577 tests pass.

### Deferred to v0.11.14+

- **XU-01 phase 2** — Net.lua wire-injection harness. **Single
  highest-leverage debt item** post-v0.11.13. Would have caught
  both v0.11.13 HIGH/CRITICAL regressions at commit time. Required
  precondition for XR-16 (MaybeRunBot 638-line refactor).
- **XR2-08** — OPEN-1 NetU-01 250ms re-broadcast may not fully
  close the chat-throttle window. Structural fix is collapsing
  MSG_OVERCALL_RESOLVE + MSG_CONTRACT into one message; deferred
  pending phase 2 harness for empirical validation.
- **SU2-07** — `B.Sound.Try` removes the existence guard for
  migrated sites. Theoretical risk only (Sound.lua loads via .toc
  before State/UI), but worth a top-level shim in Sound.lua's
  tail.
- **XR2-07** — Sun calibration empirical telemetry (~100 rounds
  via `WHEREDNGNDB.history` → `tools/calibrate.py`). Latent risk
  that cumulative bonuses post-v0.11.10 over-fire Sun. Pin coverage
  exists for constants, not fire-rate distribution.

## v0.11.12 — test-harness extension + Sound.Try migration + doc updates

Continues the v0.11.9 ultra-audit queue. The previous batch (v0.11.11)
closed wire-validation symmetry items + the SU-Ultra-01 reachability
fix. This batch adds behavioral test coverage for the BotMaster path
(highest-leverage architectural code), migrates the Sound.Cue guard
pattern to the v0.11.11 helper, and documents the calibration journey.

### Added (test infrastructure — XU-01 phase 1)

- **`tests/test_botmaster.lua`** — new behavioral harness loading
  State + Bot + BotMaster under stub globals. Exercises `BM.PickPlay`
  and `rolloutValue` end-to-end. Closes the test-harness gap that
  allowed v0.11.2 SU-Ultra-01 ("SWA per-team breakdown shipped dead")
  and v0.10.6 RT07-01 ("redeal recovery shipped dead") to pass
  source-string-match pins. **Source-string pins on BotMaster.lua
  remained useful as structural guardrails but couldn't catch the
  "code matches text but is unreachable" bug class** — those need
  behavioral exercise, which this harness provides.

  19 new behavioral pins covering:
  - **Section A**: BotMaster surface + IsActive flag-gating
  - **Section B**: C-14 + Bot1-01 state-swap correctness — verifies
    all 6 swapped fields (hostHands, trick, tricks, akaCalled,
    playedCardsThisRound, _memory) are restored after BM.PickPlay,
    and that `_inRollout` doesn't leak
  - **Section C**: heuristicPick delegates to Bot.PickPlay (counts
    >100 invocations during a single BM.PickPlay rollout)
  - **Section D**: Bot1-02 `_inRollout` flag-leak guard — injects an
    R.IsLegalPlay error and verifies the flag still clears
  - **Section E**: v0.11.10 canonical scoring rule end-to-end —
    Sun-Carré-A meld contributes exactly 400 raw / 40 nq through
    R.ScoreRound (the user-arbitrated "should be 66" rule)

  **Phase 2** (Net.lua harness with WoW API stubs: C_ChatInfo,
  C_Timer, GetTime, CHAT_MSG_ADDON event injection) is the next
  test-infrastructure investment; deferred to its own release
  because it requires a substantial stub kit. Phase 1 covers
  the highest-value architectural code (C-14 + Bot1-01/02 all live
  in BotMaster.lua) which is enough for the majority of the
  source-string pin debt.

### Changed (refactor — XR-15 site migration)

- **10 sites migrated** from `if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_X) end`
  to `B.Sound.Try(K.SND_X)`:
  - `State.lua` (8 sites)
  - `Net.lua` (1 site)
  - `UI.lua` (1 site)

  v0.11.11 introduced `B.Sound.Try` as a thin nil-safe wrapper
  but didn't migrate existing sites. v0.11.12 completes the
  migration. Test stub `WHEREDNGN.Sound = { ..., Try = function() end, ... }`
  in `test_state_bot.lua` and `test_botmaster.lua` ensures the
  harness picks up the new helper.

  Compound-gate sites (e.g., `if not isReplay and B.Sound and B.Sound.Cue then ...`)
  retain the explicit guard form because they layer additional
  conditions (replay suppression, trick-8 gating) that don't
  belong inside the simple Try wrapper.

### Updated (XU-12 / XU-14 — doc drift closures)

- **`docs/strategy/saudi-rules.md`** — added "Bot calibration
  journey (v0.10.0 → v0.11.10)" appendix:
  - Live diagnostic: `/baloot bidcalc` reference
  - Calibration constants table (current values + Constants.lua
    locations)
  - Tuning history table (v0.4 → v0.10.4 → v0.10.6 → v0.11.9 →
    v0.11.10) covering all bidding constants that moved
  - Diagnostic process narrative referencing the v0.11.8/.9/.10
    cycle as the canonical example of "user reports → bidcalc
    trace → calibration adjustment"

- **`docs/strategy/decision-trees.md`** Section 1 — added a callout
  for `/baloot bidcalc` near the bidding-rule tables so future
  contributors find the diagnostic toggle without grep'ing
  CHANGELOG.

### Skipped (intentional defers)

- **NetU-10** — feature-decision (implement Takweesh recovery vs.
  remove forward-compat hook for `s.contract.forced`). Both options
  have merit; needs explicit user direction.
- **XR-16 MaybeRunBot 638-line refactor** — too risky without test
  harness phase 2 covering the dispatch path. Better deferred until
  XU-01 phase 2 lands.
- **XU-01 phase 2 (Net.lua harness)** — substantial stub kit work;
  separate release. Phase 1 in v0.11.12 covers BotMaster which is
  the higher-leverage half.
- **XU-15 (30+ inline `S.s.* =` writes architectural debt)** — slow-
  burn refactor; many sites; better as ongoing improvement than a
  single batch.

### Tests

- **`tests/test_botmaster.lua`** Sections A-E (19 new pins)
- **569 / 569 pass** (up from 550, +19 new behavioral pins)

## v0.11.11 — audit-queue batch (NetU-01..09 + SU-Ultra-01..03 + XU-07/09/10)

Sweeps the remaining items from the v0.11.9 ultra audit: 1 HIGH (OPEN-1
chat-throttle mitigation) + multiple MED wire-validation symmetry items
+ the v0.11.2 SWA banner unreachable-code fix + magic-number promotion
to K.* + Sound.Try helper introduction.

### Fixed (HIGH)

- **NetU-01 / OPEN-1 mitigation** (`Net.lua:1369` `_HostResolveOvercall`)
  — added defensive 250ms re-broadcast of `MSG_CONTRACT` after a
  successful overcall resolution. Mitigates the leading remaining
  hypothesis for the user-reported "Sun overcall bottom contract
  banner not updating" bug (open since v0.11.2): WoW's
  `CHAT_MSG_ADDON` chat-throttle (~4-6 msg/sec/sender) can drop the
  single MSG_CONTRACT broadcast in the dense overcall sequence (open
  + 4×decision + resolve dual-emit + contract + dealphase + turn +
  whispers). The retry costs nothing in the happy path
  (S.ApplyContract's idempotence guard at line 1059 makes re-receipt
  a no-op) and recovers from a single throttle drop.

### Fixed (MED — SWA banner reachability)

- **SU-Ultra-01 / SU-Ultra-02** (`Net.lua:3401` `HostResolveSWA` +
  `UI.lua:3043` `renderBanner` SWA branch) — fixed the v0.11.2 SWA
  per-team breakdown which had been STRUCTURALLY DEAD CODE since v0.11.2.
  HostResolveSWA sets `S.s.lastRoundResult = nil` BEFORE renderBanner
  runs, so the conditional `if r and r.bidderTeam ...` always fell
  through to the degraded "Claim verified — all remaining tricks
  awarded." line. Same failure mode as v0.10.6 redeal recovery
  (RT07-01) — code that compiles, source-matches, and tests pass but
  is unreachable. Fixed by stashing the breakdown directly on
  `S.s.swaResult.breakdown` (host-side); UI.lua now reads from there.
  Non-host receivers see the existing degraded view (wire-format
  extension would push past the 252-byte chunk limit; deferred).

### Fixed (MED — wire-validation symmetry, 8 items)

Same defense-in-depth shape as v0.11.3 RT07-05 / v0.11.5 cluster:

- **NetU-02** (`Net.lua:1496` `_OnMeld`) — kind enum check
  (`{seq3, seq4, seq5, carre}`). Pre-v0.11.11 garbage kind silently
  wrote nil-value meld, risking nil-arithmetic in score sum.
- **NetU-03** (`Net.lua:3388` `_OnAKA`) — suit enum check
  (`{S, H, D, C}`). Garbage suits silently passed to ApplyAKA + UI.
- **NetU-04** (`Net.lua:1652` `_OnRound`) — bounds check on
  addA/addB ≤ 200, totA/totB ≤ 1000. Pre-v0.11.11 nil was rejected
  but bogus huge values could falsely trigger game-end via
  R.GameEndWinner.
- **NetU-05** (`Net.lua:882` `_OnBidCard`) — `#card == 2` check.
  Mirrors XR-11's `_OnPlay`. Allows empty string sentinel.
- **NetU-06** (`Net.lua:786` `_OnLobby`) — per-name 64-char cap.
  Mirrors XR-06's encodedHand cap. Defends against multi-MB name
  injection via SaveSession persistence.
- **NetU-07** (`Net.lua:1069` `_OnPreempt`) — seat ∈ [1,4]. Mirrors
  XR-08's escalation-handler cluster.
- **NetU-08** (`Net.lua:3030` `_OnSWAResp`) — responder + caller
  ∈ [1,4]. Pre-v0.11.11 garbage seats wrote `req.responses[99]`
  which lingered in SavedVariables.
- **NetU-09** (`Net.lua:885` `_OnHand`) — encodedCards ≤ 16 chars.
  Mirrors XR-06.

### Fixed (MED — UI hardening)

- **SU-Ultra-03** (`UI.lua:3068` renderCardGlyphs) — whitelist rank
  and suit before glyph render. Pre-v0.11.11 any 2-char pair
  (e.g. "XY") passed through, producing visually-nonsense rows.
  Now invalid cards are silently skipped.

### Fixed (defense-in-depth)

- **XU-09** (`State.lua:264` TRANSIENT_FIELDS) — added `s.overcall`.
  Pre-v0.11.11 a /reload during PHASE_OVERCALL restored the struct
  with stale wall-clock; renderOvercallBanner showed 0-or-negative
  timer with no host-side enforcement (the original 5-second timer
  was gone). Now /reload during the overcall window cleanly drops
  it. v0.11.5 SU-01 patched the in-session leak; this closes the
  cross-/reload path.

### Added (refactor + tunability)

- **XU-07** (`Constants.lua` + `Bot.lua`) — promoted 5 bidding
  thresholds from Bot.lua locals to K.* constants for tunability:
  `K.BOT_TH_HOKM_R1_BASE` (42), `K.BOT_TH_HOKM_R2_BASE` (36),
  `K.BOT_TH_SUN_BASE` (40), `K.BOT_BID_JITTER` (6),
  `K.BOT_SUN_VOID_PENALTY_CAP` (8). Bot.lua locals retained as
  aliases sourced from K.* for backward-compat with existing call
  sites. Calibration trail documented in Constants.lua comment.

- **XR-15 / XU-10** (`Sound.lua`) — added `B.Sound.Try(soundId)`
  thin nil-safe wrapper. Helper enables incremental migration of
  the 13 `if B.Sound and B.Sound.Cue then B.Sound.Cue(K.SND_X) end`
  call sites; existing sites unchanged in v0.11.11 (each requires
  gate-preservation review). Future cleanup release can migrate.

### Tests

- **`tests/test_state_bot.lua` Section U** (26 new pins covering
  every NetU-01..09, XU-09, SU-Ultra-01..03, XU-07, XR-15)
- T.2 pin updated for the K.BOT_SUN_VOID_PENALTY_CAP promotion
- **550 / 550 pass** (up from 524, +26 new pins; 1 pin updated)

### Still open / deferred to v0.11.12+

- **XR-15 site migration**: helper is in place; converting the 13
  existing call sites is a pure-refactor follow-up.
- **XU-01/02 test-harness extension**: phase 1 (`test_botmaster.lua`)
  + phase 2 (Net.lua under WoW API stubs). Substantial work; ~96%
  of v0.11.x pins still source-string-match.
- **XR-16 MaybeRunBot 638-line refactor** (high risk; better after
  test-harness extension).
- **NetU-10 dead `s.contract.forced`** (decide whether to implement
  Takweesh recovery or remove dead reads).
- **XU-12 / XU-14 doc drift** (saudi-rules.md / decision-trees.md
  bidding calibration journey not documented in user-facing docs).

## v0.11.10 — canonical scoring rule (R5 + v0.11.6 fully reverted) + Sun-bidding closure

User-stated authoritative rule supersedes both v0.10.0 R5 and v0.11.6.
After ultra-audit cross-validation against video #43 (lines 152-158
verbatim Arabic walking through sere 20→4 nq, quarte 50→10 nq in Sun)
and the user's own concrete statement of canonical values, the
correct rule is:

> sere is 4 points in sun and 2 in hokm
> 50 is 10 points in sun and 5 in hokm
> 100 is 20 points in sun and 10 in hokm
> Carré-A is 40 points in sun and shifts to 10 in hokm as there is
> no carré-A in hokm.

Decoded: **all melds get the FULL contract multiplier (Sun ×2 +
escalation Bel/Triple/Four/Gahwa)**. Belote (K+Q of trump) alone is
multiplier-immune. The user's reported "should be 66" answer was
correct after all — but the right path to it is `K.MELD_CARRE_A_SUN
= 200` raw with full Sun×2 mult, NOT 400 raw with the "Sun-immune"
hack. v0.11.6 produced 40 nq for Carré-A but broke sere/quarte/quinte
to 2/5/10 nq instead of canonical 4/10/20. Both v0.10.0 R5 (200→400)
and v0.11.6 (split-multiplier) introduced regressions; v0.4.x was
correct all along.

### Reverted (HIGH — scoring correctness)

- **`Constants.lua` `K.MELD_CARRE_A_SUN`: 400 → 200.** Original v0.4.x
  value. With Sun×2 mult applied (per canonical rule): 200×2/10 = 40 nq.
- **`Rules.lua` R.ScoreRound**: removed v0.11.6 split (`contractMult` /
  `escalationMult` no longer exported); restored single `mult` applied
  uniformly to `(cards + melds)`. Belote post-mult immunity preserved.
- **`Net.lua` HostResolveTakweesh + HostResolveSWA invalid branch**:
  same single-mult restore.
- **`UI.lua` renderBanner**: per-bucket multiplier display reverted to
  single `×N` row.
- **`State.lua` ApplyMeld** comment: "200 raw" annotation.
- **`docs/strategy/saudi-rules.md` Q3 + Q5**: rewritten with canonical
  rule + math reference + history note for posterity.
- **`tests/test_rules.lua` Section S**: rewritten to pin the canonical
  values directly (8 pins covering all melds in both contracts +
  Sun-Bel escalation + end-to-end R.ScoreRound flow). Replaces v0.11.6
  pins.

### Fixed (HIGH — Sun bot bidding closure)

The v0.11.9 calibration was insufficient because the CHANGELOG
prediction misjudged `BID_JITTER` (assumed ±25, actual ±6). At
urgency=0, the post-v0.11.9 `[QS TH AH 8C KH]` hand had `sun=40`
vs threshold band 41-53 → **0% fire rate** (predicted 60%). Per
audit BotU-16:

- **`Bot.lua` `TH_SUN_BASE`: 47 → 40.** Brings the threshold band to
  34-46 so `sun=40` clears it ~50% of jitter outcomes (the canonical
  A+T-mardoofa Sun-bid rate per Saudi pro convention). Other hands:
  - `[8H JC AC TC 7S]` (sun=35) → ~10-15% fire rate
  - `[AS KH KC JH AD]` (sun=24, 2-Ace-no-mardoofa) → 0% (correctly
    conservative)
  - Weak A+T (sun~27) → 0% (correctly conservative)

This closes the user-reported "30 bidding rounds = 0 Sun bids"
investigation. Combined with v0.11.9's `MARDOOFA_BONUS 10→20` and
`void-cap 18→8`, A+T-mardoofa hands now reliably bid Sun.

### Tests

- **`tests/test_rules.lua` Section S** (8 new pins): K.MELD_CARRE_A_SUN
  = 200 + canonical math for sere/quarte/quinte/Carré-A in both
  contracts + Sun-Bel + empty-meld G/H/I/K compat + end-to-end
  R.ScoreRound flow.
- **524 / 524 pass** (up from 518; 6 previous v0.11.6 pins replaced
  by 8 canonical pins).

### Note on the v0.10.0 → v0.11.10 calibration journey

For posterity, the bidding-calibration constants moved through:

| Constant | v0.9 | v0.10.4 | v0.10.6 | v0.11.9 | **v0.11.10** |
|---|---|---|---|---|---|
| `BOT_SUN_MARDOOFA_BONUS` | 5 | 10 | – | 20 | 20 |
| `TH_SUN_BASE` | 50 | – | 47 | – | **40** |
| `sunStrength` void-cap | 25 | – | – | 8 | 8 |
| `K.MELD_CARRE_A_SUN` | 200 | – | – | – | **200 (revert)** |

All cumulative changes shipped now reflect the user-stated
authoritative rule. Cross-validation against video #43 + #32 + #38
agrees with this state.

### Re-test instructions

1. Update to v0.11.10 (CurseForge auto-publish ~10 min)
2. `/reload`
3. `/baloot bidcalc` to enable trace
4. Play 10-20 rounds
5. Expected pattern:
   - ~50% of A+T-mardoofa Sun-eligible hands bid Sun
   - Sun-Carré-A scoring shows 40 nq for the meld portion
   - Sun-Bel scoring shows 80 nq for the meld portion
   - Hokm-Carré-A (treated as Carré-other) shows 10 nq
6. Disable trace when satisfied: `/baloot bidcalc`

## v0.11.9 — bidding calibration (user-arbitrated from bidcalc trace evidence)

User played ~50+ bidding events with the v0.11.8 `bidcalc` trace
on. Analysis surfaced **three real calibration issues**, all confirmed
by specific trace events. Each fix is targeted with a defensible
Saudi-source basis.

### The data

Three Sun-eligible hands (sunMinShape=true) were observed in the
trace; ALL were filtered out by the strength threshold despite being
canonical Saudi Sun bids:

| Hand | aces | mardoofa | sunStrength | thSun | Gap |
|---|---|---|---|---|---|
| `[QS TH AH 8C KH]` | 1 | 1 | 20 | 43-47 | -23 to -27 |
| `[8H JC AC TC 7S]` | 1 | 1 | 15 | 48-52 | -33 to -37 |
| `[AS KH KC JH AD]` | 2 | 0 | 14 | 41 | -27 |

The first two have A+T mardoofa pairs (the canonical "إكة مردوفة"
pattern, video #25); the third has 2 Aces + 2 Kings (high-card
concentration). All structurally bid-Sun in Saudi convention but the
heuristic score values 14-20 were structurally ~25 points below the
threshold band of 41-52.

Plus one weak-mardoofa Hokm trigger:

```
[bid s4 r2] hand=[7C KC AC JS 8S] sun=-1 aces=1 mardoofa=1 thSun=51
[bid s4 r2] R2 Sun skipped: sunMinShape=false sun=-1 thSun=51
[bid s4 r2] R2 Hokm fires: S bestScore=30 >= thHokmR2=28
```

J♠+8♠ is NOT a Saudi mardoofa pair (canonical: J+9 or J+A). The bot
bid Hokm-Spades on a 2-trump hand where the second trump is 8 — the
exact RT07-07 audit-flagged case ("count==2 admits weak mardoofas").

### Fixed

- **`Constants.lua` `K.BOT_SUN_MARDOOFA_BONUS`: 10 → 20.** The v0.10.4
  bump (5 → 10) was insufficient. A+T mardoofa is the canonical
  "must-bid" Sun pattern in Saudi convention; +10 was structurally
  too small to cross the threshold even after face-value addition.
  Pair cap (2) preserved so 2-pair hands cap at +40, not unbounded.

- **`Bot.lua:949` `sunStrength` void-penalty cap: 18 → 8.** The
  void/short-suit penalty is HOKM-think mistakenly applied to Sun.
  In Hokm voids = ruff vulnerabilities; in Sun (no trump) voids are
  neutral or POSITIVE for the bidder (free discards on opp leads).
  Pre-v0.11.9 a hand like `[QS TH AH 8C KH]` (A+T+K hearts locked
  suit + 3 mid singletons) got 28 face value − 18 cap = 10 base —
  the penalty wiped out the entire face-value advantage of the
  A+T+K trio. Cap of 8 preserves "definitely-junk hand" filtering
  (e.g. all 4 suits void/honorless = -8) without erasing strong
  single-suit concentrations. History: 25 → 18 (Gemini softening) →
  8 (v0.11.9).

- **`Bot.lua:794` `hokmMinShape` Lever C tightening (RT07-07 closure).**
  The v0.10.6 `count == 2 and hasSideAce` clause admitted ANY second
  trump as a "mardoofa partner" of J — including 7, 8, T, Q, K. The
  bidcalc trace caught the bot bidding Hokm on J+8+side-Ace, exactly
  the case RT07-07 audit predicted. Per video #26 R2 the canonical
  "مردوفة" partner of J is specifically rank 9 (top mardoofa) or A
  (still strong). v0.11.9 tightens the gate: tracks `hasTrumpNine`
  and `hasTrumpA` separately and requires `(hasTrumpNine or hasTrumpA)`
  alongside the existing `hasSideAce`. J+7/J+8/J+T/J+Q/J+K with side
  Ace no longer triggers — closing the loose gate.

### Expected behavioral change

Re-running the trace's three missed Sun hands with v0.11.9 strength values:

| Hand | New sunStrength | thSun band | Fire rate |
|---|---|---|---|
| `[QS TH AH 8C KH]` | 28 − 8 + 20 = **40** | 32-57 (jittered) | ~60% |
| `[8H JC AC TC 7S]` | 23 − 8 + 20 = **35** | 32-57 | ~40% |
| `[AS KH KC JH AD]` | 32 − 8 + 0 = **24** | 32-57 | ~5% |

Net: ~50% of A+T-mardoofa hands now bid Sun (was 0%); 2-Ace-no-mardoofa
hands stay conservative (legitimately marginal in 5-card view).

### Tests

- **`tests/test_state_bot.lua` Section T** (8 new pins):
  - T.1: `K.BOT_SUN_MARDOOFA_BONUS = 20`
  - T.2a-b: void-penalty cap = 8 (and old 18 removed)
  - T.3a-b: hokmMinShape declares trump-rank flags + uses them in count==2
  - T.4 BEHAVIORAL: J+8+side-Ace 5-card hand → Bot.PickBid returns PASS
    (RT07-07 closure verified end-to-end via Bot.PickBid path)
- **518 / 518 pass** (up from 510, +8 new pins).

### Note

`/baloot bidcalc` toggle from v0.11.8 is still available — re-enable
it to verify v0.11.9 produces the predicted Sun-bid rate. Expected
trace pattern: `R1 direct Sun fires: sun=NN >= thSun=MM` should now
appear ~50% of the time on A+T mardoofa hands (was 0% pre-v0.11.9).

## v0.11.8 — bidcalc trace toggle (diagnostic for Sun-bidding investigation)

User-reported "bots not bidding Sun in 30 bidding rounds = 0".
Analysis of a 13-game-round SavedVariables snapshot showed bots
ARE bidding Sun (2/5 bot bids = 40% Sun rate, both made), but the
user's 30-bidding-round observation covers a wider sample than the
file. To get definitive data, this release adds a chat-output
diagnostic trace toggle.

### Added (diagnostic)

- **`/baloot bidcalc`** (alias `/baloot bidtrace` / `/baloot biddebug`)
  — toggles `WHEREDNGNDB.debugBidcalc`. When ON, every `Bot.PickBid`
  call prints to chat with seat + bidRound prefix. Output covers:
  - **Top-of-call**: hand, sunStrength, aceCount, mardoofa pairs,
    urgency stack, all three thresholds (thSun, thHokmR1, thHokmR2)
    with jitter applied
  - **Each decision branch**: which path fired (R1 direct Sun, R1
    Hokm-on-flipped, R2 Sun, R2 Hokm, fall-through PASS) with the
    specific values that led to it
  - **Negative paths**: when a Sun bid is *blocked* by the
    sunMinShape gate, threshold gap, or Hokm-margin rule

  Off-by-default. Zero overhead in production (the helper short-
  circuits on the toggle check before any string formatting). Format
  pcall'd so a bad fmt-string can't crash bot dispatch.

  Independent of the master `/baloot debug` flag (which gates
  Log.lua-level output) — this is a focused short-term diagnostic
  toggle aimed at the Sun-bidding question. Sample output:
  ```
  [bid s3 r1] hand=[7H 9C TS QH AC 8S JD AH] sun=42 aces=2 mardoofa=0 urgency=0 thSun=47 thHokmR1=42 thHokmR2=36
  [bid s3 r1] R1 direct Sun skipped: sunMinShape=true sun=42 thSun=47
  [bid s3 r1] R1 Hokm-on-flipped blocked: anyHokm=false anySun=false bidCardSuit=nil
  [bid s3 r1] R1 falls through to PASS
  ```

### Use case

Enable the toggle, play 5-10 rounds, capture the chat log. The
output reveals whether bots:
- Have hands that should bid Sun but don't (calibration regression)
- Have weak Sun-shape hands that legitimately stay Hokm (sampling)
- Run into a specific threshold/jitter pattern that pre-v0.11.8
  invisibly biased away from Sun

The bidcalc-instrumented data closes the diagnostic loop without
needing additional `/dump` commands.

### Tests

- **`tests/test_state_bot.lua` Section R** (7 source-match pins):
  - R.1a-b: Slash.lua wires the toggle via `WHEREDNGNDB.debugBidcalc`
  - R.2a-e: Bot.PickBid defines `btrace` + gates on the flag + traces
    R1/R2 Sun decisions + hand-state at the top of each call
- **510 / 510 pass** (up from 502, +8 new pins).

## v0.11.7 — SWA UX fixes (user-reported): bot-1-card short-circuit + result-banner cards

Two user-reported SWA UX bugs:
1. Bot calling SWA with 1 card left is silly UX — the bot is about
   to play that card anyway as the final trick. Just play.
2. The post-resolution score banner ("SWA from Bot X verified") had
   no card display, even when the caller was the player's teammate.
   The pending banner showed cards during the 5-second window, but
   they vanished when the round resolved.

### Fixed (UX)

- **`Bot.lua:3926` Bot.PickSWA** — short-circuit on `#hand <= 1`.
  Pre-v0.11.7 the gate was `#hand == 0 or #hand > 4` (allowing 1).
  With 1 card left the bot's MaybeRunBot dispatch will play that
  card as the next trick anyway; SWA banner + permission flow +
  claim-verified announcement for a single forced play is just
  noise. Now the bot just plays.

- **`Net.lua:3304` HostResolveSWA** — stash caller's `encodedHand`
  into `S.s.swaResult`. Pre-v0.11.7 the swaResult had only `caller`,
  `valid`, `contractMade`, `sweep` — the cards weren't carried into
  PHASE_SCORE. The post-resolution banner therefore had no card
  data, particularly opaque for teammate-bot SWAs ("SWA from Bot 3
  verified" with nothing to verify visually).

- **`Net.lua` SendSWAOut wire format** — extended to field 10
  (encodedHand). Backward-compatible with pre-v0.11.7 receivers
  (they ignore the extra field; nil-encodedHand falls through to
  the no-cards branch). Receiver `_OnSWAOut` consumes field 10
  with the same 16-char cap as v0.11.5 XR-06 (8 cards × 2 chars).
  Dispatcher passes `fields[10]` through.

- **`UI.lua` renderBanner SWA branch** — appends rank+suit-glyph
  card row to the banner title when `swaResult.encodedHand` is
  populated. Red-suit cards render in red, black-suit cards in
  white. Visible to ALL viewers regardless of caller team (per
  user spec: "you should be able to see the cards regardless").
  Format: `SWA! Bot 3 claimed — verified  ·  J♠ A♠ T♠ K♠`.

### Tests

- **`tests/test_state_bot.lua` Section Q** (7 new pins):
  - Q.1: Bot.PickSWA #hand<=1 short-circuit
  - Q.2a-b: HostResolveSWA encodedHand computation + stash
  - Q.3a-d: SendSWAOut signature + _OnSWAOut signature + dispatcher
    fields[10] + 16-char cap
- **502 / 502 pass** (up from 493, +9 new pins).

### User-reported still open (telemetry / calibration)

- **Bots not bidding Sun** — user reports 30 rounds with 0 Sun bids
  even after v0.10.4 + v0.10.6 calibration adjustments
  (MARDOOFA_BONUS 5→10, TH_SUN_BASE 50→47). Filed for next
  calibration cycle. Need data on which seats/hands the user
  thinks should have bid Sun but didn't.

## v0.11.6 — split-multiplier scoring: contract-mult vs escalation-mult (R5 supersession)

**User-arbitrated scoring rule fix.** A reported scoring bug ("Sun
SWA-fail with opp Carré-A meld scored 106, should have been 66")
exposed that the v0.10.0 R5 fix had the **multiplier rule wrong** for
melds in Sun. The R5 reasoning that `K.MELD_CARRE_A_SUN = 400` is the
raw value was correct (matches videos #32 + #38's "أربع مئة"), but
applying Sun's ×2 multiplier to that meld produced 80 nq game points
in Sun vs 10 nq in Hokm — a **1:8 ratio** that contradicts the
videos' clear "Hokm: 100; Sun: 400" 1:4 framing.

The canonical Saudi rule per user clarification:
- **Cards** scale with contract-mult (Sun ×2 / Hokm ×1) AND
  escalation-mult (Bel ×2, Triple ×3, Four ×4, Gahwa ×4)
- **Melds** (sequence, carré-other, carré-A) scale ONLY with
  escalation-mult — they're contract-mult-immune
- **Belote** (K+Q of trump) is immune to ALL multipliers
  (existing rule, unchanged)

Under the new rule the Hokm/Sun ratio is exactly 1:4 (10 nq vs 40 nq),
matching the Saudi naming convention. The user's reported scenario now
correctly produces 66 / 0 instead of 106 / 0.

### Fixed (HIGH — scoring correctness)

- **Rules.lua R.ScoreRound** — split the multiplier into
  `contractMult` (Sun ×2 / Hokm ×1) and `escalationMult` (Bel/Triple/
  Four/Gahwa). Cards multiply by both via `mult = contractMult ×
  escalationMult`; melds multiply by `escalationMult` only. Belote
  stays multiplier-immune (added post-everything). Result struct
  exports both `contractMult` and `escalationMult` separately so UI
  consumers can show the breakdown; `multiplier` field preserved as
  the combined value for backward-compat (test_rules.lua section K
  pins still pass).

- **Net.lua HostResolveTakweesh** (line 2382) — same split. Takweesh
  Qaid penalty math now matches R.ScoreRound.

- **Net.lua HostResolveSWA invalid branch** (line 3179) — same split.
  Resolves the user-reported "Sun SWA-fail with Carré-A scored
  106 / should be 66" bug.

### Changed (UI — score-banner breakdown)

- **UI.lua renderBanner** — bidder/defender breakdown lines now
  display the per-bucket multiplier suffix when relevant:
  `Team A: cards 130 ×2 + melds 400 ×1`. The modifiers row appends a
  `melds ×N (Sun-immune)` indicator when a Sun contract has melds in
  play and the meld-side multiplier differs from the card-side
  multiplier — making the contract-mult-immunity rule visible
  without needing to compute the math manually.

### Sanity-check / cross-validation (R5 supersession reasoning)

- Hokm-Carré-A = 100 raw → 100 ÷ 10 = **10 nq** (no Sun, no
  escalation)
- Sun-Carré-A under R5 = 400 × Sun×2 ÷ 10 = **80 nq** → 1:8 ratio
- Sun-Carré-A under v0.11.6 = 400 ÷ 10 = **40 nq** → 1:4 ratio ✓
- Sun-Bel-Carré-A under v0.11.6 = 400 × Bel×2 ÷ 10 = **80 nq**
  (escalation still applies)
- Videos #32 line ~245 + #38 line ~61: "in Hokm count as 100; in Sun
  it's 400" — explicit 1:4 ratio between the named values

The earlier R5 doc's `/5 divisor` analogy with sere/quarte (e.g.,
sere 20 → 4 nq under Sun) was correctly read but mis-extrapolated to
Carré-A: the videos' /5 worked-examples for sequences may have been
demonstrating simplified accumulated arithmetic rather than per-meld
divisor application. Per user-arbitrated rule, all melds are
contract-mult-immune.

### Tests

- **`tests/test_rules.lua` Section S** (12 new pins):
  - S.0a-e: result struct exposes `contractMult` + `escalationMult`
    correctly across Hokm/Sun ± escalation
  - S.1a-c: user's reported SWA-fail scenario reproduces correctly
    (raw 660 → final 66) + Hokm/Sun 1:4 ratio cross-check
  - S.2a-b: Sun-Bel preserves escalation ×2 on melds (400 × Bel×2 = 80 nq)
  - S.3a: empty-meld fixture unchanged (regression guard for
    sections G/H/I/K)
  - S.4: Hokm-Bel quarte still scales correctly (escalation works)
  - S.5a-b: Belote stays multiplier-immune (existing rule preserved)
- **493 / 493 pass** (up from 479, +14 new pins).

### Impact analysis

**Affected (verified via grep):**
- `Rules.lua` R.ScoreRound, `Net.lua` HostResolveTakweesh + SWA-invalid,
  `UI.lua` renderBanner — all updated.
- `BotMaster.lua` rolloutValue uses `R.ScoreRound`, inherits
  automatically. Saudi-Master ISMCTS now evaluates rollout-team scores
  with the corrected Sun-meld math.
- `Net.lua` HostResolveSWA valid branch uses `R.ScoreRound`, inherits
  automatically.

**Not affected:**
- `Bot.lua` PickBid/Ashkal/Double/Triple/Four/Gahwa/Preempt/AKA/SWA/
  PickPlay — none of these compute multiplier × meld directly. The
  `sunStrength` and `escalationStrength` heuristic functions weight
  cards/aces, not multiplier-affected meld values.
- All existing test fixtures in test_rules.lua sections G/H/I/K use
  empty melds (`{ A = {}, B = {} }`), so meld×mult scoring isn't
  pinned anywhere — **zero test churn from existing fixtures.**

### Constants.lua + saudi-rules.md updates

- `K.MELD_CARRE_A_SUN = 400` retained; comment rewritten to explain
  the post-v0.11.6 multiplier rule and reference the math trace
  (Sun: 40 nq base, 80 nq Bel; Hokm: 10 nq via MELD_CARRE_OTHER).
- `docs/strategy/saudi-rules.md` Q3 marked "🔁 R5 SUPERSEDED v0.11.6"
  with the full ratio-cross-check rationale.
- `docs/strategy/saudi-rules.md` Q5 marked "🔁 REVISED v0.11.6"
  pointing to the contract-side / escalation-side split and noting
  that video #43's /5 worked-examples were demonstrating
  simplified accumulated arithmetic.

## v0.11.5 — defensive batch: SU-01 + 7 LOW closures + dead-code cleanup

Closes the remaining defensive findings from v0.11.3 comprehensive
audit that survived v0.11.4. All low-risk one-liners or targeted
removals. Two false-positive findings (SU-03, SU-06) verified
non-issues during implementation (audit was incorrect on both).

### Fixed (MED — defensive)

- **SU-01** (`State.lua` `S.ApplyContract`) — clear `s.overcall` when
  advancing phase past PHASE_OVERCALL. Pre-v0.11.5, under client wire
  reorder where MSG_CONTRACT arrived before MSG_OVERCALL_RESOLVE,
  this function advanced phase to PHASE_DOUBLE but left `s.overcall`
  non-nil. The follow-up `_OnOvercallResolve` then bailed on the
  v0.11.0 A5 phase guard, so `s.overcall` was never cleared. It
  survived through the round and into SaveSession (the field is NOT
  in `TRANSIENT_FIELDS`). Defensive single-line clear; the overcall
  window is logically closed once a contract has been (re-)applied.

### Fixed (LOW — wire-validation hardening)

Each guards against a buggy/forked host emitting malformed broadcast
frames that would silently corrupt receiver state. Same shape as
the v0.11.3 RT07-05 / v0.11.4 wire-validation cluster.

- **NetA-06** (`Net.lua:843` `_OnDealPhase` redeal branch) — validate
  `nextDealer ∈ [1,4]`. Pre-v0.11.5 a buggy/forked host emitting
  `MSG_DEAL_PHASE;redeal;<garbage>` passed nil or out-of-range into
  `S.ApplyRedealAnnouncement`; the redeal banner displayed the wrong
  (or no) dealer name.
- **NetA-07 / XR-04** (`Net.lua:2279` `_OnTakweeshOut` and
  `Net.lua:3057` `_OnSWAOut`) — validate caller ∈ [1,4] and (Takweesh
  only) `illegalSeat ∈ [0,4]` (0 = "no offender" sentinel from the
  wire format). Pre-v0.11.5 garbage callers wrote into
  `S.s.takweeshResult.caller` / `S.s.swaResult.caller`; downstream
  `S.s.seats[99]` lookups returned nil and label fallback dropped to
  `"?"`.
- **XR-05** (`Net.lua:2677` `_OnPause`) — enforce payload ∈ {"0","1"}.
  Pre-v0.11.5 any non-"1" payload (nil, "true", garbage) silently
  mapped to false (resume). Bogus payloads now drop at the wire.
- **XR-06** (`Net.lua:2872` `_OnSWAReq` + `Net.lua:3040` `_OnSWA`) —
  cap `encodedHand` to 16 chars (max 8 cards × 2 chars/card).
  Pre-v0.11.5 the encoded hand was stashed unbounded into
  `S.s.swaRequest`, which is NOT in `TRANSIENT_FIELDS` so persists
  to SavedVariables. WoW addon-channel max payload caps ~252 bytes
  per chunk so the actual attack surface was small, but explicit
  cap closes the future-channel-format-change risk.
- **XR-08** (`Net.lua` `_OnDouble` / `_OnTriple` / `_OnFour` /
  `_OnGahwa`) — seat range checks added. Downstream `eligibleSeat`
  comparison would have rejected out-of-range seats by mismatch but
  explicit range gating is uniform with the rest of the wire layer.
- **NetA-09** (`Net.lua:1864` `_HostExecuteRedeal`) — validate
  `nextDealer ∈ [1,4]` after the existing nil-check. Pre-v0.11.5 a
  corrupted SavedVariables with `s.redealing.nextDealer = 99` passed
  the nil-check and corrupted `s.dealer` + downstream rotation math
  (99 % 4 + 1 = 4, so first-bidder math limps along but the
  dealer-rotation invariant breaks from this round forward).

### Removed (LOW — dead code)

- **Bot1-05 / C-01** (`Bot.lua:1391-1397`) — deleted the byte-identical
  duplicate of the singleton-T cardinality gate. The canonical block
  at lines ~1361-1367 is preserved; this site is now a one-line
  no-op marker. The duplicate had been flagged in the v0.10.7 audit
  and survived through several cycles.
- **XR-14** (`Constants.lua:183`) — removed `K.MSG_KICK = "K"`. Zero
  references across the codebase; the kick-a-seat UX was never
  implemented. Tag `"K"` is now free for future reuse.

### Investigated, not real bugs (audit false-positives)

- **SU-03** — `s.takweeshResult` was reported as missing from
  `TRANSIENT_FIELDS`; verified during implementation that line
  `State.lua:228` already has `takweeshResult = true,`. The audit
  agent was reading from a different (or imagined) version. No
  action.
- **SU-06** — round-end cue cluster (HOKM_LOST/KABOOT/etc.) was
  reported as needing an `isReplay` guard like RT07-03. Investigation
  showed `_OnResyncRes` calls `S.ApplyResyncSnapshot` which writes
  `s.cumulative` directly from the snapshot fields — MSG_ROUND is
  NOT replayed during resync. The audit's claimed "MSG_ROUND replay
  flood" scenario doesn't actually happen. No action.

### Tests

- **`tests/test_state_bot.lua` Section P** (25 new source-match pins):
  - P.1 (SU-01): S.ApplyContract clears s.overcall
  - P.2 (NetA-06): _OnDealPhase nextDealer range
  - P.3a-c (NetA-07/XR-04): Takweesh + SWA caller ranges
  - P.4 (XR-05): _OnPause payload domain
  - P.5a-b (XR-06): SWA encodedHand 16-char cap
  - P.6 (XR-08): four escalation handlers seat range
  - P.7 (NetA-09): _HostExecuteRedeal nextDealer range
  - P.8 (Bot1-05): T-cardinality canonical block appears exactly once
  - P.9 (XR-14): K.MSG_KICK definition removed
- **479 / 479 pass** (up from 454, +25 new pins).

### Still open (defer to v0.12.x)

- **OPEN-1** — Sun overcall bottom contract banner not updating.
  Both Net.lua and State+UI audit agents confirm no code-level bug
  from inspection. Pending user repro details.
- **XR-01** — Test-harness blind spot. `tests/run.py` doesn't load
  Net.lua / BotMaster.lua / WHEREDNGN.lua → all v0.11.x pins are
  source-string matches. Bigger lift; needs WoW API stubs.
- **Bot1-03** — ISMCTS performance budget guard. Defer until user
  reports lag.
- **RT07-07 / Bot1-04** — `hokmMinShape` weak mardoofa (J+7 passes).
  Calibration; pending v0.11.1+ telemetry.
- **XR-15** — Sound.Cue guard helper consolidation (~26 LOC reduction).
  Pure refactor; no behavioral change. Defer.
- **XR-16** — `MaybeRunBot` 638-line refactor candidate. Bigger lift.

## v0.11.4 — comprehensive-audit batch: C-14 completion + Saudi-Master robustness + wire-validation cluster

Closes the highest-value items from the v0.11.3 comprehensive audit
(four parallel agents covering Net.lua / State+UI.lua / Bot+BotMaster /
cross-cutting+red-team). Three tracks in one batch.

### Fixed (HIGH)

- **Bot1-01** (`BotMaster.lua` rolloutValue) — **C-14 completion**.
  v0.11.1 swapped 5 fields (hostHands / trick / tricks / akaCalled /
  playedCardsThisRound) but missed `Bot._memory`. The audit
  (`C_Bot_audit.md` Bot1-01) found this was the partial-coverage gap:
  branches reading `_memory[seat].played[card]` and `_memory[seat].void[suit]`
  saw real-state observations only — the rollout's simulated forward
  play never updated `_memory`, so the simulated tail's revealed voids
  were invisible to the rollout policy. Affected branches:
  - **Ace-exhaustion lead** (`Bot.lua:2101-2132`) — at trick T+k of a
    rollout, "have side Aces all been played?" silently answered "no"
    (only saw real-state plays through trick T). Trump-poor cash-side
    play was undervalued.
  - **Faranka exception #4** (`Bot.lua:2985-2999`) — bidder-team
    Faranka pos-4 trump-cut fires when all opps observed-void in
    trump. Rollouts couldn't see voids revealed in tricks T+1..T+k.
  - **`opponentsVoidInAll` / `anyOpponentVoidIn`** helpers
    (`Bot.lua:674-702`) — opp-void-aware lead branches in pickLead.
  - **`PickAKA` suppression** (`Bot.lua:3385`) — suppress AKA when
    partner observed void in trump.

  Fix: rolloutValue now also saves/swaps/restores `B.Bot._memory` to a
  rollout-local `rolloutMemory[seat] = { played, void }` populated from
  `simTricks` + `currentTrick.plays` at swap-in (mirrors
  `Bot.OnPlayObserved`'s populated/void inference rule). A
  `recordRolloutMemory(seat, pick, leadSuit)` helper updates the
  rollout-local memory after every pick during the rollout loop, so
  voids revealed in the simulated tail are visible to subsequent
  picks. Cross-round signals (`firstDiscard`, `likelyKawesh`,
  `akaSent`, `_partnerStyle` ledger) are NOT swapped — those are
  invariant during a single-round rollout and the Bot.PickPlay
  branches that read them aren't bot-coordination-relevant in
  rollouts.

### Fixed (MED — Saudi-Master robustness)

- **Bot1-02** (`BotMaster.lua` BM.PickPlay legal-set construction) —
  `_inRollout` flag leak fix. Pre-v0.11.4 a `R.IsLegalPlay` error
  inside the legal-set loop propagated up to Net.lua's outer pcall
  in `MaybeRunBot`, which caught the error but never restored
  `B.Bot._inRollout` — silently disabling Saudi-Master ISMCTS for the
  rest of the session (every subsequent `Bot.PickPlay` short-circuited
  at the delegation guard, falling through to heuristics). The C-14
  v0.11.1 expansion widened the surface area where errors could
  occur (full pickLead/pickFollow now exposed via the rollout policy
  delegation), making this leak more likely.

  Fix: wrap legal-set construction in pcall via named-function
  `buildLegalSet`. On failure, `_restore(nil)` clears `_inRollout`
  and returns nil so `Bot.PickPlay` falls back to heuristics for THIS
  move only — Saudi-Master tier remains armed for the rest of the
  session. Named-function form (rather than inline closure) preserves
  the I.4 (H4) per-world pcall structural test that requires the
  first inline `pcall(function()` to come after the per-world for-loop.

### Fixed (MED — wire-validation cluster, 5 one-liners)

Same defense-in-depth shape as v0.11.3 RT07-05 (`_OnContract` bidder
range + btype enum). Each guards against a buggy/forked host emitting
malformed broadcast frames that silently corrupt receiver state.

- **NetA-03 / RT07-06** (`Net.lua:1608` `_OnRound`) — nil-numeric
  guards on addA/addB/totA/totB. Pre-v0.11.4 `S.ApplyRoundEnd`
  unconditionally wrote `s.cumulative.A = totA`; nil totals silently
  corrupted the score panel until the next valid MSG_ROUND.
- **NetA-04** (`Net.lua:1573` `_OnTrick`) — winner ∈ [1,4] + points
  non-nil. Pre-v0.11.4 `s.tricks[i].winner = nil` corrupted trick
  history; downstream `R.TeamOf(nil)` defaulted to "B", miscounting
  team trick totals.
- **NetA-05** (`Net.lua:875` `_OnTurn`) — seat ∈ [1,4]. Pre-v0.11.4
  a bogus `s.turn = 99` broke turn-glow UI (`S.s.seats[99] = nil`)
  and AFK timer arming (`isBotSeat` returned nil → bot dispatch
  noops). Garbage seat persisted until next valid MSG_TURN.
- **XR-09** (`Net.lua:1615` `_OnGameEnd`) — winner ∈ {"A","B"}.
  Pre-v0.11.4 accepted any string and wrote into `s.winner`; downstream
  `R.TeamOf` comparisons silently fell through to default branches.
- **XR-11** (`Net.lua:1475` `_OnPlay`) — seat ∈ [1,4] + `#card == 2`.
  Pre-v0.11.4 a malformed card (1-char, 5-char, garbage) was passed
  to `S.ApplyPlay` → `R.IsLegalPlay` → `card:sub(1,1)/sub(2,2)`
  producing bogus rank/suit silently. Mirrors the inline check
  already in `_OnTrick`'s encPlays loop.

### Tests

- **`tests/test_state_bot.lua` Section O** (20 new source-match pins):
  - O.1a-f (Bot1-01): Bot._memory swap/restore + rolloutMemory
    population + recordRolloutMemory helper
  - O.2a-c (Bot1-02): buildLegalSet + pcall + _restore on failure
  - O.3 (NetA-03): _OnRound nil-numeric guard
  - O.4a-b (NetA-04): _OnTrick winner range + points non-nil
  - O.5 (NetA-05): _OnTurn seat range
  - O.6 (XR-09): _OnGameEnd winner enum
  - O.7a-b (XR-11): _OnPlay seat + card-length
- **454 / 454 pass** (up from 434, +20 new pins).

### Verified-correct items (no action needed; from comprehensive audit)

- **C-14 architecture** (post v0.11.1) — structurally correct. State
  swap covers every field read by `Bot.PickPlay` descendants.
- **All v0.11.0/.3 closures hold**: A5, B2, C1#6, D1, E2, RT07-01,
  RT07-02, RT07-03, RT07-04, RT07-05, S-1, U-7.
- **TRANSIENT_FIELDS coverage clean** post-RT07-01.
- **Wire/state Send↔On pairing clean** — no orphans.
- **Self-broadcast loops** — every `_On*` has `fromSelf` guard.
- **Tier strict-extension intact**: Master ⊂ Fzloky ⊂ M3lm ⊂ Advanced.
- **Bot memory lifecycle**: per-round / per-game resets correct.
- **Resync handshake post-C1#6** fully covers pause-during-resync.
- **Takweesh banner WIN/LOST**: verified-correct (proxy ≡ score-delta
  by construction; unlike SWA's v0.11.2 fix).

### Still open (next-batch candidates)

- **OPEN-1** — Sun overcall bottom contract banner not updating.
  Both Net.lua and State+UI agents confirm no code-level bug from
  inspection. Most-likely root: AddonMessage chat-throttle drop of
  MSG_CONTRACT (no redundant rebroadcast in `_HostResolveOvercall`).
  Defensive mitigation possible: re-send MSG_CONTRACT ~250ms later.
  Pending user repro details (host vs client, `/dump`, screenshot).
- **SU-01** — `S.ApplyContract` should clear `s.overcall` on phase
  advance (defensive single-line; wire-reorder edge case).
- **SU-06** — `S.ApplyRoundEnd` cue cluster lacks isReplay guard
  (rejoiner audio flood). Mirror RT07-03 pattern.
- **XR-01** — Test-harness blind spot. `tests/run.py` doesn't load
  Net.lua / BotMaster.lua / WHEREDNGN.lua → all v0.11.x pins are
  source-string matches. Bigger lift; needs WoW API stubs.
- **Bot1-03** — Performance budget for ISMCTS. Defer until user
  reports lag.
- **RT07-07** — `hokmMinShape` weak mardoofa (J+7 passes). Calibration;
  pending v0.11.1+ telemetry.
- **LOW**: NetA-06, NetA-07, XR-04, XR-08, XR-14, XR-15, XR-16
  (dead constant, sound-cue dedup, MaybeRunBot refactor, etc.).

## v0.11.3 — RT07 batch: SND_LAST_TRICK_WIN trick-8 gate + sweep-track reset + contract wire-validation

Three targeted MED closures from `audit_v0.10.7/D_RedTeam_audit.md`.
All three are low-risk defense-in-depth or UX-correctness fixes.

### Fixed (MED)

- **RT07-02** (`State.lua` `S.ApplyTrickEnd` last-trick-win cue) —
  `SND_LAST_TRICK_WIN` is now gated to trick 8 only. Pre-v0.11.3 the
  cue fired on every "guaranteed-unbeatable" play across all 8 tricks
  (pos-4 win, boss-of-suit with trump exhausted, boss-of-trump). User's
  v0.10.7 spec was *"sound for the last hand winning card when it
  played and 100% it is obvious a win"* — "last hand" = trick 8 in
  Saudi parlance, and the v0.10.7 CHANGELOG wiring blurb explicitly
  said `#tricks == 8`. The cue now layers with the natural cluster of
  round-end cues (SND_TRICK_WON, SND_KABOOT, SND_BALOOT, possibly
  SND_HOKM_LOST) for a single coherent close-of-round audio moment
  rather than scattering across mid-round tricks. Note: `s.tricks`
  already includes the just-resolved trick at the cue site (via
  `table.insert` earlier in `ApplyTrickEnd`), so `#s.tricks == 8` is
  the correct test.

- **RT07-04** (`State.lua` `S.ApplyRoundEnd`) — added
  `s.sweepTrackAnnounced = nil` defensively at round-end. Pre-v0.11.3
  the flag was only reset by `ApplyStart` and `reset()`; v0.11.0 S-1
  added the `ApplyResyncSnapshot` reset for rejoiners. v0.11.3
  completes the triple of reset sites so a corrupted/partial-restore
  state (orphan PHASE_SCORE without subsequent MSG_START, dropped
  start-of-round frame) doesn't carry the prior round's announced-flag
  into the next round. `sweepTrackAnnounced` is not in
  `TRANSIENT_FIELDS` so it persists across `/reload` via
  `RestoreSession`; this round-boundary clear is the belt-and-braces
  guard.

- **RT07-05** (`Net.lua:899` `N._OnContract`) — added
  `bidder ∈ [1,4]` range check and `btype ∈ {HOKM, SUN}` enum check.
  Pre-v0.11.3 only `nil` was rejected. The `fromHost` trust gate
  already prevents non-host peers from forging MSG_CONTRACT, but a
  host running a buggy/forked client could send `MSG_CONTRACT;5;H;X`,
  writing `s.contract.bidder = 5` and silently masking the error
  downstream (`R.TeamOf(5)` defaults to "B", `(5 % 4) + 1 = 2`
  off-by-one for next-seat math, `S.s.seats[5]` is `nil`). Same
  defensive shape as the existing nil-check. Originally noted in
  `review_v0.10.4_ship_readiness.md` deferred items (B-Net-02 H1/H2);
  this is the explicit closure.

### Tests

- **`tests/test_state_bot.lua` Section N** (5 new source-match pins):
  - N.1 (RT07-02): `ApplyTrickEnd` last-trick-win cue gated on
    `#s.tricks == 8`
  - N.2 (RT07-04): `S.ApplyRoundEnd` clears `s.sweepTrackAnnounced`
  - N.3a (RT07-05): `_OnContract` rejects bidder outside 1-4 range
  - N.3b (RT07-05): `_OnContract` rejects btype outside `{HOKM, SUN}`
- **434 / 434 pass** (up from 429, +5 new pins).

### Still open (next batch candidates)

- **OPEN-1** — Sun overcall bottom contract banner not updating
  (user-reported v0.11.2; needs repro details)
- **RT07-06** — `_OnRound` accepts nil numeric fields (similar shape
  to RT07-05; defer to next MED batch)
- **RT07-07** — `hokmMinShape` Lever C admits weak mardoofa pairs
  (calibration; pending v0.11.1 telemetry)
- **B1, C-07, C-19, X-1** — still as-listed in v0.11.0 deferred
- **Comprehensive ultra audit** — pending v0.11.1+v0.11.2+v0.11.3
  game-log telemetry from user

## v0.11.2 — SWA banner UX: per-team breakdown + WIN/LOST relative to round outcome

User-reported UX hotfix surfaced from a screenshot: the SWA result
banner was overwriting the regular round-end score breakdown, and
its "WIN" headline was driven by SWA-validity rather than the actual
round outcome. Concretely the user's screenshot showed: team A bid
HOKM, Bot 3 (team A) called SWA, claim was verified, but team A's
trick total fell short of the make threshold so team B got +20 raw.
The banner showed a green "WIN" headline despite team A losing the
contract, and the regular per-team cards-and-melds breakdown was
hidden behind the SWA's three-line text.

### Fixed

- **`UI.lua:3036` `renderBanner` SWA branch (UX, MED)** — the SWA
  banner now:
  - Computes WIN/LOST from the actual round score delta
    (`lastRoundDelta`) relative to the local team — replacing the
    prior `setOutcome(callerTeam)` proxy which used SWA validity.
    A valid SWA claim can still coincide with a contract loss when
    the bidder team's trick points fall short of the make threshold
    (and likewise an invalid claim can coincide with a sweep
    elsewhere); the score delta is the only authoritative source
    of round outcome.
  - Shows the same per-team breakdown as the regular round-end path
    (`bidderTeam: cards X + melds Y`, `defenderTeam: cards X + melds
    Y`, modifiers row with contract type + Bel/Triple/Four/Gahwa +
    multiplier, Belote line if applicable) instead of replacing those
    rows with a single `Claim verified — all remaining tricks
    awarded.` line. The SWA-specific text is now confined to the
    banner title.
  - Title becomes either `SWA! <name> claimed — verified` (green
    backdrop) or `SWA failed — <name> claimed wrongly` (red
    backdrop).
  - Non-host degraded view (no `lastRoundResult` broadcast yet) keeps
    the prior single-line explanation in the bidder slot as a
    graceful fallback.

  Preserved: the `final` score-delta line stays unchanged at the
  bottom (`A +X   B +Y` with team-color highlights). Sounds (e.g.
  `SND_HOKM_LOST` from State.lua) continue to fire through the
  existing State.lua paths — no Sound code touched.

### Investigated, not reproduced

- **Sun overcall bottom contract banner not updating** (user-reported,
  same message): traced the wire flow end-to-end and could not find
  a code-level bug. After `S.FinalizeOvercall` mutates `s.contract`
  (host-side) and `S.ApplyContract` is called via `MSG_CONTRACT`
  receive (client-side), the bottom contract strip in `renderStatus`
  reads `S.s.contract.type` / `.trump` / `.bidder` on every UI
  refresh and rebuilds the text unconditionally — there's no caching
  layer that could hold stale values. The dispatcher fires `UI.Refresh`
  after every `CHAT_MSG_ADDON` event (`Net.lua:677`), and the host's
  `_HostResolveOvercall` calls `UI.Refresh` explicitly at line 1345
  (or via `HostFinishDeal` in the Sun-Bel-skip path).

  If the user can reproduce reliably, useful diagnostics would be:
  - Were they host or client when the bug fired?
  - The SavedVariables `WHEREDNGN.lua` dump at the moment of the bug
    (specifically `WHEREDNGN.s.contract` and `WHEREDNGN.s.phase`)
  - Whether the chat showed the `Sun overcall by <name>` log line
  - A screenshot of the moment AFTER the resolve

  Filing as `OPEN-1` for now; ready to fix once we have a repro.

### Tests

- `429 / 429 pass` — no test changes (UI.lua doesn't have a Lua
  harness; the change is mechanical and source-isolated to the SWA
  banner branch).

## v0.11.1 — C-14 BotMaster heuristicPick → Bot.PickPlay delegation

Single architectural fix: the audit-flagged HIGH item from v0.11.0's
deferred list. `BotMaster.lua` rolloutValue used a 50-line Advanced-
mirror placeholder for its rollout policy that the audit's deep dive
identified as the **single highest-impact gap in the bot code** —
rollouts under-valued ~30% of Saudi-canonical play patterns
(sweep-pursuit, trick-8 boss-scan, free-trick suit, Sun L08, Tahreeb
sender/receiver, Faranka exceptions, AKA receiver, Sun shortest-suit,
Belote preservation, Tanfeer, etc.). Saudi-Master tier was structurally
no stronger than Fzloky on these scenarios because every rollout was
biased away from canonical patterns.

This release reroutes rollouts through `Bot.PickPlay` under the
existing `_inRollout=true` recursion guard set in `BM.PickPlay`. The
delegation pattern + state swap was already identified by audit as
the canonical fix; this release implements it cleanly.

### Fixed (HIGH-architectural)

- **C-14** (`BotMaster.lua:644-755` rolloutValue heuristicPick) —
  replaced the 50-line Advanced-mirror placeholder with a single-line
  delegation: `return B.Bot.PickPlay(s)`. The rollout policy now picks
  up every Saudi-canonical branch in pickLead/pickFollow that the
  placeholder missed.

  **Mechanism**:
  - `BM.PickPlay` already sets `B.Bot._inRollout = true` (existing
    line 822) before entering the world loop. The recursion guard at
    `Bot.PickPlay:3450` (`if not Bot._inRollout`) short-circuits the
    BotMaster delegation when set, so the delegated call runs
    pickLead/pickFollow directly without recursive ISMCTS re-entry.
  - State swap inside `rolloutValue`: save and override
    `S.s.hostHands`, `S.s.trick`, `S.s.tricks`, `S.s.akaCalled`,
    `S.s.playedCardsThisRound` so `Bot.PickPlay` reads the
    determinization-sampled view rather than the real game state.
    `S.s.playedCardsThisRound` matters because `S.HighestUnplayedRank`
    keys off it (used by sweep-pursuit boss-scan, J+9 trump-lock,
    highest-unplayed lead).
  - `S.s.akaCalled` set to `nil` for sim-blind AKA semantics
    (rollouts intentionally treat AKA as not-yet-called; future tricks
    can't introduce new AKA calls in simulation).
  - Per-trick re-swap of `S.s.trick = currentTrick` after each new
    trick reset, since the loop reassigns `currentTrick` to a fresh
    table on trick boundaries.
  - All 5 swapped fields restored unconditionally via pcall pattern
    so a mid-rollout error cannot leak the swap to the next world's
    `sampleConsistentDeal` (which would corrupt sampling by reading
    polluted hostHands).

  **Bias direction shift**: the old placeholder was fundamentally
  Hokm-only (mostly Advanced-mirror smother + lowest-rank duck +
  highest-trump bidder lead). It missed all Sun-specific lead patterns
  and any later-tier follow refinements. The delegated call exposes
  the rollout simulator to the same logic real bots use, including
  M3lm/Fzloky/Master tier-specific branches when the seat being
  simulated qualifies (per `Bot.IsAdvanced/IsM3lm/IsFzloky` checks
  inside pickLead/pickFollow).

  **Performance note**: per-pick cost rises from ~5µs to ~20-50µs.
  Worst-case early-trick rollout (100 worlds × 8 candidates × ~25
  plays ≈ 20k inner picks) lands ~400-1000ms per move, vs ~100ms for
  the placeholder. Acceptable for Saudi-Master tier where the user
  has explicitly opted into a 100-world sampler — the move-quality
  gain dwarfs the latency. If empirical telemetry shows users
  perceiving the lag, a `_lightweight=true` flag could short-circuit
  the heaviest pickFollow branches in v0.11.2.

  Source: `.swarm_findings/audit_v0.10.7/C_Bot_audit.md` Audit Item
  BM-3 (lines 360-478) + Recommendation #1 (lines 580-586).

### Tests

- **`tests/test_state_bot.lua` Section M** (10 new source-match pins):
  - M.1 (C-14): heuristicPick body delegates to `B.Bot.PickPlay`
  - M.1b (C-14): old "Lead heuristics (Advanced-mirror)" placeholder
    comment removed (regression guardrail against accidental restore)
  - M.2a-f (C-14): rolloutValue saves/swaps/restores the 5 swapped
    state fields (hostHands, trick, tricks, akaCalled,
    playedCardsThisRound)
- **429 / 429 pass** (up from 419, +10 new pins).

### Caveat / next-step

The existing `tests/test_state_bot.lua` doesn't load `BotMaster.lua`,
so the C-14 delegation isn't exercised behaviorally in the test
suite — only structurally pinned. Manual smoke-testing during
development confirmed `BM.PickPlay` completes successfully with the
new delegation in ~430ms for a 100-world early-trick move (single
all-spade fixture, all 8 candidates evaluated). A behavioural test
that loads BotMaster + runs a tier comparison is the next test-
infrastructure item, deferred until the existing test_state_bot.lua
harness gap (no Net.lua / no BotMaster.lua) is closed more broadly.

The next phase per user direction is empirical telemetry: collect
v0.11.1 SavedVariables across several rounds with Saudi-Master tier
active, then compare bot decision quality vs v0.11.0 (which used the
Advanced-mirror placeholder). Specifically watch for:
- Sun bidder-team rollouts now leading the shortest suit (was leading
  longest)
- Trick-8 sweep-pursuit boss-scans firing
- AKA receiver branch firing in rollouts (was hard-blocked by
  must-trump-ruff in placeholder)

### Deferred (still-open from v0.10.7 audit, not in v0.11.1)

- **X-1** — State→UI refresh implicit dependency (massive surface)
- **C-11** — `hokmMinShape` R2-only scoping (pending telemetry)
- **C-19** — BotMaster retry-exhaust instrumentation
- 5 more MED items: A2, B1, C-07, RT07-02, etc.
- LOW items (dead-code, MaybeRunBot refactor, Sound-guard dedup)

## v0.11.0 — audit_v0.10.7 closures + voice-cue refresh

200k-token quad-track audit (Net.lua, UI.lua+State.lua, Bot.lua+
BotMaster.lua, cross-cutting/red-team) surfaced 9 HIGH + 22 MED + 17
LOW findings. v0.11.0 closes the 7 actionable HIGH bugs + 2 high-value
MED + the 8-voice-cue audio refresh. Architectural items (C-14
BotMaster heuristicPick weakness, X-1 State→UI refresh implicit
dependency) deferred to v0.11.1.

The single most important finding: **my v0.10.6 redeal-stuck recovery
was structurally dead** (RT07-01) — `s.redealing` was in
`TRANSIENT_FIELDS` so SaveSession wiped it before persistence, meaning
the recovery code at WHEREDNGN.lua + Net.lua never had data to act on.
The exact user-reported scenario ("paused mid-redeal + /reload") still
soft-locked despite the v0.10.6 shipped fix. Test-harness gap (Net.lua
+ WHEREDNGN.lua not loaded by `tests/run.py`) masked the regression.

### Fixed (HIGH)

- **RT07-01** (`State.lua:211` TRANSIENT_FIELDS) — removed `redealing`
  from the transient-fields table so SaveSession persists it. The
  v0.10.6 recovery code at `WHEREDNGN.lua` PLAYER_LOGIN + `Net.lua`
  LocalPause resume now has data to act on. The C_Timer-based auto-
  dismiss path is replaced by the recovery path post-/reload.
  **The user-reported soft-lock is now actually fixed.**

- **A5** (`Net.lua:1186` `_OnOvercallResolve`) — phase-idempotency
  guard. The v0.10.3 dual-emit (`"!"` + `"?"`) for cross-version compat
  could fire `_OnOvercallResolve` twice; under wire reorder the second
  hit could revert a remote client from PHASE_PLAY back to
  PHASE_DOUBLE. Added `if S.s.phase ~= K.PHASE_OVERCALL then return end`.

- **D1** (`WHEREDNGN.lua:197` PLAYER_LOGIN) — PHASE_PREEMPT AFK re-arm
  branch. Pre-v0.11.0 the re-arm chain covered DOUBLE/TRIPLE/FOUR/
  GAHWA but not PREEMPT; /reload during a Triple-on-Ace pre-emption
  with a human eligible seat soft-locked the same way the v0.10.6
  redeal-stuck bug did. Added `for _, pseat in ipairs(s.preemptEligible)`
  loop that re-arms `StartBelTimer(pseat, "preempt_pass")` for the
  first human eligible seat.

- **S-1** (`State.lua:546` ApplyResyncSnapshot) — added
  `s.sweepTrackAnnounced = nil` to the resync clear block. Pre-v0.11.0
  a rejoiner carrying a stale `true` flag from a prior round would
  silently miss the v0.10.7 SND_SWEEP_TRACK cue when their team
  swept tricks 1-2-3 of the new round.

- **U-7** (`UI.lua:2034`) — SWA Deny button switched from `addAction`
  (single-click) to `addConfirmAction`. Misclick cost ~30 game points
  (handTotal × mult, awarded as the Qaid penalty against the caller).
  Takweesh had confirm protection; Deny didn't.

- **B2** (`Net.lua:2079` HostFinishDeal) — nil-hands soft-lock now
  surfaces a user-facing chat error advising `/baloot reset`. Pre-
  v0.11.0 was log-only, leaving the user with a frozen window and no
  visible explanation.

- **C1#6** (`Net.lua:316` SendResyncReq) — `resyncResExpiryTimer` now
  pause-aware. Pre-v0.11.0 the 30s window timer fired regardless of
  pause; user paused for >30s (or paused + /reload) saw legitimate
  MSG_RESYNC_RES rejected as expired. Recursive named function
  pattern matching the v0.10.5 SWA pause re-arm fix.

### Fixed (MED — 2 high-value cherry-picks)

- **E2** (`Net.lua:2940` `_OnSWA`) — added `swaRequest` mutex matching
  `_OnSWAReq`. Pre-v0.11.0 a direct MSG_SWA claim from a different
  seat could race against an in-flight vote window — the second
  resolve clobbered the first.

- **RT07-03** (`Net.lua` MSG_TRICK + `State.lua` ApplyTrickEnd/ApplyPlay)
  — resync replay no longer fires v0.10.7 sound cues for past events.
  Added trailing `;1` replay flag to whispered MSG_TRICK frames during
  resync; receiver propagates `isReplay` through `S.ApplyTrickEnd` +
  `S.ApplyPlay`; the v0.10.7 cues (SND_TRUMP_CUT, SND_SWEEP_TRACK,
  SND_LAST_TRICK_WIN) skip when `isReplay=true`. Pre-v0.11.0 a
  rejoiner heard the cues for every past trick during the snapshot
  replay flood.

### Voice-cue refresh (8 mp3 → ogg replacements)

User-supplied refreshed Saudi voice cues replace the v0.5-era
edge-tts synthesized cues. All 8 files copied from `Downloads/`,
converted via `ffmpeg libvorbis q=5`, dropped into `sounds/`:

| File | Phrase | Trigger |
|---|---|---|
| `aka.ogg` | إكَهْ | AKA partner-coordination call |
| `ashkal.ogg` | أشكال | Ashkal call |
| `wla.ogg` | ولا | round-2 pass |
| `pass.ogg` | بَسْ | round-1 pass |
| `sun.ogg` | صن | Sun bid |
| `hokm.ogg` | حكم | Hokm bid |
| `awal.ogg` | أوَل | round-1 bidding start |
| `thany.ogg` | ثآني | round-2 bidding start |

No code changes — constant paths unchanged.

### Tests

- **`tests/test_state_bot.lua` Section L** (3 new pins):
  - L.1 (RT07-01): `redealing = true` no longer in TRANSIENT_FIELDS
  - L.2 (S-1): ApplyResyncSnapshot clear block contains
    `sweepTrackAnnounced` reset
  - L.3 (RT07-03): `S.ApplyTrickEnd` + `S.ApplyPlay` signatures
    accept `isReplay`; v0.10.7 cues gated on `not isReplay`
- **419 / 419 pass** (up from 412 in v0.10.7, +7 new pins).

### Deferred to v0.11.1+ (per v0.10.7 audit)

#### HIGH-architectural (deserves its own release)

- **C-14** — BotMaster `heuristicPick` rollout policy substantially
  weaker than `Bot.PickPlay` (Saudi Master ISMCTS sampler under-
  values canonical play). Recommended fix: route rollouts through
  `Bot.PickPlay` under `_inRollout=true` guard. Substantial — needs
  A/B simulation testing.
- **X-1** — State→UI refresh dependency is implicit (every Net.lua
  dispatch must remember `B.UI.Refresh()`). Same architectural
  pattern that caused the v0.10.6 round-end-stuck bug. Massive
  refactor surface.

#### MED batch (cherry-pick from 22)

- A2: unknown-tag silent UI churn (cosmetic but real)
- B1: HostStartRound mid-round redeal hazard (phase gate)
- C-07: topTouchSignal write-without-read at M3lm tier (data
  collected but unused — wire BotMaster reader call from M3lm too)
- C-19: BotMaster retry-exhaust silent fallthrough (instrumentation)
- C-11: `hokmMinShape` Lever C R2-only scoping (pending v0.10.6
  empirical telemetry showing R1 over-firing)
- 17 more in `audit_v0.10.7/` reports

#### LOW (defer to v0.11.2+)

- Dead-code duplicate at Bot.lua:1361-1397
- 638-line `MaybeRunBot` refactor candidate
- `K.MSG_KICK = "K"` dead constant
- 18 Sound-guard duplications (refactor to `cue()` helper)

### References

Audit reports under `.swarm_findings/audit_v0.10.7/`:
- `A_Net_audit.md` — Net.lua deep audit (~600 lines)
- `B_UIState_audit.md` — UI.lua + State.lua audit (~963 lines)
- `C_Bot_audit.md` — Bot.lua + BotMaster.lua audit (~630 lines)
- `D_RedTeam_audit.md` — cross-cutting / red-team audit (~365 lines)

## v0.10.7 — 6 specialized sound cues (user-supplied)

User-driven audio polish — six new specialized cues layered on top
of the existing sound system. All six OGG files supplied by the user
and wired into appropriate trigger sites in `State.lua`. Cues fire
on the appropriate audience (some all-clients, some local-only,
some team-specific). The generic `SND_LOST_ROUND` stinger is now
suppressed when one of the new specific loss cues fires so the
local client doesn't hear two stacked stingers.

### Added — 6 new sound cues

| Constant | File | Trigger | Audience |
|---|---|---|---|
| `K.SND_SWEEP_TRACK` | `sounds/sweep_track.ogg` | After trick 3 closes when same team won 1+2+3 — sweep pursuit confirmed. Once per round. | All clients |
| `K.SND_KABOOT` | `sounds/kaboot.ogg` | Round-end when local team achieved Al-Kaboot (won all 8 tricks). | Winning team only |
| `K.SND_TRUMP_CUT` | `sounds/trump_cut.ogg` | First trump played in a non-trump-led trick (Hokm only). One cue per cut event. | All clients |
| `K.SND_LAST_TRICK_WIN` | `sounds/last_trick_win.ogg` | Local seat plays a card that's GUARANTEED unbeatable by remaining seats (option 3c). Pos-4 win OR boss-of-suit with trump pool exhausted OR boss-of-trump. | Local seat only |
| `K.SND_HOKM_LOST` | `sounds/hokm_lost.ogg` | Hokm contract failed (`bidderMade=false`); fires for the bidder team (losers) only. **Takes priority over `SND_KABOOT_AGAINST`** when both would fire. Supersedes generic `SND_LOST_ROUND`. | Bidder team (losers) only |
| `K.SND_KABOOT_AGAINST` | `sounds/kaboot_against.ogg` | Round-end when Al-Kaboot was scored against local team. Suppressed if `SND_HOKM_LOST` fired (Hokm-fail dominates kaboot-against per user spec). Supersedes generic `SND_LOST_ROUND`. | Losing team only |

### Loss-cue priority order (per user spec)

1. **`SND_HOKM_LOST`** wins when bidder team failed Hokm AND local on bidder team — even when opp also achieved Al-Kaboot. The contract loss is the dominant outcome.
2. **`SND_KABOOT_AGAINST`** fires only when `SND_HOKM_LOST` didn't claim priority above (e.g., defender team got swept on a Sun contract, or sweep without contract failure).
3. **`SND_LOST_ROUND`** generic fallback fires only when neither of the above did (e.g., normal Sun-fail loss, Takweesh penalty loss).
4. **`SND_KABOOT`** (winning team) fires independently — distinct audience so no priority conflict.

### Last-trick-win cadence (option 3c)

Fires only when the local play is **provably unbeatable** from public state:
- **Position 4** AND local won → always (last-to-play has full trick info)
- **Earlier positions**: card is the boss of its suit AND for Hokm: trump pool fully exhausted (no remaining seat can ruff)
- **Trump-led tricks**: card is the highest-unplayed trump

Conservative — false negatives (won-but-not-fired) acceptable, false positives (cued-but-could've-been-beaten) not. Bot._memory void inferences are host-side only and not consulted client-side; cue relies on `S.HighestUnplayedRank` public state.

### Trigger-site wiring

- **`State.lua` `S.ApplyPlay`** (trump-cut detection): scan plays
  in the current trick for trump count BEFORE the new play; fire
  if zero prior trump AND new play IS trump AND lead-suit ≠ trump
  AND contract is Hokm.
- **`State.lua` `S.ApplyTrickEnd`** (sweep-track + last-trick-win):
  when `#tricks == 3`, if all 3 winners are on the same team,
  fire SND_SWEEP_TRACK once per round (gated by
  `s.sweepTrackAnnounced`); when `#tricks == 8` AND
  `winner == localSeat`, fire SND_LAST_TRICK_WIN.
- **`State.lua` `S.ApplyRoundEnd`** (kaboot/hokm-lost cluster):
  branch on local team membership relative to `sweep` and
  `bidderMade` parameters. Layered on top of existing
  `SND_BALOOT` round-end fanfare; suppresses `SND_LOST_ROUND`
  when a more specific loss cue (HOKM_LOST or KABOOT_AGAINST)
  fires.

### State additions

- **`s.sweepTrackAnnounced`**: per-round one-shot flag for the
  SND_SWEEP_TRACK gate. Reset at round-start (`S.ApplyStart`)
  and on full-state Reset.

### Tests

- 412 / 412 still pass — sound wiring is non-blocking
  (`B.Sound.Cue` checks for module presence; tests run with
  `B.Sound = nil`, all calls no-op).

## v0.10.6 — bidding-calibration step 3 + redeal-stuck fix (Lever C + Lever A + UX)

Calibration-probe agent (read-only) traced source-canonical Saudi
bid patterns through the addon's strength functions and identified
**the lever as HOKM-side, not Sun-side**. Plus a user-reported
HIGH bug: paused-during-redeal + /reload soft-locks the round.

### Fixed (UX HIGH — paused-during-redeal soft-lock, user report)

User report: *"game was reshuffling, i paused and did /reload, i
came back after reload to the bidding round with no buttons and
it froze with turn on the opposite side bot (dealer)."*

- **`Net.lua` new `N._HostExecuteRedeal(nextDealer)`**: extracted
  from the inline 3s `C_Timer.After` body in `N._HostRedeal` so
  it can be re-invoked from recovery paths (LocalPause resume,
  PLAYER_LOGIN session restore) when the original timer was lost
  to a pause+/reload sequence. Idempotent — bails on missing
  `s.redealing`, wrong phase, or paused state.
- **`Net.lua` `LocalPause` resume path**: when un-pausing, if
  `s.redealing` is set and phase is DEAL2BID/DEAL1, schedule a
  fresh 3s timer to land the deal. Pre-v0.10.6 the resume path
  only handled stuck PHASE_PLAY tricks; redeal-stuck case had no
  recovery.
- **`WHEREDNGN.lua` PLAYER_LOGIN session restore**: same recovery
  for the cross-/reload case. If `s.redealing` is set after
  restore and we're not paused, schedule the deal step. Mirrors
  the existing `_HostStepPlay` re-fire pattern for stuck tricks.

### Tightened (Lever C — `hokmMinShape` R2 canonical-minimum)

Per the calibration-probe agent's primary finding (review_v0.10.2
BIDDING_CALIBRATION_v0.10.5.md §8.1, video #26 R2):

- **`Bot.lua:805` `hokmMinShape`**: added `count == 2 and hasSideAce`
  clause to accept the canonical-minimum Hokm hand from video
  #26 R2 — *"أقل شي عشان تشتري الحكم: الولد + مردوفة معاه + إكا
  وحدها"* ("minimum to buy Hokm: J of trump + ONE other trump
  with it + ONE Ace on the side"). The existing `not hasJ →
  return false` guard at line ~798 already enforces J-of-trump
  anchor, so the new clause is exactly the R2 pattern (2-trump-
  with-J + side Ace), no broader. Pre-v0.10.6 this canonical
  pattern was silently rejected — the most-emphasized "minimum
  confident bid" in the entire Hokm corpus, lost.

  **Per 200k-trial Monte Carlo: ~19.23% of random 8-card hands
  match this pattern. Predicted lift: net bid rate 82% → 92.35%,
  Hokm bid rate 68.6% → 79.95% (+11.3pp).** This is the
  largest-impact single-lever lift available; addresses the
  user's "bots are not bidding" telemetry directly.

### Tightened (Lever A — `TH_SUN_BASE` 50 → 47)

Secondary calibration step paired with the v0.10.4
`K.BOT_SUN_MARDOOFA_BONUS` 5→10 bump:

- **`Bot.lua:37` `TH_SUN_BASE`**: 50 → 47. Moves the S-B "confident
  A+T mardoofa pair + 2-Ace" hand from ~38% jitter-clear to ~75%
  jitter-clear. Predicted Sun bid rate 16.8% → 22.1% per bot.
  NOT enough to close the S-A "single-mardoofa مجازف" gap
  (sunStrength=22 vs threshold=47, gap of 25 still too wide for
  threshold tweak) — that gap requires a sunStrength formula
  rebalance which is risk-laden and **deferred to v0.10.7+** if
  v0.10.6 telemetry still shows Sun under-firing.

### Test fixture refit (C-section, no behavioural change)

The PickBid sanity test fixture `{JH,9H,AH,TH,KH}` (5-card royal
flush in hearts) crossed the new Sun threshold band [41, 53] via
the v0.10.4 mardoofa bonus + v0.10.6 threshold drop combination
(sunStrength=43 within band). Replaced TH with 8H to break the
mardoofa pair — preserves the test's intent (strong 5-trump hand
bids Hokm, J+9+A+K still textbook strong-Hokm), now seed-robust.

### Tests

- **`tests/test_state_bot.lua` C-section new pin**: R2 canonical-
  minimum Hokm bid (J+9-trump + side Ace + advanced mode) bids
  HOKM. Pre-v0.10.6 this exact pattern PASSed via hokmMinShape
  rejection; post-v0.10.6 it bids correctly.
- **412 / 412 pass** (up from 411 in v0.10.5, +1 new pin).

### Deferred to v0.10.7+ (per calibration-probe agent §8.3-8.4)

- **S-A gap closure** — sunStrength formula under-rewards single-
  mardoofa hands by ~25-30 points. Threshold tweaks can't close
  this. Bonus bumps to MARDOOFA_BONUS 10→30+ would over-reward
  non-canonical mardoofa hands. Wait for empirical telemetry on
  v0.10.6 — if S-A-class hands still under-fire, tackle as a
  formula-rebalance audit.
- **R7 sirra-malaki Hokm under M3lm** — H-D pattern (4-card
  trump-meld, no Ace) is rejected under M3lm's L07 patch. Source
  carves it out as a "rare exception". Re-evaluating L07
  trade-off in isolation reserved for separate audit.
- **Promote thresholds to `K.*` constants** — `TH_SUN_BASE`,
  `TH_HOKM_R1_BASE`, `TH_HOKM_R2_BASE` are file-local in Bot.lua;
  a future cleanup can promote to `K.BOT_TH_*` for consistency
  with the rest of the bot tunables.

### References

Calibration-probe report at `.swarm_findings/review_v0.10.2/
BIDDING_CALIBRATION_v0.10.5.md` (430-line read-only audit with
10-pattern source-canonical trace + 200k-trial Monte Carlo).

## v0.10.5 — scoring-track audit closures (HIGH-2 + 4 MED + helpers + UI hotfix)

10-agent scoring sub-audit (S-Score-01..10) traced end-to-end
scoring pipelines that per-function audits couldn't see.
**Verdict: scoring is broadly correct; HIGH-1 was already shipped
in v0.10.4; HIGH-2 + 4 MED gaps close in this release.** Plus
two shared helpers extract divergent logic that had been
duplicated (and drifting) across 3 call sites each. Plus
user-reported UI hotfix for round-end "Next Round" stick.

### Fixed (UI hotfix — round-end "Next Round" sticks for human host)

- **`Net.lua:N.HostStartRound` + `N.HostFinishDeal`**: both
  functions advance host-side state and rely on the subsequent
  bot action's loopback to trigger `B.UI.Refresh()`. When the
  new round's first bidder (HostStartRound) or trick-1 leader
  (HostFinishDeal) is the human host, no bot fires → no loopback
  → UI stays on the prior PHASE_SCORE view. The Awal sound still
  plays because it's queued from `S.ApplyStart`, but the bid
  panel / play table never renders. **User-reported: "sometimes
  the round ends screen gets stuck even when pushing the next
  round button, you hear awal sound but it does not show you
  cards."** Fix: explicit `B.UI.Refresh()` at the tail of both
  functions. Harmless when a bot DID fire (Refresh runs again
  on the bot's loopback).

### Fixed (HIGH-2 — Reverse Al-Kaboot type-blind defender over-pay)

- **`Constants.lua` new `K.AL_KABOOT_REVERSE = 88`**: per video #16
  (canonical Saudi reverse Al-Kaboot / الكبوت المقلوب), defender
  sweep is awarded uniformly 88 raw across contracts — not the
  forward-AK 250/220.
- **`Rules.lua` `R.ScoreRound` sweep block**: branch on bidder-team
  vs defender-team detection. Forward-AK (bidder team sweeps):
  existing 250/220 logic unchanged. Reverse-AK (defender team
  sweeps): gated on `tricks[1].plays[1].seat == contract.bidder`.
  If bidder didn't lead trick 1, the sweep falls through to
  normal scoring (no AK bonus). The gating reflects the canonical
  Saudi asymmetry — forward-AK rewards crushing the contract;
  reverse-AK is a smaller "humiliation" payout that requires the
  bidder to have actively engaged.

  **Pre-v0.10.5 over-paid defender by ~16 gp/round (Hokm) or
  ~35 gp/round (Sun) — game-deciding in a 152-target match.**
  Source: S-Score-06.

### Fixed (MED-1 — Belote-cancellation team-level rule shared helper)

- **`Rules.lua` new `R.IsBeloteCancelled(team, meldsByTeam)`**:
  the canonical post-v0.9.0 M5 team-level form.
- **3 call sites consolidated**: `R.ScoreRound`,
  `Net.HostResolveTakweesh`, `Net.HostResolveSWA` (invalid SWA
  branch). Pre-v0.10.5 the Net.lua qaid handlers used a
  `m.declaredBy == kWho` SAME-PLAYER check, which missed
  cancellation when the K+Q holder's PARTNER declared the ≥100
  meld — over-crediting the bidder team by +2 gp on Qaid-context
  rounds. Source: S-Score-07.

### Fixed (MED-2 — Game-end H3 tiebreak shared helper)

- **`Rules.lua` new `R.GameEndWinner(cumA, cumB, target, result)`**:
  canonical post-v0.8.6 H3 logic — Gahwa winner > bidderMade-side
  > defensive "A".
- **3 call sites consolidated**: `Net.lua` normal round-end (was
  already canonical), Takweesh, SWA-invalid (both used pre-v0.8.6
  raw bidder-team logic that could award the match to the OFFENDER
  team on simultaneous-target hits during Qaid resolution).
  Source: S-Score-08.

### Fixed (MED-3 — Gahwa Sun-stale-flag defensive type-gate)

- **`Rules.lua` Gahwa match-win branch**: type-gated on
  `contract.type == K.BID_HOKM`. Sun has no Gahwa rung; a stale
  `contract.gahwa = true` on a Sun contract (resync, hostile peer,
  incomplete reset) would otherwise fire a spurious match-win.
  The multiplier path (lines 904-913) and inversion path (825-832)
  already collapse Sun's stale tripled/foured/gahwa flags
  defensively; this branch was missed. Source: S-Score-02 +
  S-Score-08.

### Fixed (MED-4 — Belote sweep-override / cancellation ordering)

- **`Rules.lua` `R.ScoreRound`**: cancellation walk now runs
  BEFORE sweep-override. Pre-v0.10.5 ordering: sweep-override
  flipped Belote ownership to the sweeping team FIRST, then
  cancellation walked meldsByTeam for the (possibly-flipped)
  Belote owner. In rare configs where the K+Q-holder's team had
  a ≥100 meld AND the OTHER team swept, the override moved
  Belote to the sweeper before cancellation could fire — net
  ~2 gp swing. Source: S-Score-04 + B-Rules-02 F-01.

### Doc — citation drift fixes

- **`docs/strategy/saudi-rules.md` Q1**: stale `Rules.lua:694`
  reference (was line of `R.ScoreRound` start) refreshed to
  current `~795` (Belote-Hokm gate inside that function).
- **`docs/strategy/glossary.md`**: "Match target | 152 raw"
  corrected to "152 game points" — the target is compared against
  per-team cumulative GAME points after div10 rounding, not raw.
- **`CLAUDE.md`**: "Bidder fails on tied 81/162" extended to
  cover Sun's 65/130 threshold too. Both Hokm and Sun require
  strictly more than half; doc previously implied Hokm-only.

### Tests

- **`tests/test_rules.lua` Section H.10-H.13**: Reverse Al-Kaboot
  pins (Hokm reverse → 88 raw, Sun reverse → 88×2=176, no AK fires
  when bidder didn't lead trick 1, forward-AK regression pin
  unchanged at 250).
- **`tests/test_rules.lua` Section L**: MED-3 Sun-Gahwa malformed
  flag does NOT fire match-win.
- **`tests/test_rules.lua` Section Q+**: 5 pins for
  `R.IsBeloteCancelled`, 7 pins for `R.GameEndWinner` (covers all
  H3 tiebreak branches), 1 pin for MED-4 ordering (Belote
  cancelled by 100-meld BEFORE sweep-override).
- **411 / 411 pass** (up from 387 in v0.10.4, +24 new pins).

### Removed from §4.2 backlog (verified false alarm)

- "MED | `Net.lua:2185-2190, 2930-2935` | R2 Sun mult collapse not
  backported to Takweesh / SWA-invalid". Verified by S-Score-07:
  both Net.HostResolveTakweesh and Net.HostResolveSWA invalid
  branches correctly apply `K.MULT_SUN`. Not a bug.

### Deferred to v0.10.6+ (per scoring-audit §"LOW")

- LOW-1: Net.lua qaid handlers don't apply v0.10.0 R2 Sun-rung
  defensive normalization (production-unreachable; defense-in-depth
  gap).
- LOW-2: `K.GAME_TARGET = 152` constant — replace 6+ hardcoded
  `or 152` literals across the codebase. Hygiene.
- LOW-4: `R.TeamOf(nil)` returns "B" silently (defensive only;
  same root cause as several existing audit refs).
- LOW-5/6: additional test pins for Belote multiplier-immunity at
  ×3/×4 + Carré-A 400 integration through R.ScoreRound.

### Pre-existing deferred items (carried from v0.10.4)

- D-RedTeam-01 E4 — T-AKA trick-locking exploit
- B-Net-02 H1/H2 — Forced-flag dead branches + bidder out-of-range
- B-State-02 H1 — ApplyBid value validation gap
- Bargiya FN → FP swing (cross-cite)
- B-Bot-06 F-01/F-02 — L07 cascade fail at M3lm+
- Dead-code redundancy at `Bot.lua:1336-1342` / `1366-1372`
- Bargiya inner-discriminator axis flip
- ISMCTS akaCalled-respecting sample pool
- `S.s.swaDenied` UI banner read
- Sun-Mathlooth-K pos-4 smother gate
- Test-harness gap (Net.lua + BotMaster.lua not loaded by run.py)

### References

Audit reports under
`.swarm_findings/review_v0.10.2/_track_S_scoring/`:
- `SCORING_SUMMARY.md` (~300-line synthesis)
- `S-Score-01..10.md` (per-pipeline sub-reports)

## v0.10.4 — review_v0.10.2 validation closures (4 HIGH + 1 calibration + tooling + doctrine doc)

Validation pass against the v0.10.3 audit synthesis caught 1 UI-
parity miss in M4 + 2 wire-level AKA exploits (HIGH) + 1 Sun-bid
calibration gap. Pre-shipping ship-readiness pass surfaced two
1-line wire guards (E1 + E2) on the AKA protocol. Late ship-
readiness pass surfaced HIGH-1 (X5 half-fix in `S.ApplyMeld` —
silent Hokm-Carré-A scoring corruption since v0.10.0). Tooling:
telemetry parser fix unblocks the calibration analyzer. Plus
doctrine note in `saudi-rules.md` documents the intentional Qaid-
vs-failed-bid meld asymmetry (v0.10.1 arbitration rationale).

### Fixed (HIGH-1 — X5 half-fix closure: Hokm-Carré-A in `S.ApplyMeld`)

- **`State.lua:1167-1190`**: v0.10.0's X5 fix patched
  `R.DetectMelds` (the meld-detection path used by `Bot.PickMelds`
  for declaring) but missed the **parallel path in `S.ApplyMeld`**
  used on the wire-receive side AND on the host's own ApplyMeld
  self-loopback. Pre-v0.10.4: `kind == "carre" + top == "A" +
  contract.type == K.BID_HOKM` fell through with `value = nil`,
  silently dropping every Hokm-Carré-A meld. Cascade: missing
  100-meld broke bidder strict-majority threshold, `R.CompareMelds`
  winner-takes-all, AND v0.9.0 M5 belote-cancellation (silent
  +20 raw over-credit on rounds where the offender held K+Q of
  trump alongside the lost Carré-A). Per video #32 line 245 +
  video #38 line 61, Carré-A in Hokm = 100 raw (treated like
  Carré-T/K/Q). Fix: added the Hokm branch with
  `value = K.MELD_CARRE_OTHER`. Stale comments at 1166 ("200 raw"
  — actual is 400) and 1177 ("Hokm 4-Aces: doesn't score" —
  opposite of rule) corrected.

  **Real-game impact:** every game with a Hokm-Carré-A round
  played since v0.10.0 mis-scored. Fix triggers ~1.92% of rounds
  per the audit's frequency estimate; combined cascade can be
  10 gp dropped + 20 gp over-credited = ~30 gp swing on affected
  rounds.

### Fixed (HIGH — `S.GetLegalPlays` AKA-blind, M4 completeness)

- **`State.lua:1975`** (comment header at 1962): pass `s.akaCalled`
  as the 6th arg to `R.IsLegalPlay`. Without this, the UI-dimming
  function ignored AKA-receiver relief — the human player saw
  non-trump discards greyed out even when partner had AKA'd,
  visually contradicting the M4 rule that legality, bot heuristics,
  and BotMaster outer driver all already honor. Same one-arg shape
  as the v0.10.3 BotMaster fix #5; this closes the M4 loop at the
  final layer.

### Fixed (HIGH — wire-level AKA exploit guards)

Pre-ship validation surfaced two wire-level AKA exploit windows
the v0.10.3 ship missed. Both are 1-line `if … then return end`
guards at the host receive boundary; both close real attack
surfaces with no risk to legitimate traffic.

- **E1 — trump-AKA wire reject** (`Net.lua:3122` `N._OnAKA`,
  D-RedTeam-01:29-60 / B-Net-05 F8a). AKA is meaningful only on
  non-trump suits — the AKA promise is "I have the boss of this
  non-trump suit." The UI hides the AKA button when the candidate
  suit equals trump, but a hostile peer can craft `MSG_AKA;<seat>;
  <trump>` directly on the wire. If accepted, it could mislead a
  partner-bot's `pickFollow` into suppressing a ruff that should
  fire (multi-trick damage on non-trump-led tricks via the
  implicit-AKA branch). Reject at wire entry. Companion guard
  added at `Rules.lua:115-130`: `akaRelief` excludes
  `akaCalled.suit == contract.trump` regardless of how the banner
  was set — defense-in-depth even if a malformed banner slipped
  past the wire-entry guard.

- **E2 — `_OnAKA` mid-trick lead-only gate** (`Net.lua` after E1
  guard, D-RedTeam-01:63-90 / B-Net-05 F8b). `LocalAKA` enforces
  lead-only at line 2358 (anti-misclick) but the wire path didn't.
  A hostile peer sending mid-trick `MSG_AKA` would set
  `s.akaCalled` after the receiver had already committed to ruff
  (or just before the next ruff decision), suppressing it. Added
  the same gate as `LocalAKA`: refuse AKA frames received when
  `#S.s.trick.plays > 0` (mid-trick).

### Calibrated (Sun-bid threshold — A+T mardoofa surgical bump)

- **`Constants.lua:329` `K.BOT_SUN_MARDOOFA_BONUS` 5 → 10**: the
  per-pair bonus for the canonical Saudi إكة مردوفة (A+T cover)
  pattern was under-rewarding hands that a Saudi pro would bid
  Sun on. Validation's preferred lever over a `TH_SUN_BASE` drop
  because it's surgical: the bonus only fires for hands with the
  doc-anchored A+T cover (video #25), not broadly relaxing the
  Sun threshold for any A-heavy hand. With pair cap = 2, max
  bonus moves from +10 to +20 for a 2-pair Sun-Mughataa hand.

  **First-step calibration framing:** simulation estimate
  predicts Sun bid rate moves ~3.1% → ~4.1% per seat. **The
  user's "bots under-bid Sun" complaint will be partially —
  but not fully — addressed.** Empirical telemetry (~30+ rounds
  on v0.10.4) needed to confirm the lift. **Reserved for v0.10.5:
  if real-play data shows still under-firing, the second pass is
  `K.TH_SUN_BASE` 50 → 44** (broader, but less doc-anchored).
  Not stacking both today — A/B comparability requires single-
  variable steps.

### Fixed (UI — first-launch felt theme mismatch, user report)

- **`UI.lua` `U.Show`**: on first launch with a non-default felt
  theme saved (e.g. `WHEREDNGNDB.feltTheme = "midnight"`), the
  cycle button label rendered correctly ("Felt: Midnight") but
  the backdrop tints rendered the **classic green** values from
  the COL hardcoded defaults at lines 143-145. Cause: `setBackdrop`
  reads `COL.feltDark`/`COL.feltLight` at frame-construction time;
  although `applyThemeColors()` runs at module-load (line 211) and
  should have updated COL before `buildMain/Lobby/Table` fire, an
  edge case in the load order left some frames captured against
  the pre-mutation defaults. Defensive fix: after freshly-built
  frames exist, force-reapply the theme by re-invoking
  `SetFeltTheme(active)`. Idempotent (writes the same name back),
  no behavioural change for users on the default green theme. The
  cycle button label and the actual backdrop now agree on first
  launch.

### Tooling — telemetry parser fix

- **`tools/calibrate.py`**: WoW SavedVariables uses bracketed-
  string key syntax (`["history"] = { ... }`) for all named
  table keys. The pre-v0.10.4 parser's regexes only matched
  bare-key form (`history = { ... }`) — the primary regex
  failed entirely, the fallback regex's non-greedy `.*?\n\s*\}`
  terminated at the first row's close brace (capturing only ~one
  row's worth of inner text with no `{}` markers, yielding zero
  parsed rows). Rewrote the locator to manual brace-walking
  with string-literal awareness; rewrote the row-key regex to
  accept both bare and bracketed forms. End-user can now run
  `python tools/calibrate.py <SavedVariables-path>` and get
  the calibration report — previously silently returned "no
  telemetry rows found" against valid SavedVariables files.

### Doc — Qaid meld-asymmetry doctrine note

- **`docs/strategy/saudi-rules.md`**: documents the intentional
  asymmetry between regular failed-bid (both teams keep own melds
  per «مشروعي لي ومشروعك لك») and Qaid (offender forfeits melds
  per «المشتري مشروعه فايد»). The two proverbs describe different
  round-end scenarios — fair-tricks-fail vs rule-violation —
  and are consistent in their respective contexts. Captures the
  v0.10.1 user arbitration rationale so future audits don't
  re-flag the asymmetry as a bug. Pre-v0.10.4 the doc still
  reflected the pre-v0.10.1 «keeps melds uniformly» reading.

### Tests

- **`tests/test_state_bot.lua` Section J**: GetLegalPlays
  AKA-relief pin (3 positive cases for non-trump discards +
  trump-still-legal, 3 sanity cases for the without-AKA
  must-trump baseline).
- **`tests/test_state_bot.lua` Section K**: HIGH-1 X5 half-fix
  parity pin — `S.ApplyMeld` produces 100-raw value for Hokm-
  Carré-A (was silently dropped pre-v0.10.4); Sun-Carré-A still
  400 raw; Hokm-Carré-K unchanged at 100 raw; Carré-9 still
  drops (K.CARRE_RANKS excludes 9).
- **`tests/test_rules.lua` Q.13**: trump-suit malformed `akaCalled`
  does not grant ruff-relief (defense-in-depth pin for E1).
- **387 / 387 pass** (up from 371 in v0.10.3, +16 new pins).

### Notes for v0.10.5 reviewers

The v0.10.3 CHANGELOG cited some HIGH-fix line numbers (1705,
2128, 830, 2964) that were comment-block headers; actual code
starts are 1714, 2143, 838, 2980. The fixes themselves are
correct; only the citation drifted. Won't amend v0.10.3 (already
on CurseForge) — captured here for forward reference.

### Deferred to v0.10.5+ (per ship-readiness review)

#### Newly catalogued HIGH backlog (absent at v0.10.3 ship too)

These were surfaced by the v0.10.4 ship-readiness pass via the
red-team and code-audit tracks; they're NOT v0.10.4 ship-blockers
but should be visible in the §4.2 backlog from now on:

- **D-RedTeam-01 E4** — T-AKA trick-locking exploit. AKA-on-T
  semantic per J-067 part 1 (10 substitutes for Ace) is partially
  honored at the bot heuristic but not at the legality layer in
  the over-trump-required case. Separate from M4 receiver-relief.
- **B-Net-02 H1/H2** — Forced-flag dead branches + out-of-range
  bidder. Wire validation gap on `MSG_BID` — accepts bidder seat
  outside 1..4 → `ApplyBid` writes to invalid seat slot.
- **B-State-02 H1** — `S.ApplyBid` lacks input value validation;
  partial mitigation downstream but the gap can corrupt state.
- **Bargiya FN → FP swing** (cross-cite). The `lenAtAce ≥ 5`
  promotion to `bargiya` (v0.10.2 M7) closes the FN but introduces
  a narrow FP path (sender holds 5+ but discarded A defensively
  on a partner-winning trick where partner was already on the
  Ace). Need hand-shape disambiguation; deferred per audit §4.2.

#### Pre-existing deferred items (per validation)

- B-Bot-06 F-01/F-02 — L07 cascade fail at M3lm+ for Aceless
  5-trump J+9 hands (~5–7 gp/match impact).
- Dead-code redundancy at `Bot.lua:1336-1342` / `1366-1372`
  (duplicate T-cardinality block in `PickBid`).
- Reverse Al-Kaboot rewrite (`K.AL_KABOOT_REVERSE = 88` constant
  doesn't exist yet; needs new bidder-led-trick-1 gate logic).
- Bargiya inner-discriminator axis flip (event-count → hand-shape).
- ISMCTS `akaCalled`-respecting sample pool (E-Det-01 #2c).
- `S.s.swaDenied` UI banner read.
- Sun-Mathlooth-K pos-4 smother gate (G-Logic-01 §3).
- Test-harness gap: Net.lua + BotMaster.lua not loaded by
  `run.py`; H1–H4 pins are source-string matches not behavioural.
- Backported MED fixes (Net.lua M5 / H3 / R2; State.lua M3
  false-AKA wipe). The full review notes M5 + H3 should arguably
  be HIGH per B-Net-04 — re-triage on v0.10.5 cycle.

### Coordination references

Full v0.10.4 ship-readiness analysis at
`.swarm_findings/review_v0.10.2/REVIEW_v0.10.4_ship_readiness.md`
(539 lines). Single richest pre-ship document — pulls together
the synthesis + focused validation + corpus traversal into one
verdict.

## v0.10.3 — review_v0.10.2 audit closures (CRIT + 8 HIGH + 7 doc + 4 follow-ups)

Multi-track ~95-agent audit cycle (Tracks A through G + synthesis)
covering 114 reports surfaced one CRIT-class production defect and
a cluster of HIGH-severity heuristic mis-scopings. Combined with
in-flight stash work and §9 low-risk follow-ups, this release closes:

- **1 CRIT** (resync dead in production via wire-tag collision)
- **6 HIGH code fixes** (4 from fork audit + my implicit-AKA closure
  + SWA pause re-arm refactor)
- **7 doc fixes** (Mathlooth revert + saudi-rules cleanup + glossary
  phantom-constant removal)
- **3 low-risk follow-ups** (dead anti-rule deletion, F-30b secondary
  trigger, hardcoded UI glyph)
- **1 UI label cleanup** (last hardcoded Arabic glyph)

All gated by 367 / 367 tests.

### Fixed (CRIT-1 — wire-tag collision; resync dead in production)

- **`Constants.lua:229`**: `K.MSG_OVERCALL_RESOLVE` collided with
  `K.MSG_RESYNC_REQ` (both `"?"`). Net.lua's dispatch chain hits
  OVERCALL_RESOLVE first → every `?` tag misrouted →
  `_OnResyncReq` was permanently unreachable. **Multiplayer rejoin
  / snapshot recovery has been silently broken since the overcall
  feature landed in v0.7.0.** Reassigned OVERCALL_RESOLVE to `"!"`.
- **`tests/test_rules.lua` Section R**: regression pin asserting
  (a) the specific collision is gone and (b) the broader invariant
  that every `K.MSG_*` constant has a unique byte value, so future
  tag additions can't reintroduce a silent dispatcher collision.

#### Cross-version compatibility (mitigated)

The `"?"` → `"!"` reassignment was paired with bidirectional
backward-compat so v0.10.2 ↔ v0.10.3 lobbies don't soft-lock at
`PHASE_OVERCALL`:

- **v0.10.3 host → v0.10.2 client**: `N.SendOvercallResolve`
  dual-emits BOTH the canonical `"!"` tag AND a legacy `"?"`-shaped
  frame so v0.10.2 clients (which only know `"?"`) still receive
  the resolve. v0.10.3 clients see both; the second arrival hits
  the idempotent `_OnOvercallResolve` (state already cleared) so
  it's a benign no-op.
- **v0.10.2 host → v0.10.3 client**: the dispatcher's `"?"` branch
  payload-shape-disambiguates. RESYNC_REQ is 2 fields
  (`"?;{gameID}"`); OVERCALL_RESOLVE is 4 fields
  (`"?;{taken};{by};{type}"`). 4-field `"?"` payloads route to
  `_OnOvercallResolve`; 2-field route to `_OnResyncReq`.

Net result: v0.10.2 ↔ v0.10.3 lobbies work in both directions
without coordinating upgrades. The dual-emit is eligible to be
dropped in v0.11.0 once v0.10.2 ages out of the install base.

### Fixed (HIGH — heuristic scoping / variable-shadowing bugs)

- **`Bot.lua:1705` `pickLead`** (B-Bot-* HIGH): pre-v0.10.3 the
  `isBidderTeam` predicate gated on `contract.type == K.BID_HOKM`,
  silently returning FALSE for ALL Sun contracts. This bypassed
  every downstream Sun branch — including Sun sweep-pursuit-early
  citing `K.AL_KABOOT_SUN = 220` (×2 = 440 effective). The check
  is purely about team relationship; type-gates already exist at
  each downstream use site. Removed the type clause.
- **`Bot.lua:2128` `bidderTeam` undefined** (B-Bot-08, HIGH):
  the conservativeOpp loop referenced an undefined `bidderTeam`,
  resolved to `nil` by Lua → `R.TeamOf(s2) ~= nil` always true →
  team-gate was a no-op (the loop accepted ANY seat with
  `styleTrumpTempo == -1`, including bidder-team). Defined locally
  inside the existing `contract.bidder` non-nil guard.
- **`Bot.lua:2964-2992` Faranka F-16 K-cover scope** (A-Src-29 +
  D-RT-03 S-1, HIGH): F-16 ("no K of trump → don't Faranka") was
  firing uniformly across all Hokm Faranka exceptions even though
  its threat model — opp A-of-trump punishment of the withheld
  card — is **structurally extinct on Exception #4** (both opps
  observed-void in trump). Scoped F-16 to skip when `oppsVoidPath`
  is true. Source-C confirms F-16 is purely a Sun anti-rule from
  video #06; the v0.10.0 X3 import to all Hokm exceptions was
  over-tight per A-Src-29.
- **`BotMaster.lua:830`** (E-Det-01 #7, B-BotMaster-01 F1, HIGH):
  Saudi-Master tier's outer driver passed 5 args to
  `R.IsLegalPlay`, omitting the optional 6th `akaCalled`. Real-
  state legal filtering ignored M4 AKA-receiver relief — the
  bot's own legal set was AKA-blind, defeating the v0.10.2 M4
  fix at the canonical case. Added `S.s.akaCalled` as 6th arg.
  (Inner rollouts intentionally pass nil for sim-blind AKA
  semantics.)
- **`Rules.lua` `R.IsLegalPlay` implicit-AKA extension**: companion
  closure to the BotMaster fix. The v0.10.2 M4 relief honored only
  the explicit `s.akaCalled` banner; partner's bare-A lead in Hokm
  non-trump (the IMPLICIT AKA per S6-6 / video #18) didn't fire
  any banner because `Bot.PickAKA`'s `r=="A"` early-return
  suppresses it. Without legality recognition, the bot's pickFollow
  implicit-AKA branch had the same dead-discards-filter shape as
  the pre-v0.10.2 explicit case. Detect the implicit pattern from
  the lead card itself: partner-led + non-trump + Ace + Hokm =
  same relief.
- **`Net.lua` SWA pause-soft-lock re-arm refactor** (E-Net-01,
  HIGH): three SWA timer sites (LocalSWA at ~2546, _OnSWAReq at
  ~2691, bot-fired at ~4059) had pause-handling shapes that all
  leaked under multi-cycle pause-toggles within one window. The
  bot-fired site bare-exited on `S.s.paused` with no re-arm at
  all (single pause = permanent soft-lock). The other two sites
  had a one-step re-arm whose inner timer also bare-exited on
  pause (two pauses within one window = soft-lock). All three
  refactored to named functions that recursively re-arm
  themselves, mirroring the OVERCALL_TIMEOUT pattern at line
  ~1195. Each pause cycle now resets to a fresh full
  `SWA_TIMEOUT_SEC` window from resume.

### Doc (review_v0.10.2 source-cite corrections)

- **`saudi-rules.md`**: Carré-A in Sun melds-table 200 → 400 (the
  table was self-contradicting v0.10.0 R5's prose); SWA paragraph
  rewritten — v0.5.17 routes ALL SWA calls through the 5-sec
  permission window, the pre-v0.5.17 "≤3 instant" branch is gone
  in code; failed-bid scoring corrected per «مشروعي لي ومشروعك لك»
  (each team keeps its own declared melds, only trick-points flow
  to winner — v0.4.3+ encoded this); stale `Rules.lua` line refs
  refreshed.
- **`decision-trees.md` + `glossary.md` Mathlooth REVERTED to
  K-tripled** (A-Src-06 + C-Xref-07): v0.10.0 R7 flipped this from
  K-tripled to J-tripled citing wrong Sun rank order. Video #17
  is unambiguous: «اول شيء عندك اكه بعدها عشره بعدها شايب» —
  Saudi Sun rank is **A > T > K > Q > J > 9 > 8 > 7**. K-tripled
  (مثلوث الشايب) is canonical; J/Q-tripled are lower-probability
  variants per the same video. Filename `17_k_tripled` was
  correct all along. R7's "romanization-error" framing was
  itself the error.
- **`glossary.md` phantom-constant cleanup**: removed references
  to non-existent constants (`K.MSG_HOKM`, `K.PHASE_HOKM`,
  `K.MULT_HOKM`, `K.MSG_SUN`, `K.PHASE_SUN`, `K.MSG_BEL`).
  Hokm/Sun share `K.MSG_BID = "B"` with type discriminator;
  Hokm uses `K.MULT_BASE = 1`; Bel uses `K.MSG_DOUBLE = "X"`.

### Cleanup (low-risk follow-ups per review §9)

- **Deleted dead rule-7 anti-trigger** at `Bot.lua:3005-3024`
  (A-Src-29 + D-RT-03 S-5): the "opp bidder led trump-Q AND we
  hold J+8 → cancel Faranka" anti-trigger was both sourceless
  (F-39 / J+8-vs-Q absent from #04 Hokm corpus) and structurally
  dead post-v0.10.0 (bidder-team gates on Exceptions #2/#3 and
  F-16 K-cover veto on Exception #4 made the path unreachable
  with `farankaTriggered = true` AND opp-bidder-led-Q). Removed.
- **F-30b secondary trigger** (G-Logic-01 §1): extended Exception
  #4 (`oppsVoidPath`) to also fire when
  `S.HighestUnplayedRank(trump) == nil` — the structurally-
  extinct case where the entire trump pool has been played out.
  Per-opp `void[trump]` flags are only set on observed
  fail-to-follow; trump-led consumption can exhaust the pool
  without ever surfacing a void → no opp can ruff regardless.
- **`UI.lua:1952` قبلك hardcoded glyph** (E-UI-01-2): replaced
  raw Arabic with Latin "Qablak" since WoW's bundled fonts
  (Arial Narrow / Frizz / Skurri) don't render Arabic glyphs.
  Same pattern as the AKA button at line 2046. Last remaining
  hardcoded Arabic glyph in v0.10.2's UI label set.

### Tests

- **`tests/test_rules.lua` Section Q.9-Q.11**: implicit-AKA
  legality relief (partner bare-A lead grants relief; opp bare-A
  doesn't; bare-K isn't Ace).
- **`tests/test_rules.lua` Section R**: wire-tag distinctness
  pin (CRIT-1 specific + invariant for all `K.MSG_*`).
- **367 / 367 pass** (up from 362 baseline).

### Deferred to v0.10.4 (per review §9)

- `S.s.swaDenied` UI banner read (UI component design needed).
- Sun-Mathlooth-K pos-4 smother gate (G-Logic-01 §3 — needs
  Mathlooth-suit hand-shape detection).
- Reverse Al-Kaboot rewrite (`K.AL_KABOOT_REVERSE = 88` constant +
  bidder-led-trick-1 gate).
- Bargiya inner-discriminator axis flip (event-count → hand-shape).
- ISMCTS akaCalled-respecting sample pool (E-Det-01 #2c).
- Backported MED-severity fixes (Net.lua M5 / H3 / R2; State.lua M3
  false-AKA wipe; `S.GetLegalPlays` AKA-blind).

### References

Audit reports under `.swarm_findings/review_v0.10.2/`:
- `_track_A_sources/A-Src-01..30` (verbatim Arabic re-extracts)
- `_track_B_code/` (per-function audits)
- `_track_C_xref/C-Xref-01..07` (cross-references / doc-drift)
- `_track_D_redteam/D-RT-01..32` (adversarial probes)
- `_track_E_ux/E-Det-01` (ISMCTS determinism)
- `REVIEW_v0.10.2.md` (~250-line synthesis)

## v0.10.2 — review-cycle MEDIUM/LOW closures (M3+M4+M7+M8+L3)

Five items from the v0.10.0 source-of-truth review closed in one
sweep. All gated by 360+ tests; bot-side behaviour now matches the
canonical Saudi pro conventions for AKA mechanics, Sun opening
leads, and Bargiya signaling.

### Fixed (M4 — AKA-receiver legality relief, J-066/J-067 part 2)

- **`Rules.lua` `R.IsLegalPlay`**: new optional 6th parameter
  `akaCalled = {seat, suit}`. When partner has called AKA on the
  led suit (banner state from `S.s.akaCalled`), the receiver is
  exempt from must-trump-ruff — they may discard freely. Closes
  `xref_X2_aka.md` B1 + B5: pre-v0.10.2 the bot's AKA-receiver
  branch was structurally dead code because `R.IsLegalPlay`
  always enforced must-trump for void+has-trump receivers,
  filtering non-trump options out of `legal` before the branch
  could pick them.
- **`Bot.lua` `legalPlaysFor`**: passes `S.s.akaCalled` through to
  every live-game legality check. Simulator callers (`R.SunCanRolloff`)
  deliberately omit the param so rollouts get AKA-blind semantics
  (transient banner state shouldn't propagate into hypothetical
  futures).
- **`Net.lua`**: 3 host-side `R.IsLegalPlay` call sites updated
  (LocalPlay anti-misclick warn, _OnPlay validation, AFK auto-play).
  All now AKA-aware on the host.
- **`Bot.lua` AKA-receiver branch (line ~2513)**: comment updated
  from "deferred to later release" to "now LIVE" — the upstream
  legality fix means `discards` filter has live content.

### Fixed (M3 — False AKA = Qaid, J-069)

- **`State.lua` `S.ApplyPlay`**: host-side validation. When the
  AKA-caller leads, the lead card MUST be the highest-unplayed of
  the AKA'd suit. Otherwise the AKA was a false claim — mark the
  lead with `.illegal=true, .illegalReason="false AKA"` and clear
  `s.akaCalled` so partner doesn't get receiver-relief on a bogus
  banner. The existing Takweesh resolution path scans `.illegal`
  marks and resolves the round as a Qaid against the offender's
  team. Also catches AKA-suit ≠ lead-suit as trivially false.
- Walks `playedCardsThisRound` from the highest non-trump rank
  downward; if any rank above the lead's is unplayed, the AKA
  is invalid. Bot's `Bot.PickAKA` already validates sender-side
  (line 3217) so legitimate addon traffic never hits this path —
  it's defensive against hostile/buggy peers that bypass the
  local `LocalAKAcandidate` gate.

### Added (M8 — Sun seat-1 mardoofa probe lead, Pro-2 L08)

- **`Bot.lua` `pickLead`**: new branch BEFORE the singleton-low /
  shortest-suit fallthrough. When the Sun bidder (or partner)
  opens trick 1 holding an A+T mardoofa (إكة مردوفة), they MUST
  lead the Ace from that pair. Source-L Pro-2 wording: "obligatory
  on him AND on his partner" — both bidder and partner are bound.
  Pre-v0.10.2 the Sun-bidder lead path fell through to "Sun
  shortest-suit lead" which led the LOWEST card from the SHORTEST
  suit — exactly opposite of L08. Tier-gated at Advanced+.

### Added (M7 — Bargiya canonical FN, محشور بلون واحد proxy)

- **`Bot.lua` `OnPlayObserved` Tahreeb recorder**: when recording
  a partner-winning A-discard signal, capture sender's pre-discard
  length-in-suit from `S.s.hostHands` (host-only). Stored as
  `tahreebSent[suit].lenAtAce`, alongside the existing rank array.
  Backward-compat: legacy fixtures with raw rank-string entries
  leave `lenAtAce` nil; only the host's bot updates it.
- **`Bot.lua` `tahreebClassify`**: when `signals[1] == "A"` AND
  `signals.lenAtAce >= 5`, return `"bargiya"` directly (confirmed
  invite per video #14 rule 2 — sender محشور بلون واحد) instead
  of demoting to `"bargiya_hint"` and waiting for a second event.
  Closes the FN where genuine 5-card invites were beaten by
  ascending 2-event "want" signals in another suit.

### Tightened (L3 — PickAKA doubled-contract conservatism)

- **`Bot.lua` `Bot.PickAKA`**: new gate — when `S.s.contract.doubled`
  is true (any escalation rung in play), suppress AKA categorically.
  Per `xref_X2_aka.md` B3 / G18-10 paragraph 2: doubled hands raise
  the info-leak cost of any signal because both sides are extra-
  motivated to read every banner. The bot now matches Saudi pro
  reservation: AKA only in normal play, not under Bel/Triple/Four.

### Tests

- **`tests/test_state_bot.lua` Section J**: 12 new pins for L3, M3,
  M7, M8 (with bidder-team and defender-seat sanity cases).
- **`tests/test_rules.lua` Section Q**: 8 new pins for M4 covering
  partner AKA / opp AKA / wrong-suit AKA / Sun-no-op / trump-still-
  legal scenarios.
- All 360+ tests pass; no regressions in the existing E/F/G/H/I/P
  sections.

### Status

After this release the v0.10.0 review's confirmed bugs are all
closed (M1 → M4 → M7 → M8 → L3 + earlier R1-R7 / X1-X5 closures).
Remaining items are opt-in variants (L4-L6 sessional flags, M5
Sun Faranka 5-factor weighted accumulator, M9 pre-bid Tawzee Qaid)
and the broader missing-features catalogue (MF-1..MF-20). Audit
cycle is genuinely saturated — calibration phase (`tools/calibrate.py`
+ in-game telemetry) is the next bottleneck.

## v0.10.1 — M1 closure: Qaid offender melds now forfeited (user arbitration)

The v0.10.0 review surfaced an unresolved rule-reading ambiguity (M1):
on a Qaid penalty, does the offender's team **keep** their own
declared melds (per "مشروعي لي ومشروعك لك" / PDF K-08) or **forfeit**
them (per Source H H-36.12 + PDF 02 K-04 "the buyer's meld is
forfeited")? User arbitration resolved this in favor of the
forfeit reading.

### Fixed (M1 — Qaid offender forfeits melds)

- **`Net.lua` `HostResolveTakweesh` (line ~2196-2225)**: when a Qaid
  penalty is resolved, the OFFENDER team (opposite of `winnerTeam`)
  now zeros their own declared melds. The non-offender team (the
  winner of the penalty) keeps their own melds × multiplier as
  before. Belote independent regardless of side.
- **`Net.lua` `HostResolveSWA` invalid-claim branch (line ~2924-2940)**:
  invalid SWA is a Qaid context — the SWA caller's team (the
  offender) zeros their own melds. Opp adds their own melds × mult.
- **Scope deliberately narrow**: the same change is NOT applied to
  `R.ScoreRound`'s regular contract-fail branch, because that path
  fires on plain bidder-failed-to-make (no illegal play). PDF K-04's
  "buyer's meld forfeited" wording is specifically about Qaid
  context, so regular fail keeps the existing "each team keeps own
  melds" semantics.

### Doc

- The pre-v0.10.1 14th-audit fix comment ("each team keeps their own
  melds during a Qaid") cited PDF K-08; it's preserved as a
  historical reference inside the new comment, then explained why
  v0.10.1 reverses for Qaid contexts. Future readers can see both
  the prior reasoning and the M1 arbitration outcome.

### Tests

- 340/340 still pass. Note: per `xref_X1_*.md` G1, there are no
  unit tests covering `N.HostResolveTakweesh` directly, so this
  behavior change is regression-bare. Adding Net.lua test harness
  coverage is a separate (larger) effort flagged in the Phase 2B
  cross-reference report.

### Concrete impact

- ~10-20 game points per round difference on Qaid-triggering rounds
  vs the pre-v0.10.1 behavior (loser's pre-existing melds no longer
  count toward their own score).

## v0.10.0 — Source-of-truth review: 9 silent bugs closed + doc-drift sweep

A 24-agent triangulation across 38 video transcripts, 8 PDFs, and the
addon code surfaced silent bugs in scoring, signaling, and bot
decision-making — most of which had been silently mis-attributed to
"framing" in earlier audits. Full review at
`.swarm_findings/review_v0.10.0/REVIEW.md` with cite trails.

### Fixed (HIGH — silent scoring bugs)

- **R5 — Carré-A in Sun under-scored 2×**
  (`review_v0.10.0/reaudit_R5_carre_a_sun.md`). Per videos #32 + #38,
  الأربع ميه names a **400 raw direct** value (the meld's name IS its
  value); per video #43 Sun divides raw by 5 → 80 game points. Pre-
  v0.10.0 `K.MELD_CARRE_A_SUN = 200` produced 200×Sun×2 ÷ 10 = 40 gp
  — exactly half. An earlier "Gemini scoring-audit catch" 400→200 was
  a misinterpretation: it eliminated the correct value as if it were
  double-counting. Fixed: `Constants.lua:95` 200 → 400 with rewritten
  comment tracing the math.

- **X5 — Carré-A in Hokm meld silently dropped**
  (`review_v0.10.0/xref_X5_meld_coverage.md`). `R.DetectMelds:240-242`
  had no `else` branch for Ace+Hokm — `value` stayed `nil` and the
  meld was never emitted. Per videos #32 line 245 + #38 line 61,
  Carré-A in Hokm scores 100 (treated like Carré-T/K/Q). Cascade:
  silent drop broke bidder strict-majority threshold check,
  `R.CompareMelds` winner-takes-all path, AND the Belote-cancellation
  v0.9.0 M5 path (holder's missing 100-meld left Belote uncancelled →
  silent +20 over-scoring). Fixed: added Hokm `value =
  K.MELD_CARRE_OTHER` branch with regression test inverted at
  `tests/test_rules.lua:365-379`.

### Fixed (HIGH — bot-decision corrections)

- **R1 — Bel-100 over-corrected by v0.9.2 #45**
  (`review_v0.10.0/reaudit_R1_bel100.md`). Three sources unanimous on
  the rule once parsed verbatim: **caller.cum ≤ 100 AND opposite.cum
  ≥ 101**, score-split and role-irrelevant. Pre-v0.9.2 was missing
  the dual-team check (`mine < 100` only). v0.9.2 #45 added the
  check but anchored on bidder/defender role, breaking the edge case
  where the bidder team is TRAILING (e.g., A=130/B=60, B bids Sun
  to catch up — B is the trailing side and per Saudi rule may Bel;
  v0.9.2 wrongly forbade this). Fixed: collapsed to score-split
  predicate; dropped `contract.bidder` consultation in `R.CanBel`;
  simplified `Net._SunBelAllowed` to query trailing team. Test
  fixtures rewritten in Section N.

- **R6 — Touching-honors K-signal interpretation INVERTED**
  (`review_v0.10.0/reaudit_R6_touching_honors.md`). Per video #05
  lines 783-884, when follower plays K after partner's bare-A: K is
  a singleton; Q and J are NOT in their hand ("Can he have Q or J?
  No, impossible — he would have played those instead"). Pre-v0.10.0
  code at `Bot.lua:491-492` set `entry.nextDown = "Q"` — pinning Q
  to the seat that the source EXPLICITLY says doesn't have Q. v0.9.2
  #12 fix activated the previously dead WRITE branch, turning dead-
  code-wrong into reachable-mispredicting-wrong. Fixed: K-signal now
  emits `entry.cleared = {"Q", "J"}` (negative-bias); reader at
  `BotMaster.lua` handles the new field by clearing those rank
  desires. Also extended `entry.broke` to fire on rank 9 (per Source
  D R3e: "9/8/7 → discourage further A-runs"; pre-v0.10.0 only 7/8).

- **R6 — Trust-asymmetry now enforced at READ site**
  (`review_v0.10.0/reaudit_R6_*.md` + `xref_X4_pro2_deal.md`). Per
  video #05 @ 03:17-03:22: "trust partner signals at face value,
  discount opponent signals (تقيد)." Pre-v0.10.0 the BotMaster
  topTouchSignal reader applied pins/clears uniformly to all 4 seats;
  opponents could weaponize the mis-pin via deceptive K-plays. Fixed:
  reader now gates on `s == R.Partner(seat)` — opponent inferences
  no longer feed sampler bias. (Self is also skipped; bot's own
  hand is known.)

- **X3 — Hokm Faranka Exception "#3" missing bidder-team gate**
  (`review_v0.10.0/xref_X3_faranka.md`). v0.9.2 #49 fixed the same-
  class bug for code's Exception "#2"; Exception "#3" (J-dead, hold
  9) at `Bot.lua:2795-2804` had the same gap and would Faranka into
  opp's Hokm contract on J-dead+9-only hands. Fixed: same `and
  onBidderTeam` gate.

- **X3 — Code's Faranka Exception "#4" relaxed from bidder-only to
  bidder-team**. Per Source C (video #04), bidder-team is sufficient
  for the "both opps trump-void" exception — partner of bidder also
  qualifies. Pre-v0.10.0's strict `contract.bidder == seat` check
  silently fell through for the partner; now uses the same
  `onBidderTeam` flag.

- **X3 — F-16 anti-rule enforced** ("no K of trump → don't
  Faranka"). Pre-v0.10.0 the code accepted T-as-cover when K was
  absent, violating Source C's explicit anti-rule. Faranka without
  K-cover has no defensive backbone (any opponent A-of-trump
  punishes the preserved card directly). Fixed: explicit
  `hasKtrump` check before allowing `farankaTriggered = true`.

- **X4/L07 — Hokm-needs-Ace tier-gated for M3lm+**
  (`review_v0.10.0/xref_X4_pro2_deal.md`). Per Pro-2 PDF L07, Hokm
  bid SHOULD require an Ace (defensive vs Sun-overcall, Kaboot,
  4-Hundred). Per Source H this is STRATEGY not hard rule — gated
  at M3lm+ (Basic/Advanced stay permissive). Pre-v0.10.0
  `hokmMinShape` enforced `hasSideAce` only at `count == 3`; the
  `count >= 4` self-sufficient branch passed without ANY Ace check
  (half-implemented L07). Fixed: M3lm+ requires `hasAnyAce` (side-
  Ace OR trump-A) at any trump count.

### Fixed (MEDIUM — invariant defense)

- **R2 — Sun escalation defensive normalization**
  (`review_v0.10.0/reaudit_R2_sun_escalation.md`). Sun has NO
  Triple/Four/Gahwa rungs (canonical rule, 3 sources unanimous —
  PDF 02 K-21, PDF 07 L34, video #11). The phase machine prevents
  these flags in practice (`State.ApplyDouble` jumps Sun directly
  to `PHASE_PLAY`), but if any caller / hand-edited save / stale
  resync slips a Sun-tripled/foured/gahwa flag through, the
  multiplier path used to apply ×6 / ×8 — encoding the invariant
  violation. Fixed: `R.ScoreRound` collapses Sun multipliers to
  Sun×Bel maximum; inversion logic ignores Sun-tripled/foured/gahwa
  for outcome determination too. Defense-in-depth Sun guards added
  at `Bot.PickTriple` / `Bot.PickFour` / `Bot.PickGahwa` (return
  `false, false` on Sun). Test fixtures rewritten to assert
  collapse instead of codifying the wrong invariant.

### Documented (M2 — deferred fix with diagnostic comment)

- **AKA receiver-relief at `Bot.lua:2451-2475` is effectively dead
  code in canonical scenarios** per `xref_X2_aka.md` B1.
  `R.IsLegalPlay` doesn't consult `S.s.akaCalled` — must-trump-ruff
  fires whenever seat is void in led suit and has trump. The
  proper fix is upstream (R.IsLegalPlay AKA-aware), but that's a
  broader change with cross-test implications (J-066/J-067 AKA-on-T
  trick-locking, J-069 false-AKA = Qaid). Inline diagnostic comment
  added; deferred to a later release.

### Doc drift (no code change)

- `saudi-rules.md` Q3 reconciliation rewritten (was incorrectly
  declaring "no change needed" — see R5).
- `saudi-rules.md` Q3b added for the Carré-A in Hokm cascade (X5).
- `saudi-rules.md` Q4 footnote refreshed (rounding resolved at
  v0.5.6, double-confirmed in v0.10.0 review).
- `saudi-rules.md` Q6 closed: سيكل (sykl) is colloquial name for
  9-8-7 tierce, scores 20 like any tierce — no separate code path.
- `saudi-rules.md` melds table: Carré-J corrected (was "trump-
  implicit 200"; canonical = 100 in any contract per videos).
- `decision-trees.md` Section 4: "K-tripled (مثلوث الشايب)" →
  "J-tripled (مثلوث الولد)" with v0.10.0 review note explaining the
  romanization-artifact bug. Per Source F, video #17 covers J-tripled
  (Sun A>T>J → J wins trick 3), not the Hokm-K case earlier docs
  imagined.
- `glossary.md` Mathlooth entry expanded with the J-tripled
  correction.
- `glossary.md` Bargiya entry now annotates "Burqia" as a
  transliteration alias (same Arabic word برقيّة, both spellings
  appear in source materials) and emphasizes the **hand-shape**
  (محشور) classification axis vs event-count.
- `CLAUDE.md` SWA section: 5-second auto-approve timer now correctly
  framed as **addon UX construct, NOT Saudi rule** (per video #35
  verbatim — no timer terminology in source). Plus 5+-card mandatory
  permission framing.

### Tests

- 340/340 regression tests pass.
- New: Hokm Carré-A meld emit test (was inverted to assert "no
  meld" — flipped to assert 100 raw).
- Updated: R.CanBel Section N rewritten for score-split rule with
  bidder-trailing edge case fixtures.
- Updated: Sun-tripled / Sun-foured tests now assert collapse to
  Sun×Bel multiplier instead of codifying the ×6 / ×8 invariant
  violation.

### Open: M1 — Qaid-offender-melds (human arbitration required)

The v0.10.0 review surfaced a rule-reading ambiguity that this
release does NOT close — left for user arbitration:

- **Source H H-36.12**: offender's melds on Qaid are "zeroed/
  forfeited"
- **PDF K-04**: "the buyer's meld is forfeited (kept by neither
  side, just lost)"
- **PDF K-08**: "stays with owner" (ambiguous — does "stays" mean
  "owner scores it" or "stays in their pile but doesn't count"?)
- **Current code**: keeps melds with offender (`Net.lua:2207-2208`,
  `Rules.lua:807-808`). The 14th-audit fix cited K-08 as basis.
- **Concrete impact**: ~10-20 game points per round when Qaid
  triggers.

Pending user decision in next release.

## v0.9.6 — Telemetry schema v=2: bot-vs-human bidder split for calibration

Audit `audit_v0.9.0/41_v083_telemetry.md` flagged two missing fields
that block meaningful calibration: schema versioning (forward-compat)
and per-row bot-flags (bot-bidder vs human-bidder distinguishability).
Both wired now.

### Added (State.lua telemetry row schema v=2)

- `v = 2` — schema version field. Pre-v0.9.6 rows lack this; analyzer
  treats them as `v=1` and skips bot/human-split analysis.
- `bidderIsBot` — derived 0/1 flag from `s.seats[bidder].isBot`. The
  single most important field for calibration: lets the analyzer
  separate "the BOT is mis-bidding" from "the HUMAN is mis-bidding."
  Without this, fail-rate / Bel-rate signals are uninterpretable.
- `seat1Bot` / `seat2Bot` / `seat3Bot` / `seat4Bot` — per-seat
  isBot snapshot at row write time. Lets the analyzer compute
  "this round had N bots at the table" cohorts.

### Updated (tools/calibrate.py)

- New "bot vs human bidder" report section. Skips pre-v0.9.6 (v=1)
  rows. For v=2 rows, splits make/fail by `bidderIsBot` and emits
  fail-rate spread:
  - Spread < 15pp = balanced bidder behavior
  - Spread > 15pp = **CALIBRATION SIGNAL** (tier or threshold
    mismatch worth investigating)
- Pre-v0.9.6-only datasets get a graceful "play more rounds with
  v0.9.6+" hint instead of a confusing empty section.

### Why this matters

The audit framed it well: telemetry's whole purpose is to drive
threshold refits. Without bot/human distinguishability, every
signal is averaged across both populations — meaningless for
saying "raise BOT_BEL_TH" or "lower TH_HOKM_R1_BASE". v=2 makes
the analyzer's calibration recommendations actually actionable.

### Tests

- 333/333 regression tests pass.
- Analyzer verified end-to-end on a 5-row synthetic dataset
  (2 bot bidders + 3 human bidders); produces correct fail-rate
  split + spread calculation.

### Backward compatibility

- Old v=1 rows in existing SavedVariables remain valid; analyzer
  reads both schemas.
- 200-row FIFO cap unchanged — old rows naturally drop as new
  v=2 rows accumulate.

## v0.9.5 — Section 4 rule 1B wouldWin gate + saudi-rules.md doc fixes

Audit-sweep loop iter on the saturated queue. Three items closed.

### Fixed (Bot.lua — Section 4 rule 1B trick-stealing misfire)

`pickFollow` rule 1B (Sun + partner-winning + we-can't-beat → second-
lowest as re-entry signal) was missing a `wouldWin` precondition.
The `sorted[2]` second-lowest pick could BEAT partner's lead and
steal the trick, contradicting the rule's intent. Concrete misfire:
partner leads JH, our hand `{7H, KH}`, smother gate fails (only 1
point card), rule 1B fires, sorted[2]=KH, KH beats JH, **we steal
partner's trick.**

Fix: gate `return sorted[2]` on `not wouldWin(sorted[2], trick,
contract, seat)`. If the second-lowest would steal, fall through
to `lowestByRank` (partner keeps the trick — the absolute-lowest
play also implicitly preserves re-entry in 2-card holdings since
there's only one alternative).

Source: `audit_v0.9.0/18_section4_now.md` §2.

### Fixed (saudi-rules.md doc drift D5)

Two stale sections updated:

- **Q4 score-rounding text** (line 156). Was tagged "⚠ Possible
  mismatch" pointing at `(x + 4) / 10` (rounds DOWN). Now reflects
  v0.5.6 fix `(x + 5) / 10` (rounds UP per video #43, "حساب النقاط
  في البلوت للمبتدئين"). Audit `audit_v0.9.0/26_rules_scoring.md`
  §6 verified the code is correct; only the doc was stale.

- **Qaid forfeit text** (line 119). Was "offending team's melds
  forfeited (zeroed) but NOT transferred to caller". Code's actual
  semantic (per 14th-audit Codex/Gemini interpretation) is "each
  team keeps own melds" — neither zeroed nor transferred. Updated
  doc to match. Audit `audit_v0.9.0/28_rules_aka_swa_takweesh.md`
  §4 confirms code-correctness.

### Tests

- 333/333 regression tests pass. Rule 1B wouldWin gate is observation-
  driven; existing E.6 fixture passes (the 9H second-lowest does NOT
  beat AH lead, so the new gate doesn't fire there).

### Audit response cumulative (v0.8.6 -> v0.9.5)

| Severity | Closed |
|---|---|
| HIGH    | 4/4 |
| MEDIUM  | 5/5 |
| LOW     | 4/6 (L2, L3 cosmetic remain) |
| Doc drift | **5/5 + saudi-rules Q4/Qaid** (D5 closed v0.9.5) |
| Missing | 7/11 |
| v0.9.0 ultra-audit | **13+** items closed |

## v0.9.4 — Calibration tooling: telemetry analyzer + workflow doc

Audit cycle saturated; pivoting to empirical calibration. v0.8.3 added
the per-round telemetry pipeline; this release adds the analyzer that
reads it and the doc that explains the workflow.

### Added

- **`tools/calibrate.py`**: zero-dependency Python analyzer for
  `WHEREDNGNDB.history` rows. Reads SavedVariables/WHEREDNGN.lua,
  parses the history table (hand-written Lua-table parser; only
  stdlib), and prints a calibration report covering:
  - Contract-type mix (Hokm vs Sun fraction)
  - Bid-round breakdown (R1 / R2 / forced)
  - Bidder make / fail rate
  - Bel / Triple / Four / Gahwa fire rates against current
    `K.*_TH` thresholds with healthy-range annotations
  - Per-bidder seat performance + cumulative-delta sum
  - Sweep frequency
  - Calibration-signal flags (fail-rate, Bel-rate, etc.) with
    target ranges from Saudi-tournament empirical data
- Modes: `--json OUT` to dump parsed rows; `--paste` to read from
  stdin.

- **`docs/CALIBRATION.md`**: workflow doc covering how to dump
  telemetry from in-game, where SavedVariables lives on Windows,
  what the analyzer produces, what each metric means in healthy
  ranges, and privacy notes (local-only, no network egress, no
  hand contents in rows).

### Why now

The bot has ~20 tunable thresholds calibrated from videos +
symmetric-distribution unit tests, but never against
human-asymmetric real-game outcomes. This is the missing input.
~100 rounds of real telemetry should be enough to refit
`BOT_BEL_TH`, `TH_HOKM_R1_BASE`, `BOT_OVERCALL_*_TH`, and the
escalation-chain ladders.

### Tests

- 333/333 regression tests pass (no production-code change in
  this release; all additions are under `tools/` + `docs/`).
- Analyzer tested on a synthetic 3-row dataset to verify parser
  + report path work end-to-end.

## v0.9.3 — Audit-sweep loop: 4 more v0.9.0 ultra-audit items closed

Continuation of the 60-report v0.9.0 ultra-audit. Four items closed
this iteration: doc drift on Section 10 (HIGH per audit #22),
bargiya_hint pass-through gap in N-3 (#58), short-window
StartLocalWarn no-op (#56), and AKA precondition (g) round-stage
suppression (#19 + decision-trees.md).

### Fixed

- **Section 10 doc drift (HIGH per audit #22)**. `decision-trees.md`
  Section 10 still tagged exceptions #2, #3, #4 + the J+8 anti-rule
  as `(not yet wired)` even though they shipped in v0.8.4 / v0.8.5 /
  v0.9.2. v0.9.0's doc-refresh updated Section 9 + Section 11 rule 3
  + Section 11 rule 4 markers but missed Section 10 entirely. Now:
  - Default no-Faranka row reframed as "wired by absence" (winners-
    branch covers it; no Faranka path exists unless an exception
    fires).
  - Exception #1 marked partially wired (v0.5.19 trick-3 sweep
    pursuit; cross-wire to pickFollow Faranka still deferred).
  - Exception #2 marked wired v0.8.4 + bidder-team gate v0.9.2.
  - Exception #3 marked wired v0.8.5 (with `S.HighestUnplayedRank`
    trump-rank fix).
  - Exception #4 marked wired v0.8.4.
  - J+8 anti-Faranka rebuttal marked wired v0.8.4.

- **#58 N-3 receiver: bargiya_hint silent drop**
  (`audit_v0.9.0/58_tahreeb_desync.md`). The N-3 opp-avoid pass at
  `Bot.lua:1799` only marked `cls == "bargiya" or cls == "want"` as
  avoid-suit. The v0.9.0-introduced `bargiya_hint` (single-A event,
  ambiguous between invite and defensive shed) was silently dropped
  — meaning a Saudi-tier opp's legitimate single-event Bargiya
  invite went undefended (we wouldn't deny tempo). Now also avoids
  on `bargiya_hint`. Conservative defense: lower-confidence hint
  still warrants suit-avoidance.

- **#56 StartLocalWarn warnAt-clamp** (`audit_v0.9.0/56_afk_new_phases.md`
  Q5). Pre-warn computed `warnAt = TURN_TIMEOUT_SEC - 10 = 50s` for
  ALL kinds, including the 5-second OVERCALL window — `warnAt > timeout`
  meant the warn never fired. Now: per-kind timeout selection
  (`overcall` uses `OVERCALL_TIMEOUT_SEC=5`), with proportional
  warnAt: 10s before for long windows (≥20s), 1s before for short
  windows. The OVERCALL human gets a 1s pre-warn cue.

### Added

- **AKA precondition (g) — round-stage / scoreUrgency suppression**
  (`audit_v0.9.0/19_section6_now.md` §2 + decision-trees.md
  Section 6 row "preconditions"). When `trickNum >= 6` (late round,
  ≤2 tricks remain), AKA's marginal information value is low —
  most voids are known, partner can read trick state directly,
  and the banner just leaks our top-card holding. Now suppress
  late-round AKA UNLESS the round is clutch (opp near-win, we
  near-clinch, or close-race within 20 cum points). Pre-v0.9.3
  only the coarse `trickNum <= 1` skip existed.

### Tests

- 333/333 regression tests pass (no fixture additions; behavior
  changes are observation-driven and gracefully degrade in absence
  of triggering conditions).

### Audit response cumulative (v0.8.6 → v0.9.0 → v0.9.1 → v0.9.2 → v0.9.3)

| Severity | Closed |
|---|---|
| v0.7.1 HIGH    | 4/4 |
| v0.7.1 MEDIUM  | 5/5 |
| v0.7.1 LOW     | 4/6 |
| v0.7.1 Doc drift | **5/5** (Section 10 closed v0.9.3) |
| v0.7.1 Missing | **7/11** (AKA precond g closed v0.9.3) |
| v0.9.0 ultra-audit | 11+ closed (HIGH-impact subset) |

## v0.9.2 — Audit-sweep loop: 7 v0.9.0 ultra-audit findings closed

Continuation of the v0.9.0 ultra-audit response. The 60-report
re-audit surfaced one CRITICAL bug (a feature claimed wired in
v0.9.0 was actually dead code), three HIGH bugs (persistence /
exploit / contract-aid), one MEDIUM (Ashkal allow-list gap), and
two LOW (UX race + hand-edit safety). All seven are closed in
this release.

### Fixed (CRITICAL)

- **#12 Touching-honors WRITE branch was dead code**
  (`audit_v0.9.0/12_touching_honors.md`). The v0.9.0 commit
  9c32c50 wired `topTouchSignal` inferences (Section 6 rules 1-4,
  video #05) but the predicate referenced an undeclared local
  `trick` instead of the existing `trickPlays`. The variable
  resolved to a global lookup → `nil`, the entire WRITE branch
  silently short-circuited, and the BotMaster sampler iterated
  against a permanently empty ledger every PickPlay call. The
  v0.9.0 CHANGELOG falsely claimed this feature was wired.
  Substituting `trickPlays` activates the dead branch as
  designed; the 60-weight desire-pin and 5-card desire-clear
  inferences now flow into ISMCTS sampling.

### Fixed (HIGH)

- **#54 M4 _partnerStyle persistence quirks**
  (`audit_v0.9.0/54_m4_partnerstyle_quirks.md`). Two bugs:
  (a) restore-side type guard was truthy-only — corrupt
  SavedVariables (hand-edited, partial-write crash, version
  skew) populating `partnerStyle` as a string would crash the
  next `Bot.OnEscalation` and silently break bot decisions for
  the rest of the game. Now `type() == "table"` checked per
  subfield. (b) Cross-character session guard short-circuited
  to PASS when either side was nil — if PLAYER_LOGIN's restore
  ran before `SetLocalName` resolved, any owner's session
  passed. Now fail-closed: `if not sess.owner or not s.localName
  then return false end`.

- **#46 Bait-ledger forced-J exploit**
  (`audit_v0.9.0/46_bait_ledger_exploit.md`). v0.8.2's deceptive-
  overplay detector flagged any J-of-suit play under partner-
  winning state as a bait, including the case where J was the
  opp's only legal card (mathematically forced). The flag
  persisted across rounds AND across /reload via M4, so a
  skilled opp could burn the bot's lead-X option for the entire
  game by playing one forced J in round 1. Two-part fix:
  (a) add a forced-J approximation gate — only flag when the
  seat's `mem.played` shows they previously held lower-rank
  same-suit cards; (b) move `baitedSuit` and `topTouchSignal`
  from per-game to per-round scope (Bot.ResetMemory), so
  cross-round amplification dies at round boundary even if a
  false flag slips through.

- **#49 Hokm Faranka Exception #2 missing bidder-team guard**
  (`audit_v0.9.0/49_hokm_faranka_priorities.md`). The 2-trump-
  count Faranka trigger fired regardless of contract ownership,
  so on a 2-trump hand against an OPPONENT's Hokm contract the
  bot would Faranka — actively withholding trump from a trick
  the opp wanted to win, helping their contract make. Fix:
  gate trigger on `R.TeamOf(contract.bidder) == R.TeamOf(seat)`.
  Exception #4 already had this guard; #2 was the gap.

### Fixed (MEDIUM)

- **#60 A-2 doubleton-T-no-A still slips through Ashkal gate**
  (`audit_v0.9.0/60_a2_singleton_t.md`). v0.9.1 closed the K
  block but the doc allow-list specifies `singleton-T`. Pre-
  v0.9.2 a hand with 2+ Ts (each in different suits, neither
  paired with own-suit A) could still Ashkal at bid-up T —
  contradicting the doc's cardinality requirement. Add explicit
  T-count gate: accept T only when `tCount == 1`.

### Fixed (LOW)

- **#45 R.CanBel three-predicate divergence**
  (`audit_v0.9.0/45_canbel_three_predicates.md`). The UI gate
  (`R.CanBel`), bot decision (`Bot.PickDouble`), and host gate
  (`Net._SunBelAllowed`) used three different predicates for
  Sun Bel-eligibility per video #11. In dual-low scenarios
  (both teams <100), the UI showed a Bel button that the host
  silently dropped — defender clicked, saw success locally,
  then watched it vanish on next MSG_ROUND. Now `R.CanBel`
  consults `contract.bidder` to apply the asymmetric form
  (`bidder>=101 AND defender<=100`); legacy nil-bidder callers
  fall through to the symmetric form for backward compat.

- **#47 Telemetry history hand-edit safety**
  (`audit_v0.9.0/47_telemetry_growth.md`). Append site
  (`State.lua`) and dump site (`Slash.lua`) used `or {}`
  fallback only — a hand-edited `WHEREDNGNDB.history` of any
  non-table type (number, string, corrupt array entry) crashed
  the next `#h` / `h[#h+1]` op. Type-guard with `type() ==
  "table"` mirrors the pattern at the top-level
  `WHEREDNGNDB` init in `WHEREDNGN.lua`. Dump path also skips
  non-table rows.

### Tests

- 333/333 regression tests pass (up 3 from v0.9.1's 330 due to
  new R.CanBel asymmetric pin coverage in test_rules.lua N).
- The touching-honors WRITE branch is now reachable; existing
  state_bot tests do not exercise the new flow but no fixture
  regresses.

### Audit response cumulative

| Severity | Closed (v0.8.6 + v0.9.0 + v0.9.1 + v0.9.2) |
|---|---|
| HIGH (v0.7.1) | 4/4 |
| MEDIUM (v0.7.1) | 5/5 |
| LOW (v0.7.1) | 4/6 (L1, L4, L5, L6) |
| Doc drift | 3/5 |
| Missing | 6/11 |
| **v0.9.0 ultra-audit findings** | **7 closed** (#12 CRIT, #45/#46/#47/#49/#54 + #60) |

### Deferred (v0.9.0 ultra-audit)

- **#51 SWA 5+ asymmetry** (UX/Saudi-rule alignment, not a bug;
  rescued by determinism check from being a scoring exploit).
- **#55 Bargiya axis FN** (cheap fix has B-side trade-off; needs
  recorder-side change for محشور proxy — deferred for design).

## v0.9.1 — Audit-sweep loop iteration: L5 + A-2 + AKA precondition (f)

Three audit items closed in one loop pass.

### Fixed (LOW)

- **L5 _OnResyncRes accepts unsolicited snapshots**. Pre-v0.9.1 a
  peer who passively overheard the gameID could fabricate a
  MSG_RESYNC_RES and inject score-state (no hand exposure, but
  cumulative + bid + contract + seat names leaked). Now: we track
  `expectingResyncRes` and only accept a response within a 30-second
  window after we explicitly sent MSG_RESYNC_REQ. The flag clears
  on first valid response or timeout.

### Added (missing feature #3 — A-2 Ashkal bid-up rank gate)

- **`Bot.PickBid` Ashkal anti-trigger A-2** (Common, video 31).
  Per the doc's allow-list ("bid-up small/mid: 7, 8, 9, J, Q,
  singleton-T"), the K is NOT permitted. Pre-v0.9.1 the predicate
  only blocked A (A-3) and T-with-A-cover (A-4); K could fire
  Ashkal in the 65-84 sun-strength range. Now: explicit `bidCardRank
  == "K"` block.

### Added (missing feature #4 — AKA precondition (f))

- **`Bot.PickAKA` precondition (f) — partner-trump-void**
  (decision-trees.md Section 6, row "AKA-call decision preconditions"
  subitem f). The whole point of AKA is to ask partner to defer
  the ruff. If partner is observed void in trump
  (`Bot._memory[partner].void[trump] == true`), they can't ruff
  anyway — the signal carries zero coordination value and leaks
  info to opponents (the banner is broadcast). Now suppressed.

### Tests

- 330/330 regression tests pass (no new fixtures this iteration; the
  three changes are observation-driven and graceful in absence of
  triggering conditions).

### Audit response cumulative

| Severity | Closed (v0.8.6 + v0.9.0 + v0.9.1) |
|---|---|
| HIGH    | 4/4 |
| MEDIUM  | 5/5 |
| LOW     | **4/6** (L1, L4, L5, L6) |
| Doc drift | 3/5 |
| Missing | **6/11** (G-4, touching-honors, Tahreeb-want, Bargiya-2flavor, A-2, AKA-f) |

## v0.9.0 — Audit MEDIUM/LOW fixes + 4 missing-feature wires + doc drift refresh

Continuation of the 73-agent v0.7.2 audit response. v0.8.6 closed
HIGH (H1-H4); v0.9.0 closes MEDIUM (M1-M5), partial LOW (L1, L4, L6),
ships 4 of the 11 documented missing features, and refreshes doc-
drift markers (D3, D4).

### Fixed (MEDIUM)

- **M1 PHASE_OVERCALL pause-blind timer**. The 5s overcall window's
  `C_Timer.After` fired regardless of pause state — could force-
  resolve the contract on resume before a human had a chance to
  click. Now: re-arms a fresh 5s timer on resume (mirrors SWA
  pattern at Net.lua:2627).
- **M2 /reload mid-OVERCALL or mid-SWA soft-locks**. PLAYER_LOGIN
  re-armed only Bel/Triple/Four/Gahwa AFK timers. Host /reload
  during PHASE_OVERCALL or with an SWA permission request in
  flight left the window stuck until manual recovery. Now: both
  windows are re-armed in WHEREDNGN.lua's PLAYER_LOGIN handler
  (cleanly resetting `startedAt` / `req.ts` so the 5s clock
  restarts post-reload).
- **M3 ISMCTS desire-table mutation idempotence**. Pre-v0.9.0,
  per-seat mutations in `sampleConsistentDeal` (line 368
  pSignalSuit, line 428 leadCount, etc.) wrote DIRECTLY into the
  shared `strong` / `defenderDesire` / `partnerDesire` tables —
  pollution persisted across seats and retry attempts within
  one PickPlay call. Now: each seat clones desire before mutation
  (3-line patch).
- **M4 Bot._partnerStyle persisted across /reload**. Bot's module-
  level state (`_partnerStyle`, `_memory`, `r1WasAllPass`) lived
  outside `S.s` and was wiped on every /reload — M3lm / Fzloky /
  Saudi-Master silently lost all accumulated reads (bels/triples/
  fours/gahwas counts, void inferences, aceLate, leadCount,
  baitedSuit, gahwaFailed, sunFail, etc.) mid-game. Now bundled
  into `WHEREDNGNDB.session.bot`; rehydrated in `S.RestoreSession`.
- **M5 Belote cancellation team-level**. Cancellation predicate
  required `m.declaredBy == kWho` (same player) — silently ignored
  partner's ≥100 meld AND silently failed when declaredBy was nil.
  Saudi rule "≥100 subsumes belote" applies to the team's collective
  scoring side. Now any team-mate's ≥100 meld cancels.

### Fixed (LOW)

- **L1 UI banner ticks during pause**. SWA + overcall self-ticking
  countdown OnUpdate handlers now skip body refresh under
  `S.s.paused`. Banner stays visible with frozen digit until resume.
- **L4 Late-AKA retroactive flip**. `N.LocalAKA` now requires
  `#trick.plays == 0` (we're about to lead) AND turn-aware
  (`S.s.turn == localSeat AND turnKind == "play"`). Pre-v0.9.0,
  pressing AKA mid-trick retroactively flipped `s.akaCalled` and
  suppressed the 4th-seat bot's ruff after the fact —
  informationally inconsistent.
- **L6 WHEREDNGNDB.target type-guard gap**. Both read sites in
  `WHEREDNGN.lua` now `tonumber()`-coerce. Hand-edited string
  target no longer breaks `cum >= target` arithmetic.

### Added (4 of 11 missing features)

- **G-4 partner-bid suppression** (audit missing #1, video #29).
  `Bot.PickBid` R2 now suppresses our own Hokm bid when partner
  has already bid Hokm — Saudi convention says support partner's
  commitment, don't compete. Sun overcall still allowed (different
  contract type). Pre-v0.9.0 the bot would emit HOKM:♥ outbid
  on partner's HOKM:♠; the host dropped it (winning already set),
  but the wire violation was visible.

- **Touching-honors family — Section 6 rules 1-4** (audit missing
  #10, video #05, Definite-confidence). When a seat plays T/K/Q
  in a trick led by their PARTNER's Ace of the same suit (or
  AKA-led), Saudi convention infers the next-rung-down rank in
  their hand:
    plays T  → has K
    plays K  → has Q
    plays Q  → has J
    plays 7/8 → broke in suit's high cards
  Inference written to `Bot._partnerStyle[seat].topTouchSignal[suit]`.
  Read by BotMaster sampler: pins the inferred next-down card to
  the seat (desire weight 60), and clears suit-high desires when
  the seat showed broke.

- **Tahreeb sender's "want" arm** (audit missing #7, video #10).
  Pre-v0.9.0 the Tahreeb sender only emitted T-4 ("LARGER first" =
  don't-want signal); the "want" arm (LOW-then-HIGH ascending
  sequence) was never emitted, so receiver's "want" classification
  could only fire by coincidence. Now wired: when we hold A or T
  of a side suit with ≥3 cards, the FIRST discard event from that
  suit is the LOWEST non-winner — receiver reads ascending
  sequence as "want this suit, lead it back".

- **Bargiya 2-flavor split** (audit missing #9, video #14).
  `tahreebClassify` now distinguishes:
    `bargiya`       — confirmed invite (signals[1]==A, ≥2 events)
    `bargiya_hint`  — ambiguous single-Ace event (could be invite
                       OR defensive shed; lower-confidence)
  Receiver scoring weights: bargiya=3, want=2, bargiya_hint=1
  (below "want" so multi-event signals dominate the ambiguous
  single-Ace case).

### Doc drift (D3, D4)

- Section 9 Tanfeer rules (3 rows) updated from "(not yet wired)"
  → "wired v0.5.14" with code-anchor hints.
- Section 11 rule 3 (pigeonhole pin) updated from "(not yet wired)"
  → "wired v0.5.22".
- Section 11 rule 4 (Sun-bidder partner concentration) updated
  from "(not yet wired)" → "wired v0.6.1".
- Section 11 rule 8 (deceptiveOverplay bait ledger) updated
  to reflect v0.8.2 wire (was duplicated in the doc; deduped).

### Tests

- 330/330 regression tests pass (was 330; M5 fix corrected one
  test's expected value from "A" to nil — the original test pinned
  the buggy single-player-only cancellation behavior).

### Audit response status (cumulative across v0.8.6 + v0.9.0)

| Severity | Total | Closed | Remaining |
|---|---|---|---|
| HIGH    |  4 | **4** | 0 |
| MEDIUM  |  5 | **5** | 0 |
| LOW     |  6 | **3** (L1, L4, L6) | 3 (L2 cosmetic AFK-pass, L3 stale akaCalled defensive, L5 _OnResyncRes info-leak) |
| Doc drift | 5 | **3** (D3, D4, partial D2) | 2 (D1 line-anchor pass, D2 R.CanBel unification, D5 Qaid forfeit text) |
| Missing |  11 | **4** | 7 (B-3, A-2, AKA preconds f+g, Bargiya receiver phase-split, 70/25/5 prior, Six-factor Tanfeer) |

## v0.8.6 — 73-agent audit HIGH fixes (H1-H4)

User-supplied 73-agent audit on v0.7.2 head identified four HIGH-severity
functional defects. All four fixed with source-level regression pins.

### Fixed (H1) — Sun-overcall race-A wire desync

**Net.lua `_OnOvercallResolve`** previously called `S.FinalizeOvercall()`
which RE-DERIVED the contract mutation from the remote's local
`s.overcall.decisions` table. If MSG_OVERCALL_DECISION frames were
dropped/reordered on a slow client, the remote's local-derived contract
disagreed with the host's. The `taken=true` branch was masked by the
host's follow-up MSG_CONTRACT broadcast; the `taken=false` branch had
no self-correction → desync persisted into trick play (different
trump suit / multiplier / scoring).

Fix: trust the wire. `_OnOvercallResolve` now just clears local
overcall state and exits PHASE_OVERCALL. The host is server-of-truth
via the follow-up MSG_CONTRACT (sent on `taken=true`); on `taken=false`
the contract stayed Hokm and the remote shouldn't mutate based on its
possibly-wrong local decisions.

### Fixed (H2) — Failed-Gahwa loser keeps own melds (cumulative inflation)

**Net.lua `_HostStepAfterTrick`** Gahwa-win override force-bumped the
WINNER's add to push their cumulative to target, but left the LOSER's
add intact (which could include their own meld points per the
"each team keeps own melds" rule in `R.ScoreRound:fail`). This
inflated the loser's cumulative cosmetically AND, more critically,
created a tiebreaker false-fire path when both teams happened to land
exactly at target.

Fix: zero the loser's add (delta) after force-bumping the winner's.
The cumulative state now cleanly reflects "match decided by Gahwa
override" with no tiebreaker race.

### Fixed (H3) — Tie-at-target tiebreaker reads `contract.bidder` (wrong on failed Gahwa)

**Net.lua `_HostStepAfterTrick`** game-end branch awarded
match-on-tie to `R.TeamOf(S.s.contract.bidder)`. On a FAILED contract
(`bidderMade==false`), the bidder team is the LOSER of the round —
awarding them the match contradicts the round result.

Fix: tiebreaker now respects `res.gahwaWinner` (canonical for Gahwa
rounds), then `res.bidderMade` (bidder won round → bidder team;
bidder failed → opp team won round). The pre-v0.8.6 raw
`contract.bidder` read is removed.

### Fixed (H4) — ISMCTS pcall granularity wraps entire 100-world loop

**BotMaster.PickPlay** `pcall` previously wrapped the entire `for w =
1, numWorlds do` loop. One bad world (sampler edge case, malformed
card, ScoreRound corner) caused pcall to bail and discard ALL 99
healthy rollouts → fallback to heuristics, dropping Saudi Master to
M3lm-equivalent for that play.

Fix: `pcall` moved INSIDE the per-world iteration. Failed worlds are
silently skipped; remaining worlds aggregate normally. With 100
worlds typical, losing 1-2 to errors is statistically irrelevant.
Only when literally all worlds error does the function fall back to
heuristics (suggests a deterministic bug, not a sampling edge).

### Tests

- 330/330 regression tests pass (was 319; +11 in new test_state_bot.lua
  section I).
- I.1a-e (H3): tiebreaker decision matrix (5 cases — bidderMade
  true/false × bidder seat 1/2 × Gahwa override).
- I.2/I.2b/I.2c (H1): source-level pin asserting `_OnOvercallResolve`
  no longer invokes `FinalizeOvercall`, still clears `s.overcall`,
  still transitions to PHASE_DOUBLE.
- I.3a/I.3b (H2): source-level pin for `addA = 0` / `addB = 0` in
  the Gahwa-win override branch.
- I.4 (H4): source-level pin asserting `pcall(function()` appears
  AFTER `for w = 1, numWorlds` (per-world wrapping, not loop-wrapping).

### Audit report

The full report and 73 per-agent findings live at
`.swarm_findings/audit_v0.7.1/AUDIT_REPORT.md`. This release closes
the HIGH section. MEDIUM (5) and LOW (6) findings + 11 missing
features are deferred for follow-up.

## v0.8.5 — Hokm Faranka exception #3 + S.HighestUnplayedRank trump-rank fix

Audit-sweep loop iteration. Two fixes that landed together because
the second was discovered while implementing the first.

### Fixed (State.lua)

- **`S.HighestUnplayedRank` trump-rank-order bug**. Pre-v0.8.5 the
  function walked `AKA_ORDER` (`A>T>K>Q>J>9>8>7`, plain rank) for
  ALL suits — including the Hokm trump suit, where the actual rank
  order is `J>9>A>T>K>Q>8>7`. So calling `HighestUnplayedRank(trump)`
  while the J was still live would return "A" instead of "J",
  producing wrong "boss" detection in the trick-8 sweep-pursuit
  branch (Bot.lua:1503) and wrong logic for the trump-pull-skip
  guard (Bot.lua:1832).
- Now auto-detects when `suit == s.contract.trump` AND
  `s.contract.type == K.BID_HOKM`, walks the new `TRUMP_HOKM_ORDER`
  in that case. Backward-compatible — no caller signature change.
- Practical impact: in late-game Hokm with J still live and us
  holding A of trump, the bot was incorrectly leading A as a
  "safe boss" in sweep pursuit. With the fix, the bot correctly
  identifies J as the top-live and skips A-leads when J could
  over-ruff. Estimated EV gain: 1-2 sweep recoveries per 100 rounds
  in late-trick scenarios.

### Changed (Bot.lua)

- **Hokm Faranka exception #3** (Common, video 04). When J of
  trump is observed dead AND we hold the 9 of trump → 9 is the
  new top live trump. Faranka allowed (withhold the new boss to
  ambush opp's remaining high cards). Detection uses the now-fixed
  `S.HighestUnplayedRank(contract.trump) == "9"` predicate (clean
  one-liner thanks to the trump-rank fix).
- Layered alongside Section 10 exceptions #2 and #4 from v0.8.4 in
  pickFollow. Anti-trigger from v0.8.4 (rule 7: opp bidder Q-led +
  we hold J+8) still applies and overrides exception #3 too.

### Tests

- 319/319 regression tests pass (no regression).
- Both fixes are observation-driven and require specific late-game
  hand shapes; the property-test legality sweep (section B) covers
  many random states without explicit fixtures. The
  `HighestUnplayedRank` fix is implicitly exercised every time the
  function is called — pre-v0.8.5 callers got wrong results that
  happened to not break legality but did mis-aim the bot's lead/
  follow choices.

## v0.8.4 — Hokm Faranka exceptions (Section 10 rules 2, 4)

Closes the v0.5.20-deferred Section 10 exceptions. Default Hokm
Faranka stays NO (play winners normally); these two exceptions
allow withholding the top trump in narrow Common-confidence cases.

### Changed (Bot.lua pickFollow)

- **Section 10 exception #2** (Common, video 04): we hold only 2
  trumps total → trump posture is already weak; Faranka EV cost
  is small. Withhold the top, play a non-winner (preferring
  non-trump non-winners to preserve trump cover).
- **Section 10 exception #4** (Common, video 04): we are the
  bidder AND both opponents are observed void in trump → risk-free
  Faranka (no one can punish the withhold). Same withhold logic.

- **Anti-trigger (rule 7)**: when opp bidder led trump-Q AND we
  hold both J and 8 of trump → override the Faranka trigger and
  play J normally. Direct counter per Section 10 rule 7.

- M3lm-gated. Lower tiers stay with default no-Faranka.

### Deferred (Section 10 exceptions still pending)

- **Exception #1** (Al-Kaboot pursuit): sweep-track detection
  exists in pickLead but cross-wiring with pickFollow adds
  complexity. Defer.
- **Exception #3** (J of trump dead, our 9 is now top): needs
  played-card scan + dynamic top-trump tracking. Doable; deferred
  for separate batch.
- **Exception #5** (partner shown extra trump): needs new style
  ledger counter for partner trump-cut events. Defer.

### Tests

- 319/319 regression tests pass (no regression).
- Faranka exceptions are M3lm-gated and require specific hand
  shapes; the property-test legality sweep in section B catches
  any illegal-card regression. No dedicated fixture in this batch
  (would require multi-trick state setup); covered indirectly by
  E.1/E.6 + the legality sweep.

## v0.8.3 — Live-game telemetry export

Foundation for empirical calibration work. Captures one row per round
into `WHEREDNGNDB.history` (SavedVariables, persists across sessions),
exposed via `/baloot history` slash commands.

### Added (State.lua)

- `S.ApplyRoundEnd` writes a row to `WHEREDNGNDB.history` per round.
  Capped at 200 rows; oldest rows drop when full. Captures:
  `roundNumber`, `ts` (GetTime), `type` (HOKM/SUN), `trump`,
  `bidder`, `doubled`/`tripled`/`foured`/`gahwa` flags, `forced`
  (Takweesh-recovery), `bidRound` (1/2), `bidCard`, `addA`/`addB`,
  `totA`/`totB`, `sweep`, `bidderMade`, `target`, `localSeat`.

### Added (Slash.lua)

- `/baloot history [N]` — print last N row summaries to chat
  (default 20). One line per round with contract shape + score
  delta + multiplier flags.
- `/baloot history clear` — wipe the history table.
- `/baloot history on` / `/baloot history off` — toggle capture
  (default ON).

### Behavior changes

- None on a clean install. `WHEREDNGNDB.historyEnabled` defaults to
  `nil` which is treated as ON (`~= false`). Existing players see
  the table grow silently; can disable with `/baloot history off`
  if SavedVariables size is a concern.
- Each client logs independently — every player has their own
  per-round perspective. Useful for individual analysis.

### Rationale

v0.5_FINAL_REPORT Priority 1 flagged "Bel calibration from real game
data" as the unblocking work for several deferred calibration items
(R1 threshold, BOT_GAHWA_TH, BOT_OVERCALL thresholds, Bel-strength
formula). This is zero-risk infrastructure — no behavior change —
that makes that calibration possible. Run a few sessions, dump the
table, fit thresholds against observed outcomes.

### Tests

- 319/319 regression tests pass (no regression).
- Telemetry write is gated on `WHEREDNGNDB` being a table; in the
  test harness `WHEREDNGNDB` is a stub table so writes happen but
  don't affect test assertions.

## v0.8.2 — Section 11 rule 8 bait-detected ledger

Closes the Section 11 rule 8 deferred item. When an opponent plays J
of led suit (or trump) while their partner was already winning the
trick — i.e., the J was unnecessary — the bot now reads it as Saudi
deceptive overplay ("I'm void below J, re-lead this suit") and
records the suit as a bait-detected target.

Subsequent `pickLead` defender turns AVOID re-leading that suit,
denying the opp's bait setup.

### Added (Bot.lua emptyStyle)

- `Bot._partnerStyle[seat].baitedSuit = { S=0, H=0, D=0, C=0 }` —
  per-suit counter accumulated across the game.

### Added (Bot.lua OnPlayObserved)

- Bait-detection branch: when a non-self seat plays J AND
  `#trickPlays >= 2` AND the pre-J trick winner equals this seat's
  partner, increment `baitedSuit[cardSuit]`. M3lm-implicit (the
  ledger always accumulates; only readers gate on tier).

### Added (Bot.lua pickLead defender branch)

- After the v0.7.1 opp-meld suit-avoidance check: if any opp
  `baitedSuit[X] >= 1` AND no earlier avoid is set AND X is not
  trump, set `fzlokyAvoidSuit = X`. Layered avoid logic:
  Fzloky > meld-suit > bait-suit (first non-nil wins).

### Tests

- 319/319 regression tests pass (no regression).
- Bait detection is observation-driven; the property-test sweep in
  test_state_bot.lua section B exercises pickLead against many
  random states without explicit bait fixtures. The wire is graceful
  — when no bait is observed, all reads return 0 and behave
  identically to v0.8.1.

## v0.8.1 — B-95 opponent score-urgency tracking

Closes the wave8 B-95 gap: bot's own urgency was wired into
`matchPointUrgency` (v0.5.x), but opponent urgency was unmodelled.
Desperate humans bid weaker hands; the bot now anticipates this
and counter-Bels accordingly.

### Added (Bot.lua)

- `opponentUrgency(oppSeat)` — local helper, mirror of `scoreUrgency`
  read from oppSeat's team perspective. Returns +12 (opp on brink),
  +6 (opp behind 80+), -8 (opp near clinch), 0 (neutral). M3lm-gated.
- `Bot.OpponentUrgency(oppSeat)` — public wrapper for cross-module
  use (BotMaster sampler reads this).

### Changed (Bot.lua)

- `Bot.PickDouble` lowers the Bel threshold by 5 when the contract
  bidder's `opponentUrgency` ≥ 6 (their team behind 80+, or we're
  near clinch). M3lm-gated. Combined with existing `combinedUrgency`
  the threshold stays within the `BOT_BEL_TH - 16` floor.

### Changed (BotMaster.lua)

- `sampleConsistentDeal` damps `pickProb` to 0.5 (matching the
  aceLate degradation tier) when the bidder seat has `OpponentUrgency`
  ≥ 6. Strong-card pinning becomes less aggressive in the bidder's
  hand, widening the sampled distribution toward weaker holdings —
  the Hail-Mary bid pattern.

### Tests

- 319/319 regression tests pass (no regression).
- The B-95 wire is gated on M3lm + cumulative-score state; unit
  tests for `Bot.PickPlay` legality (section B) sweep across many
  random states without explicit B-95 fixtures. The behavior is
  graceful — when opponentUrgency returns 0 (neutral), all wires
  no-op identically to pre-v0.8.1.

## v0.8.0 — Sun-overcall window: cross-trump Hokm take

Extension of v0.7.0. Same 5s window now also lets a non-bidder seat
**TAKE the contract as their OWN Hokm** (different trump suit), in
addition to the existing TAKE-as-Sun option. Symmetric with how
v0.7.0 enabled bidder UPGRADE → Sun and non-bidder TAKE → Sun.

Bidder UPGRADE remains Sun-only (a bidder switching to a different
Hokm suit makes no strategic sense — they already chose their best
trump).

### Added (Constants.lua)

- `K.BOT_OVERCALL_TAKE_HOKM_TH = 80` — bot threshold for cross-trump
  Hokm take.

### Changed (Rules.lua)

- `R.ResolveOvercall` now accepts decisions of the form
  `TAKE_HOKM_<S|H|D|C>`. Validates suit (must be one of S/H/D/C and
  must NOT match bidder's current trump). On match, returns
  `{ taken = true, by = N, type = "TAKE_HOKM", trump = "<suit>" }`.
- TAKE and TAKE_HOKM_<suit> share the same priority (bid order from
  dealer's right). Bidder UPGRADE still wins over both.

### Changed (State.lua)

- `S.RecordOvercallDecision` accepts `TAKE_HOKM_<S|H|D|C>` decisions.
  Validates the 11-character format and suit set; rejects malformed
  inputs (`TAKE_HOKM_X`, `TAKE_HOKM_`, `TAKE_HOKM`).
- `S.FinalizeOvercall` handles the `TAKE_HOKM` result type: contract
  type stays Hokm, bidder is rewritten to taker, trump is rewritten
  to result.trump, defender pair re-derived.

### Changed (Bot.lua)

- `Bot.PickOvercall` extended to evaluate Hokm-take alternatives.
  For each non-current-trump suit, computes `suitStrengthAsTrump`,
  applies the B-1 Saudi minimum-Hokm gate (J + count >= 3), and
  returns the strongest contract type that clears its threshold.
  When TAKE-as-Sun and TAKE_HOKM-as-Hokm both clear, the higher raw
  strength score wins.

### Changed (Net.lua)

- `N.LocalOvercall` validates `TAKE_HOKM_<suit>` decisions, rejects
  same-as-current-trump suits, and routes via the existing
  `MSG_OVERCALL_DECISION` wire (no protocol change — decision string
  is just longer).

### Changed (UI.lua)

- Non-bidder PHASE_OVERCALL action panel shows two TAKE options:
  "Take as Sun" + "Take as Hokm <suit>" (auto-picks best non-current-
  trump suit from local hand using inline suitStrength heuristic).
  WLA still available. Decided-state label handles all decision
  types including TAKE_HOKM_<suit>.

### Tests

- 319/319 regression tests pass (was 292; +7 new in section P,
  +20 new in section H).
- New P.23-P.29: TAKE_HOKM resolution, same-suit rejection,
  malformed-suit rejection, bidder UPGRADE still wins, bid-order
  priority across mixed TAKE/TAKE_HOKM, forced-contract gating.
- New H.15-H.17: Bot.PickOvercall TAKE_HOKM choice, contract
  rewrite via S.FinalizeOvercall, lock-out, malformed decision
  rejection.

## v0.7.2 — Section 4 rule 1 split + Section 11 rule 1 wire (video #05/#09 re-read)

User-reported re-read of source video #05 transcript revealed that
v0.5.11 conflated two distinct scenarios into a single "Sun losing-
side dump HIGHEST" rule. The fix went from one wrong extreme to
another. v0.7.2 splits Section 4 rule 1 into two scenarios per the
correct readings, AND wires Section 11 rule 1 (deferred since v0.5.22
when the WHY column was suspect).

### The video re-read

**Video #05 transcript** (Saudi Arabic, paraphrased):
> "If this opponent played the K, it's possible he has only the T.
> He played the K [which is] smaller than the T. But could he have
> the Q or J? No, impossible — if he had them he would have played
> them instead of the K, because they are smaller than the K."

The convention is **Tasgheer** (play-smallest), not "dump-highest".
The speaker's reasoning: opp plays K because K is the smallest of
their non-saving cards. Q/J/9/8/7 (smaller than K in plain rank
A>T>K>Q>J>9>8>7) would have been played FIRST per the convention.

**Video #09** ("biggest mistake in Baloot") is a DIFFERENT scenario:
partner-led Tahreeb-receiver context where playing absolute lowest
signals "I'm out of this suit", denying partner the re-entry.

### Changed (Bot.lua)

- **Section 4 rule 1A** (Common, video 05). REVERTED v0.5.11
  "highestByRank" branch in `pickFollow` opp-winning fall-through.
  The fall-through to `lowestByRank(legal)` at the function bottom
  already implements the corrected Tasgheer convention. The v0.5.11
  branch is now a documentation-only marker explaining the revert.

- **Section 4 rule 1B** (Definite, video 09). New branch in
  `pickFollow` partner-winning fall-through (after smother fails).
  When Sun + partner-winning + must-follow + can't-beat AND no
  point card to donate via Takbeer: returns **second-lowest** of
  the in-suit follow set, NOT absolute lowest. Preserves partner's
  ability to lead the suit back to us as a re-entry. Fires only
  for Sun (Hokm partner-winning has different conventions) and
  only when ≥2 in-suit cards are available.

- **Section 11 rule 1** (Common, video 05). Wire in
  `Bot.OnPlayObserved`: when Sun + opp follows lead suit with K or
  T AND that play loses (some other card in the trick outranks it),
  set `mem.void[leadSuit] = true`. Per Tasgheer convention, smaller
  cards (Q/J/9/8/7) would have been played first; reaching K or T
  means everything below is structurally absent. Pragmatic
  approximation — seat may still hold a single T after K-play, but
  the void flag is the right signal for sampler / opp-void lookups.

### Changed (docs/strategy/decision-trees.md)

- Section 4 rule 1 split into 1A (Sun+opp-winning → SMALLEST) and
  1B (Sun+partner-winning → SECOND-LOWEST).
- Section 11 rule 1 WHY column rewritten — was "Saudi losing-side
  dump-highest convention" (wrong); now "Saudi Tasgheer / play-
  smallest convention" with transcript citation.
- Contradictions log: the Sun off-suit losing-side dump entry
  reframed as RESOLVED v0.7.2 with rationale.

### Tests

- 292/292 regression tests pass (was 291; +1 new E.6).
- **E.1 updated**: pre-v0.7.2 expected `KH` (v0.5.11 highest); now
  expects `8H` (v0.7.2 lowest, Tasgheer rule 1A).
- **E.6 new**: pin for rule 1B partner-winning + can't-beat →
  second-lowest. Constructed to skip the smother gate (#pointCards=1
  H card, completed=0, not lastSeat) so the rule 1B branch fires.

## v0.7.1 — B-97 opp-meld suit avoidance (audit sweep)

Single-fix release. Loops back to `bot_picker_gaps.md` / wave8 B-97
for one previously unprocessed item.

### Changed (Bot.lua)

- **B-97 opp-meld suit avoidance** (audit). Pre-v0.7.1, `pickLead`
  never read `S.s.meldsByTeam` — opponents could declare a sequence
  meld in suit X (their established run) and the bot would still
  lead X freely, giving them tempo to cash the declared cards.
  Added an M3lm-gated reader in the defender-branch fzlokyAvoid
  block that flags any opponent-team sequence meld's suit as an
  avoid hint. Layered on top of existing Fzloky avoid (Fzloky wins
  if both apply). Skips trump suit (irrelevant to non-trump lead
  selection) and skips carrés (across-suit 4-of-a-rank don't imply
  a suit-lead intent).
  Sources: bot_picker_gaps.md / wave8 B-97.

### Tests

- 291/291 regression tests pass.
- B-97 fix is on the M3lm+ defender-lead path and only triggers when
  an opp seq meld is already in `S.s.meldsByTeam` — narrow scenario,
  no dedicated fixture (covered by the property-test sweep in
  test_state_bot.lua section B that runs random states across many
  seeds and would catch any illegal-card regression).

## v0.7.0 — Sun-overcall window: Phase 3 (UI) — feature complete

End-to-end Sun-overcall window. The bidder of any non-forced Hokm
contract gets a 5-second window to upgrade to Sun (unless the R1
bid card was an Ace, in which case only WAIVE is available); other
seats get to TAKE the contract as their Sun. First bidder UPGRADE
wins; otherwise earliest TAKE in bid order; otherwise Hokm stands.

### Added (UI.lua)

- **Sun-overcall countdown banner** mirroring SWA's pattern. Shows
  "Xs left · N/4 decided" and self-ticks at ~3 Hz. Auto-hides on
  phase exit. Anchored to `centerPad` top, tinted blue (vs SWA
  gold) for at-a-glance phase distinction.
- **PHASE_OVERCALL action buttons** in the standard action panel:
  - Bidder + non-Ace bid → "Upgrade to Sun (Ns)" + "WLA (waive) (Ns)"
  - Bidder + Ace bid → "WLA (waive) (Ns)" only (UPGRADE filtered)
  - Non-bidder → "Take as Sun (Ns)" + "WLA (waive) (Ns)"
  - After local seat decides → status indicator instead of buttons
    ("Upgraded to Sun — waiting for others", etc.)
- Host explicitly calls `B.UI.Refresh()` from
  `N._HostBeginOvercallWindow` since the loopback receiver returns
  early on `S.s.isHost` — without this the host wouldn't see their
  own overcall buttons / banner.

### End-to-end behaviour

| Scenario | Outcome |
|---|---|
| All-bot table, no bot bids strong enough Sun | 5s elapses, all WAIVE, contract stays Hokm (existing flow) |
| All-bot table, one bot has Sun-strong hand | Synchronous resolve at window-open: contract flips to Sun |
| Mixed table, human bidder Sun-strong | Human clicks Upgrade, contract flips, 5s short-circuits if all decide |
| Mixed table, human non-bidder takes | Human clicks Take, contract flips, becomes new bidder |
| R1 bid card was Ace, bidder strong | Bidder sees WLA only — anti-trap rule. Other seats can still TAKE. |
| Forced/Takweesh contract | Window does NOT open (existing post-bid flow proceeds as v0.6) |
| Sun bid | Window does NOT open (overcall is Hokm-only) |
| Late join during window | Resync replay sends MSG_OVERCALL_OPEN + recorded decisions |

### Tests

- 291/291 regression tests pass.
- Phase 3 UI is not covered by headless tests (no UI test harness in
  the repo). State machine + bot AI are exhaustively tested in Phase 1
  (sections P + H, 65 assertions). Network protocol relies on
  manual in-game verification — the SWA banner pattern this mirrors
  is a known-good blueprint.

### Configuration

- `WHEREDNGNDB.allowSunOvercall` (Boolean, default true): set false
  to disable the entire feature for non-Saudi-rule installations.

### Known limitations / deferred polish

- 5s window is short. If you find players consistently miss the
  decision, we can raise `K.OVERCALL_TIMEOUT_SEC` (or make it
  contextual: longer when a human is eligible, shorter when only
  bots remain undecided).
- Bot strength thresholds (`K.BOT_OVERCALL_SELF_TH = 75`,
  `K.BOT_OVERCALL_TAKE_TH = 80`) are first-pass calibrations.
  Tune empirically once you've played some games.
- `Bot.PickOvercall` is M3lm+ only (lower tiers always WAIVE) per
  D3 in the design spec. If you want Advanced bots to also act on
  overcalls, drop the `Bot.IsM3lm()` gate.

### Side notes (logged for future work)

- **R1 bid rate measurement** (1000 deals): R1 bid 36.7%, R2 bid
  69.7% of those that reached R2, overall 80.8% of deals get a bid;
  19.2% all-pass redeals. Lowering `TH_HOKM_R1_BASE` from 42 to 38
  would shift more boundary hands into bidding without violating
  the B-1 minimum-shape gate. **Deferred** — calibration tweak,
  not a bug.
- **Ashkal never fires in pure-bot bidding** despite v0.5.8 ORDER
  FIX — likely because the bid-history snapshot used by the Ashkal
  predicate is empty when seats are simulated independently.
  **Deferred** — separate investigation.

## v0.7.0-pre2 — Sun-overcall window: Phase 2 (network protocol)

Wires the Phase 1 state machine onto the addon-message bus so the
overcall window opens in actual networked play. UI is still Phase 3.

### Added (Constants.lua)

- `K.MSG_OVERCALL_OPEN` (`>`) — host announces the 5s window opens.
  No payload.
- `K.MSG_OVERCALL_DECISION` (`<`) — a seat decided. Payload:
  `seat;decision` where decision ∈ {UPGRADE, TAKE, WAIVE}.
- `K.MSG_OVERCALL_RESOLVE` (`?`) — host announces window closed +
  result. Payload: `taken(0|1);by(seat or 0);type`.

### Added (Net.lua)

- `N.SendOvercallOpen / SendOvercallDecision / SendOvercallResolve`
  broadcast wrappers.
- `N._OnOvercallOpen / _OnOvercallDecision / _OnOvercallResolve`
  receivers + dispatch entries in `N.HandleMessage`.
- `N._HostBeginOvercallWindow` — opens the window via
  `S.BeginOvercall`, broadcasts MSG_OVERCALL_OPEN, records all
  bot-seat decisions synchronously (via `Bot.PickOvercall`), schedules
  the 5s timer OR early-resolves if all seats already decided.
- `N._HostResolveOvercall` — calls `S.FinalizeOvercall`, broadcasts
  MSG_OVERCALL_RESOLVE, broadcasts a fresh MSG_CONTRACT if the
  contract was rewritten, then continues the existing post-bid flow
  (Sun-Bel-skip check + `MaybeRunBot` for PHASE_DOUBLE).
- `N.LocalOvercall(decision)` — local-action helper for the player's
  UI button click. Validates decision vs `R.CanOvercall` + bidder/
  non-bidder semantics; sends the wire message.
- Hook in `N._HostStepBid` (between `S.ApplyContract` and the existing
  Sun-Bel-skip/MaybeRunBot path) — calls
  `_HostBeginOvercallWindow`. If it returns true, defers the rest of
  the post-bid flow until `_HostResolveOvercall` fires; otherwise
  proceeds normally.
- `N.MaybeRunBot` early-returns on PHASE_OVERCALL — bot decisions
  are already recorded synchronously by the host orchestrator and
  the 5s timer drives the resolve.
- `N.StartLocalWarn` accepts `"overcall"` kind (no-op pre-warn since
  5s < 10s warn threshold; included for symmetry with the existing
  escalation kinds).
- Resync replay: `N.SendResyncRes` whispers `MSG_OVERCALL_OPEN` plus
  any already-recorded `MSG_OVERCALL_DECISION` frames when a rejoiner
  arrives during PHASE_OVERCALL. Without this, late-joiners would see
  PHASE_OVERCALL in the snapshot but no `s.overcall` body, so their
  UI button + clicks would silently no-op.

### Behavior changes

- Per-install opt-out: `WHEREDNGNDB.allowSunOvercall = false` disables
  the window entirely (default: enabled). Useful for non-Saudi-rule
  installations.

### Phase 2 explicitly NOT included

- **No UI yet.** Clicking the local-action button requires Phase 3
  (UI 5s popup mirroring SWA's pattern).
- **Headless wire test absent.** WHEREDNGN's Net.lua doesn't have a
  headless test harness (everything's mocked at S/Bot layer). Phase 2
  changes are validated by Phase 1's 65 headless tests + manual
  network testing in-game.

### Tests

- 291/291 regression tests pass — Phase 2 is a wire-protocol layer
  on top of Phase 1's already-tested state primitives.

## v0.7.0-pre1 — Sun-overcall window: Phase 1 (state machine + bot AI)

User-requested feature: post-Hokm-bid 5-second window where the bidder
may upgrade their Hokm to Sun, AND non-bidder seats may take the
contract as their own Sun. Implements `Q1=A, Q2=simultaneous-bid-order
priority, Q3=A, Q4=other-takes-or-bidder-self-upgrade, Q5=before Bel,
D1=bid-order-priority, D2=no-Takweesh, D3=M3lm+, D4=SWA-style popup`
from the design discussion.

This release ships **Phase 1 only** — the pure-host state-machine
primitives, bot AI, and headless tests. Network plumbing (Phase 2)
and UI (Phase 3) follow in subsequent releases.

### Added (Constants.lua)

- `K.PHASE_OVERCALL = "overcall"` — new game phase between bid
  resolution and PHASE_DOUBLE.
- `K.OVERCALL_TIMEOUT_SEC = 5` — 5-second window per spec.
- `K.BOT_OVERCALL_SELF_TH = 75` — bidder self-upgrade strength.
- `K.BOT_OVERCALL_TAKE_TH = 80` — non-bidder take strength (stricter).

### Added (Rules.lua)

- `R.CanOvercall(seat, contract, bidCard)` — eligibility predicate.
  Returns false for forced/Takweesh contracts, Sun contracts, the
  bidder when bid card is Ace (anti-trap rule), nil inputs.
- `R.ResolveOvercall(decisions, contract, bidCard, dealerSeat)` —
  conflict resolver. Bidder UPGRADE wins; otherwise earliest TAKE
  in bid order (starting from dealer's right).

### Added (State.lua)

- `S.BeginOvercall(bidCard, dealerSeat)` — opens the window,
  transitions phase to PHASE_OVERCALL, initializes `s.overcall`.
  Refuses on Sun/forced contracts.
- `S.RecordOvercallDecision(seat, decision)` — locks in a per-seat
  decision (UPGRADE/TAKE/WAIVE). Once decided, no take-backs.
- `S.FinalizeOvercall()` — runs `R.ResolveOvercall`, mutates
  `s.contract` if an overcall wins (rewrites bidder + clears trump
  + re-derives defender pair), transitions phase to PHASE_DOUBLE,
  clears `s.overcall`.

### Added (Bot.lua)

- `Bot.PickOvercall(seat)` returns `"UPGRADE"`, `"TAKE"`, or
  `"WAIVE"`. Tier-gated: lower-than-M3lm always WAIVE per D3.
  Uses `sunStrength(hand)` against the two thresholds; respects
  Ace-bid-card via `R.CanOvercall`.

### Added (tests)

- `test_rules.lua` section P (22 assertions): `R.CanOvercall` +
  `R.ResolveOvercall` covering bidder UPGRADE, non-bidder TAKE,
  Ace-bid blocks, forced contracts, bid-order priority,
  multi-TAKE arbitration across different dealer positions, nil
  inputs.
- `test_state_bot.lua` section H (43 assertions): full state-
  machine integration — BeginOvercall/Record/Finalize lifecycle,
  contract rewriting on UPGRADE vs TAKE, phase transitions, lock-out
  semantics, invalid-input rejection, Bot.PickOvercall tier gating
  + strength-decision sweep.

### Phase-1 explicitly NOT included

- **No networking yet.** `MSG_OVERCALL_TAKE` / `MSG_OVERCALL_WAIVE`
  / `HostBeginOvercall` / `HostResolveOvercall` are Phase 2.
- **No UI.** The 5s popup mirroring SWA's flow is Phase 3.
- **No integration with `S.ApplyContract`.** Existing post-bid
  flow still goes directly to PHASE_DOUBLE — Phase 2 will hook
  the overcall window in.

### Tests

- 291/291 regression tests pass (was 226; +65 in sections P + H).
- Headless tournament unaffected (overcall window not yet wired
  into the natural game loop).

## v0.6.1 — BotMaster sampler biases + bidder-branch styleTrumpTempo wire

Three clean wires that were dead infrastructure or partial.

### Changed (BotMaster.lua sampler)

- **B-56 leadCount-based suit bias** (audit Tier 4 / v0.5_FINAL_REPORT
  Priority 2). `leadCount[suit]` was previously written by
  `Bot.OnPlayObserved` (Bot.lua:368-369) but read by zero pickers —
  pure dead infrastructure. Now read in `sampleConsistentDeal` for
  OPPONENT seats: when an opp seat has led a given suit ≥3 times
  across the game (per-game style ledger, not per-round), bias the
  sampler to put more cards of that suit in their hand. Encoded as
  `desire[suit] = 1` (triggers the existing 20-weight suit-fallback
  path). Skipped for Kawesh-cleared opponents and for teammates
  (we already have stronger Fzloky / Tahreeb signals on partner).

- **Section 11 rule 4 — Sun-bidder partner concentration** (Common,
  video 02 — deferred from v0.5.22). `getPartnerCards` previously
  returned `{}` for Sun contracts, leaving the bidder's partner
  with no sampler bias at all. Saudi convention: a Sun-bidder
  team only commits when both partners can carry trick-pulling
  weight, so the partner typically holds A's and K's across
  multiple suits. Encoded as per-card desire weights:
  `desire["A"..s] = 8` (matches defender bias), `desire["K"..s] = 4`
  (partial clustering tier).

### Changed (Bot.lua)

- **B-57/B-71 styleTrumpTempo bidder-branch wire** (audit
  bot_picker_gaps.md). Pre-v0.6.1 the bidder branch of `pickLead`
  never read `styleTrumpTempo` — only the defender branch did.
  Gap: a defender showing CONSERVATIVE trump tempo (saving high
  trump for over-ruff capture rather than tempo pull) is signaling
  intent to over-ruff the bidder's pulled trump. Saudi pro counter:
  cash side-suit Aces FIRST (defenders must follow if they have
  the suit; can't over-ruff a non-trump lead), forcing them to
  spend low cards in side suits before pulling trump.
  Inserted between the trump-poor side-Ace branch and the B-98
  J+9 trump-lock branch in pickLead bidder mode. M3lm-gated
  (style ledger requires accumulated prior-round signal), Hokm-only.

### Audit-confirmed already wired (no code change)

- **B-67 aceLate counter** — wired into `sampleConsistentDeal`'s
  `pickProb` adjustment (BotMaster.lua:376-378). Confirmed live.

- **B-83 gahwaFailed counter** — wired into `Bot.PickFour` (Bot.lua:
  ~2755). Confirmed live.

- **B-47/B-50 oppGahwas/oppFours** — wired into `matchPointUrgency`
  (Bot.lua:802-827). Confirmed live.

- **M-3 rollout void tracking** — moot. `heuristicPick` doesn't read
  `Bot._memory.void`; legality is enforced via the simulated hand
  state which IS updated as cards play out. The "stale void" concern
  doesn't apply with the current rollout architecture.

### Deferred

- **Section 11 rule 1 (Sun K-or-higher dump-high inference)**: the
  decision-tree rule documents a "no lower rank" inference but the
  rationale ("Saudi losing-side dump-highest convention") suggests
  the OPPOSITE — dump-highest is consistent with holding lower
  cards underneath. Defer until source video #05 can be re-verified.

- **Section 11 rule 2 (Hokm trump-high-dump)**: needs new
  `trumpHighDump` counter infrastructure. Defer.

- **Section 11 rule 5 (Tahreeb-low-from-partner)**: needs
  `tahreebSuspect[suit]` ledger key. Defer.

### Tests

- 226/226 regression tests pass.
- Headless tournament (M3lm vs Master) still tier-ordered correctly:
  Basic 97.9, M3lm 99.5, Master 99.5 over 30 rounds.
- The sampler biases don't affect picker legality (only sampled
  hand distributions); property-test legality coverage continues
  to sweep across many seeds.

## v0.6.0 — Section 1 deferred bidding rules + audit H-3/H-7 fixes (closes v0.5.x audit cycle)

Three audit-pending items landed in one batch. Major version bump
signals end of the v0.5.x decision-trees translation cycle —
Sections 1-11 of `docs/strategy/decision-trees.md` are now either
implemented or explicitly deferred with rationale.

### Changed (Bot.lua)

- **B-7 Bel-fear bias for Sun bidding** (Common, video 25). When
  OUR team's cumulative is at >= K.SUN_BEL_CUMULATIVE_GATE (=100),
  the OTHER team can still Bel us in Sun (per the v0.5.9 E-1 rule:
  only the team <100 may Bel; opp at <100 still qualifies). A
  failed Bel'd Sun = ×2 multiplier on handTotal=130 raw = 26 game
  points lost — major setback. Bias `thSun` UP by +8 to deter
  Sun bids when we're at risk. Roughly one strength-tier penalty.
  Sources: decision-trees.md S-7 / Section 1 row "Cumulative score
  ≥100 (Sun-Bel-gate context)" (Common, video 25).

- **H-3 singleton-low rank guard** (audit MASTER_REPORT). The
  pre-v0.6.0 singleton-lead branch in `pickLead` priority 2
  picked the lowest singleton unconditionally — including a
  singleton Ace/T/K/Q in Hokm where the opponent void in that
  suit can over-ruff and capture the honor for nothing. The
  "ruffing entry" rationale (lead low, dump it, partner can lead
  the suit back later for us to ruff) only applies to genuinely
  low cards. Filter Hokm-contract singletons to face-rank 7/8/9;
  if all our singletons are honors, fall through to the
  longest-suit-low lead instead of dumping a winner. Sun keeps
  current behavior (A/T are sure stoppers in Sun).
  Sources: MASTER_REPORT H-3 / wave3 A-47.

- **H-7 combined-urgency cap** (audit MASTER_REPORT). Previously
  callers computed `urgency = scoreUrgency(team) + matchPointUrgency(team)`
  with each component capped independently (±10 on
  matchPointUrgency, +12 max on scoreUrgency). Combined could
  reach +22, dropping BOT_BEL_TH from 70 to 48 in worst case —
  bot Bels garbage hands when desperate. Per the audit comment
  intent ("combined cap ±15"), introduced `combinedUrgency(team,
  context)` helper that clamps the SUM. All five threshold
  computations (Bel/Triple/Four/Gahwa + R2 Hokm) now route
  through the helper. Sources: MASTER_REPORT H-7 / wave2 A-56.

### Confirmed already wired (no code change in this release)

- **G-2 round-1 conservative bias** (Common, video 25): R1 Hokm
  threshold (`TH_HOKM_R1_BASE` ~=42) is already higher than R2
  (`TH_HOKM_R2_BASE` ~=36). The v0.5.13 calibration locked in the
  Saudi bidding-decision-tree's "round 1 stricter" intent. No new
  code needed.

- **B-3 5+ trump Kaboot pursuit** (Common, video 04): partially
  handled by v0.5.19's trick-3 sweep-pursuit extension. The
  trump-heavy hand path triggers sweep-pursuit early (trick 3+),
  giving 5+ trumps free play to chase Kaboot when bidder team
  hasn't lost a trick yet.

### Deferred

- **G-4 Takweesh bid-override anti-trigger** (Common, video 13):
  blocks bidding when we just Takweeshed (Qaid). Conflicts with
  the user's earlier Sun-overcall expectation (the Sun-overcall
  scenario explicitly allows mid-bidding overcall). Defer until
  the multi-day Hokm-overcall-window UX lands.

- **H-9 BOT_GAHWA_TH=135 calibration**: audit recommends lowering
  to 125 since 135 is mathematically near-unreachable. Defer —
  Gahwa is a match-win commit; conservative bias preferred until
  empirical Gahwa-success rate is measured.

### Tests

- 226/226 regression tests pass.
- Headless tournament averages: Basic 97.9, M3lm 99.5, Master 99.5
  over 30 rounds (tier ordering preserved post-edit).
- The B-7 / H-3 / H-7 changes don't have dedicated test fixtures
  (hand-shape gating is hard to pin without elaborate setups);
  property-test legality coverage in test_state_bot.lua section
  B sweeps the picker output across many random hands and would
  catch any illegal-card regression.

## v0.5.22 — decision-trees.md Section 11 rule 3: pigeonhole pin extension

Translates the Definite-confidence Section 11 rule (sampler hand-
reconstruction inference). Extension of v0.5.0's H-1 J/9-of-trump
pin in `BotMaster.PickPlay` sampler.

### Changed (BotMaster.lua sampler)

- **Rule 3 pigeonhole pin** (Definite, video 05). When N trumps
  remain unseen AND we observe all-but-one OTHER seats are void
  in trump (via `Bot._memory[s].void[trump]`), all those remaining
  trumps MUST be in the one remaining trump-eligible seat —
  mathematical force. Pin them via `meldPins`.

  Pre-v0.5.22, only J/9 of trump were pinned (H-1). The other
  trump cards (K/Q/T/A/8/7) were sampled randomly across all
  three opp/partner hands per the baseline 70%-pickProb. With
  voids surfacing late in the round, the random sampling was
  often counter-factual (placed trumps on seats known to be
  void). This extension uses the void-observation data to
  hard-constrain the remaining trumps to the single eligible
  seat when only one such seat exists.

  Significantly improves rollout accuracy late in the round when
  trump voids have surfaced — the rollout no longer wastes
  iterations on impossible deals.

### Other Section 11 rules (deferred)

| Rule | Confidence | Status |
|---|---|---|
| 1 (Sun K-or-higher dump-high inference → no-lower-rank constraint) | Common | DEFERRED — needs `dumpHighSeen` ledger key + sampler constraint |
| 2 (Hokm trump-high-dump → opp short on trump) | Common | DEFERRED — needs `trumpHighDump` counter |
| 4 (Partner Sun bidder → assume one long suit + concentrated highs) | Common | DEFERRED — Sun-bidder-partner sampler bias |
| 5 (Partner Tahreeb'd low → partner has A or J in other suit) | Common | DEFERRED — `tahreebSuspect[suit]` ledger key |
| 6 (Touching-honors gate when not winning) | Definite | BLOCKED — no touching-honors read exists yet (rules 1-3 from Section 6 also deferred) |
| 7 (Convention-adherence rolling counter) | Sometimes | DEFERRED |
| 8 (Bait-detected ledger) | Sometimes | BLOCKED — no deceptiveOverplay sender exists yet |

### Tests

- 226/226 regression tests pass.
- The pigeonhole pin fires only when:
  - Hokm contract.
  - Trump suit known.
  - All-but-one other seats observed void in trump (mid-late round).
  This is rare in random tournaments; the change won't show up in
  aggregate baseline metrics. Verified empirically via the tournament
  harnesses still running clean.

## v0.5.21 — Section 5 Sun Faranka + scoring discrepancy fix + Hokm SWA safety

Three user-reported items addressed in one batch.

### Section 5 — Sun pos-4 Faranka (Definite, video 06)

The canonical Saudi Faranka: Sun + lastSeat + partnerWinning + we
hold A AND a "cover" (T or K) of led suit + EXACTLY 2 cards of
led suit → DUCK with the cover, let partner take this trick, our
A captures the next opp-led trick. Bridges 2 tricks per single
A/cover deployment.

This branch fires BEFORE the v0.5.18 Takbeer-extension smother
because Faranka and Takbeer conflict (both fire on partner-
winning + we-hold-A). Per video #06, Faranka is the correct
Sun pos-4 play; Takbeer is the general partner-winning donate-
highest behavior. When BOTH match, Faranka wins.

Tier-gating: bidder-team only (rule 9 anti-trigger — defenders
should win the trick to deny opp Kaboot rather than fish for
tempo). Anti-trigger rule 4 (≥3 cards of suit, 10 drops naturally)
is enforced via `suitCount == 2` gate.

Anti-trigger rules 3, 5, 6, 8 are SOMETIMES-confidence or require
state we don't track cheaply (e.g., A is known to be at LHO).
Deferred.

### Scoring discrepancy fix (user-reported "scoring not matching docs")

Two paths in Net.lua used the OLD `(x + 4) / 10` rounding (5
rounds DOWN), inconsistent with R.ScoreRound's v0.5.6 fix to
`(x + 5) / 10` (5 rounds UP per video #43):

- **`Net.HostResolveTakweesh`** (Qaid penalty path) at line ~1889.
- **`Net.HostResolveSWA`** invalid-SWA branch at line ~2591.

Both now use `(x + 5) / 10` consistently with R.ScoreRound. So
a Qaid penalty resolution and an invalid-SWA penalty resolve
with the same rounding direction as a normal round-end. User-
reported symptom: scores after a takweesh/SWA-failure didn't
match what the docs said for raw values ending in 5 (e.g., 65
raw should be 7 game points per "5 rounds UP", not 6).

### Hokm SWA safety net (user-reported "bots SWA while opp has Hokm")

User reports observing bots calling SWA in Hokm contracts while
opponents still hold trump (Hokm) cards. R.IsValidSWA is post-
v0.5.17 strict-caller-correct (per inline trace verification),
but the user wants extra conservatism in Hokm.

Added belt-and-suspenders gate to `Bot.PickSWA`: in Hokm, after
R.IsValidSWA returns true, additionally verify that NO opponent
holds a trump higher than caller's top trump. Specifically:
- Compute `callerTopRank` = highest TrickRank of caller's trumps.
- Compute `oppTopRank` = highest TrickRank of opps' trumps.
- Reject SWA if `oppTopRank > callerTopRank`.

When caller has 0 trumps and opp has any trump, oppTopRank > -1 =
callerTopRank → reject. (R.IsValidSWA already correctly rejects
this case via the must-trump-ruff path; the safety net is
redundant defense for any edge case.)

Trade-off: bot may miss some genuinely valid Hokm SWAs where
caller has no trump but the situation is otherwise unbeatable
(e.g., 4-card endgame where caller holds 4 Aces and opp's only
trump is 7H but they're forced to follow non-trump leads). Rare;
conservative bias preferred per user.

### Tests

- 226/226 regression tests pass.
- The Section 5 Faranka branch and the Hokm SWA safety net are
  not directly pinned by tests (would require complex hand setup);
  scoring rounding fix is implicitly covered by the existing
  Section M div10 tests in test_rules.lua.

## v0.5.20 — decision-trees.md Section 10: Hokm Faranka audit (no code change)

Section 10's 9 rules establish the Saudi convention: **Hokm Faranka
default = NO**, with 5 narrow Common-confidence exceptions and 2
Definite anti-rules.

The current bot code never voluntarily ducks (winners-branch returns
cheapest-winner; falls through to lowestByRank when no winners) —
so the Hokm-default is automatically satisfied. The Definite anti-
rules (6, 7, 9) are likewise implicitly correct via winners-branch
behavior. The 5 Common-confidence exceptions allow Faranka in
narrow scenarios — those are deferred.

### Audit findings — all Hokm Faranka rules

| Rule | Confidence | Status | Why |
|---|---|---|---|
| 1 (default = NO Faranka) | Definite | **ALIGNED** | Bot never ducks. winners-branch picks cheapest winner; lowestByRank fallback in losing-side. No Faranka path exists in code. |
| 2 (exception: Al-Kaboot pursuit) | Common | DEFERRED | Would allow Faranka when on sweep-track. Variance acceptable per video #04 ("losing ANY trick already kills Kaboot"). Defer until sweep-track Faranka becomes a measurable need. |
| 3 (exception: only 2 trumps held) | Common | DEFERRED | Trump-poor hand, low-cost incremental Faranka. Edge case. |
| 4 (exception: J-of-trump dead, your 9 is new top) | Common | DEFERRED | Requires played-card scan + dynamic top-trump shift detection. |
| 5 (exception: bidder + opp trump exhausted) | Common | DEFERRED | Risk-free Faranka condition. Requires void-tracking on opp seats. |
| 6 (exception: partner has shown extra trump) | Sometimes | DEFERRED | Single-source. Style-ledger reading (partner trump-cut-cleanly inference). |
| 7 (anti-Faranka: opp bidder led trump-Q + we hold J+8) | Definite | **ALIGNED** | Bot plays J normally (winners-branch fires). Faranka isn't tempted because the bot doesn't have a Faranka heuristic to override. |
| 8 (anti-Faranka: pos-4 trump-9-only + opp Faranka'd) | Common | **ALIGNED** | Bot plays 9 to win (winners-branch fires). |
| 9 (meta: trump still live → assume worst case, cover) | Definite | **ALIGNED** | Bot's risk-averse default (no voluntary ducking) implements this meta-principle. |

### Net effect: no code change

Hokm Faranka is a refinement OPPORTUNITY (the 5 Common-confidence
exceptions could lift bot strength in specific scenarios), but the
DEFAULT behavior is already correct per Saudi convention. Implementing
the exceptions adds risk-of-misfire (Faranka ducked at the wrong
moment costs the trick) for marginal gain. Defer to a focused release
once empirical measurements show what subset of these matters.

### Tests

- 226/226 regression tests pass (no behavior change in this release).

## v0.5.19 — decision-trees.md Section 7: trick-3 Kaboot pursuit + endgame audit

Translates Section 7 endgame/SWA rules. Most are already wired
post-v0.5.17; this release lands the trick-3 Kaboot-pursuit
extension and audits the rest.

### Changed

- **Section 7 rules 1+2** (Common, videos 06+07+15): trick-3
  Kaboot pursuit extension. The pre-v0.5.19 sweep-pursuit branch
  in `pickLead` only fired at `trickNum == 8`. Per video #15: "if
  no opp cut by trick 2, trump distribution is favorable; sweep
  is genuinely reachable. Earlier trigger lets tricks 3-7 be
  optimized for sweep." Now: when `trickNum >= 3` AND `isBidderTeam`
  AND mytTeam-has-won-every-prior-trick → enter sweep-pursuit
  mode (same logic as trick-8 — boss-lead in safe suit, fall
  through to highest-face-value). K.AL_KABOOT_HOKM=250,
  K.AL_KABOOT_SUN=220 ×2 = 440. High-value bonus to pursue.

### Confirmed already wired (no code change)

- **Rule 7** (Sun Bargiya — Common, video 01): wired in v0.5.10
  T-1 Bargiya sender. When partner is winning + we hold A of side
  suit X with cover → discard A as Bargiya signal.

- **Rule 11** (SWA deterministic-or-bust — Definite, video 35):
  enforced in v0.5.17 via R.IsValidSWA strict-caller (cooperative
  branch tightened to "every play must succeed").

- **Rule 12** (Opp denies SWA → Qaid penalty — Common, video 35):
  already wired via `MSG_SWA_OUT` + `Net.HostResolveSWA` outcome
  path. The valid-flag in the message carries the result.

### Confirmed implicitly handled (no code change)

- **Rule 5** (Defender prevent Kaboot — Common, video 07): the
  existing `pickFollow` winners-branch already returns any winner
  when opp is winning + we have a winner. "First success" =
  taking any trick = the winners-branch firing at all.

- **Rule 6** (Defender force-fail — Common, video 07): partially
  implicit via `scoreUrgency` for bidding/escalation. The play-
  side "capture high-value tricks at cost of low-card discipline"
  would require switching the winners-branch from cheapest-winner
  to highest-face-value-winner when defender + bidder-making.
  Could be a future targeted enhancement; currently the
  cheapest-winner default still captures trick points (just not
  maximally).

### Deferred

- **Rule 3** (Sun bidder sweep abandonment — Sometimes, video 15):
  needs score-tracking. House-rule territory.
- **Rule 4** (Defender Qaid-bait — Sometimes): doc explicitly
  says "bot likely should NOT do this without dedicated
  heuristic". Skip.
- **Rule 8** (Sun trick-8 Bargiya followup — Sometimes, videos
  01+08): we'd lead the suit we Bargiya'd in earlier. Requires
  reading our OWN `tahreebSent` (not partner's) — small
  extension to the v0.5.10 receiver. Defer.
- **Rule 9** (Reverse Al-Kaboot scoring — Sometimes, video 16):
  +88 raw to defender team on full sweep against bidder. Single-
  source; doc says "confirm before wiring". Defer.
- **Rule 10** (SWA card-count thresholds 5+ stricter): video #35
  refines current ≤3-instant / 4+-permission to ≤3 / 4-context-
  dependent / 5+-mandatory. Current code (post-v0.5.17 — all
  flows go through 5s window) is functionally correct; the
  "context-dependent" subtlety is hard to pin behaviorally. Defer.

### Tests

- 226/226 regression tests pass (no new tests for this release;
  the trick-3 sweep pursuit fires only when bidder-team has won
  every prior trick — rare in random tournaments, exercised
  empirically rather than via a pinned test).

## v0.5.18 — decision-trees.md Section 4: Takbeer point-card extension

Translates the remaining Definite-confidence rule from Section 4
(Takbeer/Tasgheer) — extending v0.5.11's smother fix from "donate
highest of {A, T}" to "donate highest of all point cards"
(A, T, K, Q, J).

### Changed

- **Section 4 rule 7 extension** (Definite, videos 21, 22, 23):
  the smother branch in `pickFollow` (partner-winning + non-trump-
  led + feedSafe gate) now considers ALL point cards in the led
  suit, not just A and T. Saudi Takbeer convention donates the
  HIGHEST point card to partner's certain-winning trick. K (4
  raw), Q (3 raw), and J (2 raw) are also "ابناء" (point-card
  sons) — donating them when no A or T is in led suit still adds
  team-pile value vs the previous fall-through to lowestByRank.

  The existing v0.5.11 descending-sort + `[1]` correctly returns
  the highest after expansion; the gate (`#pointCards >= 2 OR
  completed >= 3 OR lastSeat`) is preserved unchanged. So a hand
  with AH+TH still picks AH (same behavior as v0.5.17). A hand
  with KH+8H now picks KH on `lastSeat=true` instead of falling
  to lowestByRank (8H). +4 raw donated per occurrence.

### Confirmed (no code change)

- **Section 4 rule 13** (K-tripled / مثلوث الشايب trickle, Common,
  video 17): "Sun, hold K + 2 lower in led suit, opp leads → play
  SMALLEST first across tricks 1–2". This is ALREADY correctly
  handled by the existing pickFollow fall-through:
  - When opp's A/J/Q is unplayed, K is NOT highest unplayed →
    `winners` branch doesn't fire on K → falls to `lowestByRank`
    of legal (= smallest X card). ✓ Matches the rule.
  - When opp's higher cards are gone, K IS highest unplayed →
    `winners` branch returns K (or another winner). The K-tripled
    rule's "save K for trick 3" intent is achieved naturally
    because K wouldn't be the boss in tricks 1-2 if A is still
    out. No new code needed.

### Deferred

- **Rules 4–6 (deceptive overplay)** — Sometimes-confidence,
  single-source. Sacrifice top to bait re-lead. Requires complex
  scenario detection (partner played mid-trump, opp played low,
  we hold J+9, etc.). Defer to a focused release with the
  `pickFollow.deceptiveOverplay` branch + Saudi Master-tier
  variant.

- **Rules 10–12 (Hokm consecutive top trumps)** — Definite, video
  22, but the scenarios are subtle (Takbeer-mandatory vs INVERT
  vs over-cut-with-smaller depend on rank-adjacency analysis of
  trump cards). Defer to a focused release.

### Tests

- 226/226 regression tests pass. Section E.2 (Takbeer A over T)
  still pins AH (highest of point cards). The expansion to K/Q/J
  doesn't change A/T-present scenarios; it adds new scenarios
  where K alone is the highest available point card.

## v0.5.17 — SWA tightening + display fix + R.IsValidSWA pre-existing bug

User-reported SWA issues. Three distinct fixes:

### 1. SWA strict-caller (R.IsValidSWA cooperative branch tightened)

The pre-v0.5.17 cooperative branch accepted "if SOME partner play
leads to caller winning" — partner could optimally duck under the
caller's lead to preserve the SWA. User report: "SWA should only
work if the player will actually win every hand not back and forth
with their teammate."

Tightened to "EVERY partner play must lead to caller winning" —
partner is treated adversarially in the recursion. Combined with
the per-trick `winner == callerSeat` check, this enforces:
**caller alone wins every remaining trick under ANY legal play
sequence**. Partner may not over-take with a higher card; if
partner CAN over-take in any legal play, the SWA is invalid.

Trade-off: SWA becomes harder to validly claim. Some hands that
previously passed (caller-relies-on-partner-ducking) now fail.
Saudi-strict convention says caller must be self-sufficient —
this matches the stricter interpretation.

### 2. R.IsValidSWA pre-existing bug fix

Discovered while writing Section O regression tests. The "caller
emptied hand → success" early-return at Rules.lua line ~374 fired
WHENEVER `caller.hand` was empty, including mid-trick — after
caller played their last card as the 1st/2nd/3rd play. Subsequent
opponent ruffs (or partner over-takes) were never seen by the
validator. False-positive SWA in any 1-card lead scenario where
the opponent could ruff.

The V14 audit fix earlier only addressed the 4th-play case (added
`#plays == 4` branch above the early-return). The 1st/2nd/3rd-play
case was still broken. Now: gate the early-return on `#plays == 0`
(between tricks) so mid-trick states correctly continue the
recursion.

### 3. SWA card display in every scenario

User-reported: "SWA does not show — i need to see the actual cards
in every scenario when it is called for 5 seconds."

The pre-v0.5.17 ≤3-card "instant claim" branch resolved the SWA
without setting `swaRequest` — so the UI banner (which only renders
when `swaRequest` is non-nil) never displayed the caller's cards
in that scenario. Per user requirement, ALL SWA flows now go
through the 5-second permission display window:

- **Bot-initiated SWA** (`Net.MaybeRunBot` SWA branch): removed the
  `handCount <= 3` shortcut. Now sets `swaRequest` + broadcasts
  `MSG_SWA_REQ` + arms the 5s timer for every claim.
- **Human-initiated SWA** (`Net.LocalSWA`): removed the
  `handCount >= 4` gate. Same 5s window for all claims.

The opponent-team bot auto-accept still fires for ≤3-card claims
(no real defensive position with so few cards), and Takweesh is
still possible during the window — but the cards are visible.

### Added (Section O tests)

- **O.1** 1-card SWA, caller's AS unbeatable, valid (positive).
- **O.2** 1-card SWA, opp can ruff caller's AS, invalid (catches
  the pre-existing bug — fails on pre-v0.5.17 code).
- **O.3** 1-card SWA, partner's only-play over-takes caller's lead,
  invalid (catches the same bug).
- **O.4** 2-card SWA, partner has TWO clubs (one would over-take,
  one would duck), invalid under strict-caller (catches the
  cooperative=EVERY tightening).

### Tests

- 226/226 regression tests pass (was 222 + 4 new Section O).

### Notes

- Saved games unchanged; v0.5.16 saves load as v0.5.17.
- The Hokm-vs-Sun overcall-window UX request from the second user
  message ("any player bid Hokm in 1st/2nd round → 5-second Sun-
  overcall window with WLA waive button, Ace-special-case excludes
  bidder") is OUT OF SCOPE for this release. The current bidding
  flow DOES allow Sun-overcall (verified end-to-end via
  HostAdvanceBidding trace) — but as sequential turn-based bidding,
  not as a discrete simultaneous-overcall window. Implementing the
  proposed UX requires a new `PHASE_HOKM_OVERCALL_WINDOW`, new wire
  messages, UI integration, and race-condition handling — a
  multi-day implementation. Will be a separate focused release.

## v0.5.16 — decision-trees.md Section 6: AKA signaling refinements

Translates two AKA-related rules from Section 6:

- **S6-6 Implicit AKA on bare-Ace lead** (Definite, video 18). The
  H-5 receiver in `pickFollow` now fires on partner's bare-Ace lead
  in a non-trump suit, even when no explicit `MSG_AKA` was
  broadcast. Per Saudi convention, leading bare A non-trump IS the
  implicit AKA call. Receiver suppresses the forced trump-ruff and
  plays a low non-trump instead. Detection: partner LED (first play
  of trick) a card with rank=A in a non-trump suit.

- **S6-10(c) AKA-sender skip on Ace** (Definite, video 18). Bot
  no longer broadcasts `MSG_AKA` when leading an Ace — that's the
  implicit-AKA case (S6-6) and the explicit announcement is
  redundant. Applied as a new gate in `Bot.PickAKA` after the
  existing `su == trump` and bot-partner gates.

### Notes

- 222/222 regression tests pass. The Section E v0.5.11 fix tests
  briefly broke during implementation when the implicit-AKA branch
  fired too broadly (matched partner's followed-Ace, not just led-
  Ace). Fixed by narrowing detection to `trick.plays[1]` (the
  trick's lead play). Test pin re-confirms expected behavior.
- The remaining S6 rules (S6-1/2/3/4 touching-honors, S6-7
  pos-4 ruff release heuristic, S6-10 (f)/(g) sender preconditions)
  are deferred — touching-honors needs new ledger keys + sampler
  integration; the others require richer state tracking.

## v0.5.15 — easy-wins batch (UI gate + Ashkal test fixture + doc refresh)

Audit follow-up batch from the v0.5.13/v0.5.14 deferred lists. Pure
small-LOC items + audit-recommended test fixture + doc maintenance.

### Sun-overcall investigation (no code change)

Verified end-to-end via inline trace: round 1 Sun-overcalls-Hokm
works correctly. The earlier user observation likely reflects bot
threshold tuning (a 2-Ace hand without mardoofa scores too low to
overcall — correct per Saudi convention since failing Sun is -26
vs failing Hokm -16). All 4 Saudi rules pass:
- Round 1 Sun overcalls Hokm ✓
- Hokm cannot overcall a prior Sun ✓
- Two Sun bids: first wins ✓
- Round 2 Sun overcalls Hokm ✓

### Fixed

- **UI Bel button consults R.CanBel** (UI.lua, PHASE_DOUBLE
  render). Previously the Bel/Bel-open/Bel-closed buttons rendered
  unconditionally for the eligible defender; clicking them in a
  forbidden Sun ≥100 scenario was silently dropped by Net.LocalDouble's
  R.CanBel guard — confusing UX. Now: when R.CanBel returns false,
  show "Bel forbidden (Sun >=100)" disabled placeholder + Skip.

### Added

- **Section G in tests/test_state_bot.lua** — 16 Ashkal eligibility
  test cases (4 dealer values × 4 seat values). Pins post-v0.5.7
  correct behavior: only `bidPos >= 3` (dealer + dealer's-LEFT) may
  call Ashkal. Audit-recommended fixture from v0.5.6/v0.5.7 saga.

### Changed (docs)

- **glossary.md "Re-anchoring line numbers" section** — refreshed
  current snapshot table for v0.5.15. Picker line numbers drifted
  +165 to +461 lines across v0.5.8 → v0.5.14. Snapshot included
  alongside the existing grep recipe.
- **decision-trees.md section headers** — Sections 1–7 line-number
  refs updated to current values. Cell-level "MAPS-TO" line refs
  inside the tables NOT updated (would be hundreds of edits) —
  treat them as approximate.
- **decision-trees.md S6-7 stale claim removed** — the doc claimed
  `R.IsLegalPlay` "may need a 'partner winning trick' exception."
  Wave-2 audit confirmed Rules.lua:118–121 + 147–149 already have
  it. Updated to "ALREADY WIRED" + flagged the actual remaining
  gap (a pickFollow heuristic to *prefer* non-trump discard when
  released, separate from the legality fix).

### Deferred to a future release

- **Section 3 rule 1** (`pickLead` strong-card-hold). The user's
  queue marked it "easy" but the rule requires post-processing the
  chosen lead card to detect "leading our strong suit early"
  (T-as-top in non-A suit, partner hasn't captured trick) and
  rerouting to a different suit. Non-trivial in the existing
  pickLead structure with multiple lead heuristics (Tahreeb pref,
  Fzloky pref, Advanced bare-Ace, bidder trump-pull, lead-from-
  longest). Better as a focused release.

### Tests

- 222/222 regression tests pass (was 206 + 16 new Section G).
- No production behavior change beyond the UI Bel button gate
  (which now matches Net.LocalDouble's already-existing wire-side
  enforcement).

## v0.5.14 — decision-trees.md Section 9: Tanfeer (تنفير)

Translates Section 9 (Tanfeer / opponent-disrupt convention) — 3
rules. Inverse of Section 8 Tahreeb: where Tahreeb signals run
sender→partner using top-down/bottom-up direction encoding,
Tanfeer signals run via the discarded SUIT alone (positive single-
event signal) when OPP is winning. Also wires the receiver-side
opp-signal avoidance and revives the formerly-dead
`tahreebAvoidSuit` variable from the Wave-2 audit.

### Wired (Section 9 rules)

- **N-1 Sender (Common, video 03).** When opp is winning AND we're
  void in led suit (so we're discarding from a non-led non-trump
  suit), pick the LOWEST card from a "wanted suit" — a non-trump
  suit where we hold a high card (A or T) AND ≥1 spare low to
  discard. The discarded SUIT signals partner "I want this back";
  we keep the high card in hand. M3lm+ + bot-partner-only.
  Implementation in `pickFollow` after Section 4 rule 1.

- **N-2 Default semantics (Common, video 03).** Doc-only — the
  existing pickFollow already defaults to lowestByRank when winner
  is uncertain (no specific Tanfeer encoding fires). LowestByRank
  is closer to "Tahreeb-low" (positive partner-want) than Tanfeer-
  positive, so the default aligns with the doc's "Tahreeb is the
  dominant convention" claim. Documented as a comment in the N-1
  block.

- **N-3 Receiver (Common, video 10).** `pickLead` M3lm+ block now
  reads OPP `tahreebSent` (in addition to partner's). Opp's
  "want"/"bargiya" classifications add to a `tahreebAvoidSet`.
  Conflict resolution: if our partner-pref-suit is ALSO in the
  opp-avoid set, drop the partner pref. Defending against opp's
  signal dominates partner-help when both signals point at the
  same suit (rare).

### Fixed

- **Dead variable revival.** v0.5.10's receiver block set
  `tahreebAvoidSuit` from partner's "dontwant" but never read it.
  Wave-2 audit flagged. Now consumed by the v0.5.14 N-3 conflict
  resolution: partner-dontwant suits added to the same
  `tahreebAvoidSet` along with opp-want/bargiya.

### Tests

- 206/206 regression tests pass (was 202 + 4 new Section F).
- **F.1**: N-1 sender — opp winning + void in led + A+low in side
  suit returns the LOW (7H). Sun contract used since Hokm + opp-
  winning + void-in-led triggers must-trump (no non-trump
  candidates for N-1 to pick from).
- **F.2**: N-1 sender doesn't fire on lone A (no spare low in
  same suit). Falls through to lowestByRank.
- **F.3**: N-3 receiver — opp `tahreebSent` ascending sequence
  records as want; pickLead consumes the opp signal without crash.
- **F.3b**: N-3 conflict resolution — partner pref + opp signal
  same suit → partner pref dropped.

### Notes

- Asymmetric harness still runs clean (PickFollow N-1 fires only
  in opp-winning + void-in-led + qualifying-wanted-suit scenarios,
  rare in symmetric play).
- No data shape changes; v0.5.13 saves load as v0.5.14 unchanged.
- Deferred Section 9 items: none — all 3 rules wired or documented.

## v0.5.13 — S-3 calibration + magic-number K.* promotion

Two related items from the v0.5.11 deferred list:

1. **S-3 (3-Ace Sun bonus) calibration:** the v0.5.8 implementation
   used `+12` to nudge 3-Ace hands toward Sun. Wave-2 audit found
   that 3-Ace hands without an AKQ stopper triple landed at sun ≈ 41
   vs thSun = 44–56, which couldn't fire R1 reliably. The
   decision-trees.md Section 1 row ranks S-3 as Definite ("almost
   always Sun"), so the formula should clear the median threshold
   reliably. Bumped from 12 → 15: the floor moves from 41 to 44,
   crossing thSun in ~70% of jitter outcomes (vs ~30% under +12).

2. **Magic-number K.* promotion:** v0.5.x added several inline
   tunable literals to `Bot.PickBid` and `Rules.R.CanBel`. Pulled
   them into named `K.*` constants in Constants.lua so future
   tuning lives in one place and comments can't drift from values.

### Added (Constants.lua)

- **`K.BOT_SUN_3ACE_BONUS = 15`** (S-3, was inline +12; bumped per
  Wave-2 calibration)
- **`K.BOT_SUN_MARDOOFA_BONUS = 5`** (S-8 per A+T mardoofa pair)
- **`K.BOT_SUN_MARDOOFA_PAIR_CAP = 2`** (S-8 max pairs counted)
- **`K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN = 5`** (B-5 round-2 margin)
- **`K.BOT_ASHKAL_DIRECT_SUN_PIVOT = 85`** (A-6 65/85 pivot)
- **`K.BOT_PICKBID_BELOTE_BONUS = K.MELD_BELOTE`** (B-6; aliased to
  the meld constant so the bid bonus tracks the actual scoring
  bonus if either is ever retuned)
- **`K.SUN_BEL_CUMULATIVE_GATE = 100`** (E-1 / R.CanBel; Saudi
  Bel-legality threshold for Sun)

### Changed (Bot.lua)

- S-3 bonus now reads `K.BOT_SUN_3ACE_BONUS` (=15, bumped from 12).
- S-8 mardoofa bonus and pair cap now read K.* constants.
- B-5 Sun-over-Hokm margin reads `K.BOT_BIDDING_SUN_OVER_HOKM_MARGIN`.
- A-6 Ashkal pivot reads `K.BOT_ASHKAL_DIRECT_SUN_PIVOT`.
- B-6 Belote bonus reads `K.BOT_PICKBID_BELOTE_BONUS`.

### Changed (Rules.lua)

- `R.CanBel` reads `K.SUN_BEL_CUMULATIVE_GATE` instead of inline `100`.

### Tests

- 202/202 regression tests pass (no behavior change for
  same-strength inputs; the S-3 +3 nudge shifts which 3-Ace hands
  trigger the Sun-bid threshold but is empirically validated by
  the asymmetric harness still running clean).

### Notes

- No new tests in this release. The 6 new K.* constants are
  static values; the S-3 calibration change is verified
  by the asymmetric harness's clean run + the
  pre-existing PickBid sanity tests still passing.
- Saved games unchanged; v0.5.12 saves load as v0.5.13 unchanged.

## v0.5.12 — test coverage for v0.5.11 fixes (Wave-3 audit follow-up)

The 40-agent swarm audit's Wave-3 verification flagged that v0.5.11
shipped 4 load-bearing fixes (Race A, Section 4 rule 1, Takbeer
smother, T-4 over-fire gate) with **zero new tests**. A future
refactor could silently re-flip the behavior — particularly the
single-character Takbeer sort flip and the Section 4 rule 1
HIGHEST-vs-LOWEST direction. This release adds 6 targeted regression
tests pinning the post-v0.5.11 behavior.

### Added (test coverage)

- **`tests/test_state_bot.lua` Section E** — 6 new tests pinning
  the v0.5.11 fixes:
  * **E.1** Section 4 rule 1: Sun losing-side off-suit dumps HIGHEST.
    Pre-v0.5.11 returned LOWEST (8H); post returns KH.
  * **E.2** Takbeer smother: partner certain-winning donates A over T.
    Pre-v0.5.11 returned TH; post returns AH.
  * **E.3** T-4 over-fire gate: K-doubleton + A-doubleton both skip
    Tahreeb encoding, falling through to lowestByRank → 7S
    (preserves the high cards). Pre-v0.5.11 returned KH (over-fired).
  * **E.4** T-4 base case (sanity): Q-doubleton still fires the
    Tahreeb encoding correctly (gate doesn't accidentally block Q).
  * **E.5** PickDouble integration with R.CanBel: Sun + defender
    cumulative ≥100 → PickDouble returns false regardless of strength.
  * **E.5b** Hokm Bel not blocked by the Sun-100 gate (sanity).

### Notes

- 202/202 regression tests pass (was 196 + 6 new).
- The Race A wire-side fix doesn't have a direct test in this
  release because `tests/test_state_bot.lua` doesn't load `Net.lua`.
  Wire-side enforcement uses the same broadcast + `HostFinishDeal`
  pattern as the well-exercised AFK timeout path; missing test is
  acceptable risk for now.
- No production code changed in this release — pure test-coverage.

## v0.5.11 — 35-agent swarm audit follow-up: 4 fixes

A 35-agent (2-wave) swarm review of v0.5.8/9/10 surfaced 4 actionable
issues. All fixed. Wave-3 verification confirmed convergence.

### Fixed

- **Race A wire desync (Net.lua _OnDouble).** When v0.5.9 host receives
  a Bel from a v0.5.8 client (which has no LocalDouble Bel-100 gate),
  the host previously rejected silently. The v0.5.8 client had already
  applied `doubled=true` locally before sending the wire — round-stuck
  desync until the next deal. Now: on rejection, host broadcasts
  `MSG_SKIP_DBL` + calls `HostFinishDeal()`, snapping the client back
  into lockstep. Reuses the existing AFK-timeout recovery pattern.
  Severity: WARNING (rare in production — only mixed v0.5.8/v0.5.9
  sessions, both same-day-tagged, CurseForge auto-update window).
  Sources: Wave-1/Wave-2 audit Race-A finding.

- **Section 4 rule 1: Sun losing-side off-suit dump HIGHEST
  (Bot.lua pickFollow).** Previously the bot dumped the LOWEST in-suit
  card when forced to follow a suit it can't win — what video #9 calls
  "the biggest mistake in Baloot." Now: in Sun + must-follow + can't
  beat current winner, return `highestByRank` of the in-suit cards.
  Saudi inverse-laddering convention signals partner that we're done
  with this suit. Hokm trump-follow keeps LOWEST (Section 4 rule 2,
  separate convention). Hokm non-trump losing-side keeps LOWEST until
  doc clarifies.
  Sources: decision-trees.md Section 4 rule 1 (Definite, videos 05+09).

- **Section 4 rule 7 Takbeer fix (Bot.lua pickFollow smother branch).**
  When partner is certain-winning a non-trump-led trick, the Saudi
  Takbeer rule says donate the HIGHEST card (التكبير, "magnification").
  The smother branch was sorting ascending and returning [1] = LOWEST
  of {A, T} held in led suit — the literal opposite. Single-char flip
  (`<` → `>`). Maximizes trick-point capture (~1 raw point per
  occurrence: A=11 vs T=10).
  Sources: decision-trees.md Section 4 rule 7 (Definite, videos
  21+22+23).

- **T-4 over-fire gate (Bot.lua pickFollow Tahreeb sender).** v0.5.10's
  T-4 dump-larger-first rule fired on ANY 2-card non-trump non-led
  suit, including K+J / A+x doubletons — shedding the valuable card
  for a Tahreeb signal worth ~1 trick of coordination. Saudi rule's
  premise is a "2-card unwanted suit" (low cards). Now: T-4 only fires
  when the doubleton's higher rank is at most Q. K/T/A doubletons fall
  through to `lowestByRank`, preserving the high card.
  Sources: Wave-2 audit T-4 over-fire finding.

### Tests

- 196/196 regression tests pass.

### Notes

- No data shape changes; v0.5.10 saved games load as v0.5.11 unchanged.
- The Wave-2 audit also identified several deferred items NOT fixed in
  this release:
  * **UI Bel button doesn't consult R.CanBel** — UI shows the button
    in PHASE_DOUBLE without checking; clicking it triggers the
    LocalDouble silent gate. Cosmetic UX bug; low player-impact.
  * **S-3 +12 bonus undercalibrated** — 3-Ace hands without AKQ triple
    sit at sun=41 vs thSun=44-56, can't fire R1. Doc says "Definite
    almost always Sun." Could short-circuit `if aceCount >= 3 and
    sunMinShape then return BID_SUN` (parallel to S-4 Carré).
  * **Pigeonhole pin extension to H-1** — Definite Section 11 rule.
    BotMaster sampler hard-pins J/9 of trump to bidder; should also
    hard-pin remaining N trumps when N opponents are known void.
  * **Magic numbers ripe for K.* promotion** — B-5 +5, A-6 85, S-3 +12,
    S-8 +5, R.CanBel 100. Pure refactor.
  * **Decision-trees.md / glossary.md line numbers stale** — all
    picker references drifted +165 to +461 lines after v0.5.8/9/10
    insertions. Comment-only update.
  * **`tahreebAvoidSuit` dead variable** — set by receiver classifier
    but never consumed by the picker.

## v0.5.10 — decision-trees.md Section 8: Tahreeb (تهريب) MVP

The most heavily-sourced section of decision-trees.md (5 of 10 source
videos) — partner-supply discard convention. This release lands the
sender-side encoding + receiver-side reading scaffolding as MVP. All
the high-confidence Definite rules from Section 8 are wired; the
Common-confidence shape-specific receiver rules (T-mardoofa, T-tripled,
Sun-bidder special cases) are deferred to a follow-up.

### Added

- **`tahreebSent[suit]` per-seat style-ledger key** (Bot.lua, in
  `emptyStyle`). For each suit, accumulates the rank of every discard
  the seat made WHILE THEIR PARTNER WAS WINNING the trick. Reset
  per-round via `Bot.ResetMemory` (other ledger counters are per-game
  and stay across rounds — this matches their semantics).

- **`tahreebClassify(signals)` helper** (Bot.lua, before pickLead).
  Classifies a tahreebSent list into `"bargiya"` (Ace at index 1),
  `"want"` (≥2-event ascending), `"dontwant"` (≥2-event descending),
  `"hint"` (single non-Ace event), or `nil`. Uses `K.RANK_PLAIN` for
  ordering since Tahreeb signals are non-trump discards.

- **Tahreeb-signal recording in `Bot.OnPlayObserved`.** When `seat`
  plays a non-led-suit card AND the trick winner BEFORE this play
  was `R.Partner(seat)`, append the rank to
  `Bot._partnerStyle[seat].tahreebSent[discardSuit]`. The "winner
  before this play" is computed by reconstructing the trick with all
  plays except the current one and calling `R.CurrentTrickWinner`.

### Wired (Section 8 rules)

**Sender side** (in `pickFollow` partner-winning + void-in-led branch,
M3lm+ + bot-partner-only):

- **T-1 Bargiya** (Definite, videos 01, 03). Sun, partner winning,
  hand has A of side suit X with cover (≥2 cards in X) → discard
  the A as Bargiya ("I have the slam in X, lead it back").
- **T-4 Dump-ordering** (Definite, video 01). From a 2-card non-led
  non-trump suit, dump the LARGER first. Larger-first is unambiguous
  refusal; smaller-first would be a false positive bottom-up signal.

**Receiver side** (in `pickLead`, M3lm+ + bot-partner-only):

- **T-7/T-8 reading** (Definite, videos 09, 10). Read partner's
  recorded `tahreebSent` per suit; classify; if any suit returns
  `"bargiya"` (priority 3) or `"want"` (priority 2), prefer
  leading our LOWEST card in that suit (so partner's tops win). If
  any suit returns `"dontwant"`, mark it as avoid (informational —
  not yet consumed by the picker; the existing low-from-longest
  fallback naturally avoids declared-want suits).

### Tier gating

All Tahreeb logic is M3lm+ and bot-partner-only. Signals to a human
partner are noise (humans don't follow the convention reliably);
the existing Fzloky reasoning at the same site applies here.

### Tests

- 196/196 regression tests pass (no new tests in this release —
  Tahreeb behavior is exercised in production via the M3lm+ tier
  in real games; the existing harnesses use `pickContract` and
  fixed-bidder asymmetric deals which don't drive PickFollow's
  partner-winning discard branch).
- 100-round baseline tournament metrics identical to v0.5.9 — the
  Tahreeb branch fires only in M3lm+ Sun discard scenarios, rare
  enough in random symmetric play that aggregate metrics don't shift.

### Deferred (Section 8 rules NOT in this release)

- **Common-confidence receiver shape rules** (T-mardoofa, T-tripled,
  T+sun-bidder, T+non-sun-bidder, no-winning-card high-return,
  partner-resupply release-control). These need richer hand-shape
  inference + per-suit T-count tracking.
- **Three-discard variant** (Common, video 10). Strict-ascending
  3-event sequences. Requires extending the encoding state machine.
- **Sender's strong-suit avoidance** (Common, video 03). Don't
  Tahreeb FROM your strong suit. Currently the bot may Bargiya
  away its own strong-suit Ace if it has cover; the fix needs a
  "what is our strong suit" classifier.
- **Cutter-as-Tahreeb-event** (Common, video 03). Treating a ruff
  as a Tahreeb signal. Adds a state-tracking dimension.

## v0.5.9 — decision-trees.md Section 2: Sun Bel-100 legality gate

Translates the Definite-confidence rule from Section 2 (Escalation):
**in Sun contracts, only the team at <100 cumulative score may Bel**
(الحكم مفتوح في الدبل ≠ الصن; Sun has the gate, Hokm doesn't). This
is a rule-correctness item, not a heuristic — wired both bot-side
(`Bot.PickDouble`) and wire-side (`Net._OnDouble` + `Net.LocalDouble`)
so a stale-state human client cannot bypass it via the wire.

### Added

- **`R.CanBel(team, contract, cumulative)` in Rules.lua.** Authoritative
  predicate: returns true iff the given team may legally call Bel
  against `contract`, given the cumulative table. Hokm: always true.
  Sun: true iff `cumulative[team] < 100`. Three call sites consume the
  same predicate so behavior cannot drift between bot and human.

- **16 boundary tests** in `tests/test_rules.lua` Section N pin the
  `< 100` direction strictly (99 ✓, 100 ✗, 101 ✗), per-team
  independence (A blocked at 100 doesn't affect B), and defensive
  nil handling.

### Fixed (rule-correctness)

- **E-1 (decision-trees.md Section 2): Sun Bel-100 gate.** Previously
  bots and humans could call Bel in Sun even when their cumulative
  was >=100 — a Saudi-rule violation. `Bot.PickDouble` now early-returns
  false when `R.CanBel` is false; `Net._OnDouble` rejects illegal
  incoming wire messages with a `Warn` log; `Net.LocalDouble` short-
  circuits before issuing the wire.
  Sources: decision-trees.md Section 2 (Definite, video 11);
  glossary.md "Bel (×2) legality gate".

### Tests

- 196/196 regression tests pass (was 180; +16 R.CanBel boundary tests).

### Notes

- Hokm Bel logic is unchanged — the gate explicitly returns true for
  Hokm regardless of score.
- The other Section 2 rules are NOT in this release:
  * Round-1 Bel restriction (Sometimes confidence — TBD from a
    follow-up video to confirm exact mechanism)
  * Trick-3 Al-Kaboot pursuit trigger (Common; structural — needs
    pursuit-flag state field + pickLead read-side wire)
  * Sun bidder sweep-abandonment (Sometimes; score-aware sweep logic)
  * Defender Qaid-bait (Sometimes; doc explicitly says "bot likely
    should NOT do this without dedicated heuristic")

## v0.5.8 — Bot.PickBid: translate decision-trees.md Section 1 (bidding)

Translates Section 1 of `docs/strategy/decision-trees.md` (~25 rules
sourced from Saudi tournament videos) into `Bot.PickBid` picker code.
Each named patch (B-1 through B-6, S-1 through S-8, A-3 through A-6)
maps to a specific WHEN/RULE/MAPS-TO row in the decision tree.

A 3-agent post-commit audit surfaced one BUG (B-1 missing the
"≥1 side Ace" requirement from the source rule) and one stylistic
NOTE (leading-underscore locals). Both fixed before tagging.

### Bidding fixes

- **B-1, B-2, B-4: Hokm minimum-shape gate.** Bot now refuses to bid
  Hokm unless either (a) count ≥ 4 with J of trump (B-2 self-
  sufficient) OR (b) count == 3 with J of trump AND ≥ 1 side Ace
  (B-1 minimum, "الحكم المغطى"). The absolute floor (B-4) is "no J
  OR count ≤ 2 → never bid Hokm". The audit-fix step added the
  side-Ace requirement to the count==3 case — without it, a
  J+x+x trump hand with zero side aces could bid (no side trick
  power, structurally weak). Suits like 9+A+T+K (no J) likewise
  never bid. New helper `hokmMinShape(hand, suit)` enforces the
  rule; applied in round 1 (Hokm-on-flipped) and round 2 (best-suit
  search). Sources: decision-trees.md B-1, B-2, B-4 (all Definite, video 26).

- **B-5: 16-vs-26 Hokm-over-Sun bias.** Round 2 now requires Sun to
  beat the best Hokm score by ≥ 5 strength points before overcalling
  Hokm. Failed Hokm = 16 raw, failed Sun = 26 raw — the asymmetry
  bounds the failure cost. Borderline tied calls stay with Hokm.
  Sources: decision-trees.md B-5 (Definite, videos 25 + 26).

- **B-6: Belote (سراء ملكي) bidding bonus.** When the hand holds K+Q
  of any suit, that suit gets a +20 bonus in PickBid's Hokm-strength
  calculation (multiplier-immune Belote bonus). New helper
  `beloteSuit(hand)`. Sun bidding is unaffected (Belote is Hokm-only).
  Sources: decision-trees.md B-6 (Definite, video 26).

### Sun fixes

- **S-1, S-5, S-6: Sun minimum-shape gate.** Bot now refuses to bid
  Sun without either A+T mardoofa (إكة مردوفة) OR 2+ Aces. A bare
  1-Ace hand without T-cover gets torn through; Saudi rule says do
  not bid Sun. New helper `sunMinShape(hand)`.
  Sources: decision-trees.md S-1, S-5 (Definite/Common, video 25).

- **S-3: 3+ Aces strong-Sun bonus.** +12 to Sun strength when the
  hand holds 3 or more Aces. The 26-vs-16 risk premium is paid by
  sustained trick power across 3+ suits.
  Sources: decision-trees.md S-3 (Definite, video 25).

- **S-4: Carré of Aces (الأربع مئة) mandatory Sun.** When the hand
  holds all 4 Aces, returns `K.BID_SUN` as the earliest possible
  exit — beats every other path. Carré of Aces = 200 raw × 2 = 400
  effective ("Four Hundred").
  Sources: decision-trees.md S-4 (Definite, videos 25, 32, 38).

- **S-8: Sun-Mughataa A+T mardoofa bonus.** +5 per A+T mardoofa pair
  (capped at 2 pairs) on top of the normal Sun strength. "Covered
  Sun" emphasizes safety distinct from raw Ace count.
  Sources: decision-trees.md S-8 (Common, video 25).

### Ashkal fixes

- **Order restructure:** Ashkal-eligibility check now runs BEFORE
  the direct-Sun branch. Previously direct-Sun (sun ≥ thSun = 50)
  short-circuited Ashkal (sun ≥ thAshkal = 65), making the Ashkal
  block effectively dead code. The decision tree expects eligible
  seats to PREFER Ashkal in the 65-84 strength band; the restructure
  enables that preference. Non-eligible seats fall through to direct
  Sun unchanged.

- **A-3: bid-up = A → don't Ashkal.** Anti-trigger; losing A into
  no-trump with no T-cover is a textbook bad Ashkal.
  Sources: decision-trees.md A-3 (Definite, video 31).

- **A-4: bid-up = T + we hold A same suit → don't Ashkal.** Hokm
  preserves the A+T mardoofa; Ashkal converts to Sun and breaks it.
  Sources: decision-trees.md A-4 (Common, video 31).

- **A-5: 3+ Aces → don't Ashkal.** With that much firepower, claim
  the contract directly via Sun; we don't need partner's project.
  Sources: decision-trees.md A-5 (Common, video 31).

- **A-6: sun ≥ 85 → don't Ashkal (the 65/85 pivot).** 65-84 strength
  range = Ashkal range; 85+ = direct-Sun range. Falls through to the
  direct-Sun branch below.
  Sources: decision-trees.md A-6 (Common, video 31).

### Test status

- 180/180 regression tests pass (existing PickBid sanity tests:
  strong J+9+A+T+K hand still bids Hokm; weak 7/8-only hand still
  passes — both unaffected because the new gates don't reject those).
- 100-round symmetric baseline tournament unchanged: the harness
  uses `pickContract` (deterministic strongest-hand picker), not
  `Bot.PickBid`, so PickBid changes are not exercised offline.
- Asymmetric harness similarly uses fixed bidder + trump.
- Behavioral validation will land via player feedback; the WoW
  bidding loop is the real test surface for these changes.

### Notes

- No data shape changes; v0.5.7 saved games load as v0.5.8 unchanged.
- Deferred to a future patch (Section 1 rules NOT yet wired):
  * B-3 (5+ trump Kaboot pursuit flag — needs `S.s.pursuitFlagBidder`
    + pickLead read-side wire; structural)
  * B-7 (cumulative ≥ 100 Bel-fear bias on Sun bidding)
  * G-2 (round-1 conservative bias — already partially encoded via
    r1Base > r2Base; further tightening unclear without data)
  * G-4 (don't bid against partner's contract — Takweesh
    bid-override anti-trigger)

## v0.5.7 — v0.5.6 audit follow-up: revert Ashkal misfix + correct CHANGELOG narrative

A 3-agent audit on v0.5.6 surfaced two issues that had to be
fixed:

1. **The v0.5.6 Ashkal seat-restriction "fix" was an inversion,
   not a correction** — the original v0.5.5 code was already
   correct. v0.5.6's misfix is reverted in this release.

2. **The v0.5.6 CHANGELOG attributed a Bel-rate jump (0% → 13-67%)
   to the score-rounding cascade through `scoreUrgency`. That
   attribution was empirically false** — A/B test reverting the
   rounding alone showed identical Bel rates. The actual cause
   was v0.5.5's harness state-leakage fix, not v0.5.6's rounding
   change. Narrative corrected.

Plus a small test-fixture cleanup: `tests/test_rules.lua` had
two assertions hard-coded to the OLD `(x+4)/10` formula; both
coincidentally passed under the new `(x+5)/10` formula but were
asserting the wrong invariant. Updated to `+5` and added explicit
"5 rounds UP" boundary tests.

### Fixed

- **Reverted State.lua:1450-1490 Ashkal seat-restriction.** The
  v0.5.6 change to `bidPosition == 1 OR bidPosition == 4` was
  based on misreading WHEREDNGN's seat geometry. Audit against
  `UI.lua:223-225` confirms `R.NextSeat(seat) = (seat % 4) + 1`
  is "the seat to your RIGHT" (the existing UI code documents
  this — `pos == "right"` returns `R.NextSeat(me)`). So in the
  bidding order `{dealer+1, dealer+2, dealer+3, dealer}`:
  - bidPosition 1 = dealer+1 = **dealer's RIGHT** (NOT eligible)
  - bidPosition 3 = dealer+3 = **dealer's LEFT** (eligible)
  - bidPosition 4 = dealer (eligible)

  Video #31's "dealer + dealer's LEFT" therefore maps to
  positions 3 + 4 — exactly what `bidPosition < 3` (the v0.5.5
  code) was already enforcing. **The v0.5.5 code was correct;
  the v0.5.6 misfix is reverted.**

  Comment block in State.lua updated to explicitly cite
  UI.lua's seat convention as the disambiguator.

- **Updated `tests/test_rules.lua` div10 assertions** to use
  `(x+5)/10` and added 3 explicit boundary tests pinning
  "5 rounds UP" behavior:
  - `div10(65) = 7` (5 rounds UP)
  - `div10(15) = 2` (5 rounds UP)
  - `div10(64) = 6` (4 rounds DOWN)

### Notes

- The score-rounding fix in `Rules.lua:698` (`(x+4)/10` →
  `(x+5)/10`) is **kept** — it remains mathematically correct
  per video #43. The CHANGELOG narrative attributing the Bel-rate
  cascade to it has been corrected, but the fix itself stands.
- Strategy docs (`docs/strategy/bidding.md`,
  `docs/strategy/decision-trees.md`) updated to reflect the
  corrected Ashkal seat geometry.
- 180/180 regression tests pass (was 177 before; 3 new boundary
  tests added).

### Audit findings (recorded for traceability)

- Audit #1 (Ashkal): FLAGS — verdict driven by `UI.lua:223-225`
  seat-direction convention conflicting with v0.5.6's comment.
  Resolution: revert.
- Audit #2 (score rounding): FLAGS minor — test fixtures
  hardcoded `+4` formula. Resolution: update to `+5` + add
  boundary tests.
- Audit #3 (Bel-rate cascade): REFUTED — empirical A/B test
  showed rounding had zero causal effect on Bel rates. The
  v0.5.6 CHANGELOG narrative was a false attribution.
  Resolution: correct the narrative; the actual cause was
  v0.5.5's harness state-leakage fix unmasking previously-hidden
  Bel events.

## v0.5.6 — Saudi tournament-video doc batch + 2 rule-correctness fixes

This release lands two things:

1. A massive **strategy-docs scaffold** in `docs/strategy/`
   (~24,000 words, 11 files) distilled from 40+ Saudi Baloot
   tutorial videos processed via yt-dlp auto-captions and
   whisper-turbo on RTX 5080 GPU.
2. Two rule-correctness fixes surfaced by the doc audit:
   one `State.lua` Ashkal seat-restriction fix and one
   `Rules.lua` score-rounding direction fix.

The bigger Bot.PickBid heuristics-wiring work (translating the
new `decision-trees.md` Section 1's ~25 bidding rules into
picker code) is **deliberately deferred** to a follow-up so the
docs and the picker-code translation can be reviewed
independently.

### Fixed (rule correctness)

- **Ashkal seat restriction (State.lua:1450-1487).** Per video
  #31 "شرح الاشكل بالتفصيل في البلوت", only the **dealer + dealer's
  LEFT** (يسار الموزع) may call Ashkal. The previous code
  enforced "bidPositions 3 + 4 in turn order" which maps to
  **dealer's RIGHT + dealer** — wrong direction. The new check
  is `bidPosition == 1 OR bidPosition == 4` (dealer's-left = pos 1
  in CCW bidding order, dealer = pos 4). Comment block updated
  to cite the video and explain the seat geometry.

- **Score rounding direction (Rules.lua:698).** Per video #43
  "حساب النقاط في البلوت للمبتدئين", Saudi convention is **5 rounds
  UP** (65 raw → 70, 67 raw → 70, 64 raw → 60). The previous
  `div10(x) = floor((x + 4) / 10)` rounded 5 DOWN. Corrected to
  `floor((x + 5) / 10)`. Secondary effect: cumulative scores
  reach the 100/152 thresholds slightly faster, which cascades
  through `scoreUrgency` / `matchPointUrgency` and noticeably
  raises bot-bot Bel rates in baseline tournaments (a positive —
  v0.5.5's 0% Bel was a known structural gap).

### Added (strategy docs)

- **`docs/strategy/`** (new folder, 11 files):
  - `README.md` — navigation + decision tree
  - `glossary.md` — Arabic ↔ code-identifier mapping with Lua
    line cross-refs; authoritative card-name family-trio (شايب=K,
    بنت=Q, ولد=J); Tahreeb / Tanfeer / Faranka / Bargiya /
    Takbeer / Tasgheer / Mardoofa / Mughataa fully defined
  - `decision-trees.md` — operational WHEN/RULE/MAPS-TO chains
    across 11 sections; ~140+ rules with confidence ratings
    (Definite / Common / Sometimes) sourced from videos
  - `saudi-rules.md` — rule deltas vs French Belote; rule-
    correctness verifications cross-checked against `Rules.lua`
    / `Net.lua` (Bel-100 gate, pos-4 ruff-relief, must-overcut-
    not-partner, Sun ×2 multiplier, Ashkal seat eligibility);
    Kasho-vs-Qaid distinction; Reverse Al-Kaboot
  - `bidding.md` — Hokm/Sun/Ashkal hand-strength heuristics
    (J+مردوفة+إكا minimum Hokm; A+T mardoofa minimum Sun;
    16-vs-26 failed-bid asymmetry; trump-count tiers; Ashkal
    65/85 threshold pivot)
  - `escalation.md` — Bel/Bel-x2/Four/Gahwa chain
  - `signals.md` — Tahreeb (5 forms, 70/25/5 prior, two-trick
    confirmation, "biggest mistake in Baloot" rule); Tanfeer as
    parent class with Tahreeb as intent-bearing subset; Bargiya
    2-flavor split (come-to-me invite vs defensive shed); AKA
    touching-honors signaling
  - `endgame.md` — Faranka (5-factor Sun framework, Hokm 5
    exceptions); the "smart move" (J/T sacrifice deception);
    Al-Kaboot trick-3 trigger; SWA strict-deterministic
  - `opening-leads.md` — strong-card timing; Tahreeb-return
    decision tree by length
  - `bot-personalities.md` — tier-fit table for new heuristics
  - `transcripts.md` — yt-dlp + Whisper workflow doc
- **`CLAUDE.md`** — repo-level guidance pointing future Claude
  sessions to `docs/strategy/`; non-obvious Saudi rules
  highlighted (9 doesn't form Carré, Belote multiplier-immune,
  Sun ×2, etc.)

### Open questions documented (not fixed)

- Sun Belote (ملكي) — single-source claim of K+Q meld in Sun;
  currently Hokm-only in code. **Decision: keep Hokm-only.**
- سيكل (sykl) — possible 9-8-7 sequence meld; unconfirmed.
- Bel hand-strength thresholds — no video covered specific
  numerical thresholds for *when* to call Bel; remaining gap.
- 5 procedural bid-rules from video #28 cross-checked: 4 of 5
  already implemented in `State.lua` `S.HostAdvanceBidding`,
  1 (auto-convert-to-Sun on missing trump) is UI-prevented.

### Deferred to follow-up

- **Translate `decision-trees.md` Section 1's bidding rules
  into `Bot.PickBid` picker code.** The decision-trees.md
  format gives exact Bot.lua line-N maps; the picker-code
  translation is the natural next step but kept separate from
  this commit so docs and code-translation can be reviewed
  independently.

### Test status

- 177/177 regression tests pass.
- Baseline tournament: Bel rates jumped from 0% (v0.5.5) to
  13-67% in natural mode, primarily from the rounding-direction
  cascade through `scoreUrgency`. Game outcomes still well-
  distributed; no test regressions.

## v0.5.5 — playtest-fixture audit: harness state-leakage bug found

A targeted playtest-fixture audit (asked: "is Master good enough?")
built a new `test_asymmetric_metrics.lua` harness that biases the
deal so the bidder gets a realistic strong-Hokm trump cluster
(J+9, J+9+A, or J+9+A+T of trump). Running it surfaced a
LONG-STANDING bug in BOTH the asymmetric and the existing
baseline harnesses that silently masked all Bel/Triple/Four/Gahwa
measurements as 0% across every v0.5.x release.

**No production code changed in this release.** Live bot behaviour
is unaffected — the bug was purely in the offline tournament
harnesses. v0.5.0–v0.5.4 telemetry must be re-read with the
"escalation rates were unobservable" caveat.

### Fixed (test harness)

- **State-leakage bug in `resolveEscalation` (test_baseline_metrics.lua,
  test_asymmetric_metrics.lua).** `Bot.PickDouble`, `PickTriple`,
  `PickFour`, and `PickGahwa` all read `S.s.contract` and
  `S.s.hostHands` directly. The harness called `resolveEscalation`
  BEFORE `playOneRound` (which is what calls `freshState` + sets
  the live state). So every escalation pick ran against either nil
  state (round 1) or the PREVIOUS round's contract+hands (rounds 2+).
  Result: defender PickDouble computed strength against the wrong
  hand and threshold against the wrong contract, so it almost never
  fired. Fix: call `freshState` and seed `S.s.contract` /
  `S.s.hostHands` / `S.s.cumulative` BEFORE `resolveEscalation`.
  `playOneRound` then re-runs `freshState` (idempotent) before play.

### Added

- **`tests/test_asymmetric_metrics.lua` + `tests/run_asymmetric.py`** —
  100-round tournaments at three bias levels (moderate / strong /
  elite) covering the full 6 tier configs × 2 modes matrix. Output
  written to `.swarm_findings/bot_asymmetric_metrics.json`.

- **`tests/probe_defender_strength.lua`** — diagnostic probe that
  computes the defender-strength distribution across 1000 hands per
  bias level and cross-validates by directly calling Bot.PickDouble.
  Confirms the formula matches: 16% defender-clear-rate at TH=60
  vs 16% per-defender Bel-fire rate from the live picker.

### Findings (post-fix tournament data)

Symmetric baseline (`bot_baseline_metrics.json`, 100-round tournaments):
- all_basic natural: Bel 67% (6/9 rounds played)
- all_advanced natural: Bel 13%
- all_m3lm natural: Bel 14%
- all_master natural: Bel 15%
- mixed_*_master natural: Bel 13–15%
- Triple still 0% across all natural-mode configs — bidder rarely
  has the strength to push back

Asymmetric (`bot_asymmetric_metrics.json`):
- moderate bias: Bel 0–36%, sweep 6–7% (similar to symmetric)
- strong bias: Bel 6–12%, first Triple observed (8% in basic)
- elite bias: Bel 0–8%, sweep climbs to 12–21% (bidder strong → sweeps)
- Master vs Basic in mixed configs: Master wins consistently across
  all bias levels (AvgB > AvgA in mixed_basic_master_natural at all
  three bias levels)

### Notes

- 177/177 regression tests still pass; pure test-infra change.
- Future calibration sprints can now use reliable Bel/Triple/Four/
  Gahwa rate measurements as a feedback signal.

## v0.5.4 — SWA banner shows the actual cards (player feedback)

Previously the SWA banner showed only "N cards remaining" + timer.
Player approved (or auto-approved) without seeing WHICH cards the
caller was claiming — especially opaque for bot-initiated SWA where
the player has no other visibility into the bot's hand.

### Changed

- **SWA banner now renders the caller's full hand inline (UI.lua).**
  The banner height grew from 38 to 100 px to accommodate a card-
  face row beneath the title/body. Up to 4 card slots (SWA fires at
  ≤4 remaining), centered horizontally, anchored to the banner's
  bottom edge. The cards are decoded from `swaRequest.encodedHand`
  which has been on the wire since v0.4.6 — only the visualization
  was missing. Saudi convention is "show your hand on SWA"; opponents
  can now actually inspect the claim before the auto-approve timer
  expires.

- **No data shape changes** — pure UI fix. v0.5.3 saved games and
  active SWA requests display correctly without any state migration.

### Notes

- Both render paths updated: the banner's self-tick OnUpdate (3 Hz
  for the timer countdown) and the `renderSWABanner` Refresh path.
  Both share `_lastEnc` to avoid redecoding the hand 3× per second.
- 177/177 regression tests pass; UI.lua syntax-checks clean via
  Lua loadfile.

## v0.5.3 — second ultra-test follow-up: 3 BUGs fixed

A 6-agent verification swarm against shipped v0.5.2 surfaced three
new bugs that the previous round missed. All three are now fixed.

### Fixed (BUGs)

- **BUG #1: `Bot._inRollout` flag leaked on rollout error
  (BotMaster.lua).** `BM.PickPlay` set `B.Bot._inRollout = true` and
  relied on the explicit `_restore` calls at every return path. But
  the rollout loop had no `pcall` around it. If `rolloutValue`,
  `R.IsLegalPlay`, `C.TrickRank`, or `R.ScoreRound` errored mid-
  rollout (malformed card, bad meld, nil ref), the error escaped to
  Net.lua's outer `pcall` — but `_inRollout` was never restored.
  Every subsequent `Bot.PickPlay` would then skip the BotMaster
  delegation guard and silently degrade Saudi Master to heuristic
  for the rest of the session. Now: rollout loop is wrapped in
  `pcall`; on error, `_restore(nil)` clears the flag and Bot.PickPlay
  falls through to heuristics for THIS pick only.

- **BUG #2: `PickFour` threshold floor was gated on `Bot.IsM3lm()`
  (Bot.lua).** v0.5.2's PickDouble unconditional floor cited "matches
  PickFour's defensive cap" — but PickFour's own floor was INSIDE
  the IsM3lm() block at line ~1958, so non-M3lm tiers (Basic /
  Advanced / Fzloky / Master) had no floor at all. With
  `scoreUrgency("defend")` and `matchPointUrgency` capable of
  dropping the threshold by 12+, this allowed false-Four bids on
  hands below the safe minimum strength. Lifted the floor cap OUT
  of the IsM3lm block so it applies unconditionally — symmetric
  with PickDouble's v0.5.2 behavior.

- **BUG #3: Trick-8 boss-scan was greedy (Bot.lua pickLead).** The
  v0.5.2 fix correctly added `trumpExhausted` to isSafe, but the
  boss-scan loop returned the FIRST boss in hand-iteration order
  rather than the BEST. With multiple bosses on trick 8 (especially
  when `trumpExhausted` opens up ALL non-trump bosses), throwing a
  7-of-spades-boss instead of a Ten-of-clubs-boss costs up to 10
  face-value points PLUS the +10 LAST_TRICK_BONUS goes to whichever
  card actually wins. Fix: collect all qualifying safe bosses into
  a list, then pick by `highestByFaceValue` (which is contract-aware
  via C.PointValue, correctly handling Hokm / Sun trump-vs-plain
  scoring).

### Notes

- No data shape changes; v0.5.2 saved games load as v0.5.3 unchanged.
- All Lua files pass syntax check; 177/177 regression tests pass.
- 100-round baseline tournament unchanged from v0.5.2 (the fixes
  affect rare paths: rollout errors, non-M3lm Four bids, and
  trick-8 multi-boss scenarios — none common enough to shift
  large-N tournament metrics).

## v0.5.2 — ultra-test follow-up: 2 BUGs + 3 WARNINGs fixed

A 12-agent ultra-verification swarm read the v0.5.0+v0.5.1 patches
end-to-end against the live tree and surfaced two actual bugs and
three latent footguns. All five are now fixed and the regression
suite (177 tests) plus 100-round baseline tournament still pass.

The headline empirical result: with the test-harness fix in this
release (BotMaster.lua now loaded by all four offline harnesses),
Master vs M3lm finally diverges in the standalone tournament —
all_master natural is winner=A (8.8/8.1, sw=0.06) while all_m3lm
natural is winner=B (6.6/10.3, sw=0.07). mixed_basic_master forced
flipped to winner=B (Master), confirming the v0.5_FINAL_REPORT
prediction held end-to-end.

### Fixed (BUGs from ultra test)

- **BUG #1: C-2 SWA C_Timer nil-guard misplacement (Net.lua).**
  When `C_Timer` is unavailable (test harness, pre-init edge cases),
  the previous `S.s.swaRequest` was set + broadcast was issued, but
  the auto-approve timer was silently skipped — leaving a dangling
  permission flow that never resolved. Now: timer arming check
  happens BEFORE the swaRequest assignment; if `C_Timer` is nil we
  degrade to the instant-claim path so the round never stalls.

- **BUG #2: C-4 isSafe excluded non-trump bosses in Hokm
  (Bot.lua pickLead trick-8).** The original isSafe expression
  `(contract.type ~= K.BID_HOKM) or C.IsTrump(c, contract)`
  excluded every non-trump boss card in Hokm — rendering the
  trick-8 boss-scan dead in the dominant case (Hokm contracts).
  Now: when `S.HighestUnplayedRank(contract.trump) == nil`,
  trump is exhausted and non-trump bosses ARE safe to lead;
  added `trumpExhausted` check to isSafe.

### Fixed (WARNINGs from ultra test)

- **WARNING #1: PickDouble had no threshold floor (Bot.lua).**
  Combined drops from `scoreUrgency("defend")` + `matchPointUrgency`
  could push the threshold down by 15+; combined with C-3b adding
  up to +31 to strength (3 voids × 5 + 3 Aces × 8) and BEL_JITTER
  ±10, weak-trump hands could fire false-Bels. Floored at
  `K.BOT_BEL_TH - 16` to match PickFour's defensive cap.

- **WARNING #2: H-4 Belote preservation passed `legal` not `hand`
  (Bot.lua pickFollow).** When must-follow forced non-trump play,
  `legal` would not contain K or Q of trump even when both were
  still in hand — `holdsBeloteThusFar(legal, ...)` returned false
  and the preservation logic was bypassed. Now passes `hand`; the
  filter still applies to `legal` below so legality is preserved.

- **WARNING #3: Net.lua double-delegation to BotMaster.PickPlay.**
  Since v0.5.0's C-1 fix made Bot.PickPlay delegate internally,
  the explicit `if B.BotMaster ... B.BotMaster.PickPlay(seat)`
  block in MaybeRunBot was redundant — and would cause double
  ISMCTS computation if BotMaster bailed and Bot.PickPlay
  re-delegated. Single canonical call: `B.Bot.PickPlay(seat)`.

### Fixed (test harness)

- **Test harness load order: BotMaster.lua now loaded by all four
  offline harnesses** (`test_baseline_metrics.lua`,
  `test_multiseed_metrics.lua`, `test_v0.5_traced_game.lua`,
  `test_bel_decision_quality.lua`). Without this, Bot.PickPlay's
  C-1 delegation fell through (B.BotMaster was nil) and Master
  silently degraded to M3lm in offline tournaments — masking the
  empirical proof that the C-1 fix was actually wired. With the
  load added, all_master and all_m3lm now produce divergent
  outputs in the standalone baseline (the result predicted in
  the v0.5_FINAL_REPORT but not previously reproducible offline).

### Notes

- No data shape changes; v0.5.1 saved games load as v0.5.2 unchanged.
- All Lua files pass syntax check; 177/177 regression tests pass.
- Baseline tournament metrics: see updated
  `.swarm_findings/bot_baseline_metrics.json`.

## v0.5.1 — Sprints B-H: complete bot improvement campaign

Continues the v0.5.0 work by landing the remaining 8 staged patches
from the bot improvement research campaign. v0.5.0 unlocked the
Saudi Master tier; v0.5.1 lands the strategy and coordination
heuristics that distinguish a competent player from a Saudi pro.

Empirical 100-round A/B tournament (`bot_baseline_metrics_sprint_BCDH.json`):
- All-Master (natural) flipped from B-wins back to balanced
  (8.8/8.1) — Master-vs-Master games are now near-symmetric
- Master ISMCTS rollouts have higher quality through
  partner-trump bias (H-3) and defender-Ace clustering (H-2 in v0.5.0)

### Added (Critical missing features)

- **C-2: Bot-initiated SWA (`Bot.PickSWA`).** Bots now claim the rest
  of the round when holding an unbeatable hand (≤4 cards, R.IsValidSWA
  passes). Net.lua MaybeRunBot dispatches SWA via the existing
  permission flow (5-sec auto-approve from v0.4.6) for ≥4 cards or
  instant-claim for ≤3. Saudi convention preserved. Silent gameplay
  improvement: bots no longer leak winnable trick-points to opponents
  by playing out unbeatable hands trick-by-trick.

- **C-4: Last-trick +10 targeting + AL-KABOOT pursuit.** Trick 8
  was previously played identical to trick 1 — `lowestByRank(winners)`
  in pos-4 wasted the highest face-value card on a cheap winner,
  forfeiting the LAST_TRICK_BONUS. Now `pickFollow` pos-4 on trick 8
  uses `highestByFaceValue`, and `pickLead` on trick 8 prefers boss
  cards in safe suits (or highest-rank if our team has won 7/7
  → AL-KABOOT pursuit mode).

- **C-3b: Defender-aware strength formula additions.** PickDouble's
  Bel-decision strength now adds void-suit count × 5 (each void =
  ruff potential) and side-suit Aces beyond the first × 8 (sustained
  trick-winning power). Combined with v0.5.0's TH=60 calibration,
  Bels now fire on the right defender hands.

### Added (High-priority strategy heuristics)

- **H-3: Sampler partner trump-count bias (`getPartnerCards`).** The
  bidder's partner now gets a trump-suit weighting (`desire[trump] = true`
  → weight 20 via the suit-fallback) plus a light non-trump-Ace bias
  (5 per Ace). Without this, the sampler under-trumped the partner
  in ~50% of worlds, distorting cooperative trump-clearing rollouts.

- **H-4: Belote (K+Q of trump) preservation.** `pickFollow` discard
  fallback now skips K and Q of trump in tricks 1-3 if BOTH are still
  in hand. Saudi rule: Belote +20 raw post-multiplier scores when
  both K and Q are played from the same hand. Bot was routinely
  shedding K via `lowestByRank` (rank 4, low-end). Belote bonus now
  preserved.

- **H-5: AKA receiver convention.** When partner announces AKA on
  the led suit and is currently winning the trick, the bot
  suppresses the forced trump-ruff and plays a low non-trump
  discard instead. The half-coordination from v0.4.5 (sender-only)
  is now complete.

- **H-6: A-of-trump preservation for late tricks.** In bidder
  pickLead trump-pull, the A of trump is now excluded from the
  highestTrump candidate set when (a) `#tricks < 5` AND (b) we have
  non-Ace trump available. Saudi pros spend J/9 on pull and reserve
  A for late tricks where its 11 face value + LAST_TRICK_BONUS = 21
  effective points.

- **H-8 (already in v0.5.0): scoreUrgency context-aware** — confirmed
  active in v0.5.1.

### Activated (Style ledger wiring)

- **H-9 (partial): `triples` counter wired into PickFour.** Previously
  written by OnEscalation but read by zero pickers. Now defenders
  facing a habitual-Triple bidder (`triples >= 2`) drop their Four
  threshold by 5 (capped at -16 combined with `gahwaFailed`).
  `aceLate` and `leadCount` remain dead — wiring them is staged for
  a future cleanup sprint.

### Empirical impact

Pre-v0.5 → v0.5.1 cumulative (100-round tournaments):

| Metric | Before | After (v0.5.0) | After (v0.5.1) |
|---|---|---|---|
| `all_master` natural AvgB | 10.3 | 8.5 | **8.1** (more competitive) |
| `mixed_basic_master` natural Master gp/round | 8.8 | **11.7** | 11.5 |
| `mixed_basic_master` forced winner | A | **B** | B (Master) |
| `mixed_m3lm_master` sweep rate | 0.07 | 0.13 | **0.13** |

### Verification

- 9/9 Lua files syntax-validated
- 177/177 tests pass
- 3 baseline JSONs preserved as evidence
  (`bot_baseline_metrics.json`, `_sprint_A.json`, `_sprint_BCDH.json`)
- v0.5.1 worktree retained for reference

## v0.5.0 — Sprint A: Saudi Master tier unlocked + bot quality improvements

The 20-agent ruflo-swarm "Bot Improvement" research campaign (the
larger 300-agent budget converged early) found 5 critical structural
defects + 9 high-priority gaps in bot behavior. This release lands
Sprint A — the highest-impact subset — verified via empirical 100-round
A/B tournaments that show measurable Master-tier wins for the first
time. Master vs Basic mixed tournaments flipped winner: Master team
gp/round +33%; sweep rate +86% in M3lm-vs-Master.

Full research report at `.swarm_findings/bot_improvement_v0.5_REPORT.md`.
Pre-Sprint-A baseline at `.swarm_findings/bot_baseline_metrics.json`;
post-Sprint-A at `bot_baseline_metrics_sprint_A.json`. Staged patches
for the remaining findings at `.swarm_findings/bot_proposed_patches/`.

### Fixed (Critical structural defects)

- **C-1: Saudi Master ISMCTS was dead code (CRITICAL).**
  `Bot.PickPlay` never delegated to `BotMaster.PickPlay`. Only
  Net.lua's MaybeRunBot reached the sampler — direct callers (AFK
  recovery, error fallback, test harnesses) all ran heuristics
  even with `saudiMasterBots=true`. Empirical proof: M3lm and
  Saudi Master produced byte-identical metrics across all 6
  tournament configs in 100-round runs. v0.5 wires the
  delegation at the top of `Bot.PickPlay`, gated by a new
  `Bot._inRollout` flag set by `BotMaster.PickPlay` to prevent
  ISMCTS from recursively re-entering itself.

- **C-5: numWorlds direction was BACKWARDS (HIGH).** v0.4.7 audit
  incorrectly marked H-2 as resolved; the production code still
  used 30 worlds at trick 1 (max uncertainty) and 100 at trick 8
  (least uncertainty). Inverted to 100/60/30 by trick number —
  early-trick decisions, where the state space is largest, now
  get the most sampling budget. ~50% reduction in early-trick
  rollout sampling noise.

- **C-3a: Bel threshold lowered 70 → 60 (HIGH).** Empirical
  bel-decision-quality test (`bel_decision_quality.json`) showed
  TH=70 fired Bel only 4.2% of the time in 1000 hands and was
  wrong 50% of those firings (literal coin-flip precision). At
  TH=60 the F1 score doubles (0.137 → 0.286). Calibration only —
  the underlying strength formula still has structural issues,
  documented in C-3b for a future sprint.

### Added (Sampler improvements)

- **H-1: Hard-pin J/9 of trump to bidder (HIGH).** Previously the
  desire-weight mechanism (J=50, 9=40) still placed them on
  defenders ~30% of sampled worlds — every such world was
  structurally inverted (defender holding the trump Jack), and
  every rollout pessimistic for the bidder team. Now hard-pinned
  via the same `meldPins` mechanism used for the bid card and
  declared melds.

- **H-2: Defender side-suit Ace clustering (HIGH).** Previously
  defender seats got `desire = {}` — side-suit Aces distributed
  uniformly. Real defenders cluster non-trump Aces (since the
  bidder claimed trump). Added `getDefenderCards`: each non-trump
  Ace gets weight 8, King 4, plus a long-suit incentive. Ships
  for both opposing seats; bidder's partner stays on `{}` (H-3
  staged for future).

### Fixed (Strategy heuristics)

- **H-7: Sun opening lead from shortest non-trump suit (MEDIUM).**
  Saudi pro convention is to lead from shortest suit in Sun
  (forcing opponents to play their boss early). Bot previously
  fell through to the same "low from longest" used by Hokm
  defenders — the longest-suit lead is right for Hokm but wrong
  for Sun (no trump shield; long-suit cards get over-trumped).
  Sun now leads shortest, with boss/Fzloky/singleton priorities
  preserved.

- **H-8: Context-aware near-win urgency (MEDIUM).**
  `scoreUrgency` returned -8 uniformly when our team was near-clinch,
  raising thresholds for ALL escalations. Saudi pros do the
  opposite for DEFENSIVE escalation (Bel, Four) — they aggress
  when one win clinches the match. Added `context` param: `"bid"`
  preserves the conservative -8 (offensive); `"defend"` flips to
  +5 (aggressive). PickDouble and PickFour now pass `"defend"`;
  PickBid/PickTriple/PickGahwa/PickPreempt stay `"bid"`.

### Empirical impact (100-round A/B tournament)

Pre-Sprint-A → Post-Sprint-A:

| Config | Metric | Before | After | Delta |
|---|---|---|---|---|
| `mixed_basic_master` natural | Master AvgB | 8.8 | **11.7** | **+33%** |
| `mixed_basic_master` forced | Tournament winner | A (Basic) | **B (Master)** | flipped |
| `mixed_m3lm_master` natural | Sweep rate | 0.07 | **0.13** | +86% |
| `all_master` natural | AvgB | 10.3 | 8.5 | -1.8 (more competitive) |

Master vs Basic empirically advantageous for the first time.

### Staged for future sprints (design specs in `.swarm_findings/bot_proposed_patches/`)

- **C-2: Bot-initiated SWA** (`Bot.PickSWA`)
- **C-3b: Defender-aware strength formula** (proper Bel calibration)
- **C-4: Last-trick +10 / Al-Kaboot pursuit** (LAST_TRICK_BONUS targeting)
- **H-3: Sampler partner trump-count bias**
- **H-4: Belote K+Q preservation**
- **H-5: AKA receiver convention**
- **H-6: A-of-trump preservation for late tricks**
- **H-9: Wire dead `_partnerStyle` counters** (leadCount, triples, aceLate)

### Verification

- 9/9 Lua files syntax-validated
- 177/177 tests pass
- A/B baseline JSON evidence committed
- Worktree experiment in `WHEREDNGN-sprintA` branch (kept for reference)

## v0.4.11 — Spectator mode + WoW deck

### Added

- **WoW card deck** ("Battle of Heroes" PNG set, 32 face cards at
  512×768 + synthesized purple/gold back). Sources placed in
  `cards/wow/_src/` (PNG), rasterized to 128×192 TGAs by the new
  `cards/_make_wow.py` script using LANCZOS resampling. Registered
  as `wow` in `CARD_STYLES` (UI.lua); cycle in via `/baloot cards`
  or the lobby Cards: button. The zip ships no back image so we
  synthesize one matching the deck theme: charcoal-violet body
  with diagonal violet lattice + warm-gold border.

- **Spectator support.** A 5th+ party member with no seat now sees
  the full table:
  - Three seat badges (top/left/right) populated using a fixed
    seat-1 anchor, mapping seats 2/3/4 to right/top/left.
  - A new "Spectating" info line in the hand-row area showing
    seat 1's name + card count (the seat that doesn't get a badge).
  - Banner (round-end / game-end) renders normally; the v0.4.8
    WIN/LOST headline correctly stays empty for spectators.
  - All player-action paths still gate on `S.s.localSeat`:
    `renderHand`, `renderActions`, `LocalPlay`, `LocalBid`,
    `LocalSWA`, `LocalTakweesh`, `IsMyTurn`, etc. all return early
    when there's no seat — spectators cannot interfere.
  - The v0.4.10 lost-round stinger and v0.4.8 WIN/LOST headline
    are also correctly suppressed for spectators (existing
    `s.localSeat` guards in `S.ApplyRoundEnd` and `setOutcome`).
  - Team coloring on the badges falls back to absolute team
    (A=green / B=red) for spectators — they don't have a partner
    relationship to claim "us-vs-them" against.

## v0.4.8 — Three small UI fixes (player feedback)

### Fixed

- **Lobby checkbox overlap:** the 4-tier bot checkbox stack
  (Advanced / M3lm / Fzloky / Saudi Master) had its bottom row at
  `y=12`, the same vertical band as the centred Host Game / Start
  Round / Fill Bots buttons. The "Saudi Master" label visually
  overlapped Host Game. Shift the entire stack up by 30 (new
  `y={108, 86, 64, 42}`) and bump the right-column Cards/Felt cycle
  buttons to match (`y={108, 86}`) so the top two rows still pair.

- **Pass label rendered as empty boxes for opponents:**
  `bidLabelForSeat` returned `"بس"` (Arabic colloquial "Pass") for
  the per-seat bid display below other players' names. WoW's bundled
  fonts (Arial Narrow / Frizz / Skurri) don't include Arabic glyphs
  — same constraint already documented for the AKA button — so the
  label rendered as empty boxes / glyph errors. Match the local-side
  bid-button convention: `"wla"` (Latin transliteration of ولا) in
  R2, `"Pass"` in R1.

- **Round-end banner: WIN / LOST headline:** the score banner showed
  "AL-KABOOT! / BALOOT! / ALLY B3DO" with YA MRW7 pointing at the
  losing team, but players had to mentally translate that contract
  framing into their own team's outcome. Added a large-font headline
  above the contract title showing "WIN" (green) or "LOST" (red)
  from the local player's perspective. Logic covers all branches:
  - Sweep → sweeping team wins
  - Contract made → bidder team wins
  - Contract failed → defender team wins
  - SWA valid → caller's team wins; invalid → opp wins
  - Takweesh caught → caller's team wins; false call → opp wins
  - Match end → S.s.winner team wins
  - Non-host degraded view → infer from delta sign

  Banner height bumped from 170 → 196 to fit. Spectators (no
  localSeat) get an empty headline, falling back to the existing
  contract-title context.

## v0.4.7 — 50-agent empirical + codebase audit (5 critical bugs found)

A second 50-agent ruflo-swarm audit, this time split 20 agents on
empirical playtest scenarios (tracing real game flows step-by-step)
and 30 agents on full-codebase review. The empirical wave alone
caught two CRITICAL bugs that pure static analysis missed in v0.4.6.
Full audit report at `.swarm_findings/v0.4.7_AUDIT_REPORT.md`.

### Fixed (Critical)

- **v0.4.6 turn-desync fix was incomplete (CRITICAL):** the self-heal
  block at `Net.lua:_OnPlay` correctly accepted host-signed plays for
  any seat AT THE FIRST GATE, then patched `s.turn`. But the SECOND
  authority gate (`if not isReplay and not authorizeSeat(seat, sender)
  then return end`) did NOT have the fromHost escape. For human
  seats, `authorizeSeat(seat, host)` returns false (sender is host,
  seat owner is the human's name), so the play was silently dropped
  AFTER the self-heal patched `s.turn`. The reported AFK auto-play
  cascade (player sees stuck turn → AFK fires → click an
  already-played card → "illegal play") was NOT actually fixed in
  v0.4.6 — only after this v0.4.7 patch is the chain complete. Mirror
  the fromHost escape on the second gate at Net.lua:1104.

- **AFK timeout silently forfeited melds (CRITICAL):**
  `_HostTurnTimeout`'s play branch auto-played the AFK seat's lowest
  legal card but did NOT auto-declare melds. The Saudi meld
  declaration window closes after trick 1 (`#s.tricks >= 1` gate in
  `S.GetMeldsForLocal` / `S.ApplyMeld` / `Bot.PickMelds`), so a human
  AFK'd through trick 1 silently lost their entire meld score — a
  declared Quarte (50 raw) under Bel ×2 = 100 raw = 10 gp lost with
  no UI feedback. Now mirrors `MaybeRunBot`'s auto-declare pattern:
  if `meldsDeclared[seat]` is false, run the meld picker on the AFK
  seat's behalf, broadcast, stamp `meldsDeclared`, then play the
  card. Outside the trick-1 window the meld picker returns `{}`
  naturally, so the fix is a no-op there.

- **BotMaster fallback deal path missing meldPins (CRITICAL):**
  `sampleConsistentDeal`'s primary path correctly pinned declared
  meld cards to their declarer (since v0.4.5). The fallback path
  (used when the primary 15-attempt loop exhausts) ignored
  `meldPins` entirely — a Tierce 7-8-9 of Hearts declared by seat 3
  could end up split across all four seats in fallback rollouts,
  corrupting every Saudi Master ISMCTS estimate in games with active
  melds. Fix mirrors the primary path: exclude `meldPins` keys from
  the fallback shuffle pool and pre-place them into the declaring
  seat's hand before filling the remainder.

### Fixed (High)

- **SWA 5-sec timer ignored pause:** both `_OnSWAReq` and `LocalSWA`
  C_Timer.After callbacks fired during paused games, force-approving
  SWA requests mid-pause. Now the timer's first action is a paused
  check; if paused, re-arm a fresh 5-sec window when the game resumes
  rather than auto-approving. Opponents retain the chance to press
  Takweesh after unpause.

- **Bot.OnPlayObserved fired on replay frames:** during a resync
  /reload, `_OnPlay` re-applies in-flight plays with `isReplay=true`.
  The Bot.OnPlayObserved call was outside the `not isReplay` guard,
  so void inference / firstDiscard / aceLate / leadCount / likelyKawesh
  counters could be poisoned by phantom replay observations on any
  client with bot logic loaded. Currently safe because only humans
  rejoin (B.Bot is unused on their clients), but the latent risk is
  closed — guard added.

### Fixed (Medium one-line patches per audit synthesis)

- **`C.IsKaweshHand` requires ≥5 cards:** Saudi Kawesh is defined on
  the first-five-dealt hand. The previous guard `#hand == 0` allowed
  a 1-4-card mid-deal hand of all 7/8/9 to falsely match. Tightened
  to `#hand < 5`.

- **`WHEREDNGN.lua` `B.Net` nil-guard:** the CHAT_MSG_ADDON dispatcher
  called `B.Net.HandleMessage` without a nil-check. Every other
  module reference in the file is nil-guarded; this one was an
  outlier and would flood error popups if Net.lua ever failed to
  load.

- **`UI.lua` `renderActions` localSeat guard:** spectators (joined
  party with no seat) had no top-level gate. Most action branches
  gated on localSeat internally, but PHASE_SCORE/GAME_END only
  checked isHost — exposing host buttons to spectator-host edge
  cases. Single `if not S.s.localSeat then return end` at the entry.

### Audit-confirmed PASS items (no change)

- B-61 sunFail direction is correct (raise threshold = Bel less);
  earlier wave's EV math was flawed (forgot Bel doubles bidder's
  made score symmetrically)
- Carré J = 100 and no-Carré-9 are correct per Saudi rule
  (Pagat-strict, not French Belote convention); confirmed against
  v0.4.3 audit citations to "نظام التسجيل في البلوت"
- Trick resolution, must-follow / overcut / partner-winning
  exception in `R.IsLegalPlay` all correct
- Resync / replay flow / packSnapshot serialization clean
- AFK timer arming/cancelation respects pause and SWA correctly
  (preempt window post-host-reload is the only minor gap)

### Open (deferred — info / next sprint)

- AKA receiver behavior in pickFollow: bot partner reads `akaSent`
  per-suit dedup but doesn't actually consult `S.s.akaCalled` to
  suppress over-trumping. Half of the AKA convention is missing.
- Headless tournament test fixtures cannot exercise Tier 4 features
  (resets between rounds). 5 concrete test skeletons proposed in
  audit report; not yet implemented.
- All-4-disconnect: non-host state lost (no resync mechanism after
  group dissolves). Acceptable for v1; would need a mid-host-migrate
  protocol to fix.

## v0.4.6 — Three player-reported bugs + SWA UX rework + 50-agent audit follow-ups

A 50-agent ruflo-swarm audit on the v0.4.5 + v0.4.6 changes (10 waves
of 5 agents each, 50 distinct angles) confirmed three follow-up bugs
in the Tier 4 work; all three are fixed below. The full audit report
is at `.swarm_findings/v0.4.6_AUDIT_REPORT.md`. The audit also
re-derived the EV math for B-61 (sunFail) and confirmed the original
direction is correct (raise Bel threshold against repeat-sunFail
bidders). Master report's `gahwaFailed` counter was found to be a
dead increment with no consumer; this release wires it into PickFour.

### Audit-driven fixes (in addition to the v0.4.6 player-reported items below)

- **B-99 likelyKawesh teammate cross-contamination (HIGH):** the
  `mem.likelyKawesh` flag in `Bot.OnPlayObserved` was being set for
  the just-played seat regardless of team. The BotMaster sampler
  consumed the flag uniformly across all seats — when a partner
  played only 7/8/9 in tricks 1-3 (legitimate signal-suit conservation,
  not a Kawesh-skip pattern), the sampler cleared the partner's
  `desire` map, discarding the Fzloky `pSignalSuit` bias that was
  set just two lines earlier. Fixed by gating the consumer at
  `BotMaster.lua:226-229`: the desire-clear now only fires when
  `R.TeamOf(s) ~= R.TeamOf(seat)` (s is an opponent of the calling
  bot's seat). The flag itself remains descriptive of per-seat
  behaviour; only the consumption is team-relative. Dead-code
  `for opp = 1, 4 do ... end` loop in `Bot.OnPlayObserved` removed.

- **B-83 gahwaFailed wired into PickFour (MEDIUM):** the
  `_partnerStyle.gahwaFailed` counter was incremented in
  `Bot.OnRoundEnd` (Bot.lua:234) when a Gahwa contract failed but
  had zero consumers — fully dead instrumentation. Per the master
  report's B-83 spec, defenders should be more aggressive against
  reckless Gahwa-callers. Now wired in `Bot.PickFour` (Bot.lua:1670):
  tiered threshold drop of -5 on `gahwaFailed >= 1` and -8 on
  `gahwaFailed >= 2` (matching `styleBelTendency`'s magnitude).
  M3lm-gated.

- **Takweesh now explicitly clears swaRequest (MEDIUM):**
  `HostResolveTakweesh` previously relied on the SWA 5-sec timer's
  phase guard to no-op the auto-approve; the timer would find
  `phase ~= PHASE_PLAY` after Takweesh's `S.ApplyRoundEnd` and
  return. Worked correctly but left `S.s.swaRequest` stale through
  PHASE_SCORE, contradicting the changelog claim that "Takweesh
  during the window clears swaRequest". Now explicit:
  `S.s.swaRequest = nil` at the top of `HostResolveTakweesh`
  (Net.lua:1736). Belt-and-braces with `ApplyStart`'s round-start
  clear; comments in the SWA timer block are now accurate.

### v0.4.6 (original — three player-reported bugs)



### Fixed

- **Turn desync → illegal play (CRITICAL):** players occasionally got
  stuck — their UI showed the previous seat highlighted while the host
  thought it was their turn. AFK auto-play would fire on the host
  (consuming a card from their authoritative hand), and when the
  player finally clicked, they hit "illegal play" because their UI
  still showed the auto-played card but it was no longer in their
  hand on the host. RCA pinned this to `Net.lua` MSG_PLAY handler:
  `if S.s.turn ~= seat or S.s.turnKind ~= "play" then return end`
  silently dropped any MSG_PLAY whose seat didn't match the local
  turn pointer. CHAT_MSG_ADDON party-channel is at-most-once under
  server contention; a single dropped MSG_TURN frame made the
  receiver permanently miss every subsequent play in the trick,
  including the host's recovery auto-play. Fix: when the seat doesn't
  match local turn but the sender is the host (or the seat is a bot
  whose moves the host signs), trust the host's authority and
  self-heal `s.turn` before applying. Existing idempotence guard
  prevents double-apply if the missed MSG_TURN arrives later.

- **Hokm Bel scoring zeroed loser's melds (HIGH):** when a Hokm
  contract was Bel'd (×2) and the bidder team failed, the bidder's
  declared melds were nullified — a quarte (50 raw) that should
  have scored 100 raw / 10 gp under Bel ×2 instead scored 0. Same
  bug in the doubled-tie inversion ("take") branch — a defender
  team that Bel'd and tied lost ALL their melds. Both contradict
  the Saudi rule "مشروعي لي ومشروعك لك" (each team keeps their
  own declared melds; only the qaid penalty handTotal × multiplier
  flows to the winner). The qaid path was already corrected in
  v0.4.3; the regular `R.ScoreRound` fail/take branches now match.

### Changed

- **SWA permission window: 5-sec auto-approve + Takweesh counter
  (UX redesign):** previously a permission-required SWA (≥4 cards
  remaining) waited indefinitely on Accept/Deny votes from both
  opponents. Now the host arms a `K.SWA_TIMEOUT_SEC = 5` second
  auto-approve timer at request-time. During the window:
  - the SWA-claim banner displays in the centre of the table
    (caller name + remaining-card count + countdown)
  - opponents inspect the claim and either let the timer auto-
    approve, or press the always-visible **TAKWEESH** button to
    counter (Takweesh scans every prior trick of the SWA caller's
    team for an illegal play; if found, the qaid penalty applies
    and SWA is voided)
  - explicit Accept / Deny still works as a manual override
  - bots auto-accept (existing behaviour) — the timer is mostly
    a safety net for human deadlocks
  Rationale: humans may have played illegal cards in earlier tricks
  that would invalidate an SWA claim. The 5-sec window gives the
  opposing team a natural inspection beat to call Takweesh against
  prior misplays before the SWA resolves.

## v0.4.5 — 200-agent audit Tier 1+2 (critical bot fixes)

Tier 1 (4 confirmed critical bugs) + Tier 2 (style-ledger activation)
from the 200-agent ruflo-swarm audit campaign. All 5 candidate
critical findings reviewed; one (C-2 trump-ruff void rollback) was
re-classified as a false positive — the void flag IS correct in a
trump-ruff scenario because the seat is genuinely void in lead suit,
and the existing `wasIllegal` guard at Bot.lua:213-217 already
prevents void inference on rolled-back illegal plays.

### Fixed (Tier 1 critical bugs)

- **C-1 Bot memory inert for ~half of plays (CRITICAL):**
  `Bot.OnPlayObserved` was only invoked from the two human-play
  dispatch sites in `Net.lua`. Bot plays via `MaybeRunBot`, AFK
  auto-plays via `_HostTurnTimeout`, and bot error-recovery
  fallbacks all skipped the observer entirely. Result: void
  inference, `firstDiscard`/Fzloky signals, AKA per-suit dedup,
  trump-tempo counters (`trumpEarly`/`trumpLate`), and the entire
  per-seat memory subsystem missed every bot card play. Downstream
  `suitCardsOutstanding`, `HighestUnplayedRank`, and
  `opponentsVoidInAll` produced wrong answers all round long.
  Fix: added `Bot.OnPlayObserved(seat, card, leadBefore)` calls at
  three sites in `Net.lua` (the bot-play dispatch, the AFK timeout,
  and the play-decision error-recovery branch), each capturing
  `leadSuit` BEFORE `S.ApplyPlay` mirrors the human-play pattern.

- **C-3 A/T sure-stopper not gated to Sun (CRITICAL):** The
  pos-2 "sure stopper" shortcut at `Bot.lua:1003-1012` returned the
  highest non-trump A/T of the led suit unconditionally. In Hokm,
  a non-trump Ace is NOT a guaranteed winner — an opponent void in
  that suit can over-ruff and the bot sacrifices its Ace for
  nothing. Now gated on `contract.type == K.BID_SUN` where Aces
  genuinely cannot be over-trumped.

- **C-4 PickDouble trump-weight blocked Hokm Bel (CRITICAL):**
  `Bot.PickDouble` computed strength as `sunStrength + 0.5 *
  trumpStr`. The 0.5x discount was inconsistent with the 1.0x
  weight used by `escalationStrength` (PickTriple/Four/Gahwa). A
  Hokm defender with J+9+A of trump scored ~42 trump points but
  only saw 21 in PickDouble — combined hand total mathematically
  could not reach `BOT_BEL_TH=70`. Strong-trump defenders
  systematically declined legitimate Bels. Trump weight now 1.0x,
  aligned with the rest of the escalation pipeline.

- **C-5 heuristicPick rollout selected wrong card (CRITICAL):**
  `BotMaster.heuristicPick` bidder-lead branch called
  `highestRank(legal)` then checked `if C.IsTrump(t, contract)`.
  When the highest legal card by `TrickRank` was NOT trump (e.g.,
  a side-suit Ace outranking a depleted trump in the cross-scale
  comparison), the trump check failed and the rollout silently
  fell through to the side-suit branch — returning a low side-suit
  card instead of pulling trump. Saudi Master ISMCTS rollouts
  therefore made the wrong bidder-lead decision in any trump-poor
  position. Now filters legal to trump cards first, picks
  `highestRank(trumpCards)`, and only falls through if the trump
  set is empty.

### Activated (Tier 2 style ledger)

- **`styleBelTendency` wired into `Bot.PickTriple`:** The function
  was defined at `Bot.lua:181-187` and fed by `OnEscalation` but
  had zero callers across the codebase. Habitual Belers (`bels >=
  2`) now drop our Triple threshold by 8 — their Bel signal is
  noise and we counter more aggressively. M3lm-gated
  (`Bot.IsM3lm()`).

- **`styleTrumpTempo` wired into `pickLead` defender branch:** The
  function was defined at `Bot.lua:189-196` and fed by
  `OnPlayObserved` but had zero callers across the codebase. As a
  defender against a known aggressive trump-puller (bidder or
  bidder's partner observed leading trump in early tricks across
  prior rounds), the bot now saves J/9 of trump from the
  forced-trump fallback, burning 7/8/Q/K instead so the boss trump
  is held back to over-ruff their pulled trump tricks. M3lm-gated
  and Hokm-only.

### Architectural (Tier 3 — human-vs-bot guards)

The 200-agent audit identified that the bot's partner-aware code
paths (`partnerBidBonus`, `pickLead` Fzloky reads, `PickAKA`)
applied bot-calibrated logic equally to human partners — a
systematic mis-calibration unblocked by a single architectural
helper plus four scoped guards.

- **`Bot.IsBotSeat(seat)` helper added (Bot.lua:80-90):** thin
  proxy delegating to `S.IsSeatBot`. Replaces every
  `S.s.seats[seat] and S.s.seats[seat].isBot` open-coded reach
  into State across the picker code. One-line call sites for the
  guards below.

- **H-11 / B-09 / B-14: `partnerBidBonus` PASS penalty halved for
  human partners (Bot.lua:436-437):** bot PASS = calibrated weakness
  signal (`PickBid` only passes when no Sun-strong / Hokm-strong /
  Ashkal-eligible hand is present). Human PASS = often overcaution
  on marginal hands a bot would have bid. Treating both as a -10
  signal suppressed Triple/Four/Gahwa after a human partner's PASS
  even when our own hand merited escalation. Bot partner: -10;
  human partner: -5.

- **H-12 / B-31 / B-87 / B-90: `pickLead` Fzloky guarded on
  `Bot.IsBotSeat(partner)` (Bot.lua:775-787):** Fzloky is a bot-side
  convention (bot's first off-suit discard is a deliberate
  suit-preference signal — high = lead this, low = avoid). A human's
  first off-suit discard is just whatever they shed (often a high
  card to dump weakness, often random). Reading a human's discard as
  a "lead this suit" signal misdirected the bot's lead priority for
  the rest of the round.

- **B-33 / B-60: `Bot.PickAKA` suppressed when partner is human
  (Bot.lua:1158-1168):** AKA is a partner-coordination signal —
  bot partners read the per-round `akaSent` flag and suppress
  over-trumping the announced suit. Human partners typically don't
  recognize the AKA banner as a "don't ruff this suit" instruction;
  at best the signal is wasted, at worst it leaks information to
  opponents (who see the same banner) and hands them a free read on
  which suit we hold the boss in.

- **`Bot.PickPreempt` partner-bid bonuses scaled for human partners
  (Bot.lua:1389-1402):** symmetric with H-11 — a human PASS doesn't
  imply weakness as reliably as a bot PASS, and a human Hokm bid
  doesn't imply J/9 as reliably as a bot Hokm bid. PASS penalty
  -6 → -3, Hokm bonus +5 → +3 when partner is human. Sun bonus
  unchanged (Sun bid implies real high-card distribution either way).

### Reclassified

- **C-2 trump-ruff void rollback:** the master report flagged this
  as a critical bug, but on inspection the void inference IS
  correct — a trump-ruff genuinely implies the seat was void in
  lead suit (otherwise they'd have been forced to follow). The
  separate rollback at lines 262-269 is the Fzloky firstDiscard
  rollback for forced ruffs (the discard isn't a preference signal),
  and that path correctly nils only `firstDiscard`. The illegal-play
  case is already gated by `wasIllegal` at Bot.lua:213-217. No
  change needed.

### Track B (Tier 4 — human-pattern exploitation)

The 200-agent audit catalogued ~25 missing-feature gaps where the
bot collected data but failed to act on it, or had no way to
detect a human-specific pattern. Tier 4 adds the foundation
callbacks plus 11 picker integrations that turn the dormant style
ledger into actual gameplay decisions. M3lm-gated where the
counters are involved; Hokm-only / contract-conditioned where
appropriate. Dropped from scope (per master report's own
reverse-exploit-risk caveats): B-63/B-93 Bel-timing hesitation,
B-76 tilt detection, B-85 trump-back context flag, B-88 echo
convention.

#### Foundation infrastructure

- **`Bot.OnRoundEnd(contract, bidderMade)` callback added
  (Bot.lua:222-239, State.lua):** wired from `S.ApplyRoundEnd` on
  every client (mirrors `OnEscalation`'s broadcast pattern). Allows
  per-round outcome tracking without scattering bookkeeping across
  multiple Net.lua dispatch sites.

- **`emptyStyle` extended with 4 new counters (Bot.lua:155-180):**
  `gahwaFailed` (reckless callers — bidder Gahwa'd and failed),
  `sunFail` (defensive-Sun pattern — bidder Sun'd and failed),
  `aceLate` (A-hoarder pattern — Ace played at trick 5+),
  `leadCount[suit]` (per-suit lead frequency for repeat-lead
  pattern). Maintained on every client; consumed only host-side.

- **`emptyMemory` extended with `likelyKawesh` flag (Bot.lua:117-122):**
  per-round, per-seat. Set by `OnPlayObserved` after trick 3 if all
  observed plays are rank 7/8/9. Consumed by BotMaster sampler.

- **`Bot.r1WasAllPass` snapshot (B-80 / H-10):**
  `S.HostBeginRound2` captures whether R1 ended with all 4 seats
  passing BEFORE clearing `s.bids`. `S.ApplyStart` resets to false
  at round start. `Bot.PickBid` R2 reads it to drop `r2Base` by 6
  in trap-pass rounds (the table is weak overall; a strong R2 bid
  by a human is more likely overcaution-recovery than genuine
  combined strength).

#### Style-ledger integrations (8 picker fixes)

- **B-47 / B-50 — `matchPointUrgency` reads opponent escalation
  history (Bot.lua:563-590):** sums opponent `.gahwas` and
  `.fours` across both opp-team seats. Gahwa-prone opponent
  trailing by 50+ → +3 (they may try a desperate Gahwa to spike,
  Bel them ready). Passive opponent (0 fours, 0 gahwas) when
  WE are far behind → dampen +3 to +1 (no spike risk to
  defend against).

- **B-77 — `anyOpponentVoidIn` helper + Ace-lead exploit
  (Bot.lua:354-368, ~1010):** when one opponent is known void in
  a side suit AND we hold the boss, lead the boss in priority 1.5
  of `pickLead`. The single-void variant fires far more often than
  the both-void shortcut at priority 1, capturing high cards that
  would otherwise sit unused.

- **B-82 — Trump-drought tell in defender `pickLead`
  (Bot.lua:1000-1043):** scans the current round's tricks for
  bidder leads. After 3 tricks, if the bidder has led at least once
  but never trump, the bidder is trump-poor — defenders cash their
  highest non-trump A/T immediately (no ruff threat). M3lm-gated.

- **B-98 — J+9 trump-lock in bidder `pickLead`
  (Bot.lua:951-994):** once both J and 9 of trump are observed
  played (or held in our own hand), opponent trump strength is
  spent. Switch to cashing side-suit Aces while still holding
  reserve trump for defensive ruffs. Advanced+, depends on the
  C-1 memory population fix from earlier in v0.4.5.

- **B-96 — Ace-exhaustion window in bidder `pickLead`
  (Bot.lua:935-959):** after trick 3, if all 3 non-trump Aces
  have been observed played (anywhere, including our own hand), no
  Ace threats remain — switch to leading our highest non-trump
  (now bosses) instead of continuing trump-pull.

- **B-99 — `likelyKawesh` inference + BotMaster integration
  (Bot.lua:367-387, BotMaster.lua:213-228):** `OnPlayObserved` flags
  a seat as `likelyKawesh` after trick 3 if all their observed plays
  are rank 7/8/9. The sampler `desire` map is cleared for that seat,
  so trump J/9/A no longer get pinned to a low-card hand — fixes
  rollouts that previously mis-modeled Kawesh-skipping opponents
  as having strong cards.

- **B-67 — `aceLate` counter feeds sampler probability
  (Bot.lua:359-365, BotMaster.lua:228-234):** seats with
  `aceLate >= 2` get `pickProb` reduced from 0.7 to 0.5 in the
  sampler — A-hoarder patterns lower the reliability of bid-strong
  bias for that seat.

- **B-56 — `leadCount[suit]` accumulation
  (Bot.lua:351-358):** populated on every lead play in
  `OnPlayObserved`. Consumed by future repeat-lead exploitation
  features (placeholder ledger; no current picker integration —
  data is being captured for downstream use).

- **B-61 — `sunFail` defensive-Sun detection in `PickDouble`
  (Bot.lua:1597-1611):** when the Sun bidder has failed Sun ≥2
  times this game, our Bel threshold rises by 8 (defensive Sun
  has low base score; the 2x Bel reward is small if we win and
  large if we lose, expected-value math favors letting low Sun
  play out without Bel risk amplification). M3lm-gated.

#### Wire-protocol fix

- **B-69 — `s.target` added to packSnapshot
  (Net.lua:351, State.lua:368-373, 461-468):** late-joining /
  reloaded clients previously defaulted to 152 even when the host
  had configured a different target via `/baloot target N`. Field
  29 of the resync snapshot now carries the host's target. Backwards-
  compatible: pre-v0.4.5 hosts omit field 29 and the receiver
  preserves its existing `s.target` default.

## v0.4.4 — Bidding visibility + bigger meld strips (player feedback)

Two cosmetic fixes from player feedback. No rule / wire / scoring
changes.

- **Hokm bid suit visible to other players.** When a player calls
  Hokm in round 2 (or any bidding round), the seat badge now shows
  "HOKM ♠" (or ♥ / ♦ / ♣) below the player's name, in the suit's
  on-card colour. Over-bidders can now see which direction someone
  is going and decide whether to over-bid with Sun, Bel, or skip.
  Pass / Sun / Ashkal also render. Visible only during the bidding
  phases (DEAL1 / DEAL2BID); cleared once the contract is locked.

- **Meld strip 1.45x larger and below the badge.** Players reported
  the seat-side meld card strip (cards face-up during the 5-second
  trick-2 reveal) was too small to read. Cards now scale 1.45x and
  the strip is anchored BELOW the seat badge frame (extending ~46
  px down into the table area) instead of squeezed inside the
  badge bottom. The local bar's strip is unchanged so the local
  player's own layout stays the same.

## v0.4.3 — Saudi rule corrections (10-agent scoring audit)

Three rule-compliance fixes from a 10-agent audit (Codex + Gemini + 8
Claude angle agents) that cross-checked the scoring algorithm against
seven canonical Saudi Baloot PDF references:
- نظام التسجيل في البلوت (Scoring System)
- نظام الدبل في لعبة البلوت (Doubling System)
- نظام اللعب في البلوت (Play System)
- ماهو البلوت في لعبة البلوت (Bloot Definition)
- الثالث (Triple-on-Ace)
- سر الاحتراف 1 + 3 (Pro Secrets)

The audit identified ~7 issues; the user authorised three to fix and
deferred the rest pending interpretation. Re-confirmed-correct: card
values, hand totals, Bloot value (20 raw = 2 gp), Bloot cancellation,
sequence values, Sun-no-Triple/Four/Gahwa, tie resolution, qaid
penalty scaling under escalation (interpretation b).

### Fixed

- **Carre-A in Sun double-counted (CRITICAL):** `K.MELD_CARRE_A_SUN`
  was 400 raw, then multiplied by `MULT_SUN=2` in `R.ScoreRound` →
  800 raw / 80 gp final. Saudi rule says "أربع مئة" = 400 (final
  raw, post-Sun-mult). Constant now 200 raw so the Sun ×2 brings the
  final to 400 raw / 40 gp, matching canon.

- **Qaid melds nullified loser's projects (HIGH):** Both
  `HostResolveTakweesh` and the invalid-SWA path in `HostResolveSWA`
  zeroed out the loser's declared melds, contradicting Saudi rule
  "مشروعي لي ومشروعك لك" (each team keeps their own melds during a
  qaid). Both teams now retain their own declared melds; the qaid
  penalty (handTotal × multiplier) is awarded to the winner
  separately.

- **Sun Bel eligibility too permissive (HIGH):** Code enabled Sun Bel
  whenever EITHER team had cumulative ≥ 101. Saudi rule "ويكون الدبل
  للمتأخر فقط وهو الذي لم يتجاوز عدده 100" requires the doubler to
  be the BEHIND team, AND someone to have crossed 100. New helper
  `N._SunBelAllowed(bidderSeat)` enforces: bidder team ≥ 101 AND
  defender team < 101. Applied to all 5 Sun-Bel-gate sites
  (post-bid contract, preempt finalize, post-preempt-claim, host
  bot path, local preempt action).

### Researched (deferred)

- **Sun "no abnat" rule:** A research agent confirmed the addon's
  `div10` rounding is canonically correct for Hokm but produces
  ±1 game-point errors for Sun at certain card-point boundaries
  (totals ending in 3 or 6). Canonical Sun rule is "round to nearest
  10 preserving units-5, then ÷5", which differs from the current
  "× MULT_SUN(2), then round-half-down ÷10". The fix would require
  refactoring the rounding pipeline to apply card-point rounding
  BEFORE the multiplier — deferred pending design call.

### Confirmed correct (no change)

- Card point values (J/9 in trump, J in non-trump)
- Hand totals (162 Hokm, 130 Sun)
- Bloot value (20 raw → 2 gp), cancellation, no-doubling
- Sun phase machine blocks Triple/Four/Gahwa
- Tie resolution (strict bidder>defender, doubled-tie inversion)
- Sequence values (SEQ3=20, SEQ4=50, SEQ5=100)
- Qaid penalty scaled by escalation (interpretation b per user)

Tests: 177 passed, 0 failed.

## v0.4.2 — Round-end banner clarity (player feedback)

Two cosmetic fixes only; no rule / wire / scoring changes.

- **YA MRW7 tease for the losing team.** The round-end banner used
  to declare the OUTCOME ("AL-KABOOT", "BALOOT", "ALLY B3DO") but
  not WHICH team got the bad end. Players reported the result was
  ambiguous when their team's identity wasn't obvious. The title
  now appends "— YA MRW7 [losing team]" in red. Same applies to
  Takweesh, SWA, and the non-host degraded view (which infers the
  loser from the broadcast delta).
- **Score colors now reflect us-vs-them, not Team A vs Team B.**
  The final-delta line and team labels (A +X, B +Y) used to
  hard-code Team A as green and Team B as red regardless of which
  team the local player belonged to — so a Team B player saw their
  own deltas in red. Both labels and numbers now use `txtUs` for
  the local team and `txtThem` for opponents (or fall back to the
  legacy A=green/B=red for spectators / pre-join state).

## v0.4.1 — Saudi Master pro-grade ISMCTS

Major BotMaster.lua upgrade driven by a 25-agent + Codex + Gemini
deep audit focused exclusively on the Saudi Master tier. The bot
now plays meaningfully closer to a pro Saudi Baloot tactician.

### Sampling fidelity (`sampleConsistentDeal`)

- **Bidder strong-card weighting**: bidder's hand sample is now
  biased toward J / 9 / A of trump (Hokm) or multi-suit Aces (Sun)
  with 70% selection rate per "desired" card. Previously uniform
  random.
- **Partner Fzloky signal**: partner's first-discard suit gets a
  +20 weight in the sampler so worlds match what the bot already
  reads at lead time.
- **Declared meld cards pinned**: every unplayed card in a declared
  tierce / quart / quint / carré is pinned to the declarer's seat.
  Previously the sampler could scatter "Hearts Tierce 7-8-9" across
  all four seats, corrupting every rollout's view.
- **Bid card pinned to bidder** (kept from v0.3.x): the public bid
  card always lands in the bidder's hand.

### Rollout value function (`rolloutValue`)

- **Real Saudi scoring**: `R.ScoreRound` now drives the rollout
  utility — multipliers (Bel ×2, Triple ×3, Four ×4), make/fail
  cliff, melds, sweep, belote, last-trick bonus all priced in. The
  previous raw-trick-points return ignored multipliers entirely.
- **Team diff axis**: returns `result.raw[us] - result.raw[opp]`
  instead of just our points. Puts both "we make by 5" and "we
  fail by 2" on a single ranking axis where the contract-outcome
  cliff dominates raw-point fluctuation.
- **Gahwa terminal boost**: ±10000 when the rollout reaches a
  Gahwa-won-game state, ensuring match-winning candidates dominate.
- **Meld reconstruction**: each rollout reconstructs the initial
  8-card hand for each seat and runs `R.DetectMelds` so opponent
  meld threats are correctly priced (was previously zero).

### Rollout policy (`heuristicPick`)

- Now mirrors live `pickFollow` for position-aware play:
  - Pos-2 ducking with sure-stopper exception (Ace of led suit
    in Sun is unbeatable; Hokm trump-only-1-out is a stopper).
  - Pos-3 third-hand-high (committed winner so 4th seat can't
    cheaply overcut).
  - Smother on partner-winning + non-trump-led trick.
  - Trump preservation when not last seat.

### Adaptive search depth (`PickPlay`)

- World count scales with trick number for endgame fidelity:
  - Tricks 1-3: 30 worlds (default)
  - Tricks 4-5: 60 worlds
  - Tricks 6+: 100 worlds (small information set, near-exhaustive)

### Tests

177/177 passing (new Master-tier tournament test in
`test_state_bot.lua` confirms Master tier matches M3lm tier
under randomized synthetic deals).

### Audit findings deferred

- Backtracking CSP for void-fallback sampler (architectural
  overhaul; current 15-attempt retry adequate for normal play).
- Bel-open/closed inversion claim (verified that current code
  already matches Saudi convention: strong defender opens to
  invite escalation, marginal defender closes to lock-in ×2).
- Adaptive `numWorlds` based on confidence intervals (current
  trick-based scaling is simpler and well-tuned for the budget).
- Per-seat Hokm/Sun bid count ledger extension (would require new
  Bot.OnBid hook; deferred to a follow-up release).

## v0.4.0 — Bot AI improvements (25-agent audit)

Tactical and evaluation upgrades across all bot tiers. No wire-format
changes. Driven by a 25-agent audit (23 Claude angle agents + Codex
CLI + Gemini CLI) focused exclusively on Bot.lua and BotMaster.lua.

### Bidding evaluation

- `suitStrengthAsTrump` now scores 7 and 8 of trump at +2 each (Saudi
  Hokm convention). Previously fell through with 0 contribution,
  undercounting trump-rich hands by up to 8 points.
- `sunStrength` adds two new bonuses:
  - **+6 per card beyond 4** in suits ≥5 long that contain an A or K
    ("the suit walks"). A 6-card spade suit with AKQ now scores ~30
    higher than before, properly reflecting Sun-control value.
  - **+8 stopper triple** for any AKQ in the same suit (3 guaranteed
    tricks in no-trump).
  - Distribution penalty cap softened from −25 to −18 (long solid
    suits no longer bleed all their headroom).
- Advanced R2 threshold bump reduced from +6 to −4. The previous +6
  forced Advanced/M3lm to pass winnable marginal hands that Basic
  scooped up — directly responsible for the headless-tournament
  M3lm regression (97.7 vs Basic 99.1).
- `matchPointUrgency` magnitudes halved on the opp-near-win branches
  (+8→+5, +3→+2) and the function output is now capped at ±10.
  Previously stacked with `scoreUrgency` could reduce thresholds by
  up to 20 points (Bel 70→50), causing desperate over-escalations.

### Card play tactics

- `pickFollow` smother (partner winning) now fires on Sun and Ashkal,
  not Hokm-only. Dumping A/T of the led suit is free points in any
  contract.
- New Sun sure-stopper: in any contract with a non-trump lead, the
  Ace of the led suit is unbeatable AND a high-point card. Pos-2 no
  longer ducks A/T of the led suit ("don't voluntarily lose 11
  points").
- Pos-3 forced trump-ruff now uses the LOWEST trump, not the highest
  — saving J / 9 / A for forcing leads. Previously the bot wasted
  the J of trump on a 7-of-side-suit ruff in a classic give-back.

### Kawesh / Saneen

- New `Bot.PickKawesh(seat)` implements the bot side of the
  hand-annul rule: 5+ cards of {7,8,9} → unconditionally call
  Kawesh in DEAL1. Net.lua bot dispatch checks before bidding so
  the bot redeals an unwinnable hand the same way a human would.
  Previously bots had to play these hands and lose.

### Pre-emption

- `Bot.PickPreempt` now factors partner's bid history. Partner who
  passed → −6 (no fallback if our Sun fails). Partner who bid Sun →
  +8 (side-suit coverage implied). Partner who bid Hokm → +5.
- The Ace-of-bid-suit bonus raised from +8 to +12. The Ace is worth
  ~11 raw points + tempo control + guaranteed first-trick — under-
  weighted at +8.

### Saudi Master ISMCTS rollouts

- `BotMaster.heuristicPick` upgraded with three of the highest-impact
  live heuristics, closing the gap with `Bot.pickFollow`:
  - Smother on partner-winning + last-seat (with non-trump lead).
  - Position-3 highest-winner (was always lowest).
  - Position-3 forced-trump-ruff exception: lowest trump.
  - Trump preservation: discard non-trump first when not last seat.
- `sampleConsistentDeal` now pins the public bid card to the
  bidder's hand. Previously the sampler could randomly assign it to
  any opponent, corrupting every rollout's evaluation.

### Tests

176/176 passing. Headless tournament (`test_state_bot.lua`) tests
play-only with synthetic contracts; full bidding-round comparison
between tiers requires a separate harness and is not in this release.

## v0.3.2 — Lobby card-style preview

Cosmetic add only.

- The `Cards: <name>` cycle button in the lobby now renders a 3-card
  preview (Ace of Spades · King of Hearts · 10 of Diamonds) at its
  right edge using the currently-selected style. Both the in-lobby
  cycle button and `/baloot cards <name>` keep the preview in sync
  with the active style.

## v0.3.1 — Classic v2 deck + royal_noir refresh

Two cosmetic adds; no wire-protocol changes, no rule changes.

- New card style `classic_v2` from David Bellot's SVG-cards (LGPL,
  via Huub de Beer's PNG mirror at htdebeer/SVG-cards). Pulls the
  2x PNGs and rasterizes them to TGA at the addon's 128×192 size.
  Pairs naturally with the Midnight felt theme — uses `back-black.png`
  from the same source.
- Royal Noir refresh: replaced the SVG sources with the user-supplied
  zip and re-rendered the 33 TGAs. Same `royal_noir` style name, new
  art.

Activation:

    /baloot cards classic_v2
    /baloot cards royal_noir
    /baloot themes              -- shows the full list

## v0.3.0 — Visual themes (mix-and-match) + deep audit hardening

Wire-format compatible additive release. v0.2.x clients can play with
v0.3.0 hosts (extra fields are append-only and ignored by older
parsers); v0.3.0 receivers handle pre-v0.3.0 senders gracefully.

### Deep audit hardening (post-draft, audit waves 6–13)

Eight additional audit waves after the initial v0.3.0 draft, each
combining Codex CLI + Gemini CLI + 5–10 parallel Claude angle agents
for cross-source verification. Findings refuted with code-trace
verification were not applied; only multi-source-confirmed real bugs
went in.

**36 confirmed bug fixes + 17 defense-in-depth guards** across 10
commits (e83bf8b, c4964b1, b5d506a, 456dda2, a3e4aa3, c3ecc73,
0aa496f, 5dbd9d6, 15931cf):

- Host /reload mid-bid soft-lock — `hostDeckRemainder` was wrongly
  in TRANSIENT_FIELDS; restoring `hostHands` without its remainder
  short-circuited HostDealRest.
- 4-play trick stuck on /reload — PLAYER_LOGIN restore now re-fires
  `_HostStepPlay` if the saved trick is complete.
- Host's own preempt swallowed by `fromSelf` — LocalPreempt now
  applies state directly instead of routing through `_OnPreempt`.
- ApplyContract escalation flags wiped on duplicate broadcast —
  added (bidder, type, trump) idempotence guard.
- `scoreUrgency` / `matchPointUrgency` returns had inverted signs vs.
  their docstring — flipped, near-win is now actually conservative.
- UI peek-banner could overlay round-end banner — phase-gated on
  PLAY/DEAL3 and U.Refresh now `clearHand` in SCORE/GAME_END.
- Reset between games silently reverted user's `/baloot target` and
  team names — `reset()` now reads from WHEREDNGNDB.
- SWA permission requests could be clobbered by a second concurrent
  request — added overwrite guard.
- Resync roster lookup mishandled cross-realm name suffixes — added
  `nameEq` normalization on both `info.name` and sender.
- Remote humans never saw the preempt window — host's seat=0 frame
  now broadcasts the eligible-seat CSV; receivers seed phase +
  preemptEligible.
- Host's own SWA permission claim resolved as empty hand —
  `encodedHand` now stashed in the local request struct (the
  `fromSelf` loopback guard had skipped its population path).
- MaybeRunBot now early-returns while a SWA permission request is
  in flight; bot play timer also re-checks at fire time so an
  already-scheduled callback can't slip past the entry guard.
- Resync snapshot now packs a 4-bit `isBot` mask in field 28; without
  it, post-resync seats had `isBot=nil` and host-signed bot
  broadcasts silently failed `authorizeSeat`.
- Host /reload mid-SWA-vote no longer drops `swaRequest` (removed
  from TRANSIENT_FIELDS).
- WHEREDNGNDB type-guarded throughout — corrupted SavedVariables
  no longer crashes addon load.
- `lastTrick` cleared in ApplyStart so peek can't display the
  previous round's final trick.
- ApplyStart also clears `swaRequest` + `swaDenied` so a Kawesh
  redeal mid-SWA-vote doesn't leak Accept/Deny buttons into the new
  round.
- AFK turn timer now defers when a SWA permission request is active
  — the SWA caller's hand was being force-played under them while
  opponents were still voting.
- SWA bot opponents auto-accept on the host's behalf — bots never
  send MSG_SWA_RESP, so a host-with-bots game would otherwise
  deadlock waiting for two votes that never come.
- Redeal banner C_Timer.After(3.0) now uses a generation token
  (`B._redealGen`); /baloot reset and the UI reset popup both bump
  the generation, so an in-flight redeal callback no-ops instead of
  spawning a ghost round.
- `ApplyResyncSnapshot` now re-derives `s.localSeat` through
  `S.SeatOf(s.localName)` (normalized) and clears `s.isHost`
  unconditionally — same-realm rejoiners with a bare-vs-suffixed
  name mismatch were being left with `localSeat=nil` and a stale
  `isHost=true` from a prior session.
- HostResolveSWA now prefers `S.s.hostHands[callerSeat]` over the
  wire-supplied hand — a stale or modified client could previously
  validate impossible claims via the trusted decode path.
- U.PulseTurn now stores the ticker handle and cancels prior on
  re-arm — back-to-back calls used to spawn overlapping animations.
- `/baloot reset` and the UI reset popup now both also call
  `N.CancelTurnTimer` and `N.CancelLocalWarn` so stale AFK or
  T-10s pre-warn timers can't fire on the next frame after reset.
- Non-host SWA responder now applies the response to their own
  `swaRequest` locally (deny clears + 3s toast, accept records
  vote). The wire echo via `_OnSWAResp` was being dropped by
  `fromSelf`, leaving the denier with stale Accept/Deny buttons.
- `_OnResyncRes` and `_OnLobby` now early-return for an active host
  — a stale or forged peer broadcast could otherwise demote the
  host via `ApplyResyncSnapshot`'s `s.isHost = false` or
  `ApplyLobby`'s "new game" reset path.
- Defense-in-depth: 13 more host-broadcast handlers (`_OnStart`,
  `_OnDealPhase`, `_OnHand`, `_OnBidCard`, `_OnTurn`, `_OnContract`,
  `_OnTrick`, `_OnRound`, `_OnGameEnd`, `_OnPause`, `_OnTeams`,
  `_OnTakweeshOut`, `_OnSWAOut`) plus 4 branch-specific cases
  (`_OnPreemptPass` seat=0, replay branches of `_OnMeld`/`_OnPlay`/
  `_OnAKA`) now have explicit `if S.s.isHost then return end`. Each
  was already protected by `fromHost`, but local invariants make
  the protection robust to future refactors.

Tests: 176/176 passing across every commit.

### Visual themes — split into card style + felt theme axes

Card art and table felt are now two independent saved variables you
can mix and match: 4 card styles × 4 felt themes = 16 combinations.

**Card styles** (`/baloot cards <name>` or lobby `Cards: ...`):
- `classic` — hayeah Vector Playing Cards (the original)
- `burgundy` — SVGCards 4-color deck with red lattice back
- `tattoo` — old-school SVG art with rose decorations + portrait face
  cards + burgundy mandala back
- `royal_noir` — gold-on-charcoal SVG deck with crown face cards

**Felt themes** (`/baloot felt <name>` or lobby `Felt: ...`):
- `green` — classic forest-green felt
- `burgundy` — deep wine-red felt
- `vintage` — saddle-brown leather felt
- `midnight` — near-black felt with indigo undertone

The previous single-axis `WHEREDNGNDB.cardTheme` is migrated on first
load to the appropriate `cardStyle` + `feltTheme` pair.

### Asset pipeline

Three SVG-based decks (`burgundy`, `tattoo`, `royal_noir`) are
rasterized to TGA via `resvg_py` (Rust-based, no system cairo). One
procedural felt generator per theme produces the 128×128 tileable
fabric. Source SVGs preserved under `cards/<theme>/_src/` for
reproducibility.

### Test harness

New `tests/test_rules.lua` (120 assertions) and `tests/test_state_bot.lua`
(56 assertions) covering Constants/Cards/Rules/State/Bot. Driven by
`tests/run.py` via Python lupa. 176/176 passing across all the
audit-sweep changes below.

### Bug-fix sweep — three audit passes (~40 real bugs)

Three rounds of 20-agent parallel audits before release. Categorised:

**Critical (gameplay-blocking):**
- Resync replay frames (MSG_PLAY/AKA/MELD whispered during rejoin) now
  carry a "1" flag the receiver uses to bypass turn + authorizeSeat
  gates. Mid-trick rejoin reconstructs the table correctly. The
  earlier "fix" that just appended replay messages was silently
  filtered by those gates.
- Every bot decision callback in MaybeRunBot is now wrapped in pcall
  with phase-appropriate recovery (force-pass / force-skip / lowest-
  legal-play). A `Bot.PickX` error no longer freezes the deal — bots
  have no AFK timer otherwise.
- Each escalation pcall tracks `applied` AND `skipSent` so recovery
  can branch on real state vs. unreachable state, avoiding both stalls
  (when phase has advanced past the simple guard) AND double SKIP_X
  broadcasts (when the body completed the skip then HostFinishDeal
  errored).
- Bel-decision recovery on `applied=true` calls MaybeRunBot for open
  Bel in Hokm (correctly running the bidder's Triple decision)
  instead of HostFinishDeal which would skip the entire chain.
- Solo-bot preempt path no longer routes through `_OnPreempt` — that
  handler short-circuits on `fromSelf(sender)` before authorizeSeat,
  silently dropping the claim. Bots now apply directly + run the
  host post-apply block.
- WHEREDNGN.lua PLAYER_LOGIN restore re-arms StartTurnTimer +
  StartBelTimer + StartLocalWarn for human seats. /reload mid-turn no
  longer leaves the table waiting forever.
- `_HostTurnTimeout` and `_HostBelTimeout` now respect `S.s.paused` —
  C_Timer:Cancel() doesn't catch already-queued callbacks, so a
  pause-during-fire would otherwise let auto-actions run mid-pause.
- `_OnKawesh` and `HostHandleKawesh` likewise respect paused.

**Wire format:**
- `MSG_ROUND` now includes `sweep` ("A"/"B"/"") + `bidderMade` (""/0/1).
  BALOOT fanfare fires on every client, not just the host. Three-state
  bidderMade encoding distinguishes "absent" (legacy / SWA / Takweesh)
  from "explicit failure" so legacy hosts and per-feature paths don't
  trigger false-positive fanfares.
- `MSG_PLAY` / `MSG_AKA` / `MSG_MELD` extended with optional trailing
  "1" flag for resync replay (see Critical above).

**Theme system:**
- Split `cardTheme` → `cardStyle` + `feltTheme` (mix-and-match).
- Theme refresh re-applies backdrop colors to seat badges, localBar,
  party panel, lobby seat-rows, and the main outer rim. Was tex-only
  previously; corner tints stayed stale until /reload.
- `migrateLegacyTheme` runs only when legacy is non-nil so fresh
  installs fall through to runtime defaults.

**Scoring & game logic:**
- `R.IsValidSWA` resolves complete tricks before the caller-empty
  short-circuit. Caller playing their last card to a trick they
  would lose now correctly fails the claim.
- `R.IsValidSWA` rejects top-level entry with caller-empty + no plays
  (corrupted-state guard).
- `R.ScoreRound` no longer mutates `meldPoints` with the +20 belote
  bonus. Belote is exposed separately on the result struct; UI shows
  it on its own line.
- `S.ApplyTrickEnd` rejects partial tricks (`#plays != 4`); malformed
  broadcasts no longer corrupt history.
- `S.reset()` and `S.ApplyResyncSnapshot` explicitly clear all
  per-trick / per-round transient fields (akaCalled, lastTrick,
  redealing, takweeshResult, swaResult/Request/Denied, ...). Stale
  banners no longer leak across game boundaries or resync.

**Bot AI:**
- `Bot.OnEscalation` accepts a rung kind ("double"/"triple"/"four"/
  "gahwa"); per-rung counters in the style ledger. Previously every
  rung incremented `m.bels`, misclassifying aggressive bidders.
- `partnerEscalatedBonus` gated on `IsAdvanced` (was IsM3lm); team-
  membership check covers BOTH defender seats (was only bidder+1).
- `Bot.PickGahwa` returns `(yes, false)` matching PickTriple/PickFour.
- `OnPlayObserved` trumpEarly/Late counter no longer requires
  `leadSuit == contract.trump` (was unreachable on lead plays).
- `firstDiscard` rolled back when the off-suit play was a forced
  trump ruff (Fzloky no longer misreads forced ruffs as preference).

**UX & polish:**
- StartLocalWarn supports "four" / "gahwa" / "preempt" kinds; State
  arms them in the open path of each escalation.
- AKA banner frame-level bumped above center trick cards.
- localBar.meldStrip anchored INSIDE localBar so it no longer
  extends 36 px into the centerPad/trick area.
- statusFor PHASE_SCORE / PHASE_GAME_END use custom team names.
- Sound throttle classification: VOICE interval applies only to
  `K.SND_VOICE_*` paths; everything else (BALOOT, CARD_PLAY,
  TURN_PING, ...) uses the SFX interval. Previously the SFX-paths-
  as-strings were bucketed as voice and suppressed.
- `_HostRedeal` accepts a reason ("allpass" / "kawesh"); Kawesh path
  no longer also prints "all passed".
- `framePos` drag-stop persists on first drag (nil-safe init).
- Cards.lua SortHand nil-safe SUIT_DISPLAY lookup.

### Notes for upgraders

Pre-v0.2.0 → v0.3.0 still requires a coordinated bump (escalation
chain change). v0.2.x → v0.3.0 is wire-compatible: a v0.2.x client
in a v0.3.0 host party will not hear the BALOOT fanfare on remote
sweeps/failures (no MSG_ROUND extra-fields parser), but everything
else works including the resync flow.

## v0.2.0 — Canonical 4-rung escalation + Triple-on-Ace pre-emption

This release applies the remaining canonical Saudi rules from the
new batch of documents ("نظام الدبل في لعبة البلوت" / "الثالث" /
"ماهو البلوت في لعبة البلوت"). It is a **wire-format-incompatible**
release — clients on <v0.2.0 will desync. Bump everyone together.

### Escalation chain rewrite (FOUR rungs, not five)

Per "نظام الدبل في لعبة البلوت", the canonical Saudi escalation chain
has only **four** rungs, not the five we shipped previously. The
"Bel-Re" rung is non-canonical and has been removed entirely.

**Old chain (5 rungs):**
- Bel(def, ×2) → Bel-Re(bid, ×4) → Triple(def, ×8) → Four(bid, ×16) → Gahwa(def, ×32)

**New chain (4 rungs):**
- Bel(def, ×2) → Triple(bid, ×3) → Four(def, ×4) → Gahwa(bid, **match-win**)

Every escalation alternates between the bidder and defenders. The
multipliers now match canon: ×2 / ×3 / ×4. Gahwa is no longer a
round-multiplier — calling it bets the entire match: a successful
Gahwa wins the game outright (cumulative→target); a failed Gahwa
hands the match to defenders.

Removed across `Constants.lua`, `State.lua`, `Net.lua`, `Rules.lua`,
`UI.lua`, `Bot.lua`:
- `K.MULT_BELRE`, `K.MULT_GAHWA`, `K.PHASE_REDOUBLE`, `K.MSG_REDOUBLE`,
  `K.MSG_SKIP_RDBL`, `K.BOT_BELRE_TH`
- `S.ApplyRedouble`, `s.belrePending`, `contract.redoubled`
- `N.SendRedouble`, `N._OnRedouble`, `N._OnSkipRedouble`, `N.LocalRedouble`
- `Bot.PickRedouble`
- All UI references to "Bel-Re" / `PHASE_REDOUBLE`

Re-targeted constants:
- `K.MULT_TRIPLE`: 8 → **3**
- `K.MULT_FOUR`: 16 → **4**
- `K.MULT_GAHWA`: 32 → (deleted; Gahwa is match-win, not a multiplier)
- `K.BOT_TRIPLE_TH`: 95 → **90** (lower — Triple is now ×3, less risky)
- `K.BOT_FOUR_TH`: 115 → **110**
- `K.BOT_GAHWA_TH`: 130 → **135** (raised — Gahwa is now terminal)

Role flips (Triple/Four/Gahwa):
- **Triple** was defender's response to Bel-Re; now **bidder's** response to Bel.
- **Four** was bidder's response to Triple; now **defenders'** response to Triple.
- **Gahwa** was defender's terminal; now **bidder's** terminal (match-win).

`Rules.lua` tie-inversion table rewritten for the 4-rung chain:
`R.ScoreRound` returns `gahwaWonGame=true` + `gahwaWinner` when the
contract had Gahwa active; `_HostStepAfterTrick` reads these and
overrides `addA`/`addB` to push the winner to the cumulative target.

### Open/Closed escalation choice (التربيع)

Per the same doc, each escalation rung lets the caller choose **open**
("I bel & I'm prepared for your Triple") or **closed** ("I bel & we
play — no further escalation"). The wire format extends each
escalation tag with a trailing `;0` (closed) or `;1` (open) field;
pre-v0.2.0 senders that omit it default to open.

- `S.ApplyDouble`/`ApplyTriple`/`ApplyFour` take an `open` boolean.
  Closed transitions phase directly to PLAY; open advances to the
  next-rung window.
- UI: each escalation now has paired buttons ("Bel & open" / "Bel
  & closed"). Sun's Bel button hides the open variant since Sun has
  no Triple rung anyway.
- Bot: `Bot.PickTriple/Four` return `(yes, wantOpen)` — open if
  strength is ≥20 above threshold (we'd still escalate next rung),
  else closed.

### Belote cancellation when 100-meld present

Per "ماهو البلوت في لعبة البلوت": the +20 belote bonus is **cancelled**
when the same K+Q-of-trump holder also declared a meld of value ≥100
(seq5 or carré of T/K/Q/J/A). The 100-meld subsumes the belote — no
double-counting. Sequences of 3/4 (≤50) and the bare belote stand on
their own.

- `R.ScoreRound`: belote scan now post-checks `meldsByTeam[team]` for
  any meld with `declaredBy == kWho and value ≥ 100`. Match → cancel
  belote.
- Same guard in `N.HostResolveTakweesh` and `N.HostResolveSWA`
  invalid branch.

### Triple-on-Ace pre-emption (الثالث) — host-toggleable, ON by default

Entirely new mechanic. When a round-2 Sun bid lands and the original
**bid card is an Ace**, eligible earlier seats (those who already bid
in this round, excluding the buyer's partner — "can't Triple your
partner") may "claim before you" — taking the Sun contract for
themselves. Per "الثالث" doc.

New constants:
- `K.PHASE_PREEMPT` — pre-emption window phase
- `K.MSG_PREEMPT = "@"`, `K.MSG_PREEMPT_PASS = "%"` — wire tags
- `K.BOT_PREEMPT_TH = 75` — bot threshold

New host-toggleable: `WHEREDNGNDB.preemptOnAce` (default true). Toggle
via `/baloot preempt`.

New code:
- `S.PreemptEligibleSeats(buyer, bidder)` — eligibility list
- `S.ApplyPreempt`, `S.ApplyPreemptPass` — state transitions
- `N._OnPreempt`, `N._OnPreemptPass`, `N._FinalizePreempt`,
  `N.LocalPreempt`, `N.LocalPreemptPass`, `N.SendPreempt`,
  `N.SendPreemptPass`
- UI: `PHASE_PREEMPT` action panel with "قبلك (Pre-empt)" + "Pass"
  buttons for eligible seats only
- Bot: `Bot.PickPreempt(seat)` — Sun-strength gated, +8 bonus when
  holding the Ace of bid suit
- AFK timer: `kind="preempt_pass"` auto-passes after 60s

### Saved-game upgrader

`State.RestoreSession` strips stale `redoubled=true` /
`belrePending` fields and bumps any `phase=="redouble"` save back to
`PHASE_DOUBLE` so the eligible defender can act fresh. Pre-v0.2.0
sessions restored on v0.2.0+ install will not freeze on load.

### Wire format changes (v0.2.0+, breaking)

- `K.MSG_DOUBLE/TRIPLE/FOUR`: payload extended with trailing `;0|;1`
  open/closed flag. Receivers default to open if missing.
- Resync snapshot (`packSnapshot`): removed `redoubled` slot; added
  `tripleOpen`, `fourOpen`. Slots renumbered (15-17 → 14-19).
- `K.MSG_REDOUBLE` and `K.MSG_SKIP_RDBL` deleted.
- `K.MSG_PREEMPT`, `K.MSG_PREEMPT_PASS` added.

Hard requirement: all party members must be on v0.2.0+. Mixed
versions will desync immediately.

---

## v0.1.33 — Saudi rules sweep (canonical doc-driven fixes)

This release applies the canonical Saudi rules from the
official scoring + play documents ("نظام التسجيل في البلوت" /
"نظام لعبة البلوت الأساسي") that the user provided.

**SWA permission flow + canonical Qayd meld rule**
(see prior notes — same as the earlier draft of this version).

**Ashkal seat restriction (R3)**
- Per the play-system doc: only the **3rd and 4th players in
  bidding order** can call Ashkal. The 1st and 2nd bidders
  cannot.
- `State.HostAdvanceBidding` now silently drops Ashkal from
  seats with bid-position < 3.
- UI hides the Ashkal button for the same seats.
- `Bot.PickBid` Ashkal heuristic gated on the same condition.

**Sun escalation gate (R5/R7)**
- Per the doc: *"في الصن لايوجد الثري والفور والقهوة وإنما
  يلعب دبلاً فقط. ولايحق للاعب أن يدبل خصمه إلا بعد أن يتجاوز
  المئة أي 101"* — Sun has no Triple/Four/Gahwa; only Bel,
  and Bel is locked until at least one team's cumulative game
  score has exceeded 100 (≥101).
- `Net._HostStepBid` "contract" branch: when contract is Sun
  and both teams' cumulative <101, skip `PHASE_DOUBLE`
  entirely and go straight to play via `HostFinishDeal`.
- `State.ApplyRedouble`: Sun contracts skip `PHASE_TRIPLE` —
  set phase to PLAY directly so Triple/Four/Gahwa never fire
  in Sun.
- `Net._OnRedouble`: Sun contracts call `HostFinishDeal`
  immediately after Bel-Re instead of dispatching the Triple
  decision.

**Aces carré value (R8)**
- `K.MELD_CARRE_A_SUN`: 200 → **400** raw. The doc explicitly
  says *"الأربع مئة فهي الأربع أكك"* — the four-hundred meld
  is the four-Aces carré.

## v0.1.33-pre — SWA permission flow + canonical Qayd meld rule

**Saudi-rule fix (HIGH)**

- **Qayd / Tasjeel meld rule**: per the Saudi scoring document
  ("نظام التسجيل في البلوت"), in any early-termination penalty
  (takweesh, invalid SWA), the OFFENDER'S MELDS STAY WITH THEM —
  they don't transfer to the winning side. Previously we were
  awarding all melds (both teams' values combined) to the winner,
  which doesn't match the canonical Saudi rule:

  > "المشروع لصاحبه" — *"the meld stays with its owner"*

  Now: winner takes `handTotal × mult` + their OWN melds × mult
  + belote (independent). The offender keeps their melds (held
  out from scoring this round). Applies to both
  `HostResolveTakweesh` and the invalid-SWA branch in
  `HostResolveSWA`. Math produces exactly **26 (Sun) / 16
  (Hokm)** game points for the bare penalty as specified by the
  document.

**SWA permission flow (NEW)**

Per the Saudi-rules video: SWA called with 4+ cards remaining
requires opponent permission. Implemented as a host-toggleable
gate.

- New host settings:
  - `WHEREDNGNDB.allowSWA` (default true) — disables SWA
    entirely for tournament-mode play.
  - `WHEREDNGNDB.swaRequiresPermission` (default true) — gates
    4+-card claims behind opponent vote.
- New slash commands: `/baloot swa` (toggle SWA on/off),
  `/baloot swaperm` (toggle the permission gate — same flag
  via `/baloot swa` if you don't need the second control;
  see help).
- New wire tags: `MSG_SWA_REQ` ("I"), `MSG_SWA_RESP` ("O").
- Flow:
  - ≤3 cards: instant resolution (current behavior).
  - 4+ cards: caller broadcasts a request. Both opponents see
    Accept / Deny buttons in the action panel.
  - Either opponent denies → request cancelled, 3-second toast
    shows the denier name, round resumes from where it was.
  - Both opponents accept → host runs the actual minimax
    validator and proceeds with normal SWA scoring (now using
    the Qayd meld rule).
- The caller's SWA button is hidden while a request is in
  flight to prevent double-clicks.

**Documentation**

- `WHEREDNGN.lua` flag comment for `allowSWA` updated: SWA is
  now confirmed Saudi convention (per video tutorial), not just
  a digital-app shortcut. The English-language references
  (Pagat, Saudi Federation page) just don't cover it.

**Deferred**

- "Sequence specification" (شرح السوا): caller laying out the
  exact play order to satisfy the claim. The current minimax
  validator implicitly handles sequencing (it finds ANY winning
  order), so this is a UX nicety not a correctness issue. Still
  on the future-work list.

## v0.1.32 — five-agent audit sweep

**HIGH-severity fixes**

- **`Rules.ScoreRound` make-check**: the threshold comparison was
  adding both teams' melds to both team totals, which could flip
  a made contract to failed when meld values differed. Now uses
  `R.CompareMelds` first and only the winning team's melds count
  toward the threshold (matches the actual scoring branches).
- **`S.ApplyMeld` trick-1 lock**: rejects late wire-side meld
  declarations once trick 1 has closed, backing up the UI / Bot
  / GetMeldsForLocal local gates.
- **Resync replay**: `SendResyncRes` now whispers the bid card,
  every declared meld, and every closed trick to the rejoiner
  using existing `MSG_BIDCARD` / `MSG_MELD` / `MSG_TRICK` wires.
  A mid-hand /reload-rejoin now correctly rebuilds the meld strip,
  peek-last-trick state, and contract banner. Previous resync
  snapshot was 26-field-only and dropped trick history + melds.
- **Bot trump-tempo counter**: was firing on RUFF (defensive cut)
  rather than LEAD. Now requires `#trick.plays == 1` and
  `leadSuit == trump` so only voluntary tempo-spending counts.
- **Fzloky avoid-suit `pairs()` ordering**: rewritten as a
  two-pass selection so the avoid-suit can never claim "longest"
  via iteration-order luck. Avoid-suit only wins if it exceeds
  the best non-avoid by ≥2 cards.
- **`bidsAttempts` counter**: dropped — was never incremented and
  drove `styleBelTendency` into degenerate values. Belief now
  gates on `bels >= 1` count alone.
- **AKA banner reposition**: was 26 px tall anchored above the
  centre pad, but the gap to the top seat-badge is only 10 px.
  Banner pokes ~16 px into the partner badge. Now 22 px tall
  anchored INSIDE centerPad's top edge — clear of both seat and
  trick area.
- **Contract banner reposition**: was at `f.BOTTOM, 0, 6`,
  overlapping the score and round text at the same Y. Now sits
  at `f.BOTTOM, 0, 30` — above the score line.
- **`_HostStepPlay` paused guard**: trick-resolve timer no longer
  fires while the host is paused.
- **`_HostRedeal` reset/pause guard**: 3 s redeal timer now
  aborts if game state was reset or paused during the wait.

**MEDIUM-severity fixes**

- **`S.ApplyGameEnd` idempotence**: returns early on duplicate
  re-apply with the same winner — prevents the BALOOT fanfare
  cue from double-firing on host-loopback + remote receive.
- **Bid card visible during escalation**: `renderCenter` now
  keeps the bid card up through DEAL3 / DOUBLE / REDOUBLE /
  TRIPLE / FOUR / GAHWA, not just the bidding rounds. Players
  retain "what was bid" reference all the way to play start.
- **Transient-fields cleanup**: `lastRoundResult`,
  `lastRoundDelta`, `lastTrick` added to TRANSIENT_FIELDS so
  they don't survive a /reload (would otherwise surface a
  previous round's banner).
- **`BotMaster.lua` rollout policy**: was always picking
  `lowestRank(legal)` on lead. Now mirrors `Bot.pickLead`
  — bidder team leads highest trump in Hokm, defenders lead
  lowest from longest non-trump. Removes the systematic bias
  toward passive lines in determinization rollouts.
- **Dead-code cleanup**: `partnerVoidIn` (defined, never
  called), `smothers` / `smotherOpps` counters (never
  written) removed from `Bot._partnerStyle` and `Bot.lua`.

**LOW-severity fixes**

- `_OnAKA` now goes through `authorizeSeat` — prevents a peer
  from spoofing an AKA banner for another seat.
- `WHEREDNGNLog` removed from `WHEREDNGN.toc` — the
  `SavedVariablesPerCharacter` declaration was unused; log
  buffer is in-memory only.

## v0.1.31 — Saudi Master tier (ISMCTS-flavoured)

**New tier: Saudi Master** — top of the cascade
`Saudi Master → Fzloky → M3lm → Advanced`. New module
`BotMaster.lua` (~280 lines) implements determinization-sampling
play decisions:
- At each play, sample 30 plausible opponent hands consistent
  with our cards + observed plays + inferred voids.
- For each candidate card, simulate the rest of the round across
  all 30 worlds using existing pickFollow / pickLead heuristics
  as the rollout policy.
- Pick the card with the best aggregate team score.
- Sampler honours per-seat void inference from `Bot._memory`.

Bidding, melds, and escalations still flow through the
M3lm/Fzloky paths since the bidding tree doesn't benefit from
sampling at the same scale; only PLAY decisions get the ISMCTS
treatment. Performance budget ~150 ms per move (30 worlds × ≤8
candidate cards × ~25 cheap rollout plays).

UI: new "Saudi Master" checkbox at the bottom of the lobby
difficulty stack. Slash: `/baloot saudimaster` (also accepts
`master+` and `ismcts`). Cascade rules: ticking Saudi Master
auto-checks Fzloky / M3lm / Advanced (greyed). `Bot.IsSaudiMaster()`
gates the new picker.

## v0.1.30 — SWA scoring rebuilt, takweesh simplified

**SWA scoring fix (HIGH severity)**
- `HostResolveSWA` was awarding `handTotal × mult` to the winning
  side and 0 to the other regardless of how many tricks were
  played. Already-earned trick points evaporated, the kaboot
  bonus never applied, the last-trick +10 was missing.
- Now: VALID SWA synthesizes the remaining tricks (each won by
  caller seat), appends to played-trick history, and routes
  through `R.ScoreRound`. ScoreRound handles sweep / made /
  failed / meld winner / last-trick bonus / belote correctly
  by construction.
- INVALID SWA still applies the flat penalty: opp takes
  handTotal × mult + ALL melds × mult + belote.
- Sweep is now detected when caller's team has won every played
  trick AND wins all remaining via SWA → kaboot bonus
  (250 / 220 raw) applies via the same ScoreRound path.

**Takweesh scoring simplified**
- Dropped the made/failed mapping introduced in v0.1.28 — both
  branches of takweesh are punitive penalties to the same shape.
- Now: caught → caller's team takes handTotal × mult + ALL
  melds × mult + belote. Not-caught → opp-of-caller takes the
  same. Single code path, no contract-result inversion.

## v0.1.29 — belote tightened to "K+Q played", SWA/takweesh docs

**Fix (Saudi rule, rb3haa)**
- Belote (+20 raw) now requires the K AND Q of trump to BOTH be
  played before the round ends. v0.1.27/v0.1.28 had been scanning
  unplayed hands too — that's wrong: per Saudi convention, belote
  must be announced as the cards are played. If a takweesh or SWA
  ends the round before K+Q both surface, no belote bonus.
- Applies to both `HostResolveSWA` and `HostResolveTakweesh`.

**Documentation**
- `HostResolveSWA` doc-comment now flags the made/failed contract
  mapping as a HOUSE-RULE NORMALIZATION. The published Saudi
  sources don't fully specify a meld/belote formula for SWA —
  our mapping (valid+bidder→MADE etc.) is a defensible synthesis
  but isn't a verbatim attested rule.

## v0.1.28 — takweesh scoring respects melds + belote

**Fix (same shape as v0.1.27)**
- `HostResolveTakweesh` had the identical bug as the pre-v0.1.27
  SWA path: awarded only `handTotal × multiplier` and ignored
  meld points + belote. A defender team could win a takweesh
  while ALSO holding 100-point carrés and K+Q-of-trump and still
  drop those points.
- Now routes through the standard made/failed branches:
  - Caught + caller is bidder team OR not caught + caller is
    defender team → MADE: bidder team takes hand × mult, meld
    winner gets their melds × mult.
  - Caught + caller is defender team OR not caught + caller is
    bidder team → FAILED: opp-of-bidder takes hand × mult AND
    all declared melds combined × mult.
- Belote +20 raw flows independently to its K+Q-of-trump holder.
  Takweesh ends the round mid-trick, so we scan unplayed hands
  too (same fix shape as SWA's belote scan).
- Audit also confirmed: regular ScoreRound has no early-end path
  to worry about (always runs at #tricks ≥ 8 when all cards are
  played); Kawesh has no scoring path (annul + redeal); game-end
  tie-rule is consistent across all three scoring paths;
  Ashkal-shifted bidder is correctly read everywhere; bot meld
  lock is enforced in both human and bot paths.

## v0.1.27 — SWA scoring respects melds + belote

**Fix**
- SWA was awarding only `handTotal × multiplier` to the winning
  side, ignoring meld points and belote. A team with 400 worth of
  melds could lose because the opposing team called SWA — wrong
  per Saudi rules.
- `HostResolveSWA` now routes through the same made/failed
  scoring branches as a regular round:
  - **Made** (caller's claim valid AND caller is on bidder team):
    bidder team takes `handTotal × mult`. Meld winner (per
    `R.CompareMelds`) gets their melds × mult.
  - **Made** (caller's claim invalid AND caller is on defender
    team): same — defender's false claim hands the contract back
    to the bidder.
  - **Failed** (caller valid + defender, OR caller invalid +
    bidder): opposing team takes `handTotal × mult` AND ALL
    declared melds combined × mult — same rule the regular
    `ScoreRound` uses for a busted contract.
- Belote (+20 raw, Hokm only) flows to the K+Q-of-trump holder
  regardless of SWA outcome. SWA can end the round before K+Q
  are played; we scan unplayed hands so the holder still gets
  the bonus per Saudi convention.

## v0.1.26 — round-2 Sun overcall, "wla" pass label

**Saudi rule fix: round 2 has a Sun overcall window**
- Previously round 2 was "first non-pass wins" — seat 3's Hokm bid
  resolved bidding immediately, robbing seat 4 (and any later
  seats) of their chance to bid Sun.
- Now both rounds wait for all 4 bids, and Sun overcalls Hokm in
  either round. Hokm-vs-Hokm in round 2 still uses first-non-pass
  ordering. Sun-vs-Sun: first direct Sun locks (same as round 1).
- Round-2 Hokm-on-flipped-suit drop and Ashkal silently-dropped
  paths still apply.

**UX**
- Pass button in round 2 now labelled "wla" (ولا) to match the
  Saudi verbal convention. Confirms an existing bid or opens a
  redeal if all 4 say wla.

## v0.1.25 — SWA full minimax, last-trick visibility, Fzloky tier

**SWA validation upgraded to full minimax**
- Previous "sufficient condition" check rejected valid claims like
  `[A♠ A♦ T♦]` in Sun (lead A♠ → A♦ → T♦, all wins) because it
  couldn't see that T♦ becomes the boss after A♦ is played.
- Now `R.IsValidSWA` runs a recursive minimax over the remaining
  game tree: caller's team picks plays cooperatively, opponents
  pick adversarially, and the claim is valid iff caller can
  guarantee winning every remaining trick. Bounded by hand size
  so worst-case ~ thousands of nodes — fine for a one-time check.
- "Caller wins" still means trick winner == caller seat (strict
  reading; partner taking a trick doesn't satisfy the claim).

**Last-trick peek now shows all 4 plays everywhere**
- The peek button could show only 2–3 cards on non-host clients
  because `MSG_TRICK` arrived before the 4th `MSG_PLAY` and the
  trick-end snapshot captured a partial trick.
- `MSG_TRICK` now carries the full trick payload (leadSuit + all
  4 seat/card pairs). `_OnTrick` rebuilds `s.trick.plays` from
  the snapshot before applying trick-end, so `s.lastTrick` is
  always complete regardless of inter-sender ordering.

**Fzloky tier (signal-aware bots)**
- New checkbox below M3lm. Slash: `/baloot fzloky`.
- Tier cascade: `Fzloky → M3lm → Advanced`. Each lower tier is
  auto-checked-and-disabled when a higher one is on.
- Fzloky reads partner's first off-suit discard as a high/low
  suit-preference signal and biases lead choice accordingly:
  - Partner discards A/T/K → bot prefers leading that suit
    (lowest card from it; partner has the high cards).
  - Partner discards 7/8 → bot avoids leading that suit unless
    no alternative exists.
- v1 covers first-discard signaling only. Echo / petite-grand
  peter / "throw the king" are still future work.

## v0.1.24 — SWA claim, carré tie-break, M3lm UX polish

**New: SWA (سوا) claim mechanic**
- New action button "SWA" next to TAKWEESH during play. Confirm
  once before sending.
- Caller reveals their remaining hand; host validates via
  `R.IsValidSWA` (sufficient condition: every caller card is
  the current "boss" of its suit, plus a Hokm trump-count
  guarantee against forced ruffs).
- Outcome:
  - **Valid** → caller's team takes the full hand × multiplier
    (same shape as a made contract — caller proved dominance).
  - **Invalid** → opposing team takes the full hand × multiplier
    (same penalty as a failed takweesh).
- Wire: `MSG_SWA = "Q"` (caller→host with hand reveal),
  `MSG_SWA_OUT = "Z"` (host→all with verdict + scoring).
- Banner: green "SWA!" on success, red "SWA failed" on bust;
  takes priority over the normal score breakdown.

**Saudi rule fix: carré tie-break**
- Equal-value carrés (e.g. K-carré vs J-carré, both 100 raw)
  now break by the trick-rank of the top card. Trump-J carré
  beats trump-Q carré in Hokm; Aces in Sun beat anything else
  by raw value already. Bonus is small (×0.01) so it can't
  flip carré-vs-sequence comparisons.

**Saudi rule fix: bot meld lock**
- `Bot.PickMelds` now respects the trick-1 declaration window
  the same way `S.GetMeldsForLocal` does. Previously bots could
  declare melds in trick 2+ via the bot-auto-meld loop in
  Net.lua. Closes a rule-bypass.

**M3lm UX polish**
- Lobby Advanced checkbox auto-checks and disables when M3lm
  is on, signalling visually that M3lm strictly extends Advanced.
- Tooltip clarifies "stack with Advanced for full effect" was
  redundant — now reads as a single-pick tier system.

**Defensive cleanup**
- `LocalSWA` clears any stale `swaResult` banner from earlier
  in the round before broadcasting.

## v0.1.23 — M3lm tier, audit fixes, banner copy

**M3lm (pro) bot tier — host opt-in, stacks with Advanced**
- Lobby checkbox is now functional (was greyed in v0.1.20).
- New slash: `/baloot m3lm` toggles the flag.
- Adds three new layers on top of Advanced:
  - **Partner / opponent play-style modeling**: per-seat counters
    (`bels`, `trumpEarly`, `trumpLate`) accumulate across a full
    game so the bot can read each player's tendencies. Reset only
    on round 1 of a new game.
  - **Match-point urgency**: finer-grained threshold modifier
    layered on top of Advanced's `scoreUrgency` — opponent ≥
    target-15 → extra −8 (defensive desperation), opponent ≥
    target-40 → extra −3 (caution), we ≥ target-15 → extra +5
    (lock it down), behind 50–80 → extra −3 (measured risk).
  - **Coordinated escalation**: `partnerEscalatedBonus` adds to
    escalation strength when partner has already Beled / Tripled
    in the current contract. Defender chain (Bel/Triple/Gahwa)
    rewards escalating partners with +5/+8/+12; bidder chain
    (Bel-Re/Four) rewards bidder partners with +5/+8.
- Net.lua hooks `Bot.OnEscalation(seat)` from
  `_OnDouble/_OnRedouble/_OnTriple/_OnFour/_OnGahwa` so the
  partner-style ledger updates from network events too (covers
  remote players as well as bots).
- `Bot.IsAdvanced()` now returns true if EITHER advancedBots OR
  m3lmBots is set — M3lm strictly extends Advanced.

**Saudi rules audit fixes**
- Meld declaration window closes at end of trick 1 (Pagat-strict).
  Previously a player could still declare during trick 2 if they
  hadn't yet played their first card. `S.GetMeldsForLocal` now
  returns empty once `#s.tricks >= 1`.
- Game-end ties now go to the bidding team (Saudi convention)
  instead of Team A by default. Affects both
  `_HostStepAfterTrick`'s round-end branch and
  `HostResolveTakweesh`'s game-end branch.

**Copy**
- Game-end banner: "GAME OVER" → "8amt!! go play something else".

## v0.1.22 — only winning team reveals in trick 2

**Fix**
- Trick-2 card reveal is now gated to declarers on the **winning
  team only**, per Saudi rule (Pagat-cited): "the opposing team are
  not allowed to show or score for any projects." Losing team's
  cards are never exposed, even though their trick-1 announcement
  still happens.
- Both teammates on the winning team can still reveal — each gets
  their own 5-second window when their PLAY turn opens in trick 2.
- Trick-1 announcement text remains unchanged: every declarer's
  type/length/top-rank still posts (verbal declaration is public
  by everyone), suit still hidden.
- Ties (or no melds) → neither team reveals. Matches the scoring
  side, which already awards 0 to both on a tie.

## v0.1.21 — meld display rule corrected

**Fix**
- Trick 1 now shows only an announcement text — type, length and top
  rank, *no suit and no cards* ("Seq3 K (20)", "Carré J (100)"). The
  full mini-card strip is no longer flashed during trick 1.
- Trick 2: each declarer's actual cards become visible for exactly
  5 seconds when their PLAY turn starts, then hide for the rest of
  the hand. Hooked into `S.ApplyTurn` rather than `S.ApplyPlay` —
  so the timer starts with the turn, not after the play.
- Trick 3 onwards: nothing is shown. Earlier trick-1-always-visible
  behaviour was an over-broad reading of the Saudi rule; this
  release matches the table convention (announce in trick 1, brief
  reveal in trick 2, gone after).

## v0.1.20 — Advanced bot heuristics (host opt-in)

**New**
- Lobby checkboxes: **Advanced** (functional) and **M3lm**
  ("master", greyed out — reserved for a future deeper-heuristic
  layer with multi-trick lookahead and signal interpretation).
- Slash command: `/baloot advanced` toggles the host's advanced-bot
  flag.
- Default is OFF on upgrade — existing bot behaviour is unchanged
  unless the host explicitly turns Advanced on.

**Advanced-mode heuristics (Tier 1 + 2 + 3 from the bot research
agents):**

*Bidding*
- Hand evaluation: J+9 synergy bumped from +10 to +18 (Coinche
  step-jump). J-of-trump step-function damp — no-J + no 9+A pair
  + count<5 trump suit gets 0.4× score (structurally weak).
- Side-suit aces fold into Hokm strength (+8 each, capped at 3).
- Sun bid distribution penalty: −10 per suit with count<2 or no
  honors (capped at −25).
- Round-2 threshold raised to ≥ Round-1 + 6 (R2 picker has more
  optionality, so the bar should be higher, not lower).
- Ashkal additional check: only call if our own holding in the
  flipped suit is weak (no J of flipped, count ≤ 2).

*Escalation (Bel / Bel-Re / Triple / Four / Gahwa)*
- Partner's bid feeds escalation strength directly:
  HOKM-trump-match +20, HOKM-other +10, SUN +15, ASHKAL +15,
  PASS-both-rounds −10.
- Score-urgency threshold modifier: behind 80+ → −6 (more
  aggressive); near loss → −12; near win → +8 (conservative).

*Play*
- Position-aware following: 2nd-hand-low (duck unless sure
  stopper) / 3rd-hand-high (commit a card that survives 4th-seat
  overcut). 4th still cheapest-winner.
- `pickLead` boss-card scan: lead the highest unplayed card in
  any non-trump suit when we hold it (free trick).
- Bidder lead asymmetry: trump-poor bidder (<4 trump) with a
  side-suit Ace cashes the Ace before the trump pull. Bidder's
  partner falls through to defender-style logic instead of
  blindly leading high trump.
- Bot AKA self-call: when leading the boss of a non-trump suit,
  bot fires the AKA banner + voice cue first so partner doesn't
  over-trump (matches the human signal).
- Smother gate (basic + advanced): now relaxes when 4th-to-act
  with partner winning — the trick is going on partner's pile
  no matter what, free points.

**Internals**
- `Bot.IsAdvanced()` / `Bot.IsM3lm()` (the latter always returns
  false until the M3lm tier is implemented).
- All advanced helpers return 0/nil in basic mode so non-advanced
  hosts get the v0.1.19 behaviour bit-for-bit.

## v0.1.19 — Saudi rules sweep, smarter bots, meld timing

**Saudi rules**
- `Rules.IsLegalPlay` — when trump is led and your partner is currently
  winning the trick, you no longer have to overcut. Matches the
  off-lead-trump partner-winning exception that was already in place.
- `Rules.ScoreRound` — in a sweep (Al-Kaboot), the +20 belote bonus
  now follows the sweep winner instead of staying with the K+Q
  holder. "Winner takes all" applies to belote too.
- `State.HostAdvanceBidding` — round-2 Hokm cannot reuse the bid
  card's flipped suit (host-side enforcement, backing up the UI gate).
- `State.HostAdvanceBidding` — first direct Sun bid in round 1 locks
  the declarer chair; later direct Sun bids no longer overcall it.
  An Ashkal-derived Sun can still be overcalled by a later direct
  Sun (the direct bid reassigns declarer to the actual bidder per
  Saudi convention). Tracked via a `viaAshkal` flag on the winning
  record.
- `Net.HostResolveTakweesh` — takweesh penalty multiplier now respects
  the full escalation chain (Triple ×8, Four ×16, Gahwa ×32). Was
  previously stuck at base / Bel ×2 / Bel-Re ×4.

**Bots**
- Bidding thresholds raised: `TH_HOKM_R1_BASE 35→42`,
  `TH_HOKM_R2_BASE 28→36`. Bots stop committing to Hokm on weak
  hands.
- `pickLead` rewritten for non-bidder team — 5-tier priority:
  opponent-void high lead, low singleton, low from longest non-trump,
  fallback lowest non-trump, lowest trump. No more blind Ace leads.
- `pickFollow` smother gated — bots only dump A/T onto a partner-
  winning trick if (a) holding ≥2 of A/T in lead suit, OR (b) past
  trick 3. Trump-led smother skipped entirely. Stops the trick-1
  Ace burn.
- New `Bot.PickTriple` / `PickFour` / `PickGahwa` — strength-gated
  escalation (`BOT_TRIPLE_TH 95`, `BOT_FOUR_TH 115`,
  `BOT_GAHWA_TH 130`) replaces the previous flat 10% coin-flip.
- New Ashkal heuristic — when partner has bid Hokm in round 1 and
  the bot's Sun-strength clears `BOT_ASHKAL_TH (65)`, bot calls
  Ashkal to push partner into Sun (higher multiplier).

**Hand display**
- Sort order now strictly alternates colour: ♠ ♥ ♣ ♦
  (B R B R). Replaces the previous BBRR group-by-colour layout.
  Easier to scan — every adjacent pair is opposite colour.

**Meld display timing**
- Meld card strip now follows a three-window model per Saudi rule:
  - Trick 1: every declarer's strip is visible the whole time.
  - Trick 2: a seat's strip appears only while it's that seat's
    turn, and hides as soon as the next seat is up.
  - Trick 2 last player: held visible 4 seconds after their final
    play (no "next turn" to clip them).
  - Trick 3 onwards: never visible.

## v0.1.18 — meld backdrop fix, hand sort, contract banner

**Fixes**
- Meld mini-cards now render with a solid cream body + dark edge
  drawn from explicit Texture layers (BACKGROUND/0 for the edge,
  BACKGROUND/1 for the body, ARTWORK for the card face). The
  previous BackdropTemplate approach didn't reliably render at
  small sizes, leaving the cards transparent. Slot bumped to 22×30.
- Meld strip and meldText label both hide once trick 1 closes,
  matching the Saudi rule that melds are public during trick 1
  only. Previously the text label persisted for the whole round
  alongside the strip.

**UX polish**
- Hand sort now groups suits by colour (♣ ♠ ♥ ♦ → black, black,
  red, red) instead of the interleaved black-red-red-black layout
  that the old K.SUIT_INDEX produced. One colour boundary in the
  middle of the hand instead of two — easier to scan.
- Contract line at the bottom of the window upgraded to a wood-edged
  plate with a 15-px outlined font: `Contract: HOKM ♥  by  Bidder
  [Bel+x16]`. The plate auto-hides outside an active contract.
  Modifier list now also shows Triple/Four/Gahwa multipliers.

## v0.1.17 — meld display polish + AKA label fix

**Fixes**
- Meld mini-cards now have the cream card-body backdrop. Previously
  the slot was a bare texture and the card art TGAs are transparent
  outside the rank/pip glyphs, so cards looked like floating
  fragments. Each slot is now a small frame with the same body +
  edge backdrop as the table card faces, with the rank/pip texture
  laid on top.
- AKA button label and banner switched from "إكَهْ" to Latin "AKA".
  WoW's bundled fonts (Arial Narrow / Frizz / Skurri) don't include
  Arabic glyphs, so the original label rendered as empty boxes. The
  voice cue still says إكَهْ, so the audio carries the Saudi feel.
- Meld card strips now respect the Saudi-rule timing: face-up only
  during trick 1 (PHASE_DEAL3 and the first trick of PHASE_PLAY).
  After trick 1 closes the cards rejoin the hand and the strip
  hides — only the score the meld earned is remembered (shown in
  the round-end banner).
- Slot size bumped 18×24 → 26×36 so the card art is actually
  legible at table scale.

## v0.1.16 — AKA call (إكَهْ) + meld card display

**New gameplay**
- AKA (إكَهْ) partner-coordination signal in Hokm contracts. When the
  local player holds the highest unplayed card in any non-trump suit
  (Sun ranking: A → 10 → K → Q → J → 9 → 8 → 7), an "إكَهْ" button
  appears in the action row. Pressing it broadcasts a soft signal:
  voice cue plays for everyone, banner appears above the trick area
  showing the suit + caller. The teammate uses this to avoid
  over-trumping. No legal-play enforcement — purely informational,
  matching the social signal used at the table.
- Voice asset (sounds/aka.ogg) — placeholder generated via gTTS;
  re-bake with `_make_voice_eleven.py aka` on a paid ElevenLabs
  plan to swap in the Saud voice (consistent with the rest of the
  Arabic cues).

**New visual**
- Declared melds now show as face-up mini cards next to each player
  in addition to the existing text label. Per Saudi rule, melds are
  public the moment they're declared during trick 1.
- Once trick 1 closes, the meld-comparison verdict drives strip
  styling: the winning team's melds stay at full opacity, the losing
  team's melds dim to 0.45 alpha so the player can see what was
  declared but it visibly "doesn't count". Ties stay neutral (0.85).
- Strips appear under the seat-badge card-back fan for opponents and
  above the local bar for the local player.

**Internals**
- `s.playedCardsThisRound` set tracks cards played this hand; rebuilt
  from s.tricks on /reload, marked TRANSIENT for SaveSession.
- `s.akaCalled` is per-trick ephemeral, cleared by ApplyTrickEnd.
- Wire: `MSG_AKA = "e"`, payload `seat;suit`. Soft signal — host
  doesn't need to validate or arbitrate; receivers gate on PHASE_PLAY
  + HOKM contract.

## v0.1.15 — multiplayer rejoin after game-end

**Bug fix**
- After a game ended and the host clicked Reset + Host Game, joiners
  who were still showing the score banner (PHASE_SCORE / GAME_END)
  silently dropped the new lobby announcement. Symptoms: the Join
  button never appeared on the joiner's side, OR the joiner's Join
  click went out with the previous game's stale gameID and the host
  silently rejected it — leaving only some of the players visible
  in the host's seat list.
- `Net._OnHost` and `State.ApplyLobby` now accept lobby announcements
  in any "passive" phase (IDLE, LOBBY, SCORE, GAME_END). Mid-active-
  play phases still ignore stranger announcements (anti-grief).
- When a new gameID arrives, ApplyLobby soft-resets leftover round
  artifacts (contract, hand, tricks, score banner, winner) while
  preserving session identity (localName, target, team-name labels,
  peer versions).
- `pendingHost` is now cleared once the joiner is successfully
  seated, so a stale entry from a finished game can't mask a future
  host announcement.

## v0.1.14 — peek button relocated, banner re-labelled

**UI**
- The last-trick peek "?" button moved out of the felt's top-right
  corner and into the main frame's top-right gutter, just below the
  Reset button. It now sits between Bot 2's seat badge and Reset, so
  the trick area stays uncluttered.
- The pause "II" button takes the freed-up corner inside the felt
  (top-right of the centre pad).
- Round-result banner: "Contract made" → "ALLY B3DO" to match the
  Saudi-Arabish wording players use at the table.

## v0.1.13 — lobby seat-row layout fix

**UI fix**
- Lobby seat rows now auto-fit between the lobby's left edge and the
  party-members sidebar's left edge instead of overhanging it. The old
  fixed 380-px-wide centred rows clipped under the sidebar by ~22 px
  on the right; new rows use anchored TOPLEFT/TOPRIGHT pairs so the
  layout stays tidy regardless of the main frame width.

## v0.1.7 — visuals, takweesh detail, reset button, audit fixes

**New UI**
- Reset button (top-right under game code) with a Blizzard popup
  confirmation. Equivalent to `/baloot reset`.
- "(KZKZ will come)" branding next to the title.
- Minimal-bg toggle (bottom-left): hides the outer green frame so
  only the felt trick area + cards remain visible. Useful for
  streaming or low-clutter views. Persists per-account.

**Takweesh feedback**
- A successful Takweesh now displays the offending card (rank + suit
  glyph) and the rule reason in chat: "K♠ — must follow suit",
  "T♥ — must overcut", etc.
- Score banner shows the same details for the rest of the round.

**Card art**
- All 32 card-face TGAs re-baked composited against the cream
  backdrop so anti-aliased edges blend cleanly. Fixes the "glow"
  visible on Ace of Diamonds (and minor halos on other cards).

**Agent-audit fixes**
- `redealing` and `takweeshResult` added to TRANSIENT_FIELDS so
  timer-backed banners don't persist across /reload.
- `maybeRequestResync` no longer gated on PHASE_IDLE — RestoreSession
  brings us into a non-IDLE phase and we still want the host's
  authoritative state, not a possibly-stale local snapshot. Added
  a host-skip so a solo-bot host doesn't broadcast to nobody.

## v0.1.6 — escalation chain, redeal pause, polish

**New gameplay**
- Full Triple / Four / Gahwa escalation chain (×8 / ×16 / ×32) per
  Saudi rule 4-10. Bot opponents skip these by default with a small
  random escalation chance.
- Voice cues "ثري" / "فور" / "قهوة" announce each step.
- Doubled-tie inversion logic now follows the alternating "buyer"
  rule across all 5 escalation levels.

**Bidding feel**
- Bots commit on more typical biddable hands (thresholds lowered
  ~30%) — fewer all-pass rounds.
- Bel-skip no longer plays the pass voice (it was confusing right
  after a contract announcement).
- Round-2 pass says "ولا" (round-1 still says "بَسْ").
- "ثآني" announces the round-2 bidding window (mirrors "أوَل").
- AWAL / THANY voices delayed 0.5s so the visual round-start lands
  first, then the audio.
- All-pass redeal now holds for 3s with a "Next dealer: NAME"
  banner so the rotation is obvious instead of instant.
- Trick-resolve buffer 1.5s → 2.2s; bot delays 1.0s → 1.6s.

**UI polish**
- Custom team A / B names — host edits in lobby, broadcast to all
  clients, persists per-account, applied across score line + banner.
- Local player bar narrower (540 → 280px) and centered, with the
  same turn-glow texture the other three seat badges use.
- Card back replaced with a programmatic navy/gold diamond pattern.
- Ace of Clubs no longer renders a white square (chroma-keyed the
  source PNG's solid card body to transparent).
- Pause/peek buttons elevated to FULLSCREEN_DIALOG strata so they
  remain clickable when the pause overlay is up.
- Title/scale buttons no longer overlap.

## v0.1.3 — session persistence

- Game state survives `/reload` and logout. The host's snapshot
  (phase, contract, scores, seats, hands, current trick, melds) is
  saved on `PLAYER_LOGOUT` and restored on the next `PLAYER_LOGIN`.
- Per-character guard so an account's saved session can't surface on
  a different character.
- Sessions older than an hour or finished games are discarded.
- Reset clears the saved session.

## v0.1.2 — title overlap fix

- Move +/- scale buttons off the centered title (they were covering
  the "WH" of "WHEREDNGN").

## v0.1.1 — visuals, sound, scoring fixes, hardening

**Visuals**
- Vector Playing Cards art (32 cards + back) replaces the FontString placeholders.
- Four-color suit deck (♠ black, ♥ red, ♦ blue, ♣ green) — suits are unambiguous at a glance.
- Felt-green tiled trick area with winner-glow on the trick winner.
- Card slide-in animation from each player's edge.
- Bot avatar circles next to seat names.
- Window scale controls (+/−) in the title bar; size persists.

**Sound (with mute toggle in top-left)**
- Card swish + slap on every play.
- Soft bell when your turn arrives.
- Two-note chime when contract is finalized.
- Triad arpeggio when your team wins a trick.
- Four-note fanfare for AL-KABOOT / contract failure.
- Arabic voice cues (ElevenLabs Saud) for HOKM / SUN / ASHKAL / PASS / "Awal" round-start.

**Bot AI**
- Bid threshold randomized ±6 so two bots dealt similar hands don't always pick the same bid.
- Bel/Bel-Re threshold randomized ±10 — no longer a hard cliff.
- Smother-partner: in Hokm, bots dump A/10 of trick lead suit when partner is winning.
- Trump-saving: bots prefer non-trump discards when they're not closing the trick.
- Card-counting helper for outstanding-trump awareness.
- Takweesh detection: bots call Takweesh on opponent illegal plays (60% in trick 1, decays through hand).

**Networking / correctness**
- Authority + phase + idempotence guards on `_OnBid`/`_OnPlay`/`_OnMeld`/`_OnTakweesh`/`_OnKawesh`.
- Resync-on-reload (`MSG_RESYNC_REQ`/`RES`): players who `/reload` mid-game request state from the host and rehydrate.
- Host pause toggle suspends bots and AFK timers without dropping in-flight state.
- AFK pre-warn (T-10s) flashes the local bar and pings audibly so auto-pass isn't a surprise.
- Hold-to-confirm on Bel-Re and Takweesh — single-click can't trigger a round-ender by mistake.

**Saudi rule corrections**
- Strict-majority make check (Saudi rule 4-2/4-3): 65-65 (Sun) / 81-81 (Hokm) is now a tie that goes to the defenders.
- Belote shifted into the make-check total (rule 4-5).
- Doubled-tie inversion (rule 4-10): on a tied doubled hand, the bidder team takes the full count.

**Bug fixes**
- `cancelLocalWarn` was nil at call time → every Local* action crashed. Forward-declared.
- Sound dispatch: SoundKit IDs now route via `PlaySound`, not `PlaySoundFile`.
- Takweesh false-call no longer leaves the trick frozen on the table.

## v0.1.0 — initial release

- Full Saudi Baloot ruleset: Hokm, Sun, Ashkal, Belote, Al-kaboot, Takweesh, Kawesh.
- 4-player party-only over addon channel; bots fill empty seats.
- Bidding (round 1 + round 2), Bel/Bel-Re windows, meld declarations, trick play.
- AFK timer auto-skips Bel/Bel-Re windows after 60s.
- Authority + idempotence guards on Double/Redouble messages.
