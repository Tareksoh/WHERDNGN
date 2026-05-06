# B-Net-03: Takweesh penalty resolution — deep audit (v0.10.2 + post-v0.10.1 M1)

**Audit version:** v0.10.2 (HEAD)
**Track:** B — code review
**Author scope:** `Net.HostResolveTakweesh` (Net.lua:2127-2339), entry points (`N.LocalTakweesh` 2071-2077, `N._OnTakweesh` 2079-2089), display path (`N._OnTakweeshOut` 2091-2125), state mutations (State.lua:1149-1189 `S.ApplyMeld`, 1463-1530 `S.ApplyRoundEnd`, transient-fields 191-247), Rules.lua reference (`R.SumMeldValue` 503-507, `R.ScoreRound` 661-953).
**Cross-cuts read:** `_track_C_xref/C-Xref-01_swa_pipeline.md`, `_track_C_xref/C-Xref-02_score_pipeline.md` F1/F2/F4, `_track_D_redteam/D-RT-06_carre_cascade.md`, `D-RT-09_sun_escalation_bypass.md`, `D-RT-17_resync_edges.md`, `D-RT-20_belote_cancel_edges.md`, `D-RT-23_multi_qaid_race.md`, `D-RT-27_reset_redeal.md`, `D-RT-28_score_boundary.md`.

---

## TL;DR

The v0.10.1 M1 fix (offender-team melds zeroed on Qaid) is **correctly wired** at Net.lua:2216-2218 and matches the symmetric SWA-invalid path at Net.lua:2940-2952. The new line `local offenderTeam = (winnerTeam == "A") and "B" or "A"` plus `mpA = (offenderTeam == "A") and 0 or meldA` is correct under both branches (`caught` and `notcaught`) and consistent with the `HostResolveSWA` invalid branch.

But the cross-cut surfaces **eight real defects** (one CRITICAL via cascade, two MEDIUM, five LOW/INFO):

| ID | Severity | Layer | Title |
|---|---|---|---|
| **B-N3-1** | MEDIUM | Net | Takweesh Belote-cancel predicate is per-player, not team — M5 backport missed (Net.lua:2240) |
| **B-N3-2** | MEDIUM | Net | Tie-at-target tiebreaker uses naive bidder-team-wins; v0.8.6 H3 fix not backported (Net.lua:2327-2331) |
| **B-N3-3** | MEDIUM | Net | Sun-multiplier compound: stale `tripled/foured/gahwa` on Sun yields ×6/×8 in Takweesh path — R2 normalization not duplicated (Net.lua:2185-2190) |
| **B-N3-4** | CRITICAL | State | Hokm Carré-A silently dropped at S.ApplyMeld (State.lua:1173-1184) — diverges from `R.DetectMelds` and from the Constants.lua:94 doc comment. Compound with Takweesh: an offender team that "lost" 0 melds because their declared Hokm Carré-A was already nilled silently has nothing to forfeit, but THE WINNER also forfeits any of their own Hokm-Carré-A meld — so the "winner adds own melds × mult" stage under-credits |
| **B-N3-5** | LOW | Net | Pre-bid Tawzee Qaid locked out — phase guards at LocalTakweesh / _OnTakweesh / HostResolveTakweesh (lines 2073/2083/2129) reject during DEAL1/DEAL2BID/DEAL3/DOUBLE/TRIPLE/FOUR/GAHWA |
| **B-N3-6** | LOW | Net | Mid-Takweesh /reload race: TRANSIENT_FIELDS includes `takweeshResult=true` AND PLAYER_LOGIN restore does NOT re-broadcast PHASE_SCORE banner. Rejoiner during PHASE_SCORE post-Takweesh sees no catch detail |
| **B-N3-7** | LOW | Net | `S.ApplyRoundEnd(addA, addB, totA, totB)` call site (Net.lua:2264) omits `sweep` and `bidderMade` args — BALOOT fanfare suppressed on Takweesh resolution; "lost-round stinger" still fires via delta-direction inference |
| **B-N3-8** | INFO | Net | Game-end propagation correct: `MSG_GAMEEND` broadcast after `S.ApplyGameEnd` (lines 2332-2333); `_OnGameEnd` handler at Net.lua:1510-1515 idempotent on `S.ApplyGameEnd` (State.lua) |

