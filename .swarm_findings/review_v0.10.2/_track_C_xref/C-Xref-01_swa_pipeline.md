# C-Xref-01: SWA Pipeline End-to-End Cross-Cut

**Audit version**: v0.10.2
**Track**: C (cross-reference)
**Date**: 2026-05-05
**Scope**: Full SWA pipeline — UI button → Net.LocalSWA → permission flow → R.IsValidSWA → HostResolveSWA → S.ApplyRoundEnd → R.ScoreRound sweep branch + Bot.PickSWA bot-side asymmetry.

---

## TL;DR

End-to-end correctness is **GOOD on the happy path** and **GOOD on the post-v0.10.1 forfeit semantics** (caller's team melds zeroed on invalid SWA). The R3 reaudit's behavioral verdict still stands: instant ≤3 / permission ≥4 / mandatory ≥5 are all routed through the same plumbing (`needPerm` branch); the 5-sec timer is documented (correctly) as addon-UX, not a Saudi rule.

But the cross-cut surfaces **five real issues** that have no individual layer's audit:

1. **F-1 (NEW, MEDIUM)** — UI's SWA button has **no hand-count gate**. A human can fire the SWA permission flow at 8 cards (round-start), guaranteeing a Qaid against their own team via the deterministic-or-bust `R.IsValidSWA`. Bot has the gate (`#hand <= 4` at Bot.lua:3871), human doesn't.
2. **F-2 (NEW, MEDIUM)** — Bot-fired SWA timer (Net.lua:4059) does NOT re-arm on pause; the two human-initiated paths (LocalSWA at 2546, _OnSWAReq at 2693) DO re-arm. Asymmetric pause behavior — a `/pause` during a bot's 5-sec window silently discards the auto-resolve, leaving `swaRequest` stale until something else clears it.
3. **F-3 (NEW, LOW)** — `renderSWABanner` (UI.lua:3210-3212) computes countdown directly from `req.ts` without subtracting paused time, so the banner countdown CAN drift downward during pause. The OnUpdate self-tick at UI.lua:1456-1458 freezes correctly, but the Refresh-driven render path doesn't. UI-only display flicker; doesn't affect the host's actual timer (which is C_Timer-based and re-armed on pause-resume).
4. **F-4 (NEW, LOW)** — Race window: a Takweesh fired DURING the SWA permission window correctly clears `swaRequest` (Net.lua:2144), BUT the C_Timer.After bot-auto-accept already ran synchronously inside `_OnSWAReq` before the Takweesh broadcasts, so the responses table is partially populated when Takweesh arrives. This is harmless because `HostResolveTakweesh` is the dominant resolver, but it's not idempotent if the wire delivery interleaves badly with `_OnSWAResp` arriving after Takweesh.
5. **F-5 (NEW, LOW)** — Mid-trick SWA validation: `R.IsValidSWA` correctly uses partial trickState (Rules.lua:387-405 `#plays == 4` branch handles the in-flight trick), and `HostResolveSWA` reconstructs trickState faithfully (Net.lua:2888-2904, including the V14 fix for "no plays in flight, leader = S.s.turn"). This is solid.

**No blocker bugs. Two MEDIUM additions to the v0.10.2 review backlog (F-1, F-2). Three LOW notes.**

---

## End-to-End Trace (the happy path)

### Step 1 — UI button (UI.lua:1997-2030)

**Visibility**: `S.s.phase == K.PHASE_PLAY` AND `S.s.localSeat` AND `WHEREDNGNDB.allowSWA ~= false` AND `S.s.swaRequest == nil`.

**No gate** on hand-count, validity, or partial-trick state. Confirmation flow via `addConfirmAction` (two-click).

```lua
if swaEnabled and not swaPending then
    addConfirmAction("|cffffd055SWA|r",
        "|cffffd055SWA? again to confirm|r",
        function() net().LocalSWA() end)
end
```

**Issue F-1**: a human at 8 cards (round 1 trick 1) can press SWA. `Bot.PickSWA` self-rejects via `#hand > 4` (Bot.lua:3871) before R.IsValidSWA even runs; the human flow has no equivalent. The user's reported "ultra-rare 8-card SWA" path per video #35 line 2353 is real — but ALWAYS requires permission AND is mathematically near-impossible to satisfy R.IsValidSWA (would require 4 Aces + 4 Tens + perfect partner alignment). So the practical risk is "user accidentally fires expensive Qaid against own team", not "user exploits". Recommend either (a) mirror the bot's `#hand <= 4` gate at the UI level, OR (b) document that the strict R.IsValidSWA validator IS the gate (currently the "deterministic-or-bust" reading). Source #35 itself does NOT prohibit 8-card SWA; it only says "you must ask permission" and "they would never let it pass". The current code lets the user shoot themselves.

### Step 2 — Net.LocalSWA (Net.lua:2473-2586)

```
LocalSWA()
├── pause / phase / contract / allowSWA gates       # 2474-2477
├── handCount = #(S.s.hand or {})                   # 2486
├── needPerm = WHEREDNGNDB.swaRequiresPermission ~= false  # 2487-2488
├── re-entrancy guard (caller already pending)      # 2496-2498
├── if needPerm:
│   ├── Build S.s.swaRequest with encodedHand + ts + windowSec  # 2502-2520
│   ├── N.SendSWAReq → broadcast MSG_SWA_REQ        # 2521
│   ├── (host-only) auto-accept opponent bots       # 2526-2533
│   ├── (host-only) C_Timer.After 5s with pause re-arm  # 2539-2576
│   └── return
└── (else, never taken — needPerm is true by default)
    ├── N.SendSWA                                   # 2584
    └── (host-only) N.HostResolveSWA               # 2585
```

**Verdict: correct.** The `needPerm` default (≠ false) means EVERY SWA goes through the permission window — confirms reaudit R3's "v0.5.17 routes ALL through permission flow" finding. The ≤3-card "instant claim" path at line 2581-2585 is dead code unless the user explicitly toggles `WHEREDNGNDB.swaRequiresPermission = false`.

**Subtle correctness: the auto-accept loop at 2528-2533 fires for the host's OWN call** because the wire-loopback is dropped by `fromSelf` — without it, `_OnSWAResp` bot bots would never be triggered for a host-self-call, deadlocking the round. The 9th-audit fix comment confirms this. ✓

### Step 3 — Permission flow + 5-sec timer

**Three timer-arming sites** (all use `C_Timer.After(K.SWA_TIMEOUT_SEC, ...)`):

| Site | Lines | Pause re-arm? | Notes |
|---|---|---|---|
| `N.LocalSWA` (host's own call) | 2546-2576 | YES (2552-2569) | `pinnedHand` snapshot prevents staleness if hand mutates after Resolve |
| `N._OnSWAReq` (remote SWA arrives at host) | 2693-2730 | YES (2701-2718) | Decodes wire-supplied `encodedHand` on resolve |
| `MaybeRunBot` bot SWA dispatch | 4059-4067 | NO (early-return on paused — F-2 below) | Only this path skips re-arm |
| `WHEREDNGN.lua` PLAYER_LOGIN restore | 270-292 | YES (resets `req.ts`) | Re-arms host's auto-resolve after /reload |

**Issue F-2 (MEDIUM)**: bot-fired SWA at Net.lua:4059 has:

```lua
C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function()
    if not S.s.isHost then return end
    if S.s.paused then return end                   -- bare early-exit
    local req = S.s.swaRequest
    if not req or req.caller ~= seat then return end
    ...
```

vs. LocalSWA at 2552 which re-arms with a fresh window:

```lua
if S.s.paused then
    local req2 = S.s.swaRequest
    if req2 and req2.caller == mySeat then
        req2.ts = (GetTime and GetTime()) or req2.ts
        if C_Timer and C_Timer.After then
            C_Timer.After(K.SWA_TIMEOUT_SEC or 5, function() ... end)
        end
    end
    return
end
```

A `/pause` during the bot's 5-sec window leaves `swaRequest` populated forever (until the next ApplyStart or HostResolveTakweesh clears it). The user CAN still press Takweesh to break the deadlock, and the next round's ApplyStart wipes swaRequest defensively, so this is "soft-stuck" not "permanently broken" — but it contradicts the rest of the codebase's pattern. **Recommend adding the same re-arm block to MaybeRunBot's bot-SWA timer.**

**5-sec timer is correctly documented as addon-UX** in CLAUDE.md (already amended per R3 reaudit). No source-rule conflict.

### Step 4 — R.IsValidSWA (Rules.lua:383-501)

Deterministic-or-bust adversarial recursion. **No probabilistic shortcut.** Saudi-strict per v0.5.17 design (partner treated adversarially):

```lua
for _, card in ipairs(legal) do
    local nh, ns = applyMove(card)
    if not R.IsValidSWA(callerSeat, nh, contract, ns) then
        return false
    end
end
return true
```

Every legal play of every seat (caller, partner, both opponents) must lead to a winning subtree. Partner adversarial trade-off documented at lines 471-493 (the v0.5.17 design comment).

**Subtle correctness fixes preserved**:
- Line 397-404 (V14 fix): full 4-play trick is resolved BEFORE the caller-empty short-circuit. Without this, if caller plays their last card as the 4th of a trick they LOSE (e.g. opp trumped in), `#hands[caller]==0` would early-return `true`. ✓
- Line 418-420 (v0.5.17 fix): empty-caller-hand short-circuit is gated on `#plays == 0` (between tricks), not just on hand-empty mid-trick. ✓

**Mid-trick SWA (F-5 below)** — verified: the recursion correctly observes partial `plays`; `nextSeat` is computed from `plays[#plays].seat` at line 427. ✓

**Adversarial-partner trade-off** — confirmed over-rejecting for the "two-hand SWA in Hokm" cooperative case from #35 (R3 reaudit's MEDIUM caveat: speaker's "trust your partner will come" framing). This is a known v0.5.17 design choice. Not a v0.10.2 regression.

### Step 5 — N.HostResolveSWA (Net.lua:2862-3073)

**Two branches** keyed on `R.IsValidSWA(callerSeat, hands, c, trickState)` at line 2915.

#### Invalid branch (Net.lua:2920-2987) — Saudi Qaid penalty

Computes `handTotal × mult` (26 Sun / 16 Hokm before div10) to opp + opp's own melds × mult. Belote independent (line 2978-2982). **Caller team's melds are zeroed (line 2951-2952)**:

```lua
local mpA = (callerTeam == "A") and 0 or meldA
local mpB = (callerTeam == "B") and 0 or meldB
```

This is the **v0.10.1 M1 fix** (CHANGELOG line 113-129). Verified: matches `HostResolveTakweesh`'s offender-forfeit semantics (Net.lua:2196-2225). Saudi-strict deterministic-or-bust ✓.

#### Valid branch (Net.lua:2988-3043) — synthetic round

Builds an 8-trick history with caller as winner of every remaining trick, then delegates to `R.ScoreRound`:

```lua
local synth = {}
for _, t in ipairs(S.s.tricks or {}) do synth[#synth + 1] = t end

-- Build remaining plays list (in-flight + every unplayed card)
local remaining = {}
for _, p in ipairs(trickPlays) do remaining[#remaining + 1] = ... end
for seat = 1, 4 do
    for _, card in ipairs(hands[seat] or {}) do
        remaining[#remaining + 1] = { seat = seat, card = card }
    end
end

-- Pack into 4-play tricks, all won by callerSeat
while #synth < 8 and #remaining > 0 do
    local plays = {}
    for j = 1, 4 do
        if #remaining > 0 then plays[j] = table.remove(remaining, 1) end
    end
    synth[#synth + 1] = {
        leadSuit = (plays[1] and C.Suit(plays[1].card)) or "S",
        plays = plays,
        winner = callerSeat,
    }
end

local result = R.ScoreRound(synth, c, S.s.meldsByTeam)
```

**Verdict: correct in spirit**, with one subtle wrinkle that's been seen-and-handled:

- The synthesized tricks have `leadSuit` set to the suit of the 1st remaining card, which is **arbitrary order** — the unplayed cards are iterated in seat order (1..4) without regard to legal play. `R.ScoreRound` ignores `leadSuit` for trick-winner computation (uses `t.winner` directly per line 666 — "team = R.TeamOf(t.winner)") so this works for scoring. But it means the synthetic tricks are NOT a valid Saudi play sequence; they're a scoring shortcut.
- For the **sweep branch** (`R.ScoreRound:712-714`): if EVERY trick (real + synthetic) was won by the caller's team, `trickCount[callerTeam] == 8` triggers `sweepTeam = callerTeam` → AL_KABOOT bonus. **This is correct**: SWA is the caller asserting they win every trick; if that holds and prior tricks were also won by their team, they swept. Saudi convention preserved. ✓
- **Edge edge**: if caller's team has won every prior trick AND the SWA is valid, this triggers AL_KABOOT in the synthesized round. This is the intended outcome — claiming the rest while having taken every prior trick IS the canonical sweep. ✓

### Step 6 — S.ApplyRoundEnd (State.lua:1463-1530)

Applied via `HostResolveSWA` line 3058 with `(addA, addB, totA, totB, sweepTeam, contractMade)`. Standard ApplyRoundEnd semantics — clears turn, sets phase to PHASE_SCORE, fires BALOOT cue when `sweep ~= nil or bidderMade == false`. UI banner picks up via `S.s.swaResult` rendered at UI.lua:3017-3043. ✓

### Step 7 — Round-end / R.ScoreRound

Already covered in step 5 (valid branch reuses ScoreRound). Sweep branch behavior is correctly tied to caller's-team tally of `winner == callerSeat` synthetic tricks.

---

## Specific findings against the prompt's checklist

### Permission flow timing — 5-sec timer

| Property | Status |
|---|---|
| Documented as addon-UX (not Saudi)? | **YES** — CLAUDE.md line 41-46 (post-R3 reaudit) and Constants.lua:274-281 |
| Uses `C_Timer.After`? | **YES** — all 4 timer sites, with explicit fallback on harness path (Net.lua:4068-4072) |
| Pause-aware? | **MIXED** — re-arms in 3/4 sites; bot SWA timer (Net.lua:4059) early-exits without re-arm (**F-2 MEDIUM**) |
| Re-arm on /reload? | **YES** — WHEREDNGN.lua:270-292 fires fresh 5s timer post-restore, sets `req.ts = now` |

### Hand-count gates

| Threshold | Source rule (#35) | Code behavior | Status |
|---|---|---|---|
| ≤3 cards | Instant claim (no permission) | Routed through 5-sec window (`needPerm` always true) — UX choice for visibility | **Acceptable divergence** (R3 reaudit) |
| 4 cards | جلسة-conditional permission | Same 5-sec window | **Correct** (defaults to stricter convention) |
| ≥5 cards | Mandatory permission | Same 5-sec window | **Correct** |
| Code distinguishes 4 vs 5+? | — | **NO** — single `needPerm` branch | **Acceptable** (5+ is never less restrictive than 4) |

The 5+ path is **collapsed to the same flow as 4** — confirmed at Net.lua:2502 `if needPerm then ...`. This is correct because both paths require permission; the 5+ path's "stricter" semantic is "no جلسة auto-permits 5+", and the code's default IS "always require permission".

### Determinism check — R.IsValidSWA over-rejection

The adversarial-partner recursion **does over-reject** for "two-hand SWA in Hokm" cooperative cases (R3 reaudit MEDIUM caveat). #35 line 2814 says "trust your partner will come" — code rejects because partner might play a card that doesn't lead to caller-wins. **Known design trade-off, documented in Rules.lua:471-493.** No new finding here.

### Forfeit semantics post-v0.10.1

Verified at Net.lua:2940-2952:

```lua
-- Saudi Qaid rule (offender melds forfeited).
-- v0.10.1 M1 fix (user-arbitrated): an invalid-SWA call is a Qaid context
-- — the caller (offender) forfeits their team's own declared melds.
local mpA = (callerTeam == "A") and 0 or meldA
local mpB = (callerTeam == "B") and 0 or meldB
```

**Integration with R.ScoreRound**: invalid SWA branch does NOT call `R.ScoreRound` — it computes the penalty directly and calls `S.ApplyRoundEnd` at line 3058. So the "regular contract-fail branch" of ScoreRound is not affected by M1. Confirmed scoping by CHANGELOG v0.10.1 lines 124-129 ("not applied to R.ScoreRound's regular contract-fail branch").

**Integration with `Net.ApplyRoundEnd`**: SWA result struct at line 3048-3052 is set BEFORE ApplyRoundEnd; UI consumes via `S.s.swaResult` for the banner. ✓

### Saudi-strict deterministic-or-bust

Confirmed end-to-end:
- Caller invokes via UI → LocalSWA → permission window → bots auto-accept → 5s timer fires.
- Host calls `R.IsValidSWA(callerSeat, hands, c, trickState)` (Net.lua:2915).
- Returns false → invalid branch: opp wins `handTotal × mult + own melds × mult`, caller's team melds zeroed, Belote independent.
- Returns true → valid branch: synthesized 8-trick history with caller as winner → ScoreRound resolves normally (sweep / made / failed).

Matches video #35 line 2944 ("the other team has the right to qaid you") — **correct**.

### Edge: 8-card SWA round-start

- **UI gate**: NO (F-1 MEDIUM finding above).
- **Bot gate**: YES — `Bot.PickSWA` rejects at `#hand > 4` (Bot.lua:3871). Bot will NEVER fire 8-card SWA.
- **Validation gate**: `R.IsValidSWA` will return false in 99.99%+ of cases — full hand requires deterministic dominance over all 4 seats × 8 cards × adversarial partner. Practical guarantee: invalid SWA → Qaid → caller's team eats `handTotal × mult` + own melds zeroed.

The user's prompt phrases this as "Qaid penalty applies" — verified, that's exactly what happens (Net.lua:2920-2987). The MEDIUM concern is the **UI lets the user shoot themselves** without warning. Rec: mirror Bot's `#hand <= 4` gate.

### Edge: SWA mid-trick

Test path: human plays card 1 of trick 5 (their last suited card), partner plays card 2, opp plays card 3, then human seat clicks SWA (still has cards in hand of other suits). `R.IsValidSWA` is called with `trickState.plays = {p1, p2, p3}` and `nextSeat = (3 % 4) + 1 = 4` (the 4th seat about to play).

Verified at Rules.lua:387-405:
- `#plays == 4` branch (line 397) does NOT trigger.
- Empty-caller-hand short-circuit (line 418) does NOT trigger if caller still has other-suit cards.
- Recursion proceeds with `nextSeat = 4`, building `legal` from seat 4's hand under the partial trick.
- After seat 4's play, full trick is resolved via the `#plays == 4` branch on the next call.

**Verdict: correct mid-trick handling.** ✓

### Bot-side asymmetry — Bot.PickSWA `#hand <= 4`

Confirmed at Bot.lua:3866-3871:

```lua
function Bot.PickSWA(seat)
    if not Bot.IsAdvanced() then return false end
    if S.s.phase ~= K.PHASE_PLAY then return false end
    if not S.s.contract then return false end
    local hand = S.s.hostHands and S.s.hostHands[seat]
    if not hand or #hand == 0 or #hand > 4 then return false end
```

The `#hand > 4` gate is in addition to:
- Tier gate (`Bot.IsAdvanced()`): Basic bots never SWA.
- Validity gate: `R.IsValidSWA` must return true.
- Hokm safety gate (Bot.lua:3906-3935): caller's top trump must beat opp's top trump (defense in depth on top of R.IsValidSWA, per v0.5.21 user-reported safety net).

**Asymmetry vs. humans**:
- Bot caps SWA at 4 cards (mirrors saudi-rules.md threshold for instant claim — bot avoids the 5+ "must ask permission" complexity).
- Bot adds Hokm trump-safety gate not present in human path.
- Human can fire SWA at any hand-count, gated only by R.IsValidSWA's deterministic check.

**Recommendation (NEW)**: document this asymmetry in glossary.md or Bot.lua header. The R3 reaudit treated SWA as a 7-tier "code matches source" item; the bot/human asymmetry was not surfaced. Either:
- (a) Add the `#hand <= 4` UI gate to match the bot's threshold (safer, prevents user-shoots-foot at 5+ cards).
- (b) Document that human path is intentionally permissive — humans at 5+ cards CAN attempt SWA at their own peril (Saudi rule allows it; bot just chooses not to as a safety conservatism).

User's preferred reading isn't clear from the source video — speaker presents 5+ as "always with permission" but doesn't forbid the player from trying.

### Takweesh-on-SWA race condition

Path:
1. Caller fires LocalSWA → `swaRequest` populated, MSG_SWA_REQ broadcast, bots auto-accept, 5s timer armed.
2. Opp clicks Takweesh → LocalTakweesh → `_OnTakweesh`/HostResolveTakweesh fires (Net.lua:2127).
3. HostResolveTakweesh sets `S.s.swaRequest = nil` at line 2144 (50-agent audit fix).
4. HostResolveTakweesh resolves the round (caller's-illegal-play scan); fires `S.ApplyRoundEnd`; phase→SCORE.
5. The 5s SWA timer fires later: `S.s.phase ~= PHASE_PLAY` early-returns (Net.lua:2722). ✓

**No race**, because:
- Phase guard at every timer site (`S.s.phase ~= K.PHASE_PLAY` returns).
- swaRequest nil-check at every timer site.
- HostResolveTakweesh runs synchronously in the same frame as the message receive.

**Subtle wrinkle (F-4 LOW)**: the `_OnSWAResp` handler at Net.lua:2735-2807 may receive a wire response AFTER Takweesh has cleared `swaRequest`. Line 2742-2743 does `if not req or req.caller ~= caller then return end` — so a stale response is safely dropped. ✓

### Pause behavior

| Component | Pause-aware? |
|---|---|
| LocalSWA host-self timer (2546) | YES, re-arms |
| _OnSWAReq remote-receive timer (2693) | YES, re-arms |
| MaybeRunBot bot-fire timer (4059) | NO — silent drop (**F-2 MEDIUM**) |
| WHEREDNGN.lua /reload restore timer (270) | YES |
| OnUpdate banner countdown (UI.lua:1452) | YES — `if S.s.paused then return` (line 1458) |
| renderSWABanner Refresh-driven render (UI.lua:3194) | NO — math drifts during pause (**F-3 LOW**) |
| LocalSWA / LocalSWAResp pause-gate | YES (lines 2474, 2591) |
| _OnSWAReq / _OnSWA pause-gate | YES (implicit via PHASE_PLAY check, but no explicit `if S.s.paused`) |
| HostResolveSWA | NO explicit pause check (only PHASE_PLAY) |

**HostResolveSWA missing explicit pause guard** is interesting. The timer sites that CALL it all check `S.s.paused` first, so the only way to reach a paused HostResolveSWA is via:
1. Direct ≤3-card path at Net.lua:2585 (dead code if needPerm default holds).
2. Permission flow when both opponents accepted before pause.

The 2nd case is a real race: if both opps accept in rapid succession, _OnSWAResp at line 2800-2806 calls HostResolveSWA without checking pause. Practical consequence: an SWA resolves mid-pause. **NOT a hot bug** — the user explicitly accepted; pause only blocks NEW interactions, and the resolution is the same with or without pause. But noting for completeness.

---

## Findings Summary

| ID | Severity | Layer | Finding | Recommendation |
|---|---|---|---|---|
| **F-1** | MEDIUM | UI | No hand-count gate on SWA button (humans can fire at 8 cards) | Mirror Bot's `#hand <= 4` gate at UI.lua:2011 OR document as intentional |
| **F-2** | MEDIUM | Net | Bot SWA timer (Net.lua:4059) doesn't re-arm on pause; other 3 sites do | Add re-arm block matching LocalSWA:2552-2569 |
| **F-3** | LOW | UI | renderSWABanner countdown doesn't freeze on pause (OnUpdate path does) | Add `if S.s.paused then return` early-exit OR don't recompute remain when paused |
| **F-4** | LOW | Net | Takweesh-during-SWA: bot auto-accepts may be partially populated when Takweesh arrives | No code change needed — confirm with a test fixture |
| **F-5** | INFO | Rules | Mid-trick SWA validation correctly handles partial trickState | No action |

---

## Verdict

The end-to-end SWA pipeline is **functionally correct** for the happy path and the Saudi Qaid penalty path. The v0.10.1 forfeit-melds fix is integrated cleanly. The 5-sec timer is consistently treated as addon-UX (not a Saudi rule). The R3 reaudit's MEDIUM caveat about adversarial-partner recursion remains valid but is a known design trade-off, not a v0.10.2 regression.

**Two MEDIUM follow-ups** (F-1 UI hand-count gate, F-2 bot timer pause re-arm) are reasonable v0.10.3 / v0.10.4 closures. **Three LOW notes** (F-3 banner countdown, F-4 Takweesh race, F-5 mid-trick) are confirmation rather than action items.

The "deterministic-or-bust" reading is preserved — failed proof = Qaid against caller — and the integration with HostResolveSWA → R.IsValidSWA → S.ApplyRoundEnd → R.ScoreRound (via synthetic tricks for the valid branch) is internally consistent.

---

## Confidence

**HIGH** on:
- Pipeline structural correctness end-to-end.
- v0.10.1 M1 forfeit semantics integration with HostResolveSWA invalid branch.
- 5-sec timer documented correctly as addon-UX (R3 reaudit confirmed).
- F-1 finding (UI lacks hand-count gate; bot has it).
- F-2 finding (Bot SWA timer asymmetric pause handling).

**MEDIUM** on:
- F-4 race window — not deeply traced through wire-ordering; relies on phase-guard + nil-check defense which is solid in practice.
- Whether F-1 should be a code fix or a documentation clarification — depends on user intent (per #35, 8-card SWA is allowed-but-strongly-discouraged; current UI matches that "allowed" reading).

**LOW / not addressed**:
- Two-handed Hokm SWA cooperative case (R3 MEDIUM caveat — out of scope for this xref).
- Whether the synthetic-trick `leadSuit` in HostResolveSWA's valid branch could affect any downstream consumer beyond R.ScoreRound (didn't trace UI/banner consumers of trick history post-SWA).

---

## Files cross-referenced

- `C:\CLAUDE\WHEREDNGN\UI.lua` — lines 1374-1484 (banner), 1997-2030 (button), 3194-3234 (renderSWABanner), 3015-3043 (result banner).
- `C:\CLAUDE\WHEREDNGN\Net.lua` — lines 2127-2225 (HostResolveTakweesh + swaRequest clear), 2473-2586 (LocalSWA), 2590-2638 (LocalSWAResp), 2640-2733 (_OnSWAReq), 2735-2807 (_OnSWAResp), 2809-2827 (_OnSWA), 2829-2846 (_OnSWAOut), 2862-3073 (HostResolveSWA), 4023-4075 (MaybeRunBot bot-SWA dispatch).
- `C:\CLAUDE\WHEREDNGN\Rules.lua` — lines 355-501 (R.IsValidSWA), 661-960 (R.ScoreRound, sweep branch at 711-723).
- `C:\CLAUDE\WHEREDNGN\State.lua` — lines 110-130 (round-init clears), 220-240 (TRANSIENT_FIELDS — swaRequest NOT transient), 800-823 (ApplyStart clears), 1192-1298 (ApplyPlay), 1415-1441 (SWARemainingPoints), 1463-1530 (ApplyRoundEnd).
- `C:\CLAUDE\WHEREDNGN\Bot.lua` — lines 3854-3938 (Bot.PickSWA, including Hokm trump-safety gate).
- `C:\CLAUDE\WHEREDNGN\Constants.lua` — lines 196-208 (MSG_SWA family), 274-281 (SWA_TIMEOUT_SEC).
- `C:\CLAUDE\WHEREDNGN\WHEREDNGN.lua` — lines 270-292 (PLAYER_LOGIN restore re-arm).
- `C:\CLAUDE\WHEREDNGN\CHANGELOG.md` — v0.10.1 M1 entry (lines 105-145), v0.10.2 entry (lines 1-103).
- `C:\CLAUDE\WHEREDNGN\.swarm_findings\review_v0.10.0\_phase2_xref\reaudit_R3_swa.md` — full naming + mechanism reaudit.
- `C:\CLAUDE\WHEREDNGN\docs\strategy\_transcripts\35_swa_term_detailed_extracted.md` — speaker decisions (videos #35 source-of-truth).
- `C:\CLAUDE\WHEREDNGN\CLAUDE.md` — line 41-46 (CLAUDE.md SWA section, post-R3 amendment).
