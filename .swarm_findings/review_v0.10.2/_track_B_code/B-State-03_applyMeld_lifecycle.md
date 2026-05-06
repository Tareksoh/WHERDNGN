# B-State-03 — `S.ApplyMeld` lifecycle audit

**Audit version**: v0.10.2 (post-v0.10.0 X5 fix re-audit)
**Track**: B (code review)
**Scope**: deep audit of meld declaration → wire → store → score lifecycle.
Confirms / extends D-RT-06's headline finding: the v0.10.0 X5 fix to
`R.DetectMelds` did NOT propagate to `S.ApplyMeld`'s duplicate value-derivation
block. Every meld declared via the wire path (humans-via-LocalDeclareMeld,
all bot dispatch paths, AFK auto-declare, resync replay) goes through
`S.ApplyMeld` and Hokm Carré-A is silently dropped before insertion into
`s.meldsByTeam`.

**Files inspected**

- `C:\CLAUDE\WHEREDNGN\State.lua` — `S.ApplyMeld` 1149-1189; `S.GetMeldsForLocal` 1930-1959
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — `R.DetectMelds` 220-289 (X5 fix at 273-287);
  `meldRank` / `bestMeld` / `R.CompareMelds` 301-353; `R.SumMeldValue` 503-507;
  belote-cancel in `R.ScoreRound` 730-744
- `C:\CLAUDE\WHEREDNGN\Net.lua` — `_OnMeld` 1354-1373; `LocalDeclareMeld`
  2374-2383; `SendMeld` 198-201; `MaybeRunBot` bot dispatch 4076-4083;
  AFK auto-declare 3422-3441; resync replay 390-410; takweesh belote-cancel
  2220-2246; SWA invalid-claim belote-cancel 2956-2978
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — `Bot.PickMelds` 3408-3418
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — `K.MELD_*` 91-107; `K.CARRE_RANKS` 109
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-06_carre_cascade.md`

---

## Executive summary

| # | Finding | Severity |
|---|---|---|
| 1 | **`S.ApplyMeld` value-derivation drops Hokm Carré-A** — duplicate of `R.DetectMelds` logic that did NOT receive v0.10.0 X5 fix; the entire X5 patch is functionally inert because every meld funnels through `ApplyMeld` | **HIGH** |
| 2 | Inline comment at State.lua:1177 "Hokm 4-Aces: doesn't score (per Pagat-strict)" actively contradicts post-X5 rule + Constants.lua:94 docstring | HIGH (root cause of #1) |
| 3 | `S.ApplyMeld` value derivation duplicates `R.DetectMelds` logic — drift risk; X5 itself is a manifestation of this | HIGH |
| 4 | `declaredBy` attribution stored on every meld; only relied upon by Net.lua's takweesh+SWA belote-cancel paths (both still on pre-M5 player-level predicate; D-RT-06 #2) — `R.ScoreRound`'s belote-cancel is now team-level (correct), but the two Net.lua duplicates were never updated | LOW (this audit; covered fully in D-RT-06 #2) |
| 5 | Idempotent dedupe is by `(seat, kind, top, suit)` — same seat re-declaring identical meld is a no-op (correct) | INFO |
| 6 | No declaration-order priority semantics — `R.CompareMelds`'s `bestMeld` only compares values, not insertion order; correct for Saudi rule | INFO |
| 7 | `Cards.IsMeldEmittable` does NOT exist; emit-gating is purely UI-side (`S.GetMeldsForLocal`) + bot-side (`Bot.PickMelds`) + state-side (`S.ApplyMeld`'s trick-1 gate) | INFO |
| 8 | AFK auto-declare path (Net.lua:3433-3441) calls `S.ApplyMeld` directly → also broken for Hokm Carré-A | HIGH (manifestation of #1) |
| 9 | `Bot.PickMelds` emits Carré-A correctly via `R.DetectMelds`, but `MaybeRunBot`'s loop at Net.lua:4076-4083 immediately funnels into `S.ApplyMeld` which drops it | HIGH (manifestation of #1) |
| 10 | Resync replay path (Net.lua:403-410 → `_OnMeld` → `S.ApplyMeld`) — drops Hokm Carré-A even on host-replayed melds. Rejoiner ends up with a different `meldsByTeam` than the host. | HIGH (manifestation of #1) |

**Headline**: the v0.10.0 X5 fix is **a half-fix**. `R.DetectMelds` correctly
emits Hokm Carré-A with `value = 100`, but the meld never reaches
`s.meldsByTeam` because `S.ApplyMeld`'s parallel value-derivation block at
State.lua:1167-1184 still has the pre-X5 shape with the explicit "Hokm 4-Aces:
doesn't score" comment. Result: silent +20 over-scoring of Belote (when the
holder's Carré-A would have cancelled it) and silent meld-strict-majority
miscalculation (the missing 100 raw is ~6 game points the bidder misses on
their side of the threshold check).

The full cascade D-RT-06 names is reproduced verbatim by every meld emitter
in the codebase — the fix in `R.DetectMelds` only matters for the local
seat's own UI / scoring at the SAME moment as detection (i.e. nowhere — the
UI's `S.GetMeldsForLocal` returns the detected list, the player clicks
declare, and that re-routes through `LocalDeclareMeld` → `S.ApplyMeld` which
drops it on the floor).

---

## The full path: PickMelds → wire → ApplyMeld → meldsByTeam → ScoreRound + Belote-cancel + CompareMelds

For Hokm contract, holder of all four Aces (e.g. seat 3 on team A):

```
                                       VALUE PATH