**No regressions vs v0.10.1.** The v0.10.1 M1 fix itself is clean and consistent with the SWA-invalid path. Most issues here pre-date M1.

---

## End-to-end pipeline (the critical path)

```
LocalTakweesh()                                # Net.lua:2071
  ├── pause / phase guards                     # 2072-2074
  ├── broadcast MSG_TAKWEESH                   # 2075
  └── (host) HostResolveTakweesh(callerSeat)   # 2076
                                                #
HostResolveTakweesh(callerSeat)                # Net.lua:2127
  ├── isHost / contract / phase guards         # 2128-2129
  ├── CancelTurnTimer()                        # 2134
  ├── swaRequest = nil    [Wave 6/9/10 fix]    # 2144
  ├── scan for opponent .illegal play          # 2150-2162
  │     scans s.tricks then s.trick.plays
  ├── winnerTeam decision                      # 2175
  │     caught   → callerTeam
  │     ¬caught  → oppTeam
  ├── handTotal = SUN ? 130 : 162              # 2177
  ├── multiplier ladder                        # 2185-2190
  │     SUN → MULT_SUN
  │     gahwa/foured/tripled/doubled cascade
  ├── meldA, meldB = SumMeldValue              # 2192-2193
  ├── cardA, cardB = winner team gets handTotal# 2194-2195
  ├── offenderTeam = ¬winnerTeam               # 2216
  ├── mpA, mpB = forfeit offender melds        # 2217-2218 [v0.10.1 M1]
  ├── Belote scan (Hokm only)                  # 2223-2246
  ├── rawA, rawB = (card+mp) * mult + belote   # 2248-2251
  ├── div10                                    # 2259-2260
  ├── totA, totB                               # 2261-2262
  ├── S.ApplyRoundEnd(addA, addB, totA, totB)  # 2264 — NO sweep/bidderMade
  ├── lastRoundResult=nil; trick=nil           # 2273-2274
  ├── takweeshResult struct {caller, offender,
  │   card, reason, caught, ts}                # 2275-2290
  ├── SendRound(addA, addB, totA, totB)        # 2291 — also no sweep/made
  ├── print local outcome                      # 2296-2314
  ├── broadcast MSG_TAKWEESH_OUT (caller, caught,
  │     offender, card, reason)                # 2317-2322
  ├── if either team >= target:                # 2324
  │     winner = (totA==totB && contract)
  │              ? R.TeamOf(contract.bidder)
  │              : (totA>totB ? "A" : "B")     # 2327-2331
  │     S.ApplyGameEnd(winner)                 # 2332
  │     N.SendGameEnd(winner)                  # 2333
  └── B.UI.Refresh()                           # 2338
```

---

## Findings

### B-N3-1 — Belote cancellation: per-player predicate, not team-level (MEDIUM)

**Files:** `Net.lua:2236-2244` (Takweesh), `Net.lua:2968-2976` (SWA-invalid mirror), `Rules.lua:738-746` (canonical post-v0.9.0 M5).

**Code (Takweesh path):**

```lua
if kWho and qWho and kWho == qWho then
    belote = R.TeamOf(kWho)
    local list = (S.s.meldsByTeam and S.s.meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if m.declaredBy == kWho and (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```

Compare to canonical (Rules.lua:738-746, post-v0.9.0 M5 fix):

```lua
if belote and kWho then
    local list = (meldsByTeam and meldsByTeam[belote]) or {}
    for _, m in ipairs(list) do
        if (m.value or 0) >= 100 then
            belote = nil
            break
        end
    end
end
```

The v0.9.0 M5 audit (`audit_v0.9.0/AUDIT_REPORT_v0.7.1.md`) explicitly identified this predicate as TEAM-level: partner's quarte cancels K+Q-holder's belote because Saudi rule "≥100 subsumes belote" applies to the team's collective scoring side. The Takweesh + SWA-invalid penalty paths in Net.lua were missed by the M5 backport — both still gate on `m.declaredBy == kWho`.

