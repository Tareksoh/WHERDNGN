# B-UI-02 — Deep audit of UI banner panels and score display (v0.10.2)

**Track**: B (code review)
**Date**: 2026-05-05
**Scope**: Read-only audit of UI banner rendering paths in `UI.lua` — round-result banner, takweesh-result banner, SWA-result banner, redealing announcement, AKA banner, game-end fanfare path, score-card display, trick-by-trick breakdown, the D-RT-09 F4 / D-RT-30 banner gap (Triple/Four/Gahwa labels alongside collapsed multiplier), Belote silent cancellation (D-RT-20 #7), match-win type-blind UI display (D-RT-30 Scenario 2), and lobby team-name display.

**Files inspected**:
- `C:\CLAUDE\WHEREDNGN\UI.lua` — lines 1290-1316 (AKA banner frame), 1318-1372 (overcall banner frame), 1374-1484 (SWA banner frame), 1486-1516 (round-end banner frame), 2826-2840 (lobby team-name boxes), 2894-2908 (teamLabel helper), 2917-2925 (teamColor helper), 2937-2940 (yaMrw7 tease), 2942-3163 (renderBanner — the main banner switch), 3181-3192 (renderOvercallBanner), 3194-3234 (renderSWABanner), 3236-3257 (renderAKABanner), 3297-3342 (renderStatus / score / contract).
- `C:\CLAUDE\WHEREDNGN\State.lua` — lines 47, 103, 110-115, 137-158, 162-175, 191-247 (TRANSIENT_FIELDS), 519-534, 794-823 (ApplyStart clears), 1320-1327 (ApplyTrickEnd clears `akaCalled`), 1443-1450 (ApplyAKA), 1463-1607 (ApplyRoundEnd / ApplyRoundResult / ApplyGameEnd).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 661-952 (R.ScoreRound — Belote cancel at 738-746, sweep at 711-723, multiplier collapse at 884-893, Gahwa MATCH-WIN type-blind at 920-937).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 1640-1719 (_HostStepAfterTrick → ApplyGameEnd), 2270-2338 (HostResolveTakweesh → takweeshResult struct), 2461-2466 (_OnTeams), 2820-2846 (_OnSWAOut), 2862-3073 (HostResolveSWA → swaResult struct).
- Prior swarm work: D-RT-09 (Sun escalation bypass, F4 = UI undefended at lines 3140-3144 & 3322-3326), D-RT-20 (Belote cancel edges — finding #7 = silent UI cancellation), D-RT-27 (reset/redeal), D-RT-28 (score boundary), D-RT-30 (Gahwa attacks — Scenario 2 = type-blind match-win at Rules.lua:928), B-State-06 (round-end / game-end transitions, F7 = idempotent fanfare), B-Net-03 (takweesh full), B-Net-04 (SWA full).

---

## Executive verdict

The five banner systems (round-result, takweesh, SWA, redeal, AKA) and the game-end fanfare are **structurally correct on the happy paths** for current-canonical input. Lifetime semantics (transient fields, `:Hide()` on phase change, AKA per-trick clear, redeal 3.5s auto-clear) are clean.

**Six real bugs / gaps surface**, three confirmed cross-cuts of prior findings:

- **B-UI-02-1 HIGH** — Takweesh- or SWA-driven match-win is **completely invisible**. The PHASE_GAME_END branch at UI.lua:2996-3010 fires before the takweesh / SWA / sweep branches, so a hand whose Takweesh penalty (or SWA outcome) vaults a team to ≥152 shows ONLY the generic "8amt!! go play something else" banner — no offending card, no SWA outcome, no contract title. Cross-cut: D-RT-28 (score boundary), B-State-06 F7.
- **B-UI-02-2 MEDIUM** — D-RT-09 F4 + D-RT-30 Scenario 2 confirmed: the `mods` array at UI.lua:3140-3144 (round-end) and 3322-3326 (running contract) is **type-blind**. A Sun contract carrying stale `tripled/foured/gahwa` flags renders as `Sun · Bel · Triple · Four · Gahwa (match-win) · ×4` — the `×4` is correctly normalized by Rules.lua:884-893's collapse, but the textual mod list contradicts the multiplier. Defense-in-depth gap.
- **B-UI-02-3 LOW (UX)** — D-RT-20 #7 confirmed: a cancelled Belote (M5 path zeros `r.belote`) produces **zero user-visible signal**. The K+Q-trump holder who also has a quinte/quarte never sees an explanation for the missing +20.
- **B-UI-02-4 MEDIUM** — D-RT-30 Scenario 2 confirmed at the wire/state path: `Rules.lua:928` `if contract.gahwa then` gates the MATCH-WIN branch on the flag alone, **with no `contract.type ~= K.BID_SUN` guard**. This is upstream of the UI but produces a `gahwaWonGame=true` result on a stale Sun-Gahwa contract, which then drives `ApplyGameEnd` and the UI banner. The match-end UI is the visible blast radius.
- **B-UI-02-5 MEDIUM** — Valid SWA + failed contract is conflated with "SWA wins everything". The SWA banner branch (UI.lua:3017-3044) reads ONLY `sw.valid`, not `sw.contractMade`. A valid SWA on a contract that still failed shows "Claim verified — all remaining tricks awarded" with possibly-tiny deltas.
- **B-UI-02-6 LOW** — Sweep bonus (`K.AL_KABOOT_HOKM` = 200, `K.AL_KABOOT_SUN` = 300) is invisible in the round-end breakdown. The `bidder`/`defender` lines at UI.lua:3133-3136 print `cards N + melds N` from `r.teamPoints` and `r.meldPoints`, but in the sweep branch (Rules.lua:817-822) `cardA/cardB` is replaced by the bonus and `teamPoints` is the IN-TRICK total — the player sees the in-trick numbers, not the +200/+300 they actually scored. The "AL-KABOOT!" title is the only acknowledgement.

Plus four LOW informational notes:

- **B-UI-02-N1** — Multiplier flags shown as a list ("Bel · Triple · Four") even though Rules.lua:889-892's `elseif` chain treats them as exclusive. Same pattern in the running-contract banner.
- **B-UI-02-N2** — `S.s.takweeshResult.ts` and `S.s.swaResult.ts` are populated but never read (dead UI data).
- **B-UI-02-N3** — Non-host degraded banner (UI.lua:3087-3105) hides bidder/defender/modifiers/belote sub-lines unconditionally, even when the broadcast carried sweep/bidderMade enough to show a "Sweep" or "Failed" title prefix.
- **B-UI-02-N4** — `U.Refresh` does not freeze under `S.s.paused` — banner content keeps re-rendering. Mostly harmless (banner data is mostly static during PHASE_SCORE), but the SWA banner's `OnUpdate` correctly freezes (line 1458) where the central `renderBanner` does not gate on pause.

**Severity tally**: 0 CRITICAL · 1 HIGH (B-UI-02-1) · 3 MEDIUM (2, 4, 5) · 2 LOW (3, 6) · 4 LOW-INFO (N1-N4).

---

## Banner inventory and lifetime

| Banner | Frame | State source | Lifetime | Render fn |
|---|---|---|---|---|
| **Round-result** (centered, 270×196) | `tablePanel.banner` (UI.lua:1496-1516) | `S.s.lastRoundResult` (host) + `S.s.lastRoundDelta` (all) | PHASE_SCORE / PHASE_GAME_END only | `renderBanner` (2942-3163) |
| **Takweesh-result** (re-uses round banner) | same frame | `S.s.takweeshResult` | Cleared at `S.ApplyStart` (State.lua:806) and on resync (State.lua:526) | branch in `renderBanner` (3046-3082) |
| **SWA-result** (re-uses round banner) | same frame | `S.s.swaResult` | Cleared at `S.ApplyStart` (State.lua:807) and on resync (State.lua:527) | branch in `renderBanner` (3017-3044) |
| **Redeal** (re-uses round banner) | same frame | `S.s.redealing = {nextDealer, ts}` | `S.ApplyRedealAnnouncement` 3.5s auto-clear (State.lua:149-156) | branch in `renderBanner` (2950-2962) |
| **AKA toast** (180×22, top of centerPad) | `tablePanel.akaBanner` (UI.lua:1295-1316) | `S.s.akaCalled = {seat, suit}` | Cleared at `ApplyTrickEnd` (State.lua:1327) | `renderAKABanner` (3236-3257) |
| **Overcall countdown** (280×38) | `tablePanel.overcallBanner` (UI.lua:1322-1372) | `S.s.overcall` | PHASE_OVERCALL only, OnUpdate self-ticks | `renderOvercallBanner` (3181-3192) |
| **SWA-pending preview** (280×100, +card row) | `tablePanel.swaBanner` (UI.lua:1390-1484) | `S.s.swaRequest` | PHASE_PLAY only, OnUpdate self-ticks | `renderSWABanner` (3194-3234) |
| **Game-end** (re-uses round banner) | same frame | `S.s.winner`, `S.s.cumulative` | PHASE_GAME_END only | branch in `renderBanner` (2996-3010) |
| **Score line** (bottom of main frame) | `scoreText` (UI.lua:594-596) | `S.s.cumulative.A/B`, `S.s.target` | always (when frame shown) | `renderStatus` (3303-3305) |
| **Contract line** (bottom of main frame) | `contractText` (UI.lua:601-605) | `S.s.contract` | when contract set | `renderStatus` (3307-3338) |
| **AFK pulse** (border flash on localBar) | `tablePanel.localBar` | Net.lua local-warn timer | 3-flash burst, ticker-based | `_pulseTicker` (UI.lua:3393+) |

**Banner-state precedence** (in `renderBanner`, top-to-bottom):

1. `S.s.redealing` → "All passed — redealing" (line 2950, **highest priority**)
2. `S.s.phase ~= PHASE_SCORE and ~= PHASE_GAME_END` → `:Hide()` (line 2965)
3. `PHASE_GAME_END` → "8amt!! go play something else" (line 2996, **wins over Takweesh/SWA/sweep**)
4. `S.s.swaResult` (line 3017)
5. `S.s.takweeshResult` (line 3046)
6. `S.s.lastRoundResult == nil` → non-host degraded (line 3087)
7. `r.sweep` → AL-KABOOT (line 3116)
8. `not r.bidderMade` → BALOOT (line 3122)
9. otherwise → ALLY B3DO (line 3126)

This precedence is the **root of B-UI-02-1 below** — GAME_END takes priority over SWA/Takweesh detail.

---

## 1. (B-UI-02-1, **HIGH**) Match-ending Takweesh / SWA shows zero detail

**Severity**: HIGH (UX correctness — player loses ability to learn from the round that ended the match).

**Trigger**: Last round of a match (cumulative near 152) where the round-ender is a Takweesh penalty or SWA outcome that pushes the winner to ≥152.

**Quote** (UI.lua:2996-3010, the GAME_END branch executes BEFORE the takweesh/SWA branches):

```lua
if S.s.phase == K.PHASE_GAME_END then
    -- Match-end WIN/LOST headline (re-uses round-end outcome
    -- styling for consistency).
    setOutcome(S.s.winner)
    banner:Show()
    banner:SetBackdropBorderColor(unpack(COL.legalEdge))
    banner.title:SetText(("|cffffd0558amt!! go play something else|r"))
    -- Audit C30 fix: use teamLabel for custom team-name display.
    -- Previously showed "Team A wins" even when host had set custom
    -- names like "Champs" / "Rivals".
    local winLabel = S.s.winner and teamLabel(S.s.winner) or "?"
    banner.final:SetText(("%s wins  —  %d / %d"):format(
        winLabel, S.s.cumulative.A or 0, S.s.cumulative.B or 0))
    return
end
```

After this `return`, the takweesh check (3046) and SWA check (3017) are unreachable. State still has `S.s.takweeshResult` populated (from `Net.lua:2276-2289` — set BEFORE `ApplyGameEnd` runs at `Net.lua:2332`), but the UI branch silences it.

**Repro**:
1. Host sets `target = 100` (or similar low value where a single hand's penalty ends the match).
2. Reach a state where one team is at e.g. 92, the other at 50, and a hand is in flight.
3. Defender plays an illegal card; opponent calls Takweesh; the qaid penalty pushes the cumulative ≥ target.
4. `Net.HostResolveTakweesh` sets `S.s.takweeshResult` (line 2276-2289), broadcasts MSG_ROUND, then sees `totA >= S.s.target` and calls `S.ApplyGameEnd(winner)` (line 2332).
5. `S.s.phase = PHASE_GAME_END`. UI refreshes.
6. `renderBanner` hits PHASE_GAME_END branch first (line 2996), returns without showing "TAKWEESH! X caught Y" detail.

Same path applies to SWA at `Net.lua:3069-3070`.

**Impact**: The player whose match was decided by a Takweesh/SWA call sees no acknowledgment of WHICH card was illegal or WHO got caught — just the generic match-end message. Particularly painful for SWA where the user doesn't even know if it was valid or invalid.

**Fix shape**: Reorder the branches so Takweesh/SWA detail is shown alongside the match-end headline. Either (a) inline the takweesh/SWA detail into the GAME_END branch when those structs are populated, or (b) move the GAME_END headline out of `renderBanner` into a separate frame layered above.

**Cross-cut**: D-RT-28 (score boundary), B-State-06 F7 (idempotent fanfare — the fanfare DOES fire on takweesh-induced match-win because S.ApplyRoundEnd at line 1482-1485 is called BEFORE ApplyGameEnd; the visual side is the gap).

---

## 2. (B-UI-02-2, MEDIUM) D-RT-09 F4 + D-RT-30 confirmed: type-blind Triple/Four/Gahwa labels

**Severity**: MEDIUM (defense-in-depth; not reachable in a non-tampered host on canonical play).

**Quote** (UI.lua:3140-3148, round-end banner mods line):

```lua
-- Modifiers line: contract type + multiplier
local typeStr = (S.s.contract and S.s.contract.type == K.BID_SUN) and "Sun" or "Hokm"
local mods = { typeStr }
if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel" end
if S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Triple" end
if S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
if S.s.contract and S.s.contract.gahwa then mods[#mods + 1] = "Gahwa (match-win)" end
if r.multiplier and r.multiplier > 1 then
    mods[#mods + 1] = ("×%d"):format(r.multiplier)
end
banner.modifiers:SetText("|cffaaaaaa" .. table.concat(mods, "  ·  ") .. "|r")
```

Same pattern at the running-contract line (UI.lua:3322-3326):

```lua
local mods = {}
if c.doubled    then mods[#mods + 1] = "Bel (x2)"        end
if c.tripled    then mods[#mods + 1] = "Triple (x3)"     end
if c.foured     then mods[#mods + 1] = "Four (x4)"       end
if c.gahwa      then mods[#mods + 1] = "Gahwa (match)"   end
```

**Trigger**: stale Sun contract with `tripled=true` / `foured=true` / `gahwa=true` (legitimately impossible on canonical phase progression — `State.ApplyDouble` jumps Sun directly to PHASE_PLAY per the comment at Rules.lua:874-876 — but reachable via hand-edited SVars, restored session from a buggy build, or a wire-frame attack on a desynced peer per D-RT-30 Scenario 2).

**Observable**: a Sun contract with stale `tripled+foured+gahwa` shows
```
Sun  ·  Bel  ·  Triple  ·  Four  ·  Gahwa (match-win)  ·  ×4
```
where Rules.lua:884-887 has correctly collapsed the multiplier to ×4 (Sun×Bel) — but the textual list contradicts. Asymmetric scorer↔UI behavior.

**Fix shape** (D-RT-09 F4 recommendation, three-line cost):

```lua
local sun = S.s.contract and S.s.contract.type == K.BID_SUN
if S.s.contract and S.s.contract.doubled then mods[#mods + 1] = "Bel" end
if not sun and S.s.contract and S.s.contract.tripled then mods[#mods + 1] = "Triple" end
if not sun and S.s.contract and S.s.contract.foured then mods[#mods + 1] = "Four" end
if not sun and S.s.contract and S.s.contract.gahwa then mods[#mods + 1] = "Gahwa (match-win)" end
```

Mirrors the R2 normalization already applied at Rules.lua:884-887.

**Cross-cut**: D-RT-09 finding 2d, D-RT-30 Scenario 2.

---

## 3. (B-UI-02-3, LOW) D-RT-20 #7 confirmed: silent Belote cancellation

**Severity**: LOW (cosmetic / UX) but high-value relative to fix cost.

**Quote** (UI.lua:3150-3153):

```lua
-- Belote line (if applicable)
if r.belote then
    banner.belote:SetText(("Belote (K+Q ♥): %s +20 raw"):format(teamLabel(r.belote)))
end
```

**Trigger**: K+Q-trump holder also has a 100-meld (carré of T/K/Q/J/A or quinte) — Rules.lua:738-746 zeros `belote` so the banner branch is skipped, AND line 2993's blanket `banner.belote:SetText("")` clears any previous text. The user sees no acknowledgement.

**Repro**:
1. Hokm-Spades, bidder holds K♠+Q♠+J♠+T♠+9♠ (quinte = 100, also K+Q for Belote).
2. R.ScoreRound at line 738-746: walks `meldsByTeam[A]`, finds quinte with value=100, sets `belote = nil`.
3. UI receives `r.belote == nil`. Banner shows score breakdown WITHOUT a "Belote cancelled by 100-meld" line.
4. From the player's perspective: "where's my +20?"

**Fix shape** (D-RT-20 recommendation): expose a `r.beloteCancelled = true` flag from `R.ScoreRound`, and have UI show "Belote cancelled by ≥100 meld" when set. Same Saudi rule but obscure; players will challenge it if silent.

**Cross-cut**: D-RT-20 #7 ("UI notification of cancellation — MISSING").

---

## 4. (B-UI-02-4, MEDIUM) Type-blind Gahwa MATCH-WIN at Rules.lua:928 surfaces in match-end UI

**Severity**: MEDIUM (defense-in-depth at the rule layer; the visible blast radius is the GAME_END banner).

**Quote** (Rules.lua:920-937):

```lua
-- Gahwa MATCH-WIN branch (v0.2.0+, per "نظام الدبل في لعبة البلوت"):
-- a successful Gahwa wins the entire match for the caller's team
-- regardless of point delta. A failed Gahwa hands the match to
-- defenders. Override the per-round delta to push cumulative-to-
-- target by signaling a "match-win" flag the caller (Net.lua's
-- HostStepAfterTrick) can read off the result struct.
local gahwaWonGame = false
local gahwaWinner
if contract.gahwa then
    -- Caller's team = bidder team. They "win" if bidderMade
    -- (made or doubled-tie inversion), "lose" otherwise.
    if bidderMade then
        gahwaWinner = bidderTeam
    else
        gahwaWinner = oppTeam
    end
    gahwaWonGame = true
end
```

**Trigger**: stale Sun contract with `gahwa=true` (same vector as B-UI-02-2). The multiplier path correctly collapses (Rules.lua:884-887 ignores `gahwa` for Sun), but the MATCH-WIN gate at line 928 reads only `contract.gahwa` — no `contract.type ~= K.BID_SUN` guard.

**Asymmetry**: `mult` is collapsed (Sun-Bel = ×4), but `gahwaWonGame=true` and `gahwaWinner` are returned — Net.lua:1669-1678 then forces the caller's cumulative to target, ApplyGameEnd fires, UI shows match-end. A Sun-Gahwa stale flag jumps the match.

**Fix shape** (D-RT-30 Scenario 2 recommendation):

```lua
if contract.gahwa and contract.type ~= K.BID_SUN then
    ...
    gahwaWonGame = true
end
```

**Cross-cut**: D-RT-30 Scenario 2 (`Rules.lua:928 is NOT type-gated`). Listed here because the visible UI behavior — a Sun contract showing "Gahwa (match-win)" alongside ×4, then the GAME_END banner — is what the player sees.

---

## 5. (B-UI-02-5, MEDIUM) Valid SWA + failed contract conflated with "claim wins all"

**Severity**: MEDIUM (UX correctness — player misreads outcome).

**Quote** (UI.lua:3017-3044, the SWA branch):

```lua
if S.s.swaResult then
    local sw = S.s.swaResult
    local d = S.s.lastRoundDelta or { A = 0, B = 0 }
    local cName = (sw.caller and S.s.seats[sw.caller]
                   and shortName(S.s.seats[sw.caller].name)) or "?"
    local callerTeam = sw.caller and R.TeamOf(sw.caller)
    local oppTeam = callerTeam and ((callerTeam == "A") and "B" or "A") or nil
    banner:Show()
    if sw.valid then
        -- valid SWA → caller's team wins
        setOutcome(callerTeam)
        banner:SetBackdropBorderColor(0.30, 0.85, 0.45, 1)
        banner.title:SetText(("|cffffd055SWA!|r %s claimed the rest%s"):format(
            cName, yaMrw7(oppTeam)))
        banner.bidder:SetText("Claim verified — all remaining tricks awarded.")
    else
        ...
    end
    banner.final:SetText(...)
    return
end
```

**Trigger**: Defender calls SWA in a Sun contract where the caller-team trick total is high but the bidder still failed because the SWA-trick assignments don't push them past the strict-majority threshold. `sw.valid=true` (the claim was legally awardable) but `sw.contractMade=false` (the contract still failed for the bidder, who is a different team).

The banner says "SWA! X claimed the rest — all remaining tricks awarded" with positive-framing colour AND `setOutcome(callerTeam)` paints WIN for the caller's team — but if caller is on defender team and the SWA contributes to a contract-fail that gives defenders the qaid penalty, the actual delta might be HUGE for defenders and zero for bidders. That's a clean win for caller's team. OK so far.

But the inverse: caller is bidder team, SWA awards remaining tricks, but bidder STILL fails because their accumulated total minus the meld-loser penalty doesn't beat oppTotal. Now `sw.valid=true` (claim was legally accurate) but `sw.contractMade=false` (bidder failed) — caller's team gets the qaid penalty against THEM. The banner shows "claim verified — all remaining tricks awarded" with `setOutcome(callerTeam)` painting WIN for the caller's team — but the actual delta makes them the LOSER. The colour-coded final line will show the actual deltas, but the WIN headline contradicts.

The state struct DOES carry `sw.contractMade` (set at Net.lua:3050), but the banner branch ignores it. The `setOutcome` should follow the actual delta (deferring to `bidderMade` and contract awarding rules), not just `valid`.

**Repro** (rare but real): Hokm contract, bidder calls SWA on remaining 4 tricks where two of those tricks have low-point cards. Bidder's cumulative trick-points + melds end up BELOW oppTotal because one of the synthesized tricks lacks a 9 or J that the opp would otherwise have lost. SWA "valid" by `R.IsValidSWA` (the claim is technically achievable), but `R.ScoreRound` over the synthesized tricks at Net.lua:3038 returns `bidderMade=false`. UI says "SWA! claim verified" — but the bidder team got penalized.

**Fix shape**: In the SWA banner branch, gate `setOutcome` and the title text on `sw.contractMade` (or recompute `winningTeam` from the deltas):

```lua
if sw.valid then
    local actualWinner
    if sw.contractMade then actualWinner = (R.TeamOf(S.s.contract.bidder)) -- bidder team
    else actualWinner = (R.TeamOf(S.s.contract.bidder) == "A") and "B" or "A" end
    setOutcome(actualWinner)
    -- ... use actualWinner for colouring and yaMrw7 tease
```

**Cross-cut**: B-Net-04 (SWA full audit) does cover this region but is scoped to the wire pipeline; the UI mismatch is downstream.

---

## 6. (B-UI-02-6, LOW) Sweep bonus invisible in breakdown

**Severity**: LOW (UX info gap; the title "AL-KABOOT!" is the implicit signal).

**Quote** (UI.lua:3132-3136):

```lua
-- Per-team breakdown lines: cards + melds raw
banner.bidder:SetText(("%s: cards %d + melds %d"):format(
    teamLabel(bidT), r.teamPoints[bidT] or 0, r.meldPoints[bidT] or 0))
banner.defender:SetText(("%s: cards %d + melds %d"):format(
    teamLabel(oppT), r.teamPoints[oppT] or 0, r.meldPoints[oppT] or 0))
```

`r.teamPoints[t]` is the **in-trick** card-point total (Rules.lua:668). In a sweep, Rules.lua:818-820 replaces `cardA/cardB` with `K.AL_KABOOT_HOKM` (200) or `K.AL_KABOOT_SUN` (300) — but `teamPoints` is NOT mutated (it's read-only after the trick loop). The breakdown line shows e.g. "Team A: cards 162 + melds 50" while the actual scoring used 200 (Hokm sweep). The +38 from the sweep bonus is invisible in the breakdown.

**Repro**:
1. Hokm contract. Bidder team sweeps all 8 tricks.
2. `r.teamPoints[bidT]` is the sum of in-trick points (~152 + 10 last-trick = 162 in a Hokm sweep).
3. `r.multiplier` shows ×1, ×2, ×3, etc.
4. Banner displays "cards 162 + melds N", multiplier, deltas. Player thinks "162 × 2 = 324 raw" but Rules used 200 × 2 = 400 raw. Off by ~38 raw = 4 game points.

**Fix shape**: when `r.sweep == bidT` or `r.sweep == oppT`, augment the bidder/defender lines:

```lua
if r.sweep then
    local bonus = (S.s.contract.type == K.BID_SUN) and K.AL_KABOOT_SUN or K.AL_KABOOT_HOKM
    banner.bidder:SetText(("%s: AL-KABOOT %d + melds %d"):format(
        teamLabel(r.sweep), bonus, r.meldPoints[r.sweep] or 0))
    -- defender line: 0 + 0 (loser gets nothing in a sweep)
end
```

---

## 7. (B-UI-02-N1, LOW-INFO) Multiplier flags shown as a "list"

The mods array additively concatenates "Bel · Triple · Four · Gahwa (match-win)" if all flags are set, even though Rules.lua:889-892 treats them as **mutually exclusive** (`elseif` chain — only one applies). On a canonical contract this is fine because the phase machine sets only one (Bel→Triple→Four→Gahwa each replaces the prior in escalation), but the UI presentation reads them as additive. Combined with B-UI-02-2 (type-blindness), a stale-flag scenario shows all four.

**Note**: `Bel` is NOT mutually exclusive with the others — it can stack with Triple (Bel triggers Triple in Saudi rule). So showing both "Bel" and "Triple" is correct. But "Triple" and "Four" are mutually exclusive, and "Four" and "Gahwa" are mutually exclusive. The list-style display erases that.

---

## 8. (B-UI-02-N2, LOW-INFO) Dead `ts` fields

`S.s.takweeshResult.ts` (Net.lua:2282, 2288) and `S.s.swaResult` (no ts) — neither is read anywhere in UI.lua or other modules. Inert state with no UI auto-clear (lifecycle is handled by ApplyStart/Reset/ApplyResyncSnapshot clearing the whole struct).

---

## 9. (B-UI-02-N3, LOW-INFO) Non-host degraded view hides sweep/fail context

UI.lua:3087-3105:

```lua
if not r then
    -- Non-host: degraded view, just the delta. Loser inferred from
    -- the broadcast delta (lower delta = the team that took the
    -- penalty side of this round).
    ...
    banner.title:SetText("Round done" .. yaMrw7(nonHostLoser))
    banner.final:SetText(("%s +%d   %s +%d"):format(...))
    return
end
```

Non-hosts only see the delta. MSG_ROUND broadcast carries `sweep` + `bidderMade` (per Net.lua:1681-1682 SendRound), and `S.ApplyRoundEnd` consumes them — but doesn't stash them anywhere the UI can read. So non-hosts can't paint AL-KABOOT! / BALOOT! titles. The host's bidder/defender breakdown uses host-only `lastRoundResult.teamPoints`; that's harder to backport. But the title prefix could be carried.

**Fix shape**: stash `sweep` + `bidderMade` on `S.s.lastRoundDelta` (or a sibling struct). Non-host banner can then paint the correct title.

---

## 10. (B-UI-02-N4, LOW-INFO) `renderBanner` does not gate on pause

The OnUpdate self-tickers for SWA banner (UI.lua:1458) and overcall banner (UI.lua:1350) explicitly freeze on `S.s.paused`. The central `renderBanner` does NOT. In practice this is harmless during PHASE_SCORE / PHASE_GAME_END (banner content is static during pause), but the redeal path's `ts` field is wall-clock-based and the `C_Timer.After 3.5` in `S.ApplyRedealAnnouncement` continues ticking even under pause. The `nm` text doesn't refresh (it's the same name) but a paused redeal would auto-clear after 3.5s of real time, not 3.5s of unpaused time. Edge: pause for 30s, redeal banner gone before resume. Minor.

---

## 11. Lobby team-name display

Reviewed UI.lua:625-665 (lobbyPanel.teamA/teamB EditBoxes), 2826-2840 (refresh path).

**Findings**: clean. `SetMaxLetters(20)` matches `S.ApplyTeamNames`'s `:sub(1, 20)` truncation in State.lua:165-166. Editable only by host (line 2834). Pre-fills from `S.s.teamNames` on every refresh except when the box has focus (lines 2828, 2831 — prevents typing-while-host-syncs from blowing away in-flight input). Color flips between editable-white and read-only-grey (lines 2837-2839). Wire propagation via `B.Net.SendTeams` on commit (line 657). Receiver `_OnTeams` (Net.lua:2461-2466) gates on `fromHost(sender)`. ✅

**One micro-note**: `:HasFocus()` exists, but if the host is currently editing while a non-host EditBoxes (which are disabled — line 2835) somehow had focus, the gate would prevent refresh. Disabled EditBoxes can't receive focus in standard WoW UI, so this is fine.

---

## 12. AKA banner

Reviewed UI.lua:1295-1316 (frame), 3236-3257 (renderAKABanner), State.lua:1443-1450 (ApplyAKA), 1320-1327 (ApplyTrickEnd clears).

**Findings**: clean. Phase-gated to PHASE_PLAY (line 3241). Correctly cleared at trick end. Color-coded by partner-vs-opponent (line 3250-3254). z-order bump at line 1311 (FrameLevel +50) lifts the banner above center cards — note from line 1306-1311 that pre-fix it was overlapped by trick cards.

**One observation**: the AKA banner anchor (TOP, centerPad, TOP, 0, -4) overlaps the SWA-pending banner (TOP, centerPad, TOP, 0, -32, height 100). If both were active simultaneously (defender calls SWA, partner has called AKA in same trick — not possible in canonical play because SWA fires only when AKA-irrelevant, but defensively): both banners would render with same FrameLevel +50, render-order determined by parent's child list (AKA created first → SWA above). The 22-px AKA banner at y=-4 to y=-26 would be partially hidden by the 100-px SWA banner at y=-32 to y=-132. Visual collision in a contrived state.

---

## 13. Overcall countdown banner

Reviewed UI.lua:1322-1372 (frame + OnUpdate), 3181-3192 (render).

**Findings**: clean. Self-tick at 3 Hz. Pause-frozen (line 1350). Phase-gated to PHASE_OVERCALL (line 1341, 3184). The render path `if S.s.phase ~= K.PHASE_OVERCALL or not S.s.overcall` early-outs on phase exit (line 1341, 3184). `_lastRemain` triggers a U.Refresh on second-change (line 1365-1369) so action buttons get the new digit too.

**One observation**: line 1365 — when `remain` changes, `U.Refresh` is called. This is a recursive call from inside an OnUpdate. WoW's tail-call protection prevents infinite recursion (the OnUpdate doesn't re-fire mid-tick), but it's worth noting that any state mutation in the OnUpdate would propagate before the OnUpdate's own work finishes.

---

## 14. SWA-pending banner (the preview, not the result)

Reviewed UI.lua:1390-1484 (frame + card row + OnUpdate), 3194-3234 (render).

**Findings**: clean. Caller-team-aware text (line 1467-1476, 3219-3225). Pause-frozen (line 1458). Card row populated lazily on `_lastEnc` change (line 1479-1482, 3229-3232). Phase-gated to PHASE_PLAY (line 1460, 3198). Hides + clears `_lastEnc` on phase exit (line 1461, 3199-3204).

**One observation**: line 3198 hides the banner if `not req or not req.caller or S.s.phase ~= K.PHASE_PLAY`. But `req.caller` validates only that the field is present; doesn't check `S.s.seats[req.caller]` exists (line 3206: `S.s.seats and S.s.seats[req.caller]` — defensive). If a stale `swaRequest` survives a partial state restore where `req.caller` references a now-absent seat, name resolution falls back to `"seat N"` — graceful.

---

## 15. Game-end fanfare (idempotent)

Reviewed State.lua:1597-1607 (ApplyGameEnd) and 1463-1485 (ApplyRoundEnd fanfare).

**Findings**: idempotent guard at line 1602-1604:

```lua
if s.phase == K.PHASE_GAME_END and s.winner == winnerTeam then
    return
end
```

This prevents the BALOOT-fanfare cue from double-firing on duplicate broadcasts (host loopback + `_OnGameEnd` from another client). The fanfare itself fires from `S.ApplyRoundEnd` (line 1482-1485) which is called BEFORE `ApplyGameEnd`, gated on `(sweep ~= nil or bidderMade == false)` — so a contract-made non-sweep round doesn't fire it. ✅

**Cross-cut**: B-State-06 F7 confirmed.

**One observation**: a FORCED redeal sequence (kawesh / all-pass) does NOT fire the fanfare (no `sweep`/`bidderMade` signal — all-pass calls `_HostRedeal`, not the round-end path). Correct.

---

## 16. Trick-by-trick breakdown — NOT DISPLAYED

The round-end banner shows only TEAM totals (cards N + melds N per team). There is no per-trick breakdown — no list of "trick 1: A took 25, trick 2: B took 14, ..." or last-trick attribution.

`R.ScoreRound` returns `lastTrickTeam` (Rules.lua:942) — the team that won the +10 last-trick bonus — but UI.lua never reads `r.lastTrickTeam`. The +10 is silently bundled into `teamPoints`. A player who held J of trump but lost trick 8 to the opponent's missed rough has no UI signal that the +10 went the wrong way.

**Severity**: This is by design (the banner is intentionally compact), so not a bug. Listed here as completeness for the audit scope.

---

## 17. Score-card cumulative display

Reviewed UI.lua:3303-3305:

```lua
scoreText:SetText(("%s: |cff66ff66%d|r   %s: |cffff6666%d|r   /  %d"):format(
    nA, S.s.cumulative.A or 0, nB, S.s.cumulative.B or 0,
    S.s.target or 152))
```

**Findings**: clean. Both teams shown. Custom team names with fallback. Target visible. Hardcoded color (A=green, B=red) does NOT respect the local-seat us-vs-them flip — opposing-team players see their own team in red. The round-end banner uses `teamColor()` for proper us-vs-them coloring; the cumulative score line uses raw A=green/B=red.

**Severity**: LOW (cosmetic; the score line color doesn't carry the same meaning as the banner). Listed for completeness.

---

## Summary table

| ID | Sev | Region | Finding | Cross-cut |
|---|---|---|---|---|
| **B-UI-02-1** | HIGH | UI.lua:2996-3010 | Match-end via Takweesh/SWA shows zero detail | D-RT-28, B-State-06 F7 |
| **B-UI-02-2** | MED | UI.lua:3140-3144, 3322-3326 | Triple/Four/Gahwa labels rendered without `type==BID_SUN` check | D-RT-09 F4, D-RT-30 |
| **B-UI-02-3** | LOW | UI.lua:3150-3153 | Belote silent cancellation has no UI notification | D-RT-20 #7 |
| **B-UI-02-4** | MED | Rules.lua:928 (UI is downstream) | Gahwa MATCH-WIN not type-gated; surfaces in match-end UI | D-RT-30 Scenario 2 |
| **B-UI-02-5** | MED | UI.lua:3017-3044 | Valid SWA + failed contract conflated; `setOutcome` ignores `sw.contractMade` | B-Net-04 |
| **B-UI-02-6** | LOW | UI.lua:3132-3136 | Sweep bonus (+200/+300) invisible; breakdown shows in-trick `teamPoints` | — |
| **B-UI-02-N1** | INFO | UI.lua:3140-3144 | Multiplier flags rendered as additive list, not exclusive | — |
| **B-UI-02-N2** | INFO | takweeshResult.ts, swaResult.ts | Dead state fields | — |
| **B-UI-02-N3** | INFO | UI.lua:3087-3105 | Non-host degraded view ignores broadcast `sweep`/`bidderMade` flags | — |
| **B-UI-02-N4** | INFO | renderBanner, ApplyRedealAnnouncement | Pause not honored by central renderBanner / 3.5s timer | — |
| Lobby team-name | OK | UI.lua:625-665, 2826-2840 | Clean | — |
| AKA banner | OK | UI.lua:1295-1316, 3236-3257 | Clean (one z-order edge with SWA preview) | — |
| Overcall banner | OK | UI.lua:1322-1372, 3181-3192 | Clean | — |
| SWA preview | OK | UI.lua:1390-1484, 3194-3234 | Clean | — |
| Game-end fanfare | OK | State.lua:1463-1485, 1597-1607 | Idempotent | B-State-06 F7 |
| Trick breakdown | n/a | — | Not displayed (by design) | — |
| Score line | NIT | UI.lua:3303-3305 | Hardcoded A=green/B=red ignores local-seat | — |

---

## Files referenced

- `C:\CLAUDE\WHEREDNGN\UI.lua` (banner frames, render functions, lobby team-name boxes)
- `C:\CLAUDE\WHEREDNGN\State.lua` (banner state structs, transient flags, lifecycle)
- `C:\CLAUDE\WHEREDNGN\Rules.lua` (R.ScoreRound — Belote cancel, sweep, multiplier collapse, Gahwa MATCH-WIN)
- `C:\CLAUDE\WHEREDNGN\Net.lua` (HostResolveTakweesh, HostResolveSWA, _HostStepAfterTrick, ApplyGameEnd flow)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-09_sun_escalation_bypass.md` (F4 prior)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-20_belote_cancel_edges.md` (#7 prior)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_D_redteam\D-RT-30_gahwa_attacks.md` (Scenario 2 prior)
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-03_takweesh_full.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-Net-04_swa_full.md`
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.2\_track_B_code\B-State-06_roundEnd_gameEnd.md`