┌─────────────────────────────────────────────────────────────────────┐
│ Bot.PickMelds(3)                                                    │
│   └─ R.DetectMelds(hand, contract)                                  │
│        └─ contract.type == K.BID_HOKM, isSun=false                  │
│        └─ rank=A, count=4 → enters carré branch (Rules.lua:273-286) │
│        └─ value = isSun and K.MELD_CARRE_A_SUN                      │
│             or K.MELD_CARRE_OTHER  ← X5 FIX: Hokm gets 100          │
│        └─ emits {kind="carre", value=100, top="A", cards=...}       │
│                                                                     │
│   Returned meld list: [{ value=100, top="A", kind="carre", ... }]   │
└─────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ Net.lua MaybeRunBot bot dispatch (4076-4083)                        │
│   for _, m in ipairs(melds) do                                      │
│      S.ApplyMeld(seat, m.kind, m.suit, m.top, encoded)              │
│      N.SendMeld(seat, m)                                            │
│   end                                                               │
│   ↑ Note: m.value (=100) is computed but DISCARDED — only           │
│   kind/suit/top/encoded are passed to ApplyMeld. ApplyMeld          │
│   re-derives value from kind+top+contract.                          │
└─────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
┌─────────────────────────────────────────────────────────────────────┐
│ State.lua S.ApplyMeld (1167-1184) — THE BUG                         │
│   elseif kind == "carre" then                                       │
│      if K.CARRE_RANKS[top] then                                     │
│         if top == "A" then                                          │
│            if s.contract and s.contract.type == K.BID_SUN then      │
│               value = K.MELD_CARRE_A_SUN                            │
│            end                                                      │
│            -- Hokm 4-Aces: doesn't score (per Pagat-strict) ◀ STALE │
│         else                                                        │
│            value = K.MELD_CARRE_OTHER                               │
│         end                                                         │
│      end                                                            │
│   end                                                               │
│   if not value then return end ◀───────────────────────────── DROP! │
│                                                                     │
│   In Hokm: top=="A" branch sets value only in Sun. Hokm falls       │
│   through with value=nil. Function returns BEFORE the table.insert. │
│   The meld is NEVER stored.                                         │
└─────────────────────────────────────────────────────────────────────┘
                                       │
                                       ▼
                    s.meldsByTeam.A  ← MELD NEVER LANDS
                                       │
                  ┌────────────────────┴────────────────────┐
                  ▼                                         ▼
┌──────────────────────────────┐          ┌──────────────────────────────┐
│ R.SumMeldValue(meldsByTeam.A)│          │ R.ScoreRound belote-cancel   │
│   - missing 100 raw          │          │ (Rules.lua:730-744, fixed in │
│   - bidder strict-majority   │          │  v0.9.0 M5 to be team-level) │
│     threshold check sees     │          │   for _, m in ipairs(list)   │
│     side-A points 100 lower  │          │     if (m.value or 0) >= 100 │
│     than reality             │          │        belote = nil ◀ NEVER  │
│   - approx 10 game points    │          │           triggers because   │
│     can flip the 162-vs-rest │          │           Carré-A meld isn't │
│     contract-made check      │          │           in the list        │
└──────────────────────────────┘          └──────────────────────────────┘
                                                         │
                                                         ▼
                                       Belote stays uncancelled →
                                       silent +20 raw over-credited to
                                       holder's team (gp impact: 2 in Hokm,
                                       4 in Hokm Bel, 8 in Triple, etc.)