**Repro:** Hokm-Hearts. Seat 1 holds KH+QH (belote). Seat 3 (partner) declares carré-J (value 100). During play, seat 2 plays an illegal card; seat 1 calls Takweesh. The host's HostResolveTakweesh detects K+Q via the play scan (kWho=qWho=1), sets `belote = "A"`, then walks `meldsByTeam.A`. The carré-J was declared by seat 3, so `m.declaredBy == kWho` is FALSE → cancellation does not fire → +20 belote credited to A. Per Saudi rule (post-M5) it should be cancelled.

**Severity:** MEDIUM. Concrete +2 game-point delta when the cancellation should have fired but doesn't. Probability is moderate — partner declaring a 100+ meld while caller holds K+Q of trump is not unusual in Hokm. Already documented as F1 in `C-Xref-02_score_pipeline.md`.

**Quote (Net.lua:2240):**

```lua
if m.declaredBy == kWho and (m.value or 0) >= 100 then
```

vs Rules.lua:741:

```lua
if (m.value or 0) >= 100 then
```

---

### B-N3-2 — Tied-at-target tiebreaker: naive bidder-team-wins, v0.8.6 H3 fix not backported (MEDIUM)

**Files:** `Net.lua:2324-2333` (Takweesh), `Net.lua:3060-3072` (SWA-invalid mirror), `Net.lua:1683-1709` (canonical post-v0.8.6 H3).

**Code (Takweesh path):**

```lua
if totA >= S.s.target or totB >= S.s.target then
    -- Same Saudi tie-rule as the normal-round path above.
    local winner
    if totA == totB and S.s.contract and S.s.contract.bidder then
        winner = R.TeamOf(S.s.contract.bidder)
    elseif totA > totB then winner = "A"
    elseif totB > totA then winner = "B"
    else                    winner = "A" end
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

Compare to canonical (Net.lua:1683-1709), post-v0.8.6 H3:

```lua
local winner
if totA == totB then
    if res.gahwaWonGame and res.gahwaWinner then
        winner = res.gahwaWinner
    elseif S.s.contract and S.s.contract.bidder then
        local bidderTeam = R.TeamOf(S.s.contract.bidder)
        if res.bidderMade then
            winner = bidderTeam
        else
            winner = (bidderTeam == "A") and "B" or "A"
        end
    else
        winner = "A"
    end
elseif totA > totB then winner = "A"
elseif totB > totA then winner = "B"
else                    winner = "A" end
```

The Takweesh path's comment on line 2325 ("Same Saudi tie-rule as the normal-round path above") **is no longer true** post-v0.8.6 H3. The normal path now correctly inverts on `bidderMade==false` to award the tie to the round's actual winner. Takweesh always awards to bidder-team regardless of who actually won the round.

**Repro:** Pre-Takweesh: A=140, B=130. Bidder is seat 1 (team A). Bidder's team commits an illegal play; seat 2 (team B) catches it. Per Takweesh resolution: B wins the round (notbidder+caught? Actually, no — bidder team plays illegal, defender catches → defender wins). Suppose post-Takweesh: A=152, B=152 (tied at target). Round winner is B; under H3 logic, winner should be B. Under the buggy path, bidder=seat 1, R.TeamOf(1)="A" → winner=A. Match awarded to the OFFENDING team that just got caught.

**Severity:** MEDIUM probability is very low (already noted in C-Xref-02 F2 as <0.1%), but the result directly contradicts the rule v0.8.6 H3 was added to encode. SAME bug exists in SWA-invalid path Net.lua:3064-3068. Already captured as F2 in `C-Xref-02_score_pipeline.md`.

**Quote (Net.lua:2327-2328):**

```lua
if totA == totB and S.s.contract and S.s.contract.bidder then
    winner = R.TeamOf(S.s.contract.bidder)
```

---

### B-N3-3 — Sun-multiplier compound on stale flags (MEDIUM, defense-in-depth gap)

**File:** `Net.lua:2185-2190` (Takweesh path), `Net.lua:2930-2935` (SWA-invalid mirror).

**Code:**

```lua
local mult = K.MULT_BASE
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

Compare to `R.ScoreRound` post-v0.10.0 R2 (Rules.lua:883-893):

```lua
local mult = K.MULT_BASE
if contract.type == K.BID_SUN then
    mult = mult * K.MULT_SUN
    if contract.doubled then mult = mult * K.MULT_BEL end
    -- intentionally ignore tripled/foured/gahwa on Sun
else
    if     contract.gahwa   then mult = mult * K.MULT_FOUR
    elseif contract.foured  then mult = mult * K.MULT_FOUR
    elseif contract.tripled then mult = mult * K.MULT_TRIPLE
    elseif contract.doubled then mult = mult * K.MULT_BEL end
end
```

The R2 audit (`review_v0.10.0/reaudit_R2_*.md`) collapsed the multiplier path so any combination of `tripled/foured/gahwa` on a Sun contract yields `MULT_SUN * MULT_BEL` (×4) maximum. The Takweesh penalty path was NOT updated. With a stale Sun contract carrying `tripled=true` (no foured, no gahwa), Net.lua:2188 charges `Sun × Triple = ×6` where `R.ScoreRound` would charge `Sun × Bel = ×4` (or ×2 with no Bel). With `gahwa=true`, it charges `Sun × Four = ×8`.

The phase machine prevents `tripled/foured/gahwa` from being legitimately set on Sun in v0.10.2 (State.ApplyDouble jumps Sun straight to PHASE_PLAY). But:
- A hand-edited `WHEREDNGNDB.session.state.contract` with stale flags survives RestoreSession's v0.2.0 upgrader (State.lua:323-330) which only strips `redoubled`/back-fills `belOpen/tripleOpen/fourOpen` — does NOT strip `tripled/foured/gahwa` for Sun.
- A version-skewed peer's snapshot frame can also smuggle stale flags through the wire.

**Already documented** as Scenario 2b in `D-RT-09_sun_escalation_bypass.md`: "**Net.lua:2185-2190 HostResolveTakweesh multiplier chain — UNDEFENDED**".

**Severity:** MEDIUM. Defense-in-depth concern; in practice requires SVars tampering or version skew, but the asymmetry is real and trivially fixed.

**Quote (Net.lua:2185-2190):**

```lua
local mult = K.MULT_BASE
if c.type == K.BID_SUN then mult = mult * K.MULT_SUN end
if     c.gahwa   then mult = mult * K.MULT_FOUR
elseif c.foured  then mult = mult * K.MULT_FOUR
elseif c.tripled then mult = mult * K.MULT_TRIPLE
elseif c.doubled then mult = mult * K.MULT_BEL end
```

---

### B-N3-4 — Hokm Carré-A silently dropped → cascade into Takweesh meld accounting (CRITICAL)

**Files:** `State.lua:1171-1184` (S.ApplyMeld), `Rules.lua:273-287` (R.DetectMelds), `Constants.lua:94`.

**Code (State.lua:1171-1184):**

```lua
elseif kind == "carre" then
    if K.CARRE_RANKS[top] then
        if top == "A" then
            if s.contract and s.contract.type == K.BID_SUN then
                value = K.MELD_CARRE_A_SUN     -- "Four Hundred", Sun only
            end
            -- Hokm 4-Aces: doesn't score (per Pagat-strict)
        else
            value = K.MELD_CARRE_OTHER          -- T, K, Q, J → 100 raw
        end
    end
    -- 9 carrés (and 8/7) drop through with value=nil → not scored
end
if not value then return end
```

Compare to R.DetectMelds (Rules.lua:273-287):

```lua
for rank, count in pairs(byRank) do
    if count == 4 and K.CARRE_RANKS[rank] then
        local value
        if rank == "A" then
            value = isSun and K.MELD_CARRE_A_SUN or K.MELD_CARRE_OTHER
        else
            value = K.MELD_CARRE_OTHER
        end
        ...
    end
end
```

And the Constants.lua:94 doc comment:

```lua
K.MELD_CARRE_OTHER = 100   -- T, K, Q, J (any contract type) AND Carré-A in Hokm
```

The constant comment says "AND Carré-A in Hokm" → 100 raw. `R.DetectMelds` correctly emits 100 for Hokm Carré-A. But `S.ApplyMeld` enters the `if top == "A"` branch, fails the `s.contract.type == K.BID_SUN` check in Hokm, and falls through with `value` still nil — then `if not value then return end` at line 1184 silently drops the meld. **The meld is never inserted into `s.meldsByTeam`.**

This is identical to the **CRITICAL bug** documented in `review_v0.10.0/_phase2_xref/xref_X5_meld_coverage.md` line 18:

> **Carré-A in Hokm**: 100 (per #32 L243-245, #38 L59-61, Source I §A7) | _none_ — silently dropped | **CRITICAL BUG**: Hokm Carré-A is silently dropped. Player loses entire 100-meld (= 10 nq + bidder-threshold contribution).

**Compound with Takweesh:**
- Suppose seat 1 (team A, Hokm) declares Carré-A. In `s.meldsByTeam.A`, no entry is created (the meld is dropped).
- Sometime mid-play, seat 2 (team B) plays illegally. Seat 1 calls Takweesh.
- HostResolveTakweesh sets `winnerTeam=A` (caught), `offenderTeam=B`.
- Computes `meldA = R.SumMeldValue(meldsByTeam.A)` — but Hokm-A's value is missing because S.ApplyMeld dropped it.
- Result: A's "winner adds own melds × mult" stage under-credits by 100 raw × mult. With Hokm × Bel (×2), that's 200 raw underscoring → 20 game points.

The Takweesh code itself is correct — it sums what's in `meldsByTeam.A`. The defect is that `S.ApplyMeld` never inserted the meld in the first place. **This affects every code path that reads `s.meldsByTeam` after a Hokm Carré-A declaration**: regular `R.ScoreRound` (made/fail), Takweesh, SWA-invalid, SWA-valid (synth tricks → ScoreRound), UI meld strip.

**Severity:** CRITICAL because it's silent (no error, no warning, no UI cue) and it's a known bug since v0.10.0 review (X5/R5 cascade) but State.lua:1173-1184 was not patched. The Takweesh path inherits the cascade. The fix is one line in State.lua: an `else` that emits `K.MELD_CARRE_OTHER` for Hokm Carré-A.

**Quote (State.lua:1173-1180):**

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

The `-- Hokm 4-Aces: doesn't score (per Pagat-strict)` comment is **factually wrong** under Saudi rules per #32 L243-245, #38 L59-61, and Source I §A7. R.DetectMelds got it right (line 277); S.ApplyMeld didn't.

---

### B-N3-5 — Pre-bid Tawzee Qaid locked out by PHASE_PLAY-only gating (LOW)

**Files:** `Net.lua:2073` (LocalTakweesh), `Net.lua:2083` (_OnTakweesh), `Net.lua:2129` (HostResolveTakweesh).

**Code (Net.lua:2071-2089):**

```lua
function N.LocalTakweesh()
    if S.s.paused then return end
    if S.s.phase ~= K.PHASE_PLAY then return end           -- 2073
    ...
end

function N._OnTakweesh(sender, callerSeat)
    ...
    if S.s.phase ~= K.PHASE_PLAY then return end           -- 2083
    ...
end

function N.HostResolveTakweesh(callerSeat)
    if not S.s.isHost or not S.s.contract then return end
    if S.s.phase ~= K.PHASE_PLAY then return end           -- 2129
    ...
end
```

Takweesh is hardgated to `PHASE_PLAY`. Saudi's "Tawzee Qaid" pre-bid catches (e.g., a player whose initial 5-card distribution shows an illegal pattern, like wrong dealer's-card-count, or an invalid double declaration on a Sun contract during PHASE_DOUBLE) cannot fire. The `.illegal` mark itself only fires inside `S.ApplyPlay` (State.lua:1212-1265), which only runs during PLAY.