┌──────────────────────────────┐
│ R.CompareMelds (winner-takes)│
│   bestMeld for team A picks  │
│   max meldRank — but team A  │
│   doesn't have the Carré-A   │
│   in the list at all. So if  │
│   team B has any K/Q/J carré │
│   (also 100 raw) or a seq5   │
│   (also 100), they "win" the │
│   meld comparison and take   │
│   ALL of their melds, while  │
│   team A takes nothing.      │
│   In standard rules everyone │
│   keeps their melds, but the │
│   `R.CompareMelds` API is    │
│   used by `meldRank`/        │
│   `bestMeld` clients. Verify │
│   no live caller currently   │
│   uses this winner-takes-all │
│   path; if any does, the     │
│   silent loss compounds.     │
└──────────────────────────────┘
```

(See Findings 1, 4, 8, 9, 10 below for explicit per-call-site code quotes.)

---

## Finding 1 — `S.ApplyMeld` value-derivation drops Hokm Carré-A

**Severity**: HIGH (silent over-score; silent meld score loss; round outcomes wrong)

**Location**: `C:\CLAUDE\WHEREDNGN\State.lua` lines **1167-1184**.

**Code (verbatim)**:

```lua
1164:    -- Mirror R.DetectMelds value derivation. Constants only define
1165:    -- MELD_CARRE_OTHER (T/Q/K/J — all 100 raw) and MELD_CARRE_A_SUN
1166:    -- (Aces in Sun only — 200 raw). 9/8/7 carrés don't score.
1167:    local value
1168:    if kind == "seq3" then value = K.MELD_SEQ3
1169:    elseif kind == "seq4" then value = K.MELD_SEQ4
1170:    elseif kind == "seq5" then value = K.MELD_SEQ5
1171:    elseif kind == "carre" then
1172:        if K.CARRE_RANKS[top] then
1173:            if top == "A" then
1174:                if s.contract and s.contract.type == K.BID_SUN then
1175:                    value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
1176:                end
1177:                -- Hokm 4-Aces: doesn't score (per Pagat-strict)
1178:            else
1179:                value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
1180:            end
1181:        end
1182:        -- 9 carrés (and 8/7) drop through with value=nil → not scored
1183:    end
1184:    if not value then return end
```

In Hokm with `top == "A"`, the `if s.contract.type == K.BID_SUN` branch is
false, no `else` exists, `value` stays `nil`, and line 1184 returns BEFORE
`table.insert` at 1185. **The meld is silently dropped.**

Compare with `R.DetectMelds` (Rules.lua:273-287, post-X5):

```lua
273:    for rank, count in pairs(byRank) do
274:        if count == 4 and K.CARRE_RANKS[rank] then
275:            local value
276:            if rank == "A" then
277:                value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
278:            else
279:                value = K.MELD_CARRE_OTHER
280:            end
```

`R.DetectMelds` has the X5 fix (line 277: `or K.MELD_CARRE_OTHER` for Hokm).
`S.ApplyMeld` does not. The leading comment at 1164 ("Mirror R.DetectMelds")
was correct WHEN WRITTEN; the X5 fix invalidated this mirror without
updating `ApplyMeld`.

The Constants.lua:94 docstring already calls this out correctly:

```lua
94:    K.MELD_CARRE_OTHER = 100   -- T, K, Q, J (any contract type) AND Carré-A in Hokm
```

**Repro path** (host-side bot, Hokm contract, bot has 4 Aces):

1. Round starts; `S.s.contract = { type = K.BID_HOKM, trump = ... }`.
2. `Bot.PickMelds(3)` runs, `R.DetectMelds` emits `{kind="carre", value=100, top="A", cards=...}`.
3. `MaybeRunBot` (Net.lua:4076-4083) iterates emitted melds, calls
   `S.ApplyMeld(3, "carre", nil, "A", encoded)` for the Carré-A.
4. Inside `S.ApplyMeld`, `kind == "carre"`, `top == "A"`,
   `s.contract.type == K.BID_HOKM`. Enter the `if top == "A"` branch.
5. `s.contract.type == K.BID_SUN` is false → `value` stays `nil`.
6. `if not value then return end` — **meld dropped.** No `table.insert` runs.
7. `MaybeRunBot` calls `N.SendMeld(seat, m)` — wire frame goes out anyway.
8. All other clients receive `MSG_MELD`, route to `_OnMeld` → `ApplyMeld`,
   same drop happens locally for them.

**Cascade impact (per D-RT-06)**:

- Bidder strict-majority threshold check (>81 in Hokm-bid, >162 in
  bid-after-pass) sees side-A points missing 100 raw (= 10 gp). At
  thresholds this can flip contract-made / contract-failed.
- `R.ScoreRound` belote-cancel (Rules.lua:738-744, post-M5 team-level):
  Carré-A would have ≥100 → cancels Belote. Without it: silent +20 raw
  Belote credits, multiplied by `mult` (×1 in plain Hokm, ×2 in Bel, ×4
  in Triple/Four).
- `R.CompareMelds` (Rules.lua:343-353): if any caller uses it for
  winner-takes-all, the 100-value meld's absence flips comparisons. (Audit
  caller graph in Net.lua / R.ScoreRound to confirm whether any current
  consumer triggers winner-takes-all here — D-RT-06 §1 notes the test
  harness exercises this path.)

---

## Finding 2 — Stale inline comment encodes the bug

**Severity**: HIGH (root cause; if the comment had been correct at v0.10.0 X5
review time, this duplicate logic would have been spotted)

**Location**: `C:\CLAUDE\WHEREDNGN\State.lua` line **1177**.

```lua
1177:                -- Hokm 4-Aces: doesn't score (per Pagat-strict)
```

This contradicts:

- `K.MELD_CARRE_OTHER` docstring (Constants.lua:94)
- `R.DetectMelds` X5 fix block (Rules.lua:260-267):
  > "Per videos #32 line 245 + #38 line 61, four-Aces in Hokm scores 100
  > like the other carrés."
- The CHANGELOG.md entry for v0.10.0 X5 fix.

Since the leading comment at line 1164 still says "Mirror R.DetectMelds", a
reviewer relying on that comment would assume the block matches `DetectMelds`.
The internal inline comment at 1177 is the actively-misleading line that
must be removed when fixing.

---

## Finding 3 — Value derivation duplicated; drift risk reified

**Severity**: HIGH (architectural — X5 itself is a manifestation; will recur)

**Locations**:
- `R.DetectMelds` value derivation: Rules.lua:241-244, 273-287
- `S.ApplyMeld` value derivation: State.lua:1167-1183

The two blocks must compute identical `value` for identical `(kind, top,
contract.type)` tuples but live in independent functions. Constants.lua
defines `K.MELD_SEQ3`, `K.MELD_SEQ4`, `K.MELD_SEQ5`, `K.MELD_CARRE_OTHER`,
`K.MELD_CARRE_A_SUN`, `K.CARRE_RANKS` — the **single source of truth**
should be a helper like `K.MeldValueFor(kind, top, contract)` that both
sites call.

Pattern echoed in D-RT-06 §1: same X5 cascade also reaches Net.lua's
takweesh + invalid-SWA belote-cancel duplicate (see Finding 4 below). One
canonical helper would close both the value-derivation drift and the
belote-cancel-predicate drift.

**Note for fix**: do NOT rely on the wire-emitted `m.value` — `MaybeRunBot`
discards it (Net.lua:4079 only forwards `kind/suit/top/encoded`), and the
wire format `K.MSG_MELD` (`SendMeld` 198-201) does not carry value either.
Recomputing locally is correct; the drift is the bug.

---

## Finding 4 — `declaredBy` attribution: still relied on by Net.lua belote-cancel duplicates

**Severity**: covered in D-RT-06 §2; documented here for completeness and code-quote.

**Storage**: `S.ApplyMeld` line 1187:

```lua
1185:    table.insert(s.meldsByTeam[team], {
1186:        kind = kind, value = value, suit = nsuit,
1187:        top = top, cards = cards, len = #cards, declaredBy = seat,
1188:    })
```

`declaredBy` is correctly stamped per-meld (origin seat).

**Consumption**:

- `R.ScoreRound` belote-cancel (Rules.lua:738-744): post-v0.9.0 M5,
  TEAM-level — no `declaredBy` check, only `(m.value or 0) >= 100`.
  ✅ Correct.

- Net.lua `HostResolveTakweesh` belote-cancel (Net.lua:2236-2244):

  ```lua
  2236:        if kWho and qWho and kWho == qWho then
  2237:            belote = R.TeamOf(kWho)
  2238:            local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
  2239:            for _, m in ipairs(list) do
  2240:                if m.declaredBy == kWho and (m.value or 0) >= 100 then
  2241:                    belote = nil
  2242:                    break
  2243:                end
  2244:            end
  ```

  `m.declaredBy == kWho` — pre-M5 player-level predicate. Partner's ≥100
  meld doesn't cancel.

- Net.lua `HostResolveSWA` invalid-SWA belote-cancel (Net.lua:2968-2976):

  ```lua
  2968:            if kWho and qWho and kWho == qWho then
  2969:                beloteOwner = R.TeamOf(kWho)
  2970:                local list = (S.s.meldsByTeam and S.s.meldsByTeam[beloteOwner]) or {}
  2971:                for _, m in ipairs(list) do
  2972:                    if m.declaredBy == kWho and (m.value or 0) >= 100 then
  2973:                        beloteOwner = nil
  2974:                        break
  2975:                    end
  2976:                end
  ```

  Same pre-M5 player-level predicate.

When fix #1 lands (Carré-A reaches `meldsByTeam` correctly), these two
sites still under-cancel partner-side ≥100 melds, AND would still
under-cancel the holder's own Carré-A IF the holder is NOT the K+Q
holder (because `m.declaredBy == kWho` requires same player — but
`m.declaredBy = seat` where seat holds the carré-A is a different
player than the K+Q holder, so the cancel still misses). `R.ScoreRound`
got it right by removing the `declaredBy` constraint entirely.

This is D-RT-06 §2 verbatim; flagged here to show that `S.ApplyMeld`'s
attribution work is correct and non-load-bearing for the regular-round
path post-M5, but two early-termination Net.lua duplicates still live on
the pre-M5 predicate.

---

## Finding 5 — Idempotency on duplicate declares

**Severity**: INFO (verified correct)

**Location**: `S.ApplyMeld` lines 1157-1162:

```lua
1157:    -- Idempotent: dedupe by (seat, kind, top, suit).
1158:    local nsuit = (suit ~= "" and suit) or nil
1159:    for _, m in ipairs(s.meldsByTeam[team]) do
1160:        if m.declaredBy == seat and m.kind == kind and m.top == top
1161:           and (m.suit or nil) == nsuit then return end
1162:    end
```

Same seat re-declaring identical meld is silently dropped (no double-count).
Note the `(suit ~= "" and suit) or nil` normalization handles wire-protocol
difference (`""` over the wire becomes `nil` in storage). For carrés,
`m.suit` is `nil` and the wire field is `""` — both sides normalize to
`nil` and dedupe correctly.

**Edge cases verified**:

- Two seats on same team with identical detected meld pattern (e.g. both
  hold a sequence in the SAME suit — impossible because cards are unique;
  not reachable).
- Same seat declares Carré-A twice (e.g. UI rapid-click): line 1161 catches
  it via `(seat, kind, top, suit=nil)` match.
- Replay path: `MSG_MELD` arrives during resync with same `(seat, kind, top,
  suit)` already in `meldsByTeam` — dedupe catches it. (Resync-host emits
  the existing list to rejoiner, who applies; if rejoiner already had a
  partial list from before reload, dedupe correctly elides duplicates.)

---

## Finding 6 — Meld order priority

**Severity**: INFO (verified — no order-based priority is encoded)

`R.CompareMelds` (Rules.lua:343-353) calls `bestMeld` (lines 333-341) which
does max-by-`meldRank` over the team's list. Insertion order is irrelevant.

This matches Saudi rule: each team keeps its own melds; no
"first-declared wins" semantics. (`R.CompareMelds` is reachable but its
"winner takes all" output is NOT used by `R.ScoreRound` in standard
v0.10.x — both teams keep their melds. `R.CompareMelds` exists for tests
and edge-case scoring branches; verify no live caller funnels it.)

`Bot.PickMelds` (Bot.lua:3408-3418) returns the FULL `R.DetectMelds` list,
not "the best one", so multiple melds from one seat all get declared in
sequence (the `for _, m in ipairs(melds) do` loop in `MaybeRunBot`
4076-4083 emits them all). This matches Saudi rule "Pagat-strict: declare
all melds in trick 1".

---

## Finding 7 — `Cards.IsMeldEmittable`: does NOT exist

**Severity**: INFO

Repo-wide grep for `IsMeldEmittable` / `IsMeldEmitable` / `MeldEmit`
returns 0 hits. The "emit gating" referenced in the audit prompt is
distributed across:

- **State-side** trick-1 gate: `S.ApplyMeld` line 1154
  (`if (#(s.tricks or {})) >= 1 then return end`).
- **UI-side** filter: `S.GetMeldsForLocal` line 1938 (same gate) +
  already-declared filter 1946-1957.
- **Bot-side** gate: `Bot.PickMelds` line 3416 (same gate).

No dedicated `Cards.lua` function. There IS no "emittable" predicate that
filters by something OTHER than "in trick 1 + not already declared". The
3 sites all enforce the same trick-1 lock. `S.ApplyMeld` is the
authoritative wire-side gate.

---

## Finding 8 — AFK auto-declare path (Net.lua:3433-3441)

**Severity**: HIGH (manifestation of #1)

**Location**: Net.lua lines 3433-3441 (host-side AFK turn timeout, "play"
kind):

```lua
3433:        if S.s.meldsDeclared and not S.s.meldsDeclared[seat] then
3434:            local melds = (B.Bot and B.Bot.PickMelds and B.Bot.PickMelds(seat)) or {}
3435:            for _, m in ipairs(melds) do
3436:                S.ApplyMeld(seat, m.kind, m.suit, m.top,
3437:                    C.EncodeHand(m.cards or {}))
3438:                N.SendMeld(seat, m)
3439:            end
3440:            S.s.meldsDeclared[seat] = true
3441:        end
```

When a HUMAN seat AFK's during trick 1, this calls `Bot.PickMelds(seat)` on
their hostHand and auto-declares their melds. But `S.ApplyMeld` at 3436 is
the same broken function as in MaybeRunBot.

**Repro**: human bidder holds 4 Aces in Hokm, AFKs through trick 1.
`B.Bot.PickMelds(seat)` returns `[{value=100, top="A", kind="carre", ...}]`.
`S.ApplyMeld` drops it. Player loses their 100-raw meld AND any partner-team
Belote does NOT get cancelled by it.

`N.SendMeld` at 3438 still broadcasts the wire frame. Every peer's
`_OnMeld` → `ApplyMeld` drops it. UI strip on every client shows nothing.

---

## Finding 9 — `Bot.PickMelds` emits Carré-A correctly; `MaybeRunBot` then drops it

**Severity**: HIGH (manifestation of #1)

**Code** (`Bot.lua` 3408-3418):

```lua
3408:function Bot.PickMelds(seat)
3409:    local hand = S.s.hostHands and S.s.hostHands[seat]
3410:    if not hand then return {} end
3411:    -- Saudi rule: melds must be declared during trick 1 only. ...
3416:    if (#(S.s.tricks or {})) >= 1 then return {} end
3417:    return R.DetectMelds(hand, S.s.contract)
3418:end
```

The bot picker correctly delegates to `R.DetectMelds` which has the X5 fix.
A bot holding 4 Aces in Hokm gets `{kind="carre", value=100, top="A",
cards={"AS","AH","AD","AC"}}` returned.

**`MaybeRunBot` consumer** (Net.lua 4076-4083):

```lua
4076:                if not S.s.meldsDeclared[seat] then
4077:                    local melds = B.Bot.PickMelds(seat)
4078:                    for _, m in ipairs(melds) do
4079:                        S.ApplyMeld(seat, m.kind, m.suit, m.top, C.EncodeHand(m.cards or {}))
4080:                        N.SendMeld(seat, m)
4081:                    end
4082:                    S.s.meldsDeclared[seat] = true
4083:                end
```

Line 4079 passes `m.kind/m.suit/m.top` only — `m.value` (=100) is dropped on
the floor. `S.ApplyMeld` re-derives, hits the broken Hokm-A branch, drops
the meld. End-to-end: bot's Carré-A is invisible in `meldsByTeam`.

`N.SendMeld` line 4080 still broadcasts the wire frame, peers also drop it.
Same outcome on every client.

---

## Finding 10 — Resync replay path also drops Hokm Carré-A

**Severity**: HIGH (manifestation of #1; introduces state divergence on rejoin)

**Replay code** (Net.lua 403-410):

```lua
403:    for _, team in ipairs({ "A", "B" }) do
404:        for _, m in ipairs((S.s.meldsByTeam and S.s.meldsByTeam[team]) or {}) do
405:            local enc = (m.cards and C.EncodeHand(m.cards)) or ""
406:            whisper(target, ("%s;%d;%s;%s;%s;%s;1"):format(
407:                K.MSG_MELD, m.declaredBy or 0,
408:                m.kind or "", m.suit or "", m.top or "", enc))
409:        end
410:    end
```

The host replays its `meldsByTeam` to a rejoiner. **But if the host already
dropped Hokm Carré-A** (because of #1), it's not in `meldsByTeam` to
replay, so the rejoiner is in agreement with the host's broken state.
That's at least internally consistent.

**However**, after fix #1 lands and the host's `meldsByTeam` correctly
contains Hokm Carré-A, the replay path goes through `_OnMeld` →
`S.ApplyMeld`. **If only `R.DetectMelds` is patched and `S.ApplyMeld` is
left broken**, the rejoiner receives the wire frame, runs `S.ApplyMeld`,
re-derives `value`, hits the same broken Hokm-A branch, drops the meld
locally — even though the host has it stored. The rejoiner ends up with a
DIFFERENT `meldsByTeam` than the host: silent state desync that affects
local UI strip rendering, local belote-cancel display calculations, and
any client-side scoring previews.

This makes #1 doubly important: any half-fix to only `R.DetectMelds` (or
to fix the bot loop to send `m.value` over the wire and trust it
client-side) leaves resync replay broken because `_OnMeld` → `ApplyMeld`
runs with the same broken value-derivation block. **`S.ApplyMeld` is
load-bearing for state convergence.**

---

## Recommendation summary (informational; "do NOT modify code")

The minimum fix is one line. Replace State.lua:1173-1180:

```lua
            if top == "A" then
                if s.contract and s.contract.type == K.BID_SUN then
                    value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
                end
                -- Hokm 4-Aces: doesn't score (per Pagat-strict)
            else
                value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
            end
```

with:

```lua
            if top == "A" then
                value = (s.contract and s.contract.type == K.BID_SUN)
                        and K.MELD_CARRE_A_SUN
                        or K.MELD_CARRE_OTHER
            else
                value = K.MELD_CARRE_OTHER
            end
```

(structural mirror of Rules.lua:276-280) and remove the stale 1177 comment.

The architectural fix (Finding 3) is to extract a single
`K.MeldValueFor(kind, top, contract)` helper called from BOTH `R.DetectMelds`
AND `S.ApplyMeld`. This also supports a similar consolidation of the
belote-cancel predicate in D-RT-06 §2 (R.IsBeloteCancelled(meldList) used
by `R.ScoreRound`, `HostResolveTakweesh`, `HostResolveSWA`).

Tests required after the fix:

1. Hokm contract, seat 3 holds 4 Aces, calls `S.ApplyMeld(3, "carre", nil,
   "A", encoded4Aces)`. Assert `s.meldsByTeam[teamOf(3)][1].value == 100`.
2. Hokm contract, seat 3 holds 4 Aces + K+Q of trump, declares both melds,
   completes round trick-by-trick, K+Q both played. Assert
   `R.ScoreRound`'s belote_cancelled is true (Carré-A's 100 cancels the
   +20 Belote credit). Already exists in tests/test_rules.lua per D-RT-06
   §1 — confirm it covers Hokm specifically (not just Sun).
3. Resync replay: host has Carré-A in `meldsByTeam`, rejoiner snapshot
   path runs through `_OnMeld` → `ApplyMeld` for the replayed frame.
   Assert rejoiner's `meldsByTeam` matches host's exactly.
4. Bot dispatch: bot holds 4 Aces in Hokm, `MaybeRunBot` runs. Assert
   `meldsByTeam` contains the Carré-A after the bot turn AND that the
   wire `MSG_MELD` was sent.

---

**End of audit B-State-03.**