For most cases the limitation is correct — pre-PLAY illegality is caught earlier (e.g., Constants.lua's bid validation, or `S.ApplyDouble` rejecting Sun-Triple). But if a fan-malicious peer or version-skewed client manages to slip a stale escalation flag through PHASE_DOUBLE/TRIPLE/FOUR/GAHWA, no Takweesh recourse exists until PLAY starts — and by then the contract is locked. The user intended this finding because there are documented Saudi cases (e.g., declaring an illegal Bel on Sun >100 cumulative score, where R.CanBel rejects but a hand-edited client could broadcast it) where the offended team would want to qaid pre-bid.

**Severity:** LOW. The phase-gate is defensible (Takweesh's contract scan needs at least one play to scan), but worth noting — the `.illegal` framework in S.ApplyPlay is the only source of catch material and it's PLAY-scoped.

**Quote (Net.lua:2073):**

```lua
if S.s.phase ~= K.PHASE_PLAY then return end
```

---

### B-N3-6 — Mid-Takweesh /reload: takweeshResult banner not re-broadcast on PHASE_SCORE (LOW)

**Files:** `State.lua:212` (TRANSIENT_FIELDS), `WHEREDNGN.lua:130-300` (PLAYER_LOGIN restore), `Net.lua:386-465` (SendResyncRes resync replay).

**Code (State.lua:191-247):**

```lua
local TRANSIENT_FIELDS = {
    ...
    -- Takweesh result banner is also transient — its display lifetime
    -- ends when the next round starts (handled by ApplyStart).
    takweeshResult = true,
    ...
}
```

`takweeshResult` is excluded from session save by `S.SaveSession`. So a /reload during PHASE_SCORE post-Takweesh discards the banner.

Compare to other PHASE_SCORE-state fields:
- `lastRoundDelta` (the +addA/+addB) DOES persist (not in TRANSIENT_FIELDS).
- `lastRoundResult` is set to nil at Net.lua:2273, so it's already gone.
- `swaResult` is also TRANSIENT — but the SWA-rebroadcast doesn't help much because `_OnSWAOut` only fires on the wire path.

The PLAYER_LOGIN restore handler (WHEREDNGN.lua:130-300) re-arms `swaRequest` (line 270-292), `pendingPreemptContract` (256-269 area), `overcall` window (line 256-269), but does NOT re-broadcast or re-stamp `takweeshResult`. `Net.SendResyncRes` (Net.lua:386-465) replays tricks, melds, AKA, preempt, overcall, but NOT takweesh banner. A rejoiner during PHASE_SCORE post-Takweesh sees:
- Correct cumulative scores (via ApplyRoundEnd → addA/addB persisted)
- No catch-detail banner (caller / offender / card / reason all gone)
- No "TAKWEESH! X caught Y playing AC — illegal play" chat printout (already done at Resolve time)

**Severity:** LOW (UI-only degradation, scoring is correct). Already documented as part of `D-RT-27_reset_redeal.md`. Recommendation: either un-transient `takweeshResult` (it's small) or add a re-broadcast in PLAYER_LOGIN host-restore branch.

**Quote (State.lua:210-212):**

```lua
-- Takweesh result banner is also transient — its display lifetime
-- ends when the next round starts (handled by ApplyStart).
takweeshResult = true,
```

---

### B-N3-7 — `S.ApplyRoundEnd` call site missing sweep + bidderMade args → fanfare suppressed (LOW)

**Files:** `Net.lua:2264` (Takweesh), `Net.lua:2845` (SWA-invalid), `State.lua:1463-1530` (ApplyRoundEnd), `Net.lua:2291` (Takweesh SendRound).

**Code (Net.lua:2264):**

```lua
S.ApplyRoundEnd(addA, addB, totA, totB)
```

vs the canonical signature `S.ApplyRoundEnd(addA, addB, totA, totB, sweep, bidderMade)`.

Compare to the regular `_HostStepAfterTrick` call (Net.lua:1681):

```lua
S.ApplyRoundEnd(addA, addB, totA, totB, res.sweep, res.bidderMade)
```

The fanfare-fire path in S.ApplyRoundEnd (State.lua:1482-1485):

```lua
if B.Sound and B.Sound.Cue
   and (sweep ~= nil or bidderMade == false) then
    B.Sound.Cue(K.SND_BALOOT)
end
```

For a Takweesh resolution, the round did terminate — and the bidder team may have been the one caught (i.e., bidder failed). The canonical fanfare semantic ("fail" or "sweep") would benefit from firing here, but Takweesh passes nil for both args, so no fanfare. This is intentionally documented at Net.lua:271-294 (SendRound's three-state encoding — "" / "0" / "1"):

> Three-state encoding for bidderMade ("" | "0" | "1") so the receiver can distinguish "host didn't supply" (legacy / SWA / Takweesh paths) from explicit "bidder failed". Without this, pre-v0.3.0 hosts and Takweesh/SWA call sites that omit the flag would all decode as bidderMade=false, firing a spurious fanfare on every round-end.

So the omission is **deliberate**: the bidderMade=false condition would fire the BALOOT cue on EVERY Takweesh, even when the bidder was the one who CAUGHT (caller=bidder team, found illegal in opponent). The intent was to suppress incorrect fanfare. But it also suppresses CORRECT fanfare when the bidder team really did fail (bidder team played the illegal card and was caught). A more nuanced fix would set bidderMade based on whether `winnerTeam == R.TeamOf(c.bidder)`. Today's behavior: never fire. The "lost-round stinger" at State.lua:1493-1500 still fires correctly via delta-direction inference (whichever team has the larger add wins).

**Severity:** LOW. UI/audio-only; scoring math unaffected. Already documented as F4 in `C-Xref-02_score_pipeline.md`. Same omission at Net.lua:2845 (SWA-invalid `S.ApplyRoundEnd` and `SendRound` calls).

**Quote (Net.lua:2264):**

```lua
S.ApplyRoundEnd(addA, addB, totA, totB)
```

(missing 5th + 6th args)

**Quote (Net.lua:2291):**

```lua
N.SendRound(addA, addB, totA, totB)
```

(missing 5th + 6th args)

---

### B-N3-8 — Game-end propagation correct (INFO)

**Files:** `Net.lua:2324-2334` (Takweesh game-end), `Net.lua:1510-1515` (_OnGameEnd handler), `State.lua:1597-1607` (S.ApplyGameEnd idempotency).

**Code (Net.lua:2324-2334):**

```lua
if totA >= S.s.target or totB >= S.s.target then
    -- ...tiebreak elision (see B-N3-2)...
    S.ApplyGameEnd(winner)
    N.SendGameEnd(winner)
end
```

S.ApplyGameEnd is idempotent on duplicate winner (per D-RT-28 verification). The host calls it locally + broadcasts, and a non-host receiver runs the same handler via `_OnGameEnd` (Net.lua:1510-1515) — the wire-loopback `fromSelf` skip prevents double-apply on host.

`MSG_ROUND` is broadcast at Net.lua:2291 with the cumulative totals (totA, totB). So even non-host clients without the `MSG_TAKWEESH_OUT` decoded properly will still see correct cumulative scores via ApplyRoundEnd. Game-end determination on non-host is gated by `if not fromHost(sender) then return end` at Net.lua:1505 — so only the host's MSG_GAMEEND is honored. Defended against forged GAMEEND from non-host peers.

**No defect, recorded for completeness.**

---

## Cross-cut signal: SWA-invalid mirror

The post-v0.10.1 M1 forfeit semantics (offender melds zeroed) are **identically wired** in `HostResolveSWA`'s invalid branch at Net.lua:2940-2952. This is correct and intentional — SWA-invalid is a Qaid context per Saudi rules. But the same defects apply mirror-symmetrically:

| Defect | Takweesh | SWA-invalid |
|---|---|---|
| Belote-cancel per-player vs team | Net.lua:2240 | Net.lua:2972 |
| Tied-target tiebreaker H3 missing | Net.lua:2327 | Net.lua:3064 |
| Sun-mult compound (R2 not applied) | Net.lua:2185-2190 | Net.lua:2930-2935 |
| ApplyRoundEnd missing sweep/made args | Net.lua:2264 | Net.lua:2845 |

Any fix should be applied to both call sites.

---

## What v0.10.1 M1 itself got right

Verified clean:

1. `offenderTeam = (winnerTeam == "A") and "B" or "A"` (Net.lua:2216) — correct under both branches.
2. `mpA / mpB` zero on offender side, full meld value on winner side — the "winner adds own melds × mult" semantic per Saudi Source H H-36.12 + PDF 02 K-04.
3. Belote independence: `+K.MELD_BELOTE` applied AFTER multiplier (Net.lua:2250-2251), matches Pagat "Baloot always 2 points unaffected" + R.ScoreRound:898-912 pattern.
4. Symmetry with HostResolveSWA invalid branch — both paths use the same `mpA = ... 0 or meld?` pattern.
5. div10 alignment: `(rawA + 5) / 10` (line 2259) matches Rules.lua:918 (post-v0.5.21 fix). All three round-end paths converge.

The v0.10.1 changelog's claim "regular contract-fail in R.ScoreRound is a separate (non-Qaid) scenario and continues to keep both teams' own melds" is verified (Rules.lua:823-841 retains both teams' melds in the `outcome_kind == "fail"` branch).

---

## Confidence

**HIGH** on:
- B-N3-1 (Belote-cancel team-vs-player divergence) — verified by direct text comparison Net.lua:2240 vs Rules.lua:741.
- B-N3-2 (tiebreaker H3 missing) — verified by direct text comparison Net.lua:2327-2331 vs Net.lua:1693-1709.
- B-N3-3 (Sun-mult compound) — verified by direct text comparison Net.lua:2185-2190 vs Rules.lua:883-893; matches D-RT-09 Scenario 2b independent finding.
- B-N3-4 (Hokm Carré-A drop) — verified by direct text comparison State.lua:1173-1184 vs Rules.lua:273-287; constants comment Constants.lua:94 confirms the 100-raw spec.
- v0.10.1 M1 forfeit semantics integration with Takweesh penalty path.

**MEDIUM** on:
- B-N3-5 (pre-bid Tawzee Qaid lockout) — limitation is real, but whether it's a defect depends on user intent (Saudi sources don't strongly mandate pre-bid Qaid recourse for ALL escalation-window violations).
- B-N3-6 (mid-Takweesh /reload UI loss) — banner-only; scoring is preserved through cumulative.

**LOW** on:
- B-N3-7 (fanfare suppression) — intentional per author comments, but inconsistent vs other failure paths.

---

## Files cross-referenced

- `C:\CLAUDE\WHEREDNGN\Net.lua` — 2071-2339 (Takweesh full pipeline), 271-294 (SendRound), 1503-1515 (_OnRound/_OnGameEnd), 1683-1709 (canonical H3 tiebreak), 2848-3072 (HostResolveSWA mirror).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — 503-507 (R.SumMeldValue), 220-290 (R.DetectMelds), 661-953 (R.ScoreRound), 738-746 (canonical M5 belote-cancel), 883-893 (canonical R2 mult collapse).
- `C:\CLAUDE\WHEREDNGN\State.lua` — 191-247 (TRANSIENT_FIELDS), 1149-1189 (ApplyMeld — Hokm Carré-A drop), 1463-1530 (ApplyRoundEnd), 1597-1607 (ApplyGameEnd idempotency).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — 54 (HAND_TOTAL_*), 68-72 (MULT_*), 91-115 (MELD_*).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — 130-300 (PLAYER_LOGIN restore re-arms).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\xref_X5_meld_coverage.md` — Hokm Carré-A drop CRITICAL.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-01_swa_pipeline.md` — SWA pipeline cross-cut, F-1/F-2.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_C_xref\C-Xref-02_score_pipeline.md` — F1/F2/F4 (paths' scoring divergences).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-09_sun_escalation_bypass.md` — Scenario 2b/2c.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-23_multi_qaid_race.md` — concurrency idempotence.
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-28_score_boundary.md` — game-end boundary.
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` — v0.10.1 M1 entry.
